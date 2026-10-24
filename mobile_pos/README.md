# picpos_pos — «PicPos كاشير» / PicPos Cashier

Offline tablet POS Android app (`com.picpos.pos`), LAN client of the main desktop. Architecture:
[`docs/mobile/ARCHITECTURE-M.md`](../docs/mobile/ARCHITECTURE-M.md); M-0 status:
[`docs/mobile/M-0-NOTES.md`](../docs/mobile/M-0-NOTES.md).

```
flutter analyze && flutter test            # shell matrix AR/EN × light/dark × phone/tablet, goldens, guards
flutter build apk --release                # needs android/key.properties (git-ignored); FAILS without it - see docs/ops/ANDROID-SIGNING.md
flutter test --update-goldens test/golden_test.dart   # only on a deliberate UI change
```

Shared code: `../packages/picpos_ui`, `../packages/picpos_api_client`, `../packages/picpos_device`, `../packages/picpos_rules`.
