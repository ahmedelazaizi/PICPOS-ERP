# picpos_warehouse - «PicPos مخازن» / PicPos Warehouse

Android app (`com.picpos.warehouse`) for the warehouse clerk, keeper, supervisor and manager. It is a LAN client of the main desktop and is installed on the person's own phone; the phone is paired by the manager who holds the `devices_pair_manage` permission (Settings > Linked apps > PicPos Warehouse > Pair a warehouse phone). Plan: [`docs/plans/2026-10-23-warehouse-app-plan.md`](../docs/plans/2026-10-23-warehouse-app-plan.md).

**Implemented (phases W0-W1):** shell (RTL/LTR, light/dark), QR/manual pairing pinned to the desktop's TLS fingerprint, sign-in with the user's own account, role-aware home from the server's permissions, branch/warehouse scope, local PIN lock, read-only item + stock lookup, encrypted offline store with an outbox skeleton.

**Not implemented yet (the UI says so):** receiving, transfers, counts, vouchers, label printing, sending queued operations (W2-W5).

```
flutter analyze && flutter test            # session, screens AR/EN x light/dark x phone/handheld/tablet, goldens, guards
flutter build apk --release                # needs android/key.properties (git-ignored); FAILS without it - docs/ops/ANDROID-SIGNING.md
flutter test --update-goldens test/golden_test.dart   # only on a deliberate UI change
```

Keystore: `pwsh tool/gen_android_keystore.ps1 -Apps mobile_warehouse -WriteKeyProperties`.

Shared code: `../packages/picpos_ui`, `../packages/picpos_api_client` (`WarehouseLanClient`, `PairingPayload`, `lan_pinning.dart`), `../packages/picpos_device`, `../packages/picpos_rules`.