# Axis B — Test evidence

**Version:** `d69be1eafc7d82b924723dfdbb53960b7e33acdb`. **Auditor constraint:** no `flutter`/`dart` command could be run (other workers hold locks). Opening the user's DB was not attempted: it is SQLCipher-encrypted, and reading it is out of scope.

## 1. Commands this auditor actually executed (all read-only)

| # | Command | Result |
|---|---|---|
| 1 | `git rev-parse HEAD; git branch --show-current; git status --short; git log --oneline -5` | HEAD `d69be1ea…`, branch `feat/tables-reservations-permissions`. Only untracked files are present (listed in the baseline). |
| 2 | `git log -1 --format='%H %cd'` | Commit date 2026-10-23 03:08:46 +0300. |
| 3 | `Get-Content D:\qa\logs4\_summary.txt` and the tails of `S0…S6` logs | See §2. |
| 4 | `Select-String pubspec.lock` (drift entry) | drift **2.32.1** locked. |
| 5 | Read the drift 2.32.1 package source (`engines.dart:480-531`, `db_base.dart:116-139`, `migration.dart:621`, `sqlite3/database.dart:107,198`) | Confirms MIG-001 and MIG-002 (no wrapping transaction; `onUpgrade` runs on `from > to`; version stamped after `beforeOpen`). |
| 6 | Counts via `Get-ChildItem`/`Select-String` (tables, DAOs, migration files, test files) | 167 tables, 134 DAO files, 12 epoch files. Tests: unit 691, integration 160, integration_pg 26, scenarios 14, structural 117, widget 264, data 33 files. |
| 7 | Grep/Read over `lib/` and `test/` (file:line cited in FINDINGS-B.md) | Static evidence for every finding. |

I added no tests or scripts, created no repro tooling, and modified no product file.

## 2. Prior run evidence (read, not re-run)

Source: `D:\qa\logs4\_summary.txt` (run 2026-10-21 01:45–02:53 local).

| Stage | Logged result | Status for this audit |
|---|---|---|
| S0 analyze | exit 0, "2 issues found" (info level: `use_build_context_synchronously` in `sales_returns_picpos_logic.dart:84` …) | PASS (prior run) |
| S1 main suite | `+10018 ~19: All other tests passed!` | PASS (prior run) |
| S2 scenarios | `+61 ~1` passed | PASS (prior run) |
| S3 integration | `+1018 ~27` passed | PASS (prior run) |
| S4 brand guard | `+13` passed | PASS (prior run) |
| S5 E2E | `نجح 48 · تخطّى 7 · فشل 0` | PASS (prior run) |
| S6 PostgreSQL `integration_pg` | `+92: All tests passed!` (postgres container) | PASS (prior run) |

**Caveat:** the logs carry no commit SHA, and they pre-date the HEAD commit timestamp by about two days. I could not verify that the tested tree is byte-identical to HEAD; `FINAL-QA-VERDICT.md` asserts it was the "final tree". Treat these runs as **evidence for a near-HEAD tree**, not as proof for HEAD.

Skipped tests (19 + 1 + 27 + 7) were not inventoried for axis-B relevance (NOT_RUN).

## 3. Existing tests relevant to axis B (inventory; executed only inside the prior run above)

| Area | Test files (examples) | What they do NOT cover |
|---|---|---|
| Double-entry / posting | `test/scenarios/sc_k_trial_balance_test.dart`, `sc_b_credit_sale_receipts_test.dart`, `sc_c_sales_return_void_test.dart`, `sc_d_purchase_cycle_test.dart`, `test/unit/e_je_dedup_lockstep_test.dart` | Fault injection between invoice commit and JE (DATA-005) |
| Party balances | `test/integration/party_balance_reconciliation_test.dart`, `test/integration/account_subtree_rollup_test.dart` | Re-import overwrite (DATA-003), inactive customer in AR reconciliation (ACC-007) |
| Party statement | `test/unit/party_statement_queries_test.dart`, `party_statement_branch_scope_test.dart`, widget tests | Voided/soft-deleted rows (RPT-001): grep finds no `voided`/`isDeleted` |
| Aging | `test/unit/aging_follows_due_date_test.dart`, `ar_aging_branch_scope_test.dart`, `test/data/analytics/aged_reports_scope_test.dart`, `integration_pg/financial_analytics_pg_test.dart` (`getAgedReceivables` only) | `getArAgingReport` on PG (RPT-003); as-of paid and returned purchases (RPT-002) |
| Inventory ↔ GL | `test/integration/inventory_gl_reconciliation_test.dart`, `test/unit/go_blockers_wac_gl_tie_test.dart`, `inventory_gl_reconciliation_alert_test.dart` | — |
| Depreciation | `test/integration/accounting_e2e_suite.dart:651-695`, `test/unit/asset_depreciation_multi_month_je_test.dart`, `depreciation_math_test.dart` (domain helper, not the DAO), … | Month > life (ACC-001), missing accounts (ACC-002), same month on two dates (ACC-003) |
| Payroll | `test/integration/hr_payroll_j4_test.dart`, `integration_pg/pg_hr_payroll_pg_test.dart` | — |
| Tax | `test/unit/financial_precision_test.dart`, `phase4_precision_tax_test.dart`, `client_issue_m2_tax_report_test.dart` | Soft-deleted VAT JE (RPT-004); purchase-import tax (DATA-006) |
| Migrations | `test/integration/v196_reservation_parties_migration_test.dart`, `integration_pg/reservation_parties_backfill_pg_test.dart`, `test/unit/migration_v1xx_*`, `test/structural/migration_numbering_test.dart`, `test/unit/migration_add_unique_column_test.dart` | Real old-DB fixture (MIG-007); `from > to` (MIG-001); mid-migration failure (MIG-002) |
| PG parity | `test/unit/pg_schema_parity_static_test.dart` (source-only), `scripts/run_pg_tests.dart` (Docker `postgres:16-alpine`, `--tags pg`) | PG upgrade from an older server schema (MIG-006) |
| Backup/restore | `test/unit/pending_restore_test.dart` (fake opener), `test/integration/data_wipe_service_test.dart:656-723` (fake payload), `test/unit/db_key_boot_test.dart:309-318` (sidecars), `test/services/remote_backup_config_test.dart` (config only) | **A real encrypted restore with data verification (BKP-001)** |
| Import | Idempotent product re-import test (per `FINAL-QA-VERDICT.md`; file not located by name in this audit) | Party re-import balance, purchase tax normalisation, barcode whitespace |

## 4. Check status for axis B (this auditor)

| Check | Status | Reason |
|---|---|---|
| Static review of schema constraints, soft-delete filters, posting paths, migrations, backup and import code | PASS (performed) | Findings recorded |
| Re-run of unit, integration or PG suites | NOT_RUN | `flutter`/`dart` are forbidden for this worker (lock conflicts) |
| Repro of RPT-001, ACC-001, RPT-003, DATA-001, DATA-003, MIG-001 | NOT_RUN | Same constraint; repro steps are written in FINDINGS-B.md |
| Upgrade of a real old DB with data | NOT_RUN | Needs dart and an unencrypted or keyed fixture. The prior owner-DB upgrade v195→v196 is reported OK in `FINAL-QA-VERDICT.md` (not reproduced) |
| Real backup → restore drill | NOT_RUN | Needs app runtime; BKP-001 |
| Inspection of the user's SQLCipher DB | NOT_APPLICABLE | Encrypted; prohibited by the task |
| PG execution of `getArAgingReport` | NOT_RUN | Needs a Docker/PG run; the static derivation is in RPT-003 |
| Performance of migrations or backfill on large data | NOT_RUN | Out of the static scope |
