part of '../database.dart';

/// Epoch 3 migration steps v81–v93 (pure move out of `epoch_3.dart`;
/// no behaviour change). Called in order by `_migrateEpoch3`.
///
/// Runs first: the v103 `parties.account_id` step (moved here from epoch 2,
/// B-MIG-1) executes before v81 — order preserved verbatim.
///
extension Epoch3MigrationsV081ToV093 on AppDatabase {
  Future<void> _migrateEpoch3V081ToV093(Migrator m, int from) async {
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
  }
}
