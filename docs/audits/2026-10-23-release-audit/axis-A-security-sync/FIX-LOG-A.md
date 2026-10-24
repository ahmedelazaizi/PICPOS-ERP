# Axis A — Fix log (security / authz / sync)

Companion to [FINDINGS-A.md](<FINDINGS-A.md>). One line per finding: status, tests, notes.

## Decision record — figure visibility rule (AUTHZ-002/003/004, RPT-006)

Owner rule: *figures are hidden from users without the screen's VIEW permission.*

| Surface | Rule |
|---|---|
| Sales invoices — list, KPI cards, details dialog (prices, totals, paid/remaining) | `sales_view` **AND** `sales_amounts_view` (system admin bypasses). `sales_view` alone no longer reveals amounts; `sales_amounts_view` alone doesn't either. Default roles hold both, so they are unaffected. Encoded in `kSalesFiguresCodes` (+ `screenFigureAllOfCodes`). |
| Invoice details — profit margin | the rule above **and** `products_cost_view` or `dashboard_profit` (AUTHZ-007). |
| Other screens (purchases, inventory, parties, …) | unchanged: any code in `screenFigurePermissionCodes` (the screen's view code or a registered figure code). |
| Party statement | the screen's view code (`customers_view` / `suppliers_view`). |
| Party export | view code **and** `reports_export` (a dedicated `customers_export` code is deferred — see below). |
| Party import | `customers_add` + `customers_edit` (or the supplier pair); never writes `balance` of an existing party (DATA-003). |
| Products template export (cost + prices, also the import template) | `products_price_view` **and** `products_cost_view`. |
| Customer picker card | balance / debt chip only with `customers_view`. |

Manager approval (AUTHZ-001): the approver must be a **different user** holding the code **unconditionally**
(`cond:` holders cannot approve); system admin approves except `criticalFinancialOps`. A single-user
installation therefore cannot self-approve a gated action — create a second manager.

## Status per finding

| ID | Status | Notes |
|---|---|---|
| SEC-001 | fixed | `_ensureBootstrapAdminOnce` no longer inserts `admin`/`admin`; logs a `SECURITY` line. PG test updated. |
| SEC-002 | fixed | `/api/auth/session` and `/api/auth/verify-admin` → 403 `password_change_required` for `force_password_change` users. Consequence: a forced-change user on a client terminal gets no host session until the password is changed on the host. |
| SEC-003 | fixed | token TTL 30d → 12h, `iat`, per-user revocation (`revokeUser`, already called on deactivate/lock/delete/password change), `requirePermission` rejects inactive/locked users (401). GET paths rely on the 12h TTL (middleware has no DB). Revocation list is in-memory (host restart clears it; the active/locked check is persistent). |
| SEC-004 | fixed | `UnusableCredential` (random, discarded secret) replaces `<username>123` in both sync paths. |
| SEC-005 | deferred | needs a persistent owner prompt + migration UX (owner decision "no automatic migration"). |
| SEC-006 | partly | legacy bearer now compared in constant time. Window-on-fresh-install **deferred**: a fresh install cannot be told apart from an upgraded host with legacy clients without a new marker. |
| SEC-007 | deferred | TLS-by-default + pinning at pairing is a deployment/UX change. |
| SEC-008 | fixed | `GET /api/parties` and `/api/sync/pull?table=parties`: no `balance`/`credit_limit` without a verified identity (and the pull returns `serverTime: null`); branch-restricted sessions only get global parties + parties whose `branch_ids` include their scope. |
| SEC-009 | fixed | `LoginLockoutStore` persists lockouts in `settings`; override dialog limited to 5 attempts / 15 min per requesting user. Close-shift password dialog **not** covered. |
| SEC-010 | deferred | raising Argon2 cost needs a latency benchmark on POS hardware. |
| SEC-011 | fixed | both boot heals set `force_password_change`. |
| SEC-012 | fixed | `.gitignore` patterns added. |
| SEC-013/014 | deferred | CI / deployment, not code. |
| SEC-015 | fixed | unsafe printer names skip the `cmd /c` fallbacks; unique temp file. |
| SEC-016 | fixed | 25 MB / 5000 entries / 200 MB declared-uncompressed caps in `sanitizeXlsxBytes` (null = refused). |
| SEC-017 | deferred | rotation flow is a feature. |
| AUTHZ-001 | fixed | `ManagerApprovalRules` + dialog; tests incl. `tables_merge` with `cond:`. |
| AUTHZ-002/007 | fixed | details dialog uses `SalesInvoiceItemsTable`, `SalesInvoiceTotalsBlock`, `SalesInvoiceMarginGate` (PicPos + UralCash twin). |
| AUTHZ-003 | fixed | statement / export / import gates (`PartyDataAccess`, `ensurePartyDataAccess`). Import: balance never overwritten. **Branch scoping of the export is not implemented** (the export reads all parties; visible to anyone allowed to export). |
| AUTHZ-004 | fixed | see decision record. |
| AUTHZ-005/006/008/009/010 | deferred | AUTHZ-005 needs a signed approval-proof protocol (plain denial would break legitimate conditional flows); AUTHZ-006 is a design change; AUTHZ-008 service-layer enforcement; AUTHZ-009 owner decision. |
| SYNC-001 | fixed (host side) | `X-Client-Schema` handshake: clients send it on every `ServerProxy` request; host answers 426 below `minSupported` and strips columns added after the client's schema (`table_reservations.party_id` for v195 / header-less clients). `/api/health` advertises `schemaVersion` + `minClientSchema`. Header-less clients are assumed v195. The "reset the `table_reservations` watermark in the v196 migration" step is **not done** (would touch the migration). |
| SYNC-002 | fixed | row failures hold the table's watermark for up to 3 consecutive cycles (`DeltaPullFailureTracker`), then advance with a `SYNC-ALERT` log line. |
| SYNC-003/004/005/006/007 | deferred | features / design. |
| RPT-006 | partly | product template export gated; customer picker masked; party export gated. Statement export/print rely on the statement screen entry gates. |
| DATA-003 | fixed (update path) | existing parties keep their balance on import; new parties still get the sheet balance (no party opening-balance JE path exists — same as the Add Party dialog). |

## Follow-up pass - items that were "deferred" above (security + distribution closure)

Status after this pass. Tests are under `test/security/` unless noted.

| ID | Status | Notes / tests |
|---|---|---|
| SEC-005 | **mitigated** (re-wrap path already exists; warning added) | The safe M0-M8 re-key flow (`DbKeyMigrationService`, admin-triggered, applied before any handle opens at the next boot) needs no schema change; automatic migration stays off by owner decision. Added a persistent, non-dismissable admin banner while the key is legacy: `legacy_db_key_banner.dart` + `legacyDbKeyWarningProvider` mounted in `app_shell.dart`. Test: `legacy_db_key_banner_test.dart`. Supported remediation: Settings > Security > Database encryption (migrate), or portable export/import. |
| SEC-006 | partly (unchanged) | Constant-time compare was already done. Window-on-fresh-install is **still deferred**: with no schema change nothing distinguishes a fresh host from an upgraded host that still has legacy clients (`install_date` is written lazily by the licence service on every first run). Follow-up for the first-run wizard: a server host created by the wizard can call `setSetting('lan_legacy_transition_ended','true')`. |
| SEC-007 | **fixed** | TLS by default with a first-run self-signed certificate in secure storage, fingerprint pinning (TOFU/QR), explicit legacy HTTP switch, Android pinned client. `docs/security/lan-tls.md`; `lan_tls_test.dart`, `lan_pairing_tls_pin_test.dart`, `packages/picpos_api_client/test/lan_pinning_test.dart`. |
| SEC-010 | **fixed** | Argon2id m=19456 KiB, t=2, p=1 (OWASP minimum); verification reads m/t/p from the stored hash (bounded), older hashes verify and are rehashed at the next login. `argon2_params_test.dart`. Measured +~65 ms (JIT, dev PC) per hash. |
| SEC-013 | **fixed** | Gitleaks job is blocking on pull requests and release tags (advisory on plain branch pushes). |
| SEC-014 | **fixed (code + docs)** | `TLS_CERT_FILE`/`TLS_KEY_FILE`/`BIND_ADDRESS` + startup warning for exposed plain HTTP; `docs/ops/CLOUD-SERVER-DEPLOY.md`; `server/test/tls_config_test.dart`. |
| SEC-017 | **fixed** | Rotate-signing-key flow: new seed generated, published (server revokes every admin device of the company in the same call), seed stored only after success. Server routes `POST /desktop/link/rotate-signing-key`, `POST /desktop/admin-devices/revoke-all`; desktop button in Linked devices. `server/test/m1_admin_rotate_test.dart`, `admin_signing_key_rotation_test.dart`. |
| AUTHZ-005 | **deferred** | Needs a host-signed approval-proof protocol plus clients that attach it, including outbox replays whose proof may have expired. A plain 403 for conditional grants would break legitimate offline flows (returns, large discounts, voids). |
| AUTHZ-006 | **deferred** | `WebHttpReadGate` table does not cover every device GET (`/api/sales/held`, `/api/product-batches`, `/api/shifts`, `/api/payment-allocations`, sync reads); default-deny would break client reads. Needs the table completed first. |
| AUTHZ-008 | **fixed** | `BookingActionsService` enforces `bookings_add` (+`bookings_deposit` for a deposit), `bookings_status`, `bookings_cancel`, `bookings_assign` for actor-attributed calls; `userId == null` is the system/sync path. Conditional grants count as held (approval is a UI step). `booking_service_authz_test.dart`; `booking_status_logging_test.dart` now grants its actor the codes. |
| AUTHZ-009 | **fixed** | Unit cost column and inventory valuation require `products_cost_view` (`canSeeInventoryCost`, `inventoryCostVisibilityProvider`). `inventory_cost_visibility_test.dart`. Owner decision recorded here. |
| SYNC-003 | **not reproducible at HEAD** | Already fixed: `pushTableReservation` -> `ClientWriteInterceptor.submitTableReservation` -> `POST /api/table-reservations` (in `test/golden/api_routes.txt`). |
| SYNC-004 | **fixed** | Host `POST /api/parties` matches on normalised phone + normalised name (formatting/digit-script insensitive) and records same-phone/different-name rows in `party_dedup_suspects`. `party_phone_dedupe_test.dart`. |
| SYNC-005 | **fixed (product conflicts)** | A 409 naming another record (`conflictWithGlobalId`, new `code: UNIQUE_CONFLICT`) is a terminal business conflict: dead-lettered and shown in the sync-failures UI instead of "synced". Generic wording (`already exists`, `duplicate`) keeps the old benign behaviour. `sync_unique_conflict_test.dart`. Other tables only benefit once their handlers return the structured code. |
| SYNC-006 | **accepted, documented** | The client DB holds everything its branch scope allows by design (offline-first); figure masking is UI-level. Protection = SQLCipher key (SEC-005) + OS access control. |
| SYNC-007 | **not built, not claimed** | No relay route/queue exists (`server/lib`), no UI text in `lib/` or `mobile_admin/` mentions it; only design docs (`docs/mobile/ARCHITECTURE-M.md` ADR-M2, `ARCHITECTURE-MC.md` marks it "not live"). `submitCommand` throws `not_available_in_m1`. |
| REL-002 | **fixed (tooling + CI gate)** | `tool/gen_selfsigned_codesign.ps1` (test only), CI fails release tags without `PICPOS_SIGN_PFX_BASE64`/`PICPOS_SIGN_THUMBPRINT` unless `ALLOW_UNSIGNED`; `RELEASE=1` installer build fails without an identity. `docs/ops/WINDOWS-SIGNING.md`. A real certificate is still required. |
| REL-003 | **partly fixed** | The installer now takes a verified copy of the database to `Documents\backups\pre-upgrade\` and ABORTS the upgrade if it cannot (`installer/preupgrade_backup.isi`, hooked in `setup_picpos.iss` and `setup.iss`). The in-app non-blocking pre-migration backup, rotation and downgrade guard are unchanged. |
| REL-004 | **fixed** | All three apps fail closed without `android/key.properties`; `tool/gen_android_keystore.ps1`; `docs/ops/ANDROID-SIGNING.md`; CI job `android-release`. |
| DEP-001 | **documented** | `docs/security/sqlcipher-eol.md`; dependency untouched. |