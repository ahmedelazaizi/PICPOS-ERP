part of '../database.dart';

extension Epoch3Migrations on AppDatabase {
  // ═══════════════════════════════════════════════════════════════════════════
  // EPOCH 3: v81 → v111 — Enterprise, advanced features, latest PIR
  // ═══════════════════════════════════════════════════════════════════════════
  Future<void> _migrateEpoch3(Migrator m, int from) async {
    // v103: Task 10 — Link Parties to GL Accounts.
    // B-MIG-1: MOVED here from _migrateEpoch2, which runOnUpgrade only calls
    // when `from < 81`. A DB upgrading from v81-v102 skipped epoch 2 entirely
    // and never got parties.account_id. Epoch 3 always runs, so gating on
    // `from < 103` here covers every upgrade path. (ensureSchemaDefaults also
    // re-adds it on every boot as defense-in-depth.)
    if (from < 103) {
      await _safeMigrate(
        'v103 parties.account_id',
        () => m.database.customStatement(
          'ALTER TABLE parties ADD COLUMN account_id INTEGER REFERENCES accounts(id)',
        ),
      );
    }
    // v81: F-10 — E-invoice immutable audit trail
    if (from < 81) {
      try {
        await m.database.customStatement('''
              CREATE TABLE IF NOT EXISTS e_invoice_status_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                submission_id INTEGER NOT NULL REFERENCES e_invoice_submissions(id),
                old_status TEXT,
                new_status TEXT NOT NULL,
                changed_by TEXT,
                notes TEXT,
                changed_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
              )
            ''');
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_einv_status_log_submission ON e_invoice_status_log(submission_id);',
        );
      } catch (e) {
        debugPrint('[Migration] v81 e_invoice_status_log: $e');
      }
    }
    // v82: F-15/F-16 — Maker-Checker approval + Period reopen audit
    if (from < 82) {
      try {
        // Journal entry approval (Maker-Checker)
        await m.database.customStatement(
          "ALTER TABLE journal_entries ADD COLUMN status TEXT NOT NULL DEFAULT 'posted'",
        );
        await m.database.customStatement(
          'ALTER TABLE journal_entries ADD COLUMN approved_by INTEGER REFERENCES users(id)',
        );
        await m.database.customStatement(
          'ALTER TABLE journal_entries ADD COLUMN approved_at INTEGER',
        );
        // Period reopen audit
        await m.database.customStatement(
          'ALTER TABLE accounting_periods ADD COLUMN reopen_reason TEXT',
        );
        await m.database.customStatement(
          'ALTER TABLE accounting_periods ADD COLUMN reopened_by INTEGER',
        );
        await m.database.customStatement(
          'ALTER TABLE accounting_periods ADD COLUMN reopened_at INTEGER',
        );
      } catch (e) {
        debugPrint('[Migration] v82 maker-checker: $e');
      }
    }
    // v83: Performance optimization — indexes + period_account_summaries
    if (from < 83) {
      try {
        // Period account summaries for fast trial balance
        await m.database.customStatement('''
              CREATE TABLE IF NOT EXISTS period_account_summaries (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                account_id INTEGER NOT NULL REFERENCES accounts(id),
                year INTEGER NOT NULL,
                month INTEGER NOT NULL,
                total_debit REAL NOT NULL DEFAULT 0,
                total_credit REAL NOT NULL DEFAULT 0,
                net_balance REAL NOT NULL DEFAULT 0,
                updated_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
                UNIQUE(account_id, year, month)
              )
            ''');
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_period_summary_lookup ON period_account_summaries(account_id, year, month);',
        );
        // Composite index for report queries (account + date range)
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_jel_account_date ON journal_entry_lines(account_id, entry_id);',
        );
        // Sales invoice performance indexes
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_sales_inv_date ON sales_invoices(invoice_date);',
        );
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_sales_inv_branch ON sales_invoices(branch_id);',
        );
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_sales_inv_shift ON sales_invoices(shift_id);',
        );
        // Stock movements performance
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_stock_movements_product ON stock_movements(product_id, movement_date);',
        );
        // Bank reconciliation tables
        await m.database.customStatement('''
              CREATE TABLE IF NOT EXISTS bank_statement_lines (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                bank_account_id INTEGER NOT NULL REFERENCES accounts(id),
                transaction_date INTEGER NOT NULL,
                reference TEXT,
                description TEXT,
                debit_amount REAL NOT NULL DEFAULT 0,
                credit_amount REAL NOT NULL DEFAULT 0,
                running_balance REAL NOT NULL DEFAULT 0,
                is_matched INTEGER NOT NULL DEFAULT 0,
                matched_journal_line_id INTEGER,
                match_type TEXT,
                import_batch TEXT,
                created_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
              )
            ''');
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_bank_stmt_date ON bank_statement_lines(transaction_date);',
        );
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_bank_stmt_account ON bank_statement_lines(bank_account_id);',
        );
        await m.database.customStatement('''
              CREATE TABLE IF NOT EXISTS bank_reconciliations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                bank_account_id INTEGER NOT NULL REFERENCES accounts(id),
                period_start INTEGER NOT NULL,
                period_end INTEGER NOT NULL,
                statement_balance REAL NOT NULL,
                book_balance REAL NOT NULL DEFAULT 0,
                difference REAL NOT NULL DEFAULT 0,
                total_matched INTEGER NOT NULL DEFAULT 0,
                total_unmatched INTEGER NOT NULL DEFAULT 0,
                status TEXT NOT NULL DEFAULT 'draft',
                prepared_by INTEGER,
                completed_at INTEGER,
                created_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
              )
            ''');
      } catch (e) {
        debugPrint('[Migration] v83 performance+bank_recon: $e');
      }
    }

    // ═══ v84: Enterprise tables (budgets, deferred, approvals, SOD) ═══
    if (from < 84) {
      try {
        await m.database.customStatement('''
              CREATE TABLE IF NOT EXISTS budgets (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                fiscal_year_id INTEGER NOT NULL REFERENCES fiscal_years(id),
                account_id INTEGER NOT NULL REFERENCES accounts(id),
                cost_center_id INTEGER REFERENCES cost_centers(id),
                name TEXT,
                annual_amount REAL NOT NULL DEFAULT 0,
                distribution_method TEXT NOT NULL DEFAULT 'equal',
                status TEXT NOT NULL DEFAULT 'draft',
                approved_by INTEGER REFERENCES users(id),
                approved_at INTEGER,
                created_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
              )
            ''');
        await m.database.customStatement('''
              CREATE TABLE IF NOT EXISTS budget_lines (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                budget_id INTEGER NOT NULL REFERENCES budgets(id),
                month INTEGER NOT NULL,
                planned_amount REAL NOT NULL DEFAULT 0,
                actual_amount REAL NOT NULL DEFAULT 0,
                variance REAL NOT NULL DEFAULT 0,
                notes TEXT
              )
            ''');
        await m.database.customStatement('''
              CREATE TABLE IF NOT EXISTS deferred_schedules (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                type TEXT NOT NULL,
                description TEXT NOT NULL,
                total_amount REAL NOT NULL,
                recognized_amount REAL NOT NULL DEFAULT 0,
                remaining_amount REAL NOT NULL DEFAULT 0,
                source_account_id INTEGER NOT NULL REFERENCES accounts(id),
                target_account_id INTEGER NOT NULL REFERENCES accounts(id),
                start_date INTEGER NOT NULL,
                end_date INTEGER NOT NULL,
                total_periods INTEGER NOT NULL,
                completed_periods INTEGER NOT NULL DEFAULT 0,
                frequency TEXT NOT NULL DEFAULT 'monthly',
                status TEXT NOT NULL DEFAULT 'active',
                reference_id INTEGER,
                reference_type TEXT,
                created_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
              )
            ''');
        await m.database.customStatement('''
              CREATE TABLE IF NOT EXISTS deferred_entries (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                schedule_id INTEGER NOT NULL REFERENCES deferred_schedules(id),
                period_number INTEGER NOT NULL,
                recognition_date INTEGER NOT NULL,
                amount REAL NOT NULL,
                journal_entry_id INTEGER REFERENCES journal_entries(id),
                is_posted INTEGER NOT NULL DEFAULT 0,
                posted_at INTEGER
              )
            ''');
        await m.database.customStatement('''
              CREATE TABLE IF NOT EXISTS approval_workflows (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                entity_type TEXT NOT NULL,
                amount_threshold REAL NOT NULL DEFAULT 0,
                required_levels INTEGER NOT NULL DEFAULT 2,
                is_active INTEGER NOT NULL DEFAULT 1,
                created_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
              )
            ''');
        await m.database.customStatement('''
              CREATE TABLE IF NOT EXISTS approval_steps (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                workflow_id INTEGER NOT NULL REFERENCES approval_workflows(id),
                step_order INTEGER NOT NULL,
                step_name TEXT NOT NULL,
                role_id INTEGER REFERENCES roles(id),
                user_id INTEGER REFERENCES users(id),
                can_reject INTEGER NOT NULL DEFAULT 1
              )
            ''');
        await m.database.customStatement('''
              CREATE TABLE IF NOT EXISTS approval_requests (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                workflow_id INTEGER NOT NULL REFERENCES approval_workflows(id),
                entity_type TEXT NOT NULL,
                entity_id INTEGER NOT NULL,
                amount REAL NOT NULL DEFAULT 0,
                current_step INTEGER NOT NULL DEFAULT 1,
                status TEXT NOT NULL DEFAULT 'pending',
                requested_by INTEGER NOT NULL REFERENCES users(id),
                notes TEXT,
                created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
                completed_at INTEGER
              )
            ''');
        await m.database.customStatement('''
              CREATE TABLE IF NOT EXISTS approval_decisions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                request_id INTEGER NOT NULL REFERENCES approval_requests(id),
                step_id INTEGER NOT NULL REFERENCES approval_steps(id),
                decided_by INTEGER NOT NULL REFERENCES users(id),
                decision TEXT NOT NULL,
                comments TEXT,
                decided_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
              )
            ''');
        await m.database.customStatement('''
              CREATE TABLE IF NOT EXISTS sod_conflicts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                permission1 TEXT NOT NULL,
                permission2 TEXT NOT NULL,
                conflict_type TEXT NOT NULL DEFAULT 'hard',
                description TEXT NOT NULL,
                is_active INTEGER NOT NULL DEFAULT 1
              )
            ''');
        await m.database.customStatement('''
              CREATE TABLE IF NOT EXISTS sod_violations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                conflict_id INTEGER NOT NULL REFERENCES sod_conflicts(id),
                user_id INTEGER NOT NULL REFERENCES users(id),
                role_id INTEGER REFERENCES roles(id),
                detected_action TEXT NOT NULL,
                was_blocked INTEGER NOT NULL DEFAULT 0,
                override_reason TEXT,
                overridden_by INTEGER REFERENCES users(id),
                detected_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
              )
            ''');
        // Indexes
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_budget_year ON budgets(fiscal_year_id);',
        );
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_budget_line_month ON budget_lines(budget_id, month);',
        );
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_deferred_type ON deferred_schedules(type);',
        );
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_approval_request_entity ON approval_requests(entity_type, entity_id);',
        );
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_approval_request_status ON approval_requests(status);',
        );
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_sod_violation_user ON sod_violations(user_id);',
        );
        // Add multi-currency columns to journal_entries
        try {
          await m.database.customStatement(
            'ALTER TABLE journal_entries ADD COLUMN currency_id INTEGER REFERENCES currencies(id);',
          );
        } catch (e) { debugPrint('[Migration] v84 ADD currency_id (safe-skip): $e'); }
        try {
          await m.database.customStatement(
            'ALTER TABLE journal_entries ADD COLUMN exchange_rate REAL NOT NULL DEFAULT 1.0;',
          );
        } catch (e) { debugPrint('[Migration] v84 ADD exchange_rate (safe-skip): $e'); }
        try {
          await m.database.customStatement(
            'ALTER TABLE journal_entries ADD COLUMN cost_center_id INTEGER REFERENCES cost_centers(id);',
          );
        } catch (e) { debugPrint('[Migration] v84 ADD cost_center_id (safe-skip): $e'); }
      } catch (e) {
        debugPrint('[Migration] v84 enterprise: $e');
      }
    }

    // ═══ v85: Phase 9 Enterprise tables ═══
    if (from < 85) {
      try {
        await m.database.customStatement('''
              CREATE TABLE IF NOT EXISTS entities (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                code TEXT NOT NULL,
                type TEXT NOT NULL DEFAULT 'subsidiary',
                parent_entity_id INTEGER REFERENCES entities(id),
                ownership_pct REAL NOT NULL DEFAULT 100,
                currency_id INTEGER REFERENCES currencies(id),
                is_active INTEGER NOT NULL DEFAULT 1,
                created_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
              )
            ''');
        await m.database.customStatement('''
              CREATE TABLE IF NOT EXISTS entity_mappings (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                entity_id INTEGER NOT NULL REFERENCES entities(id),
                cost_center_id INTEGER REFERENCES cost_centers(id),
                branch_id INTEGER REFERENCES branches(id)
              )
            ''');
        await m.database.customStatement('''
              CREATE TABLE IF NOT EXISTS intercompany_transactions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                from_entity_id INTEGER NOT NULL REFERENCES entities(id),
                to_entity_id INTEGER NOT NULL REFERENCES entities(id),
                transaction_type TEXT NOT NULL,
                amount REAL NOT NULL,
                currency_id INTEGER REFERENCES currencies(id),
                exchange_rate REAL NOT NULL DEFAULT 1.0,
                from_journal_id INTEGER REFERENCES journal_entries(id),
                to_journal_id INTEGER REFERENCES journal_entries(id),
                status TEXT NOT NULL DEFAULT 'pending',
                description TEXT,
                transaction_date INTEGER NOT NULL,
                created_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
              )
            ''');
        await m.database.customStatement('''
              CREATE TABLE IF NOT EXISTS restatements (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                reason TEXT NOT NULL,
                description TEXT NOT NULL,
                fiscal_year_id INTEGER NOT NULL REFERENCES fiscal_years(id),
                status TEXT NOT NULL DEFAULT 'draft',
                created_by INTEGER NOT NULL REFERENCES users(id),
                approved_by INTEGER REFERENCES users(id),
                applied_at INTEGER,
                created_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
              )
            ''');
        await m.database.customStatement('''
              CREATE TABLE IF NOT EXISTS restatement_lines (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                restatement_id INTEGER NOT NULL REFERENCES restatements(id),
                account_id INTEGER NOT NULL REFERENCES accounts(id),
                original_debit REAL NOT NULL DEFAULT 0,
                original_credit REAL NOT NULL DEFAULT 0,
                adjusted_debit REAL NOT NULL DEFAULT 0,
                adjusted_credit REAL NOT NULL DEFAULT 0,
                notes TEXT
              )
            ''');
        await m.database.customStatement('''
              CREATE TABLE IF NOT EXISTS compliance_checks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                category TEXT NOT NULL,
                check_name TEXT NOT NULL,
                description TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'pending',
                details TEXT,
                score REAL NOT NULL DEFAULT 0,
                last_checked_at INTEGER,
                created_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
              )
            ''');
        // Indexes
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_interco_entities ON intercompany_transactions(from_entity_id, to_entity_id);',
        );
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_entity_mapping ON entity_mappings(entity_id);',
        );
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_restatement_year ON restatements(fiscal_year_id);',
        );
      } catch (e) {
        debugPrint('[Migration] v85 enterprise-adv: $e');
      }
    }

    // ═══ v86: Phase 2 - Stock Requisitions ═══
    if (from < 86) {
      try {
        await m.createTable(stockRequisitions);
        await m.createTable(stockRequisitionItems);
      } catch (e) {
        debugPrint('[Migration] v86 stock requisitions: $e');
      }
    }

    // v87: Journal Entry Templates
    if (from < 87) {
      try {
        await m.createTable(journalEntryTemplates);
        await m.createTable(journalEntryTemplateLines);
      } catch (e) {
        debugPrint('[Migration] v87 journal templates: $e');
      }
    }
    // Migration v88: Phase C7 — Field-Level Audit Logging
    if (from < 88) {
      try {
        await m.createTable(fieldAuditLogs);
      } catch (e) {
        debugPrint('[Migration] v88 field audit logs: $e');
      }
    }
    // Migration v89: Phase C3 — Dynamic Approval Engine columns
    if (from < 89) {
      try {
        await m.addColumn(approvalWorkflows, approvalWorkflows.conditionRules);
        await m.addColumn(
          approvalWorkflows,
          approvalWorkflows.escalationHours,
        );
        await m.addColumn(
          approvalWorkflows,
          approvalWorkflows.autoApproveBelow,
        );
      } catch (e) {
        debugPrint('[Migration] v89 approval engine: $e');
      }
    }
    // Migration v90: Phase C2 Landed Cost + C4 Cycle Counting
    if (from < 90) {
      try {
        await m.createTable(cycleCountPlans);
        await m.createTable(cycleCountTasks);
        await m.createTable(cycleCountItems);
        await m.createTable(landedCostSheets);
        await m.createTable(landedCostItems);
        await m.createTable(landedCostAllocations);
      } catch (e) {
        debugPrint('[Migration] v90 cycle count + landed cost: $e');
      }
    }
    // Migration v91: Phase C1 API Keys + C5 Report Builder
    if (from < 91) {
      try {
        await m.createTable(apiKeys);
        await m.createTable(customReports);
        await m.createTable(savedReportRuns);
      } catch (e) {
        debugPrint('[Migration] v91 api keys + reports: $e');
      }
    }
    // Migration v92: Phase 0 Resilience — Ledger Cascades (FIN-02)
    if (from < 92) {
      try {
        await m.database.transaction(() async {
          // 1. Rename existing table
          await m.database.customStatement(
            'ALTER TABLE journal_entry_lines RENAME TO journal_entry_lines_old',
          );

          // 2. Create new table with updated constraints (JournalEntryLines code modified to include cascade)
          await m.createTable(journalEntryLines);

          // 3. Migrate data
          await m.database.customStatement('''
                INSERT INTO journal_entry_lines (id, entry_id, account_id, debit, credit, description, cost_center_id)
                SELECT id, entry_id, account_id, debit, credit, description, cost_center_id
                FROM journal_entry_lines_old
              ''');

          // 4. Drop old table
          await m.database.customStatement('DROP TABLE journal_entry_lines_old');
        });
      } catch (e) {
        debugPrint('[Migration] v92 ledger cascades: $e');
      }
    }
    // ═══ v93: PIR Phase 1 — Composite performance indexes ═══
    if (from < 93) {
      try {
        // IX-01: Journal entry lines by account+entry (ledger queries)
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_jel_account_entry ON journal_entry_lines(account_id, entry_id);',
        );
        // IX-02: Stock movements composite (inventory reports)
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_stock_mv_prod_wh_date ON stock_movements(product_id, warehouse_id, created_at);',
        );
        // IX-03: Sales invoices by date+warehouse (daily reports)
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_sales_inv_date_wh ON sales_invoices(invoice_date, warehouse_id);',
        );
        // IX-04: Safe transactions by safe+date (treasury reports)
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_safe_txn_safe_date ON safe_transactions(safe_id, created_at);',
        );
        // IX-05: Activity logs by entity (audit trail lookups)
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_activity_entity ON activity_logs(entity_type, entity_id);',
        );
      } catch (e) {
        debugPrint('[Migration] v93 composite indexes: $e');
      }
    }
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

    // v134 (2026-04-28): branch code for invoice number prefixing.
    // Auto-derive from name (first 3 chars uppercased, spaces stripped) when
    // not set, so existing branches get a sensible default like "FAR" for
    // "فرع رئيسي". Admin can later override via the branch management UI.
    if (from < 134) {
      await _safeMigrate('v134 branches.code',
          () => m.database.customStatement(
              'ALTER TABLE branches ADD COLUMN code TEXT'));
      await _safeMigrate('v134 branches.code backfill',
          () => m.database.customStatement(
              "UPDATE branches SET code = UPPER(SUBSTR(REPLACE(name,' ',''), 1, 3)) "
              "WHERE code IS NULL OR code = ''"));
      debugPrint('[Migration] v134: branches.code added + backfilled');
    }
    // v135: M8 — add branch_id to op_expenses for branch-scoped expense reporting
    if (from < 135) {
      await _safeMigrate('v135 op_expenses.branch_id',
          () => m.database.customStatement(
              'ALTER TABLE op_expenses ADD COLUMN branch_id INTEGER REFERENCES branches(id)'));
      debugPrint('[Migration] v135: op_expenses.branch_id added');
    }
    // v136: M4 — add cost_center_id to parties for branch+cost-center assignment
    if (from < 136) {
      await _safeMigrate('v136 parties.cost_center_id',
          () => m.database.customStatement(
              'ALTER TABLE parties ADD COLUMN cost_center_id INTEGER REFERENCES cost_centers(id)'));
      debugPrint('[Migration] v136: parties.cost_center_id added');
    }
    // v137: M6 — add branch_ids + is_global to offers for branch-targeted promotions
    if (from < 137) {
      await _safeMigrate('v137 offers.branch_ids',
          () => m.database.customStatement(
              'ALTER TABLE offers ADD COLUMN branch_ids TEXT'));
      await _safeMigrate('v137 offers.is_global',
          () => m.database.customStatement(
              "ALTER TABLE offers ADD COLUMN is_global INTEGER NOT NULL DEFAULT 1"));
      debugPrint('[Migration] v137: offers.branch_ids + is_global added');
    }
    // v138: Issue 2 — products.created_on_server (server-canonical lock flag)
    //       Issue 18 cleanup — activity_logs.branch_id (SQL-level filter)
    //
    // Default 1 ("server-canonical") for existing product rows is the safe
    // backfill: every product on a client DB at migration time arrived via
    // a server pull, so treating it as server-canonical preserves prior
    // behaviour. Going forward, postProduct on the server stamps 0 when
    // the request comes from a client API call.
    //
    // activity_logs.branch_id is nullable so historical rows (no branch
    // recorded) keep working; ActivityLogger stamps it on new writes.
    if (from < 138) {
      await _safeMigrate('v138 products.created_on_server',
          () => m.database.customStatement(
              'ALTER TABLE products ADD COLUMN created_on_server INTEGER NOT NULL DEFAULT 1'));
      await _safeMigrate('v138 activity_logs.branch_id',
          () => m.database.customStatement(
              'ALTER TABLE activity_logs ADD COLUMN branch_id INTEGER REFERENCES branches(id)'));
      debugPrint('[Migration] v138: products.created_on_server + activity_logs.branch_id added');
    }

    // v139 — Phase 5A.9 (Issue 5). Additive only: seed two settings rows
    // used by the new server-side branch scope work shipped in this phase.
    //   * `client_branch_scope_v5_migrated` — false until the user runs the
    //     "تنظيف بيانات الفروع الأخرى" action from settings (5A.4). Lets us
    //     show the dry-run prompt only on the first launch after upgrade
    //     and never again once the cleanup has happened.
    //   * `server_branch_filter_enabled` — feature flag (G7). True after
    //     upgrade. Setting it to false at runtime makes /api/sync/pull
    //     ignore the `branch_id` parameter and revert to the pre-Phase-5
    //     behaviour without redeploy.
    // Both use INSERT OR IGNORE so a second run of the migration is a
    // no-op, and existing user-set values (e.g. someone manually flipped
    // the flag) survive the upgrade.
    if (from < 139) {
      await _safeMigrate('v139 client_branch_scope_v5_migrated seed',
          () => m.database.customStatement(
              "INSERT OR IGNORE INTO settings(key, value) VALUES('client_branch_scope_v5_migrated', 'false')"));
      await _safeMigrate('v139 server_branch_filter_enabled seed',
          () => m.database.customStatement(
              "INSERT OR IGNORE INTO settings(key, value) VALUES('server_branch_filter_enabled', 'true')"));
      debugPrint('[Migration] v139: Phase 5A branch-scope settings seeded');
    }

    // v140 — Phase 6 (T1). Branch-isolation feature flag.
    //   `client_pulls_transactional_enabled` — when 'false' (the default),
    //   a client device skips Tier 3 of fullSync (sales, purchases, journals,
    //   safe_transactions, shifts, …) and treats itself as a self-contained
    //   branch ledger. Pushes via outbox are unaffected; the server still
    //   gets every write tagged with branch_id. Set to 'true' to revert to
    //   pre-Phase-6 behaviour without redeploy. Server mode reads but does
    //   not act on this flag (the gate in SyncService checks `isClient`
    //   first), so the seeded value is fine for both modes.
    if (from < 140) {
      await _safeMigrate('v140 client_pulls_transactional_enabled seed',
          () => m.database.customStatement(
              "INSERT OR IGNORE INTO settings(key, value) VALUES('client_pulls_transactional_enabled', 'false')"));
      debugPrint('[Migration] v140: client_pulls_transactional_enabled seeded (false)');
    }

    // v142 (Feature 004 — Multi-Branch Governance, US1). FixedAssets gains
    // `global_id` (UUIDv7 sync identity) and `linked_account_id` (per-asset
    // Chart-of-Accounts sub-account FK). Both are nullable for legacy rows;
    // the DAO populates them atomically on every new fixed asset going
    // forward. Note v141 is reserved for the in-flight Phase 7 T1 stash
    // (safe_transactions.branch_id) — leaving the gap is intentional.
    if (from < 142) {
      await _safeMigrate('v142 fixed_assets.linked_account_id',
          () => m.database.customStatement(
              'ALTER TABLE fixed_assets ADD COLUMN linked_account_id INTEGER REFERENCES accounts(id)'));
      await _safeMigrate('v142 fixed_assets.linked_account_id index',
          () => m.database.customStatement(
              'CREATE INDEX IF NOT EXISTS idx_fixed_assets_linked_account ON fixed_assets(linked_account_id)'));
      await _safeMigrate('v142 fixed_assets.global_id',
          () => m.database.customStatement(
              'ALTER TABLE fixed_assets ADD COLUMN global_id TEXT'));
      await _safeMigrate('v142 fixed_assets.global_id unique index',
          () => m.database.customStatement(
              'CREATE UNIQUE INDEX IF NOT EXISTS idx_fixed_assets_global_id ON fixed_assets(global_id) WHERE global_id IS NOT NULL'));
      debugPrint('[Migration] v142: fixed_assets.linked_account_id + global_id added');
    }
    // v143 (Feature 005, 2026-05-03): Re-align party sub-account parents
    // to the seeded codes `1121` / `2111`. Pre-005 the constants in
    // PartyDao referenced `1201` / `2101`, codes that were never added to
    // seedChartOfAccounts(). On installs that exercised the party-creation
    // flow before this migration, those phantom parents were created at
    // runtime as orphan roots holding a parallel set of sub-accounts.
    //
    // Migration steps:
    //   1. If the seeded `1121` exists AND a runtime `1201` exists, re-
    //      parent every child of `1201` onto `1121` then delete `1201`.
    //   2. Same flip for `2101` → `2111`.
    //   3. Best-effort: rows that can't be migrated (FK conflicts) are
    //      logged and left in place. The chart will then show both parents
    //      side by side until the user resolves the leftover manually.
    //
    // Idempotent: running twice on a clean install is a no-op because the
    // SELECT for the orphan parent returns null.
    if (from < 143) {
      Future<void> realignParent(String oldCode, String newCode) async {
        await _safeMigrate('v143 realign $oldCode → $newCode', () async {
          // Boolean literal pinned to SQLite syntax. The migration runs on
          // the client (SQLite). Postgres deployments pick up the seeded
          // chart fresh, so the orphan-cleanup branch never triggers.
          const boolTrue = '1';

          // Lookup both accounts. If either is missing, skip.
          final oldRow = await m.database.customSelect(
            'SELECT id FROM accounts WHERE code = ? LIMIT 1',
            variables: [Variable<String>(oldCode)],
          ).getSingleOrNull();
          if (oldRow == null) return;
          final newRow = await m.database.customSelect(
            'SELECT id FROM accounts WHERE code = ? LIMIT 1',
            variables: [Variable<String>(newCode)],
          ).getSingleOrNull();
          if (newRow == null) {
            debugPrint('[Migration] v143 skip $oldCode → $newCode: '
                'seeded $newCode missing (chart not seeded yet)');
            return;
          }

          final oldId = oldRow.data['id'] as int;
          final newId = newRow.data['id'] as int;
          if (oldId == newId) return;

          // Re-parent every child of the orphan onto the seeded parent.
          await m.database.customStatement(
            'UPDATE accounts SET parent_id = ? WHERE parent_id = ?',
            [newId, oldId],
          );

          // Delete the orphan IF it now has no children AND no JE lines
          // reference it directly. Anything else is a developer-only
          // edge case; leave it in place + log.
          final residualChildren = await m.database.customSelect(
            'SELECT COUNT(*) AS c FROM accounts WHERE parent_id = ?',
            variables: [Variable<int>(oldId)],
          ).getSingle();
          final residualLines = await m.database.customSelect(
            'SELECT COUNT(*) AS c FROM journal_entry_lines WHERE account_id = ?',
            variables: [Variable<int>(oldId)],
          ).getSingle();
          final children = (residualChildren.data['c'] as num).toInt();
          final lines = (residualLines.data['c'] as num).toInt();
          if (children == 0 && lines == 0) {
            await m.database.customStatement(
              'DELETE FROM accounts WHERE id = ?',
              [oldId],
            );
            debugPrint(
                '[Migration] v143: dropped orphan account $oldCode (id=$oldId)');
          } else {
            // Mark the orphan inactive + system-protected so the user
            // sees it greyed out in the COA UI but can't delete it
            // accidentally — it still anchors any historical JE lines.
            await m.database.customStatement(
              'UPDATE accounts SET is_active = $boolTrue, is_system = $boolTrue '
              'WHERE id = ?',
              [oldId],
            );
            debugPrint('[Migration] v143: kept orphan $oldCode (id=$oldId) — '
                'residualChildren=$children residualLines=$lines');
          }
        });
      }

      await realignParent('1201', '1121');
      await realignParent('2101', '2111');
      debugPrint('[Migration] v143: party sub-account parent realignment complete');
    }
    // v144 (Feature 005 Phase 8, 2026-05-03): cleanup duplicate safe-linked
    // accounts that some users created via the manual COA dialog before
    // realising the modern atomic createSafeWithLinkedAccount() helper
    // already produces them with a canonical `111-XXXXX` (dashed, 5-digit)
    // code. The legacy duplicates show up as same-name siblings under
    // either parent `111` or `1110` with a no-dash compact format like
    // `11101`, `11102`, `111001`, etc. Symptom in production:
    //   111-00001  صندوق نقد الادارة   ← canonical, linked from safes.linked_account_id
    //   11101      صندوق نقد الادارة   ← orphan duplicate, never referenced by FKs
    //
    // Migration steps:
    //   1. For every safe with a non-null `linked_account_id`, look up the
    //      canonical account.
    //   2. Find any OTHER account under the same parent that shares the
    //      safe's name AND has no rows in `journal_entry_lines`.
    //   3. Soft-delete (mark inactive + system) the orphan rather than
    //      hard-deleting; keeps a paper trail and preserves any sync
    //      history. The COA UI hides inactive system accounts by default.
    //
    // No-op on fresh installs (no duplicates exist).
    if (from < 144) {
      await _safeMigrate('v144 dedupe orphan safe accounts', () async {
        final dialect = m.database.executor.dialect;
        final isPg = dialect == SqlDialect.postgres;
        final boolFalse = isPg ? 'FALSE' : '0';
        final boolTrue = isPg ? 'TRUE' : '1';

        // Pull every safe + its canonical linked account in one round-trip.
        final pairs = await m.database.customSelect(
          'SELECT s.id AS safe_id, s.name AS safe_name, '
          's.linked_account_id AS linked_id, '
          'a.parent_id AS parent_id '
          'FROM safes s '
          'JOIN accounts a ON a.id = s.linked_account_id '
          'WHERE s.linked_account_id IS NOT NULL',
        ).get();

        var dropped = 0;
        for (final row in pairs) {
          final safeName = row.data['safe_name'] as String?;
          final linkedId = row.data['linked_id'] as int?;
          final parentId = row.data['parent_id'] as int?;
          if (safeName == null || linkedId == null || parentId == null) {
            continue;
          }

          // Find sibling accounts (same parent) that share the safe's
          // name but are NOT the canonical linked one.
          final siblings = await m.database.customSelect(
            'SELECT id, code FROM accounts '
            'WHERE parent_id = ? AND name = ? AND id <> ? AND is_active = $boolTrue',
            variables: [
              Variable<int>(parentId),
              Variable<String>(safeName),
              Variable<int>(linkedId),
            ],
          ).get();

          for (final sib in siblings) {
            final orphanId = sib.data['id'] as int;
            // Don't touch orphans that have JE lines — those carry
            // historical data and silently hiding them would break audit.
            final lineCount = await m.database.customSelect(
              'SELECT COUNT(*) AS c FROM journal_entry_lines '
              'WHERE account_id = ?',
              variables: [Variable<int>(orphanId)],
            ).getSingle();
            final hasLines = (lineCount.data['c'] as num).toInt() > 0;
            if (hasLines) {
              debugPrint(
                  '[Migration] v144 keep orphan #$orphanId (${sib.data['code']}) — has JE lines');
              continue;
            }

            await m.database.customStatement(
              'UPDATE accounts SET is_active = $boolFalse, '
              "name = name || ' [مكرر — مُؤرشف v144]' "
              'WHERE id = ?',
              [orphanId],
            );
            dropped++;
            debugPrint(
                '[Migration] v144 archived orphan #$orphanId code=${sib.data['code']} name="$safeName"');
          }
        }
        debugPrint(
            '[Migration] v144 complete — archived $dropped duplicate safe accounts');
      });
    }

    // ── v145: Spec 008 / FR-001 — add `branch_id` to `shifts` table ──
    //
    // Multi-branch users (admin / financial manager with user_branch_access
    // rows for >1 branch) had no way to record WHICH branch a shift was
    // opened on. The close-time logic fell back to `getUserBranchId(userId)`
    // which returns the FIRST user_branch_access row — closing a shift on
    // Branch B incorrectly zeroed Branch A's safes.
    //
    // The new column is nullable so legacy `shifts` rows (created before
    // this migration) keep working: `closeShiftWithAudit` reads
    // `shift.branchId` first and only falls back to `getUserBranchId` when
    // the column is null.
    if (from < 145) {
      await _safeMigrate('v145 shifts.branch_id (Spec 008)', () async {
        await m.addColumn(shifts, shifts.branchId);
        debugPrint('[Migration] v145 added shifts.branch_id (NULLABLE)');
      });
    }

    // ── v146: Feature 009 — Auto-Deplete BOM on Sale + POS Terminals ──
    //
    // Phase 2 (foundational) of Feature 009. Four additive changes, all
    // safe with default values that preserve legacy behavior:
    //
    //   1. bill_of_materials.auto_deplete_on_sale (BOOL, default 0)
    //      Enables the new at-sale deduction path. Existing BOMs keep the
    //      manual-production behavior because default = false (FR-002,
    //      FR-031, FR-032).
    //
    //   2. bill_of_materials.depletion_policy (TEXT, default
    //      'prefer_finished_stock')
    //      Per RD-1 — when on-hand finished stock exists, deduct it first
    //      and only auto-deplete the residual. Settable to
    //      'always_auto_deplete' per BOM.
    //
    //   3. sale_bom_consumptions (NEW append-only table, FR-028)
    //      Logs every raw-material deduction caused by an auto-deplete sale,
    //      freezing unit_cost_at_sale at deduction time so returns reverse
    //      at original cost (FR-021). Sync = appendOnly (Constitution III).
    //
    //   4. pos_terminals (NEW master-data table, FR-034) +
    //      shifts.pos_terminal_id (NULLABLE column, FR-035)
    //      Foundation for per-terminal stock-shortage policy override
    //      (FR-017). Each device gets a stable device_id (UUIDv7 in
    //      flutter_secure_storage); shifts opened from the device populate
    //      pos_terminal_id automatically. Pre-migration shifts keep NULL
    //      (Constitution I — Behavior Preservation).
    if (from < 146) {
      await _safeMigrate(
        'v146 BOM auto-deplete + POS terminals (Feature 009)',
        () async {
          // 1+2: BOM columns
          await m.addColumn(billOfMaterials, billOfMaterials.autoDepleteOnSale);
          await m.addColumn(billOfMaterials, billOfMaterials.depletionPolicy);
          // 3: consumption log (append-only)
          await m.createTable(saleBomConsumptions);
          // 4a: POS terminal registry
          await m.createTable(posTerminals);
          // 4b: shift -> terminal link
          await m.addColumn(shifts, shifts.posTerminalId);
          debugPrint(
              '[Migration] v146 BOM auto-deplete + POS terminals OK');
        },
      );
    }

    // ═════════════════════════════════════════════════════════════════════
    // v147 — Quality hardening pass (2026-05-12)
    //
    // Adds the **performance indexes** that were declared via @TableIndex
    // annotations on fresh installs but never backfilled into upgraded
    // databases. Audit (May 12) flagged these as missing for installs that
    // shipped before the corresponding feature work landed:
    //
    //   - journal_entries.fiscal_year_id  → period-close report scans
    //   - cost_centers.parent_id          → hierarchical roll-up reports
    //   - activity_logs.branch_id         → per-branch audit filter
    //   - parties (is_active, deleted_at) → list screens with soft-delete
    //
    // (idx_journal_entry_lines_cost_center, idx_journal_entries_branch,
    // idx_journal_entries_ref were already backfilled in v111/v115 so we
    // don't re-add them here.)
    //
    // Why no ALTER TABLE ADD FK: SQLite can't add FK constraints to an
    // existing table without a full rebuild — too risky on production
    // 100MB+ databases. The Drift schema already declares the constraints
    // for new installs; the application layer (orchestrators + dual-write
    // pattern in ENGINEERING_GUIDELINES.md R4) enforces referential integrity on legacy
    // rows going forward.
    //
    // Wrapped in a single transaction for atomicity (lesson from v143/v144
    // audit feedback — partial index creation could leave query planner
    // confused mid-migration). `IF NOT EXISTS` keeps it idempotent.
    // ═════════════════════════════════════════════════════════════════════
    if (from < 147) {
      await _safeMigrate(
        'v147 quality hardening: missing FK indexes',
        () async {
          await m.database.transaction(() async {
            await m.database.customStatement(
              'CREATE INDEX IF NOT EXISTS idx_journal_entries_fiscal '
              'ON journal_entries(fiscal_year_id) '
              'WHERE fiscal_year_id IS NOT NULL;',
            );
            await m.database.customStatement(
              'CREATE INDEX IF NOT EXISTS idx_cost_centers_parent '
              'ON cost_centers(parent_id) '
              'WHERE parent_id IS NOT NULL;',
            );
            await m.database.customStatement(
              'CREATE INDEX IF NOT EXISTS idx_activity_logs_branch '
              'ON activity_logs(branch_id) '
              'WHERE branch_id IS NOT NULL;',
            );
            await m.database.customStatement(
              'CREATE INDEX IF NOT EXISTS idx_parties_active '
              'ON parties(is_active, deleted_at) '
              'WHERE deleted_at IS NULL;',
            );
          });
          debugPrint('[Migration] v147 quality-hardening indexes OK');
        },
      );
    }

    // ═════════════════════════════════════════════════════════════════════
    // v148 — Spec 129 F4: caller-minted globalId on inventory_bonds so
    // mirror local insert + server-side insert agree on identity. Without
    // this column, retried `submitInventoryBond` calls produce duplicate
    // bond rows on the server because the dedup target doesn't exist.
    // ═════════════════════════════════════════════════════════════════════
    if (from < 148) {
      await _safeMigrate('v148 inventory_bonds.global_id', () async {
        try {
          await m.database.customStatement(
            'ALTER TABLE inventory_bonds ADD COLUMN global_id TEXT',
          );
        } catch (e) {
          debugPrint('[Migration] v148 ADD inventory_bonds.global_id (safe-skip): $e');
        }
        try {
          await m.database.customStatement(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_inventory_bonds_global_id '
            'ON inventory_bonds(global_id) WHERE global_id IS NOT NULL',
          );
        } catch (e) {
          debugPrint('[Migration] v148 CREATE UNIQUE INDEX idx_inventory_bonds_global_id (safe-skip): $e');
        }
        debugPrint('[Migration] v148 inventory_bonds.global_id OK');
      });

      // Spec 129 F6 / FR-601..606 — is_system_default flag on 6 master-data
      // tables (5 standalone + parties for the 3 seeded delivery companies).
      // Backfill marks the earliest-id row matching each canonical seeded
      // name (Q1 tiebreaker per spec clarification 2026-05-25). User-renamed
      // rows leave the flag false; the boot self-heal gates on the flag
      // instead of "is this name missing?", so renames now survive restart.
      await _safeMigrate('v148 is_system_default columns + backfill', () async {
        // 1. Add the column on each of the 5 standalone master-data tables.
        for (final table in const [
          'branches', 'warehouses', 'safes', 'units', 'categories',
        ]) {
          try {
            await m.database.customStatement(
              'ALTER TABLE $table ADD COLUMN is_system_default INTEGER NOT NULL DEFAULT 0',
            );
          } catch (e) {
            debugPrint('[Migration] v148 ADD $table.is_system_default (safe-skip): $e');
          }
        }
        // parties already has lots of rows on production installs; same shape.
        try {
          await m.database.customStatement(
            'ALTER TABLE parties ADD COLUMN is_system_default INTEGER NOT NULL DEFAULT 0',
          );
        } catch (e) {
          debugPrint('[Migration] v148 ADD parties.is_system_default (safe-skip): $e');
        }

        // 2. Backfill: mark earliest-id row matching each canonical seeded
        //    name. Canonical names mirror the actual database_seeder.dart
        //    inserts verbatim (data-model.md §1.2 had stale aspirational
        //    names; the seeder is the ground truth — see Spec 129 commit log
        //    + user confirmation 2026-05-25 that delivery companies are
        //    طلبات / كريم / اشيائي).
        const standaloneCanonicals = <String, List<String>>{
          'branches':   ['الفرع الرئيسي'],
          'warehouses': ['المخزن الرئيسي'],
          'safes':      ['صندوق الكاشير', 'الحساب البنكي', 'صندوق تحويل كليك'],
          'units':      ['قطعة', 'كيلو', 'علبة', 'كرتونة'],
          'categories': ['عام'],
        };
        for (final entry in standaloneCanonicals.entries) {
          final table = entry.key;
          for (final name in entry.value) {
            try {
              await m.database.customStatement(
                'UPDATE $table SET is_system_default = 1 '
                'WHERE id = (SELECT MIN(id) FROM $table WHERE name = ?)',
                [name],
              );
            } catch (e) {
              debugPrint('[Migration] v148 backfill $table name="$name" (safe-skip): $e');
            }
          }
        }

        // parties — only the 3 seeded delivery companies get the flag.
        // Filtered by is_delivery_company=true so a customer who happens
        // to be named 'طلبات' isn't accidentally promoted.
        for (final name in const ['طلبات', 'كريم', 'اشيائي']) {
          try {
            await m.database.customStatement(
              'UPDATE parties SET is_system_default = 1 '
              'WHERE id = (SELECT MIN(id) FROM parties '
              '            WHERE name = ? AND is_delivery_company = 1)',
              [name],
            );
          } catch (e) {
            debugPrint('[Migration] v148 backfill parties name="$name" (safe-skip): $e');
          }
        }

        debugPrint('[Migration] v148 is_system_default columns + backfill OK');
      });
    }

    // ═════════════════════════════════════════════════════════════════════
    // v149 — Spec 148 (S-ISSUE): stock_requisitions gains a caller-minted
    // global_id (for future cross-node sync dedup, mirroring inventory_bonds)
    // and fulfilled_by_transfer_id (audit link to the transfer bond produced
    // when the requisition is approved). Both nullable; no item-table change.
    // ═════════════════════════════════════════════════════════════════════
    if (from < 149) {
      await _safeMigrate('v149 stock_requisitions.global_id + fulfilled_by_transfer_id', () async {
        try {
          await m.database.customStatement(
            'ALTER TABLE stock_requisitions ADD COLUMN global_id TEXT',
          );
        } catch (e) {
          debugPrint('[Migration] v149 ADD stock_requisitions.global_id (safe-skip): $e');
        }
        try {
          await m.database.customStatement(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_stock_requisitions_global_id '
            'ON stock_requisitions(global_id) WHERE global_id IS NOT NULL',
          );
        } catch (e) {
          debugPrint('[Migration] v149 CREATE UNIQUE INDEX idx_stock_requisitions_global_id (safe-skip): $e');
        }
        try {
          await m.database.customStatement(
            'ALTER TABLE stock_requisitions ADD COLUMN fulfilled_by_transfer_id INTEGER',
          );
        } catch (e) {
          debugPrint('[Migration] v149 ADD stock_requisitions.fulfilled_by_transfer_id (safe-skip): $e');
        }
        debugPrint('[Migration] v149 stock_requisitions sync + fulfilment columns OK');
      });
    }

    // ═════════════════════════════════════════════════════════════════════
    // v150 — Spec 151 (return-key fix). The RETURN JE re-key means multiple
    // partial returns of ONE invoice now share (reference_type, reference_id):
    // both are keyed on the originating invoice id, with per-event uniqueness
    // carried by journal_entries.global_id. The v120 idx_je_autopost_dedup
    // UNIQUE index — created ONLY in the v120 upgrade block — would reject the
    // 2nd partial return and roll the whole return transaction back on any
    // v120-upgraded DB. Drop + recreate it exempting the multi-JE reference
    // types (see kCreateJeAutopostDedupIndexSql), then backfill historical
    // hash-keyed return JEs onto their originating invoice id so the cancel /
    // edit reverse queries (which now match `referenceId == invoice.id`) find
    // them instead of double-posting (purchase) / reversing nothing (sales).
    // ═════════════════════════════════════════════════════════════════════
    if (from < 150) {
      await _safeMigrate('v150 return-exempt autopost dedup index', () async {
        // (a) Index recreate — CRITICAL. The OLD non-exempted index MUST be
        // dropped BEFORE the backfill re-keys return JEs onto shared invoice
        // ids, or the backfill would itself trip the old UNIQUE constraint.
        // A genuine failure here rethrows via _safeMigrate → boot fails loud.
        await m.database
            .customStatement('DROP INDEX IF EXISTS $kJeAutopostDedupIndexName');
        await m.database.customStatement(kCreateJeAutopostDedupIndexSql);

        // (b) Backfill — BEST-EFFORT. Historical return JEs carry
        // referenceId = hash(invoiceId + amount); re-key them to the
        // originating invoice id parsed from the description. Wrapped in its own
        // try/catch so a backfill hiccup never rolls back the critical index
        // recreate above (unmatched rows keep the hash — acceptable, logged).
        try {
          const marker = 'فاتورة '; // literal token that precedes the number

          // Invoice-number extraction: the substring AFTER the 'فاتورة '
          // marker to end-of-description, matched WHOLE (=, never LIKE) to
          // invoice_number. Using the whole tail — not LIKE '%…%' — is exactly
          // what avoids the F-04 collision where editing "12" also swept "120".
          String extractNo(String col) =>
              "substr($col, instr($col, '$marker') + length('$marker'))";

          // Re-key only rows whose extracted number resolves to EXACTLY ONE
          // invoice (COUNT = 1). Ambiguous/unmatched rows are left untouched.
          // Idempotent: re-running resolves to the same invoice id.
          Future<void> backfill(String refType, String invTable) async {
            await m.database.customStatement('''
              UPDATE journal_entries
              SET reference_id = (
                SELECT inv.id FROM $invTable inv
                WHERE inv.invoice_number = ${extractNo('journal_entries.description')}
              )
              WHERE reference_type = '$refType'
                AND is_auto_posted = 1
                AND instr(description, '$marker') > 0
                AND (
                  SELECT COUNT(*) FROM $invTable inv2
                  WHERE inv2.invoice_number = ${extractNo('journal_entries.description')}
                ) = 1
            ''');
          }

          Future<int> untouchedCount(String refType, String invTable) async {
            final row = await m.database.customSelect('''
              SELECT COUNT(*) AS c FROM journal_entries je
              WHERE je.reference_type = '$refType'
                AND je.is_auto_posted = 1
                AND (
                  instr(je.description, '$marker') = 0
                  OR (
                    SELECT COUNT(*) FROM $invTable inv
                    WHERE inv.invoice_number = ${extractNo('je.description')}
                  ) != 1
                )
            ''').getSingle();
            return (row.data['c'] as int?) ?? 0;
          }

          await backfill('sales_return', 'sales_invoices');
          await backfill('purchase_return', 'purchase_invoices');

          final salesLeft = await untouchedCount('sales_return', 'sales_invoices');
          final purchLeft =
              await untouchedCount('purchase_return', 'purchase_invoices');
          debugPrint('[Migration] v150 return-JE referenceId backfill done — '
              'left untouched (ambiguous/unmatched, kept hash): '
              'sales_return=$salesLeft purchase_return=$purchLeft');
        } catch (e) {
          debugPrint('[Migration] v150 return-JE backfill '
              '(best-effort, skipped): $e');
        }
      });
      debugPrint('[Migration] v150: return-exempt autopost dedup index '
          '+ historical backfill applied');
    }

    // ═════════════════════════════════════════════════════════════════════
    // v151 — shifts.closing_snapshot (reprint a closed shift)
    //
    // The closing report is printed once, at close time, and was never
    // recoverable afterwards. Recomputing it is not enough: the ACTUAL
    // counted amounts are cashier input, and only `actual_cash` had a
    // column — the bank and click counts lived inside the free-text `notes`
    // string. A "reprint" built without them would not match the paper the
    // cashier signed.
    //
    // So the close path now stores the exact figures it printed, as JSON.
    // Nullable, no backfill: shifts closed before this point have no
    // snapshot to recover and are recomputed + labelled in the UI. Adding a
    // nullable column is the cheapest possible schema change on the large
    // production databases this runs against.
    // ═════════════════════════════════════════════════════════════════════
    if (from < 151) {
      await _safeMigrate('v151 shifts.closing_snapshot', () async {
        await m.addColumn(shifts, shifts.closingSnapshot);
        debugPrint('[Migration] v151 shifts.closing_snapshot OK');
      });
    }

    // ── v152: قيود قاعدة البيانات لمنعَي B1 و B2 ──────────────────────────
    //
    // الحارسان الموجودان (recordSalaryPayment و importDeviceCheckIn) كودُ
    // تطبيق، فبيقفلوا الضغط المكرر على نفس الجهاز بس. كاتب متزامن من جهاز
    // تاني بيقرا «مفيش صف سابق» في نفس اللحظة فالاتنين بيعدّوا. دي الطبقة
    // اللي بتمنع ده فعلاً.
    if (from < 152) {
      // الحضور: بيتنضّف قبل الفهرس. الصفوف دي **مش سجلات مالية** — بتتحوّل
      // لفلوس عبر العدّ فقط — فدمجها آمن: نبقّي أقدم صف لكل (موظف، يوم)
      // ونضم عليه أبكر دخول وآخر خروج، ونحذف الباقي.
      await _safeMigrate('v152 employee_attendance dedup', () async {
        await m.database.customStatement('''
          UPDATE employee_attendance
          SET check_in = (SELECT MIN(b.check_in) FROM employee_attendance b
                          WHERE b.employee_id = employee_attendance.employee_id
                            AND b.date = employee_attendance.date
                            AND b.check_in IS NOT NULL),
              check_out = (SELECT MAX(b.check_out) FROM employee_attendance b
                           WHERE b.employee_id = employee_attendance.employee_id
                             AND b.date = employee_attendance.date
                             AND b.check_out IS NOT NULL)
          WHERE id IN (SELECT MIN(id) FROM employee_attendance
                       GROUP BY employee_id, date)
        ''');
        await m.database.customStatement('''
          DELETE FROM employee_attendance
          WHERE id NOT IN (SELECT MIN(id) FROM employee_attendance
                           GROUP BY employee_id, date)
        ''');
        debugPrint('[Migration] v152 attendance rows deduped');
      });

      // الفهرسان **غير قاتلين بقصد**. `_safeMigrate` بيرمي أي خطأ غير
      // idempotent، ولو رمى هنا التطبيق ما بيقلعش خالص — وده تمن غالي جداً
      // لطبقة **تحصين**: الحارسان في `recordSalaryPayment` و
      // `importDeviceCheckIn` شغالين على أي حال.
      //
      // والرواتب تحديداً **ما بتتنضّفش تلقائياً**: الصف المكرر سجل مالي مربوط
      // بسند صرف نقدي وقيد يومية، وحذفه من غير عكس الحركتين بيخلّي الخزنة
      // والدفاتر غلط. لو فيه تكرار قائم، الفهرس ما بيتركّبش والبيانات تفضل زي
      // ما هي لحد ما محاسب يسوّيها — والرسالة تحت بتقول له فين بالظبط.
      //
      // PicPos لسه ماطرحش (مفيش تنصيبات) فالاتنين بينجحوا دايماً هناك؛ الفرع
      // ده موجود للنقل لقاعدة فيها بيانات.
      for (final (label, sql) in [
        ('attendance day', kCreateAttendanceDayDedupIndexSql),
        ('salary payment period', kCreateSalaryPaymentDedupIndexSql),
      ]) {
        try {
          await m.database.customStatement(sql);
          debugPrint('[Migration] v152 $label dedup index OK');
        } catch (e) {
          debugPrint(
              '[Migration] v152 $label dedup index SKIPPED — فيه تكرار قائم '
              'في البيانات لازم يتسوّى يدوياً قبل ما القيد يتركّب: $e');
          await DiagnosticLogger.logError(
              DiagnosticLogger.migration, 'v152 $label dedup index', e);
        }
      }
    }

    // ── v153: الأجرُ بالساعة والإضافي المحسوب — جدولُ العطلات وعمودا
    // ساعاتِ اليوم والتجاوز اليدويّ ──────────────────────────────────────
    if (from < 153) {
      await _safeMigrate('v153 work_holidays + hoursPerDay + isManualAmount',
          () async {
        await m.createTable(workHolidays);
        await m.addColumn(employees, employees.hoursPerDay);
        await m.addColumn(overtimeRecords, overtimeRecords.isManualAmount);
        // السجلّاتُ القائمة حُسبت بمقامٍ آخر — تُعلَّم يدويةً فلا يُعاد
        // حسابُها وتتغيّر رواتبُ ماضية.
        await m.database
            .customStatement('UPDATE overtime_records SET is_manual_amount = 1');
        debugPrint('[Migration] v153 work_holidays + hoursPerDay + '
            'isManualAmount OK');
      });
    }

    // ── v154: خدمةُ الطاولات — الحالةُ المدفوعة والخصمُ والدفعاتُ المتعدّدة ──
    if (from < 154) {
      await _safeMigrate('v154 table service columns + table_order_payments',
          () async {
        await m.addColumn(tableOrders, tableOrders.guestCount);
        await m.addColumn(tableOrders, tableOrders.notes);
        await m.addColumn(tableOrders, tableOrders.discountType);
        await m.addColumn(tableOrders, tableOrders.discountValue);
        await m.addColumn(tableOrders, tableOrders.paidAmount);
        await m.addColumn(tableOrderItems, tableOrderItems.notes);
        await m.addColumn(
            tableOrderItems, tableOrderItems.sourceTableOrderId);
        await m.createTable(tableOrderPayments);
        debugPrint('[Migration] v154 table service OK');
      });
    }

    // ── v155: ضريبةُ المبيعات على طلبات الطاولات ────────────────────────
    //
    // العمودان يحملان ما كانت السلّةُ وحدَها تحمله، فيتطابق المشحونُ
    // والمسجَّل. والقائمُ من الطلبات يأخذ الافتراضَين (`0`/`false`) — أي
    // «بلا ضريبة»، وهو حالُها اليوم بالضبط، فلا يتغيّر حسابُ طاولةٍ مفتوحةٍ
    // بمجرّد الترقية.
    if (from < 155) {
      await _safeMigrate('v155 table order tax columns', () async {
        await m.addColumn(tableOrders, tableOrders.taxEnabled);
        await m.addColumn(tableOrders, tableOrders.taxRate);
        debugPrint('[Migration] v155 table order tax OK');
      });
    }

    // ── v156: قيدُ «لا تفعيلَ بلا نسبة» على طلبات الطاولات ───────────────
    //
    // v155 أضاف العمودين وحرسَهما في الخدمة. وهذا يجعل الحالةَ الكاذبةَ
    // (`tax_enabled = 1` و`tax_rate = 0`) **مستحيلةَ التمثيل** لا مرفوضةً
    // عند بابٍ واحد — اقرأ [TableOrders.customConstraints].
    //
    // وSQLite لا تضيف قيداً بـ`ALTER TABLE`، فالسبيلُ الوحيدُ إعادةُ إنشاء
    // الجدول ونقلُ بياناته. `m.alterTable` تفعلها بالخطوات الاثنتَي عشرة
    // التي توصي بها SQLite: إطفاءُ المفاتيح، إنشاءُ بديلٍ بالشكل الجديد،
    // نقلُ الصفوف، إسقاطُ الأصل، `legacy_alter_table` كي لا تُعاد كتابةُ
    // إشاراتِ الأبناء عند التسمية، ثم إعادةُ الفهارس والمشغِّلات.
    //
    // والتسويةُ **تسبق** القيدَ بالضرورة: صفٌّ كاذبٌ قائمٌ يُفشل إعادةَ
    // الإنشاء فيقتل الإقلاع. وهي تُطفئ الزرَّ ولا تُلفّق نسبةً — الفاتورةُ
    // خرجت بضريبةِ صفرٍ فعلاً، فإطفاءُ الزرِّ هو ما يجعل السجلَّ يطابق ما
    // حُصِّل حقّاً. واختراعُ نسبةٍ الآن يعيد تسعيرَ حسابٍ رآه الضيفُ ودُفع.
    //
    // **وعتبةُ التسوية هنا هي عتبةُ اليوم لا عتبةُ ١٥٦.** `m.alterTable` تبني
    // تعريفَ الجدول **الحاليَّ** لا تعريفَه يومَ كُتبت هذه الخطوة، فالقيدُ
    // الذي تُنشئه هذه السطورُ هو ما في [TableOrders.customConstraints] الآن.
    // فلمّا شُدَّ القيدُ في v157 صار صفٌّ نسبتُه `0.005` — وهو ما كانت تُجيزه
    // v156 — يُفشل إعادةَ البناء **هنا**، قبل أن تُشغَّل v157 أصلاً. مقيسٌ لا
    // مفترض: `CHECK constraint failed: NOT tax_enabled OR tax_rate >= 0.01`
    // من خطوة v156 على قاعدةٍ مُرقّاةٍ من ١٥٥.
    //
    // فأيُّ خطوةٍ تُعيد بناءَ جدولٍ تلزمها تسويةٌ تُرضي قيدَه **الحاليّ**.
    if (from < 156) {
      await _safeMigrate('v156 table_orders tax CHECK constraint', () async {
        await customStatement(
          'UPDATE table_orders SET tax_enabled = 0 '
          'WHERE tax_enabled = 1 AND tax_rate < 0.01',
        );
        // v167 — أعمدةُ المزامنة **إلزاميّةٌ هنا** وإن أُضيفت بعد هذه
        // الخطوة بأحدَ عشرَ إصداراً: `alterTable` تنسخ بـ`INSERT INTO new
        // SELECT <أعمدةِ اليوم> FROM old`، وقاعدةٌ عند v155 لا تملكها
        // فترمي `no such column: global_id` — ويبتلعها `_safeMigrate`
        // فتضيع **الخطوةُ كلُّها** بما فيها قيدُ الضريبة.
        await m.alterTable(TableMigration(tableOrders, newColumns: [
          tableOrders.globalId,
          tableOrders.lastModifiedAt,
          tableOrders.deletedAt,
          tableOrders.originClientId,
          tableOrders.rowVersion,
        ]));
        debugPrint('[Migration] v156 table_orders tax CHECK OK');
      });
    }

    // ── v157: الحدُّ الأدنى المعقولُ للنسبة، لا مجرّد «فوق الصفر» ──────────
    //
    // قيدُ v156 (`tax_rate > 0`) يقبل `0.0000001`: القيدُ راضٍ، والزرُّ يقول
    // «مفعَّلة»، والمحصَّلُ صفرٌ بعد التقريب — الكذبةُ التي أُغلقت عائدةً
    // بصورةٍ تمرّ من تحت القيد نفسِه. والحدُّ الآن `TaxRateBounds.minRate`
    // (١٪) عند الأبواب الثلاثة: مدخلُ الإعدادات، و`setOrderTax`، والقيد.
    //
    // نفسُ آليّة v156 ونفسُ ترتيبها: التسويةُ **تسبق** إعادةَ البناء
    // بالضرورة — صفٌّ مخالفٌ قائمٌ يُفشل `m.alterTable` فيقتل الإقلاع.
    //
    // وتُطفئ الزرَّ ولا تُلفّق نسبةً: الفاتورةُ خرجت بضريبةٍ تُقرَّب إلى صفرٍ
    // فعلاً، فإطفاءُ الزرِّ هو ما يجعل السجلَّ يطابق ما حُصِّل. ورفعُ اللقطة
    // إلى الحدِّ الآن يعيد تسعيرَ حسابٍ رآه الضيفُ ودُفع.
    //
    // والمطفأُ لا يُمَسّ وإن كانت لقطتُه دون الحدّ — القيدُ لا يطارد مطفأً،
    // واللقطةُ تبقى محفوظةً كما تركها v156.
    if (from < 157) {
      await _safeMigrate('v157 table_orders minimum tax rate', () async {
        await customStatement(
          'UPDATE table_orders SET tax_enabled = 0 '
          'WHERE tax_enabled = 1 AND tax_rate < 0.01',
        );
        await m.alterTable(TableMigration(tableOrders, newColumns: [
          tableOrders.globalId, // v167 — انظر v156 أعلاه
          tableOrders.lastModifiedAt,
          tableOrders.deletedAt,
          tableOrders.originClientId,
          tableOrders.rowVersion,
        ]));
        debugPrint('[Migration] v157 table_orders minimum tax rate OK');
      });
    }

    // ── v158: الحجزُ ثم التثبيت — دفعةٌ بلا فاتورةٍ بعد ──────────────────
    //
    // `invoice_id` يصير معدوماً-مسموحاً ويُضاف `status`، فيصير الصفُّ قابلاً
    // لأن يُدرَج **قبل** الترحيل. وبه تعمل كلُّ حراس `recordPayment` قبل أن
    // تُرحَّل فاتورةٌ — فإن رفضت، لم يصدر شيءٌ يحتاج تسوية.
    //
    // وإسقاطُ `NOT NULL` لا يجري بـ`ALTER TABLE` في SQLite، فالسبيلُ إعادةُ
    // إنشاء الجدول — وهو ما تفعله `m.alterTable` بالخطوات الاثنتَي عشرة.
    // و`addColumn` تسبقها لأن `TableMigration` تنسخ الأعمدةَ القائمةَ فحسب،
    // فعمودٌ لم يوجد بعدُ لا يُنقَل بل يُنشَأ بافتراضه.
    //
    // ولا تسويةَ بيانات: الافتراضُ `settled` وكلُّ صفٍّ قائمٍ له `invoice_id`
    // غيرُ معدوم، فالقيدُ يرضى عن الصفوف القائمة كما هي.
    //
    // ⚠️ ولأن `m.alterTable` تبني تعريفَ **اليوم**: أيُّ تشديدٍ لاحقٍ لهذا
    // القيد يجب أن يُراجَع مع كلِّ خطوةٍ أقدمَ تُعيد بناءَ هذا الجدول.
    if (from < 158) {
      await _safeMigrate('v158 table_order_payments reserve-then-commit',
          () async {
        await m.addColumn(tableOrderPayments, tableOrderPayments.status);
        await m.alterTable(TableMigration(tableOrderPayments, newColumns: [
          tableOrderPayments.globalId, // v167 — انظر v156 أعلاه
          tableOrderPayments.lastModifiedAt,
          tableOrderPayments.deletedAt,
          tableOrderPayments.originClientId,
          tableOrderPayments.rowVersion,
        ]));
        debugPrint('[Migration] v158 table_order_payments reserve/commit OK');
      });
    }

    if (from < 159) {
      await _safeMigrate('v159 booking engine tables', () async {
        // جداولُ جديدةٌ خالصةٌ — لا `alterTable`، فلا خطرَ إعادةِ بناءِ
        // جدولٍ قائمٍ ولا إسقاطَ خطوةٍ أقدمَ تُعيد بناءَ نفس الجدول.
        await m.createTable(bookingResources);
        await m.createTable(bookingServices);
        await m.createTable(bookings);

        // فهرسُ المسار الساخن `(resource_id, starts_at)` — فهرسٌ خامٌّ لا
        // كيانُ drift، فلا `createTable` ولا `createAll` بيصدّروه. وهو
        // **غير فريد** عمداً: التداخلُ يُمنَع بالفحص في الـDAO لا بقيد،
        // وصفّان في نفس اللحظة مشروعان ما دام أحدُهما ملغًى أو لم يحضر.
        //
        // وهنا **قاتلٌ** بخلاف فهرسَي v152: الجدولُ أُنشئ في هذه الخطوةِ
        // نفسِها قبل سطرين، فلا بياناتٌ قائمةٌ تُفشله، وفشلُه يعني خللاً
        // حقيقيّاً يجب أن يظهر.
        await m.database.customStatement(kCreateBookingResourceSlotIndexSql);
        debugPrint('[Migration] v159 booking engine tables OK');
      });
    }

    // ── v160: نقلُ إغلاق الوردية إلى فئة الخزينة ──────────────────────────
    //
    // ⚠️ ‏160 لا 159: هذه الترقيةُ وردت من فرع `pos-flexible-permissions`
    // برقم ١٥٩، وكان ١٥٩ قد أُخذ سلفاً لجداول محرِّك الحجز التي دخلت `main`
    // قبلَها. فرُفعت إلى **١٦٠** — ومعها حارسُها `from < 160`. والشقُّ الثاني
    // هو الذي يُنسى: لو مرَّ الرقمُ وبقي الحارسُ عند ١٥٩ لما طُبِّقت أبداً على
    // قاعدةٍ بلغت ١٥٩ بمحرِّك الحجز.
    if (from < 160) {
      await _safeMigrate('v160 نقلُ إغلاق الوردية إلى فئة الخزينة', () async {
        await m.database.customStatement(
          "UPDATE permissions SET category = 'treasury' "
          "WHERE code = 'pos_shift_close'",
        );
        debugPrint('[Migration] v160 pos_shift_close → treasury OK');
      });
    }

    // ── v161: واجهةُ الحجوزات — حالةُ الحضور وأعمدةُ المورد وجدولُ التذكير ──
    //
    // ثلاثةُ تغييراتٍ في **ترقيةٍ واحدة** عن قصد: قيدُ `bookings.status`
    // وأعمدةُ `booking_resources` كلاهما يستدعي `m.alterTable` بإعادةِ بناءِ
    // جدول. ودفعُها في ترقيتين يدفع الكلفةَ مرّتين على قواعدَ حيّة.
    //
    // ⚠️ و`m.alterTable` تبني تعريفَ **اليوم** لا تعريفَ لحظةِ الترقية. فأيُّ
    // خطوةٍ أقدمَ تعيد بناءَ نفسِ الجدولين تصير تابعةً لهذا التعريف — وهي
    // هنا `v159` التي أنشأتهما بـ`createTable` (وتبني تعريفَ اليوم كذلك)،
    // فلا تعارض. **ومن أضاف عموداً لاحقاً فليقرأ هذا قبل أن يكتب خطوةً
    // بينهما.**
    if (from < 161) {
      await _safeMigrate('v161 حالةُ الحضور وأعمدةُ المورد والتذكيرات',
          () async {
        // ‏١) `bookings.status` يقبل `seated`. إضافةٌ لا استبدال، فلا صفٌّ
        //    قائمٌ يصير مخالفاً — ولا تسويةَ بياناتٍ مطلوبةٌ قبلها.
        // v167 — انظر تحذيرَ `newColumns` أدناه: ينطبق على `bookings` أيضاً،
        // وقاعدةٌ عند v160 لا تملك أعمدةَ المزامنة.
        await m.alterTable(TableMigration(bookings, newColumns: [
          bookings.globalId,
          bookings.lastModifiedAt,
          bookings.deletedAt,
          bookings.originClientId,
          bookings.rowVersion,
        ]));

        // ‏٢) أعمدةُ المورد. `addColumn` لا تكفي وحدَها لأن القيدَ على `kind`
        //    جزءٌ من تعريف الجدول، و`alterTable` تحمل الاثنين معاً.
        //
        // ⚠️ و`newColumns` **إلزاميّة** هنا: `alterTable` تنسخ البياناتِ بـ
        //    `INSERT INTO new SELECT <أعمدةِ اليوم> FROM old`، فعمودٌ لم يكن
        //    في الجدول القديم يُطلَب من مصدرٍ لا يملكه فترمي
        //    `no such column: "role"`. وتصريحُها يجعل drift يكتب الافتراضَ
        //    بدل أن يقرأ. وبدونها ابتلعها `_safeMigrate` (تعدّ
        //    «no such column» خطأً عديمَ الأثر) فخُتمت قاعدةُ المالك 161
        //    بلا أعمدةٍ وسقطت شاشةُ الحجوزات كلُّها.
        await m.alterTable(TableMigration(
          bookingResources,
          newColumns: [
            bookingResources.role,
            bookingResources.kind,
            bookingResources.shiftStartMinutes,
            bookingResources.shiftEndMinutes,
            // v167 — أعمدةُ المزامنة أُضيفت بعد هذه الخطوة بستِّ إصدارات،
            // وقاعدةٌ عند v160 لا تملكها. ونفسُ التحذير أعلاه ينطبق عليها
            // حرفاً: بدونها ترمي `no such column: global_id` ويبتلعها
            // `_safeMigrate` فتضيع أعمدةُ المورد الأربعةُ معها.
            // و`deletedAt` ليس منها — الجدولُ وُلد به.
            bookingResources.globalId,
            bookingResources.lastModifiedAt,
            bookingResources.originClientId,
            bookingResources.rowVersion,
          ],
        ));

        // ‏٣) جدولُ التذكيرات — جديدٌ فلا إعادةَ بناء.
        await m.createTable(bookingReminders);

        debugPrint('[Migration] v161 bookings seated + resource cols + '
            'reminders OK');
      });
    }

    // ‏١٦٢ — إنقاذُ القواعد التي خُتمت 161 وأعمدةُ المورد ناقصةٌ فيها.
    //
    // ⚠️ إصلاحُ خطوةِ 161 أعلاه **لا يكفي**: قاعدةٌ ختمت 161 لا يعود
    //    `from < 161` يفحصها أبداً، فتبقى بلا أعمدةٍ إلى الأبد وشاشةُ
    //    الحجوزات ساقطةٌ بـ`no such column: booking_resources.role`.
    //    (وقع على قاعدة المالك 2026-08-23.)
    //
    // ⚠️ و**بفحصٍ قبل الإصلاح**: تنصيبةٌ وُلدت بـ`onCreate` عند 161 تملك
    //    الأعمدةَ وقد تحمل بياناتٍ فيها. وإعادةُ البناء بـ`newColumns`
    //    تكتب الافتراضاتِ فوقَ القيم — أي أنّ «إصلاحاً» غيرَ مشروطٍ يمسح
    //    أدوارَ الموظّفين ومواعيدَ ورديّاتهم صامتاً.
    if (from < 162) {
      await _safeMigrate('v162 إنقاذُ أعمدةِ المورد الناقصة', () async {
        final info = await customSelect(
          'PRAGMA table_info(booking_resources)',
        ).get();
        final present =
            info.map((r) => r.data['name'] as String).toSet();

        if (present.contains('role')) {
          debugPrint('[Migration] v162 skipped — أعمدةُ المورد موجودةٌ أصلاً');
          return;
        }

        await m.alterTable(TableMigration(
          bookingResources,
          newColumns: [
            bookingResources.role,
            bookingResources.kind,
            bookingResources.shiftStartMinutes,
            bookingResources.shiftEndMinutes,
            // v167 — انظر v161 أعلاه؛ نفسُ السبب حرفاً.
            bookingResources.globalId,
            bookingResources.lastModifiedAt,
            bookingResources.originClientId,
            bookingResources.rowVersion,
          ],
        ));
        debugPrint('[Migration] v162 أعمدةُ المورد أُضيفت — إنقاذُ 161 OK');
      });
    }

    // ‏١٦٣ — نمطُ منح الصلاحية (`role_permissions.grant_mode`).
    //
    // «مشروط» في مصفوفة الأدوار: الصلاحيةُ ممنوحةٌ ويمرّ تنفيذُها بموافقة
    // مسؤول. والعمودُ بافتراض `allow`، فكلُّ منحةٍ قائمةٍ تبقى كما كانت —
    // والاتّجاهُ مقصود: افتراضٌ مشروطٌ كان سيحوّل كلَّ نظامٍ قائمٍ إلى سؤال
    // مسؤولٍ في كلّ ضغطة.
    //
    // ⚠️ **و`addColumn` لا `alterTable`**: الأخيرةُ تعيد بناءَ الجدول من
    //    تعريفِ **اليوم**، و`role_permissions` مفتاحُه مركّبٌ بمرجعَين —
    //    فإعادةُ بنائه تُخاطر بصفوفٍ قائمةٍ بلا مقابل. والإضافةُ بعمودٍ ذي
    //    افتراضٍ لا تحتاج إعادةَ بناءٍ أصلاً.
    if (from < 163) {
      await _safeMigrate('v163 نمطُ منح الصلاحية', () async {
        final info = await customSelect(
          'PRAGMA table_info(role_permissions)',
        ).get();
        final present = info.map((r) => r.data['name'] as String).toSet();
        if (present.contains('grant_mode')) {
          debugPrint('[Migration] v163 skipped — grant_mode موجودٌ أصلاً');
          return;
        }
        await m.addColumn(rolePermissions, rolePermissions.grantMode);
        debugPrint('[Migration] v163 grant_mode أُضيف');
      });
    }

    // ‏١٦٤ — الاستحقاقُ وشروطُ التعامل (أمرُ المالك 2026-08-26).
    //
    // سبعةُ أعمدةٍ في أربعة جداول تجعل «أعمار الدين» و«المستحق» و«ملفَّ
    // الطرف» أرقاماً حقيقيّةً بدل نصوصٍ في تصميم. وقبلها كان التقادمُ
    // يُحسب من **تاريخ الإصدار** لأنّ الاستحقاقَ لا وجودَ له، فيقرأ
    // المشغّلُ عمراً أقصرَ من الحقيقة لكلّ فاتورةٍ لها مهلةُ سداد.
    //
    // ⚠️ **ولا صفَّ واحدٌ يُكتَب هنا.** `due_date` يقبل الفراغَ والفراغُ يعني
    //    «بلا مهلة»، فتُقرأ `COALESCE(due_date, invoice_date)` — وأرقامُ
    //    التقادم لا تتحرّك لحظةَ الترقية. الاتّجاهُ مقصود: ترقيةٌ تُبدّل
    //    أرقامَ دفاترِ المالك بلا أن يطلب ذلك أسوأُ من ترقيةٍ لا تفعل شيئاً.
    //
    // ⚠️ **و`addColumn` لا `alterTable`**: الأخيرةُ تعيد بناءَ الجدول من
    //    تعريفِ **اليوم**، وجداولُ الفواتير والأوامر مرجعيّاتُها كثيرةٌ
    //    وفهارسُها عديدة. والإضافةُ بعمودٍ ذي افتراضٍ أو يقبل الفراغَ لا
    //    تحتاج إعادةَ بناءٍ أصلاً.
    //
    // ⚠️ **وفحصٌ مستقلٌّ لكلّ جدول**: لو أُضيف بعضُها في تشغيلٍ سابقٍ انقطع
    //    قبل تمامه، لا تسقط الخطوةُ كلُّها ولا تُعاد إضافةُ الموجود.
    if (from < 164) {
      await _safeMigrate('v164 الاستحقاقُ وشروطُ التعامل', () async {
        Future<Set<String>> columnsOf(String table) async {
          final info = await customSelect('PRAGMA table_info($table)').get();
          return info.map((r) => r.data['name'] as String).toSet();
        }

        final partyCols = await columnsOf('parties');
        if (!partyCols.contains('payment_terms_days')) {
          await m.addColumn(parties, parties.paymentTermsDays);
        }
        if (!partyCols.contains('early_payment_discount_pct')) {
          await m.addColumn(parties, parties.earlyPaymentDiscountPct);
        }
        if (!partyCols.contains('early_payment_discount_days')) {
          await m.addColumn(parties, parties.earlyPaymentDiscountDays);
        }
        if (!partyCols.contains('supplier_rating')) {
          await m.addColumn(parties, parties.supplierRating);
        }

        final salesCols = await columnsOf('sales_invoices');
        if (!salesCols.contains('due_date')) {
          await m.addColumn(salesInvoices, salesInvoices.dueDate);
        }

        final purchaseCols = await columnsOf('purchase_invoices');
        if (!purchaseCols.contains('due_date')) {
          await m.addColumn(purchaseInvoices, purchaseInvoices.dueDate);
        }

        final poCols = await columnsOf('purchase_orders');
        if (!poCols.contains('received_at')) {
          await m.addColumn(purchaseOrders, purchaseOrders.receivedAt);
        }

        debugPrint('[Migration] v164 الاستحقاقُ وشروطُ التعامل — تمّت');
      });
    }

    // ═══ v165 — متابعةُ التحصيل ومطالبةُ المورد ═══════════════════════════
    //
    // جدولان **جديدان** لا أعمدةٌ على قائم، فلا `alterTable` ولا تسويةَ
    // بيانات: `createTable` وحدَها، ولا صفَّ واحدٌ يُكتَب.
    //
    // ⚠️ **والفحصُ بوجود الجدول لا بالنسخة**: تشغيلةٌ سابقةٌ انقطعت بعد أوّلِ
    //    جدولٍ تترك النسخةَ ٦٤١ والجدولَ الأوّلَ قائماً، فـ`createTable`
    //    عليه يرمي «table already exists» ويُسقط الخطوةَ كلَّها. والفحصُ
    //    المستقلُّ لكلٍّ يجعلها قابلةً للإعادة.
    if (from < 165) {
      await _safeMigrate('v165 متابعةُ التحصيل ومطالبةُ المورد', () async {
        Future<bool> tableExists(String name) async {
          final rows = await customSelect(
            "SELECT name FROM sqlite_master "
            "WHERE type = 'table' AND name = ?",
            variables: [Variable(name)],
          ).get();
          return rows.isNotEmpty;
        }

        if (!await tableExists('party_follow_ups')) {
          await m.createTable(partyFollowUps);
        }
        if (!await tableExists('supplier_claims')) {
          await m.createTable(supplierClaims);
        }

        debugPrint('[Migration] v165 متابعةُ التحصيل ومطالبةُ المورد — تمّت');
      });
    }

    // ═══════════════════════════════════════════════════════════════════
    // v166 — المرحلة ٢: أعمدةُ المزامنة لأحدَ عشرَ جدولاً ذاتِ أثرٍ محاسبيّ
    // ═══════════════════════════════════════════════════════════════════
    //
    // ═══ العطبُ الذي تسدّه ═══
    //
    // تطبيقُ ورقةِ تحميلٍ وترحيلُ إهلاكٍ وتسجيلُ مصروفٍ تشغيليٍّ **تقيّد
    // قيوداً تُزامَن** (‏`journal` استراتيجيّةٌ قائمة) بينما المستندُ
    // المولِّدُ يبقى محلّيّاً. فالخادمُ يرى أثراً ماليّاً بلا مصدرٍ يفسّره —
    // لا يُراجَع ولا يُعكَس من جهازٍ آخر. وجهازٌ ثانٍ لا يعرف أنّ الورقةَ
    // طُبِّقت فيطبّقها ثانيةً، فيتضاعف التحميل على التكلفة.
    //
    // ═══ لماذا هذه الصيغةُ بالذات ═══
    //
    // ١) `ADD COLUMN … UNIQUE` **مرفوضةٌ في SQLite** (‏الجدولُ قد يحمل
    //    مكرَّراً أصلاً). فالعمودُ عاديٌّ ثمّ **فهرسٌ فريدٌ جزئيّ** — نفسُ
    //    علاجِ v119 وv128 بعد أن كُشف أنّ الخطأَ كان مبلوعاً والعمودُ لا
    //    يُنشَأ على أيِّ جدول.
    //
    // ٢) و`row_version` بلا مُشغِّلٍ رقمٌ ميّت: لا شيءَ يرفعه فيبدو كلُّ صفٍّ
    //    أزليّاً وتُبتلَع التعديلات. فالمُشغِّلُ هنا نسخةُ v129، وحارسُ
    //    `WHEN` يمنع الدورَ — التحديثُ داخلَ المُشغِّل يوقظه ثانيةً لولاه.
    //
    // ٣) والتعبئةُ بـ`UuidV7` لا `v4`: مرتّبةٌ زمنيّاً فتبقى الصفوفُ القديمةُ
    //    مرتّبةً عند أوّلِ دفعةٍ إلى الخادم.
    //
    // ⚠️ و`fixed_assets` له `global_id` سلفاً — الـsafe-skip يتكفّل به،
    //    والتعبئةُ تملأ ما كان فارغاً لا غير.
    if (from < 166) {
      await _safeMigrate('v166 أعمدةُ مزامنةٍ للمستندات المحاسبيّة', () async {
        const phase2Tables = [
          // التكاليفُ المحمَّلة
          'landed_cost_sheets', 'landed_cost_items', 'landed_cost_allocations',
          // الأصولُ والإهلاك
          'fixed_assets', 'asset_categories', 'asset_depreciations',
          // المصروفاتُ التشغيليّة
          'op_expenses', 'op_expense_categories',
          // التصنيعُ وتكاليفُه — و`bill_of_materials` أبٌ لاثنين منها
          'bill_of_materials',
          'manufacturing_orders', 'mfg_order_costs', 'bom_components',
        ];

        for (final t in phase2Tables) {
          // ١. المعرّفُ العالميّ — عمودٌ عاديٌّ ثمّ فهرسٌ فريدٌ جزئيّ.
          try {
            await m.database.customStatement(
              'ALTER TABLE $t ADD COLUMN global_id TEXT',
            );
          } catch (e) {
            debugPrint('[Migration] v166 ADD $t.global_id (safe-skip): $e');
          }
          try {
            await m.database.customStatement(
              'CREATE UNIQUE INDEX IF NOT EXISTS idx_${t}_global_id '
              'ON $t(global_id) WHERE global_id IS NOT NULL',
            );
          } catch (e) {
            debugPrint('[Migration] v166 IX $t.global_id (safe-skip): $e');
          }

          // ٢. تعبئةُ الصفوفِ القائمة — **قبلَ** المُشغِّل عمداً: صفٌّ بلا
          //    معرّفٍ عالميٍّ لا يُدفَع أصلاً، والتعبئةُ بعد المُشغِّل تُشعله
          //    مرّةً لكلِّ صفٍّ بلا فائدة.
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
            debugPrint('[Migration] v166 backfill $t.global_id (safe-skip): $e');
          }

          // ٣. أعمدةُ الدلتا الأربعة.
          for (final ddl in [
            'ALTER TABLE $t ADD COLUMN last_modified_at INTEGER',
            'ALTER TABLE $t ADD COLUMN deleted_at INTEGER',
            'ALTER TABLE $t ADD COLUMN origin_client_id TEXT',
            'ALTER TABLE $t ADD COLUMN row_version INTEGER NOT NULL DEFAULT 0',
          ]) {
            try {
              await m.database.customStatement(ddl);
            } catch (_) {} // safe-skip: العمودُ موجودٌ سلفاً
          }

          // ٤. مُشغِّلُ رفعِ النسخة.
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
            debugPrint('[Migration] v166 trigger $t: $e');
          }
        }

        debugPrint(
          '[Migration] v166: أعمدةُ المزامنة على '
          '${phase2Tables.length} جدولاً محاسبيّاً',
        );
      });
    }

    // ═══════════════════════════════════════════════════════════════════
    // v167 — المرحلة ٣: أعمدةُ المزامنة للفئةِ التشغيليّة (ثمانيةَ عشرَ جدولاً)
    // ═══════════════════════════════════════════════════════════════════
    //
    // ═══ العطبُ الذي تسدّه ═══
    //
    // المطاعمُ والمطبخُ والحجوزاتُ والتوزيعُ كلُّها **محلّيّةٌ بالكامل**:
    // طلبُ طاولةٍ يُفتَح على جهازٍ ولا يراه جهازٌ ثانٍ، وأمرُ تحضيرٍ يُطبَع
    // في المطبخ ولا يُغلَق من الكاشير، وحجزٌ يُؤخَذ على الاستقبال فتُباع
    // الطاولةُ نفسُها مرّتين. وهذه ليست تقارير — إنّها **حالةُ تشغيلٍ
    // لحظيّةٌ** يقرؤها أكثرُ من جهازٍ في آنٍ واحد، وهي أكثرُ ما يُشترى
    // النظامُ من أجله في مطعمٍ متعدّدِ النقاط.
    //
    // ═══ لماذا هذه الفئةُ أرخصُ من المرحلة ٢ ═══
    //
    // مقيسٌ لا مقدَّر: `tables_dao.dart` و`kitchen_dao.dart` فيهما **صفرُ**
    // استدعاءٍ لـ`createJournalEntry` وصفرُ حركةِ خزنةٍ أو مخزون، و
    // `bookings_dao.dart` فيه **واحد**. فالفئةُ في جوهرها **مسارٌ واردٌ
    // فقط** — أعمدةٌ وهجرةٌ وعضويّةُ قوائم — ولا تحتاج مسارَ الدفعِ الثقيلَ
    // الذي بنته المرحلة ٢ إلّا في موضعِ خصمِ العربونِ وحدَه.
    //
    // ═══ الصيغةُ نفسُها لنفسِ الأسباب ═══
    //
    // عمودٌ عاديٌّ ثمّ فهرسٌ فريدٌ جزئيّ (`ADD COLUMN … UNIQUE` مرفوضةٌ في
    // SQLite)، وتعبئةٌ بـ`UuidV7` **قبلَ** المُشغِّل، ومُشغِّلٌ يرفع
    // `row_version` بحارسِ `WHEN` يمنع الدور. انظر v166 أعلاه للتفصيل.
    //
    // ⚠️ و`booking_resources` و`booking_services` و`booking_reminders` لها
    //    `deleted_at` سلفاً (‏وُلدت به في `createTable`) — الـsafe-skip
    //    يتكفّل به، ولذلك تعريفُ الـDart لا يكرّره.
    if (from < 167) {
      await _safeMigrate('v167 أعمدةُ مزامنةٍ للفئةِ التشغيليّة', () async {
        const phase3Tables = [
          // الموظَّفُ — أبٌ لخمسةٍ من الفئة، وثلاثةٌ منها تشير إليه بإشارةٍ
          // غيرِ قابلةٍ للإفراغ. وليس فتحاً لشؤون الموظّفين.
          'employees',
          // المطاعمُ — الطاولاتُ وطلباتُها
          'table_sections', 'restaurant_tables', 'table_orders',
          'table_order_items', 'table_reservations', 'table_order_payments',
          // المطبخُ — أوامرُ التحضير ومحطّاتُها
          'kitchen_stations', 'category_station_mappings',
          'work_orders', 'work_order_items',
          // الحجوزاتُ — الموارد والخدمات والتذكيرات
          'booking_resources', 'booking_services', 'bookings',
          'booking_reminders',
          // التوزيعُ — خطوطُ السير وزياراتُها وتحصيلاتُ المندوبين
          'sales_routes', 'route_visits', 'sales_rep_targets',
          'sales_rep_collections',
        ];

        for (final t in phase3Tables) {
          // ١. المعرّفُ العالميّ — عمودٌ عاديٌّ ثمّ فهرسٌ فريدٌ جزئيّ.
          try {
            await m.database.customStatement(
              'ALTER TABLE $t ADD COLUMN global_id TEXT',
            );
          } catch (e) {
            debugPrint('[Migration] v167 ADD $t.global_id (safe-skip): $e');
          }
          try {
            await m.database.customStatement(
              'CREATE UNIQUE INDEX IF NOT EXISTS idx_${t}_global_id '
              'ON $t(global_id) WHERE global_id IS NOT NULL',
            );
          } catch (e) {
            debugPrint('[Migration] v167 IX $t.global_id (safe-skip): $e');
          }

          // ٢. تعبئةُ الصفوفِ القائمة — **قبلَ** المُشغِّل عمداً.
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
            debugPrint('[Migration] v167 backfill $t.global_id (safe-skip): $e');
          }

          // ٣. أعمدةُ الدلتا الأربعة.
          for (final ddl in [
            'ALTER TABLE $t ADD COLUMN last_modified_at INTEGER',
            'ALTER TABLE $t ADD COLUMN deleted_at INTEGER',
            'ALTER TABLE $t ADD COLUMN origin_client_id TEXT',
            'ALTER TABLE $t ADD COLUMN row_version INTEGER NOT NULL DEFAULT 0',
          ]) {
            try {
              await m.database.customStatement(ddl);
            } catch (_) {} // safe-skip: العمودُ موجودٌ سلفاً
          }

          // ٤. مُشغِّلُ رفعِ النسخة.
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
            debugPrint('[Migration] v167 trigger $t: $e');
          }
        }

        debugPrint(
          '[Migration] v167: أعمدةُ المزامنة على '
          '${phase3Tables.length} جدولاً تشغيليّاً',
        );
      });
    }

    // ═══════════════════════════════════════════════════════════════════
    // v168 — إهلاكُ الأصول يُرحَّل كلَّ شهرٍ لا شهراً واحداً ثمّ صمت
    // ═══════════════════════════════════════════════════════════════════
    //
    // 🔴 كشفته مصالحةُ الأصول في المرحلة ٤، ولا يظهر في أيّ اختبارِ وحدة.
    //
    // فهرسُ v120 `idx_je_autopost_dedup` فريدٌ على
    // `(reference_type, reference_id)` للقيود التلقائيّة، ويستثني أنواعاً
    // تُنتج قيداً لكلِّ حدث. و`asset_depreciation` **لم يكن** منها بينما
    // `referenceId` فيه رقمُ الأصل **بلا فترة**.
    //
    // فالنتيجةُ قبلَ هذه الخطوة: أصلٌ يُهلَك شهريّاً يُرحَّل في شهره الأوّل
    // فقط، ويُبتلَع كلُّ شهرٍ تالٍ بحجّة التكرار — بينما صفُّ
    // `asset_depreciations` يُكتَب والبطاقةُ تتقدّم. مجمَّعُ الإهلاك في
    // الأستاذ يتجمّد، فالأصولُ مضخَّمةٌ في الميزانيّة ومصروفُ الإهلاك
    // منقوصٌ في قائمة الدخل — وضريبةُ دخلٍ على أساسٍ خاطئ.
    //
    // ⚠️ **ورفعُ الحارس البرمجيِّ وحدَه لا يكفي بل يزيد الطينَ بلّة:**
    //    القيدُ يمرّ الحارسَ ثمّ يصطدم بالفهرس بـ`UNIQUE constraint
    //    failed`، و`runMonthlyDepreciation` يلتقط الاستثناءَ لكلِّ أصلٍ
    //    ويتخطّاه، فتتراجع المعاملةُ كلُّها — لا قيدَ ولا صفَّ إهلاكٍ ولا
    //    بطاقةً متقدّمة. أي أنّ الإهلاكَ **يتوقّف** بدل أن يُنقَص، و
    //    المصالحةُ تمرّ خضراءَ لأنّ الطرفَين تساويا عند الرقم الخاطئ.
    //    فالطرفان يُصلَحان معاً أو لا يُصلَح أحدُهما.
    //
    // و`DROP` ثمّ `CREATE` لأنّ `CREATE ... IF NOT EXISTS` لا يبدّل شكلَ
    // فهرسٍ قائم — نفسُ صيغةِ v150 حرفاً.
    if (from < 168) {
      await _safeMigrate('v168 إعفاءُ الإهلاك من فهرس إزالة التكرار', () async {
        await m.database
            .customStatement('DROP INDEX IF EXISTS $kJeAutopostDedupIndexName');
        await m.database.customStatement(kCreateJeAutopostDedupIndexSql);
        debugPrint('[Migration] v168: الإهلاكُ صار يُرحَّل شهريّاً');
      });
    }

    if (from < 169) {
      await _safeMigrate('v169 نموذجُ النطاقات ورابطاتُ القوالب', () async {
        // ── لماذا ALTER خامٌّ لا m.addColumn ─────────────────────────────
        // نفسُ نمطِ ما سبقه في هذا الملفّ: كلُّ عبارةٍ في try مستقلٍّ، فعمودٌ
        // موجودٌ سلفاً لا يوقف البقيّة. والأعمدةُ **مُعلَنةٌ أيضاً في أصناف
        // الجداول**، فالتنصيبُ الجديدُ يأخذها من onCreate — والإعلانُ في
        // مكانٍ واحدٍ فقط هو كيف غاب approved_by عن كلِّ قاعدةٍ جديدة.
        //
        // وكلُّها بلا افتراضٍ عمداً: الصفرُ موضعٌ حقيقيٌّ عند الحافّة، و
        // null وحدَها تقول «لم يُهاجَر بعد».
        for (final ddl in [
          'ALTER TABLE invoice_template_elements ADD COLUMN band_id TEXT',
          'ALTER TABLE invoice_template_elements ADD COLUMN x_mm REAL',
          'ALTER TABLE invoice_template_elements ADD COLUMN y_mm REAL',
          'ALTER TABLE invoice_template_elements ADD COLUMN w_mm REAL',
          'ALTER TABLE invoice_template_elements ADD COLUMN h_mm REAL',
          'ALTER TABLE invoice_template_elements ADD COLUMN condition TEXT',
          'ALTER TABLE invoice_templates '
              'ADD COLUMN layout_version INTEGER NOT NULL DEFAULT 1',
          "ALTER TABLE invoice_table_settings "
              "ADD COLUMN table_kind TEXT NOT NULL DEFAULT 'items'",
          'ALTER TABLE invoice_table_settings ADD COLUMN columns_json TEXT',
        ]) {
          try {
            await m.database.customStatement(ddl);
          } catch (e) {
            debugPrint('[Migration] v169 (safe-skip): $e');
          }
        }

        // جدولُ الرابطات. تمريرةُ `allSchemaEntities` في ensureSchemaDefaults
        // تغطّيه كذلك على كلِّ إقلاع، وهذا صريحٌ لئلّا يعتمد إنشاؤه على أثرٍ
        // جانبيٍّ في مكانٍ آخر.
        try {
          await m.createTable(templateBindings);
        } catch (e) {
          debugPrint('[Migration] v169 template_bindings (safe-skip): $e');
        }

        debugPrint('[Migration] v169: النطاقاتُ والرابطاتُ جاهزة');
      });
    }

    if (from < 170) {
      await _safeMigrate('v170 ارتفاعاتُ النطاقات تُحفَظ', () async {
        // ── لماذا عمودٌ أصلاً ──────────────────────────────────────────
        // كان ارتفاعُ النطاق مشتقّاً — أبعدُ قاعِ عنصرٍ فيه. فزرّا `+`/`−`
        // في لوحة «ارتفاع النطاق» يعملان في الجلسة ثمّ يعود الرقمُ عند
        // إعادة الفتح، والحشوةُ السفليّةُ التي يطلبها التصميمُ لا مكانَ لها.
        //
        // ⚠️ **ومُعلَنٌ في صنف الجدول كذلك** (`InvoiceTemplates.bandHeights`):
        //    الإعلانُ في مكانٍ واحدٍ فقط هو كيف غاب `approved_by` عن كلِّ
        //    قاعدةٍ جديدة — `onCreate` يبني من كيانات drift لا من هذه الخطوة.
        //
        // و`null` بلا افتراضٍ عمداً: تعني «اشتقّ كما كنتَ تفعل»، لا صفراً.
        // القوالبُ القائمةُ كلُّها ستقرؤها فارغةً فتبقى على سلوكها.
        try {
          await m.database.customStatement(
            'ALTER TABLE invoice_templates ADD COLUMN band_heights TEXT',
          );
        } catch (e) {
          debugPrint('[Migration] v170 (safe-skip): $e');
        }
        debugPrint('[Migration] v170: ارتفاعُ النطاق صار يُحفَظ');
      });
    }

    if (from < 171) {
      await _safeMigrate('v171 فرقُ تقريب الإجماليّ', () async {
        // ── لماذا عمودٌ لا اشتقاق ──────────────────────────────────────
        // سياسةُ `pos_total_rounding` تُقرِّب **المقبوض** ويبقى `total`
        // حقيقيّاً. والفرقُ بينهما ليس ديناً على العميل — فبلا عمودٍ يحمله
        // كانت الفاتورةُ تُقرأ `pending` إلى الأبد، أو يُرمى القيدُ كلُّه
        // بـ«المدين لا يساوي الدائن» بعدما خرج المخزونُ ودخل النقدُ الدرجَ
        // فعلاً (‏المقبوضُ صعوداً)، أو تُفتح ذمّةٌ وهميّةٌ على حساب المراقبة
        // لزبونٍ عابرٍ بلا حسابٍ فرعيّ (‏هبوطاً).
        //
        // ⚠️ **ومُعلَنٌ في صنف الجدول كذلك** (`SalesInvoices.roundingAdjustment`):
        //    الإعلانُ في مكانٍ واحدٍ فقط هو كيف غاب `approved_by` عن كلِّ
        //    قاعدةٍ جديدة — `onCreate` يبني من كيانات drift لا من هذه الخطوة.
        //
        // و`NOT NULL DEFAULT 0` لا nullable: صفرٌ يعني «بلا تقريب»، وهو
        // الحقُّ حرفيّاً لكلِّ فاتورةٍ سابقةٍ — فالسياسةُ لم تكن تعمل أصلاً.
        // فلا تكتب الهجرةُ صفّاً واحداً ويبقى سلوكُ ما قبلَها حرفيّاً.
        try {
          await m.database.customStatement(
            'ALTER TABLE sales_invoices '
            'ADD COLUMN rounding_adjustment REAL NOT NULL DEFAULT 0',
          );
        } catch (e) {
          debugPrint('[Migration] v171 (safe-skip): $e');
        }
        debugPrint('[Migration] v171: فرقُ التقريب صار له عمودٌ صريح');
      });
    }

    if (from < 172) {
      await _safeMigrate('v172 مستندُ مرتجع المشتريات', () async {
        // §٦‑٢ — الطرفُ الثاني الغائبُ في تسوية ض.ق.م.
        //
        // مرتجعُ الشراء كان بلا صفٍّ في أيِّ جدولِ مستندات، فضريبتُه تُشتقّ
        // من الأستاذ نفسِه ⇒ الطرفان يقرآن مصدراً واحداً ويتّفقان بالبناء.
        //
        // ⚠️ **ومُعلَنٌ في `@DriftDatabase` كذلك** (`PurchaseReturns`):
        //    `onCreate` يبني من كيانات drift لا من هذه الخطوة، والإعلانُ في
        //    مكانٍ واحدٍ فقط هو كيف غاب `approved_by` عن كلِّ قاعدةٍ جديدة.
        //    فالخطوةُ هنا للقواعد المُرقّاة وحدَها، والكيانُ للجديدة.
        //
        // و`createTable` تُولّد `CREATE TABLE IF NOT EXISTS`، فهي no-op على
        // قاعدةٍ نالته من `createAll`.
        try {
          await m.createTable(purchaseReturns);
        } catch (e) {
          debugPrint('[Migration] v172 (safe-skip): $e');
        }
        debugPrint('[Migration] v172: مرتجعُ الشراء صار مستنداً بضريبته');
      });
    }

    // ═══════════════════════════════════════════════════════════════════
    // v173 — المرحلة ٤: أعمدةُ المزامنة للسجلِّ الرقابيِّ والتشغيلِ العابر
    // ═══════════════════════════════════════════════════════════════════
    //
    // ═══ العطبُ الذي تسدّه ═══
    //
    // ستّةٌ وعشرون جدولاً كانت محلّيّةً بالكامل وحكمُها في
    // `sync_coverage_guard_test` 🔴 «يجب أن تُزامَن»:
    //
    //   • **سجلٌّ قانونيٌّ ورقابيّ** — تقديماتُ الفاتورة الإلكترونيّة وسجلُّ
    //     حالاتها، وسجلُّ تغييرات الحقول، وفشلُ الترحيل، وسيرُ الاعتماد
    //     بطلباته وقراراته، وتعارضاتُ فصل المهامّ وانتهاكاتُها، وفحوصُ
    //     الامتثال. ضياعُ الجهاز ضياعُ الإثبات، ولا يُعاد بناؤه.
    //   • **تشغيلٌ عابرٌ للأجهزة** — الجردُ الدوريُّ وجردُ المخزون وطلباتُ
    //     الصرف، ونقاطُ الولاء، وشركاتُ التوصيل ومندوبوها، والمطابقةُ
    //     البنكيّةُ بأسطر كشفها، وأسعارُ المخازن. جهازٌ يطابق كشفاً لا يراه
    //     جهازٌ آخرُ فيطابقه ثانية.
    //
    // ⚠️ و`e_invoice_configs` **مستثنًى عمداً**: يحمل `client_secret` نصّاً،
    //    ومسارُ السحب يُرسل `SELECT *`. استبعادُ العمود على السلك يُسقط
    //    الإدراجَ على العميل (‏`NOT NULL` بلا افتراض) صامتاً، وإرسالُ قيمةٍ
    //    بديلةٍ يدهس سرَّ العميل المحلّيَّ بـ`INSERT OR REPLACE`. فبقاؤه
    //    محلّيّاً هو الحكمُ المكتوبُ في الحارس، لا سهو.
    //
    // ═══ الصيغةُ نسخةُ v167 حرفاً ═══
    //
    // عمودٌ عاديٌّ + فهرسٌ فريدٌ جزئيّ (‏`ADD COLUMN … UNIQUE` مرفوضةٌ في
    // SQLite)، وتعبئةٌ بـ`UuidV7` **قبلَ** المُشغِّل، ومُشغِّلٌ يرفع
    // `row_version` بحارسِ `WHEN` يمنع الدور.
    //
    // ⚠️ و`stock_requisitions` لها `global_id` وفهرسُه منذ v149 — الـsafe-skip
    //    يتكفّل بهما والتعبئةُ تملأ الفارغَ وحدَه. و`e_invoice_status_log`
    //    كانت جدولاً بلا كيانٍ (٦‑١) وصارت كياناً في v173، فهذه الخطوةُ
    //    تُلحِق الأعمدةَ بالقواعد المُرقّاة و`createAll` يبنيها للجديدة.
    if (from < 173) {
      await _safeMigrate('v173 أعمدةُ مزامنةٍ للسجلِّ الرقابيِّ والتشغيلِ العابر',
          () async {
        const phase4Tables = [
          // التشغيلُ العابرُ للأجهزة
          'loyalty_programs', 'delivery_companies', 'couriers',
          'customer_loyalty_points', 'loyalty_transactions',
          'warehouse_prices',
          'cycle_count_plans', 'cycle_count_tasks', 'cycle_count_items',
          'stock_audits', 'stock_audit_items',
          'stock_requisitions', 'stock_requisition_items',
          'bank_reconciliations', 'bank_statement_lines',
          // السجلُّ القانونيُّ والرقابيّ
          'e_invoice_submissions', 'e_invoice_status_log',
          'field_audit_logs', 'failed_autoposts',
          'approval_workflows', 'approval_steps', 'approval_requests',
          'approval_decisions', 'sod_conflicts', 'sod_violations',
          'compliance_checks',
        ];

        for (final t in phase4Tables) {
          // ١. المعرّفُ العالميّ — عمودٌ عاديٌّ ثمّ فهرسٌ فريدٌ جزئيّ.
          try {
            await m.database.customStatement(
              'ALTER TABLE $t ADD COLUMN global_id TEXT',
            );
          } catch (e) {
            debugPrint('[Migration] v173 ADD $t.global_id (safe-skip): $e');
          }
          try {
            await m.database.customStatement(
              'CREATE UNIQUE INDEX IF NOT EXISTS idx_${t}_global_id '
              'ON $t(global_id) WHERE global_id IS NOT NULL',
            );
          } catch (e) {
            debugPrint('[Migration] v173 IX $t.global_id (safe-skip): $e');
          }

          // ٢. تعبئةُ الصفوفِ القائمة — **قبلَ** المُشغِّل عمداً.
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
            debugPrint('[Migration] v173 backfill $t.global_id (safe-skip): $e');
          }

          // ٣. أعمدةُ الدلتا الأربعة.
          for (final ddl in [
            'ALTER TABLE $t ADD COLUMN last_modified_at INTEGER',
            'ALTER TABLE $t ADD COLUMN deleted_at INTEGER',
            'ALTER TABLE $t ADD COLUMN origin_client_id TEXT',
            'ALTER TABLE $t ADD COLUMN row_version INTEGER NOT NULL DEFAULT 0',
          ]) {
            try {
              await m.database.customStatement(ddl);
            } catch (_) {} // safe-skip: العمودُ موجودٌ سلفاً
          }

          // ٤. مُشغِّلُ رفعِ النسخة.
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
            debugPrint('[Migration] v173 trigger $t: $e');
          }
        }

        debugPrint(
          '[Migration] v173: أعمدةُ المزامنة على '
          '${phase4Tables.length} جدولاً رقابيّاً وتشغيليّاً',
        );
      });
    }
    // ═══════════════════════════════════════════════════════════════════
    // v174 — بنيةُ إعادة تصميم الشاشات (بلاغُ المالك 2026-09-18)
    // ═══════════════════════════════════════════════════════════════════
    //
    // ⚠️ **ولمن هذه الكتلة؟ لعملاء SQLite وحدَهم.**
    //
    // ثلاثةُ مسالكَ تصل الجداولَ الجديدة، وهذا أضيقُها:
    //   • تنصيبةٌ جديدة  ⇒ `onCreate` يبني من كيانات drift مباشرةً
    //   • خادمُ PostgreSQL ⇒ مُصحِّحُ التكافؤ يُنشئ الناقصَ عند الإقلاع
    //                       (`[PG-PARITY-HEAL] action=created`) — مقيسٌ في
    //                       لوج الميدان لا مفترَض
    //   • عميلُ SQLite قائم ⇒ **هنا**، ولا مسلكَ له غيرُها
    //
    // ولهذا لا يُستغنى عنها بحجّة أنّ الخادمَ يُصلح نفسَه.
    if (from < 174) {
      await _safeMigrate('v174 جداولُ وأعمدةُ إعادة تصميم الشاشات', () async {
        // ─── أوّلاً: الجداولُ الأربعةُ الجديدة ───────────────────────────
        //
        // `createTable` تُولّد `CREATE TABLE IF NOT EXISTS`، فهي بلا أثرٍ على
        // قاعدةٍ نالتها من `createAll` — ولذلك تُنفَّذ بلا شرط.
        for (final entry in <String, TableInfo>{
          'asset_disposals': assetDisposals,
          'cheque_books': chequeBooks,
          'floor_plan_items': floorPlanItems,
          'import_purchase_details': importPurchaseDetails,
        }.entries) {
          try {
            await m.createTable(entry.value);
          } catch (e) {
            debugPrint('[Migration] v174 ${entry.key} (safe-skip): $e');
          }
        }

        // ─── ثانياً: الأعمدةُ الخمسةَ عشرَ ──────────────────────────────
        //
        // ⚠️ **ولا عمودَ `UNIQUE` بينها عمداً**: SQLite ترفض
        // `ADD COLUMN ... UNIQUE` على جدولٍ قائم، وهي مصيدةٌ قتلت الإقلاعَ في
        // v132 — انظر `isIdempotentMigrationError`.
        //
        // و`NOT NULL` مقبولةٌ ما دام لها `DEFAULT`، فالصفوفُ القائمةُ تُملأ.
        const columns = <String, List<String>>{
          'table_sections': [
            'canvas_width REAL',
            'canvas_height REAL',
            'origin_x REAL',
            'origin_y REAL',
            'sort_order INTEGER NOT NULL DEFAULT 0',
            'color TEXT',
          ],
          'restaurant_tables': [
            'width REAL',
            'height REAL',
            'rotation REAL NOT NULL DEFAULT 0',
          ],
          'fixed_assets': ['custodian_user_id INTEGER'],
          'commercial_papers': [
            'source_voucher_id INTEGER',
            'cheque_book_id INTEGER',
          ],
          'journal_entries': ['reference TEXT'],
          'purchase_invoices': [
            'currency_id INTEGER',
            'exchange_rate REAL',
          ],
        };

        for (final table in columns.entries) {
          for (final col in table.value) {
            try {
              await m.database.customStatement(
                'ALTER TABLE ${table.key} ADD COLUMN $col',
              );
            } catch (e) {
              debugPrint(
                '[Migration] v174 ${table.key}.$col (safe-skip): $e',
              );
            }
          }
        }

        debugPrint('[Migration] v174: أربعةُ جداولَ وخمسةَ عشرَ عموداً');
      });
    }

    // ⚠️ كتلتا v174 أدناه من **فرعَين مختلفَين** دُمِجا في 2026-09-20:
    //   • الأولى أعلاه — جداولُ وأعمدةُ إعادة تصميم الشاشات.
    //   • وهذه — إعفاءُ نقلِ الأصل من فهرس إزالة التكرار.
    // وهما مستقلّتان (جداولٌ مقابلَ فهرسٍ)، وكلٌّ منهما تحمل حارسَها
    // `from < 174` بنفسِها — فلا تُدمجان في كتلةٍ واحدة: إخفاقُ
    // إحداهما تحت `_safeMigrate` كان سيبتلع الأخرى معها.

    // ═════════════════════════════════════════════════════════════════════
    // v174 — إعفاءُ نقلِ الأصل وإعادةِ تقييمه من فهرس إزالة التكرار
    //
    // نفسُ فئةِ عطبِ v168 بمفتاحٍ آخر: `asset_transfer` مفتاحُه رقمُ الأصل
    // **بلا وجهة**، فالنقلةُ الأولى تُرحَّل وكلُّ نقلةٍ تاليةٍ لنفس الأصل
    // تُعَدّ تكراراً فتُبتلَع — والأستاذُ يُبقي القيمةَ في المركز الوسيط إلى
    // الأبد بينما البطاقةُ تتقدّم. و`asset_revaluation` نفسُ الشكل.
    //
    // والقائمتان تُرفعان معاً — الحارسُ البرمجيُّ في `createJournalEntry`
    // والـ`NOT IN` في الفهرس — وإلّا مرّ القيدُ الحارسَ واصطدم بالفهرس
    // بـ`UNIQUE constraint failed`، وهو ما وقع في v168 حرفاً.
    // و`e_je_dedup_lockstep_test.dart` يثبّت التطابق.
    //
    // و`DROP` ثمّ `CREATE` لأنّ `CREATE ... IF NOT EXISTS` لا يبدّل شكلَ
    // فهرسٍ قائم — نفسُ صيغةِ v150 وv168 حرفاً.
    // ═════════════════════════════════════════════════════════════════════
    if (from < 174) {
      await _safeMigrate('v174 إعفاءُ نقلِ الأصل وتقييمه من فهرس إزالة التكرار',
          () async {
        await m.database
            .customStatement('DROP INDEX IF EXISTS $kJeAutopostDedupIndexName');
        await m.database.customStatement(kCreateJeAutopostDedupIndexSql);
        debugPrint('[Migration] v174: نقلةُ الأصل الثانيةُ صارت تُرحَّل');
      });
    }

    // ═══════════════════════════════════════════════════════════════════
    // v175 — قاعدةُ حسابِ `sales_invoices.paid`
    // ═══════════════════════════════════════════════════════════════════
    //
    // قرارُ المالك 2026-09-19 (الخيار أ): `paid` يُبنى من قاعدةٍ مخزَّنةٍ
    // زائدَ مجموعِ التخصيصات — راجع شرحَ `paidUnallocated`.
    //
    // 🔴 **والملءُ أهمُّ من الإضافة.** عمودٌ يُضاف بـ`DEFAULT 0` يجعل كلَّ
    // فاتورةٍ قائمةٍ تقول «لم يُسدَّد منّي شيءٌ خارجَ التخصيصات» — وهو كذبٌ
    // على كلّ تاريخِ التنصيبة. وأوّلُ إعادةِ حسابٍ بعدها تُصفِّر `paid` لكلّ
    // ما مضى.
    //
    // والملءُ `paid_unallocated = paid` **صحيحٌ حرفيّاً اليوم**: جدولُ
    // التخصيصات بلا كاتبٍ واحدٍ في `lib/` (مقيسٌ)، فكلُّ قرشٍ مسجَّلٍ في
    // `paid` وقع خارجَ تخصيص. ولو وُصِل الكاتبُ قبلَ هذه الهجرةِ لصار الملءُ
    // يضاعف المخصَّص — ولذلك العمودُ والكاتبُ في كوميتٍ واحد.
    if (from < 175) {
      await _safeMigrate('v175 قاعدةُ حسابِ المسدَّد', () async {
        try {
          await m.database.customStatement(
            'ALTER TABLE sales_invoices '
            'ADD COLUMN paid_unallocated REAL NOT NULL DEFAULT 0',
          );
        } catch (e) {
          debugPrint('[Migration] v175 paid_unallocated (safe-skip): $e');
        }

        // الملءُ يُنفَّذُ **على كلّ حال**، لا داخلَ `catch` الإضافة: قاعدةٌ
        // نالت العمودَ من `createAll` تحتاجُ الملءَ أيضاً لو حملت صفوفاً
        // (مرآةٌ مُزامَنةٌ مثلاً)، وهو بلا أثرٍ على الفارغة.
        try {
          await m.database.customStatement(
            'UPDATE sales_invoices SET paid_unallocated = paid '
            'WHERE paid_unallocated = 0 AND paid <> 0',
          );
        } catch (e) {
          debugPrint('[Migration] v175 backfill (safe-skip): $e');
        }

        debugPrint('[Migration] v175: paid_unallocated + ملءٌ');
      });
    }

    // ══════════════════════════════════════════════════════════════════
    // v176 — المرفقات (§٨ من خطّة إعادة تصميم الشاشات)
    // ══════════════════════════════════════════════════════════════════
    //
    // جدولان: `attachments` الوصفُ (يُزامَن)،
    // و`attachment_blobs` البايتاتُ (خارجَ كلِّ قائمةِ سحبٍ عمداً).
    //
    // ⚠️ **ولمن هذه الكتلة؟ لعملاء SQLite القائمين وحدَهم** —
    //    التنصيبةُ الجديدةُ تنالُهما من `onCreate`، والخادمُ
    //    من مُصحِّح التكافؤ عند الإقلاع.
    if (from < 176) {
      await _safeMigrate('v176 جدولا المرفقات', () async {
        for (final entry in <String, TableInfo>{
          'attachments': attachments,
          'attachment_blobs': attachmentBlobs,
        }.entries) {
          try {
            await m.createTable(entry.value);
          } catch (e) {
            debugPrint('[Migration] v176 ${entry.key} (safe-skip): $e');
          }
        }
        debugPrint('[Migration] v176: جدولا المرفقات');
      });
    }

    // ═══════════════════════════════════════════════════════════════════
    // v177 — إعفاءُ إعادةِ ترحيلِ البيع بعد تعديلٍ مُجاز
    // ═══════════════════════════════════════════════════════════════════
    // البيعُ قد يحمل قيوداً تلقائيّةً عدّةً عبر عمر الفاتورة: الأصلي ثمّ
    // إعادةُ الترحيل بعد عكسه. تفرّدُ كلّ حدثٍ محمولٌ على `global_id`.
    if (from < 177) {
      await _safeMigrate('v177 sale-repost autopost dedup index', () async {
        await m.database
            .customStatement('DROP INDEX IF EXISTS $kJeAutopostDedupIndexName');
        await m.database.customStatement(kCreateJeAutopostDedupIndexSql);
        debugPrint('[Migration] v177: sale reposts exempted from dedup index');
      });
    }

    // v178 — reassert the salary-payment database guard on upgraded stores.
    if (from < 178) {
      await _safeMigrate('v178 salary payment dedup guard', () async {
        await m.database.customStatement(kCreateSalaryPaymentDedupIndexSql);
        debugPrint('[Migration] v178: salary payment dedup guard verified');
      });
    }

    // ═══════════════════════════════════════════════════════════════════
    // v179 — فروق صرف التسوية وإعادة التقييم
    // ═══════════════════════════════════════════════════════════════════
    if (from < 179) {
      await _safeMigrate('v179 أعمدة فروق الصرف', () async {
        const columns = <String, List<String>>{
          'parties': [
            'currency_id INTEGER REFERENCES currencies(id)',
          ],
          'sales_invoices': [
            'currency_id INTEGER REFERENCES currencies(id)',
            'exchange_rate REAL',
          ],
          'safe_transactions': [
            'currency_id INTEGER REFERENCES currencies(id)',
            'exchange_rate REAL',
            'foreign_amount REAL',
          ],
        };
        for (final table in columns.entries) {
          for (final column in table.value) {
            try {
              await m.database.customStatement(
                'ALTER TABLE ${table.key} ADD COLUMN $column',
              );
            } catch (e) {
              debugPrint('[Migration] v179 ${table.key}.$column (safe-skip): $e');
            }
          }
        }
      });
    }

    // ═══════════════════════════════════════════════════════════════════
    // v180 — BOM costing, output weights, and carcass breakdown
    // ═══════════════════════════════════════════════════════════════════
    if (from < 180) {
      await _safeMigrate('v180 manufacturing raw schema', () async {
        for (final statement in [
          ..._manufacturingV180CreateStatements,
          ..._manufacturingV180ColumnStatements,
          ..._manufacturingV180IndexStatements,
        ]) {
          try {
            await m.database.customStatement(statement);
          } catch (error) {
            if (!isIdempotentMigrationError(error.toString())) rethrow;
          }
        }
        await ensureManufacturingV180Schema();
        await recalculateStoredBomCosts();
      });
    }

    // v181 — raw LAN pairing registry (kept outside Drift codegen).
    if (from < 181) {
      await _safeMigrate('v181 LAN pairing registry', ensureLanPairingSchema);
    }

    // v182 — products.tax_exempt: the product form's «معفى من الضريبة» flag
    // (raw column; tax calculation keeps reading tax_rate only).
    if (from < 182) {
      await _safeMigrate(
          'v182 products.tax_exempt', ensureProductTaxExemptSchema);
    }
  }
}
