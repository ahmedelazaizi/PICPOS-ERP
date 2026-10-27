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


# Addendum: warehouse phases W2-W5 (run `w-20261025-193844`, 2026-10-25 evening)

Evidence root: `D:\qa\device-lab\w-20261025-193844\` (`steps.log`, `NN-*.png`, `facts-*.json` = host facts per step, `api-*.json` = HTTPS probe responses, `summary.md`, `logcat.txt`, `host.log`).
APK under test: `mobile_warehouse/build/app/outputs/flutter-apk/app-release.apk`, built 2026-10-25 15:30, **85,026,584 bytes, SHA-256 `76EB438FDCA68B9149442EB0BC5409FA0E50D66FACF4846940764B306C44D939`**, copied fresh to `D:\qa\device-lab\apks\warehouse.apk` by the run (the previous run had used an older 83,386,584-byte copy). Host = REAL `NetworkService.startServer` (TLS) from the working tree; run with `-SkipLegacy` (S1-S5 were NOT re-run on the new APK; last pass was run 20261025-181236 on the older APK).

| Id | Result | Evidence |
|---|---|---|
| W0 fixtures/defaults (transfer setting OFF) | PASS | facts-w-start.json |
| W-LOGIN clerk1 (pair with pin + login, new APK) | PASS | steps.log |
| W5.1a inbox hidden from clerk (UI + API 403) | PASS | 01-w51-clerk-docs.png, api-w51-clerk-approvals.json |
| W2.1a receive by barcode -> receipt `submitted`, 2 lines | PASS | 02/03-recv-PO-00001-*.png, facts-w21.json |
| W2.1b receipt moves no stock, no ledger entry | PASS (lab assertion bug) | stock Rice absent, 0 purchase journal rows. The scripted check FAILED only because its invoice-count query errored (`no such column source_order_id`, now fixed in serve_host_test.dart); not re-run. Design R-A: `wh_receipt_handlers.dart:11`; PO `received_quantity` IS bumped at submit (6,5) before any stock posts |
| W2.1c outbox shows ops accepted | PASS | 04-w21-outbox.png |
| W2.4 accountant convert posts stock once; 2nd convert refused | PASS (invoice count check unreliable, same query bug; stock 6/5 and `posted_ref_id=1` confirm) | facts-w21-convert*.json |
| W2.2 same command id replayed -> `replayed:true`, no duplicate; new id refused 409 | PASS | api-w22-*.json, facts-w22.json |
| W2.3a over-receipt 11 of 10 refused by host, nothing counted | PASS | facts-w23.json (draft only, received 0) |
| W2.3b user told (outbox rejected + reason) | PASS | 07-w23-outbox.png |
| W2.3c receive screen does not claim success for a refused receipt | **FAIL (product)** | 06-recv-PO-00002-after-send.png shows "أُرسل الاستلام إلى المكتب." although the host rejected it. `mobile_warehouse/lib/screens/receive_pages.dart:139-141` (`report.complete` is true when the queue drained, rejected ops included) |
| W4.1a counter UI never shows expected qty | PASS | lookup shows "الكمية محجوبة أثناء الجرد"; w41-*.png |
| W4.1b counter API DTOs carry no expected/variance/quantity; review 403 | PASS | api-w41-*.json |
| W4.2a-d count, self-approve 403, early approve `recount_required`, recount by clerk3 | PASS | api-w42-*.json, facts-w42-*.json |
| W4.2e supervisor approves in inbox -> Oil 20 -> 18, both submissions `posted` | PASS | review dialog png, facts-w42-approved.json |
| W4.2f second approval -> 409 `already_finalized`, stock unchanged | PASS | api-w42-second-approve.json |
| W5.1b inbox hidden from storekeeper | PASS | api-w51-store-approvals.json |
| W5.1c inbox visible to supervisor (2 transfers + count) | PASS | api-w51-super-approvals.json |
| W5.1d visible to stock manager | PASS | w51-manager-docs.png |
| W5.1e accountant cannot sign in ("no warehouse app permission") | PASS | w51-accountant-login.png |
| W5.2 label print, no printer: honest message, no fake success | PASS | w52-label-print.png |
| W3.1 transfer OFF -> 409 `staged_transfers_disabled`, screen says so, no doc | PASS | api-w31-off-request.json, w31-*.png |
| W3.2a-f request/approve (different user)/dispatch (B1 10->6, GIT 40)/receive (6+4, GIT 0)/replays never double | PASS | facts-w32-*.json |
| W3.3 transfer 8 of 3 refused at dispatch, doc stays `approved`, stock 3 | PASS | facts-w32-dispatched.json |
| W5.3a-d offline queue, survives relaunch, replays once, 2nd drain no duplicate | PASS | w53-*.png, facts-w53-*.json |
| W5.4a revoked device: queued receipt not replayed (0 docs) | PASS | facts-w54.json |
| W5.4b user is told the phone was unpaired | **FAIL (product, UX)** | 34-w54-after-send-now.png: app is wiped back to the pairing screen with no explanatory message; the queued receipt is silently discarded. `wh_outbox.dart:101` rethrows `deviceRevoked`; wipe in `wh_session.dart:170-176`; `err_device_revoked` text is never shown on that path |
| W-CRASH / LOGCAT | PASS | no FATAL/ANR |

## Defects / observations
1. **W2.3c** receive screen shows a success snackbar for a receipt the host refuses (`receive_pages.dart:141`). The truth is only in the Outbox tab.
2. **W5.4b** revoked phone loses its queued documents silently (no message on pairing screen).
3. With the transfer setting OFF the Transfers screen shows the honest message, but "طلب تحويل" and the whole request form stay usable (a request can be queued and will be rejected) - minor.
4. Home role badge reads "مشرف / مدير مخزون" for the storekeeper (any `inventory_transfer` holder) (`wh_contracts.dart:49`) - labelling only.
5. Sign-out keeps the outbox, so ops queued by one user would be sent under the next user who signs in (not exercised; read from `wh_session.dart:179`, `wh_outbox.dart`).
6. `goods_in_transit` journal debit landed on account 1134 and the credit on 1136 (account names "مخزون البضاعة التامة الصنع" / "...للبيع"): mapping of `goods_in_transit` to a finished-goods inventory account is worth an accountant's review.

## Lab limits / lessons
- Launching `run_lab.ps1` through a hidden `Start-Process` with redirected output made UI dumps unreliable (pairing form button missing, login not detected) in 3 runs; the same script run as a tool background job paired fine. Pair-Form now also waits for the IME and falls back to a geometry tap.
- Replays by command id, DTO checks and the accountant convert are driven from the host process (probe phone / real service), not from the app UI.
- Camera, printer hardware, Arabic typing not covered. Legacy S1-S5 not re-run on the new APK.

# Addendum 3: full rerun after the lab-script fixes (run `20261026-012136`, 2026-10-26)

Evidence root: `D:\qa\device-lab\20261026-012136\` (`steps.log`, `NN-*.png`, `facts-*.json`, `api-*.json`, `summary.md`, `logcat.txt`, `host.log`).
APK under test: `mobile_warehouse/build/app/outputs/flutter-apk/app-release.apk` (signed, built 2026-10-26 00:27), **85,042,968 bytes, SHA-256 `5C4A8BF6EE8D903C55F516F47B58FBA2EA19FE7CCBCC1FFCAA51D19D689A0D58`**, copied fresh to `D:\qa\device-lab\apks\warehouse.apk` by the run (row `ENV-APK-wh identity`). Host = REAL `NetworkService.startServer` (TLS) from the working tree; full run (S1-S5, S2, S3, W2-W5), emulator `emulator-5554` (android-34).

**Result: 67 PASS, 0 FAIL, 2 NOT_APPLICABLE** (69 rows incl. ENV rows and LOGCAT). The previous run `20261026-002725` (same APK) had 61 PASS / 6 FAIL / 2 NOT_APPLICABLE; all six FAILs were lab-script problems, none a product defect:

| Previous FAIL | Cause (verified) | Fix in `tool/device_lab` |
|---|---|---|
| S5.3 pm clear -> unpaired | lab: after `pm clear` the address field stayed empty (`16-s5-repaired.png` of the old run shows the app's own "بيانات الإقران ناقصة"), so the re-pair never happened; the pairing code itself was fine | `Pair-Form` re-reads the three fields from the UI dump and retypes a missing one; `Fresh-Pair-And-Login` retries once with a NEW code (one pending offer only) |
| W2.1c outbox ops accepted | lab: asserted the internal name `receipt_submit`; the UI shows "استلام: إرسال" / "استلام: الأصناف" + "مقبولة" | primary = host events (1x `receipt_submit` + 1x `receipt_lines`), secondary = Arabic UI text |
| W3.2e / W3.2f transfer receive | lab: `transfer_pages.dart:67` and `:71` open TWO keypad sheets (received qty, then "منها تالف (المرسل n)"); the driver confirmed only the first, so no receive was ever sent. App is correct: with both sheets confirmed the doc becomes `received`, stock 6/4, in-transit 0 (`43-w32-after-receive.png`, `facts-w32-received.json`). W3.2f failed only as a consequence (its own new-key receive performed the first receive) | driver waits for each sheet title and confirms both; `Enter-Qty` waits 1 s for the slide-in animation |
| W5.3a / W5.3b offline queue + relaunch | lab: asserted `receipt_submit` text; UI shows the two receipt ops with "بانتظار الإرسال" chips, counter "بانتظار الإرسال: N · مرفوضة: M" and the banner "لا اتصال بالمكتب. العمليات المحفوظة: N" | host-side "no document yet" is primary, Arabic UI text secondary (`>=2` pending, because the rejected W3.3 dispatch also sits in the outbox) |

During the rerun one more lab bug of mine was caught and fixed before the final run: the new field check compared only a 10-character prefix, and `10.0.2.2:18080` / `10.0.2.2:18443` share it (S1.4 failed); it now compares the full value.

| Id | Result | Evidence (under the run folder) |
|---|---|---|
| ENV-APK-wh identity | PASS | `steps.log` (size 85,042,968, SHA-256 below) |
| ENV-HOST | PASS | `steps.log` |
| ENV-EMULATOR | PASS | `steps.log` |
| ENV-INSTALL-wh | PASS | `steps.log` |
| ENV-INSTALL-pos | PASS | `steps.log` |
| ENV-INSTALL-admin | PASS | `steps.log` |
| ENV-INSTALL-van | PASS | `steps.log` |
| S1.1 launch (no crash, onboarding) | PASS | `01-s1-launch.png` |
| S1.2 plain-HTTP host refused | PASS | `02-s1-plain-http.png` |
| S1.3 wrong fingerprint refused (pin enforced) | PASS | `03-s1-wrong-fp.png` |
| S1.4 pair over 10.0.2.2 with code + fingerprint (TLS) | PASS | `04-s1-paired.png` |
| S1.5a wrong password refused | PASS | `05-s1-login-bad.png` |
| S1.5b user without warehouse_mobile_access refused | PASS | `06-s1-login-cashier.png` |
| S1.6 login + role-aware home (clerk: branch One, only B1 warehouse) | PASS | `07-s1-home.png` |
| S1.7 item lookup scoped to the device branch | PASS | `08-s1-lookup-barcode.png` |
| S1.7b name search also branch-scoped | PASS | `09-s1-lookup-name.png` |
| S4 offline: honest error, no stale/fake data, no crash | PASS | `10-s4-offline-lookup.png` |
| S4b recovery after network returns | PASS | `11-s4-back-online.png` |
| S5.1 force-stop + restart keeps pairing | PASS | `12-s5-restart.png`, `13-s5-after-unlock.png` |
| S5.2 background/resume keeps pairing | PASS | `14-s5-background-resume.png` |
| S1.8 host revokes device -> app wipes/locks on next call | PASS | `15-s1-after-revoke.png` |
| S5.3 pm clear -> unpaired | PASS | `16-s5-repaired.png`, `17-s5-after-pm-clear.png` |
| S2a pos launch (no crash, UI renders) | PASS | `18-S2a-pos-launch.png` |
| S2b admin launch (no crash, UI renders) | PASS | `19-S2b-admin-launch.png` |
| S3 van launch (no crash, UI renders) | PASS | `20-S3-van-launch.png` |
| S2a.2 cashier LAN pairing | NOT_APPLICABLE | `21-s2a-pos-disabled.png` |
| S2b.2 admin pairing against the lab host | NOT_APPLICABLE | source refs `admin_session.dart:109`, `manage_client.dart:226` |
| W0 fixtures + defaults | PASS | `steps.log` |
| W-LOGIN clerk1 | PASS | `steps.log` |
| W5.1a approvals inbox hidden from the clerk (UI + API) | PASS | `22-w51-clerk-docs.png` |
| W2.1a receive PO by barcode: receipt document exists (submitted, 2 lines) | PASS | `24-recv-PO-00001-after-send.png` |
| W2.1b design R-A: submit moves NO stock and posts NO ledger entry | PASS | `steps.log` |
| W2.1c outbox shows both receipt ops accepted, nothing pending | PASS | `25-w21-outbox.png` |
| W2.4 accountant convert posts stock once (invoice, balances, PO closed) | PASS | `steps.log` |
| W2.4b second convert refused (no double posting) | PASS | `steps.log` |
| W2.2 replay of the SAME submit command id creates no duplicate | PASS | `steps.log` |
| W2.2b a NEW command id on an already-posted receipt is refused (no second effect) | PASS | `steps.log` |
| W2.3a over-receipt (11 of 10) is refused by the host, nothing counted as received | PASS | `28-w23-outbox.png` |
| W2.3b the user is told the quantity was refused (outbox rejected + reason) | PASS | `steps.log` |
| W2.3c receive screen does not claim success for a refused receipt | PASS | `27-recv-PO-00002-after-send.png` |
| W4.1a counter UI never shows the expected quantity (lookup + count page) | PASS | `29-w41-lookup-blind.png`, `30-w41-count-page.png` |
| W4.1b counter API responses carry no expected/variance/quantity (tasks DTO, items DTO; review 403) | PASS | `steps.log` |
| W4.2a first count submitted (counter clerk1, variance recorded privately) | PASS | `32-w42-count-sent.png` |
| W4.2b the counter cannot approve his own count (refused, stock unchanged) | PASS | `steps.log` |
| W4.2c supervisor cannot approve while a recount by another counter is required | PASS | `steps.log` |
| W5.2 label print with no printer: honest "no printer connected", no fake success, no stock effect | PASS | `33-w52-label-print.png`, `34-w52-printer-settings.png` |
| W4.2d recount by a DIFFERENT counter (clerk3) accepted | PASS | `35-w42-recount-sent.png` |
| W3.1 transfer with the setting OFF is refused honestly (API 409 + UI list message, no document) | PASS | `36-w31-transfers-off.png`, `37-w31-new-transfer-off.png` |
| W3.2a store1 requests two transfers (setting now ON) | PASS | `steps.log` |
| W3.2b the requester (no approve right) cannot approve his own transfer | PASS | `steps.log` |
| W5.1b approvals inbox hidden from the storekeeper (UI tile + API) | PASS | `steps.log` |
| W5.1c approvals inbox visible to the supervisor (2 transfer requests + the count) | PASS | `40-w51-super-inbox.png` |
| W3.2c supervisor (different user) approves both transfer requests from the inbox | PASS | `steps.log` |
| W3.2d dispatch reduces source stock and books the in-transit entry | PASS | `42-w32-after-dispatch.png` |
| W3.3 transfer larger than available (8 of 3) is refused at dispatch, no negative stock | PASS | `steps.log` |
| W3.2e receive at destination completes it: stock conserved, in-transit cleared | PASS | `43-w32-after-receive.png` |
| W3.2f never double: replayed command ids answer from the log, fresh dispatch/receive refused, stock unchanged | PASS | `steps.log` |
| W4.2e supervisor (not a counter) approves in the inbox -> adjustment posted once | PASS | `44-w42-review-dialog.png`, `45-w42-after-approve.png` |
| W4.2f a second approval does not post again | PASS | `steps.log` |
| W5.1d approvals inbox visible to the stock manager | PASS | `46-w51-manager-docs.png` |
| W5.1e accountant cannot use the warehouse app (login refused, no inbox) | PASS | `47-w51-accountant-login.png` |
| W5.3a offline: receipt is queued in the outbox, host has nothing yet | PASS | `50-w53-outbox-offline.png` |
| W5.3b queue survives app relaunch (encrypted store) | PASS | `51-w53-outbox-after-relaunch.png` |
| W5.3c network back: the document replays exactly once and the app shows it | PASS | `52-w53-outbox-replayed.png` |
| W5.3d second replay creates no duplicate | PASS | `steps.log` |
| W5.4a revoked device: queued receipt is NOT replayed (no document on the host) | PASS | `55-w54-after-send-now.png`, `56-w54-after-home-refresh.png` |
| W5.4b the user is told the phone was unpaired (and returns to pairing) | PASS | `steps.log` |
| W-CRASH warehouse app alive / no crash buffer entries during W scenarios | PASS | `steps.log` |
| LOGCAT crashes | PASS | `steps.log` |

Product defects found in this run: **none**. The earlier defects recorded above for W2.3c / W5.4b did not reproduce on this APK (W2.3c and W5.4b PASS: the screen no longer claims success for a refused receipt; the unpaired message is shown). Not covered: camera/QR, Arabic typing, printer hardware (see `docs/testing/DEVICE-LAB.md` Limits). Emulator and host were stopped at the end of the run.

# Addendum 4: fresh APKs of all four apps, cashier (C1-C5), Android 14 Bluetooth (W15), count overlap (W14), self-receive (W30)

Run `addendum4-full` (2026-10-26 23:05 - 2026-10-27 00:09), tree = commit `b3882ade` (tracked tree clean), emulator `PicPos_Van` API 34, host =
real `NetworkService.startServer` (TLS, fingerprint pin). Evidence: `D:\qa\device-lab\addendum4-full\` (`steps.log`, `summary.md`, numbered
screenshots, `facts-*.json`, `api-*.json`, `logcat.txt`, `w15-aapt2-permissions.txt`, `w15-dumpsys-package.txt`); APK scan log
`D:\qa\device-lab\scan_apk_addendum4.txt`. Short iteration run `iter2` (same scenarios, before two lab fixes) is kept next to it.

## APKs (`flutter build apk --release` in each folder, all exit 0; copied fresh by `run_lab.ps1` to `D:\qa\device-lab\apks\`)

| App | Package | Size (bytes) | SHA-256 | Signer cert SHA-256 (apksigner verify OK, CN=PicPos) | `tool\ci\scan_apk.ps1` |
|---|---|---|---|---|---|
| mobile_warehouse | com.picpos.warehouse | 85059412 | C52168AF487D339F2DEDC8E116B0A5232AC491B93C223D4F4FA2968EE6EED4EF | 6d9bbe64ebe480fc98a9a0469ee402133f0c95fa996b2aa16739a1b87c6c7e07 | CLEAN |
| mobile_pos | com.picpos.pos | 82469632 | 5B6F022BBC670E6792B042EE6C8D29286F1435FD36C82FB8C6F962253A7C13F5 | 116866999ff055ef1084bfa56f4078f0d9cc7f5d6368daaf4bcc30285010e2b5 | CLEAN |
| mobile_admin | com.picpos.admin | 66731683 | C200A92504326EB77A20AE8FBB82C5D82DF79BCF84F939B65A1E4EB2B21A87F6 | 02fd445548ef0db4582a00d7725097871254fe1031de2391d8d7040361351fce | CLEAN |
| mobile (Van) | com.picpos.picpos_van | 86072637 | E4F68590B870067BC153A4CC4F7BB8D4276278F787680C7DB9563BCCBCC4F639 | 26d479aac98dc0a85dbf80c626cca6b55dac40adc36953f629a2720a12da770d | CLEAN |

All four are `debuggable=false`. Each app has its own signing key. The lab logs size + SHA-256 of each copy in `steps.log` (`ENV-APK-*`), identical to the table.

## Result counts (113 recorded rows): PASS 107, FAIL 4, NOT_APPLICABLE 2, BLOCKED 0

New scenarios (all rows of this addendum):

| Id | Status | Evidence |
|---|---|---|
| C1.0 launch, unpaired, manual entry enabled | PASS | `57-c1-launch.png` |
| C1.1 plain-HTTP decoy refused | PASS | `58-c1-plain-http.png` (error text: cannot reach desktop) |
| C1.2 WRONG fingerprint refused (pin) | PASS | `59-c1-wrong-fp.png` |
| C1.3 pair over 10.0.2.2 with branch-bound pos code + typed fingerprint (same code still valid after the 2 refusals) | PASS | `60-c1-paired.png` |
| C1.4 host lists kind=pos, branch B1 | PASS | `devices.json` line in `steps.log` |
| C1.5 used code refused | PASS | screenshot `61`-series |
| C2.1 wrong password refused | PASS | app shows "بيانات الدخول غير صحيحة" (generic `unauthorized`, not `invalid_credentials`, see observations) |
| C2.2 user without pos_access refused | PASS | app: "لا يملك صلاحية نقطة البيع"; host sign-in clerk1 on the pos tablet => 403 `pos_access_denied` (`api-c2-host-noaccess.json`) |
| C2.3 cashier1 (branch B1) accepted | PASS | shell with 5 tabs |
| C3.1 revoke while signed in -> next app start wipes to pairing + notice "أُلغي ربط هذا الجهاز" | PASS | `67-c3-in-session-after-revoke.png`, `68`... |
| C3.2 revoke at the sign-in screen -> the sign-in call wipes + notice | PASS | screenshot `69`-series |
| C4.1 force-stop/restart keeps pairing + sign-in; C4.2 background/resume | PASS | `66-c4-resume.png` |
| C4.3 `pm clear` -> unpaired | PASS | `70-c4-after-pm-clear.png` |
| C5.1 pos token -> `/api/m1/wh/*` 403 `device_scope` | PASS | `api-c5-wh-approvals.json`, `api-c5-wh-info-user.json` |
| C5.2 pos token -> `/api/mirror/*` 403 `device_scope` | PASS | `api-c5-mirror*.json` |
| C5.3 pos token + cashier works on `/api/branches`, `/api/products`, `/api/sales` (200) | PASS | `api-c5-sales-*.json` |
| C5.4 fresh host: `lan_legacy_token_enabled` absent before `startServer`, `false` after; old bearer => 401 `legacy_token_disabled` | PASS | `facts-c5-legacy-0.json`, `api-c5-legacy-fresh.json` |
| C5.5 refused attempt in the telemetry (`refusedRequests=1`, device `lab-old-phone` refused=1) | PASS | `facts-c5-legacy-1.json` |
| C5.6 legacy bearer ENABLED (setting `true`) => 200, accepted counted | PASS | `api-c5-legacy-enabled.json`, `facts-c5-legacy-2.json` |
| C5.7 switched OFF again => 401 at once | PASS | `api-c5-legacy-off-again.json` |
| C-CRASH cashier app no crash | PASS | |
| W15.0a aapt2: BLUETOOTH + BLUETOOTH_ADMIN `maxSdkVersion=30`, BLUETOOTH_CONNECT, no location | PASS | `w15-aapt2-permissions.txt` |
| W15.0b API 34 `dumpsys package`: no location, legacy BT not requested, BLUETOOTH_CONNECT `granted=false` and no dialog at launch/sign-in | PASS | `w15-dumpsys-package.txt` |
| W15.1 print with no printer: "لا توجد طابعة متصلة", no crash, no prompt, permission still not requested | PASS | `71-w15-1-print-no-printer.png` |
| W15.2a BLUETOOTH_CONNECT requested only when "find Bluetooth printers" is tapped | PASS | dialog screenshot `73`-series |
| W15.2b deny -> "امنح التطبيق إذن البلوتوث..." (not "no printer") | PASS | |
| W15.2c `pm grant` -> no prompt, "لا توجد طابعات بلوتوث مقترنة" | PASS | |
| W15.2d `pm revoke` -> app asks again; denial reported as permission | FAIL | `76-w15-2-after-revoke.png`: dialog still on screen after 3 taps on "Don't allow" (see FAIL analysis) |
| W15.3 no crash through the permission flow | PASS | |
| W14.0-W14.3 two overlapping tasks: newer approve => 409 `overlapping_count_task`; older settles; newer => 409 `stale_overlap_count` | PASS | `api-w14-*.json` |
| W14.4 UI shows WHY the approval was refused (not a generic error) | FAIL (lab) | phone was on the Android home screen (`77-w14-ui-stale-refusal.png`) - not assessable |
| W14.5 recount: retired counter gets 409 `count_not_open`, other counter offered the task | PASS | `api-w14-recount-b.json`, `api-w14-tasks-clerk*.json` |
| W14.6 recount by clerk3 then approve OK; docs `superseded,posted`; stock unchanged | PASS | `facts-w14-done.json` |
| W30.1 dispatcher's own receive => 403 `self_approval`, still `in_transit`, stock untouched | PASS | `api-w30-a-self-receive.json` |
| W30.2 second user (mgr1) receives => 200, stock 2 | PASS | |
| W30.3 UI: dispatcher confirms both keypads on the phone -> transfer stays `in_transit`, a refusal is visible | PASS | `78-w30-ui-self-receive.png`, `79-w30-ui-outbox.png` |
| W30.4 second user then receives | PASS | |
| LOGCAT crashes (whole run) | PASS | no FATAL/ANR in `logcat.txt` |

Legacy S1-S5 and W2-W5 were rerun unchanged except: W3.2e now receives as `mgr1` (the dispatcher `super1` may no longer receive - WH-030) and
`super1` signs back in afterwards; S2a.2 now reports itself as superseded by C1-C5 (the cashier app pairs now). 49 of the 53 legacy rows PASS.
The legacy FAILs: **W2.3b** and **W3.2f** (below).

## FAIL analysis (4)

| Id | Class | Analysis |
|---|---|---|
| W2.3b | lab (pattern) / not re-examined | The phone does show the refusal on the receive screen (`W2.3c` evidence: "رفض المكتب الاستلام: الكمية تتج..."); the outbox-text regex (`مرفوضة: 1` + reason) did not match this time (it matched in Addendum 3). Outbox screenshot `28-w23-outbox.png` was not read in this addendum. Not blamed on the product. |
| W3.2f | UNRESOLVED (lab change vs product) | `replay dispatch => 409 replayed=` (expected 200 `replayed=true`); new-key dispatch/receive correctly 409; stock 6/4, in-transit 0 (no double effect). It passed in Addendum 3. What changed in this run: W3.2e's receiver is now `mgr1` (WH-030) and the commit moved on. The idempotent replay of the dispatch command is not answered from the log once the transfer has been received - candidate product behaviour change (`wh_doc_store.dart` `command()`), unverified. Needs a focused look. |
| W15.2d | lab (probably) | After `pm revoke` + relaunch the system dialog was up and `Deny-Dialog` tapped "Don't allow" three times with the dialog still visible in the last screenshot. W15.2b (first denial) passed with one tap. Either the tap misses on the second dialog or the app re-requests at once; not determined. Re-run `-SkipLegacy -SkipWarehouse -SkipCashier -SkipW14 -SkipW30` after reading the dump. |
| W14.4 | lab bug | `Ensure-App` did not bring the app back after W15 (screenshot = launcher). Static observation only (NOT verified at runtime): `mobile_warehouse/lib/l10n/strings.dart` has no `err_overlapping_count_task` / `err_stale_overlap_count` entry (grep), so the supervisor would see the generic "حدث خطأ غير متوقع" for WH-014 refusals - candidate product defect, to confirm by re-running W14 alone. |

## Product defects / observations

- No confirmed product defect in this addendum. Candidates: (1) missing UI strings for `overlapping_count_task` / `stale_overlap_count` (static grep, `mobile_warehouse/lib/l10n/strings.dart`; unverified at runtime); (2) W3.2f replay behaviour (above).
- `mobile_warehouse/lib/screens/approvals_page.dart:146`: `review.recountNeeded` can never be true inside the review dialog, because the inbox (`wh_approval_handlers.dart`) only lists counts with `readyForApproval`, which excludes `recountNeeded` - the "recount needed" message in the dialog is unreachable (dead branch; the one-line recount UI check requested for W14 therefore cannot be done there).
- Cashier app (`mobile_pos/lib/session/pos_session.dart`): the only authenticated calls are at app start (`verifyStillPaired`) and sign-in. A revoked tablet that stays open in its shell is not wiped until the next start/sign-in (C3.1 documents this); the Cashier shell is still preview-only (Sale/Held/Shift/Returns are placeholders).
- A wrong cashier password shows "بيانات الدخول غير صحيحة" (code `unauthorized`), not the specific `err_invalid_credentials` text: the host answers 401 without the `invalid_credentials` code for a bad password on a device session, or the client does not map it. Cosmetic.
- ANR seen once in the short iteration run `iter2` (`com.picpos.pos`, "Input dispatching timed out (no focused window)" at 22:50, right after C4.3's `pm clear` relaunch left the app on its splash while the lab moved on to the warehouse app). It did NOT recur in the full run (`LOGCAT crashes` PASS). Likely a lab artifact; not proven. C4.3's wait was lengthened afterwards.

## Lab limits (this addendum)

- No Bluetooth printer on the emulator: BLUETOOTH_CONNECT is exercised through the "find paired printers" scan, not through a print to a paired Bluetooth printer.
- Camera/QR never used; fingerprints typed. The Cashier "legacy bearer" checks are host-side (a lab-owned HTTPS call), since the apps no longer use the shared key. This machine derives its own legacy seed or the lab sets a fixed bearer (`serve_host_test.dart`, `legacy` command).
- The lab took ~64 min (not 45). `-SkipCashier` / `-SkipNew` etc. shorten reruns (see DEVICE-LAB.md).

## Files changed (lab only)

`tool/device_lab/run_lab.ps1`, `tool/device_lab/wh_scenarios.ps1` (W3.2e receiver = mgr1), new `tool/device_lab/pos_scenarios.ps1`, new `tool/device_lab/wh_android_scenarios.ps1`,
`test/device_lab/serve_host_test.dart` (pos pairing kind, pos probe tablet, `posapi`, `legacy`, `legacyfacts`), `docs/testing/DEVICE-LAB.md`, this file.
# Addendum 5: the four Addendum-4 FAILs fixed in the lab and rerun (runs `addendum5` + `addendum5b`, 2026-10-27)

Runs: `D:\qa\device-lab\addendum5` (`-SkipLegacy -SkipCashier -SkipW30`: W2-W5 + W15 + W14) and `D:\qa\device-lab\addendum5b` (`-SkipLegacy -SkipWarehouse -SkipCashier -SkipW30 -SkipW15`: W14 only, after a lab-script slip of mine dropped the recount call in the first run; W14.5/W14.6 of `addendum5` are therefore void and superseded by `addendum5b`). Windows PowerShell 5.1, APKs not rebuilt (copied from the existing builds). Emulator and host stopped afterwards.

| Scenario | Result | Classification | Evidence |
|---|---|---|---|
| W3.2f replay of the REAL dispatch command id, same body | PASS (200 `replayed=true`; stock 6/4, in-transit 0; one dispatch event) | LAB BUG | `addendum5\steps.log`, `facts-w32-doubles.json`, `api-w32-replay-dispatch.json` |
| W3.2g (new) same command id, DIFFERENT body | PASS (409 `idempotency_conflict`, stock unchanged) | n/a (new assertion) | `api-w32-replay-dispatch-otherbody.json` |
| W2.3b outbox shows the refusal + reason | PASS | LAB BUG | `addendum5\07-w23-outbox.png`, `w23-outbox.xml`, `steps.log` |
| W15.2d after `pm revoke` the app asks again, denial reported honestly | PASS (dialog gone after 1 tap; UI: "إذن البلوتوث مرفوض نهائياً؛ فعّل «الأجهزة القريبة»…") | LAB BUG | `addendum5\41-w15-2-after-revoke.png`, `w15-deny-dialog-*.xml` |
| W14.4a refusal visible, count not posted, no crash | PASS | LAB BUG (phone had been left off the app shell) | `addendum5b\*-w14-ui-stale-refusal.png`, `w14-ui-stale-refusal.xml`, `facts-w14-ui.json` |
| W14.4b supervisor told WHY (overlap/stale) | FAIL (generic "حدث خطأ غير متوقع.") | PRODUCT OBSERVATION (kept as an honest FAIL) | same |
| W14.5 / W14.6 | PASS in `addendum5b` | n/a | `addendum5b\summary.md` |

Root causes
- W3.2f: the premise "command id belongs to a count command" did not hold. `op-mvpptxy8-…` WAS the dispatch of that transfer (`wh_mobile_doc_events` doc_id 5, `transfer:dispatch`). The 409 came from the body: the phone queues dispatch with `{"expectedVersion":1}` (`mobile_warehouse/lib/screens/transfer_pages.dart:47`) and the host hashes `{action, {gid, ...body}}` (`lib/services/api/m1_wh/wh_doc_store.dart:292`, `wh_stock_doc_handlers.dart:59`); the lab replayed `{}`. Verified offline: SHA-256 of the canonical JSON with `expectedVersion:1` equals the stored `payload_hash` (`b614d6ce…`). The lab now looks up the dispatch event of that document and replays it with `{"expectedVersion": <row_version before dispatch>}`.
- W2.3b: the counter text is `queueCounts` with `ltr()` bidi isolates (U+2066/U+2069 around each number; `mobile_warehouse/lib/widgets/wh_widgets.dart:12`, `screens/outbox_page.dart:61`), so the literal `مرفوضة: 1` never matched. The lab regex is now bidi-tolerant and also checks pending=0, the reason text and the host-side facts (no non-draft doc, PO received 0).
- W15.2d: the second (repeated) request shows `permission_deny_and_dont_ask_again_button` (first time `permission_deny_button`), so the old id never matched. The lab matches `permission_deny\w*button` or the label `Don.t allow` (typographic apostrophe) and also asserts the dialog is gone and BLUETOOTH_CONNECT stays denied.
- W14.4: `Ensure-App` now relaunches, signs in as `super1` when needed (re-pairs if on onboarding), and the check polls for the snackbar. Result: the supervisor DOES get a refusal, but a generic one.

Product observations (not changed)
- Neither `overlapping_count_task` nor `stale_overlap_count` has a warehouse string. `mobile_warehouse/lib/session/wh_session.dart:14-24` (`kDomainCodes`) omits them; `wh_session.dart:31-42` maps the 409 (`ApiErrorKind.conflict`, `packages/picpos_api_client/lib/src/api_error.dart:119`) to `unknown`; `mobile_warehouse/lib/l10n/strings.dart:342-346` falls back to `err_unknown` ("حدث خطأ غير متوقع." / "Something went wrong."); `mobile_warehouse/lib/screens/approvals_page.dart:75-76` shows it via `showFailure` (`widgets/wh_widgets.dart:221-227`) as a snackbar. So the supervisor sees a GENERIC message, not the reason. (`recount_required` has `err_recount_required`; the overlap pair does not.)

Other checks: LOGCAT crash/ANR grep of `addendum5` and `addendum5b` logcat: no FATAL EXCEPTION / ANR for `com.picpos.*` (PASS). Limit: these runs did not exercise `com.picpos.pos` (cashier phase skipped), so the earlier one-off `com.picpos.pos` ANR is "not seen again" rather than disproven for that app.

Files changed (lab only): `tool/device_lab/wh_scenarios.ps1` (W3.2f/W3.2g, W2.3b), `tool/device_lab/wh_android_scenarios.ps1` (permission-dialog patterns, `Ensure-App`, W14.4a/b, W15.2d), this file.