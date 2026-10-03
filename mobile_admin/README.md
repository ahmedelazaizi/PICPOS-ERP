# picpos_admin — «PicPos إدارة» / PicPos Admin

Owner / finance-manager Android app (`com.picpos.admin`). Architecture:
[`docs/mobile/ARCHITECTURE-M.md`](../docs/mobile/ARCHITECTURE-M.md); phase status:
[`docs/mobile/M-0-NOTES.md`](../docs/mobile/M-0-NOTES.md).

```
flutter analyze && flutter test            # shell matrix AR/EN × light/dark × phone/tablet, goldens, guards
flutter build apk --release                # signed with android/key.properties (git-ignored), else debug key
flutter test --update-goldens test/golden_test.dart   # only on a deliberate UI change
```

Shared code: `../packages/picpos_ui`, `../packages/picpos_api_client`, `../packages/picpos_device`.
