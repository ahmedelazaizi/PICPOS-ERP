# Phase I — Cloud server + Android cash-van app (Architecture)

> Status: **I-1, I-2, I-3 and I-4 implemented** (see §14 for what is real vs stubbed; I-4 printing not yet verified on physical printers).
> Owner decisions (final): central cloud server (PostgreSQL + HTTPS API, desktop also syncs to it) — Docker **test** server for now; Android cash-van app, offline-first; per-device number ranges; **server authoritative**; only the rep deducts from **his van** stock; credit limit is checked against the **last-synced** balance; WhatsApp Business API automatic messages — **test mode (mock provider)** until Meta approval.

---

## 1. Components

```
 ┌────────────────────┐   HTTPS (TLS)    ┌──────────────────────────┐   SQL    ┌──────────────┐
 │ picpos_van (Android│ ───────────────▶ │  picpos_cloud  (server/) │ ───────▶ │ PostgreSQL 16│
 │ Flutter, offline)  │ ◀─────────────── │  shelf + postgres (Dart) │ ◀─────── │  cloud DB    │
 │ local SQLite+outbox│  bootstrap/pull  │  /mobile/*  /desktop/*   │          └──────────────┘
 └────────────────────┘  push (idempot.) │  WhatsApp outbox worker  │
                                         └──────────┬───────────────┘
 ┌────────────────────┐   HTTPS (I-3)               │ provider interface
 │ PicPos desktop     │ ◀──────────────────────────▶│ Mock (test) │ Meta Cloud API (prod)
 │ (picpos_erp, Drift)  │  master data up, field docs down
 └────────────────────┘
```

| Component | Folder | Role |
|---|---|---|
| Cloud API | `server/` (package `picpos_cloud`) | Pure Dart (no Flutter). Auth, device registry, number-range leases, mobile bootstrap/push/pull, desktop sync (I-3), WhatsApp outbox. |
| Cloud DB | Postgres 16 (`server/lib/src/db/migrations.dart`) | System of record for **field documents** and the replicated master data the reps need. |
| Test stack | `docker/` | `docker compose up` → `postgres` + `api` (seeded demo tenant). |
| Mobile app | `mobile/` (package `picpos_van`) | Flutter Android, Material 3 themed from `DESIGN.md`, Arabic RTL default + English, SQLite (sqflite) + outbox. |
| Desktop | existing `lib/` | Stays the **ledger owner** (posting engine, GL). Gains a cloud-sync client in I-3. |

### 1.1 Decision: new server package vs. reusing `lib/services/api`

**Decision: a new pure-Dart package `server/`; reuse protocols, rules and algorithms — not the code files.**

Evidence (read-only inspection of the current tree):
- `lib/services/api/*` (`api_handler.dart`, `api_handler_base.dart`, `lan_pairing_service.dart`, `api_rate_limiter.dart`), `delta_pull_service.dart` and `network_service.dart` import `package:flutter/foundation.dart`; pairing uses `secure_storage_service.dart` → `flutter_secure_storage` + `flutter_riverpod`; `network_service.dart` uses `shared_preferences`; `api_purchase_handler.dart` uses `path_provider`.
- `AppDatabase` (`lib/data/database/database.dart`) imports `path_provider` and `flutter/foundation`; `connection_io.dart` / `db_connection_strategy.dart` pull `shared_preferences`; `pg_config.dart` pulls `flutter_secure_storage`. → the Drift DB cannot be opened in a headless `dart` process (or a slim Docker image) without first extracting it.
- The LAN API is ~200 CRUD routes shaped for a trusted LAN client that mirrors the whole DB. The cloud contract for a rep is deliberately narrow (bootstrap/push/pull scoped to one rep), multi-device and Internet-facing.

What **is** reused (by contract, verified by parity tests):
| Reused item | Source | In cloud |
|---|---|---|
| Auth header conventions `Authorization: Bearer <device token>`, `X-Device-Id`, `X-Session-Token`, `X-Idempotency-Key` | `api_auth_middleware.dart`, `api_session_token.dart` | same header names |
| Pairing: 8-char code from `Random.secure()` without look-alike chars, 10-min TTL, single use, 5 attempts/IP/10 min, constant-time compare | `lan_pairing_service.dart` | same rules; but the cloud **stores a SHA-256 hash of a random token** (revocable per device, rotatable) instead of the stateless HMAC(installSecret, deviceId) |
| Delta pull: `since` + keyset cursor `(last_modified_at, id)`, `{rows, hasMore, serverTime}`, soft-delete tombstones via `deleted_at` | `api_handler.dart::_getSyncPull`, `delta_pull_service.dart` | same shape; `since`/`serverTime` in epoch **milliseconds** for the cloud (documented in the API) |
| Sync columns `global_id, last_modified_at, deleted_at, origin_client_id, row_version` | every Drift table (v167) | identical names on every cloud table |
| Tax rule `effectiveItemTaxRate(rate, exempt, companyDefault)` | `lib/core/tax/effective_item_tax_rate.dart` (pure) | ported verbatim to `server/lib/src/domain/tax.dart` |
| Invoice integrity payload `number|ISO date|total|subtotal|discount|tax|paid|customer??0|user|paymentMethod`, HMAC-SHA256, `v2:` prefix | `lib/services/invoice_integrity_service.dart` | ported to `server/lib/src/domain/integrity.dart` (test pins the format) |
| Voucher-book leaf rules (inside `[range_from, range_to]`, not used, not cancelled, book `active`, holder = rep) | `voucher_books_schema.dart::validateVoucherBookLeaf` | same rules in push validation |
| Distribution model (area → route → customers with sequence + effective dates; `rep_resources.van_warehouse_id/custody_safe_id`) | `distribution_model_schema.dart` (v185) | same table/column names in Postgres |

Done in I-4 for server and mobile: the pure rules (tax rate, totals/rounding, pricing, returns math, credit rule, payment method, integrity payload/signing, barcode normalization, printed company identity, receipt QR) live in **`packages/picpos_rules`** (pure Dart), a path dependency of `server/` and `mobile/`; their copies were deleted. Follow-up: make `picpos_erp` (desktop `lib/`) depend on it too — out of scope for I-4. Voucher-book leaf rules are still SQL in the server.

### 1.2 Decision: cloud schema

**Decision: hand-written Postgres migrations (`server/lib/src/db/migrations.dart`, ordered SQL strings embedded so the AOT binary is self-contained, applied idempotently at startup and recorded in `schema_migrations`) that mirror desktop table and column names (snake_case) + the v167 sync columns + `company_id` (tenant).** Not the Drift classes (Flutter-bound, see above) and not `supabase/migrations/0001_initial_schema.sql` (9 tables, no invoices/routes/vouchers).

Rules:
- Every replicated row is keyed by `global_id` (UUID text) **across systems**; integer `id`s are local to each database and never sent as foreign keys between systems — references travel as `*_global_id`.
- Same names as desktop (`parties`, `products`, `warehouses`, `inventory_balances`, `sales_routes`, `route_customers`, `rep_resources`, `voucher_books`, `sales_invoices`, `sales_invoice_items`, `safe_transactions`) so the I-3 desktop↔cloud mapper is a column copy, not a translation.
- `inventory_balances` has no sync columns on desktop; the cloud adds them (needed for delta pull of van stock).

## 2. Data ownership & conflict rules

| Data | Owner (writes) | Flows | Conflict rule |
|---|---|---|---|
| Master data: products, prices/price lists, tax flags, customers (identity, credit limit, phone, WhatsApp opt-in), warehouses, routes, route customers, rep resources, voucher books (issue/assign) | **Desktop** (back office) | desktop → cloud → mobile | Desktop wins. Cloud rejects mobile writes to these tables (mobile has no endpoint for them). `row_version` monotonically increases; cloud accepts a desktop upsert only if `row_version` ≥ stored. |
| Field documents: sales invoices, sales returns, collections (receipts), visits | **Mobile device that created it** (immutable after acceptance) | mobile → cloud → desktop | Insert-only, identified by `global_id`. Re-push of the same `global_id` = idempotent replay (same response). Corrections are new documents (return / reversal), never edits. |
| Acceptance status, server numbers validation, rejection reason | **Cloud** (authoritative) | cloud → mobile | Server decides `accepted` / `rejected(code)`; the device marks its local copy accordingly. |
| Customer balance, van stock | **Cloud** materialization = desktop ledger balance + accepted field docs not yet posted by desktop | cloud → mobile | Recomputed server-side; mobile only shows "last synced" value + its own pending outbox deltas (clearly labelled). |
| GL / journal entries, posting | **Desktop** posting engine (`SalesMutationsDao.createSalesInvoice` + `autoPost*`) until I-4 | desktop | One posting engine → identical accounting results. |

"Server authoritative" therefore means: the cloud is the gate for every field document (stock, credit, number ranges, scoping, integrity), and the only path a field document reaches the ledger is through the cloud.

## 3. Per-device number ranges

Goals: no number collision across offline devices; numbers gap-auditable; tie-in with paper voucher books.

### 3.1 Invoices & returns — leased blocks
- Table `number_series(company_id, doc_type, prefix, next_block_start, block_size)` — one per document type (`sales_invoice`, `sales_return`).
- Table `device_number_leases(device_id, doc_type, prefix, range_from, range_to, next_number, status[active|exhausted|revoked], leased_at)`.
- **Lease**: at bootstrap (and on every pull) the server guarantees each device holds an active lease per doc type with ≥ `low_water` (20 % of `block_size`, default 500) numbers left; otherwise it allocates the next block atomically (`UPDATE number_series SET next_block_start = next_block_start + block_size RETURNING …` inside the tx). A device may hold the current and one pre-fetched next block, so it never runs dry offline for a normal day.
- **Number format**: `{prefix}{n}` e.g. `VS-100042`. The block itself encodes the device (blocks are disjoint), so no device code is needed in the string; the lease table answers "which device issued VS-100042".
- **Push validation**: number ∈ an active/exhausted lease of **that device** for that doc type, and not already used by another `global_id` (unique index `(company_id, doc_type, number)`).
- **Revocation**: when a device is revoked its leases become `revoked`; unused numbers are reported as voided gaps (audit report), never re-issued.
- Desktop keeps its own numbering; desktop's series and the cloud prefixes must differ (configured per company; default cloud prefixes `VS-` invoice, `VR-` return).

### 3.2 Collections — voucher books (phase E tie-in)
- A collection receipt number **is a voucher-book leaf**. Books (`voucher_books`, `book_type='receipt'`) are issued on desktop with `holder_employee_id = rep`.
- The device receives the rep's active books at bootstrap with `next_number` and the server-known used/cancelled leaves; the app suggests the next free leaf (same algorithm as `suggestNextVoucherBookNumber`), the rep may type the paper leaf he actually wrote.
- **Push validation**: book exists, `status='active'`, `holder_employee_id` = rep of the session, `range_from ≤ n ≤ range_to`, leaf not used (unique `(book_id, book_number)` in `safe_transactions`) and not in `voucher_book_leaves_cancelled`. On accept, `next_number` advances (same rule as `_advanceVoucherBook`; book closes when exhausted).
- Books with no paper (pure electronic) are simply books whose leaves are only issued by the app.

## 4. Authentication

1. **Device pairing** (admin side): a back-office admin (desktop, I-3; for the test stack: `POST /admin/pairing-codes` with `X-Admin-Key`) issues a pairing code bound to a **rep employee** and company. Same code rules as LAN pairing (8 chars, no look-alikes, 10 min TTL, single use).
2. **Pair** (`POST /mobile/pair {code, deviceId, deviceName}`): server consumes the code, creates/updates `devices` row (bound to the rep), returns `deviceToken` (32 random bytes, base64url). Only `sha256(token)` is stored. Rate limit: 5 attempts / IP / 10 min.
3. **Rep login** (`POST /mobile/login {pin}` + device token): verifies the PIN (PBKDF2-SHA256, per-user salt, stored as `pbkdf2$iter$salt$hash`) of the rep bound to the device; returns a short-lived **session token** (HMAC-signed `{uid, did, exp}`, 12 h default). Login works offline on the device against the last verified PIN hash cached locally (for opening the app only; push always requires a valid server session, refreshed on reconnect).
4. Every `/mobile/*` call: `Authorization: Bearer <deviceToken>` + `X-Device-Id`; data calls also `X-Session-Token`.
5. **Revocation**: `devices.revoked_at` → all calls 401 `device_revoked`; app wipes local data after showing the reason. **Rotation** (I-2): `POST /mobile/token/rotate` returns a new device token; the previous hash stays valid only until the new token is first used (a lost response cannot lock the device out); the app rotates every 30 days.
6. Rep reassignment (route changes rep): device stays bound to the employee; scoping follows the route's current rep (`sales_routes.sales_rep_id` / `route_rep_history`), so the old rep stops seeing the customers at next pull.

## 5. Offline queue & idempotency

- Every document gets a **client-generated UUID v4 `global_id`** at creation, plus the leased number. Both are stored before the screen confirms.
- Local `outbox(global_id, kind, payload_json, status[pending|sending|accepted|rejected], attempts, last_error, created_at)`. Documents are appended in creation order; sync sends them in batches (≤ 50) in order.
- `POST /mobile/sync/push` processes each doc in its own transaction and returns per-doc results: `accepted`, `duplicate` (same `global_id` already accepted — returns the original result, no side effects), or `rejected{code, message}`. A batch never partially applies one document.
- `sync_idempotency(company_id, global_id, kind, device_id, result_json)` stores the first result; replay is O(1). Same `global_id` from a **different** device → `rejected: global_id_conflict`.
- Rejected docs stay visible on the device ("needs attention") with the reason; they are never silently dropped. Rejections that can be fixed by more data (e.g. stock arrived) can be retried by the rep after a pull; others require a new document.
- Retries: exponential backoff (5 s → 15 min cap) + immediate retry on connectivity change. Push before pull, so pull returns the server state including the device's own accepted docs.

## 6. What syncs

**Down (bootstrap then delta pull, scoped to the session rep):**
| Data | Scope |
|---|---|
| Rep profile, `rep_resources` (van warehouse, custody safe) | session employee |
| Routes | `sales_routes` where current rep = session employee (+ area, `visit_days`) |
| Customers | `route_customers` of those routes, effective today (`effective_from ≤ today` and `effective_to` null or ≥ today), with `sequence`, `balance`, `credit_limit`, `phone`, `whatsapp_opt_in`, `price_level` |
| Products | active products + barcodes + `sale_price`, `wholesale_price`, `tax_rate`, `tax_exempt`; price lists (I-2) |
| Van stock | `inventory_balances` for the van warehouse only |
| Voucher books | active books held by the rep (+ used/cancelled leaves) |
| Number leases | the device's active leases |
| Company settings | default tax rate, currency, decimals, company name/tax id for printing |

**Up (push):** sales invoices (+ lines, payment), sales returns (I-2), collections (receipts with book leaf), visits (I-2: visited/no-sale reason/geo).

Pull: `GET /mobile/sync/pull?since=<ms>` returns per-entity changed rows since the watermark (customers incl. balance, products, van stock, books, leases, document statuses) + `serverTime`; the device stores `serverTime` as the next watermark only after applying the page.

## 7. Business rules at the gate (push)

- **Scoping**: customer must be on one of the rep's routes today, otherwise `customer_not_on_route`.
- **Stock rule**: lines deduct only from the **rep's van warehouse** (`rep_resources.van_warehouse_id`); `warehouse` is not accepted from the client. For each product, `sum(qty in base unit) ≤ inventory_balances.quantity` (row locked `FOR UPDATE`), else `insufficient_van_stock` (whole document rejected). On accept the van balance is decremented and a `stock_movements` row is written (`type='sale'`, `reference_type='mobile_sales_invoice'`).
- **Credit rule** (same as desktop `SalesMutationsDao.createSalesInvoice`): when the remaining amount `total − paid > 0.01` and `credit_limit > 0`, the server checks `customer.balance (materialized) + remaining ≤ credit_limit`, else `credit_limit_exceeded`. `credit_limit = 0` means **no limit** (desktop shows «بلا حد»). The desktop's manager override (`overrideCreditLimit`) has no mobile equivalent in I-1 (I-2: remote approval request). The device performs the same check against its last-synced balance + its pending outbox, so the rep sees the block offline; the server re-checks on push (the server result wins).
- **Prices/tax**: lines carry the price the device used; the server recomputes `tax = effectiveItemTaxRate(...)` and totals with the same rounding (2 dp lines, 4 dp integrity payload). A mismatch > 0.01 → `totals_mismatch`. Price rule and override permission: §7.1.
- **Number**: §3.
- **Collections**: amount > 0; book rule §3.2; reduces customer balance.
- **Returns** (I-2): against lines of an accepted invoice of a customer on the rep's route; quantity ≤ sold − previously returned (`return_qty_exceeds_sold`); valued pro-rata from the original line; goods back into the van only; settlement per desktop `SalesReturnRefundSplit` (offset the unpaid part, refund the rest in cash from the custody safe).
- **Visits** (I-2): `visited` or `no_sale` + reason code (`closed`, `owner_absent`, `has_stock`, `no_cash`, `refused`, `other`), customer on route, route sequence stored.
- **Integrity**: on accept the server signs the invoice with the company's integrity secret (`v2:` HMAC-SHA256 over the desktop payload format) and stores `integrity_hash`. Desktop verification of cloud-signed docs requires the shared secret (I-3: secret provisioned per company in the cloud, desktop fetches it once over the authenticated channel), or the desktop re-signs after posting (`resignSalesInvoice`) — **I-3 decision point**; default: desktop re-signs on posting and keeps the cloud hash as `cloud_integrity_hash` for audit.

### 7.1 Pricing (I-2)

One implementation for both sides since I-4 (`packages/picpos_rules`, `tax.dart` + `pricing.dart`), pinned by the shared fixture `docs/mobile/fixtures/pricing_parity.json` run by the package tests:
- **Effective item tax**: exempt → 0; item rate > 0 → item rate; else the company default.
- **Totals** (desktop `FinancialUtils.calculateInvoiceTotals`): per line gross = r(qty × price), discount clamped, amount = r(gross − discount); tax-exclusive: tax = r(amount × rate); tax-inclusive (`companies.prices_include_tax`): net = r(amount / (1 + rate)), tax = r(amount − net). Document tax = r(Σ line tax), total = r(Σ net + tax). Rounding half away from zero to `decimal_places`.
- **Unit price** (enforced at the gate unless `employees.can_override_price`): customer `price_level='wholesale'` and product `wholesale_price > 0` → wholesale price; else active price lists in date range, default first then by order, and in the first list with a tier `min_quantity ≤ qty` the highest such tier; else `sale_price`. Rejection `price_not_allowed` with the expected price and its source.

## 8. Accounting parity

The cloud does **not** post journal entries in I-1/I-2. Accepted field docs are pulled by the desktop (I-3) and posted through the **existing** `SalesTransactionOrchestrator` / `SalesMutationsDao.createSalesInvoice` with `rep_employee_id`/`route_id` stamped and `warehouse_id = van`, payments into `custody_safe_id`, collections into `safe_transactions` with the book leaf (`assignVoucherBookLeaf`). This produces **the same accounting results as desktop by construction** (one posting engine). The cloud's own stock/balance changes are a provisional materialization reconciled when the desktop posts (desktop then pushes authoritative balances back up).

Gap documented: server-side posting (cloud-only companies without a desktop) needs the posting engine extracted into a pure-Dart shared package — I-6.

## 9. WhatsApp

- **Opt-in**: `parties.whatsapp_phone` (E.164) + `whatsapp_opt_in` + `whatsapp_opt_in_at` + source; set on desktop (or by the rep in the app, I-2, recorded as rep-captured consent). No opt-in → no message.
- **Triggers** (on accepted push): invoice issued → `invoice_issued` template (number, date, total, paid, remaining, new balance); collection → `payment_received` template (amount, receipt no., new balance). Optional `balance_statement` (I-5).
- **Outbox**: `whatsapp_outbox(id, company_id, party_id, to_phone, template, language, params_json, document_global_id, status[queued|sending|sent|delivered|failed|dead], attempts, next_attempt_at, provider_message_id, last_error, created_at)`. Enqueued **in the same transaction** as the accepted document (unique per `(document_global_id, template)` → idempotent).
- **Worker**: polls `queued` rows with `next_attempt_at ≤ now` (`FOR UPDATE SKIP LOCKED`), calls the provider, backoff 1 m, 5 m, 30 m, 2 h, 12 h → `dead` after 5. Delivery webhooks (Meta `statuses`) update status (I-5).
- **Provider abstraction** `WhatsAppProvider.sendTemplate(...)`: `MockWhatsAppProvider` (test mode: stores messages in memory/DB and logs; deterministic `mock-<n>` ids; can simulate failures) and `MetaCloudWhatsAppProvider` (stub: builds the Graph API `POST /{phone-number-id}/messages` template payload; sending disabled until `WHATSAPP_PROVIDER=meta` + `WHATSAPP_TOKEN`, `WHATSAPP_PHONE_NUMBER_ID` are configured). Templates must be pre-approved by Meta in Arabic and English.

## 10. Printing (I-4)

- Bluetooth Classic SPP ESC/POS printers, 58 mm (32 chars / 384 dots) and 80 mm (48 chars / 576 dots). Arabic is rendered as a **raster image** (Noto Naskh Arabic, per DESIGN.md print font) because most ESC/POS code pages lack proper Arabic shaping; then `GS v 0`.
- Content: company header, tax number, invoice number, date, rep/route, customer, lines, totals, paid/remaining/new balance, integrity short hash.
- **QR**: JoFotara/ETA-compatible payload when the company is e-invoicing; otherwise a verification URL `https://<cloud>/v/<global_id>` (I-5). **Barcode**: CODE128 of the invoice number.
- Implemented in I-4 (`mobile/lib/printing/`, §14): plugin `print_bluetooth_thermal` (Classic SPP, paired devices), receipt model → Flutter canvas raster (bundled Noto Naskh Arabic) → `GS v 0` in bands of ≤ 256 rows. Identity lines follow the desktop rules (`companyHeaderLines` in `picpos_rules`; data from cloud migration 4). QR follows the desktop decision: non-fiscal payload (invoice, date, total, company + document `globalId`) with «ليس إيصالاً ضريبيّاً»; an e-invoicing company prints **no** QR until a gateway QR exists (the device has none; the `/v/<global_id>` URL is not built). Printing never blocks a sale: failures go to a persisted retry queue.

## 11. Security

- TLS only in production (terminated by a reverse proxy, e.g. Caddy/nginx with Let's Encrypt; the API listens on the internal network). HSTS.
- Device tokens: random 256-bit, stored hashed; session tokens 12 h; rotation every 30 days; immediate revocation per device.
- Rate limits: pairing 5/IP/10 min, login 10/device/10 min, push 60/device/min (all implemented; in-memory per API instance).
- Every write is audited: `audit_log(company_id, device_id, employee_id, action, entity, global_id, ip, at, detail)`.
- PIN hashes PBKDF2 (≥ 100k iterations); admin key for test only — production admin flows go through desktop users (I-3).
- Postgres: separate app role without superuser; parameterized queries only (no SQL string interpolation, unlike the LAN `_sql` helper).
- On device: local DB in app-private storage, encrypted with SQLCipher (`sqflite_sqlcipher`) using a random 256-bit key kept in `flutter_secure_storage` (Android Keystore); wipe on revocation.
- Backups: daily `pg_dump` + WAL archiving (production), restore drill.

## 12. Deployment

**Test (now)**: `docker/docker-compose.yml` → `postgres:16-alpine` + `api` (built from `server/Dockerfile`, Dart AOT). Demo data seeded when `SEED_DEMO=true`. See `docker/README.md`.

**Production checklist — the owner must provide/decide:**
1. Host / provider (VPS or managed; region near Jordan/Egypt), sizing (start: 2 vCPU / 4 GB / 40 GB SSD).
2. Domain (e.g. `api.<company>.com`) and DNS access.
3. TLS: Let's Encrypt via reverse proxy (automatic) or provided certificate.
4. Managed Postgres or self-hosted with backups: retention period, off-site location, restore test owner.
5. Secrets: `TOKEN_SECRET`, `INTEGRITY_SECRET` per company, DB password, admin credentials (stored in the host's secret manager, never in git).
6. WhatsApp: Meta Business account verification, phone number id, permanent token, approved templates (AR/EN).
7. Monitoring/alerting contact; log retention.
8. Data-protection / consent text for WhatsApp opt-in.

## 13. Roadmap & acceptance criteria

| Phase | Scope | Acceptance criteria |
|---|---|---|
| **I-1** (done) | Architecture; cloud API skeleton (health, pairing, login, bootstrap, push sales+collections with validations, pull delta, WhatsApp outbox + mock); docker test stack; mobile skeleton (pair/login, today's route, customer card, new sale, collection, sync status; local DB + outbox) | Server tests green (pairing, scoping, idempotency, stock/credit/book-range rejections, pull delta, WhatsApp enqueue); `docker compose up` → `/health` 200; mobile `flutter test` green; `flutter build apk --debug` succeeds |
| **I-2** (done, §14) | Mobile ↔ cloud wired end-to-end (HTTP client, sync engine, backoff, conflict UI), barcode camera scan, sales returns, visits, token rotation, rate limits, SQLCipher on device, price lists | Rep completes a full offline day on a device, comes online, all docs accepted exactly once (kill-app-mid-push test); revoked device is wiped |
| **I-3** (done, §14) | Desktop ↔ cloud sync: desktop pushes master data (products, customers, routes, books, stock) and pulls accepted field docs, posting them via the existing orchestrator; admin pairing from desktop UI | A field invoice appears on desktop, posts identical GL/stock/balance as a desktop invoice with same inputs (golden comparison test); balances flow back to the van |
| **I-4** (done, §14) | Bluetooth ESC/POS printing 58/80 (raster Arabic), barcode/QR; shared `picpos_rules` package extraction | Printed sample on 58 and 80 mm devices matches checklist; parity tests run against shared package |
| **I-5** | WhatsApp real provider (Meta Cloud API), templates, webhooks, delivery status, balance statements | Sandbox number receives AR/EN templates; failures retry and dead-letter |
| **I-6** | Production deployment (owner's host/domain/TLS/backups), monitoring, optional server-side posting for cloud-only companies | Checklist §12 complete; restore drill passes |

## 14. Implementation status (I-1 + I-2 + I-3 + I-4)

The exact implemented-vs-stubbed list is in `server/README.md` and `mobile/README.md`. Summary:

**Implemented:**
- The I-1 server endpoints, with Postgres persistence and validations; the WhatsApp outbox with the mock provider (the Meta provider is a stub that stays off unless configured).
- I-2 server: sales returns and visits push (idempotent by `globalId`, rep scope, van warehouse only, return quantity ≤ sold − returned), device token rotation and revocation, login/push rate limits, audit rows, price lists, wholesale level, rep price-override permission and tax-inclusive pricing (§7.1), returnable invoices in pull.
- Server tests against Postgres (71), the docker test stack and its smoke script (now also return, over-return rejection, visits and token rotation).
- Mobile: encrypted local DB (SQLCipher, Keystore-held key) and outbox; HTTP client and sync engine with background scheduling, backoff and connectivity awareness; token rotation and wipe on revocation; the I-1 screens plus sales returns, visits (planned / visited / no sale + reason in route order), camera barcode scanning beside the keyboard-wedge path, price lists and tax-inclusive pricing with the shared parity fixture; AR/EN.
- A live contract test from the mobile client to the docker API (sale, collection, return, visits).

**Acceptance criteria (§13, I-2) — evidence and limits:**
- "All docs accepted exactly once": covered by idempotent push (server tests), the lost-response retry test and the pull-reconciliation test on mobile, and the live contract test. A full offline day on a physical device was **not** run.
- "Revoked device is wiped": server revocation test + mobile wipe test; not exercised on a device.

**I-3 (desktop ↔ cloud) — implemented:**
- Cloud (`server/lib/src/service/desktop_service.dart`, migration 3): desktop link credential (`X-Desktop-Link` + bearer secret, SHA-256 stored, revocable), `/desktop/ping`, `/desktop/master` (idempotent upsert by `globalId`, desktop wins, unknown references skipped and reported), `/desktop/documents/pending`, `/desktop/documents/ack` (`posted` final, `failed` keeps the doc pending with the reason), `/desktop/pairing-codes` (rep PIN + code from the desktop). Served balances and van stock = desktop value + accepted field docs not yet posted (§2).
- Desktop (`lib/services/cloud_sync/`): `CloudDocumentPoster` posts each field document through the existing paths — sales invoice via `SalesTransactionOrchestrator.completeSalesTransaction` (van warehouse, cash into the rep's custody safe, field date, explicit rep/route stamp, cloud `globalId` kept on the invoice, cloud number in `platform_order_number`, desktop numbering and `resignSalesInvoice`), return via `ReturnsRepositoryImpl.processSalesReturn` (cash refund from the custody safe), collection via `createReceiptVoucher` + `assignVoucherBookLeaf` (`customer_payment`), visit via `route_visits` (`completed` / `skipped` + reason). A total that differs from the desktop computation by > 0.01 is refused. Two narrow additions make field documents possible on those paths: `SaleRequest.globalId/invoiceDate/repEmployeeId/routeId/cashOutsideDrawer` and `processSalesReturn(refundSafeId:, onReturnVoucher:)` — the drawer-shift guard is skipped only for cash that sits in a rep's custody safe.
- Idempotency and conflicts: raw table `cloud_sync_documents` (schema v187); a posted document is re-acknowledged, never re-posted; a refused one is a conflict with its reason (visible in Settings › Integrations › Company cloud link, retry per document) and stays pending on the cloud.
- `CloudMasterExporter`: products and price lists incremental by `last_modified_at` (full push daily or on demand); the reps' scope (employees, rep resources, van warehouses, custody safes, areas, routes, route customers with balance and credit limit, held receipt books with cancelled leaves, van stock) on every run. Posting and ack happen before the master push.
- Scheduler (`CloudSyncScheduler`, interval from settings, never on a LAN client) + "sync now" / full push / test connection; link secret in secure storage; admin-only settings entry.
- Tests: `server/test/i3_test.dart` (6), `test/integration/cloud_sync_i3_test.dart` — golden comparison (trial balance, invoice and lines, integrity hash, rep/route stamp, safe movements, stock, customer balance, voucher-book leaf) between field documents posted from the cloud and the same documents entered on the desktop, lost-ack idempotency, conflicts and retry, master push content; with `CLOUD_URL` the same flow runs live against the docker API (desktop push → mobile bootstrap → mobile push → desktop posts). Docker smoke covers the desktop link and ack.

**Acceptance criteria (§13, I-3) — evidence and limits:**
- "Field invoice posts identical GL/stock/balance as a desktop invoice": golden comparison above (fake cloud and live docker API). Returns and collections are compared the same way.
- "Balances flow back to the van": the live test reads the posted balance from the mobile bootstrap.
- Limits: the field invoice is dated with the device date (a closed period makes it a conflict); returns use the posting date, like a desktop return. Field returns' AR-offset memo row uses the posting user's refund safe, as on desktop. Issuing the desktop credential still uses the test-stack admin key. Integrity (§7 decision point): the desktop re-signs on posting; the cloud's own hash stays in the cloud (not copied to a desktop `cloud_integrity_hash` column). Not exercised on a physical device.

**Stubbed or gaps:**
- ~~Sync for a closed app (OS-scheduled work) and GPS capture for visits~~ — done in K (below).
- Header discounts and remote price-override approval.
- Sending real WhatsApp messages through Meta (I-5).
- Printing was not run on physical 58/80 mm printers (see I-4 limits below).

**I-4 (printing + shared rules) — implemented:**
- `packages/picpos_rules` (pure Dart, `crypto` only): tax, rounding, totals, pricing, returns math, `exceedsCreditLimit`, `salesPaymentMethod`, integrity payload / `signV2` / short hash, `normalizeBarcode`, company identity lines (desktop `company_identity.dart` + thermal header rule), receipt QR decision + JoFotara TLV. Tests: the parity fixture plus rules tests (51). `server/` and `mobile/` depend on it by path; the server copies (`domain/tax.dart`, `pricing.dart`, `integrity.dart`), the mobile copy (`domain/pricing.dart`, local `normalizeBarcode`) and both duplicated parity tests were removed. The server now uses the shared credit and payment-method rules and normalizes desktop-pushed barcodes.
- Docker: the server image takes the package through the named build context `picpos_rules` (`server/Dockerfile`). **`docker/docker-compose.yml` still needs** `additional_contexts: { picpos_rules: ../packages/picpos_rules }` under `services.api.build` (outside the I-4 edit scope); until then build the image with `docker build --build-context picpos_rules=packages/picpos_rules -t picpos-cloud-test-api server` and start with `docker compose up -d --no-build`.
- Cloud: migration 4 adds `companies.name_en`, `commercial_register`, `address`, `phone`, `einvoice_enabled`; `/desktop/master` accepts them (overwritten only when sent); bootstrap **and every pull** return the company profile.
- Mobile: printing screen (printer icon in the app bar) — paired-device list, remembered default printer, paper width 58/80, print-on-save, test page, retry queue, reprint from saved documents; receipts for sales invoice, sales return and collection with identity, number, date, customer, rep, route, lines, totals, paid/remaining/payment method, new balance, CODE128 of the number, QR per the desktop decision, the cloud signature short hash after acceptance; AR/EN receipt labels. Tests: receipt model/composer, raster encoding (header, 384/576 dots, banding, real rasterization at both widths), print service with a fake printer (queue/retry, persistence, a hanging printer never blocks the sale).

**Acceptance criteria (§13, I-4) — evidence and limits:**
- "Parity tests run against shared package": `dart test` in `packages/picpos_rules` runs the fixture; server and mobile compile against the same package.
- "Printed sample on 58 and 80 mm devices matches checklist": **not run** — no printer/device in this environment. Rendering is verified by tests at both dot widths; the checklist run on real printers is still open.
- Limits: Classic Bluetooth (SPP) only, pairing in Android settings; no BLE printers. The desktop exporter does not send `nameEn` / `commercialRegister` / `address` / `phone` / `eInvoiceEnabled` yet (`CloudMasterExporter._company`, desktop `lib/` was out of scope), so until that follow-up the van prints the Arabic name and tax number only. A fiscal JoFotara/ETA QR on a field invoice needs the gateway QR to flow desktop → cloud → device (not implemented). Desktop adoption of `picpos_rules` is a follow-up.

**K (owner decisions: rep expenses, background sync, GPS) — implemented:**
- **Expense vouchers (K-1).** Desktop raw table `field_expense_categories` (v194, seeded fuel/porters/parking/maintenance/meals/other → accounts 614/617/627/6214; screen «فئات مصروفات المندوب» from the cloud-link settings, with the over-custody policy setting `cloud_expense_over_custody`). `CloudMasterExporter` pushes `expenseCategories`, the reps' **payment** books and each custody safe's ledger `balance`. Cloud migration 6: `expense_categories`, `safes.desktop_balance`, `companies.expense_over_custody` (`flag` default / `reject`), `field_attachments` (receipt photo, JPEG ≤ 1 MB, base64 on the wire), expense columns on `safe_transactions` (`category='rep_expense'`). Push kind `expense`: payment-book leaf rules = receipts (shared `claimBookLeaf`), custody = desktop balance + unposted field cash in/out; over it → flagged (`overCustody`) or `custody_exceeded`. Bootstrap/pull add `expenseCategories(+Scope)`, `paymentBooks(+Scope)`, `custodyBalance`, `expenseOverCustody`. Desktop feed kind `expense` (+ `GET /desktop/documents/attachment`); the poster posts it with `createPaymentVoucher(linkedAccountId: category account, safeId: custody)` + `assignVoucherBookLeaf` + explicit rep/route stamp, idempotent by `globalId`, refusals become conflicts. Mobile: expense screen (category, amount, note, camera photo, payment leaf, custody balance and «تجاوز العهدة» warning), outbox, printed «سند صرف» (58/80), sync/history lists.
- **Background sync (K-2).** WorkManager periodic task (15 min, network-connected constraint, exponential backoff) runs the same push + pull on the SQLCipher DB (Keystore key); empty outbox ⇒ at most one pull per 15 min. The server session is now kept in the encrypted DB so the worker can use it while valid (12 h); an expired session waits for the rep's PIN. In the app: start, queued document, connectivity back, resume; idle pull every 15 min.
- **GPS (K-3).** `geolocator`; rationale dialog (AR/EN) when the route opens, at most once a day; every visit/sale/return/collection/expense carries `geo` `{status, lat, lng, accuracy, at}` or `{status: denied|timeout|unavailable}` (8 s cap, a < 2 min last fix is reused). Cloud stores `field_geo` on all field documents (visits also lat/lng); desktop stores it on `route_visits` (lat/lng + JSON), `sales_invoices` and `safe_transactions` (v194); «الموقع» opens Google Maps from the distribution visits tab and the rep transaction-detail report.
- **Limits.** Receipt photos stay in the cloud (desktop can fetch them through the attachment endpoint but does not store them yet); return GPS is not copied to the desktop (no raw column); rep expenses are not rows of the rep transaction-detail report (they are payment vouchers in the treasury); background sync and GPS were not exercised on a physical device here.

**Next:** I-5 (WhatsApp Meta Cloud API provider, templates, webhooks, delivery status, balance statements) and I-6 (production deployment, monitoring, optional server-side posting).
