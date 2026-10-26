# FIXES-2 — second fix round of the W2–W5 warehouse review (2026-10-26)

Base: `b44098a7`, branch `feat/tables-reservations-permissions`. Nothing committed. No Drift table or `schemaVersion` change, `database.g.dart` untouched, no build_runner. Every line below was run unless it says otherwise.

Method: a failing reproduction first, then the fix. "Proven failing" means the test was run with the fix removed locally (restored afterwards) and failed.

## 1. WH-001 (critical) — partial PO invoiced in full from a client / mirror — FIXED-PROVEN
- Root cause: `ClientWriteInterceptor.submitPurchase` never sent the pulled order, `api_purchase_handler.dart` never forwarded `sourceOrderId`, so no guard ran on the host; `convertPOToInvoice` on a client built a LOCAL invoice from a stale local copy.
- Fix:
  - `lib/services/interceptor/cwi_trading_purchases.dart`, `cwi_core.dart`: `submitPurchase(sourceOrderGlobalId:)` is sent in the payload (a client's local id differs from the host's, so the GLOBAL id travels).
  - `lib/data/repositories/purchases_repository_impl.dart`: «pull PO» passes the order's global id (`PurchaseOrdersDao.purchaseOrderGlobalIdOf`).
  - `lib/data/repositories/purchase_orders_repository_impl.dart`: on a client/mirror `convertPOToInvoice` submits to the host (order global id) instead of building a local invoice; server/standalone keep the local DAO path.
  - `lib/services/api/api_purchase_handler.dart`: resolves `sourceOrderGlobalId` → host order, passes `sourceOrderId` to `createPurchaseInvoice` (guard + consumption in the invoice's own transaction), answers a refusal `409 {error: <code>}`, broadcasts `purchase_orders`.
  - `lib/data/database/daos/purchase_orders_dao.dart`: typed `PurchaseOrderNotConsumable` (codes `po_not_found`, `po_cancelled`, `po_already_converted`, `po_has_receipts`, `po_over_invoiced`); `_requireInvoiceWithinOrder` (called from `_markPurchaseOrderConverted`, on the invoice's STORED lines inside its transaction) also refuses an invoice above the ordered quantity per product; consuming an order books its lines as received (`received_quantity = quantity`) in the same transaction, so a late phone receipt is `over_receipt`.
  - Owner design kept (plan §B.2-3): an order with phone receipts is invoiced ONLY through the receipt conversion (`WhReceiptPosting`); the legacy paths refuse it. Per-line PO item ids are NOT sent: the guard works per product (documented limit).
  - `lib/services/api/api_server_error_log.dart` (new, 0.9 KB): the handler's error-log helper moved out to keep the ratchet.
- Tests (real host + client peer over HTTP): `test/e2e_fleet/wh_po_host_authority_test.dart` — `partial phone receipt, then a client convert / pull-PO: host refuses…` (409 `po_has_receipts`, host invoices 0, stock 0, AP 0, client has no local invoice), `a healthy order is consumed on the host…` (invoice qty 12 × 40, stock 12, AP 480, PO converted/received 12, second invoice 409 `po_already_converted`), `an invoice above the ordered quantity is refused (409 po_over_invoiced)`, `pull-PO through ClientWriteInterceptor.submitPurchase…` (stock 5, AP 200). Proven failing: with the host's `sourceOrderId` forwarding removed, 4/4 fail. Existing `wh_receipt_conversion_integrity_test.dart` still passes.
- Known limit: on a client the submit is fire-and-forget (outbox on any failure), so the client user sees the refusal only as a parked outbox entry; on a mirror it is awaited and throws.

## 2. WH-002 — accountant receipts on a client desktop — FIXED-PROVEN (mirror by policy refused)
- Root cause: the dialog read the LOCAL database; the phone documents live only on the main.
- Fix: `lib/services/api/m1_wh/wh_receipts_source.dart` (new): `WhReceiptsSource` with `WhLocalReceipts` (server/standalone; failures pass through `classifyWhFailure`) and `WhRemoteReceipts` (client; `GET /api/m1/wh/desk/receipts`, `POST …/convert` with the stable key `desk-convert-<gid>` so a lost answer is a replay); `lib/services/server_proxy/server_proxy_wh_desk.dart` (new, `whDeskCall`); `lib/data/providers/wh_receipts_inbox_provider.dart` picks the source by mode; dialog maps `device_scope`; one new `en.json` key (append). The main keeps permission (`purchases_create`), warehouse scope and the device policy.
- DECISION to confirm: a **mirror** console stays refused (`403 device_scope`) — `LanDeviceRoutePolicy.mirrorDeniedPaths` and `runDesk` both deny it by the owner's M1 design; the dialog tells the user to use the main/branch device. Opening it to mirrors is a one-line policy change plus a test, not done.
- Tests: `test/e2e_fleet/wh_desk_receipts_client_test.dart` (real host, accountant client: the client's DB has no phone tables; list shows the receipt; convert → 1 invoice, stock 6, AP 240, PO stays open 6/12; same key = replay, another command = 409 `invalid_transition`; cashier → `permission_denied`/403; mirror → 403 `device_scope`); `test/widget/wh_receipts_inbox_dialog_test.dart` (AR/dark + EN/light: list, convert once, refusal shown); `test/widget/wh_receipts_button_test.dart` (RTL/LTR: button with `purchases_create` opens the dialog, hidden without).
- Not changed: the 200-row `store.list` cap and the `api_rate_limiter` classification warning for `/api/m1/wh/*` (pre-existing, only logged).

## 3. NEW-02 — same idempotency key racing → false 409 — FIXED-PROVEN
- Root cause: both requests pass the replay check, the loser hits the UNIQUE key of the winner's rows and the classifier made it a final `409 duplicate_document`.
- Fix: `wh_doc_store.dart` `command()` — on a unique violation (`isUniqueViolation`, new in `wh_error_classifier.dart`) it re-reads the stored command result outside the aborted transaction and answers it as a replay (`replayed: true`, 200); a different payload under the key is still `idempotency_conflict`.
- Tests: `test/integration_pg/wh_two_connection_pg_test.dart` `NEW-02…` (two real PG connections: both answer, one `replayed`, one document, one event) — proven failing without the fix; SQLite twin `test/integration/wh_idempotent_race_test.dart` (both 200, one replayed; SQLite serialises, so it is a regression guard, not a proof of the race).

## 4. WH-006 — PG concurrency test — FIXED-PROVEN
- `test/integration_pg/wh_two_connection_pg_test.dart` rewrites it with two `AppDatabase` instances (`openExtraPgConnection()` added to `_support/pg_fixture.dart`): A holds the balance row mid-withdrawal, B tries. Result `[true,false]`, stock 2. Proven failing with `lockBalanceRow` disabled (`[true,true]`). The weak shared-database withdrawal test was removed from `wh_concurrency_pg_test.dart`; the 6+6 receipt test also runs on two connections.

## 5. WH-008 / WH-009 / WH-028
- WH-008 — FIXED-PROVEN. `cycle_count_repository_impl.dart`: a pass still in DRAFT blocks the desktop completion (`hasPhonePasses` counts `draft`+`submitted`), check + finalize share one transaction, errors are the typed `CycleCountRefused(code)` (`recount_required`, `self_approval`, `count_not_submitted`, `approver_required`, `permission_denied`). `wh_count_integrity_test.dart` asserts the exact codes (no more `throwsA(anything)`) and adds the draft case.
- WH-009 — PARTIAL. `wh_blind.dart` compares `d.ref_id = CAST(t.id AS TEXT)` (PG-safe by construction, no integer cast of a text column). PG test `WH-009: with NON-NUMERIC ref_id rows…` passes, but it did NOT fail with the old `CAST(ref_id AS INTEGER)` on PG 16 (the planner filters `kind`/`ref_type` before the cast), so it is a regression guard, not a failing-first proof.
- WH-028 — FIXED-PROVEN. `api_data_inventory.dart` `postStockTransfer`: user = authenticated session user only (body `userId` ignored); source warehouse must be in the user's warehouse scope (`403 warehouse_scope`); duplicate detection runs inside the transfer transaction and a unique-violation race answers `dedup` 200. Tests in `wh_lan_transfer_route_test.dart` (scope 403 with stock untouched, bond `createdBy` = session user although the body says another, two simultaneous requests move stock once). `api_data_handler.dart` +1 import line.

## 6. NEW-03 — busy vs dead_letter, retry/discard — FIXED-PROVEN
- `mobile_warehouse/lib/sync/wh_outbox.dart`: 503/`busy` has its own counter (`busyCount`, backoff, never dead-letters); `retry(e)` re-queues a `dead_letter` entry under the same id; `dismiss` now keeps `status=rejected, error=dismissed` (WH-023: never recorded as accepted; `picpos_device` `isDrained()` treats it as settled; the counters ignore it). `outbox_page.dart`: «Retry» for dead_letter, discard asks for confirmation; 4 strings in `strings.dart`.
- Tests: `outbox_drain_test.dart` (12 busy answers → still pending, `serverFailures` null, then accepted; retry keeps the id and is refused for a normal rejection; dismissal is not `accepted`), `outbox_page_test.dart` (EN/light, AR/dark: retry visible only for dead_letter, discard dialog cancel/confirm, LTR-isolated counts). `fake_office.dart` gained `busyReplies`. Two outbox goldens regenerated (`docs_outbox_en_dark_phone`, `docs_outbox_en_light_tablet`: invisible isolates changed the pixels; checked visually).

## 7. Remaining PARTIAL items
- WH-012 — server side now proven: `test/integration/wh_transfer_damaged_receive_test.dart` (5 dispatched, 3 ok + 1 damaged: state `received_short`, destination 4 until the pending damage voucher is approved → 3, journal balanced; `over_receipt` 409 above the dispatched). Not done: supplier-claim / purchase-return document for the damaged part of a PO receipt (owner decision).
- WH-014 — unchanged (filter-before-limit already proven); overlap prevention and the recount path remain DEFERRED (behaviour decision).
- WH-016 — FIXED: `wh_blind_count_leak_test.dart` now asserts exactly `404` (not `anyOf`), `label_builder_test.dart` asserts the emitted barcode string; `throwsA(anything)` replaced under WH-008.
- WH-018 (PG) — FIXED-PROVEN: `_audit` writes the log line under a `SAVEPOINT` on PostgreSQL; `wh_two_connection_pg_test.dart` `WH-018…` (activity_logs renamed so the INSERT fails: command still commits, doc 1 + event 1) — proven failing without the savepoint.
- WH-022 — FIXED for the listed sites: numbers LTR-isolated with `ltr()` in `transfer_pages.dart`, `count_pages.dart`, `outbox_page.dart`, `labels_page.dart` (`outbox_page_test.dart` asserts the isolate in the counts line).
- WH-023 — FIXED (see §6).
- WH-025 — FIXED-PROVEN: `test/unit/wh_mobile_docs_schema_test.dart` (failed first attempt is retried; concurrent callers share one future).
- WH-017 — NOT FIXED, documented: `docs/plans/2026-10-23-warehouse-app-plan.md` now states G-2 and G-3/SEC-006 are OPEN and why (no commit hash on the lab run, no voucher or A→B→A scenario, no APK brand check, no session revocation). No APK built, no lab used.
- DEFERRED unchanged: WH-010 (owner decision: bind the approval proof to a document), WH-015 (no Android 12+ device), WH-019 (Low/P3), WH-020, WH-021 (owner decision on syncing PO receipts to clients), WH-030 (owner decision). WH-001's host-side guard also removes the stale-`received_quantity` dependency of WH-021 for invoicing.

## Not verified / limits
- NEW-04 (legacy `convertPOToInvoice` drops tax/cost-centre) untouched.
- Client «pull PO» sends no per-line PO item ids; the over-invoice check is per product.
- `dart run scripts/run_pg_tests.dart` and `tool/run_e2e.ps1` results are in the final report, not here.