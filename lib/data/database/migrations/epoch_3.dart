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
          ('كاشير', 'نقطة البيع فقط'),
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

    if (from < 154) {
      await _safeMigrate('v154 نقلُ إغلاق الوردية إلى فئة الخزينة', () async {
        // شاشةُ الصلاحيات تقرأ الفئةَ من **صفّ القاعدة** لا من
        // `PermissionCodes.masterList` (‏`authRepo.getAllPermissions()`)،
        // و`syncAllPermissions` يتخطّى أيَّ كودٍ موجودٍ سلفاً
        // (`if (existingCodes.contains(...)) continue`). فبلا هذه الجملة
        // تبقى الصلاحيةُ في «نقطة البيع» إلى الأبد على كلّ قاعدةٍ منصَّبة —
        // أيْ في المكان الذي طلب المالكُ إخراجَها منه.
        //
        // والصلاحيةُ نفسُها لا تُمنح ولا تُنزع هنا: الفئةُ تبويبٌ في شاشة
        // الأدوار، لا إذن.
        await m.database.customStatement(
          "UPDATE permissions SET category = 'treasury' "
          "WHERE code = 'pos_shift_close'",
        );
        debugPrint('[Migration] v154 pos_shift_close → treasury OK');
      });
    }
  }
}
