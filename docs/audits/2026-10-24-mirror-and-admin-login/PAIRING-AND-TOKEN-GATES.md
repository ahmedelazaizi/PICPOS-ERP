# Pairing and token gates (owner decisions 2026-10-26)

Scope: (1) the Cashier app pairs with the LAN host, (2) gate G-3 / SEC-006 (legacy shared bearer), (3) gate G-2 (APK brand / identity / signer check).
Signing is out of scope. No Drift table or `schemaVersion` change, no `build_runner`, no APK was built, the Android emulator was not used.

Status words: **fixed** = implemented and covered by a test that ran green here; **partial** = works but a stated part is missing; **not done**.

## 1. Cashier app (`mobile_pos`) pairs with the host: **fixed** (device lab still to run)

**Root cause.** `mobile_pos` was the M-0 shell: the pairing screen had every control disabled ("معاينة فقط — الربط غير متاح حالياً"), the app had no host client, no secret storage and no sign-in. The host already pairs kind `pos` (branch-bound code, terminal code), but a `pos` device was unscoped and any user of the branch could sign in on it.

**What exists now.**

| Layer | Change |
| --- | --- |
| `packages/picpos_api_client` | New kind-generic `DeviceLanClient` (`lib/src/device_lan_client.dart`): `info`, `pair(kind)`, `login`, `probe`, `signOut`, `isRevoked`. `PairingPayload`, `createPinnedLanClient`, `ApiCredentials` and `HttpApiTransport` are reused unchanged. `WarehouseLanClient` was left as is (it could be rebased on `DeviceLanClient` later). |
| `mobile_pos` | `PosSession` (`lib/session/pos_session.dart`): pairs only with a `pos` payload, refuses expired payloads and a host without TLS, pins the certificate fingerprint, stores the per-device token, branch and terminal in the Keystore `SecretStore`, signs in through `POST /api/auth/session`, wipes everything on `401 device_revoked`. `OnboardingScreen` (camera QR through `mobile_scanner`, injectable scanner; manual address + code + fingerprint always works), `LoginScreen`, root state machine unpaired -> sign-in -> shell. Honest error text for every refusal (AR/EN, `S.errorText`), PicPos tokens only. |
| Host | `LanDeviceRoutePolicy`: kind `pos` is a deny-list (`/api/m1/wh/*`, `/api/mirror/*` -> `403 device_scope`). `deviceSessionDenial`: a `pos` device admits only users holding `pos_access` (bootstrap admin excepted) -> `403 pos_access_denied`; the existing branch check still gives `branch_access_denied`. |

**Failing-first / covering tests.**
* `test/security/pos_device_pairing_test.dart` (real in-process host through `LanHost`): v2 payload kind/https/fp/branch; branch bound by the code (the tablet cannot choose another branch), per-device token (not the legacy bearer), one-time code, wrong-kind code refused, stolen pos token -> `device_scope` on warehouse/mirror routes, role-aware sign-in (`pos_access_denied`, `branch_access_denied`), revocation -> `401 device_revoked`, stolen token under another device id refused.
* `packages/picpos_api_client/test/device_lan_client_test.dart` (5 tests).
* `mobile_pos/test/pairing_test.dart` (session: pin, kind, expiry, no-TLS, invalid code, role refusal without half-signed-in state, revocation wipe, offline leaves pairing; screens: manual pairing -> sign-in -> shell in AR/EN x light/dark, honest errors, injected QR, unpaired notice after restart). `test/e2e/pos_app_e2e_test.dart` was updated: it asserted the old "pairing disabled" M-0 behaviour; the two skipped pairing/revocation journeys are now real tests.
* Pre-existing behaviour kept: the legacy shared bearer still works for existing devices (see 2).

**Not covered / unverified.**
* No device-lab run: the emulator has no camera, the camera path (`CameraScanPage`) is untested beyond compilation; manual entry is the tested path. The TLS pin over a real socket is covered by the shared `lan_pinning` tests in `picpos_api_client`, not by a Cashier-specific socket test.
* The Cashier shell is still the M-0 preview (no products, no sale): pairing and sign-in are real, selling is not (separate scope).
* Residual scope gap: `pos` is a deny-list; every other desktop route stays open to a `pos` token plus a valid user session (plan E-9). A host-side requirement "pos code must carry a branch and a fingerprint" was NOT added (the desktop dialog already forces a branch for `pos`; the app refuses payloads without a pin and a host answer without a branch).
* Revocation is noticed on the next authenticated call (`verifyStillPaired` at app start and sign-in failures), not pushed.

## 2. G-3 / SEC-006 legacy shared bearer: **fixed** (for new servers; existing servers untouched)

**Root cause.** Every server start stamped a 30-day legacy window and generated the shared bearer; an owner could only shorten the window, not switch the bearer off, and refused attempts were invisible.

**Fix.**
* Setting `lan_legacy_token_enabled` (`settings` table, no schema change) in `lan_pairing_legacy.dart`. `initializeLegacyTransition()` writes `false` only when the server has **no** transition record yet (a new server). A missing key on a server that already has one means ON, so no existing server is switched off. `legacyAllowed()` = enabled AND inside the window.
* `LanPairingService.setLegacyTokenEnabled(bool, actorUserId:)` needs `devices_pair_manage` (audited as `device_pairing_legacy_token_on/off`); enabling restarts the window so an elapsed window does not make the switch a no-op.
* Middleware (`api_auth_middleware.dart`): when OFF the legacy bearer gets `401 {"error":"legacy_token_disabled"}`; the refused attempt is counted in `LegacyTokenTelemetry` (`refusedRequests`, per device: name, ip, user-agent, last seen, accepted, refused). A plain wrong bearer is still `403 Invalid API token` and is not counted as legacy. `network_service.dart` now always derives the token so the middleware can recognise (and count) it; acceptance stays a per-request decision.
* UI: `LegacyTokenSection` (inside the pairing dialog) - switch, warning when devices still use it, and the telemetry list. Existing "end transition" button kept.

**Tests (real host, real middleware).** `test/security/legacy_token_gate_test.dart` (5): new server refuses with 401 and counts device + user-agent; server without the key stays ON; OFF refuses legacy but paired devices work, ON restores; wrong bearer stays 403; toggle needs the permission. `test/widget/legacy_token_section_test.dart`: telemetry shown, toggle really turns it off. `test/unit/lan_pairing_test.dart` group "legacy transition" now models an upgraded server (legacy ON) explicitly; `LanHost.start(legacyToken: true)` switches it ON like an owner would. Existing legacy tests (`lan_device_credentials_flow`, `f09_security`) pass unchanged.

**Not done / caveats.** Existing servers keep the bearer ON by design (owner decision); nothing was switched off. The telemetry list is in-process (resets on restart); the persisted `legacy_seen` / `last_seen_at` columns still back "devices in use". The user-agent is only kept in memory.

## 3. G-2 APK brand / identity / signer check: **fixed** (CI step added but not yet run on GitHub)

**Root cause.** The brand scan only covered the Windows bundle; APKs were never inspected, so brand strings, a wrong application id or a debug signature could ship.

**Fix.**
* `tool/ci/apk_scan.dart` (pure Dart): scans every zip entry name and bytes (narrow, UTF-16, Arabic spellings, SHA-256 deny list) with the same policy as `tool/brand_artifact_scan.dart`; reads the binary manifest (`package` must be `com.picpos.*` and equal to the expected id of the recognised app, not `debuggable`, label/resources carry "PicPos"); runs `apksigner verify --print-certs` and fails on the Android debug certificate or an unverifiable signature.
* **Only residual allowed:** the ICU time-zone entry `Uralsk.meta` inside `lib/<abi>/libflutter.so` (the Flutter engine's ICU data - found in every built APK). This is the Windows `icudtl.dat` exception applied to its Android counterpart; it is file-scoped and exact, and the tests prove it is NOT allowed anywhere else.
* `tool/ci/scan_apk.ps1` wrapper (finds Java for apksigner; defaults: `PICPOS_APK_PATHS`, `D:\PicPos-Package-278\Android`, `mobile_*/build/app/outputs/flutter-apk`; prints SKIPPED when none exist; `PICPOS_REQUIRE_APK=1` turns that into a failure).
* `test/structural/apk_artifact_guard_test.dart`: scans release APKs from `PICPOS_APK_PATHS` or `mobile_*/build/.../app-release.apk`, skipped with a message when none exist.
* `.github/workflows/ci.yml`: new step "Scan the APK (brand, identity, signer)" in `android-release` after the debug-signature check, `PICPOS_REQUIRE_APK=1`.

**Tests.** `test/unit/apk_scan_test.dart` (13, synthetic zips + a hand-built binary manifest): clean APK passes; brand text in dex / asset names / UTF-16 / libs is reported; "structural"/"natural" are not hits; `Uralsk` allowed only in `libflutter.so`; wrong/non-picpos package, debuggable, missing label, missing manifest, non-zip; debug / unsigned signer.

**Real run on built APKs** (`tool/ci/scan_apk.ps1`): all four `D:\PicPos-Package-278\Android\PicPos-*-0.1.0.apk` (Admin, Cashier, Van, Warehouse) and every `app-release*.apk` / per-ABI / named release APK under `mobile_admin`, `mobile_pos`, `mobile`, `mobile_warehouse` build outputs: CLEAN, release signer not the debug certificate. The `app-debug.apk` files (`mobile`, `mobile_admin`, `mobile_pos`) and `mobile/.../PicPos-Van.apk` fail correctly: debuggable manifest, Android Debug certificate, and (mobile, mobile_admin) a stale `kernel_blob.bin` still containing the old package name from an old debug build.

**Not verified.** The CI step itself (needs the signing secrets on GitHub); label check for resource labels is "resources.arsc contains PicPos" rather than a resolved string.

## Gate status after this change

* **G-2: closed in the repository** (scanner, wrapper, structural test, CI step); CI proof requires one green run and a deliberately broken signing/brand case there.
* **G-3 / SEC-006: closed for new servers** (default OFF, toggle, telemetry, refused attempts counted). Existing servers still run the legacy bearer by decision; closure there is the owner's switch once the telemetry shows zero devices. The rest of G-3 (TLS + `fp` in the QR, pin refusal) was already covered by `lan_pairing_tls_pin_test.dart`.
* W0/W1 are not declared done by this change (the device-lab re-run on a recorded commit is still required).
