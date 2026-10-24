# Android release signing (PicPos Van / Cashier / Admin)

Audit finding **REL-004**. All three apps (`mobile`, `mobile_pos`, `mobile_admin`) now use the
same fail-closed rule: **a release build never falls back to the debug key.** Without a valid
`android/key.properties` the release tasks (`assembleRelease`, `bundleRelease`, `package*Release`,
`sign*Release`) stop with an actionable message. Debug builds are unaffected.

## One-time setup (per release engineer / CI)

1. Generate the upload keystores **outside the repository**:

   ```powershell
   powershell -File tool\gen_android_keystore.ps1            # default folder D:\keys\
   powershell -File tool\gen_android_keystore.ps1 -WriteKeyProperties   # also writes android/key.properties
   ```

   - Needs `keytool` (a JDK; Android Studio's bundled JBR is found automatically).
   - Creates `D:\keys\<app>-upload.jks` (PKCS12, RSA 4096, ~27 years). The script **refuses** an
     output folder inside the repo.
   - Writes `<app>/android/key.properties.example` (no secrets, safe to commit).
   - With `-WriteKeyProperties` it also writes the git-ignored `<app>/android/key.properties`
     (contains the passwords; that file is the standard Flutter/Gradle mechanism).
2. **Back up the `.jks` files and passwords offline** (password manager + an offline copy).
   Losing an upload key means installed APKs can no longer be updated by new builds
   (with Play App Signing the upload key can be reset through Play support; with sideloaded
   APKs it cannot).
3. Build: `cd mobile_pos; flutter build apk --release`.
4. Verify the certificate (must NOT say `Android Debug`):

   ```powershell
   & "$env:ANDROID_HOME\build-tools\<ver>\apksigner.bat" verify --print-certs build\app\outputs\flutter-apk\app-release.apk
   ```

## `key.properties` format

```
storeFile=D:/keys/mobile_pos-upload.jks
storePassword=<keystore password>
keyAlias=picpos-mobile-pos-upload
keyPassword=<key password>
```

`key.properties`, `*.jks` and `*.keystore` are git-ignored; `tool/check_no_secrets.ps1` (CI job
"Secrets check") fails if any is tracked.

## CI

Job `android-release` in `.github/workflows/ci.yml` runs on version tags (and manual dispatch):

1. proves the build is fail-closed (a release build with no `key.properties` must fail);
2. builds a signed APK from the repository secrets `ANDROID_KEYSTORE_BASE64` (base64 of the
   `.jks`), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`;
3. rejects a debug-signed APK (`apksigner verify --print-certs`);
4. **fails the tag** when the secrets are missing, unless `ALLOW_UNSIGNED` is `true`
   (manual dispatch input `allow_unsigned`, or repository variable `ALLOW_UNSIGNED`). Even then no
   unsigned release APK is produced: the signed build is skipped.

All three apps share the secrets above; to use a distinct keystore per app, add per-app secrets and
select them with the matrix `dir`.

## Migrating already-installed debug-signed builds

A device holding a debug-signed APK cannot be updated by a release-signed APK (signature
mismatch). Uninstall first; data is local to the app, so export/sync it before. This is a
one-time cost; later updates are signed with the upload key.

## Not verified here

The Gradle logic was reviewed and mirrors the proven `mobile_admin` pattern; `keytool` generation
was exercised on a developer PC, but an actual `flutter build apk --release` (with and without
`key.properties`) and `apksigner verify` were **not** run in this environment.
