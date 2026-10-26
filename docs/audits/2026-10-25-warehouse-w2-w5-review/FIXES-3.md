# FIXES-3 — third fix round of the W2–W5 warehouse review (2026-10-26)

Base: `fd47ac6f`, branch `feat/tables-reservations-permissions`. Nothing committed. No Drift table or `schemaVersion` change, `database.g.dart` untouched, no build_runner, no APK. The login / setup / deployment / offline-login files edited by the other worker are not part of this round.

Method: a failing reproduction first; "proven failing" = the test was run with the fix removed locally (restored afterwards) and failed.

## A. Mirror console may use the receipts desk (owner decision 2026-10-26) — FIXED-PROVEN
- Root cause: `LanDeviceRoutePolicy.mirrorDeniedPaths` (`/api/m1/wh`) and `WhHttp.runDesk` refused a mirror with `403 device_scope`.
- Fix:
  - `lib/services/api/lan_device_route_policy.dart`: `mirrorAllowedPaths = ['/api/m1/wh/desk']` is checked before the denied list; the phone API stays closed to a mirror.
  - `lib/services/api/m1_wh/wh_http.dart`: `runDesk` refuses only `warehouse`; a mirror needs `mirror_console` (re-checked) + `purchases_create`; the handler receives `mirror: true`. The acting user is the signed-in mirror user (`MirrorConsole.guard` already stamps `actorUserId`/`userId` from the session).
  - `lib/services/api/m1_wh/wh_receipts_inbox.dart`: `WhReceiptsInbox(db, mirror: true)` applies the user's BRANCH scope (`MirrorConsole.scopeOf`) on list AND convert; a user with no explicit warehouse rows is limited by branch alone.
  - `lib/services/api/m1_wh/wh_receipts_source.dart`: any network failure ⇒ `WhError('host_unreachable', 503)`; the stable code is read from `code` then `error` (mirror guard codes). `wh_receipts_inbox_dialog.dart` + 3 `en.json` keys (appended) say it in words.
- Tests: `test/e2e_fleet/wh_desk_receipts_client_test.dart`, group `mirror console` (real host + mirror peer): list + convert as the manager (invoice 1, stock 6, AP 240, `approved_by` and every activity-log row = manager id, replay `replayed:true`, one invoice); no `purchases_create` ⇒ 403 `permission_denied`; `mirror_console` revoked ⇒ 403 `mirror_console_denied`; a user without `mirror_console` cannot sign in on the mirror; multi-branch (manager of ALL sees both receipts; narrowed to B1 sees only B1, B2 convert ⇒ 404 `doc_not_found`, nothing posted); host down ⇒ `host_unreachable` 503, no local invoice, no outbox, works after `mainUp`. `test/unit/api/mirror_device_pairing_test.dart` (policy matrix), `test/widget/wh_receipts_inbox_dialog_test.dart` (offline text AR/dark + EN/light). Proven failing with the policy line removed (4 of the mirror tests fail).

## B. WH-010 — approval proof bound to a document — FIXED-PROVEN (phone UI wired for transfers)
- Root cause: the proof was bound to a permission code only (any operation of that code within 5 minutes), could not be obtained by a phone (`/api/approvals/grant` is closed to `warehouse` devices), and the approver's warehouse scope was never checked.
- Design / implemented contract: plan §«WH-010» in `docs/plans/2026-10-23-warehouse-app-plan.md`.
- Fix files: `lib/services/api/approval_proof.dart` (+`doc`/`dop`/`dv` claims), new `lib/services/api/m1_wh/wh_doc_approval.dart` (7.8 KB: `WhApproval.approverOf` + `WhApprovalProofIssuer`, route `POST /api/m1/wh/approvals/proof`), `wh_http.dart` (old `approverOf` removed), `wh_stock_doc_handlers.dart`, `wh_count_handlers.dart`, `wh_approval_handlers.dart`, `routes/api_routes_m1_wh.dart`, `test/golden/api_routes.txt`; client `packages/picpos_api_client` (`approvalProof`, `WhApprovalProof`); phone `mobile_warehouse/lib/screens/supervisor_proof.dart`, `transfer_pages.dart`, `strings.dart`, `wh_session.dart` (domain codes).
- Tests (`test/integration/wh_doc_bound_approval_test.dart`, 13): happy path (stock 20→17, `approved_by` = supervisor, replay once), forged, expired, wrong document, wrong operation (both directions), stale version, replay on another operation, other device, plain P5 proof refused, creator==approver (issue + use) and requester==approver, wrong password / no permission / outside warehouse scope / unknown doc / bad action, non-pending doc, supervisor without proof, `/api/approvals/grant` still closed to a phone. The old `wh_voucher_flow_test` case that accepted an unbound proof was changed to assert the refusal. Client: `wh_doc_client_test.dart`; phone: `docs_flow_test.dart` (wrong password then success; the proof header reaches the approve call).
- Limits: counts are bound to task + operation without a version; the proof is burned by a refused attempt; the phone UI exists for transfer approval only (voucher/count UI not wired — the contract works for them).

## C. WH-021 — PO receipts reach the clients — FIXED-PROVEN (no schema change)
- Root cause: `addReceivedQuantity` (phone receipt submit) wrote `purchase_order_items.received_quantity` with a raw UPDATE that did not touch `last_modified_at`/`row_version` of the line or the order, so the clients' delta pull (`last_modified_at > since`) never re-sent it.
- Fix: `lib/services/api/m1_wh/wh_stock_guard.dart` stamps the line and its order strictly above their previous stamp (portable `CASE`, SQLite + PG). `PurchaseOrdersRepository.orderIdsWithReceipts()` (interface + impl) and `purchases_picpos_crud.dart` hides orders with receipts from «pull PO» (stale comment replaced; file size 30,441 ≤ 30,733 baseline). Phone documents themselves stay on the host (read through `desk/receipts`, A) — no new table.
- Tests: `test/e2e_fleet/wh_po_received_sync_test.dart` (real host + client peer: 6 then 10 received are visible on the client after the delta pull; `orderIdsWithReceipts` = only the partial order). Proven failing with the old UPDATE (`Expected 6, Actual 0.0`).

## D. Leftovers
- **NEW-04 — FIXED-PROVEN.** `purchase_orders_dao.dart` `convertPOToInvoice` now carries line `taxRate`/`taxAmount`, the order `costCenterId` and the document discount (header + lines) like `WhReceiptPosting`. `test/integration/wh_legacy_po_convert_test.dart`: tax 60.8, cost centre, stock 10, supplier balance 440.8. Proven failing without the carry (`Expected 1, Actual null`).
- **WH-009 — FIXED-PROVEN (PG).** `wh_concurrency_pg_test.dart` `WH-009 (proof)`: a `count_submission`/`cycle_count_task` row with ref_id `legacy-not-a-number` passes every filter, so the old `CAST(d.ref_id AS INTEGER) = t.id` fails on PostgreSQL 16 with `22P02 invalid input syntax for type integer` (run locally against the old expression: FAILED; with `d.ref_id = CAST(t.id AS TEXT)`: passes; expression restored).
- **WH-019 / WH-020 / WH-014 — not done** (not trivial: batch-ledger unification, version checks on all commands, overlap/recount policy).
- **WH-017 — plan status updated, gates NOT closed.** G-2 (APK brand check in CI) and G-3/SEC-006 (closing the legacy shared bearer for new servers) remain OPEN; G-3 was deliberately not touched in this batch.

## Verification (what was actually run)
- `dart analyze lib test`: no errors, only the 2 known infos (`purchase_returns_picpos_logic.dart:48`, `sales_returns_picpos_logic.dart:84`).
- Structural/unit/static batch (`file_size_ratchet`, `i18n_coverage`, `picpos_permission_parity`, `permission_enforcement_coverage`, `brand_artifact_guard`, `presentation_db_import_guard`, `test/static`, `test/unit/api`): +229 all passed.
- 27 files: every `test/integration/wh_*`, every `test/e2e_fleet/wh_*`, `api_routes_golden`, `sync_strategy_endpoints_exist`, `sync_coverage_guard`, widget `wh_receipts_*`, `mirror_device_pairing`, `four_eyes_approval_host`, `mirror_console_fleet`, `wh_mobile_docs_schema`: +178 all passed.
- `mobile_warehouse`: `flutter analyze` clean; `flutter test` +121 (1 skipped) passed. `packages/picpos_api_client`: `flutter test` +93 (1 skipped) passed.
- PG: `dart run scripts/run_pg_tests.dart` was NOT run (past the 100-minute mark). Instead the three `test/integration_pg/wh_*_pg_test.dart` files were run one by one against a local `postgres:16-alpine` container (`--tags pg --run-skipped`): concurrency +5, mobile_docs +4, two_connection +4, all passed. The rest of `test/integration_pg/` was not run.
- `tool/run_e2e.ps1`: see the final report (started at 15:23; result stated there).

## Not verified / notes
- No physical phone, no APK build, no lab run.
- Two mid-session `Stop-Process` sweeps of `dart`/`flutter` processes (made to clear a stuck run) may have killed a test run of the other worker; flutter runs collided repeatedly on `sqlite3.dll` (`PathExistsException`) because both workers run flutter in the same tree.
