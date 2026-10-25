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