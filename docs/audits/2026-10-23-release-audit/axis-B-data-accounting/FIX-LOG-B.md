# Axis B — fix log (data / accounting / reports / migrations / backup)

Branch `feat/tables-reservations-permissions`, on top of `aa4e8be5`. Uncommitted (the lead commits).
Every fix has a test that was written first and seen failing (unless noted). Real SQLCipher run:
`tool/run_sqlcipher_tests.ps1 test/integration/backup_restore_drill_real_test.dart`.

| ID | Status | Fix | Test |
|---|---|---|---|
| RPT-001 | fixed | statement (window + opening) and `getCalculatedPartyBalance` exclude `is_deleted`, voided/cancelled invoices and soft-deleted safe transactions | `audit_b_rpt001_statement_soft_delete_test` |
| RPT-004 | fixed | tax report (GL side), hierarchical TB, posting reconciliation (JE + invoices + orphans) honour `is_deleted`; VAT-recon purchase side skips cancelled/voided | `audit_b_rpt004_reports_filters_test` |
| RPT-005 | fixed | half-open day range (closed at 23:59:59), `paid` filtered like sales (deleted, returns negative); logic extracted to `sales_summary_queries.dart` | `audit_b_rpt005_sales_summary_test` (new function; the old query was read, not run) |
| RPT-007 | fixed (partly) | budget actuals = posted, non-deleted JEs; cash-flow forecast live invoices; purchase summary: cancelled carries no money; variance report honours `warehouseId`; cycle-count / purchase-return movements skip soft-deleted. **Not done:** `sales_analytics_dao` returns analytics (`deleted_at`) — file at its size ceiling | `audit_b_rpt004…`, `audit_b_rpt007…` |
| RPT-003 | fixed | `getArAgingReport` rewritten with epoch arithmetic + `CASE` (no julianday / scalar MAX); passes on PostgreSQL 16 | `integration_pg/audit_b_ar_aging_pg_test`, `audit_b_rpt002_ar_aging_status_test` |
| RPT-002 | fixed (b,c) / deferred (a,d,e) | returned/cancelled/voided excluded in AR and AP aging. (a) "paid as of date": invoices carry no dated payment history (cash sales set `paid` at creation, allocations exist only for some flows) — a correct as-of needs a payment ledger; (d)(e) need return netting design | same |
| ACC-001 | fixed | straight-line capped at salvage (also `depreciation_math.dart`), nothing before the in-service month. Asset status is NOT changed (`fully_depreciated` is unused by the UI filters) | `audit_b_acc001_depreciation_test` |
| ACC-002 | fixed | missing 6213/accumulated account throws inside the per-asset transaction (nothing advances); failures returned via optional `failures` list and `DepreciationResult.failures`. Note `syncDefaultAccounts()` re-creates 6213, so the reachable failure is a posting error (closed period / no fiscal year) — tested that way | same |
| ACC-003 | fixed | duplicate guard keys on the calendar month, any day | same |
| ACC-004 | fixed | deposit requires a registered customer and an existing `2134`, else the booking is rejected atomically (no `4299`, no party AR) | `audit_b_acc004_booking_deposit_test` (+ `booking_actions_service_test` now passes a party) |
| ACC-005 | fixed | main entry + reversal in one transaction; a retry mirrors the STORED main lines | `phase9_fx_test` (new case) |
| ACC-006 | fixed | manual / unknown-type cash entries are classified per entry by counter-account: equity or `22*` -> financing, `12*` -> investing, cash<->bank transfer excluded, rest operating (`cash_flow_manual_classifier.dart`). New keys `operating.otherNet/otherOperating*`, `financing.other*`. **Documented limits:** an entry mixing activities is not split; CSV/print rows of the statement do not list the new "other" lines | `audit_b_acc006_cashflow_manual_test`; `cashflow_null_reference_type_test` + PG analytics fixture now use a revenue counter (an equity counter is financing by design) |
| ACC-007 | fixed | AR reconciliation includes deactivated customers | `audit_b_acc_low_fixes_test` |
| ACC-008 | fixed | `reverseTransaction` keys each reversal on its source entry id | same |
| ACC-009 | fixed | JE number year follows the entry date. (voucher UX pre-check with `now()` left: harmless, `createJournalEntry` re-checks) | same |
| DATA-001 | fixed | reservation create / cancel / seat on a client push a global-id snapshot through CWI -> proxy -> outbox replay -> `POST /api/table-reservations`; host applies idempotently, never regresses a terminal status, answers 409+retry when the table has not arrived. **Limit:** no overlap/double-booking rule exists locally either, so none is enforced on the host | `audit_b_data001_table_reservation_sync_test`, `structural/table_reservation_push_wiring_test` (golden `api_routes.txt` updated) |
| DATA-002 | fixed | rule: the canonical key still drops the country code (F.1); two numbers that BOTH carry different explicit codes are different people, a local number matches any. `samePhone`, picker duplicate check and the v196 backfill follow it. Documented in plan §F.1 | `audit_b_data002_phone_country_test`, `audit_b_data002_backfill_country_test` |
| DATA-003 | already fixed (73257fe6) | verified by `party_import_balance_test` | existing |
| DATA-006 | fixed | purchase import normalises 0.16 -> 16 and rejects off-ladder rates | `audit_b_data006_purchase_import_tax_test` |
| DATA-007 | fixed | `escapeCsvCell` neutralises `= + - @ TAB CR` (plain numbers untouched) | `audit_b_csv_escape_test` |
| DATA-008 | fixed | imported barcode trimmed | `excel_import_products_rerun_test` (new case) |
| MIG-001 | fixed | `runOnUpgrade(from > to)` throws `DatabaseTooNewException` before any change and before drift stamps `user_version` | `audit_b_migration_safety_test` (real file DB) |
| MIG-002 | comment corrected + idempotency proven | wrapping the whole upgrade in a transaction would disable the `PRAGMA foreign_keys=OFF` table rebuilds, so it was NOT done; replaying an interrupted 195->196 upgrade is proven idempotent. Other epochs were not individually replayed (unverified) | same |
| MIG-003 | mitigated | "no such column" skips are persisted to `DiagnosticLogger` (`MIGRATION-SKIP`); the allow-list is unchanged (old DBs rely on it) | — |
| MIG-004 | fixed (mandatory part) | no backup on a live database file => `PreMigrationBackupFailedException`, nothing changed. **Deferred:** separate retention class (needs `connection_io.dart`, at its ceiling and owned by the secret-literals worker) | same |
| MIG-005 | fixed (b,c) | multi-phone matches recorded as `multiple_phone_matches` suspects; in-memory maps rebuilt after a failed group (c: no dedicated test) | `audit_b_data002_backfill_country_test` |
| BKP-001 | fixed | real encrypted drill: create via `openConnection()` -> `createDatabaseBackup` -> modify -> `restoreDatabaseBackup` -> reboot -> original rows, `integrity_check`, `user_version`, `.pre-restore` cleaned. Skips with a reason on plain sqlite3 | `integration/backup_restore_drill_real_test` |
| BKP-002 | fixed (schema part) | `PendingRestore.acceptInspection` rejects a backup newer than `kMaxSupportedSchemaVersion` (guarded against drift by a test). `integrity_check` time-boxing not done | same |
| BKP-004 | fixed | `scripts/backup_postgres.ps1` + `docs/ops/POSTGRES-BACKUP.md` | `audit_b_pg_backup_script_test` (script not executed: no pg_dump on this machine) |
| RPT-006 | already fixed (73257fe6) | export gate + picker card masking | existing |
| RPT-009 | fixed | dead `scanFraudAlerts` / aging / `validatePeriodClosing` removed | analyze |
| — | **new finding, fixed** | The deferred startup phase (`_scheduleDeferredTasks`: integrity checks, v196 backfill retry, **auto-backup on startup**) was scheduled with `Future.microtask` from `beforeOpen`, inheriting drift's closed before-open zone; on the real isolate-backed connection it threw `Bad state: No element` and never ran. Reproduced by the drill harness; fixed with `Zone.root.scheduleMicrotask`. Production impact before the fix is UNVERIFIED (the harness uses the real `openConnection()`) | the drill fails if it regresses |

## Deferred (reason)

* DATA-004 DB constraints — needs table definitions / schemaVersion (explicitly out of scope: report, do not change).
* DATA-005 JE after commit — core sales path redesign (M), needs an owner decision between in-transaction posting and a visible pending-posting alert.
* ACC-010 balance tolerance per currency — touches every JE balance check; needs per-currency tests first.
* RPT-002 (a)(d)(e), RPT-007 returns analytics, RPT-008 reconciling line on the tax screen.
* MIG-004 retention class, BKP-003 backup health/off-device copy (needs `connection_io.dart` + UI), MIG-006 PG upgrade test and MIG-007 old-encrypted-fixture upgrade test (need real fixtures), BKP-005 (security axis).
