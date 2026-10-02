# picpos_cloud — PicPos cloud API (Phase I-1 … I-4)

A pure Dart server (`shelf` + `postgres`) with no Flutter dependency. The design and the reasons for a new package (instead of `lib/services/api`) are in `docs/mobile/ARCHITECTURE-I.md`.

Business rules (tax, totals, pricing, credit limit, payment method, `v2:` integrity signing, barcode normalization) come from the shared pure-Dart package `packages/picpos_rules` (path dependency `../packages/picpos_rules`), which the mobile app also uses; `lib/picpos_cloud.dart` re-exports it.

## Run

- Docker: see `docker/README.md`. The image needs the rules package as the named build context `picpos_rules`: `docker build --build-context picpos_rules=packages/picpos_rules -t picpos-cloud-test-api server` (from the repo root), or in compose `additional_contexts: { picpos_rules: ../packages/picpos_rules }` under `services.api.build`.
- Local: `dart run bin/server.dart` with `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`, `PORT`, `TOKEN_SECRET` (≥ 32 chars), `ADMIN_KEY`, `SEED_DEMO=true|false`, `WHATSAPP_PROVIDER=mock|meta` (`meta` also needs `WHATSAPP_PHONE_NUMBER_ID` and `WHATSAPP_TOKEN`).

## Endpoints

| Method | Path | Auth | Purpose |
|---|---|---|---|
| GET | `/health` | none | DB check and active WhatsApp provider |
| POST | `/admin/pairing-codes` | `X-Admin-Key` | `{companyGlobalId, employeeGlobalId}` → `{code, expiresAt}` (8 chars, 10 min, single use) |
| POST | `/admin/devices/<deviceId>/revoke` | `X-Admin-Key` | revoke the device and its number leases (audit row `device_revoked`; unknown device → 404) |
| GET | `/admin/whatsapp/outbox` | `X-Admin-Key` | last 100 outbox rows |
| POST | `/admin/whatsapp/process` | `X-Admin-Key` | run the outbox worker once (it also runs every 10 s) |
| POST | `/mobile/pair` | none (5 attempts per IP per 10 min) | `{code, deviceId, deviceName}` → `{deviceToken, deviceId, employeeGlobalId}` |
| POST | `/mobile/login` | device (10 attempts per device per 10 min → 429 + `Retry-After`) | `{pin}` → `{sessionToken}` (12 h) |
| POST | `/mobile/token/rotate` | device | → `{deviceToken, deviceId}`. The old token keeps working until the new one is first used, so a lost response is harmless; a retried rotation keeps the token the device holds valid |
| GET | `/mobile/bootstrap` | device + session | company (`defaultTaxRate`, `pricesIncludeTax`, `decimalPlaces`; printed identity I-4: `name`, `nameEn`, `taxNumber`, `commercialRegister`, `address`, `phone`, `eInvoiceEnabled`), rep (`canOverridePrice`), van, custody safe, routes, `noSaleReasons`, then the same payload as a pull with `since=0` |
| GET | `/mobile/sync/pull?since=<ms>` | device + session | delta: `customers` (with `priceLevel`), `customerScope`, `products` (with `wholesalePrice`), `vanStock`, `voucherBooks`, `voucherBookScope`, `priceLists` (changed lists with their full item set), `priceListScope`, `invoices` (accepted invoices of the last 90 days with per-product sold and returned quantities/amounts), `leases`, `documents` (invoices, returns, collections, visits of this device), `company` (same profile as bootstrap, so identity edits reach the van), `serverTime` |
| POST | `/mobile/sync/push` | device + session (60 per device per minute → 429) | `{documents:[…≤50]}` → per-document `accepted` / `duplicate` / `rejected{code}` |

The device headers are `Authorization: Bearer <deviceToken>` and `X-Device-Id`. The session header is `X-Session-Token`.

### Desktop link (I-3)

| Method | Path | Auth | Purpose |
|---|---|---|---|
| POST | `/admin/desktop-links` | `X-Admin-Key` | `{companyGlobalId, name}` → `{linkId, linkSecret}` (secret shown once; only its SHA-256 is stored) |
| POST | `/admin/desktop-links/<linkId>/revoke` | `X-Admin-Key` | revoke the desktop credential |
| GET | `/desktop/ping` | desktop | test connection: company + pending counts per kind |
| POST | `/desktop/master` | desktop | master-data upsert by `globalId` (desktop wins): `company` (I-4 identity keys `nameEn`, `commercialRegister`, `address`, `phone`, `eInvoiceEnabled` are overwritten only when sent), `employees`, `warehouses`, `safes`, `parties` (balance = desktop ledger), `products` (barcode normalized with the shared `normalizeBarcode`), `priceLists` (with full `items`), `distributionAreas`, `salesRoutes`, `routeCustomers`, `repResources`, `voucherBooks` (+ `cancelledNumbers`; `nextNumber` never moves back), `vanStock`; references as `*GlobalId`; unknown references are skipped and reported → `{applied, skipped}` |
| GET | `/desktop/documents/pending?limit=` | desktop | accepted field documents not yet posted on desktop (invoices, returns, collections, visits) with lines and every reference as a global id, oldest first |
| POST | `/desktop/documents/ack` | desktop | `{results:[{kind, globalId, status:"posted", desktopId, desktopNumber} \| {…, status:"failed", reason}]}`; `posted` is final (a re-ack keeps the first number), `failed` keeps the document pending with `lastDesktopError` |
| POST | `/desktop/pairing-codes` | desktop | `{employeeGlobalId, pin?}` → pairing code for a rep (sets the rep's app PIN when given) |

Desktop headers: `Authorization: Bearer <linkSecret>` and `X-Desktop-Link: <linkId>`.

Served customer balances and van stock are materialized as the desktop value plus the accepted field documents the desktop has not posted yet (invoice remaining, collections, return offsets; sold/returned quantities), so the desktop must ack before it pushes balances (it does).

### Push documents

```jsonc
{"kind":"sales_invoice","globalId":"<uuid v4>","number":"VS-100000","date":"<ISO>",
 "customerGlobalId":"…","lines":[{"productGlobalId":"…","quantity":2,"unitPrice":2.5,"discount":0}],
 "paid":5.8,"total":5.8 /* optional; checked against the server's total ±0.01 */}
{"kind":"collection","globalId":"<uuid v4>","customerGlobalId":"…","amount":20,
 "bookGlobalId":"…","bookNumber":1001}
{"kind":"sales_return","globalId":"<uuid v4>","number":"VR-100000","date":"<ISO>",
 "originalInvoiceGlobalId":"…","lines":[{"productGlobalId":"…","quantity":1}],
 "reason":"damaged","total":2.9 /* optional ±0.01 */,"cashRefund":0 /* optional ±0.01 */}
{"kind":"visit","globalId":"<uuid v4>","customerGlobalId":"…","date":"<ISO>",
 "outcome":"visited|no_sale","noSaleReason":"closed|owner_absent|has_stock|no_cash|refused|other",
 "note":"…","latitude":31.95,"longitude":35.9}
``

Pricing at the gate (unless the rep has `can_override_price`): the unit price must equal the resolved price — wholesale price for `price_level='wholesale'` customers, else the first active default/ordered price list whose tier `min_quantity ≤ qty` matches, else the sale price (`price_not_allowed`, details `expected`/`source`). Totals follow `computeTotals` for both tax modes; the effective item tax rate is 0 when exempt, the item rate when > 0, else the company default. The same code runs on the device — both use `packages/picpos_rules`, whose tests run the shared fixture `docs/mobile/fixtures/pricing_parity.json`.

Returns: valued pro-rata from the original invoice line (the whole remainder when returning all that is left), quantity ≤ sold − previously returned, goods back into the **rep's van**, settlement as desktop `SalesReturnRefundSplit` (offset the unpaid part of the invoice first, refund the rest in cash from the custody safe), `VR-` number from the device lease, `v2:` integrity hash.

Rejection codes:
- Number and identity: `number_out_of_range`, `number_already_used`, `global_id_conflict`, `invalid_global_id`.
- Customer and resources: `customer_not_on_route`, `no_van_warehouse`, `unknown_product`.
- Amounts and lines: `insufficient_van_stock` (details `available`/`requested`), `credit_limit_exceeded` (details), `totals_mismatch`, `invalid_payment`, `invalid_line`, `no_lines`.
- Voucher books: `book_not_found`, `book_not_active`, `book_not_held_by_rep`, `book_number_out_of_range`, `book_leaf_used`, `book_leaf_cancelled`, `book_number_required`, `invalid_amount`.
- Pricing: `price_not_allowed`.
- Returns: `invoice_required`, `invoice_not_found`, `invoice_not_returnable`, `customer_mismatch`, `product_not_on_invoice`, `return_qty_exceeds_sold` (details `sold`/`returned`/`requested`), `refund_mismatch`, `no_custody_safe`.
- Visits: `invalid_outcome`, `no_sale_reason_required`, `invalid_geo`.
- Kind: `unsupported_kind`.

A rejected document leaves no trace, so the device can retry the same `globalId` after fixing it. An accepted document is stored in `sync_idempotency`, and every replay returns the original result with `status: "duplicate"`.

## Implemented vs stubbed

**Implemented and tested** (`test/api_test.dart`, `test/domain_test.dart`, `test/i2_test.dart`, `test/i3_test.dart`; 39 tests against Postgres — the parity fixture cases now run in `packages/picpos_rules`):
- I-1: migrations mirroring the desktop names and the v167 sync columns; pairing (code hashed, device token stored as SHA-256), PIN login (PBKDF2), HMAC sessions; number-range leases per device and document type; bootstrap and pull scoped by route → rep; push of sales invoices (lease number, customer on route, van-only stock with row locks, server-side tax and totals, credit limit with desktop parity, stock movements, balance, custody receipt, `v2:` integrity hash) and collections (voucher-book leaf rules); idempotency by `globalId`; WhatsApp outbox with the mock provider.
- I-2:
  - Sales returns against original invoice lines (rules above), idempotent by `globalId`, rep scope (`customer_not_on_route`), van warehouse only, stock movements `return`/`mobile_sales_return`, custody-safe payment for the cash part.
  - Visits (`customer_visits`): visited / no sale with a reason code, optional note and geo, stored with the route sequence; idempotent.
  - Price lists (`price_lists`, `price_list_items`), customer `price_level`, product `wholesale_price`, rep `can_override_price`, company `prices_include_tax` and `decimal_places`; tax-inclusive totals; shared parity fixture.
  - Device token rotation with a one-use grace for the previous token; revocation blocks token, login, rotation and leases.
  - Rate limits: login 10 per device per 10 min, push 60 per device per minute (in-memory sliding window, per API instance), 429 with `Retry-After`.
  - Audit rows: pairing, login, failed login, token rotation, revocation, every accepted and rejected push (device, employee, IP).

- I-3 (`test/i3_test.dart`): desktop link credential (issue, authenticate, revoke), master-data upsert visible in the mobile bootstrap, desktop pairing with PIN, pending feed, ack posted/failed, materialized balances and van stock.
- I-4: migration 4 `i4_print_identity` (`companies.name_en`, `commercial_register`, `address`, `phone`, `einvoice_enabled`) served to the van for receipt printing (bootstrap and every pull); rules moved to `packages/picpos_rules` (server copies of `tax.dart`, `pricing.dart`, `integrity.dart` deleted); `i3_test` covers identity push → bootstrap/pull and barcode normalization. The desktop exporter does not send the identity keys yet (follow-up in `lib/services/cloud_sync/`; until then the van prints the Arabic name and tax number only).

**Stubbed or gaps:**
- **Journal entries are not posted in the cloud.** The desktop pulls the accepted documents and posts them with the existing posting engine (I-3, `lib/services/cloud_sync/`), which gives the same accounting by construction (§8 of the architecture).
- Header discounts and remote approval of price overrides are not modelled (the device sends no header discount; overrides are a rep permission).
- Rate-limit counters live in memory: with several API instances behind a load balancer they are per instance (move to Postgres/Redis in I-6).
- **`MetaCloudWhatsAppProvider`:** builds the Graph API payload but does not send (I-5). There are no delivery webhooks yet.
- **Admin endpoints:** these use a static `ADMIN_KEY` (test stack only). The desktop link can issue rep pairing codes; issuing the desktop credential itself still uses the admin key.
- **Database access:** single pool, no multi-region, no read replicas.