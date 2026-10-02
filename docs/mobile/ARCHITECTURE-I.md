# Phase I — Cloud server + Android cash-van app (Architecture)

> Status: **I-1 skeleton implemented** (see §14 for what is real vs stubbed).
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
 │ (ural_erp, Drift)  │  master data up, field docs down
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

Follow-up (I-4): extract the pure parts (`effective_item_tax_rate`, integrity payload, totals/rounding, voucher-book rules) into one shared pure-Dart package (e.g. `packages/picpos_domain`) that **both** `ural_erp` and `server/` depend on, so parity is by construction rather than by test. Not done in I-1 because `lib/` is being edited concurrently and was out of scope.

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
5. **Revocation**: `devices.revoked_at` → all calls 401 `device_revoked`; app wipes local data after showing the reason. **Rotation**: `POST /mobile/token/rotate` returns a new device token and invalidates the old hash (planned I-2; the app rotates every 30 days).
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
- **Prices/tax**: lines carry the price the device used; the server recomputes `tax = effectiveItemTaxRate(...)` and totals with the same rounding (2 dp lines, 4 dp integrity payload). A mismatch > 0.01 → `totals_mismatch`. Price-override permission per rep is I-2.
- **Number**: §3.
- **Collections**: amount > 0; book rule §3.2; reduces customer balance.
- **Integrity**: on accept the server signs the invoice with the company's integrity secret (`v2:` HMAC-SHA256 over the desktop payload format) and stores `integrity_hash`. Desktop verification of cloud-signed docs requires the shared secret (I-3: secret provisioned per company in the cloud, desktop fetches it once over the authenticated channel), or the desktop re-signs after posting (`resignSalesInvoice`) — **I-3 decision point**; default: desktop re-signs on posting and keeps the cloud hash as `cloud_integrity_hash` for audit.

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
- Interface `ReceiptPrinter { Future<void> printInvoice(...) }` exists as a stub in `mobile/lib/printing/`.

## 11. Security

- TLS only in production (terminated by a reverse proxy, e.g. Caddy/nginx with Let's Encrypt; the API listens on the internal network). HSTS.
- Device tokens: random 256-bit, stored hashed; session tokens 12 h; rotation every 30 days; immediate revocation per device.
- Rate limits: pairing 5/IP/10 min (implemented), login 10/device/10 min, push 60/device/min (I-2).
- Every write is audited: `audit_log(company_id, device_id, employee_id, action, entity, global_id, ip, at, detail)`.
- PIN hashes PBKDF2 (≥ 100k iterations); admin key for test only — production admin flows go through desktop users (I-3).
- Postgres: separate app role without superuser; parameterized queries only (no SQL string interpolation, unlike the LAN `_sql` helper).
- On device: local DB in app-private storage; I-2 adds SQLCipher (`sqflite_sqlcipher`) with the key in Android Keystore; wipe on revocation.
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
| **I-1** (this) | Architecture; cloud API skeleton (health, pairing, login, bootstrap, push sales+collections with validations, pull delta, WhatsApp outbox + mock); docker test stack; mobile skeleton (pair/login, today's route, customer card, new sale, collection, sync status; local DB + outbox) | Server tests green (pairing, scoping, idempotency, stock/credit/book-range rejections, pull delta, WhatsApp enqueue); `docker compose up` → `/health` 200; mobile `flutter test` green; `flutter build apk --debug` succeeds |
| **I-2** | Mobile ↔ cloud wired end-to-end (HTTP client, sync engine, backoff, conflict UI), barcode camera scan, sales returns, visits, token rotation, rate limits, SQLCipher on device, price lists | Rep completes a full offline day on a device, comes online, all docs accepted exactly once (kill-app-mid-push test); revoked device is wiped |
| **I-3** | Desktop ↔ cloud sync: desktop pushes master data (products, customers, routes, books, stock) and pulls accepted field docs, posting them via the existing orchestrator; admin pairing from desktop UI | A field invoice appears on desktop, posts identical GL/stock/balance as a desktop invoice with same inputs (golden comparison test); balances flow back to the van |
| **I-4** | Bluetooth ESC/POS printing 58/80 (raster Arabic), barcode/QR; shared `picpos_domain` package extraction | Printed sample on 58 and 80 mm devices matches checklist; parity tests run against shared package |
| **I-5** | WhatsApp real provider (Meta Cloud API), templates, webhooks, delivery status, balance statements | Sandbox number receives AR/EN templates; failures retry and dead-letter |
| **I-6** | Production deployment (owner's host/domain/TLS/backups), monitoring, optional server-side posting for cloud-only companies | Checklist §12 complete; restore drill passes |

## 14. I-1 implementation status

The exact implemented-vs-stubbed list is in `server/README.md` and `mobile/README.md`. Summary:

**Implemented:**
- The I-1 server endpoints, with Postgres persistence and validations.
- The WhatsApp outbox with the mock provider. The Meta provider exists as a stub that stays off unless configured.
- Server tests against Postgres.
- The docker test stack and its smoke script.
- The mobile app: local SQLite and outbox, an HTTP client and a sync engine at login and on demand, offline rules, and the I-1 screens.
- A live contract test from the mobile client to the docker API.

**Stubbed or gaps:**
- Desktop posting of cloud documents (I-3).
- Push for returns and visits (I-2).
- The token-rotation endpoint and the login/push rate limits (I-2).
- Automatic background sync and camera scanning on mobile (I-2).
- Printing: the interface exists, nothing more (I-4).
- Sending real WhatsApp messages through Meta (I-5).
- The pricing model is tax-exclusive with line discounts only (tax-inclusive is I-2).
