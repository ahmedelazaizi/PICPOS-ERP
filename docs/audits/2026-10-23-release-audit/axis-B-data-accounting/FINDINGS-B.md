# Axis B — Findings: data integrity, accounting, reports, migrations, backup

- **Version:** branch `feat/tables-reservations-permissions` @ `d69be1eafc7d82b924723dfdbb53960b7e33acdb` (app 3.9.2+277).
- **Environment:** static reading of the working tree on Windows (tracked files unmodified; untracked files are listed in PROJECT_BASELINE-B.md). Drift package source `drift-2.32.1` from the local pub cache. **No test, `flutter` or `dart` command was run by this auditor, and no DB file was opened.** Every finding is from code reading unless stated otherwise. "Repro" steps are proposed and **NOT_RUN**.
- **Affected platforms:** every SQLite/SQLCipher install (desktop host, standalone, LAN clients) unless a finding says PG only.

## Scales

| Field | Values |
|---|---|
| Type | Confirmed defect · Suspicion (needs verification) · Missing requirement · Improvement |
| Severity (impact if it happens) | Critical · High · Medium · Low |
| Priority (when to fix) | P0 before this release · P1 before wider rollout / next patch · P2 planned · P3 backlog |
| Confidence | High (code path read end to end, or verified in library source) · Medium (key step inferred) · Low (pattern only) |
| Release-blocking | Yes · Conditional (blocking only for a named deployment profile) · No |

## Summary table

| ID | Title | Type | Sev | Pri | Conf | Blocking |
|---|---|---|---|---|---|---|
| RPT-001 | Party statement includes voided/soft-deleted invoices and deleted payments | Confirmed defect | High | P0 | High (inclusion) / Medium (net effect) | **Yes** (repro first) |
| ACC-001 | Straight-line depreciation never stops at salvage / end of life | Confirmed defect | High | P1 | High | **Conditional** (tenants using fixed assets) |
| RPT-003 | `getArAgingReport` SQL is SQLite-only; fails on PostgreSQL | Confirmed defect (static) | High | P1 | High | **Conditional** (PG server mode) |
| DATA-001 | Table reservations made on a LAN client are never pushed to the host | Confirmed defect | High | P1 | High | **Conditional** (client/host + reservations) |
| RPT-006 | Figure masking not applied to exports, prints or customer-picker card | Confirmed defect | High | P1 | High | **Conditional** (if masking is sold as a control) |
| BKP-001 | No test or drill restores a real encrypted backup | Missing requirement | High | P1 | High | **Conditional** (general availability) |
| DATA-003 | Party XLSX re-import overwrites `parties.balance` without a journal entry | Confirmed defect | High | P1 | High | No |
| MIG-001 | No forward-compat guard: newer DB/backup opens silently and is re-stamped v196 | Confirmed defect | High | P1 | High | No |
| ACC-002 | Depreciation row and asset card advance without a JE; failures swallowed | Confirmed defect | Medium | P2 | High | No |
| ACC-004 | Booking deposit can land on party AR or revenue `4299`; guest deposits allowed | Confirmed defect | Medium | P2 | High | No |
| ACC-005 | FX revaluation main entry and reversal not atomic | Confirmed defect | Medium | P2 | High | No |
| ACC-006 | Cash flow puts manual JEs in operating, labelled as customer receipts / supplier payments | Confirmed defect | Medium | P2 | High | No |
| RPT-002 | Aged AR/AP "as of" uses current `paid`; AP in `getArAgingReport` counts fully returned invoices | Confirmed defect | Medium | P2 | High | No |
| RPT-004 | Tax report (GL side), hierarchical TB and posting reconciliation ignore `is_deleted` | Confirmed defect | Medium | P2 | High | No |
| RPT-005 | Sales summary / dashboard aggregates: inclusive next-midnight bound, unfiltered `paid` sum | Confirmed defect | Medium | P2 | High | No |
| RPT-007 | Budget actuals include drafts; other secondary aggregates miss filters | Confirmed defect | Medium | P2 | High (budget) / Medium (rest) | No |
| DATA-002 | Phone normalisation drops country code → cross-country false merges | Confirmed behaviour (owner rule) | Medium | P2 | High | No |
| DATA-005 | Sales JE posted after the invoice transaction commits | Confirmed design risk | Medium | P2 | High | No |
| DATA-006 | Purchase XLSX import does not normalise or validate tax rate | Confirmed defect | Medium | P2 | High | No |
| MIG-002 | Migrations not transactional (comment says they are) | Confirmed defect | Medium | P2 | High | No |
| MIG-003 | `_safeMigrate` swallows "no such column" | Suspicion | Medium | P2 | Medium | No |
| MIG-004 | Pre-migration backup is best-effort, un-checkpointed, and rotates out good backups | Confirmed defect | Medium | P2 | High | No |
| MIG-006 | PG upgrade path untested; legacy SQLite unique indexes may silently not exist | Suspicion | Medium | P2 | Medium | No |
| MIG-007 | No upgrade test from a real old (encrypted) DB file with data | Missing requirement | Medium | P2 | High | No |
| BKP-002 | Restore validates key + `quick_check` only; no schema-version check | Confirmed defect | Medium | P2 | High | No |
| BKP-003 | Backups are local-only; checkpoint failure gives a silently incomplete backup | Confirmed defect | Medium | P2 | High | No |
| BKP-004 | PostgreSQL mode has no in-app backup | Missing requirement | Medium | P2 | High | No |
| DATA-004 | Missing DB-level constraints on ledger and catalogue tables | Improvement | Low | P3 | High | No |
| DATA-007 | CSV export has no formula-injection escaping | Confirmed defect | Low | P3 | High | No |
| DATA-008 | Imported barcode not trimmed before uniqueness check | Suspicion | Low | P3 | Medium | No |
| ACC-003 | Depreciation duplicate guard keys on exact date (API path not normalised) | Suspicion | Low | P3 | Medium | No |
| ACC-007 | `getArReconciliation` compares active cards with the whole AR subtree | Confirmed defect | Low | P3 | High | No |
| ACC-008 | Generic `reverseTransaction` would skip 2nd+ reversals (no callers today) | Confirmed latent defect | Low | P3 | High | No |
| ACC-009 | JE number year from `now()`; vouchers pre-check period with `now()` | Confirmed defect | Low | P3 | High | No |
| ACC-010 | Balance tolerance fixed at 0.01 regardless of currency decimals | Improvement | Low | P3 | High | No |
| RPT-008 | Tax screen header (GL) and detail (invoices) come from different sources | Improvement | Low | P3 | High | No |
| RPT-009 | Dead audit/aging queries reference non-existent columns and wrong epoch units | Improvement | Low | P3 | High | No |
| MIG-005 | v196 backfill divergences from plan (placement, same-phone pick, cache after rollback) | Suspicion | Low | P3 | Medium | No |
| BKP-005 | Key sidecar stored beside every backup | Suspicion | Low | P3 | Low | No (refer to security axis) |

**Counts by severity:** Critical 0 · High 8 · Medium 19 · Low 12 · **Total 39**.
**Release-blocking:** 1 Yes (RPT-001) · 5 Conditional (ACC-001, RPT-003, DATA-001, RPT-006, BKP-001) · 33 No.

---

## Re-verification of known open defects at HEAD

| Prior item | Status at HEAD | Evidence | Finding |
|---|---|---|---|
| Dated aged report uses current `paid` | **Still open** | `party_reconciliation_dao.dart:79,119,197-211` | RPT-002 |
| Aged payables include cancelled invoices (`getArAgingReport`) | **Partly open.** The AP join has no status filter. Voided purchases are excluded indirectly, because void sets `is_deleted=1`. No current code writes `status='cancelled'` on invoices, so only legacy/synced rows are affected. But fully returned purchases (`status='returned'`, `is_deleted=0`) **are** counted. `_agedBalances` is correct. | `:116-120`, `purchases_repository_impl.dart:634` | RPT-002 |
| `getArAgingReport` SQLite-only | **Still open, and breaks on PG** | `:57-64,107-114`; `pg_compat_sql.dart:50,56,146` | RPT-003 |
| Cash flow classifies manual entries as operating | **Still open** | `accounting_reports_dao.dart:657,712-715` | ACC-006 |
| Cash flow / income / balance ignore `is_deleted` (prior C-2) | **Fixed** | `:259,414,477,656,733,757,780` | — |
| `approveJournalEntry` lacks balance/deleted check (prior C-1) | **Fixed** | `accounting_dao_writes.dart:1721-1758` | — |
| Account-movement / inventory / sales-reconciliation queries lack `is_deleted` | **Mixed.** The account ledger is OK (`accounting_dao_reads.dart:733,752`). Inventory–GL reconciliation is OK (it uses integer literals, which work on PG through the compat cast). There is no dedicated inventory-adjustment report or "sales reconciliation" query. **Still open:** party statement, tax report, hierarchical TB, posting reconciliation, budget actuals. | see RPT-001/004/007 | RPT-001, RPT-004, RPT-007 |
| Booking deposit → revenue `4299` if advances account missing (prior C-6) | **Still open** | `bookings_dao.dart:530-543`, `treasury_voucher_dao.dart:549-586` | ACC-004 |
| No push of table reservations client → host | **Still open** | `restaurant_repository_impl.dart:127-148` vs `:106-116` | DATA-001 |
| Phone normalisation strips country code | **Still open (owner rule F.1(a) as written)** | `phone_normalizer.dart:46-53` | DATA-002 |
| v196 backfill never retried (prior A-1) | **Fixed.** The `pending` flag is retried from deferred startup. | `database_startup.dart:1736` | — |
| "No pre-upgrade backup" (prior A-7) | **Incorrect at HEAD.** `runOnUpgrade` does take one, but it is best-effort. | `database_migrations.dart:74-79` | MIG-004 |

---

## Findings (detail)

### RPT-001 — Party statement includes voided/soft-deleted invoices and deleted payments
- **Type / axis:** Confirmed defect / reports. **Severity:** High. **Priority:** P0. **Confidence:** High that the rows are included (query read in full). Medium on the exact net effect per void flow, because the void side effects on `safe_transactions` were not traced end to end.
- **Where:** `getPartyStatement`:
  - sales [party_transactions_dao.dart:29-34](<../../../../lib/data/database/daos/party_transactions_dao.dart#L29-L34>)
  - purchases [:71-76](<../../../../lib/data/database/daos/party_transactions_dao.dart#L71-L76>)
  - safe transactions [:112-119](<../../../../lib/data/database/daos/party_transactions_dao.dart#L112-L119>)
  - opening-balance queries ≈ :421-475

  The same gap is in `getCalculatedPartyBalance` [parties_repository_impl.dart:114-160](<../../../../lib/data/repositories/parties_repository_impl.dart#L114-L160>), which uses `status != 'cancelled'` with no `is_deleted`/`deleted_at` filter, and which `reconciliation_service.dart:129` consumes. Callers: PicPos statement ledger, statement export, and the legacy `party_statement_screen.dart:150`.
- **Preconditions / repro (NOT_RUN):**
  1. Create a credit sale of 100 to customer C.
  2. Void it, which sets `status='voided', is_deleted=1` ([sales_actions_dao.dart:403-412](<../../../../lib/data/database/daos/sales_actions_dao.dart#L403-L412>)).
  3. Open C's statement for the period.
- **Expected:** The voided invoice is absent, or shown with an offsetting line, and the closing balance equals `parties.balance` and the GL sub-account.
- **Actual (from code):** The invoice is selected with no `isDeleted`/`status` predicate and emitted as a debit of 100. Running balance = sum of rows, so the statement closes 100 above the card/GL balance. Soft-deleted `safe_transactions` (`deleted_at`) are also emitted.
- **Evidence:**
  ```dart
  final salesQuery = select(salesInvoices)
    ..where((i) => i.customerId.equals(partyId) &
                   i.invoiceDate.isBetween(Variable(from), Variable(to)));
  ```
  No `isDeleted`. `test/unit/party_statement_queries_test.dart` contains no `voided`/`isDeleted` case (grep).
- **Impact:** A customer-facing document (printed/exported statement) overstates or misstates debt, which leads to collection disputes. It also disagrees with the card balance and the GL.
- **Root cause:** The statement is built from document tables, not from the GL, and the soft-delete convention was not applied to it.
- **Remediation:** Add `isDeleted.equals(false)` (or `status NOT IN ('voided','cancelled')`) to both invoice queries and to every opening-balance query, and `deletedAt.isNull()` to `safe_transactions`. Apply the same fix in `getCalculatedPartyBalance`. Longer term, build the statement from the party's GL sub-account. **Effort:** S (0.5–1 day incl. tests). Uncertainty: other statement sources (`getPartyTransactions`) may need the same change.
- **Acceptance:** A new test covering voided credit sale, voided cash sale, voided purchase and soft-deleted receipt shows statement closing balance = `parties.balance` = GL sub-account balance for that party.
- **Release-blocking:** **Yes.** Voiding is routine at POS and the statement is handed to customers. Confirm with the repro above first (≈10 min); if the void flow turns out to add an offsetting statement row, downgrade to Medium.

### ACC-001 — Straight-line depreciation never stops at salvage value or end of useful life
- **Type:** Confirmed defect. **Sev:** High. **Pri:** P1. **Conf:** High.
- **Where:** [fixed_assets_dao_ext.dart:460-482](<../../../../lib/data/database/daos/fixed_assets_dao_ext.dart#L460-L482>).
- **Repro (NOT_RUN):** Asset with price 1200, salvage 0, life 1 year, `accumulatedDepreciation` 1200 (or imported near end of life). Run monthly depreciation for the next month.
- **Expected:** 0 depreciation; asset marked fully depreciated.
- **Actual:** `monthlyDepreciation = depreciableAmount / (usefulLifeYears*12)` = 100 is posted again. Only declining balance is capped (:468-471). Book value goes below salvage and then negative. A balanced but wrong JE (Dr 6213 / Cr accumulated) is posted every month, forever. There is also no "depreciate only after purchase date" check.
- **Impact:** Overstated expense and understated assets in the income statement and balance sheet. The screens and the GL agree, so reconciliation cannot catch it.
- **Root cause:** The cap was implemented only in the declining-balance branch. The DAO duplicates the formula instead of using `domain/models/depreciation_math.dart`.
- **Remediation:** Clamp to `depreciableAmount - accumulatedDepreciation` for both methods, skip when ≤ 0, set status `fully_depreciated`, and skip periods before the purchase/in-service date. Use one shared formula. **Effort:** S.
- **Acceptance:** Tests for month `life*12+1` (0 posted), salvage > 0, and an asset imported with partial accumulated depreciation. The existing `accounting_e2e_suite.dart:651-695` still passes.
- **Release-blocking:** Conditional. Blocking for tenants who use fixed assets with any asset at or near end of life (including imported registers). Otherwise P1.

### RPT-003 — `getArAgingReport` SQL is SQLite-only and fails on PostgreSQL
- **Type:** Confirmed defect (static; not executed). **Sev:** High. **Pri:** P1. **Conf:** High (rewrite rules read).
- **Where:**
  - [party_reconciliation_dao.dart:57-64, 107-114](<../../../../lib/data/database/daos/party_reconciliation_dao.dart#L57-L114>)
  - rewrite rules [pg_compat_sql.dart:48-57, 139-149](<../../../../lib/data/database/pg_compat_sql.dart#L139-L149>)
  - callers: [report_providers.dart:46](<../../../../lib/data/providers/report_providers.dart#L46>) and [admin_snapshot_builder.dart:72-73](<../../../../lib/services/admin_snapshots/admin_snapshot_builder.dart#L72-L73>)
- **Actual (derived):**
  - In `julianday(COALESCE(si.due_date, si.invoice_date), 'unixepoch')`, the comma inside `COALESCE` defeats the `([^,]+), 'unixepoch'` rule. The generic rule `julianday\(([^)]+)\)` then rewrites it to `((COALESCE(si.due_date, si.invoice_date) / 86400.0), 'unixepoch')`, which is a row constructor, so the subtraction fails.
  - Scalar `MAX(x, 0)` does not exist in PG (it needs `GREATEST`).
  - `GROUP BY p.id` while selecting `p.name, p.balance` is accepted by PG only because `p.id` is the PK. That part is OK.
- **Expected:** The report works on both engines. `_agedBalances` already shows the portable form (epoch arithmetic, [:196-200](<../../../../lib/data/database/daos/party_reconciliation_dao.dart#L196-L200>)).
- **Evidence:** There is no `integration_pg` test for `getArAgingReport` (grep). The PG test covers `getAgedReceivables` only (`financial_analytics_pg_test.dart:139-164`).
- **Impact:** In PG server mode the AR/AP aging report provider and the admin snapshot throw. Whether the snapshot builder isolates the error was not checked.
- **Remediation:** Re-implement on top of `_agedBalances` (one source), or use epoch arithmetic plus `CASE WHEN x>0 THEN x ELSE 0 END`. Add a PG integration test. **Effort:** S.
- **Acceptance:** A `test/integration_pg` case calls `getArAgingReport` for both AR and AP and matches the SQLite result on the same fixture.
- **Release-blocking:** Conditional. Blocking where PG server mode is deployed and the aging report or admin snapshots are used.

### DATA-001 — Table reservations made on a LAN client never reach the host
- **Type:** Confirmed defect. **Sev:** High. **Pri:** P1. **Conf:** High that there is no push path. Medium that the row is later lost, because pull-overwrite semantics were not traced.
- **Where:**
  - `createReservation/updateReservationStatus/cancelReservation/deleteReservation` write locally only ([tables_dao.dart:621-714](<../../../../lib/data/database/daos/tables_dao.dart#L621-L714>)).
  - The repository passes through with no client branch ([restaurant_repository_impl.dart:127-148](<../../../../lib/data/repositories/restaurant_repository_impl.dart#L127-L148>)). Compare `saveFloorPlanLayout`'s `if (SyncInterceptor.isClientMode) … ClientWriteInterceptor.dispatchWrite` at [:106-116](<../../../../lib/data/repositories/restaurant_repository_impl.dart#L106-L116>).
  - `table_reservations` appears only in pull lists (`api_sync_pull_tables.dart:72,231`, `delta_pull_service.dart:200,344,456`). There is no reservation handling in `lib/services/sync/**` or the CWI (grep). `bookings` does have a CWI path (`cwi_sync_foundation.dart:214`).
- **Repro (NOT_RUN):** Host + client pair. Reserve table T on the client, then open the host's tables screen.
- **Expected:** The reservation is visible on the host and every other client, and conflicting reservations are prevented.
- **Actual:** It stays on the client. Other devices can double-book. The client-local row may be overwritten or orphaned by the next delta pull (unverified).
- **Impact:** Double bookings and lost reservations in multi-terminal restaurants. With the v196 `party_id`, the customer's reservation history is incomplete on the host.
- **Remediation:** Add a CWI submit plus a host API route, mirroring bookings (idempotent by `global_id`), or block reservation writes in client mode with a clear message. **Effort:** M.
- **Acceptance:** An E2E test: client creates/cancels a reservation, and the host DB row exists with the same `global_id`/status within one sync cycle, including after an offline → online replay.
- **Release-blocking:** Conditional. Blocking for client/host deployments that use table reservations. Otherwise state the limitation in the release notes.

### RPT-006 — Figure masking not applied to exports, prints or the customer picker
- **Type:** Confirmed defect (cross-ref security axis). **Sev:** High. **Pri:** P1. **Conf:** High.
- **Where:**
  - `screenFiguresVisibilityProvider` is used only in 7 presentation files (grep).
  - `exportPartiesTemplate` writes `DoubleCellValue(party.balance)` unconditionally ([excel_service.dart:930,953](<../../../../lib/data/services/excel_service.dart#L930>)). The products template writes prices and cost (`:288-295`), as does the CSV `exportProducts` (`csv_import_export_service.dart:37`).
  - The customer picker card shows the balance without masking ([customer_picker_card.dart:101](<../../../../lib/presentation/shared_widgets/customer_picker/customer_picker_card.dart#L101>)).
  - The statement export uses `party.balance` (`party_statement_export_picpos.dart:84`).
  - `maskedFinancialFigure` is documented as "used by … exports" ([financial_figures_access.dart:44-45](<../../../../lib/core/permissions/financial_figures_access.dart#L44-L45>)) but no export uses it.
- **Expected:** A user without figure permission sees `—` on screen, in exports and in prints.
- **Actual:** Only the 7 on-screen widgets are masked. Whether those users can reach the export actions was not checked (security axis).
- **Note:** `canSeeScreenFigures` grants on the screen's own view permission (`.any`). This is consistent with its doc comment, so it is not counted as a defect here. The owner decision B-1/B-2 in `FINAL-QA-VERDICT.md` governs.
- **Remediation:** Pass visibility into the export and print services, or gate the export actions on the same predicate. **Effort:** M.
- **Acceptance:** A widget/service test: a user without figure permission exports parties/products → balance and price cells are `—` or absent. The same for the picker card and statement print.
- **Release-blocking:** Conditional. Blocking if 3.9.2 advertises "hide monetary figures" as an access control. Otherwise P1.

### BKP-001 — No test or drill restores a real encrypted backup
- **Type:** Missing requirement. **Sev:** High. **Pri:** P1. **Conf:** High.
- **Evidence:**
  - `test/unit/pending_restore_test.dart` uses `PendingRestore.openerOverride` with text files: valid means the file starts with `'OK'` (:13-16).
  - `test/integration/data_wipe_service_test.dart:656-723` uses the `'fake sqlite payload'`.
  - No test opens a restored SQLCipher DB and checks its rows.
  - `FINAL-QA-VERDICT.md` lists no restore drill.
- **Expected:** At least one restore of a real encrypted backup, through the real boot path, with row-level verification.
- **Actual:** Restorability is unproven. Per the audit policy, the backup button is not proof.
- **Remediation:** An integration test that creates an encrypted DB with data → `createDatabaseBackup` → modifies the DB → `restoreDatabaseBackup` → simulated reboot (`PendingRestore.apply` + real open + `finalize`) → asserts the original rows and the key. Plus a manual drill on a copy of a real install. **Effort:** M.
- **Acceptance:** The test passes in CI. A drill log exists in `docs/handoff/`.
- **Release-blocking:** Conditional. Blocking for general availability; acceptable for the limited pilot already approved.

### DATA-003 — Party XLSX re-import overwrites the cached balance with no journal entry
- **Type:** Confirmed defect. **Sev:** High. **Pri:** P1. **Conf:** High.
- **Where:**
  - suppliers [excel_service.dart:998-1008](<../../../../lib/data/services/excel_service.dart#L998-L1008>), with the same pattern for customers (≈:1039-1050)
  - `updateParty` is a plain `replace` ([party_dao.dart:455-461](<../../../../lib/data/database/daos/party_dao.dart#L455-L461>))
- **Repro (NOT_RUN):**
  1. Export the parties template, which contains the current balance.
  2. Post a sale on credit.
  3. Re-import the file.
- **Expected:** Existing parties update their master data only. The balance changes only through ledger postings, or through an explicit opening-balance JE.
- **Actual:** `balance: openingBalance` overwrites the card, so the card no longer matches the GL sub-account. Credit-limit checks (`invoice_safety_guards.dart:35`) and POS display read the card.
- **Mitigation present:** The startup `getPartyBalanceMismatches` and the repair `recalculatePartyBalancesFromLedger` detect and repair this (`party_reconciliation_dao.dart:329-407`).
- **Remediation:** On update, ignore the balance column (or reject the import when it differs). Only new parties get an opening balance, with its JE. **Effort:** S.
- **Acceptance:** A test: re-importing the same file after a credit sale leaves `parties.balance` equal to the GL balance.
- **Release-blocking:** No (detectable and repairable), but fix before wider rollout.

### MIG-001 — No forward-compat guard: a newer DB or backup opens silently and is re-stamped v196
- **Type:** Confirmed defect. **Sev:** High. **Pri:** P1. **Conf:** High (drift 2.32.1 source read).
- **Where:**
  - drift `migration.dart:621` `hadUpgrade => !wasCreated && versionBefore != versionNow`
  - `db_base.dart:131-134` calls `onUpgrade(from, to)` even when `from > to`
  - `engines.dart:524-527` then sets `user_version = 196`
  - the app's `onUpgrade` has no `from > to` check ([database.dart:846-856](<../../../../lib/data/database/database.dart#L846-L856>), [database_migrations.dart:66-87](<../../../../lib/data/database/database_migrations.dart#L66-L87>))
  - grep finds no `user_version`/downgrade handling in `lib/data/database`
- **Repro (NOT_RUN):** Open a v197+ DB (a future build, or a restored newer backup) with 3.9.2.
- **Expected:** Refuse to open with a clear message (and offer to restore a compatible backup).
- **Actual:** It takes a pre-migration backup and runs the epoch steps, all gated `from < N` and therefore no-ops. The `ensure*`/`beforeOpen` repairs then run against an unknown newer schema and stamp it 196. On the next upgrade, migrations v197+ re-run over already-migrated data.
- **Impact:** Silent schema/data corruption on rollback, which is the standard advice when a release misbehaves. It also combines with BKP-002.
- **Remediation:** In `onUpgrade` (or before opening), `if (from > to) throw DbTooNewException` and show the recovery screen. Apply the same check in `PendingRestore.canOpen`. **Effort:** S.
- **Acceptance:** A unit test with `user_version = 999` → open fails with the typed exception, and `user_version` is unchanged.
- **Release-blocking:** No. It is required before any rollback guidance is issued.

### ACC-002 — Depreciation row and asset card advance without a journal entry; failures are swallowed
- **Type:** Confirmed defect. **Sev:** Medium. **Pri:** P2. **Conf:** High.
- **Where:** [fixed_assets_dao_ext.dart:490-544](<../../../../lib/data/database/daos/fixed_assets_dao_ext.dart#L490-L544>).
- **Actual:**
  - When `6213` or the category's accumulated-depreciation account is null, no JE is created, but the `asset_depreciations` row (`journalEntryId: null`) and `accumulatedDepreciation` are still written (:492, :520-538).
  - Any exception, including a closed period, goes to `debugPrint` and the loop continues (:541-543).
  - The UI shows only a count, so the user cannot see that assets were skipped.
- **Expected:** Missing mapping means a hard error for that asset, reported to the user. The register never advances without a JE.
- **Remediation:** Throw when an account is missing, collect per-asset failures, and return them to the UI. **Effort:** S.
- **Acceptance:** A test with an unmapped category: no depreciation row is written and the error list contains the asset.

### ACC-004 — Booking deposit can land on party AR or revenue `4299`; guest deposits allowed
- **Type:** Confirmed defect. **Sev:** Medium (High impact, low likelihood: `2134` is seeded by `database_seeder_accounts.dart:136`). **Pri:** P2. **Conf:** High.
- **Where:**
  - `linkedAccountId: advances?.id` with no null check ([bookings_dao.dart:530-543](<../../../../lib/data/database/daos/bookings_dao.dart#L530-L543>))
  - voucher fallback: party AR, else category code, created as a **revenue** account if missing ([treasury_voucher_dao.dart:549-586](<../../../../lib/data/database/daos/treasury_voucher_dao.dart#L549-L586>))
  - `partyId` is optional in `createBooking` (:455)
  - the apply step does throw on missing advances (:764-766), which is asymmetric
- **Expected (plan F.8):** The deposit is credited to `customer_advances`, and a deposit requires a registered customer.
- **Actual:**
  - With the advances account missing and a party set, it posts to the party's AR with `skipPartyBalance: true`, so the GL and the card diverge.
  - With no party, it posts to `4299` revenue.
  - A guest booking with a deposit is accepted.
  - There is no refund/forfeit flow (prior C-6; not re-traced).
- **Remediation:** Throw if advances is missing or `partyId == null && depositAmount > 0`. Implement refund/forfeit JEs. **Effort:** S (guards) + M (refund/forfeit).
- **Acceptance:** Tests: missing `2134` → exception and no voucher; guest + deposit → exception.

### ACC-005 — FX revaluation main entry and reversal are not atomic
- **Type:** Confirmed defect. **Sev:** Medium. **Pri:** P2. **Conf:** High.
- **Where:** [fx_revaluation_dao.dart:184-346](<../../../../lib/data/database/daos/fx_revaluation_dao.dart#L184-L346>).
- **Actual:**
  - There is no `transaction()` in the function (grep), so the main JE (:310) and the reversal (:329) commit separately.
  - If the reversal fails (e.g. no fiscal year covers the 1st of next month), the main entry stays.
  - A retry finds `existing != null`, `existingReversal == null`. It recomputes the lines from current data (current `paid`, current rates) and posts a reversal that may not mirror the original.
- **Remediation:** Wrap both in one transaction, or build the reversal from the stored lines of `existing`. **Effort:** S.
- **Acceptance:** A test: force the reversal to fail → no main entry persists; on retry the reversal lines equal the negated original lines.

### ACC-006 — Cash flow: manual JEs classified as operating and labelled as customer receipts / supplier payments
- **Type:** Confirmed defect (known). **Sev:** Medium. **Pri:** P2. **Conf:** High.
- **Where:** [accounting_reports_dao.dart:657, 712-715](<../../../../lib/data/database/daos/accounting_reports_dao.dart#L657-L715>), returned as `receiptsFromCustomers`/`paymentsToSuppliers` (≈:793-795).
- **Actual:** Any cash/bank movement in a JE with `reference_type` NULL or unclassified goes into operating `otherReceipts`/`otherPayments`. That includes manual loans, capital injections, owner drawings and cash↔bank transfers (a transfer grosses up both sides).
- **Expected (IAS 7):** Classification by counter-account nature, or at least a separate "unclassified" line and no "customer"/"supplier" labels.
- **Remediation:** Classify manual JEs by the non-cash counter-account's type (equity/long-term liability → financing; fixed assets → investing). Net out cash↔cash transfers. **Effort:** M.
- **Acceptance:** Fixture tests: a manual capital injection appears under financing, and a cash→bank transfer has zero net and zero gross in operating.

### RPT-002 — Aged AR/AP "as of" uses current `paid`; AP in `getArAgingReport` counts fully returned invoices
- **Type:** Confirmed defect (known, partly). **Sev:** Medium. **Pri:** P2. **Conf:** High.
- **Where:**
  - `getArAgingReport` [:79-80, 116-120](<../../../../lib/data/database/daos/party_reconciliation_dao.dart#L116-L120>)
  - `_agedBalances` [:197-211](<../../../../lib/data/database/daos/party_reconciliation_dao.dart#L197-L211>)
- **Actual:**
  - (a) Only `invoice_date <= asOf` is time-filtered. `paid` is the current value, so a past-dated report hides invoices that were open on that date.
  - (b) The AP branch of `getArAgingReport` has no status filter. A fully returned credit purchase keeps `status='returned', is_deleted=0, total, paid` (`purchases_repository_impl.dart:627-636`) and is aged as outstanding.
  - (c) AR omits `'voided'` (moot today: void sets `is_deleted`).
  - (d) The total and the row filter use the cached `p.balance` (`> 0.01`), while the buckets use invoices. In `_agedBalances`, a negative remainder is clamped to 0, so the buckets can exceed the total.
  - (e) Partial returns (sales or purchase) do not reduce `total - paid`. This is a suspicion (allocation logic not traced).
- **Remediation:** One aging source with portable SQL. `paid` as of date from allocations/receipts dated ≤ asOf (or relabel the report "current balances by invoice date"). Status filter `NOT IN ('returned','cancelled','voided')`. Net returns. **Effort:** M.
- **Acceptance:** Fixtures: invoice 1 Jan paid 1 Feb, as-of 15 Jan → in 0-30; a fully returned purchase is absent; bucket sum = total.

### RPT-004 — Tax report (GL side), hierarchical trial balance and posting reconciliation ignore `is_deleted`
- **Type:** Confirmed defect. **Sev:** Medium. Exposure is limited: no app write path sets `journal_entries.is_deleted=1`, but such rows arrive via sync/legacy data and `commercial_papers_dao.dart:685-692` revives them. **Pri:** P2. **Conf:** High.
- **Where:**
  - `getTaxReport` [accounting_reports_dao.dart:919, 932, 945, 961](<../../../../lib/data/database/daos/accounting_reports_dao.dart#L919>): `e.is_posted = $boolTrue` only. The warehouse `EXISTS` subqueries (:863, :888) don't check invoice deletion.
  - `getHierarchicalTrialBalance` [:1137](<../../../../lib/data/database/daos/accounting_reports_dao.dart#L1137>).
  - `getPostingReconciliation` (:1232, :1254, :1272-1281) has no invoice/JE `is_deleted`.
  - The VAT reconciliation purchase side (:1460-1461) has no status filter.
- **Expected:** The same exclusions as `getTrialBalance` (:123, :146), so the hierarchical TB equals the flat TB and the VAT return excludes deleted entries.
- **Remediation:** Add `AND e.is_deleted = $boolFalse` (and invoice `is_deleted`) to each. Add a test asserting flat TB == hierarchical TB with a soft-deleted JE present. **Effort:** S.
- **Acceptance:** That test plus a tax-report test with a soft-deleted VAT JE.

### RPT-005 — Sales summary / dashboard aggregates: inclusive next-midnight bound and unfiltered `paid` sum
- **Type:** Confirmed defect. **Sev:** Medium. **Pri:** P2. **Conf:** High.
- **Where:**
  - [sales_repository_impl.dart:758-781](<../../../../lib/data/repositories/sales_repository_impl.dart#L758-L781>): `end = toDate + 1 day` passed to `getTotalSales/getSalesCount` (`BETWEEN ? AND ?`, inclusive, [sales_analytics_dao.dart:129-184](<../../../../lib/data/database/daos/sales_analytics_dao.dart#L129-L184>)). Invoices stamped exactly at the next midnight are counted in both days.
  - `totalPaid` = `SUM(paid) … WHERE invoice_date BETWEEN ? AND ?` with **no `is_deleted`, return or status filter** and raw `Variable(start)` rather than `dateVar`, so `totalDue = totalSales - totalPaid` mixes filtered and unfiltered bases.
  - `getTodaySales*` use `isBetween(startOfDay, nextMidnight)` (`sales_dao.dart:276-427`).
  - Dashboard revenue (GL, by branch) and invoice count (by warehouse) use different dimensions (`dashboard_filter_provider.dart:95-139`); this is documented as intentional.
- **Remediation:** Half-open ranges (`>= start AND < end`). Apply the same filter set to `paid`. Use `dateVar` everywhere. **Effort:** S.
- **Acceptance:** A test with an invoice at 00:00:00 of D+1 counted once, and a voided paid invoice excluded from `totalPaid`.

### RPT-007 — Budget actuals include drafts; other secondary aggregates miss filters
- **Type:** Confirmed defect. **Sev:** Medium. **Pri:** P2. **Conf:** High for the budget items (read). Medium for the rest (reader report, spot-checked).
- **Where:**
  - Budget vs actual: [budgeting_dao.dart:80-97](<../../../../lib/data/database/daos/budgeting_dao.dart#L80-L97>) has no `is_posted`/`is_deleted`, so draft and unapproved JEs count as actuals.
  - Cash-flow forecast (`budgeting_dao.dart:204-214`) has no deleted/status filter and counts returns as inflows.
  - `purchase_summary_dao.dart:78-91`: `n` and `SUM(total)` include cancelled/returned. `:97-104` lacks `sm.deleted_at`.
  - `treasury_shift_aggregates_dao.dart:96-163` has no status filter. That is moot for voided (`is_deleted`), but returned status is still counted.
  - `cycle_count_dao.dart:97-113` lacks `sm.deleted_at`. `getVarianceReport` (`:303-333`) accepts `warehouseId` but never uses it.
  - Returns analytics `sales_analytics_dao.dart:1099-1106, 1151-1153, 1223-1227` lack `deleted_at`.
- **Remediation:** One shared predicate helper per document type (posted/non-deleted JE; live invoice; live movement), applied everywhere. A structural test greps report DAOs for the helper. **Effort:** M.
- **Acceptance:** A budget-vs-actual test where a draft JE is excluded, and a variance report filtered by warehouse.

### DATA-002 — Phone normalisation drops the country code, so customers in different countries can be merged
- **Type:** Confirmed behaviour; a requirement risk (owner rule F.1(a) literally says "remove the country code"). **Sev:** Medium. **Pri:** P2. **Conf:** High.
- **Where:** [phone_normalizer.dart:46-53](<../../../../lib/core/utils/phone_normalizer.dart#L46-L53>), used by the v196 backfill (rule a) and duplicate detection in the picker/add-party dialogs.
- **Actual:** `normalizePhone('+966501234567') == normalizePhone('+971501234567') == '501234567'`. Local `0501234567` also collides across countries.
- **Impact:** A reservation or booking is linked to the wrong customer (PII on the wrong person). Duplicate warnings fire falsely.
- **Remediation:** Strip only the install's home country code; keep explicit foreign codes in the key. This needs an owner decision (open question in the baseline). **Effort:** S + a re-key migration if changed.
- **Acceptance:** Unit test: different explicit country codes → different keys; home-country variants → same key.

### DATA-005 — Sales JE is posted after the invoice transaction commits
- **Type:** Confirmed design risk. **Sev:** Medium. **Pri:** P2. **Conf:** High.
- **Where:** [sales_mutations_dao.dart:509-623](<../../../../lib/data/database/daos/sales_mutations_dao.dart#L509-L623>). Invoice, stock, safe and `parties.balance` commit first (`adjustPartyBalance` ≈:417). The JE is then posted outside the transaction. On failure: a `failed_autoposts` row, a 150 ms retry, and startup repair.
- **Impact:** A crash between the commit and the JE leaves cash/AR/inventory moved in the subledgers but not in the GL until the next start. A closed period or missing account makes this permanent until manual action. Visible as reconciliation differences.
- **Root cause:** The comment cites an SQLite deadlock with nested `transaction()` (517). Drift nested transactions use savepoints, so the deadlock claim should be re-examined.
- **Remediation:** Post the JE inside the same transaction (drift savepoint), or make `failed_autoposts` visible in the UI with alerting. **Effort:** M.
- **Acceptance:** A fault-injection test: throw in the autopost → either the invoice is rolled back, or a visible pending-posting alert exists and the startup repair posts it.

### DATA-006 — Purchase XLSX import does not normalise or validate tax rates
- **Type:** Confirmed defect. **Sev:** Medium. **Pri:** P2. **Conf:** High.
- **Where:** `taxRate: _parseDouble(row[9])` ([excel_service.dart:1246](<../../../../lib/data/services/excel_service.dart#L1246>)). `_normalizeTaxRate`/`TaxRatePolicy.assertAllowed` are used only by the product import (:364-372; grep).
- **Actual:** A `0.16` cell gives a 0.16 % VAT purchase invoice. Input VAT is understated by ~99 % for those lines.
- **Remediation:** Apply the same normalisation and policy check. **Effort:** XS.
- **Acceptance:** Test: a purchase import with 0.16 and with 16 → both give 16 %; 7 (not allowed) → row error.

### MIG-002 — Migrations are not transactional, although a comment says they are
- **Type:** Confirmed defect. **Sev:** Medium. **Pri:** P2. **Conf:** High.
- **Where:**
  - The comment "والترقية جوه ترانزاكشن" ([database_migrations.dart:33-34](<../../../../lib/data/database/database_migrations.dart#L33-L34>)) does not hold: drift 2.32.1 runs `beforeOpen`/`onUpgrade` via `_BeforeOpeningExecutor` with no wrapping transaction (`engines.dart:495-531`).
  - `runOnUpgrade` adds none (:66-87).
- **Impact:** A failure mid-upgrade leaves the DDL/data steps before it committed while `user_version` stays old, so the next boot replays everything. DDL replays are absorbed by `_safeMigrate`'s idempotent-error list. **Non-idempotent data steps** (UPDATE/INSERT backfills without guards) could double-apply; which epoch steps are non-idempotent was not enumerated.
- **Remediation:** Wrap `runOnUpgrade` in `transaction()` (SQLite supports transactional DDL), or audit every data step for idempotency. Fix the comment. **Effort:** M (audit).
- **Acceptance:** A test injects a failure at step N, reboots, and asserts the final state equals a clean upgrade.

### MIG-003 — `_safeMigrate` swallows "no such column"
- **Type:** Suspicion. **Sev:** Medium. **Pri:** P2. **Conf:** Medium.
- **Where:** [database_migrations.dart:21-40](<../../../../lib/data/database/database_migrations.dart#L21-L40>).
- **Risk:** A wrong column name in a new migration is skipped silently (logged with `debugPrint` only), and the schema or data fix never happens.
- **Remediation:** Restrict the skip to an allow-list of labelled legacy steps, and persist skips to `DiagnosticLogger`. **Acceptance:** A new migration with a typo fails a test.

### MIG-004 — Pre-migration backup is best-effort, not checkpointed, and rotates out good backups
- **Type:** Confirmed defect. **Sev:** Medium. **Pri:** P2. **Conf:** High.
- **Where:**
  - [database_migrations.dart:74-79](<../../../../lib/data/database/database_migrations.dart#L74-L79>): failure → `debugPrint` and the migration continues; no WAL checkpoint (by design).
  - Retention is 7 per DB, shared with startup/manual backups, and cleanup errors are ignored ([connection_io.dart:443-444, 574-599](<../../../../lib/data/database/connection_io.dart#L574-L599>)).
- **Impact:** A data-mutating migration (e.g. the v196 backfill that creates parties) may run with no backup, or with one missing WAL-resident commits. Repeated boots during a failing upgrade can rotate out the last good backup.
- **Remediation:** Make the backup mandatory for migrations that mutate data (abort the upgrade on failure). Keep pre-migration backups in a separate retention class. **Acceptance:** A test where the backup failure aborts the upgrade, and the pre-migration backup survives 7 later backups.

### MIG-006 — PG upgrade path untested; legacy SQLite unique indexes may silently not exist
- **Type:** Suspicion. **Sev:** Medium. **Pri:** P2. **Conf:** Medium.
- **Where:**
  - PG skips `onUpgrade` and relies on `beforeOpen` parity ([database.dart:851-853](<../../../../lib/data/database/database.dart#L851-L853>)). `pg_schema_parity_static_test.dart` is source-only (no DB).
  - `ensureSchemaDefaults` re-creates dedupe/unique indexes with `IF NOT EXISTS`, and per comments they "fail silently" on duplicate data (`database_startup.dart:137+`).
- **Risk:** A PG server created by an older build gets only additive parity (no data backfills such as v196 on PG; `FINAL-QA-VERDICT.md` says the backfill now runs on PG — not re-verified). On legacy SQLite DBs with duplicates, the uniqueness that the app relies on is absent.
- **Remediation:** A PG test that opens a schema created by an older release and runs the current boot. Log, and surface in diagnostics, any unique index that failed to create.

### MIG-007 — No upgrade test from a real old (encrypted) DB file with data
- **Type:** Missing requirement. **Sev:** Medium. **Pri:** P2. **Conf:** High.
- **Evidence:**
  - The v196 test builds a synthetic "v195" by dropping/recreating `table_reservations` on a fresh v196 DB and calls `runOnUpgrade` directly (prior A-8; `test/helpers/v195_reservations_db.dart`).
  - The many `migration_v1xx_*` tests are similar unit-level checks.
  - The owner's real v195→v196 upgrade succeeded per `FINAL-QA-VERDICT.md` (another worker's run; not reproduced here).
- **Remediation:** Check in an anonymised, encrypted fixture DB from N-2 releases; open it via the normal boot path in CI and run the reconciliation checks (TB balanced, party/GL, inventory/GL).

### BKP-002 — Restore validates key + `quick_check` only, with no schema-version check
- **Type:** Confirmed defect. **Sev:** Medium. **Pri:** P2. **Conf:** High.
- **Where:** `PendingRestore.canOpen` / `apply` ([pending_restore.dart:32-44, 80-121](<../../../../lib/data/database/pending_restore.dart>)).
- **Impact:** A backup from a newer build is accepted, which triggers MIG-001. `quick_check` skips index/content cross-checks that `integrity_check` does.
- **Remediation:** Read `PRAGMA user_version` in `canOpen`, reject `> schemaVersion`, and run `integrity_check` (time-boxed) before scheduling.

### BKP-003 — Backups are local-only; a checkpoint failure gives a silently incomplete backup
- **Type:** Confirmed defect. **Sev:** Medium. **Pri:** P2. **Conf:** High.
- **Where:**
  - Auto backup proceeds on checkpoint failure with a log line only ([connection_io.dart:376-391](<../../../../lib/data/database/connection_io.dart#L376-L391>), [:603-619](<../../../../lib/data/database/connection_io.dart#L603-L619>)).
  - Backups go to `Documents/backups` on the same disk.
  - `remote_backup_config` exists, but its runtime behaviour was not reviewed (only a config test exists).
- **Impact:** Disk loss or ransomware takes the DB and every backup. An "incomplete" auto backup can lack the latest day.
- **Remediation:** Surface backup health (last complete backup, location) in the UI. Retry the checkpoint later instead of copying incomplete data. Document or enable an off-device copy.

### BKP-004 — PostgreSQL mode has no in-app backup
- **Type:** Missing requirement. **Sev:** Medium. **Pri:** P2. **Conf:** High.
- **Where:** Auto backup is gated `if (!_isPostgres)` ([database_startup.dart:1738](<../../../../lib/data/database/database_startup.dart#L1738>)). Only docs mention `pg_dump` (`tools/postgresql_setup_guide.md:191`, `docs/mobile/ARCHITECTURE-I.md:179`).
- **Remediation:** Make the installer/server provision a scheduled `pg_dump` with retention, and expose its status, or state this explicitly as an operator responsibility in the release notes.

### DATA-004 — Missing DB-level constraints on ledger and catalogue tables
- **Type:** Improvement. **Sev:** Low. **Pri:** P3. **Conf:** High.
- **Where:**
  - `journal_entries.entry_number` has no UNIQUE, and `fiscal_year_id` has no FK ([accounting_tables.dart:49, 70](<../../../../lib/data/database/tables/accounting_tables.dart#L49>)).
  - `journal_entry_lines.cost_center_id` has no FK (:109).
  - There is no CHECK for `debit >= 0 AND credit >= 0 AND NOT (debit > 0 AND credit > 0)`.
  - Product barcode has a plain index only ([product_tables.dart:65](<../../../../lib/data/database/tables/product_tables.dart#L65>)).
  - Supplier invoice number is unique per supplier in the app only (a deliberate choice documented at `purchase_insert_support_dao.dart:162-165`).
- **Remediation:** Add partial UNIQUE indexes after a duplicate scan on real data. CHECK constraints need a table rebuild on SQLite, so add them on PG first.

### DATA-007 — CSV export has no formula-injection escaping
- **Type:** Confirmed defect (cross-ref security). **Sev:** Low. **Pri:** P3. **Conf:** High.
- **Where:** `_esc` quotes only `,`, `"` and newlines ([csv_import_export_service.dart:209-214](<../../../../lib/services/csv_import_export_service.dart#L209-L214>)). XLSX uses `TextCellValue`, which is lower risk.
- **Remediation:** Prefix `'` to cells starting with `= + - @ \t \r`.

### DATA-008 — Imported barcode not trimmed before the uniqueness check
- **Type:** Suspicion. **Sev:** Low. **Pri:** P3. **Conf:** Medium. Whether `assertBarcodeFree` trims internally was not checked.
- **Where:** `barcodeStr = row[2]?.value?.toString()` with no trim ([excel_service.dart:349](<../../../../lib/data/services/excel_service.dart#L349>)), and `assertBarcodeFree` (:442).
- **Risk:** `"123 "` and `"123"` coexist, so a scan finds the wrong or no product.
- **Acceptance:** Test: import `"123 "` when `"123"` exists → rejected.

### ACC-003 — Depreciation duplicate guard keys on the exact date (API path not normalised)
- **Type:** Suspicion. **Sev:** Low. **Pri:** P3. **Conf:** Medium.
- **Where:**
  - The guard is `periodDate.equals(periodDate)` ([fixed_assets_dao_ext.dart:452-458](<../../../../lib/data/database/daos/fixed_assets_dao_ext.dart#L452-L458>)).
  - Both UIs normalise to day 1 (`fixed_assets_picpos_screen.dart:1489`, `fixed_assets_dialogs.dart:1316`).
  - The API route passes the parsed client date through unchanged (`api_data_expenses.dart:345-358`).
- **Remediation:** Normalise to the first of the month inside the DAO.

### ACC-007 — `getArReconciliation` compares active customer cards with the whole AR subtree
- **Type:** Confirmed defect. **Sev:** Low. **Pri:** P3. **Conf:** High.
- **Where:** [party_reconciliation_dao.dart:266-268](<../../../../lib/data/database/daos/party_reconciliation_dao.dart#L266-L268>) vs [:293-303](<../../../../lib/data/database/daos/party_reconciliation_dao.dart#L293-L303>).
- **Impact:** A deactivated customer with a balance shows as a false AR difference and raises a false alarm (`reconciliation_service.dart:404`).
- **Remediation:** Drop the `isActive` filter (keep `deleted_at IS NULL`, or none).

### ACC-008 — Generic `reverseTransaction` would skip the 2nd and later reversals (no callers today)
- **Type:** Confirmed latent defect / Improvement. **Sev:** Low. **Pri:** P3. **Conf:** High.
- **Where:** [accounting_dao_writes.dart:1644-1655](<../../../../lib/data/database/daos/accounting_dao_writes.dart#L1644-L1655>) posts with `isAutoPosted: true, referenceId: referenceId`, and the dedup guard (:119-153) returns the first reversal's id for the next one. A grep of `lib/` finds no caller outside the delegating chain (`accounting_service.dart:332`, `sales_return_cancel.dart:21`). `journal_entries_screen.dart:1039` documents why it was abandoned.
- **Remediation:** Remove it, or pass `allowRepost: true` / `referenceId: entry.id`, as `reverseJournalEntryById` does.

### ACC-009 — JE number year taken from `now()`; vouchers pre-check the period with `now()`
- **Type:** Confirmed defect. **Sev:** Low. **Pri:** P3. **Conf:** High.
- **Where:**
  - `_generateEntryNumber` uses `DateTime.now().year` ([accounting_dao_reads.dart:167-170](<../../../../lib/data/database/daos/accounting_dao_reads.dart#L167-L170>)), so back-dated December entries posted in January get `JE-<new year>-…`.
  - Voucher pre-checks use `DateTime.now()` (`treasury_voucher_dao.dart:149, 360`). `createJournalEntry` re-checks with the entry date, so this is only an early-UX inconsistency.
- **Remediation:** Pass the entry date into the number generator.

### ACC-010 — Balance tolerance fixed at 0.01 regardless of currency decimals
- **Type:** Improvement. **Sev:** Low. **Pri:** P3. **Conf:** High.
- **Where:** [financial_utils.dart:38-43](<../../../../lib/core/utils/financial_utils.dart#L38-L43>). The tolerance is 10 minor units for JOD (3 dp) and 1 for EGP (2 dp). Differences up to 0.01 JOD are auto-booked to `rounding_difference` on the server.
- **Remediation:** Express the tolerance in minor units (e.g. `n × 10^-decimals`) and test it per currency.

### RPT-008 — Tax screen header (GL) and detail (invoices) come from different sources
- **Type:** Improvement. **Sev:** Low. **Pri:** P3. **Conf:** High.
- **Where:** `getTaxReport` reads GL accounts (`accounting_reports_dao.dart:819-904`). `tax_report_picpos_screen.dart:59-63` lists invoices (`getSalesByDateRange`, `getSalesTaxByRate`). With a warehouse filter, manual VAT JEs from all warehouses are kept (:868-869).
- **Remediation:** Show a reconciling line (GL − invoices) on the screen. `getVatReconciliationData` already exists.

### RPT-009 — Dead audit/aging queries reference non-existent columns and wrong epoch units
- **Type:** Improvement. **Sev:** Low. **Pri:** P3. **Conf:** High.
- **Where:** [accounting_audit_dao.dart:24-200](<../../../../lib/data/database/daos/accounting_audit_dao.dart#L91-L163>). These functions use `s.paid_amount` and `payment_status` on `sales_invoices`/`purchase_invoices`, which have `paid`, not `paid_amount` (`sales_purchase_tables.dart:148, 313`). They also use `created_at / 1000`, although Drift stores seconds. `scanFraudAlerts`, `getReceivablesAging`, `getPayablesAging` and `validatePeriodClosing` have **no callers** in `lib/` (grep).
- **Remediation:** Delete them, or fix and test them before wiring anything to them.

### MIG-005 — v196 backfill divergences from the plan
- **Type:** Suspicion. **Sev:** Low. **Pri:** P3. **Conf:** Medium.
- **Where:** [reservation_parties_backfill.dart](<../../../../lib/data/database/reservation_parties_backfill.dart>), [epoch_3_v196_v205.dart:15-22](<../../../../lib/data/database/migrations/epoch_3_v196_v205.dart#L15-L22>).
- **Divergences:**
  - (a) It runs inside `onUpgrade`, before seeding, while the plan (line 264) says startup. A retry from startup exists.
  - (b) Several customers with the same normalised phone → the lowest id is picked silently (≈:216). B.10 §5 says manual choice, but that is for interactive use; F.1 is silent.
  - (c) The in-memory `byPhone`/`byName` maps are updated inside each group's transaction and not rolled back when it fails. A later group in the same run can then link to an uncommitted party id; the FK would fail that group too.
  - (d) Rule (b) links only when exactly one same-name, no-phone customer exists. It records a `name_match_phone_filled` suspect row, which addresses prior A-3.
- **Remediation:** For (b), log a suspect row for every multi-match. For (c), reload the maps after a failed group.

### BKP-005 — Key sidecar stored beside every backup
- **Type:** Suspicion (refer to security axis). **Sev:** Low (pending analysis). **Pri:** P3. **Conf:** Low.
- **Where:** `BackupSidecars.writeFor` writes "key type + fingerprint + recovery wrapper" next to each backup and is copied on export ([connection_io.dart:432, 633](<../../../../lib/data/database/connection_io.dart#L432>)).
- **Question:** Can the recovery wrapper be unwrapped without a user-held secret? If so, an exported backup plus its sidecar is effectively plaintext. Not analysed here.
