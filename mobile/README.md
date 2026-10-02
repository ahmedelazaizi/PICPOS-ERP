# picpos_van — PicPos cash-van Android app (Phase I-1 + I-2)

An offline-first Flutter app for Android. It uses Material 3, themed from the `DESIGN.md` tokens (brand blue `#0250D3`, Cairo font, light and dark schemes). The interface is Arabic RTL by default, with English available. The design is in `docs/mobile/ARCHITECTURE-I.md`.

## Build and test

```powershell
cd D:\PICPOS-ERP\mobile
D:\Cash\develop\flutter\bin\flutter.bat test                 # unit + widget tests (the live test is skipped)
D:\Cash\develop\flutter\bin\flutter.bat build apk --debug    # build\app\outputs\flutter-apk\app-debug.apk
# Contract test against the docker stack (docker/README.md):
$env:CLOUD_URL='http://localhost:18080'; D:\Cash\develop\flutter\bin\flutter.bat test test/live_cloud_test.dart
```

Android minSdk is 24 (`flutter_secure_storage` 11). The camera permission comes from `mobile_scanner` and is requested on first scan.

On the emulator the default server address is `http://10.0.2.2:18080`. On a phone, use the PC's LAN IP. The manifest allows cleartext HTTP **for the test stack only**; production will be HTTPS only.

## Structure

| Path | What |
|---|---|
| `lib/theme/brand_theme.dart` | Material colour roles, type scale (Cairo) and shapes from `DESIGN.md` |
| `lib/l10n/strings.dart` | AR/EN string table |
| `lib/data/local_store.dart` | `LocalStore` contract, `OutboxEntry`, and `MemoryLocalStore` for tests |
| `lib/data/sqflite_store.dart` | On-device **SQLCipher** database (`sqflite_sqlcipher`): `kv`, `entities` (JSON by kind and globalId) and `outbox`; migrates the I-1 plaintext file once, then deletes it |
| `lib/data/db_key.dart` | 256-bit database key, created on first start and kept in `flutter_secure_storage` (Android Keystore) |
| `lib/data/cloud_api.dart` | `CloudApi` contract and `HttpCloudApi` (pair, login, token rotation, bootstrap, pull, push) |
| `lib/domain/pricing.dart` | Verbatim copy of the server's `tax.dart` + `pricing.dart`: tax rule, totals (tax-exclusive and tax-inclusive), price resolution (wholesale level, price-list tiers), return line amounts and settlement |
| `lib/domain/sale_math.dart` | Cart line helpers and the credit rule |
| `lib/state/app_controller.dart` | Session, sync engine (push outbox, then bootstrap or pull), token rotation every 30 days, wipe on revocation, offline rules, number leases, returns, visits, voucher-book leaves |
| `lib/sync/sync_scheduler.dart` | Background sync: `SyncScheduler` (every 5 min when healthy; backoff 5 s ×3 up to 15 min with ±20 % jitter; immediate run when connectivity returns, 2 s after a document is queued, and on app resume; paused offline) and `BackgroundSync` (runs while signed in) |
| `lib/screens/*` | Pairing, PIN login, today's route, customer card (visit actions), new sale (keyboard-wedge + camera scan), sales return, collection, van stock, sync status |
| `lib/printing/receipt_printer.dart` | Printing interface only (I-4) |

## Implemented vs stubbed

**Implemented (I-1):** pairing and PIN login (offline open with a salted PIN hash); push in batches of 50 with per-document results, then bootstrap or pull with scope lists; local lease numbers kept when ahead; offline van stock, credit limit and voucher-book leaf rules; route, customer card, sale, collection, van stock and sync screens.

**Implemented (I-2):**
- **Sync:** background scheduler with retry/backoff and connectivity awareness (`connectivity_plus`); a push whose response was lost is retried and accepted exactly once (server `duplicate`), and a pull that lists the document marks it accepted; an expired session asks for the PIN again; `device_revoked` wipes credentials, data and outbox; device token rotation every 30 days. The sync tab shows online/offline and the next automatic sync.
- **Pricing:** price per customer and quantity resolved like the server (wholesale level, default/ordered price lists with quantity tiers, sale price), re-resolved when the quantity changes; tax-inclusive companies; the sale is blocked offline with `priceNotAllowed` unless the rep may override prices. Parity: `test/pricing_parity_test.dart` runs the shared `docs/mobile/fixtures/pricing_parity.json` with the same assertions as the server.
- **Sales returns:** pick one of the customer's recent invoices (from pull), return quantities ≤ sold − returned (server + unsent returns), amounts from the original lines, settlement preview (offset vs cash refund), reason, `VR-` number from the device lease; unsent returns raise van stock and lower the balance shown.
- **Visits:** planned / visited / no sale (+ reason) per customer in route order; "Visited" and "No sale" actions on the customer card; any document today counts as visited.
- **Barcode:** camera scanning (`mobile_scanner`, retail 1-D codes + QR, torch) and the keyboard-wedge/hardware path, both through `normalizeBarcode` (strips CR/LF/TAB suffixes, control characters and AIM prefixes).
- **Encrypted local DB:** SQLCipher with the key in the Android Keystore.
- **Tests:** controller, widget, returns, visits, sync scheduler/engine, scanner, pricing and DB-key tests; the live contract test against the docker API now also pushes a return and two visits.

**Stubbed or later:**
- Sync runs while the app process is alive (foreground or recently backgrounded); an OS-scheduled job (WorkManager) for a closed app is not implemented.
- Visit geo-location is accepted by the server but the app does not capture GPS yet (no location plugin).
- Returns are against server-known invoices only (an invoice still in the outbox must sync first). The return screen steps quantities by whole units.
- The revocation wipe clears the database tables; the Keystore key is kept (the data it protected is gone).
- Bluetooth ESC/POS printing (I-4). WhatsApp sending happens on the server (mock today, I-5).
- Navigation rail for tablets; the dynamic-colour decision; emulator screenshots.