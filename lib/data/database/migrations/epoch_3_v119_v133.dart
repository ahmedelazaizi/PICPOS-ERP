part of '../database.dart';

/// Epoch 3 migration steps v119–v133 (pure move out of `epoch_3.dart`;
/// no behaviour change). Called in order by `_migrateEpoch3`.
///
extension Epoch3MigrationsV119ToV133 on AppDatabase {
  Future<void> _migrateEpoch3V119ToV133(Migrator m, int from) async {
    // v119: Smart Sync expansion (remaining static & master tables)
    if (from < 119) {
      await _safeMigrate('v119 sync expansion', () async {
        final tables = [
          'units', 'accounts', 'cost_centers', 'fiscal_years',
          'accounting_periods', 'safes', 'safe_transactions',
          'warehouses', 'branches', 'users', 'stock_movements'
        ];
        for (var t in tables) {
          // 1. Add global_id
          //
          // كان `ADD COLUMN ... TEXT UNIQUE` — صيغة **مرفوضة في SQLite**
          // نهائياً، والخطأ مبلوع هنا فالبلوك كان بيكمّل بصمت والعمود ما
          // بيتعملش، والـbackfill تحته بيفشل بـ`no such column` ويتبلع هو
          // كمان. يعني v119 ما نجحش ولا مرة على أي ترقية.
          // دليل داخلي: v114/v118 في نفس الملف بيستعملوا `ADD COLUMN TEXT`
          // من غير UNIQUE — وde بينجح.
          try { await m.database.customStatement("ALTER TABLE $t ADD COLUMN global_id TEXT"); } catch (e) { debugPrint('[Migration] v119 ADD $t.global_id (safe-skip): $e'); }
          try { await m.database.customStatement("CREATE UNIQUE INDEX IF NOT EXISTS idx_${t}_global_id ON $t(global_id) WHERE global_id IS NOT NULL"); } catch (e) { debugPrint('[Migration] v119 IX $t.global_id (safe-skip): $e'); }
          // 2. Add is_global (for common static data like units/categories)
          try { await m.database.customStatement("ALTER TABLE $t ADD COLUMN is_global INTEGER NOT NULL DEFAULT 0"); } catch (e) { debugPrint('[Migration] v119 ADD $t.is_global (safe-skip): $e'); }
          // 3. Add branch_ids (for scoped data)
          try { await m.database.customStatement("ALTER TABLE $t ADD COLUMN branch_ids TEXT"); } catch (e) { debugPrint('[Migration] v119 ADD $t.branch_ids (safe-skip): $e'); }
          
          // Backfill existing records with unique UUIDs
          final existing = await m.database.customSelect("SELECT id FROM $t WHERE global_id IS NULL OR global_id = ''").get();
          for (final row in existing) {
            final uuid = const Uuid().v4();
            await m.database.customStatement('UPDATE $t SET global_id = ? WHERE id = ?', [uuid, row.data['id']]);
          }
        }
      });
      debugPrint('[Migration] v119: Extended global_id sync coverage applied');
    }

    // v120: PIR Duplicate JE Safety Net — UNIQUE partial index prevents two
    // auto-posted entries for the same (reference_type, reference_id) pair.
    // This is a database-level backstop that complements the TOCTOU transaction
    // fix in accounting_autopost_dao.dart (autoPostCashSale / autoPostCreditSale /
    // autoPostPurchase). Any concurrent caller that races past the in-code guard
    // will receive a UNIQUE constraint violation, which the DAO catches gracefully.
    if (from < 120) {
      await _safeMigrate('v120 journal_entries autopost dedup index', () async {
        await m.database.customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_je_autopost_dedup '
          'ON journal_entries(reference_type, reference_id) '
          'WHERE is_auto_posted = 1',
        );
      });
      debugPrint('[Migration] v120: Duplicate JE UNIQUE partial index created');
    }

    // v121: Backfill default roles for existing installations.
    // Fresh installs get all 5 roles via seedInitialData() → seedRolesAndPermissions().
    // Older databases may only have 'مدير النظام'. This migration ensures the 4
    // remaining system roles exist — using INSERT OR IGNORE so it is fully idempotent.
    if (from < 121) {
      await _safeMigrate('v121 backfill default roles', () async {
        final defaultRoles = [
          ('كاشير', 'البيع السريع فقط'),
          ('مخزني', 'إدارة المخزون والمنتجات'),
          ('محاسب', 'التقارير والخزينة'),
          ('مدير مالي', 'طبقة وصول غير مقيدة مالياً'),
        ];
        for (final r in defaultRoles) {
          await m.database.customStatement(
            "INSERT OR IGNORE INTO roles (name, description, is_system_role, created_at) "
            "VALUES (?, ?, 1, strftime('%s','now'))",
            [r.$1, r.$2],
          );
        }
        debugPrint('[Migration] v121: Default roles backfilled');
      });
    }
    // v122: Region Layer — middle tier between central admin and branches
    if (from < 122) {
      await _safeMigrate('v122 regions table', () async {
        await m.database.customStatement('''
          CREATE TABLE IF NOT EXISTS regions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            address TEXT,
            phone TEXT,
            cost_center_id INTEGER REFERENCES cost_centers(id),
            is_active INTEGER NOT NULL DEFAULT 1,
            global_id TEXT UNIQUE
          )
        ''');
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_regions_active ON regions(is_active)',
        );
      });
      await _safeMigrate('v122 branches.region_id', () async {
        await m.database.customStatement(
          'ALTER TABLE branches ADD COLUMN region_id INTEGER REFERENCES regions(id)',
        );
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_branches_region ON branches(region_id)',
        );
      });
      await _safeMigrate('v122 warehouses.region_id', () async {
        await m.database.customStatement(
          'ALTER TABLE warehouses ADD COLUMN region_id INTEGER REFERENCES regions(id)',
        );
      });
      await _safeMigrate('v122 safes.region_id', () async {
        await m.database.customStatement(
          'ALTER TABLE safes ADD COLUMN region_id INTEGER REFERENCES regions(id)',
        );
      });
      await _safeMigrate('v122 user_region_access', () async {
        await m.database.customStatement('''
          CREATE TABLE IF NOT EXISTS user_region_access (
            user_id INTEGER NOT NULL REFERENCES users(id),
            region_id INTEGER NOT NULL REFERENCES regions(id),
            PRIMARY KEY (user_id, region_id)
          )
        ''');
      });
    }
    // v123: Shift closing method column
    if (from < 123) {
      await _safeMigrate('v123 shifts.closing_method', () async {
        await m.database.customStatement(
          "ALTER TABLE shifts ADD COLUMN closing_method TEXT NOT NULL DEFAULT 'normal'",
        );
      });
    }
    // v124: PIR P0-01 — deletedBy audit column on financial tables
    //        PIR P0-04 — failed_autoposts monitoring table
    if (from < 124) {
      // deletedBy: who performed the soft-delete
      await _safeMigrate('v124 sales_invoices.deleted_by', () async {
        await m.database.customStatement(
          'ALTER TABLE sales_invoices ADD COLUMN deleted_by INTEGER REFERENCES users(id)',
        );
      });
      await _safeMigrate('v124 purchase_invoices.deleted_by', () async {
        await m.database.customStatement(
          'ALTER TABLE purchase_invoices ADD COLUMN deleted_by INTEGER REFERENCES users(id)',
        );
      });
      await _safeMigrate('v124 journal_entries.deleted_by', () async {
        await m.database.customStatement(
          'ALTER TABLE journal_entries ADD COLUMN deleted_by INTEGER REFERENCES users(id)',
        );
      });
      await _safeMigrate('v124 payments.deleted_by', () async {
        await m.database.customStatement(
          'ALTER TABLE payments ADD COLUMN deleted_by INTEGER REFERENCES users(id)',
        );
      });
      // Failed autoposts monitoring table
      await _safeMigrate('v124 failed_autoposts table', () async {
        await m.database.customStatement('''
          CREATE TABLE IF NOT EXISTS failed_autoposts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            invoice_id INTEGER NOT NULL,
            reference_type TEXT NOT NULL,
            error_message TEXT NOT NULL,
            is_resolved INTEGER NOT NULL DEFAULT 0 CHECK (is_resolved IN (0, 1)),
            resolved_by INTEGER REFERENCES users(id),
            resolved_at INTEGER,
            created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
          )
        ''');
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_failed_autoposts_invoice ON failed_autoposts(invoice_id, reference_type)',
        );
      });
      debugPrint('[Migration] v124: deletedBy columns + failed_autoposts table created');
    }

    // v125: Party code + party groups/categories
    if (from < 125) {
      await _safeMigrate('v125 party_groups table', () async {
        await m.database.customStatement('''
          CREATE TABLE IF NOT EXISTS party_groups (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            type TEXT NOT NULL DEFAULT 'both',
            is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
            created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
          )
        ''');
      });
      await _safeMigrate('v125 parties.code', () async {
        await m.database.customStatement(
          'ALTER TABLE parties ADD COLUMN code TEXT',
        );
      });
      await _safeMigrate('v125 parties.group_id', () async {
        await m.database.customStatement(
          'ALTER TABLE parties ADD COLUMN group_id INTEGER REFERENCES party_groups(id)',
        );
      });
      debugPrint('[Migration] v125: party_groups table + parties.code + parties.group_id');
    }

    // v126: Backfill default permissions for non-admin system roles.
    // Previously isSystemRole=true gave ALL permissions (admin bypass) to
    // كاشير, مخزني, محاسب, مدير مالي. Now only مدير النظام gets the bypass,
    // so we must ensure these roles have their intended permissions assigned.
    if (from < 126) {
      await _safeMigrate('v126 backfill cashier default permissions', () async {
        final cashierPerms = ['pos_access', 'pos_hold_order', 'pos_save', 'pos_print', 'pos_shift_close'];
        for (final code in cashierPerms) {
          await m.database.customStatement(
            "INSERT OR IGNORE INTO role_permissions (role_id, permission_id) "
            "SELECT r.id, p.id FROM roles r, permissions p "
            "WHERE r.name = 'كاشير' AND p.code = ?",
            [code],
          );
        }
      });
      await _safeMigrate('v126 backfill stockkeeper default permissions', () async {
        final perms = ['inventory_view', 'inventory_edit', 'products_add', 'products_edit', 'purchases_create'];
        for (final code in perms) {
          await m.database.customStatement(
            "INSERT OR IGNORE INTO role_permissions (role_id, permission_id) "
            "SELECT r.id, p.id FROM roles r, permissions p "
            "WHERE r.name = 'مخزني' AND p.code = ?",
            [code],
          );
        }
      });
      await _safeMigrate('v126 backfill accountant default permissions', () async {
        final perms = ['reports_view', 'treasury_view', 'sales_view', 'purchases_view'];
        for (final code in perms) {
          await m.database.customStatement(
            "INSERT OR IGNORE INTO role_permissions (role_id, permission_id) "
            "SELECT r.id, p.id FROM roles r, permissions p "
            "WHERE r.name = 'محاسب' AND p.code = ?",
            [code],
          );
        }
      });
      await _safeMigrate('v126 backfill financial manager default permissions', () async {
        final perms = ['reports_view', 'treasury_view', 'sales_view', 'purchases_view', 'settings_view', 'audit_view'];
        for (final code in perms) {
          await m.database.customStatement(
            "INSERT OR IGNORE INTO role_permissions (role_id, permission_id) "
            "SELECT r.id, p.id FROM roles r, permissions p "
            "WHERE r.name = 'مدير مالي' AND p.code = ?",
            [code],
          );
        }
      });
      debugPrint('[Migration] v126: backfilled default permissions for system roles');
    }

    // v127: Enrich `party_groups` with business-rule columns (description,
    // default discount/payment terms/price level, notes) plus a placeholder
    // `parent_group_id` for future hierarchical nesting. All new columns are
    // nullable / default-zero so existing rows survive without data.
    if (from < 127) {
      await _safeMigrate('v127 party_groups.description', () async {
        await m.database.customStatement(
          'ALTER TABLE party_groups ADD COLUMN description TEXT',
        );
      });
      await _safeMigrate('v127 party_groups.default_discount', () async {
        await m.database.customStatement(
          'ALTER TABLE party_groups ADD COLUMN default_discount REAL NOT NULL DEFAULT 0',
        );
      });
      await _safeMigrate('v127 party_groups.default_payment_terms', () async {
        await m.database.customStatement(
          'ALTER TABLE party_groups ADD COLUMN default_payment_terms TEXT',
        );
      });
      await _safeMigrate('v127 party_groups.price_level', () async {
        await m.database.customStatement(
          'ALTER TABLE party_groups ADD COLUMN price_level TEXT',
        );
      });
      await _safeMigrate('v127 party_groups.notes', () async {
        await m.database.customStatement(
          'ALTER TABLE party_groups ADD COLUMN notes TEXT',
        );
      });
      await _safeMigrate('v127 party_groups.parent_group_id', () async {
        await m.database.customStatement(
          'ALTER TABLE party_groups ADD COLUMN parent_group_id INTEGER '
          'REFERENCES party_groups(id)',
        );
      });
      debugPrint('[Migration] v127: enriched party_groups with business-rule columns');
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // v128: UUID-First Phase 1 Slice 2 — extend `global_id` to all remaining
    // sync-participating tables. Without a stable cross-install identity,
    // client→server replay can create duplicate rows whenever auto-increment
    // IDs collide. This migration adds `global_id TEXT UNIQUE` + backfills
    // UUID v7 (time-ordered, index-friendly) for every existing row.
    //
    // Covered tables (22): party_groups, purchase_invoice_items,
    // sales_invoice_items, held_orders, held_order_items, purchase_orders,
    // purchase_order_items, sales_orders, sales_order_items,
    // payment_allocations, categories, product_barcodes, product_units,
    // shifts, roles, commercial_papers, currencies, price_lists,
    // price_list_items, quotations, quotation_items, printers.
    // ═══════════════════════════════════════════════════════════════════════════
    if (from < 128) {
      await _safeMigrate('v128 UUID-First Slice 2 — global_id expansion', () async {
        final tables = [
          'party_groups',
          'purchase_invoice_items',
          'sales_invoice_items',
          'held_orders',
          'held_order_items',
          'purchase_orders',
          'purchase_order_items',
          'sales_orders',
          'sales_order_items',
          'payment_allocations',
          'categories',
          'product_barcodes',
          'product_units',
          'shifts',
          'roles',
          'commercial_papers',
          'currencies',
          'price_lists',
          'price_list_items',
          'quotations',
          'quotation_items',
          'printers',
        ];
        for (final t in tables) {
          // 1. Add global_id column (safe-skip if already present).
          //
          // كان `TEXT UNIQUE` — مرفوضة في SQLite، والخطأ مبلوع فالعمود ما
          // كانش بيتعمل على أي من الـ٢٢ جدول. نفس عطل v119 فوق.
          try {
            await m.database.customStatement(
              "ALTER TABLE $t ADD COLUMN global_id TEXT",
            );
          } catch (e) {
            debugPrint('[Migration] v128 ADD $t.global_id (safe-skip): $e');
          }
          try {
            await m.database.customStatement(
              "CREATE UNIQUE INDEX IF NOT EXISTS idx_${t}_global_id "
              "ON $t(global_id) WHERE global_id IS NOT NULL",
            );
          } catch (e) {
            debugPrint('[Migration] v128 IX $t.global_id (safe-skip): $e');
          }

          // 2. Backfill UUID v7 for existing rows missing global_id.
          try {
            final existing = await m.database
                .customSelect(
                  "SELECT id FROM $t WHERE global_id IS NULL OR global_id = ''",
                )
                .get();
            for (final row in existing) {
              await m.database.customStatement(
                'UPDATE $t SET global_id = ? WHERE id = ?',
                [UuidV7.generate(), row.data['id']],
              );
            }
          } catch (e) {
            debugPrint('[Migration] v128 backfill $t.global_id (safe-skip): $e');
          }
        }
      });
      debugPrint('[Migration] v128: global_id added + backfilled across sync tables');
    }
    // v129: P2.1 — Delta sync columns for all 40 sync tables
    // Adds: last_modified_at, deleted_at (safe-skip if exists), origin_client_id, row_version
    // AFTER UPDATE trigger auto-bumps row_version + last_modified_at; WHEN guard prevents recursion
    if (from < 129) {
      final syncTables = [
        'party_groups', 'parties', 'purchase_invoices', 'purchase_invoice_items',
        'sales_invoices', 'sales_invoice_items', 'held_orders', 'held_order_items',
        'purchase_orders', 'purchase_order_items', 'sales_orders', 'sales_order_items',
        'payments', 'payment_allocations',
        'accounts', 'journal_entries', 'cost_centers', 'fiscal_years', 'accounting_periods',
        'roles', 'users',
        'commercial_papers', 'currencies', 'price_lists', 'price_list_items',
        'regions', 'branches', 'warehouses', 'stock_movements',
        'units', 'categories', 'products', 'product_barcodes', 'product_units',
        'quotations', 'quotation_items',
        'safes', 'safe_transactions', 'printers',
        'shifts',
      ];
      for (final t in syncTables) {
        for (final ddl in [
          'ALTER TABLE $t ADD COLUMN last_modified_at INTEGER',
          'ALTER TABLE $t ADD COLUMN deleted_at INTEGER',
          'ALTER TABLE $t ADD COLUMN origin_client_id TEXT',
          'ALTER TABLE $t ADD COLUMN row_version INTEGER NOT NULL DEFAULT 0',
        ]) {
          try {
            await m.database.customStatement(ddl);
          } catch (_) {} // safe-skip: column already exists
        }
        try {
          await m.database.customStatement('''
            CREATE TRIGGER IF NOT EXISTS ${t}_bump_version
            AFTER UPDATE ON $t FOR EACH ROW
            WHEN NEW.row_version = OLD.row_version
            BEGIN
              UPDATE $t SET
                last_modified_at = strftime('%s', 'now'),
                row_version = OLD.row_version + 1
              WHERE id = NEW.id;
            END
          ''');
        } catch (e) {
          debugPrint('[Migration] v129 trigger $t: $e');
        }
      }
      debugPrint('[Migration] v129: delta sync columns added to ${syncTables.length} sync tables');
    }

    // v130: P2.2 — Persistent FK remap table (replaces JSON blob in settings)
    if (from < 130) {
      try {
        await m.database.customStatement('''
          CREATE TABLE IF NOT EXISTS remote_id_mappings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            table_name TEXT NOT NULL,
            local_id INTEGER NOT NULL,
            remote_id INTEGER NOT NULL,
            global_id TEXT,
            created_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
          )
        ''');
        await m.database.customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_remote_id_local ON remote_id_mappings(table_name, local_id);',
        );
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_remote_id_remote ON remote_id_mappings(table_name, remote_id);',
        );
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_remote_id_global ON remote_id_mappings(table_name, global_id);',
        );
        debugPrint('[Migration] v130: remote_id_mappings table created');
      } catch (e) {
        debugPrint('[Migration] v130 remote_id_mappings: $e');
      }
    }

    // v131: ISS-FIN-05 — dedicated adhoc customer columns on sales_invoices
    // Previously these were embedded as text prefixes inside the `notes` field.
    if (from < 131) {
      await _safeMigrate('v131 adhoc_customer_name',
          () => m.database.customStatement('ALTER TABLE sales_invoices ADD COLUMN adhoc_customer_name TEXT'));
      await _safeMigrate('v131 adhoc_customer_phone',
          () => m.database.customStatement('ALTER TABLE sales_invoices ADD COLUMN adhoc_customer_phone TEXT'));
      await _safeMigrate('v131 adhoc_customer_note',
          () => m.database.customStatement('ALTER TABLE sales_invoices ADD COLUMN adhoc_customer_note TEXT'));
      debugPrint('[Migration] v131: adhoc customer columns added to sales_invoices');
    }

    // v132: Multi-client activity log sync — add sync columns to activity_logs
    // so client operations are pushed to the server and appear in the central
    // audit trail (سجل العمليات المركزي).
    if (from < 132) {
      // `ADD COLUMN ... UNIQUE` مرفوضة في SQLite، وكانت بتوصل للـ`rethrow`
      // في `_safeMigrate` فتقتل الإقلاع كله على أي ترقية من إصدار < 132.
      // الصيغة دي (عمود عادي + فهرس فريد جزئي) هي نفس النمط الصح المستعمل
      // في v142/v148/v149 تحت.
      await _safeMigrate('v132 activity_logs.global_id', () async {
        await _safeMigrate(
            'v132 activity_logs.global_id (column)',
            () => m.database.customStatement(
                'ALTER TABLE activity_logs ADD COLUMN global_id TEXT'));
        await m.database.customStatement(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_activity_logs_global_id '
            'ON activity_logs(global_id) WHERE global_id IS NOT NULL');
      });
      await _safeMigrate('v132 activity_logs.origin_client_id',
          () => m.database.customStatement(
              'ALTER TABLE activity_logs ADD COLUMN origin_client_id TEXT'));
      await _safeMigrate('v132 activity_logs.last_modified_at',
          () => m.database.customStatement(
              'ALTER TABLE activity_logs ADD COLUMN last_modified_at INTEGER'));
      await _safeMigrate('v132 idx_activity_logs_global_id',
          () => m.database.customStatement(
              'CREATE INDEX IF NOT EXISTS idx_activity_logs_global_id'
              ' ON activity_logs(global_id)'));
      await _safeMigrate('v132 idx_activity_logs_modified',
          () => m.database.customStatement(
              'CREATE INDEX IF NOT EXISTS idx_activity_logs_modified'
              ' ON activity_logs(last_modified_at)'));
      debugPrint('[Migration] v132: activity_logs sync columns added');
    }

    // v133 (2026-04-28): direct branch_id on invoice tables — eliminates the
    // 2-hop JOIN (Invoice → Warehouse → Branch) for multi-branch reports and
    // filters. Backfilled from warehouses.branch_id so existing rows show up
    // under their actual branch on the new UI columns/filters immediately.
    if (from < 133) {
      await _safeMigrate('v133 sales_invoices.branch_id',
          () => m.database.customStatement(
              'ALTER TABLE sales_invoices ADD COLUMN branch_id INTEGER REFERENCES branches(id)'));
      await _safeMigrate('v133 sales_invoices.branch_id backfill',
          () => m.database.customStatement(
              'UPDATE sales_invoices SET branch_id = '
              '(SELECT branch_id FROM warehouses WHERE warehouses.id = sales_invoices.warehouse_id) '
              'WHERE branch_id IS NULL'));
      await _safeMigrate('v133 idx_sales_invoices_branch',
          () => m.database.customStatement(
              'CREATE INDEX IF NOT EXISTS idx_sales_invoices_branch '
              'ON sales_invoices(branch_id)'));

      await _safeMigrate('v133 purchase_invoices.branch_id',
          () => m.database.customStatement(
              'ALTER TABLE purchase_invoices ADD COLUMN branch_id INTEGER REFERENCES branches(id)'));
      await _safeMigrate('v133 purchase_invoices.branch_id backfill',
          () => m.database.customStatement(
              'UPDATE purchase_invoices SET branch_id = '
              '(SELECT branch_id FROM warehouses WHERE warehouses.id = purchase_invoices.warehouse_id) '
              'WHERE branch_id IS NULL'));
      await _safeMigrate('v133 idx_purchase_invoices_branch',
          () => m.database.customStatement(
              'CREATE INDEX IF NOT EXISTS idx_purchase_invoices_branch '
              'ON purchase_invoices(branch_id)'));
      debugPrint('[Migration] v133: direct branch_id added + backfilled from warehouses');
    }
  }
}
