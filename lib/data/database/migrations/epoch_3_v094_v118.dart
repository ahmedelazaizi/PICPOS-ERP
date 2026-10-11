part of '../database.dart';

/// Epoch 3 migration steps v94–v118 (pure move out of `epoch_3.dart`;
/// no behaviour change). Called in order by `_migrateEpoch3`.
///
extension Epoch3MigrationsV094ToV118 on AppDatabase {
  Future<void> _migrateEpoch3V094ToV118(Migrator m, int from) async {
    // ═══ v94: Cost center integration + order tax fields + employee treasury tracking ═══
    if (from < 94) {
      // 1. PurchaseInvoices: cost center tracking
      try {
        await m.database.customStatement(
          'ALTER TABLE purchase_invoices ADD COLUMN cost_center_id INTEGER REFERENCES cost_centers(id)',
        );
      } catch (e) {
        debugPrint('[Migration] v94 purchase_invoices.cost_center_id: $e');
      }
      // 2. Safes: link to cost center
      try {
        await m.database.customStatement(
          'ALTER TABLE safes ADD COLUMN cost_center_id INTEGER REFERENCES cost_centers(id)',
        );
      } catch (e) {
        debugPrint('[Migration] v94 safes.cost_center_id: $e');
      }
      // 3. SafeTransactions: cost center + employee + disbursement type
      try {
        await m.database.customStatement(
          'ALTER TABLE safe_transactions ADD COLUMN cost_center_id INTEGER REFERENCES cost_centers(id)',
        );
      } catch (e) {
        debugPrint('[Migration] v94 safe_transactions.cost_center_id: $e');
      }
      try {
        await m.database.customStatement(
          'ALTER TABLE safe_transactions ADD COLUMN employee_id INTEGER REFERENCES employees(id)',
        );
      } catch (e) {
        debugPrint('[Migration] v94 safe_transactions.employee_id: $e');
      }
      try {
        await m.database.customStatement(
          'ALTER TABLE safe_transactions ADD COLUMN disbursement_type TEXT',
        );
      } catch (e) {
        debugPrint('[Migration] v94 safe_transactions.disbursement_type: $e');
      }
      // 4. PurchaseOrderItems: tax rate + tax amount
      try {
        await m.database.customStatement(
          'ALTER TABLE purchase_order_items ADD COLUMN tax_rate REAL NOT NULL DEFAULT 0',
        );
      } catch (e) {
        debugPrint('[Migration] v94 purchase_order_items.tax_rate: $e');
      }
      try {
        await m.database.customStatement(
          'ALTER TABLE purchase_order_items ADD COLUMN tax_amount REAL NOT NULL DEFAULT 0',
        );
      } catch (e) {
        debugPrint('[Migration] v94 purchase_order_items.tax_amount: $e');
      }
      // 5. SalesOrderItems: tax rate + tax amount
      try {
        await m.database.customStatement(
          'ALTER TABLE sales_order_items ADD COLUMN tax_rate REAL NOT NULL DEFAULT 0',
        );
      } catch (e) {
        debugPrint('[Migration] v94 sales_order_items.tax_rate: $e');
      }
      try {
        await m.database.customStatement(
          'ALTER TABLE sales_order_items ADD COLUMN tax_amount REAL NOT NULL DEFAULT 0',
        );
      } catch (e) {
        debugPrint('[Migration] v94 sales_order_items.tax_amount: $e');
      }
    }
    // ═══ v95: BOM components — unit conversion factor for manufacturing ═══
    if (from < 95) {
      try {
        await m.database.customStatement(
          'ALTER TABLE bom_components ADD COLUMN quantity_in_base REAL NOT NULL DEFAULT 1.0',
        );
      } catch (e) {
        debugPrint('[Migration] v95 bom_components.quantity_in_base: $e');
      }
    }
    // ═══ v96: Gap audit — missing schema columns across 7 tables ═══
    if (from < 96) {
      final v96Columns = <String>[
        'ALTER TABLE safes ADD COLUMN linked_account_id INTEGER REFERENCES accounts(id)',
        'ALTER TABLE op_expenses ADD COLUMN cost_center_id INTEGER REFERENCES cost_centers(id)',
        'ALTER TABLE employees ADD COLUMN branch_id INTEGER REFERENCES branches(id)',
        'ALTER TABLE sales_orders ADD COLUMN cost_center_id INTEGER REFERENCES cost_centers(id)',
        'ALTER TABLE purchase_orders ADD COLUMN cost_center_id INTEGER REFERENCES cost_centers(id)',
        'ALTER TABLE stock_audits ADD COLUMN warehouse_id INTEGER REFERENCES warehouses(id)',
        'ALTER TABLE inventory_bonds ADD COLUMN cost_center_id INTEGER REFERENCES cost_centers(id)',
      ];
      for (final stmt in v96Columns) {
        try {
          await m.database.customStatement(stmt);
        } catch (e) {
          debugPrint('[Migration] v96: $e');
        }
      }
    }
    // ═══ v97: Expense workflow — status + payment method tracking (U-03, F-12) ═══
    if (from < 97) {
      try {
        await m.database.customStatement(
          "ALTER TABLE op_expenses ADD COLUMN status TEXT NOT NULL DEFAULT 'draft'",
        );
      } catch (e) {
        debugPrint('[Migration] v97 op_expenses.status: $e');
      }
      try {
        await m.database.customStatement(
          "ALTER TABLE op_expenses ADD COLUMN payment_method TEXT NOT NULL DEFAULT 'cash'",
        );
      } catch (e) {
        debugPrint('[Migration] v97 op_expenses.payment_method: $e');
      }
    }
    // ═══ v98: Expense category → GL account code mapping (C-03 audit fix) ═══
    if (from < 98) {
      try {
        await m.database.customStatement(
          "ALTER TABLE op_expense_categories ADD COLUMN account_code TEXT NOT NULL DEFAULT '5299'",
        );
      } catch (e) {
        debugPrint('[Migration] v98 op_expense_categories.account_code: $e');
      }
    }
    // ═══ v99: ISS-16 — 5 missing performance indexes ═══
    if (from < 99) {
      try {
        // 1. Cost center lookups on sales invoices
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_sales_inv_cost_center '
          'ON sales_invoices(cost_center_id)',
        );
        // 2. Cost center lookups on journal entry lines
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_jel_cost_center '
          'ON journal_entry_lines(cost_center_id)',
        );
        // 3. Cost center lookups on purchase invoices
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_purchase_inv_cost_center '
          'ON purchase_invoices(cost_center_id)',
        );
        // 4. Cost center lookups on safe transactions
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_safe_txn_cost_center '
          'ON safe_transactions(cost_center_id)',
        );
        // 5. Product name search index
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_products_name '
          'ON products(name)',
        );
      } catch (e) {
        debugPrint('[Migration] v99 ISS-16 indexes: $e');
      }
    }
    // ═══ v100: Add showInPos column to categories ═══
    if (from < 100) {
      try {
        await m.addColumn(categories, categories.showInPos);
      } catch (e) {
        debugPrint('[Migration] v100 showInPos: $e');
      }
    }
    // ═══ v101: Invoice Designer — section & formula columns ═══
    if (from < 101) {
      try {
        await m.database.customStatement(
          "ALTER TABLE invoice_template_elements ADD COLUMN section TEXT NOT NULL DEFAULT 'body'",
        );
      } catch (e) {
        debugPrint('[Migration] v101 section: $e');
      }
      try {
        await m.database.customStatement(
          'ALTER TABLE invoice_template_elements ADD COLUMN formula TEXT',
        );
      } catch (e) {
        debugPrint('[Migration] v101 formula: $e');
      }
    }
    // ═══ v102: PIR ISS-14 — 5 missing performance indexes ═══
    if (from < 102) {
      final v102Indexes = <String>[
        // 1. Sales invoice items → invoice_id JOIN
        'CREATE INDEX IF NOT EXISTS idx_si_items_invoice_id '
        'ON sales_invoice_items(invoice_id)',
        // 2. Purchase invoice items → invoice_id JOIN
        'CREATE INDEX IF NOT EXISTS idx_pi_items_invoice_id '
        'ON purchase_invoice_items(invoice_id)',
        // 3. Stock movements → product_id lookups
        'CREATE INDEX IF NOT EXISTS idx_stock_movements_product '
        'ON stock_movements(product_id)',
        // 4. Journal entry lines → entry_id aggregation
        'CREATE INDEX IF NOT EXISTS idx_jel_entry_id '
        'ON journal_entry_lines(entry_id)',
        // 5. Safe transactions → date range reports
        'CREATE INDEX IF NOT EXISTS idx_safe_txn_date '
        'ON safe_transactions(transaction_date)',
      ];
      for (final stmt in v102Indexes) {
        try {
          await m.database.customStatement(stmt);
        } catch (e) {
          debugPrint('[Migration] v102 index: $e');
        }
      }
    }
    // v104: Add multi-unit columns to invoice items
    if (from < 104) {
      try {
        await m.addColumn(salesInvoiceItems, salesInvoiceItems.unitName);
        await m.addColumn(salesInvoiceItems, salesInvoiceItems.quantityInBase);
        await m.addColumn(
          purchaseInvoiceItems,
          purchaseInvoiceItems.unitName,
        );
        await m.addColumn(
          purchaseInvoiceItems,
          purchaseInvoiceItems.quantityInBase,
        );
        await seedStandardUnitsIfNotExists();
      } catch (e) {
        debugPrint('[Migration] v104 failed: $e');
      }
    }
    // v105: Multi-branch account mapping — add cost_center_id to account_mappings
    if (from < 105) {
      try {
        // Add cost_center_id column
        await m.database.customStatement(
          'ALTER TABLE account_mappings ADD COLUMN cost_center_id INTEGER REFERENCES cost_centers(id);',
        );
        // Drop old unique index on purpose
        await m.database.customStatement(
          'DROP INDEX IF EXISTS account_mappings_purpose_unique;',
        );
        // Create composite unique index (purpose + cost_center_id)
        // coalesce ensures null cost_center_id maps to 0 for uniqueness
        await m.database.customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_account_mappings_purpose_cc '
          'ON account_mappings(purpose, coalesce(cost_center_id, 0));',
        );
      } catch (e) {
        debugPrint('[Migration] v105 failed: $e');
      }
    }
    // v106: Rename item_id → bom_id in manufacturing_orders (schema drift fix)
    if (from < 106) {
      try {
        // SQLite 3.25.0+ supports ALTER TABLE RENAME COLUMN
        await m.database.customStatement(
          'ALTER TABLE manufacturing_orders RENAME COLUMN item_id TO bom_id;',
        );
      } catch (e) {
        debugPrint(
          '[Migration] v106 rename item_id→bom_id: $e (may already be correct)',
        );
      }
    }
    // v108: Rebuild account_mappings — remove column-level UNIQUE on purpose
    // The original table had UNIQUE on purpose alone, which prevents
    // multi-cost-center mappings. DROP INDEX can't remove column-level
    // constraints, so we must rebuild the table.
    if (from < 108) {
      try {
        await m.database.transaction(() async {
          // 1. Rename existing table
          await m.database.customStatement(
            'ALTER TABLE account_mappings RENAME TO account_mappings_old',
          );
          // 2. Create new table WITHOUT any UNIQUE on purpose
          await m.database.customStatement('''
                CREATE TABLE IF NOT EXISTS account_mappings (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  purpose TEXT NOT NULL,
                  account_id INTEGER NOT NULL REFERENCES accounts(id),
                  cost_center_id INTEGER REFERENCES cost_centers(id),
                  description TEXT,
                  updated_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
                )
              ''');
          // 3. Copy data (de-duplicate by purpose+cost_center_id)
          // NOTE: updated_at is already stored as integer epoch by Drift,
          // using strftime('%s', ...) on an integer causes NULL/failure.
          await m.database.customStatement('''
                INSERT OR IGNORE INTO account_mappings (id, purpose, account_id, cost_center_id, description, updated_at)
                SELECT id, purpose, account_id, cost_center_id, description,
                       CASE WHEN typeof(updated_at) = 'integer' THEN updated_at
                            ELSE CAST(strftime('%s', updated_at) AS INTEGER)
                       END
                FROM account_mappings_old
              ''');
          // 4. Drop old table
          await m.database.customStatement('DROP TABLE account_mappings_old');
          // 5. Create composite unique index
          await m.database.customStatement(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_account_mappings_purpose_cc '
            'ON account_mappings(purpose, coalesce(cost_center_id, 0))',
          );
        });
      } catch (e) {
        debugPrint('[Migration] v108 rebuild account_mappings: $e');
      }
    }
    // v107: Seed manufacturing accounts (Raw Materials, Goods In Transit, WIP)
    if (from < 107) {
      try {
        // Get the parent account ID for Current Assets (code 1100)
        final parentResult = await m.database.customSelect(
          "SELECT id FROM accounts WHERE code = '1100' LIMIT 1",
        ).getSingleOrNull();
        final parentId = parentResult?.data['id'] as int? ?? 2;

        // Insert Raw Materials (1104) if not exists
        await m.database.customStatement(
          "INSERT OR IGNORE INTO accounts (code, name, account_type, parent_id, is_system, balance) "
          "VALUES ('1104', 'مواد خام', 'asset', $parentId, 1, 0.0);",
        );
        // Insert Goods In Transit (1105) if not exists
        await m.database.customStatement(
          "INSERT OR IGNORE INTO accounts (code, name, account_type, parent_id, is_system, balance) "
          "VALUES ('1105', 'بضاعة بالطريق', 'asset', $parentId, 1, 0.0);",
        );
        // Insert WIP / إنتاج تحت التشغيل (1106) if not exists
        await m.database.customStatement(
          "INSERT OR IGNORE INTO accounts (code, name, account_type, parent_id, is_system, balance) "
          "VALUES ('1106', 'إنتاج تحت التشغيل', 'asset', $parentId, 1, 0.0);",
        );
      } catch (e) {
        debugPrint('[Migration] v107 seed manufacturing accounts: $e');
      }
    }
    // v109: Safety net — ensure account_mappings has cost_center_id column
    // Previous migrations (v105/v108) may have failed silently on some DBs,
    // leaving the table without the cost_center_id column.
    if (from < 109) {
      try {
        // Check if cost_center_id column exists by querying PRAGMA
        final cols = await m.database.customSelect(
          "PRAGMA table_info('account_mappings')",
        ).get();
        final hasCostCenterId = cols.any(
          (c) => c.data['name'] == 'cost_center_id',
        );
        if (!hasCostCenterId) {
          debugPrint(
            '[Migration] v109: cost_center_id missing — rebuilding account_mappings',
          );
          await m.database.transaction(() async {
            await m.database.customStatement(
              'ALTER TABLE account_mappings RENAME TO account_mappings_broken',
            );
            await m.database.customStatement('''
                  CREATE TABLE IF NOT EXISTS account_mappings (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    purpose TEXT NOT NULL,
                    account_id INTEGER NOT NULL REFERENCES accounts(id),
                    cost_center_id INTEGER REFERENCES cost_centers(id),
                    description TEXT,
                    updated_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
                  )
                ''');
            await m.database.customStatement('''
                  INSERT OR IGNORE INTO account_mappings (id, purpose, account_id, description, updated_at)
                  SELECT id, purpose, account_id, description,
                         CASE WHEN typeof(updated_at) = 'integer' THEN updated_at
                              ELSE CAST(strftime('%s','now') AS INTEGER)
                         END
                  FROM account_mappings_broken
                ''');
            await m.database.customStatement(
              'DROP TABLE IF EXISTS account_mappings_broken',
            );
          });
        }
        // Ensure composite unique index exists
        await m.database.customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_account_mappings_purpose_cc '
          'ON account_mappings(purpose, coalesce(cost_center_id, 0))',
        );
      } catch (e) {
        debugPrint('[Migration] v109 safety net: $e');
      }
    }

    // v110: Enhanced Chart of Accounts — add nameEn, normalBalance, level, accountNature
    if (from < 110) {
      try {
        try {
          await m.database.customStatement(
            "ALTER TABLE accounts ADD COLUMN account_nature TEXT NOT NULL DEFAULT 'detail'",
          );
        } catch (e) { debugPrint('[Migration] v110 ADD account_nature (safe-skip): $e'); }
        try {
          await m.database.customStatement(
            "ALTER TABLE accounts ADD COLUMN normal_balance TEXT NOT NULL DEFAULT 'debit'",
          );
        } catch (e) { debugPrint('[Migration] v110 ADD normal_balance (safe-skip): $e'); }
        try {
          await m.database.customStatement(
            "ALTER TABLE accounts ADD COLUMN level INTEGER NOT NULL DEFAULT 1",
          );
        } catch (e) { debugPrint('[Migration] v110 ADD level (safe-skip): $e'); }

        // Auto-populate normalBalance for existing accounts based on accountType
        await m.database.customStatement(
          "UPDATE accounts SET normal_balance = 'credit' WHERE account_type IN ('liability', 'equity', 'revenue')",
        );

        // Auto-populate level from parent depth
        await m.database.customStatement(
          "UPDATE accounts SET level = 1 WHERE parent_id IS NULL",
        );
        await m.database.customStatement(
          "UPDATE accounts SET level = 2 WHERE parent_id IN (SELECT id FROM accounts WHERE parent_id IS NULL)",
        );
        await m.database.customStatement(
          "UPDATE accounts SET level = 3 WHERE parent_id IN (SELECT id FROM accounts WHERE level = 2)",
        );
        await m.database.customStatement(
          "UPDATE accounts SET level = 4 WHERE parent_id IN (SELECT id FROM accounts WHERE level = 3)",
        );

        // Mark accounts with children as 'view' (non-postable)
        await m.database.customStatement(
          "UPDATE accounts SET account_nature = 'view' WHERE id IN (SELECT DISTINCT parent_id FROM accounts WHERE parent_id IS NOT NULL)",
        );

        debugPrint('[Migration] v110: Enhanced Chart of Accounts columns added');
      } catch (e) {
        debugPrint('[Migration] v110: $e');
      }
    }

    // v111: PIR Remediation — remaining performance indexes
    if (from < 111) {
      try {
        // Journal entries by reference type/id (for autopost lookups)
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_journal_entries_ref '
          'ON journal_entries(reference_type, reference_id);',
        );
        // Purchase invoices by date
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_purchase_invoices_created '
          'ON purchase_invoices(created_at);',
        );
        // Purchase invoices by supplier
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_purchase_invoices_supplier '
          'ON purchase_invoices(supplier_id);',
        );
        // Safe transactions composite (safe + date)
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_safe_txn_safe_date '
          'ON safe_transactions(safe_id, created_at);',
        );
      } catch (e) {
        debugPrint('[Migration] v111 indexes: $e');
      }
    }

    // v112: PIR Security — Force password change for default admin & new accounts
    if (from < 112) {
      try {
        await m.addColumn(users, users.forcePasswordChange);
        // Force change for default admin if password is still 'admin'
        // Note: Since we don't know the salt here easily for a raw update,
        // we'll just set it for user with id 1 (default admin)
        await m.database.customStatement(
          "UPDATE users SET force_password_change = 1 WHERE id = 1 AND username = 'admin';",
        );
      } catch (e) {
        debugPrint('[Migration] v112 force_password: $e');
      }
    }

    // v113: Invoice Template Designer — add unit, barcode, notes table columns
    if (from < 113) {
      try {
        await m.database.customStatement(
          "ALTER TABLE invoice_table_settings ADD COLUMN show_unit INTEGER NOT NULL DEFAULT 0",
        );
      } catch (e) {
        debugPrint('[Migration] v113 show_unit: $e');
      }
      try {
        await m.database.customStatement(
          "ALTER TABLE invoice_table_settings ADD COLUMN show_barcode INTEGER NOT NULL DEFAULT 0",
        );
      } catch (e) {
        debugPrint('[Migration] v113 show_barcode: $e');
      }
      try {
        await m.database.customStatement(
          "ALTER TABLE invoice_table_settings ADD COLUMN show_notes INTEGER NOT NULL DEFAULT 0",
        );
      } catch (e) {
        debugPrint('[Migration] v113 show_notes: $e');
      }
    }

    // v114: Phase 14 — Add globalId (UUID) to Products and Parties for deterministic sync
    if (from < 114) {
      // Products.globalId
      await _safeMigrate('v114 products.globalId', () async {
        await m.database.customStatement(
          "ALTER TABLE products ADD COLUMN global_id TEXT NOT NULL DEFAULT ''",
        );
        // Backfill existing products with unique UUIDs
        final existingProducts = await m.database.customSelect(
          "SELECT id FROM products WHERE global_id = ''",
        ).get();
        for (final row in existingProducts) {
          final uuid = const Uuid().v4();
          await m.database.customStatement(
            'UPDATE products SET global_id = ? WHERE id = ?',
            [uuid, row.data['id']],
          );
        }
      });

      // Parties.globalId
      await _safeMigrate('v114 parties.globalId', () async {
        await m.database.customStatement(
          "ALTER TABLE parties ADD COLUMN global_id TEXT NOT NULL DEFAULT ''",
        );
        // Backfill existing parties with unique UUIDs
        final existingParties = await m.database.customSelect(
          "SELECT id FROM parties WHERE global_id = ''",
        ).get();
        for (final row in existingParties) {
          final uuid = const Uuid().v4();
          await m.database.customStatement(
            'UPDATE parties SET global_id = ? WHERE id = ?',
            [uuid, row.data['id']],
          );
        }
      });

      debugPrint('[Migration] v114: globalId added to Products (${0}) and Parties');
    }

    // v115: PIR Phase 1 — Performance indexes for branches and cost centers
    if (from < 115) {
      await _safeMigrate('v115 performance indexes', () async {
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_journal_entries_branch ON journal_entries(branch_id, entry_date);',
        );
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_journal_entries_posted ON journal_entries(is_posted, entry_date);',
        );
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_journal_entry_lines_cost_center ON journal_entry_lines(cost_center_id);',
        );
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_stock_movements_branch ON stock_movements(branch_id, created_at);',
        );
      });
      debugPrint('[Migration] v115: Performance indexes added added successfully');
    }
    // v118: Smart Sync Hardening (global_id and branch sharing injection)
    if (from < 118) {
      await _safeMigrate('v118 sync hardening', () async {
        final tables = ['categories', 'products', 'parties', 'sales_invoices', 'purchase_invoices', 'journal_entries'];
        for (var t in tables) {
          // 1. Add global_id
          try { await m.database.customStatement("ALTER TABLE $t ADD COLUMN global_id TEXT NOT NULL DEFAULT ''"); } catch (e) { debugPrint('[Migration] v118 ADD $t.global_id (safe-skip): $e'); }
          // 2. Add is_global
          try { await m.database.customStatement("ALTER TABLE $t ADD COLUMN is_global INTEGER NOT NULL DEFAULT 0"); } catch (e) { debugPrint('[Migration] v118 ADD $t.is_global (safe-skip): $e'); }
          // 3. Add branch_ids
          try { await m.database.customStatement("ALTER TABLE $t ADD COLUMN branch_ids TEXT"); } catch (e) { debugPrint('[Migration] v118 ADD $t.branch_ids (safe-skip): $e'); }

          // Backfill existing records with unique UUIDs
          final existing = await m.database.customSelect("SELECT id FROM $t WHERE global_id = ''").get();
          for (final row in existing) {
            final uuid = const Uuid().v4();
            await m.database.customStatement('UPDATE $t SET global_id = ? WHERE id = ?', [uuid, row.data['id']]);
          }
        }
      });
      debugPrint('[Migration] v118: global_id, is_global, & branch_ids applied to essential sync tables');
    }
  }
}
