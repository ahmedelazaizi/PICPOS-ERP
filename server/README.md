# picpos_cloud — PicPos cloud API (Phase I-1)

A pure Dart server (`shelf` + `postgres`) with no Flutter dependency. The design and the reasons for a new package (instead of `lib/services/api`) are in `docs/mobile/ARCHITECTURE-I.md`.

## Run

- Docker: see `docker/README.md`.
- Local: `dart run bin/server.dart` with `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`, `PORT`, `TOKEN_SECRET` (≥ 32 chars), `ADMIN_KEY`, `SEED_DEMO=true|false`, `WHATSAPP_PROVIDER=mock|meta` (`meta` also needs `WHATSAPP_PHONE_NUMBER_ID` and `WHATSAPP_TOKEN`).

## Endpoints

| Method | Path | Auth | Purpose |
|---|---|---|---|
| GET | `/health` | none | DB check and active WhatsApp provider |
| POST | `/admin/pairing-codes` | `X-Admin-Key` | `{companyGlobalId, employeeGlobalId}` → `{code, expiresAt}` (8 chars, 10 min, single use) |
| POST | `/admin/devices/<deviceId>/revoke` | `X-Admin-Key` | revoke the device and its number leases |
| GET | `/admin/whatsapp/outbox` | `X-Admin-Key` | last 100 outbox rows |
| POST | `/admin/whatsapp/process` | `X-Admin-Key` | run the outbox worker once (it also runs every 10 s) |
| POST | `/mobile/pair` | none (5 attempts per IP per 10 min) | `{code, deviceId, deviceName}` → `{deviceToken, deviceId, employeeGlobalId}` |
| POST | `/mobile/login` | device | `{pin}` → `{sessionToken}` (12 h) |
| GET | `/mobile/bootstrap` | device + session | company, rep, van, custody safe, routes, then the same payload as a pull with `since=0` |
| GET | `/mobile/sync/pull?since=<ms>` | device + session | delta: `customers`, `customerScope`, `products`, `vanStock`, `voucherBooks`, `voucherBookScope`, `leases`, `documents`, `serverTime` |
| POST | `/mobile/sync/push` | device + session | `{documents:[…≤50]}` → per-document `accepted` / `duplicate` / `rejected{code}` |

The device headers are `Authorization: Bearer <deviceToken>` and `X-Device-Id`. The session header is `X-Session-Token`.

### Push documents

```jsonc
{"kind":"sales_invoice","globalId":"<uuid v4>","number":"VS-100000","date":"<ISO>",
 "customerGlobalId":"…","lines":[{"productGlobalId":"…","quantity":2,"unitPrice":2.5,"discount":0}],
 "paid":5.8,"total":5.8 /* optional; checked against the server's total ±0.01 */}
{"kind":"collection","globalId":"<uuid v4>","customerGlobalId":"…","amount":20,
 "bookGlobalId":"…","bookNumber":1001}
```

Rejection codes:
- Number and identity: `number_out_of_range`, `number_already_used`, `global_id_conflict`, `invalid_global_id`.
- Customer and resources: `customer_not_on_route`, `no_van_warehouse`, `unknown_product`.
- Amounts and lines: `insufficient_van_stock` (details `available`/`requested`), `credit_limit_exceeded` (details), `totals_mismatch`, `invalid_payment`, `invalid_line`, `no_lines`.
- Voucher books: `book_not_found`, `book_not_active`, `book_not_held_by_rep`, `book_number_out_of_range`, `book_leaf_used`, `book_leaf_cancelled`, `book_number_required`, `invalid_amount`.
- Kind: `unsupported_kind` (returns and visits come in I-2).

A rejected document leaves no trace, so the device can retry the same `globalId` after fixing it. An accepted document is stored in `sync_idempotency`, and every replay returns the original result with `status: "duplicate"`.

## Implemented vs stubbed (I-1)

**Implemented and tested** (`test/api_test.dart`, `test/domain_test.dart`):
- Migrations, with tables mirroring the desktop names and the v167 sync columns.
- Pairing, with the code hashed and the device token stored as SHA-256. Rep PIN login uses PBKDF2. Sessions are HMAC-signed. Device revocation is in place.
- Number-range leases per device and document type, with automatic renewal below 20 %.
- Bootstrap and pull scoped by route → rep.
- Push of sales invoices with these checks:
  - lease number and uniqueness
  - customer on today's route
  - van-only stock, with row locks
  - server-side tax (`effectiveItemTaxRate`, ported) and totals
  - credit limit with desktop parity (limit 0 = none; remaining > 0.01)
  - deduction from van stock, stock movements, the customer balance, a custody-safe receipt for the paid part, and a `v2:` HMAC integrity hash in the desktop payload format
- Push of collections with these checks:
  - voucher-book leaf rules (held by the rep, active, in range, not used, not cancelled)
  - `next_number` advance as in desktop `_advanceVoucherBook`
  - the customer balance
- Idempotency by `globalId`.
- WhatsApp outbox, enqueued in the same transaction (opt-in only, unique per document and template), with a worker, back-off and dead-lettering through `MockWhatsAppProvider`.
- Audit log rows for pairing and accepted pushes.

**Stubbed or gaps:**
- **Journal entries are not posted in the cloud.** Desktop pulls the accepted documents and posts them with the existing posting engine (I-3), which gives the same accounting by construction (§8 of the architecture).
- **Pricing:** the I-1 model is tax-exclusive prices with line discounts only. Tax-inclusive companies, header discounts, price lists and rep price-override permission are I-2.
- **Missing endpoints:** sales returns and visits push, token rotation, and login/push rate limits are I-2.
- **`MetaCloudWhatsAppProvider`:** builds the Graph API payload but does not send (I-5). There are no delivery webhooks yet.
- **Admin endpoints:** these use a static `ADMIN_KEY` (test stack only). Admin flows move to desktop in I-3.
- **Database access:** single pool, no multi-region, no read replicas.
