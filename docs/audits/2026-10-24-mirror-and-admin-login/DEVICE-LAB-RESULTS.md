# Device lab results (2026-10-25, run `run6`)

How to rerun: `docs/testing/DEVICE-LAB.md`. Evidence root: `D:\qa\device-lab\run6\`
(`steps.log` timestamped, `NN-*.png` screenshots, `*.xml` UI dumps, `logcat.txt`, `host.log`, `host-api.log`, `summary.md`).

Environment: AVD `PicPos_Van` (android-34 google_apis x86_64, headless, swiftshader_indirect, booted in ~55 s), host reached at
`10.0.2.2`. Host = REAL `NetworkService.startServer` (TLS, `0.0.0.0:18443`, fingerprint pinned by the app) from a
`git archive HEAD` snapshot (909f2d38), because the working-tree `lib/services/api/m1_wh/wh_blind.dart` (other worker, in progress)
did not compile (`Variable.int` not found) at the time. APKs: the release APKs built 2026-10-24 (warehouse 12:43) copied to
`D:\qa\device-lab\apks\`. Caveat: the warehouse APK was built from the tree at that time, the host from HEAD; they interoperated.

## Scenarios

| Id | Result | Evidence |
|---|---|---|
| ENV host / emulator / 4 APK installs | PASS | `steps.log` 14:4x; `/api/m1/info` -> `{"tls":true,...}` |
| S1.1 warehouse launch, no crash | PASS | `01-s1-launch.png`; process alive, no crash buffer entries |
| S1.2 plain-HTTP host refused | PASS | `02-s1-plain-http.png` (stays on pairing, network error); decoy on :18080 |
| S1.3 wrong fingerprint refused | PASS | `03-s1-wrong-fp.png`; the SAME code then pairs in S1.4, so the refused attempt never reached `/api/pair` (pin checked first) |
| S1.4 pair over 10.0.2.2 (code + fingerprint, TLS) | PASS | `04-s1-paired.png`; `host-api.log`: `POST /api/pair`; `devices.json`: kind=warehouse branch_id=1 |
| S1.5a wrong password | PASS | `05-s1-login-bad.png`; host `POST /api/auth/session -> 401` |
| S1.5b user without `warehouse_mobile_access` (cashier1) | PASS | `06-s1-login-cashier.png`; host `GET /api/m1/wh/session -> 403` |
| S1.6 login + role-aware home | PASS | `07-s1-home.png`: "مرحباً Lab Clerk", Branch One, clerk badge, only "B1 Main WH", no supervisor-only items |
| S1.7 item lookup scoped to device branch | PASS | `08-s1-lookup-barcode.png`: Lab Milk **12.0** in B1 Main WH; B2's 99 never shown. `09-s1-lookup-name.png` same for name search (B2's 55 absent) |
| S1.8 host revokes device -> app wipes | PASS | `15-s1-after-revoke.png` back on pairing screen after the next lookup; `devices.json`: `revoked:1` |
| S2a cashier (mobile_pos) launch | PASS | `18-S2a-pos-launch.png`: "ربط جهاز الكاشير ... معاينة فقط — الربط غير متاح حالياً" |
| S2a.2 cashier pairing | NOT_APPLICABLE | `mobile_pos/lib/screens/onboarding_screen.dart:53-55` (`onPressed: null`); dump: 2 disabled buttons; gap P7/M-5 (`mobile_pos/test/e2e/pos_app_e2e_test.dart:17`). Host side (`deviceKind:'pos'`) exists but no client |
| S2b admin (mobile_admin) launch | PASS | `19-S2b-admin-launch.png` ("ربط هذا الجوال - بالسحابة وبشبكة المحل معاً") |
| S2b.2 admin pairing | NOT_APPLICABLE | pairs with the cloud (`mobile_admin/lib/admin_session.dart:109`, `manage_client.dart:226`), no LAN leg; the lab host serves no `/manage/pair` |
| S3 Van (mobile) launch | PASS | `20-S3-van-launch.png` (cloud pairing form, prefilled `http://10.0.2.2:18080`) |
| S4 offline (Wi-Fi/data off + airplane) | PASS (with UX note) | `10-s4-offline-lookup.png`: no stale/fake rows, no crash, honest error. After restore `11-s4-back-online.png` returns data |
| S5.1 force-stop + restart keeps pairing | PASS | `12/13-s5-*.png`: app-lock PIN screen, unlock -> still paired (no re-pairing) |
| S5.2 background/resume | PASS | `14-s5-background-resume.png` |
| S5.3 `pm clear` -> unpaired | PASS | `16-s5-repaired.png` then `17-s5-after-pm-clear.png` pairing screen |
| LOGCAT | PASS | no `FATAL EXCEPTION`/`AndroidRuntime: Process: com.picpos`/ANR in `logcat.txt` |
| Desktop Windows smoke | SKIPPED | no data-dir switch: DB `getApplicationDocumentsDirectory()` (`lib/data/database/connection_io.dart:40`), prefs in `%APPDATA%`, secrets in Credential Manager; a launch would touch `C:\Users\Dell\Documents\picpos_unified.db*`. Needs a throwaway Windows user/VM or a product `PICPOS_DATA_DIR` override |

No scenario FAILed in the final run. Earlier runs (run1-run5) failed only from lab-driver bugs (PowerShell 5.1 vs `pwsh`,
script encoding, `$pin`/`$PIN` case-insensitive clash, IME back-key); fixed in `tool/device_lab`.

## Findings (not failures; product observations)

1. **Offline message is ambiguous** - the warehouse app shows one text for no network and for fingerprint mismatch: "تعذّر الاتصال بالمكتب أو لم تتطابق بصمة الشهادة" and has no distinct offline banner (`mobile_warehouse` `err_network`, `lib/l10n/strings.dart:117-120`). Honest, but a user in airplane mode is told about certificates.
2. **Revoke is detected lazily** - the revoked phone only wipes on its next call (lookup/refresh), not proactively; fine for the stated contract, worth knowing.
3. **Single pending pairing offer** - `LanPairingService` keeps one `_pendingOffer` (`lib/services/api/lan_pairing_service.dart:165`): issuing a second code silently invalidates the first. Pairing two phones from two dialogs in parallel would race.
4. **Rate-limit classification warnings** on the host: `/api/m1/info` and `/api/pair` are "not in classification map" (`lib/services/api/api_rate_limiter.dart` `_classRules`) and fall to the default 120 req/60 s class (host log).
5. Working tree `lib/services/api/m1_wh/wh_blind.dart:21` (other worker, in progress) does not compile at the time of the run (`Variable.int`; drift's `Variable.withInt`).

## Environment issues

- Pre-existing `com.picpos.pos/admin/picpos_van` on the AVD were signed with a different key (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`); the lab uninstalls them (lab AVD only).
- A second adb device `A3SQUT5530001476` was attached; the lab only addresses `emulator-5554`.
- `*.ps1` is in `.gitignore` (line 51): the lead must `git add -f tool/device_lab/*.ps1`.
- Dev shell is Windows PowerShell 5.1 (no `pwsh`); scripts are UTF-8 with BOM.

## Files created

`tool/device_lab/{lab_lib,run_lab,start_emulator,stop_emulator}.ps1`, `test/device_lab/serve_host_test.dart`,
`docs/testing/DEVICE-LAB.md`, this file. Scratch: `D:\qa\device-lab\` (apks, src snapshot, run1-run6, logs).
