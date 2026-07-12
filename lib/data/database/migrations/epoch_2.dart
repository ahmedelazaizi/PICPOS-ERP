part of '../database.dart';

extension Epoch2Migrations on AppDatabase {
  // ═══════════════════════════════════════════════════════════════════════════
  // EPOCH 2: v60 → v80 — Medium-scale features, security, bug fixes
  // ═══════════════════════════════════════════════════════════════════════════
  Future<void> _migrateEpoch2(Migrator m, int from) async {
    // v60: Enhanced sync audit trail
    if (from < 60) {
      try {
        await m.database.customStatement('''
          CREATE TABLE IF NOT EXISTS sync_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            table_name TEXT NOT NULL,
            record_id TEXT NOT NULL,
            operation TEXT NOT NULL,
            payload TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
          )
        ''');
      } catch (e) {
        debugPrint('[Migration] v60 failed (safe-skip): $e');
      }
    }

    // v61: Accounting Periods (FIN-01) — for fiscal period gating
    if (from < 61) {
      try {
        await m.createTable(accountingPeriods);
        // Add status to journal_entries for Draft/Posted workflow
        await m.database.customStatement("ALTER TABLE journal_entries ADD COLUMN status TEXT NOT NULL DEFAULT 'posted'");
      } catch (e) {
        debugPrint('[Migration] v61 failed (safe-skip): $e');
      }
    }
    // v62: Financial period lookup index
    if (from < 62) {
      try {
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_acc_periods_date ON accounting_periods(year, month);',
        );
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
    // v63: Multi-Warehouse (v2) — Warehouse transfers integration
    if (from < 63) {
      try {
        await m.database.customStatement('CREATE TABLE IF NOT EXISTS warehouse_transfers (id INTEGER PRIMARY KEY AUTOINCREMENT)');
        await m.database.customStatement('CREATE TABLE IF NOT EXISTS warehouse_transfer_items (id INTEGER PRIMARY KEY AUTOINCREMENT)');
      } catch (e) {
        debugPrint('[Migration] v63 failed (safe-skip): $e');
      }
    }
    // v64 -> 65: Unit Conversion Support (Inventory)
    if (from < 65) {
      try {
        await m.createTable(productUnits);
        await m.database.customStatement('ALTER TABLE products ADD COLUMN base_unit_id INTEGER');
      } catch (e) {
        debugPrint('[Migration] v65 failed (safe-skip): $e');
      }
    }
    // v66: Product Multi-Barcode support
    if (from < 66) {
      try {
        await m.createTable(productBarcodes);
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
    // v67: Branch Isolation — adding branchId to core documents
    if (from < 67) {
      try {
        await m.database.customStatement('ALTER TABLE sales_invoices ADD COLUMN branch_id INTEGER');
        await m.database.customStatement('ALTER TABLE purchase_invoices ADD COLUMN branch_id INTEGER');
        await m.database.customStatement('ALTER TABLE stock_movements ADD COLUMN branch_id INTEGER');
        await m.database.customStatement('ALTER TABLE inventory_bonds ADD COLUMN branch_id INTEGER');
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_sales_branch ON sales_invoices(branch_id);',
        );
      } catch (e) {
        debugPrint('[Migration] v67 failed (safe-skip): $e');
      }
    }
    // v68: Security — Activity/Audit Logs (PIR §2.1)
    if (from < 68) {
      try {
        await m.createTable(activityLogs);
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
    // v69: Advanced Pricing — Pricing rules & levels
    if (from < 69) {
      try {
        await m.database.customStatement('CREATE TABLE IF NOT EXISTS pricing_rules (id INTEGER PRIMARY KEY AUTOINCREMENT)');
        await m.database.customStatement('ALTER TABLE parties ADD COLUMN pricing_level_id INTEGER');
      } catch (e) {
        debugPrint('[Migration] v69 failed (safe-skip): $e');
      }
    }

    // v70: Product Modifiers & Extras (Restaurant/POS)
    if (from < 70) {
      try {
        await m.database.customStatement('''
              CREATE TABLE IF NOT EXISTS modifier_groups (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                min_selection INTEGER NOT NULL DEFAULT 0,
                max_selection INTEGER NOT NULL DEFAULT 1,
                is_active INTEGER NOT NULL DEFAULT 1
              )
            ''');
        await m.database.customStatement('''
              CREATE TABLE IF NOT EXISTS modifier_items (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                group_id INTEGER NOT NULL REFERENCES modifier_groups(id) ON DELETE CASCADE,
                name TEXT NOT NULL,
                extra_price REAL NOT NULL DEFAULT 0,
                is_default INTEGER NOT NULL DEFAULT 0,
                is_active INTEGER NOT NULL DEFAULT 1,
                sort_order INTEGER NOT NULL DEFAULT 0
              )
            ''');
        await m.database.customStatement('''
              CREATE TABLE IF NOT EXISTS product_modifier_groups (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
                modifier_group_id INTEGER NOT NULL REFERENCES modifier_groups(id) ON DELETE CASCADE,
                sort_order INTEGER NOT NULL DEFAULT 0,
                UNIQUE(product_id, modifier_group_id)
              )
            ''');
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_modifier_items_group ON modifier_items(group_id);',
        );
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_product_modifier_groups_product ON product_modifier_groups(product_id);',
        );
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
    // v71: Click transfer safe (#18)
    if (from < 71) {
      try {
        await seedClickSafeIfNotExists();
      } catch (e) {
        debugPrint('[Migration] v71 failed: $e');
      }
    }

    // (v103 parties.account_id add MOVED to _migrateEpoch3 — B-MIG-1: this
    // method is skipped for from>=81, so the block never ran for v81-v102 DBs.)
    // v72: click_paid column for split payments (#18)
    if (from < 72) {
      try {
        await m.database.customStatement(
          'ALTER TABLE sales_invoices ADD COLUMN click_paid REAL NOT NULL DEFAULT 0',
        );
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
    // v73: PIR — Performance indexes for newer tables
    if (from < 73) {
      try {
        // Purchase orders
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_purchase_orders_supplier ON purchase_orders(supplier_id);',
        );
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_purchase_orders_status ON purchase_orders(status);',
        );
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_purchase_order_items_order ON purchase_order_items(order_id);',
        );
        // HR: Performance reviews
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_performance_reviews_employee ON performance_reviews(employee_id);',
        );
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_performance_goals_review ON performance_goals(review_id);',
        );
        // HR: Employee contracts
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_employee_contracts_employee ON employee_contracts(employee_id);',
        );
        // Warehouse prices (per-warehouse pricing
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_warehouse_prices_lookup ON warehouse_prices(product_id, warehouse_id);',
        );
        // HR: Leave requests & overtime
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_leave_requests_employee ON leave_requests(employee_id);',
        );
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_overtime_records_employee ON overtime_records(employee_id);',
        );
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
    // v74: R-28 — Add userId to stock_movements for audit trail
    if (from < 74) {
      try {
        await m.database.customStatement(
          'ALTER TABLE stock_movements ADD COLUMN user_id INTEGER REFERENCES users(id)',
        );
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
    // v75: N3 — User branch/warehouse access control tables
    if (from < 75) {
      try {
        await m.createTable(userBranchAccess);
        await m.createTable(userWarehouseAccess);
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
    // v76: Link cost centers to branches, warehouses, and fixed assets
    if (from < 76) {
      try {
        await m.database.customStatement(
          'ALTER TABLE branches ADD COLUMN cost_center_id INTEGER REFERENCES cost_centers(id)',
        );
        await m.database.customStatement(
          'ALTER TABLE warehouses ADD COLUMN cost_center_id INTEGER REFERENCES cost_centers(id)',
        );
        await m.database.customStatement(
          'ALTER TABLE fixed_assets ADD COLUMN cost_center_id INTEGER REFERENCES cost_centers(id)',
        );
      } catch (e) {
        debugPrint('[Migration] $e');
      }
    }
    // v77: Add isHiddenFromEntries to accounts + Sales Orders tables
    if (from < 77) {
      try {
        await m.database.customStatement(
          'ALTER TABLE accounts ADD COLUMN is_hidden_from_entries INTEGER NOT NULL DEFAULT 0',
        );
      } catch (e) {
        debugPrint('[Migration] v77-accounts failed: $e');
      }
      try {
        await m.createTable(salesOrders);
        await m.createTable(salesOrderItems);
      } catch (e) {
        debugPrint('[Migration] v77-orders failed: $e');
      }
      try {
        await m.database.customStatement(
          'ALTER TABLE safes ADD COLUMN bank_name TEXT',
        );
        await m.database.customStatement(
          'ALTER TABLE safes ADD COLUMN account_number TEXT',
        );
      } catch (e) {
        debugPrint('[Migration] v77-safes failed: $e');
      }
      // Seed sales/purchase order permissions
      try {
        await seedV77Permissions();
      } catch (e) {
        debugPrint('[Migration] seedV77Permissions: $e');
      }
    }
    // v78: Independent Payments table + PurchaseInvoices.isLocked + Accounts indexes
    if (from < 78) {
      try {
        await m.createTable(payments);
        await m.createTable(paymentAllocations);
      } catch (e) {
        debugPrint('[Migration] v78 create payments tables: $e');
      }
      try {
        await m.database.customStatement(
          'ALTER TABLE purchase_invoices ADD COLUMN is_locked INTEGER NOT NULL DEFAULT 0',
        );
      } catch (e) {
        debugPrint('[Migration] v78 purchase_invoices.isLocked: $e');
      }
      // Accounts indexes (created by Drift annotations for new installs;
      // for upgrades we create them manually)
      try {
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_accounts_code ON accounts (code)',
        );
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_accounts_type ON accounts (account_type)',
        );
      } catch (e) {
        debugPrint('[Migration] v78 accounts indexes: $e');
      }
    }
    // v79: S02 — Invoice integrity hash for tamper detection
    if (from < 79) {
      try {
        await m.database.customStatement(
          'ALTER TABLE sales_invoices ADD COLUMN integrity_hash TEXT',
        );
      } catch (e) {
        debugPrint('[Migration] v79 sales integrity_hash: $e');
      }
      try {
        await m.database.customStatement(
          'ALTER TABLE purchase_invoices ADD COLUMN integrity_hash TEXT',
        );
      } catch (e) {
        debugPrint('[Migration] v79 purchase integrity_hash: $e');
      }
    }
    // v80: F-DISCOUNT — Settlement discount field in safe transactions
    if (from < 80) {
      try {
        await m.database.customStatement(
          'ALTER TABLE safe_transactions ADD COLUMN discount REAL NOT NULL DEFAULT 0',
        );
      } catch (e) {
        debugPrint('[Migration] v80 safe_transactions.discount: $e');
      }
    }
  } // end _migrateEpoch2
}
