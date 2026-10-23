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
