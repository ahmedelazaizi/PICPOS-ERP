# Axis B — Coverage

**Version:** `d69be1eafc7d82b924723dfdbb53960b7e33acdb`.
**Method:** static code reading, plus drift library source and prior run logs.

This auditor ran 6 read-only reader passes, each covering a sub-area. Every reader claim used in FINDINGS-B.md was re-checked by me against source. Three claims were corrected:

- Purchase re-import is **not** duplicated: the DAO rejects a reused supplier invoice number (`purchase_dao.dart:252`).
- Generic `reverseTransaction` has **no callers**, so ACC-008 is downgraded to latent.
- Status-filter gaps are mostly moot, because void sets `is_deleted=1`.

**Status legend:** PASS = area reviewed, no defect found · FAIL = defect recorded · PARTIAL = reviewed with gaps noted · NOT_RUN · NOT_APPLICABLE.

| # | Area | Scope reviewed | Method | Status | Findings / notes |
|---|---|---|---|---|---|
| 1.1 | PK/FK/UNIQUE/CHECK | `accounting_tables`, `sales_purchase_tables`, `product_tables`, `restaurant_tables`, `inventory_tables`; `foreign_keys=ON` | Read | FAIL (minor) | DATA-004 |
| 1.2 | Soft-delete consistency in reports | TB, IS, BS, CF, ledger, tax, hierarchical TB, posting/VAT/inventory recon, party statement, party calc balance, aging ×2, sales analytics, sales summary, purchase reports/summary, budgeting, treasury shift, cycle count, returns analytics | Read + grep | FAIL | RPT-001, RPT-002, RPT-004, RPT-005, RPT-007 |
| 1.3 | Analytics engine `lib/domain/analytics/*` | Data sources only (pure Dart over DAO maps) | Read | PASS (inherits DAO filters) | Ratio-grading defects from the prior review (C-7) were not re-verified |
| 1.4 | Money types and rounding | `financial_utils.dart`, `app_constants.dart`, `createJournalEntry` rounding | Read | PARTIAL | ACC-010; REAL storage is a documented decision (FA-04) |
| 1.5 | Dates and time zones | epoch seconds vs ms, range bounds | Read | FAIL | RPT-005, RPT-009; no TZ normalisation found (local time) |
| 1.6 | PG vs SQLite divergences | `sqlBool`, `PgCompatSql.fixSql`, compat operators, aging SQL | Read | FAIL | RPT-003; raw boolean literals are mitigated by the PG compat cast |
| 2.1 | Double-entry at write time | `createJournalEntry`, `approveJournalEntry`, `JournalBalance` | Read | PASS | — |
| 2.2 | Auto-posting per module | Sales cash/credit, returns, purchases, purchase returns, vouchers, payroll, depreciation, disposal, inventory adjustments/transfers, manufacturing, FX, booking deposit | Read (call sites; bodies for sales, depreciation, FX, booking, vouchers) | FAIL | ACC-001, ACC-002, ACC-004, ACC-005, DATA-005. Treasury transfer, purchase void and landed-cost bodies not read in detail (PARTIAL) |
| 2.3 | Zero-cost / COGS | `zero_cost_policy` | Read | PASS (policy explicit) | With missing COGS/inventory accounts, COGS lines are dropped silently (noted; not raised separately) |
| 2.4 | Period closing / locking | `validateFinancialPeriod` on the write path | Read | PASS | ACC-009 (minor) |
| 2.5 | Reversal / void | `reverseJournalEntryById`, `reverseTransaction`, invoice void | Read | PASS with latent issue | ACC-008 |
| 2.6 | Tax amounts / e-invoice hooks | `calculateInvoiceTotals`, `getTaxReport`, JoFotara/ETA file locations | Read | PARTIAL | RPT-004, RPT-008, DATA-006; e-invoice payload correctness not reviewed |
| 2.7 | Deposits / advances | Booking deposit | Read | FAIL | ACC-004 |
| 2.8 | Party balance vs GL | `adjustPartyBalance`, mismatch check, AR reconciliation | Read | FAIL | DATA-003, ACC-007, DATA-005 |
| 2.9 | Inventory vs GL | `getInventoryGlReconciliation` | Read | PASS | — |
| 3 | Cross-screen report consistency | Dashboard vs sales report; tax header vs detail; flat vs hierarchical TB; statement vs card | Read | FAIL | RPT-001, RPT-004, RPT-005, RPT-008 |
| 4.1 | Migration strategy / epochs | `database.dart`, `database_migrations.dart`, epoch file list, drift internals | Read | FAIL | MIG-002, MIG-003, MIG-004 |
| 4.2 | v196 backfill vs plan §F.1 | `reservation_parties_backfill.dart`, `phone_normalizer.dart`, plan §F | Read | FAIL (minor) | DATA-002, MIG-005 |
| 4.3 | Upgrade from an old DB with data | Tests inventory | Read | NOT_RUN | MIG-007 |
| 4.4 | Downgrade / forward-compat | drift source + app | Read | FAIL | MIG-001 |
| 4.5 | SQLCipher key at open | `connection_io.dart`, `db_key_*` | Read | PASS | — |
| 4.6 | PG schema parity | static test, runner script | Read | PARTIAL | MIG-006 |
| 4.7 | `ensureSchemaDefaults` | `database_startup.dart:137+` | Read (reader report) | PARTIAL | MIG-006 |
| 4.8 | Failure mid-migration | drift + `_safeMigrate` | Read | FAIL | MIG-002 |
| 5.1 | `createDatabaseBackup`, WAL checkpoint, retention | `connection_io.dart` | Read | FAIL | BKP-003, MIG-004 |
| 5.2 | Restore path | `pending_restore.dart`, `db_key_startup.dart` | Read | FAIL | BKP-002 |
| 5.3 | Restore actually tested | Test inventory | Read | FAIL (missing) | BKP-001 |
| 5.4 | Backup protection | Encrypted copy + key sidecar | Read | PARTIAL | BKP-005 (to security axis) |
| 5.5 | PG backup | Docs / startup | Read | FAIL (missing) | BKP-004 |
| 6.1 | XLSX import idempotency / barcode / tax | `excel_service.dart`, `excel_import_result.dart` | Read | FAIL | DATA-003, DATA-006, DATA-008 |
| 6.2 | Export accuracy and masking | Excel/CSV exports, masking registry | Read | FAIL | RPT-006, DATA-007; PDF report figure accuracy NOT_RUN |
| 6.3 | Attachments | DB blobs; file name not sanitised | Read (reader) | PASS (no FS write path) | Note only |
| 7.1 | Manufacturing | Posting accounts | Read (call sites) | PARTIAL | BOM cost roll-up not verified numerically |
| 7.2 | Payroll | Engine rounding + posting | Read (reader) | PASS | — |
| 7.3 | Fixed assets | Depreciation formula, posting, disposal | Read | FAIL | ACC-001, ACC-002, ACC-003 |
| 8 | Known open defects re-verification | 6 listed + prior C-1/C-2/C-6/A-1/A-7 | Read | Done | Table in FINDINGS-B.md |
| — | Sync of reservations | Push paths | Read + grep | FAIL | DATA-001 |

## Not covered / limits

- No dynamic execution by this auditor (see TEST-EVIDENCE-B.md §4).
- I did not trace the side effects of every void flow on `safe_transactions`. This is why the net effect in RPT-001 is rated Medium confidence.
- I did not compare FX revaluation sign conventions with the accounting policy.
- I did not verify the correctness of the e-invoice (JoFotara/ETA) payload amounts.
- I did not measure performance of migrations or reports on large data.
- I did not verify `remote_backup_config` runtime behaviour.
