# Axis B — Project baseline: data architecture as implemented

| Item | Value |
|---|---|
| Repo | `D:\PICPOS-ERP` |
| Branch | `feat/tables-reservations-permissions` |
| HEAD | `d69be1eafc7d82b924723dfdbb53960b7e33acdb` (`chore(release): QA fixes, i18n keys, docs, version 3.9.2+277`, committed 2026-10-23 03:08 +0300) |
| App version | `3.9.2+277` (`pubspec.yaml`) |
| Local changes at audit start | Untracked only: `Cairo,Noto_Naskh_Arabic/`, root `*.txt` (all_final, font_*, orig5…), two new plan docs under `docs/plans/2026-10-23-*`, two Arabic design folders, `طلب مراجعه.txt`. No tracked file modified. |
| Remote | Not checked (no fetch performed — read-only audit; remote state unknown). |
| Auditor mode | Read-only. No `flutter`/`dart` command run. No DB file opened (the user DB is SQLCipher-encrypted; not attempted). |

## 1. Storage engines

- **SQLite + SQLCipher** (desktop / standalone / host): Drift `2.32.1` (pinned) over `sqlcipher_flutter_libs ^0.6.8`.
  - Key resolved before any file handle: `resolveDatabaseKey` → `DbKeyBlockedException` recovery screen on failure ([connection_io.dart:49-52](<../../../../lib/data/database/connection_io.dart#L49-L52>)).
  - `PRAGMA key` is the first statement in setup, followed by a `cipher_version` probe that refuses a plain sqlite3 engine, then `PRAGMA foreign_keys = ON`, WAL, etc. ([connection_io.dart:70-118](<../../../../lib/data/database/connection_io.dart#L70-L118>)). All before Drift migrations.
- **PostgreSQL** (server mode): `drift_postgres ^1.3.1`, `postgres ^3.4.0`. `AppDatabase.withExecutor(..., isPostgres: true)` ([db_connection_strategy.dart:137-141](<../../../../lib/data/database/db_connection_strategy.dart#L137-L141>)). Reports run against PG in this mode (same DAO code).
  - Dialect helpers: `sqlBool()` ([database.dart:654](<../../../../lib/data/database/database.dart#L654>)); raw SQL translated by `PgCompatSql.fixSql` (strftime/julianday/INSTR/GROUP_CONCAT only — **not** `date(` or scalar `MAX(a,b)`/`MIN(a,b)`) ([pg_compat_sql.dart:112-157](<../../../../lib/data/database/pg_compat_sql.dart#L112-L157>)).
  - PG compat layer creates `OPERATOR =(boolean,integer)` and `CAST (integer AS boolean)` so raw `is_x = 0/1` literals work ([database_pg_create.dart:277-303](<../../../../lib/data/database/database_pg_create.dart#L277-L303>)).
  - PG schema is created fresh (`_createAllForPostgres`) and **`onUpgrade` is skipped on PG** ([database.dart:846-856](<../../../../lib/data/database/database.dart#L846-L856>)); parity is enforced at `beforeOpen` (`_ensurePostgresSchemaParity`).

## 2. Schema shape

- 167 Drift `extends Table` classes under `lib/data/database/tables/`; 134 DAO files under `lib/data/database/daos/`; plus raw-SQL tables/indexes created in `onCreate`/migrations (e.g. `idx_je_autopost_dedup`, `EInvoiceStatusLog`).
- `schemaVersion => 196` ([database.dart:673](<../../../../lib/data/database/database.dart#L673>)).
- PKs: integer `autoIncrement` everywhere; cross-device identity via `global_id` (UUIDv7, `UNIQUE` on most tables).
- FKs: declared via `.references()`; enforced on SQLite (`foreign_keys = ON`). `journal_entry_lines.entry_id → journal_entries ON DELETE CASCADE`.
- Notable missing constraints (see DATA-004): no `UNIQUE` on `journal_entries.entry_number`, no FK on `journal_entries.fiscal_year_id` / `journal_entry_lines.cost_center_id`, no `CHECK` on debit/credit sign or exclusivity, no `UNIQUE` on product barcode (app-level `assertBarcodeFree` only), supplier-invoice-number uniqueness app-level only (per supplier, [purchase_insert_support_dao.dart:166-195](<../../../../lib/data/database/daos/purchase_insert_support_dao.dart#L166-L195>)).
- Soft-delete model (two conventions):
  - `is_deleted` boolean (+ `deleted_at`): `journal_entries`, `sales_invoices`, `purchase_invoices`, `purchase_returns`.
  - `deleted_at` nullable only: most other tables (`safe_transactions`, `stock_movements`, `parties`, `table_reservations`, `bookings`, …).
  - Sales void and purchase void set **both** `status='voided'` and `is_deleted=true` ([sales_actions_dao.dart:403-412](<../../../../lib/data/database/daos/sales_actions_dao.dart#L403-L412>), [purchase_void_dao.dart:335-338](<../../../../lib/data/database/daos/purchase_void_dao.dart#L335-L338>)). No current code path writes `status='cancelled'` on sales/purchase invoices (only legacy/sync data can carry it). Full purchase return sets `status='returned'` and keeps `is_deleted=0`, `total`, `paid` unchanged ([purchases_repository_impl.dart:627-636](<../../../../lib/data/repositories/purchases_repository_impl.dart#L627-L636>)).
  - `journal_entries.is_deleted = true` is never set by any app write path in `lib/` (grep); it can arrive via sync from another node/legacy data, and `commercial_papers_dao` revives such rows ([commercial_papers_dao.dart:685-692](<../../../../lib/data/database/daos/commercial_papers_dao.dart#L685-L692>)). Reversal model = new `-rev` JE; original stays posted with no "reversed" flag.

## 3. Money, rounding, dates

- Money stored as `REAL` (Drift `RealColumn`) — explicit decision "FA-04" ([financial_utils.dart:54](<../../../../lib/core/utils/financial_utils.dart#L54>)). Not integer minor units.
- Rounding: `FinancialUtils.round()` half-away-from-zero after `toStringAsFixed(10)` normalisation; comparisons via `toMinorUnits`. Decimals from `AppConstants.decimalPlaces` (JOD = 3 default; `setCurrency` switches, EGP = 2) ([app_constants.dart:40,67](<../../../../lib/core/constants/app_constants.dart#L40>)).
- `balanceTolerance = 0.01` fixed (= 10 minor units in JOD, 1 in EGP) ([financial_utils.dart:38-43](<../../../../lib/core/utils/financial_utils.dart#L38-L43>)).
- Invoice VAT: per-line rounding; invoice discount spread across lines, leftover to the largest line; tax-inclusive mode backs out net per line; delivery fee untaxed ([financial_utils.dart:144-225](<../../../../lib/core/utils/financial_utils.dart#L144-L225>)).
- Dates: Drift `DateTime` stored as epoch **seconds** (`bigint` on PG, [database.dart:779](<../../../../lib/data/database/database.dart#L779>)); some raw columns use milliseconds (`approved_at` written as `millisecondsSinceEpoch`, [accounting_dao_writes.dart:1753](<../../../../lib/data/database/daos/accounting_dao_writes.dart#L1753>)) — mixed units (observation; the only consumer found reading epoch columns with a wrong unit is dead code, RPT-009). Local device time; no explicit TZ normalisation found.

## 4. Accounting engine

- Single writer `createJournalEntry` ([accounting_dao_writes.dart:45-311](<../../../../lib/data/database/daos/accounting_dao_writes.dart#L45-L311>)): runs in `transaction()`; per-line rounding to 3 dp; balance compared in minor units; ≤ 0.01 diff → `rounding_difference` account (or largest line on client), > 0.01 → throws; posting to parent/view accounts throws; closed fiscal year / closed accounting period throws via `validateFinancialPeriod` (exempt: fiscal_close/open, opening_balance); auto-post dedup on `(reference_type, reference_id, is_auto_posted)` except `kMultiJeReferenceTypes` ([database_sql_constants.dart:56-89](<../../../../lib/data/database/database_sql_constants.dart#L56-L89>)) backed by raw unique index `idx_je_autopost_dedup`.
- Draft approval (`approveJournalEntry`) re-checks balance, `is_deleted`, period, maker≠checker, and a conditional `UPDATE … WHERE is_posted=false AND is_deleted=false` with rowcount check ([accounting_dao_writes.dart:1705-1758](<../../../../lib/data/database/daos/accounting_dao_writes.dart#L1705-L1758>)).
- Auto-posting modules (accounts): cash/credit sale, sales return, purchase, purchase return, receipt/payment vouchers, treasury/voucher transfers, payroll (621/2131/2132/2123/1146), fixed-asset depreciation (6213 / category accumulated) and disposal (4314/642), inventory adjustments (shrinkage/surplus), transfers (goods_in_transit), manufacturing (WIP/raw_materials/applied_overhead), FX revaluation (6313 + next-month reversal), booking deposit (receipt voucher → `customer_advances` 2134). Sales JE is posted **after** the invoice transaction commits, with `failed_autoposts` log + 150 ms retry + startup repair ([sales_mutations_dao.dart:511-623](<../../../../lib/data/database/daos/sales_mutations_dao.dart#L511-L623>)).
- Zero-cost policy: setting `zero_cost_policy` (`warn` default → revenue posted without COGS + log; `block` → throw).
- Cached balances: `parties.balance` maintained by `adjustPartyBalance` (+ absolute writers); startup `getPartyBalanceMismatches` and repair `recalculatePartyBalancesFromLedger`; aggregate `getArReconciliation`; inventory `getInventoryGlReconciliation` (accounts 1131/1133/1136 vs `SUM(current_stock*cost_price)`).

## 5. Migrations

- Strategy ([database.dart:798-860](<../../../../lib/data/database/database.dart#L798-L860>)): `onCreate` = `createAll` + raw SQL + `ensure*Schema`; `onUpgrade` (SQLite only) = `runOnUpgrade` → pre-migration backup (non-blocking, no WAL checkpoint) → `_migrateEpoch1` (<60), `_migrateEpoch2` (<81), `_migrateEpoch3` (always, internally gated `from < N`) ([database_migrations.dart:66-87](<../../../../lib/data/database/database_migrations.dart#L66-L87>)).
- Epoch files: `epoch_1`, `epoch_2`, `epoch_3`, `epoch_3_v081_v093`, `_v094_v118`, `_v119_v133`, `_v134_v147`, `_v148_v156`, `_v157_v166`, `_v167_v173`, `_v174_v195`, `_v196_v205`.
- `_safeMigrate` swallows "duplicate column", "already exists", "no such column", "cannot add a unique column"; rethrows others.
- Drift 2.32.1 semantics (verified in package source): `beforeOpen` → `onUpgrade` runs through `_BeforeOpeningExecutor` **without a wrapping transaction**; `user_version` is written only after `beforeOpen` completes; `hadUpgrade` is `versionBefore != versionNow` so a **newer** DB (from > to) also calls `onUpgrade` and is then stamped 196 (`engines.dart:495-531`, `db_base.dart:118-139`, `migration.dart:621`).
- `beforeOpen` → `runBeforeOpen` ([database_startup.dart:19-128](<../../../../lib/data/database/database_startup.dart#L19-L128>)): ensure-schemas, PG parity, seeding, permissions sync, startup patches, deferred tasks (integrity checks, `retryResPartiesBackfill`, auto backup).
- v196: `table_reservations.party_id` / `bookings.party_id` + `reservation_parties_backfill.dart` (rules F.1 a–d, `party_dedup_suspects`, done/pending flags).

## 6. Backup / restore

- `createDatabaseBackup` = byte copy of the (encrypted) DB file to `Documents/backups/<db>_backup_<ts>[-n].db` + keyinfo sidecar; optional `PRAGMA wal_checkpoint(TRUNCATE)` first; retention 7 per DB name ([connection_io.dart:366-454, 574-599](<../../../../lib/data/database/connection_io.dart#L366-L454>)).
- `autoBackupOnStartup`: if newest backup > 24 h; SQLite only (PG mode: no in-app backup; docs point to `pg_dump`).
- Restore: two-phase `PendingRestore` (`.restore-pending`, key + `quick_check` validation, `.pre-restore` rollback) ([pending_restore.dart](<../../../../lib/data/database/pending_restore.dart>), [db_key_startup.dart:19-30](<../../../../lib/data/database/db_key_startup.dart#L19-L30>)). No `user_version` check.

## 7. Import / export

- XLSX via `excel_service.dart` (+ `xlsx_sanitizer.dart` strips built-in numFmt ids < 164 only). Products: match by code, tax normalised (0.16→16) and policy-checked, barcode app-checked. Parties: match by name, **balance overwritten**. Purchases: grouped by supplier invoice number; duplicate number rejected per supplier by DAO guard.
- CSV export `csv_import_export_service.dart` (no formula-injection escaping).
- Figure masking (`canSeeScreenFigures`, commit `d2272da0`) applied in 7 presentation files only; not in exports/prints.

## 8. Assumptions and open questions

1. Q: Is PG server mode shipped to customers in 3.9.2 (affects RPT-003 severity)? Assumed **yes** (provisioning code + E2E with PG server exist).
2. Q: Do deployments use client→host LAN topology with table reservations (affects DATA-001)? Assumed possible.
2b. Q: Is "hide monetary figures" (commit `d2272da0`) being sold as an access control (affects RPT-006 blocking status)?
3. Q: Is the home country fixed per install (would allow keeping foreign country codes in `normalizePhone`)? Unknown.
4. Assumption: prior run logs `D:\qa\logs4` correspond to the tree that became HEAD; logs carry no SHA and pre-date the commit timestamp (2026-10-21 vs commit 2026-10-23), so this is **unverified**.
