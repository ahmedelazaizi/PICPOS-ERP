# picpos_van — PicPos cash-van Android app (Phase I-1)

An offline-first Flutter app for Android. It uses Material 3, themed from the `DESIGN.md` tokens (brand blue `#0250D3`, Cairo font, light and dark schemes). The interface is Arabic RTL by default, with English available. The design is in `docs/mobile/ARCHITECTURE-I.md`.

## Build and test

```powershell
cd D:\PICPOS-ERP\mobile
D:\Cash\develop\flutter\bin\flutter.bat test                 # unit + widget tests (the live test is skipped)
D:\Cash\develop\flutter\bin\flutter.bat build apk --debug    # build\app\outputs\flutter-apk\app-debug.apk
# Contract test against the docker stack (docker/README.md):
$env:CLOUD_URL='http://localhost:18080'; D:\Cash\develop\flutter\bin\flutter.bat test test/live_cloud_test.dart
```

On the emulator the default server address is `http://10.0.2.2:18080`. On a phone, use the PC's LAN IP. The manifest allows cleartext HTTP **for the test stack only**; production will be HTTPS only.

## Structure

| Path | What |
|---|---|
| `lib/theme/brand_theme.dart` | Material colour roles, type scale (Cairo) and shapes from `DESIGN.md` |
| `lib/l10n/strings.dart` | AR/EN string table |
| `lib/data/local_store.dart` | `LocalStore` contract, `OutboxEntry`, and `MemoryLocalStore` for tests |
| `lib/data/sqflite_store.dart` | On-device SQLite: `kv`, `entities` (JSON by kind and globalId) and `outbox` |
| `lib/data/cloud_api.dart` | `CloudApi` contract and `HttpCloudApi` (pair, login, bootstrap, pull, push) |
| `lib/domain/sale_math.dart` | Tax rule, totals and credit rule (same as server and desktop) |
| `lib/state/app_controller.dart` | Session, sync engine (push outbox, then bootstrap or pull), offline rules, number leases, voucher-book leaves |
| `lib/screens/*` | Pairing, PIN login, today's route, customer card, new sale, collection, van stock, sync status |
| `lib/printing/receipt_printer.dart` | Printing interface only (I-4) |

## Implemented vs stubbed (I-1)

**Implemented:**
- **Pairing, login and sync**
  - Pairing (code → device token) and PIN login. The PIN is cached as a salted hash so the app can be opened offline.
  - If the server reports `device_revoked`, the app wipes its local data.
  - Sync: the outbox is pushed in batches of 50 and per-document results (`accepted`/`duplicate`/`rejected`) are recorded. Then the app bootstraps or pulls deltas and applies the scope lists.
  - The local lease `nextNumber` is kept when it is ahead of the server's.
- **Offline rules:**
  - van stock = last-synced stock − pending sales;
  - credit limit against the last-synced balance plus pending documents (limit 0 = no limit);
  - invoice numbers from the device lease;
  - the voucher-book leaf suggestion and its validation.
- **Screens:**
  - **Route:** customers in sequence, each with a visit status (derived from today's documents).
  - **Customer card:** balance, limit and available credit.
  - **Sale:** barcode entry by keyboard-wedge or hardware scanner, a product picker, the cart, cash or credit, and the amount collected now.
  - **Collection:** with a voucher-book leaf.
  - **Van stock.**
  - **Sync status:** pending, accepted and rejected documents, with the rejection reasons.
- **Tests:** controller tests (5), widget tests (5), and a live contract test against the docker API that passes.

**Stubbed or later:**
- Camera barcode scanning (I-2, `mobile_scanner`).
- Automatic background sync and back-off (I-2; today sync runs at login and on demand).
- Sales returns and visit records (no-sale reasons, GPS) — I-2.
- SQLCipher encryption and a Keystore key (I-2).
- Token rotation (I-2).
- Bluetooth ESC/POS printing (I-4).
- WhatsApp sending happens on the server (mock today, I-5).
- Navigation rail for tablets.
- The dynamic-colour decision.
- Emulator screenshots: none were taken in I-1.
