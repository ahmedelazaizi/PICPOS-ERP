# Device lab (real Android runtime + real sockets)

The unit/integration suites run in-process. The device lab runs the **built signed
APKs on an Android emulator** against the **real production LAN host stack over TLS**,
driven with `adb` only (no Appium).

## What is real, what is not

| Piece | Real? |
|---|---|
| LAN host | `NetworkService.startServer` (real `ApiHandler`, rate limiter, `ApiAuthMiddleware`, `LanPairingService`, `lan_tls` self-signed certificate, bound to `0.0.0.0`). Seeded through the production `ServerSetupWriter` + role defaults. |
| Host DB | in-memory `AppDatabase.forTesting()` (temporary; nothing persisted). Secure storage is an in-memory mock (no native side in `flutter test`). |
| Android apps | the release APKs, real Keystore, real TLS stack, real network (emulator NAT, host = `10.0.2.2`) |
| Camera / QR scan | **not exercised** - the pairing code, address and fingerprint are typed in the manual-entry form |
| Arabic input | not typed (adb cannot): all lab credentials are ASCII; Arabic is only *read* from `uiautomator dump` |

## Prerequisites

- Windows, PowerShell 5.1+ (scripts are UTF-8 with BOM; run them with `powershell -File`), Flutter on `PATH`.
- Android SDK at `D:\dev-cache\android-sdk` (override `ANDROID_SDK_ROOT`), AVD `PicPos_Van` (android-34 google_apis x86_64) and a hypervisor (WHPX/HAXM/Hyper-V).
- Release APKs in `D:\qa\device-lab\apks\` as `warehouse.apk`, `pos.apk`, `admin.apk`, `van.apk`
  (copy from `<app>\build\app\outputs\flutter-apk\app-release.apk`; the lab never runs `flutter build`).
  `run_lab.ps1` re-copies `mobile_warehouse\build\app\outputs\flutter-apk\app-release.apk` over `warehouse.apk` on every run
  and logs its size + SHA-256 (`ENV-APK-wh identity` row of `summary.md`), so a stale copy cannot be tested by mistake.
- Ports 18443 (HTTPS host) and 18080 (plain-HTTP decoy) free.
- Only `emulator-5554` is ever touched (`LAB_SERIAL` overrides); other adb devices are ignored.

## Run

```powershell
powershell -ExecutionPolicy Bypass -File tool\device_lab\run_lab.ps1            # host from the working tree
powershell -ExecutionPolicy Bypass -File tool\device_lab\run_lab.ps1 -Snapshot  # host from `git archive HEAD` in D:\qa\device-lab\src
                                                                                 #   (use when lib/ is mid-edit and does not compile)
# options: -SkipHostStart (a host is already running)  -KeepEmulator  -HostMinutes 45  -RunId x
#          -SkipLegacy (only the W2-W5 warehouse scenarios)  -SkipWarehouse (only S1-S5)
```

Output: `D:\qa\device-lab\<run-id>\` - `steps.log` (timestamped), numbered screenshots,
`*.xml` UI dumps, `logcat.txt`, `host.log`, `host-api.log`, `summary.md`.
Host-only: `LAB_HOST=1 flutter test test/device_lab/serve_host_test.dart` (skipped without `LAB_HOST=1`)
writes `D:\qa\device-lab\host.json` (address, fingerprint, users, pairing codes + QR payloads) and obeys
`cmd.txt` lines: `issue B1|B2`, `revoke-all`, `list`, `stop`.
`start_emulator.ps1` / `stop_emulator.ps1` boot / kill the headless AVD
(`-no-window -no-audio -gpu swiftshader_indirect`, animations off).

Notes: `LanPairingService` keeps **one** pending offer - every `issue` supersedes the previous
code (the driver issues a fresh one before each pairing). Pre-existing lab-AVD packages signed with a
different key are uninstalled before install.

### Rerun a subset

The runner has no per-scenario filter; it is split into two phases, and each phase can be run alone (the emulator is booted and
the host started either way, ~2 min):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool\device_lab\run_lab.ps1 -SkipLegacy      # only W2-W5 (warehouse documents), ~25 min
powershell -NoProfile -ExecutionPolicy Bypass -File tool\device_lab\run_lab.ps1 -SkipWarehouse   # only S1-S5, S2, S3 (pairing, lookup, offline, other apps), ~12 min
```

To iterate on one step, start the host once by hand (`LAB_HOST=1 flutter test test/device_lab/serve_host_test.dart`), then run
with `-SkipHostStart -KeepEmulator` and dot-source `lab_lib.ps1` in an interactive shell (`Get-Dump`, `Screen-Text`, `Tap-Node`,
`Host-Do`, `Get-Facts`) to replay a single step against the booted emulator. Use `-RunId x` to keep evidence apart. Run the lab
as a background job and poll in bounded loops: a full run takes ~35 min.

### Addendum-4 scenarios and rerunning a subset

Phases run in this order: S1-S5 (legacy) -> W2-W5 (`wh_scenarios.ps1`) -> **C1-C5 cashier** (`pos_scenarios.ps1`) -> **W15 / W14 / W30**
(`wh_android_scenarios.ps1`). Switches (all combinable): `-SkipLegacy`, `-SkipWarehouse`, `-SkipCashier`, `-SkipNew` (W15+W14+W30),
`-SkipW15`, `-SkipW14`, `-SkipW30`. Examples (Windows PowerShell 5.1, run as a background job, poll with bounded loops):

```powershell
$lab = 'powershell -NoProfile -ExecutionPolicy Bypass -File tool\device_lab\run_lab.ps1'
# only the cashier app (C1-C5, ~13 min)
& powershell -NoProfile -ExecutionPolicy Bypass -File tool\device_lab\run_lab.ps1 -SkipLegacy -SkipWarehouse -SkipNew
# only Android 14 Bluetooth (W15, ~10 min)
& powershell -NoProfile -ExecutionPolicy Bypass -File tool\device_lab\run_lab.ps1 -SkipLegacy -SkipWarehouse -SkipCashier -SkipW14 -SkipW30
# only count overlap + self-receive
& powershell -NoProfile -ExecutionPolicy Bypass -File tool\device_lab\run_lab.ps1 -SkipLegacy -SkipWarehouse -SkipCashier -SkipW15
```

APKs: build the four release APKs first (`flutter build apk --release` in `mobile_warehouse`, `mobile_pos`, `mobile_admin`, `mobile`, sequentially);
`run_lab.ps1` copies each `mobile_*/build/app/outputs/flutter-apk/app-release.apk` fresh to `D:\qa\device-lab\apks\` and logs size + SHA-256
(`ENV-APK-*`). Verify signer/identity with `apksigner verify --print-certs` and `powershell -File tool\ci\scan_apk.ps1 <apk...>`.

| Id | What it proves |
|---|---|
| C1.* | cashier pairing over 10.0.2.2 with a branch-bound `pos` code + typed fingerprint; wrong fingerprint and plain-HTTP decoy refused; used code refused; host lists kind=pos/branch |
| C2.* | wrong password refused; user without `pos_access` refused (`pos_access_denied`); cashier of the branch accepted |
| C3.* | host revokes the tablet -> wipe to pairing + notice at next start (signed in) / at the sign-in call |
| C4.* | restart/resume keeps pairing; `pm clear` unpairs |
| C5.1-C5.3 | pos device token: `/api/m1/wh/*` and `/api/mirror/*` = 403 `device_scope`; ordinary sales routes work |
| C5.4-C5.7 | legacy shared bearer: OFF on a fresh host (setting absent -> false) = 401 `legacy_token_disabled` + telemetry; ON (`setting|lan_legacy_token_enabled|true`) works; OFF again refused |
| W15.0-W15.3 | aapt2 + `dumpsys package` (no location, BLUETOOTH/ADMIN max SDK 30), no-printer honesty, BLUETOOTH_CONNECT requested only when scanning for printers, deny/grant/revoke via the system dialog and `pm grant/revoke` |
| W14.* | count overlap (`overlapping_count_task`, `stale_overlap_count`), recount, retired counter excluded (host-side via the `api` channel + one UI check) |
| W30.* | the dispatcher cannot receive his own transfer (403 `self_approval`, UI refusal), a second user can |

New host commands (`serve_host_test.dart`): `issue B1|B2 [pos]` (third word = device kind), `posapi|label|user-or--|METHOD|path|json|key` (REAL HTTPS call
from a lab *cashier probe tablet*, kind=pos, branch B1; `-` = device token only), `legacy|label|METHOD|path|deviceId` (old-style shared bearer),
`legacyfacts|name` (`facts-<name>.json`: setting value, accepted/refused counters, attempts). `revoke-all` spares both probes. `host.json` carries
`legacySettingBeforeStart`. The cashier app has no PIN; its screens are matched by Arabic text.
### Lab rules learned the hard way

- **One pending pairing offer.** The host keeps a single pending offer (`LanPairingService._pendingOffer`): every `issue` supersedes
  the previous code, and a used code is gone. Any pairing (also a re-pair after `revoke-all` or `pm clear`) needs a **fresh**
  `New-Code`, and two phones can never be paired in parallel. `Fresh-Pair-And-Login` retries once with a new code;
  `Pair-Form` re-reads the three fields from the UI dump and retypes one that stayed empty (the app answers "بيانات الإقران ناقصة"
  otherwise - once the address was lost right after `pm clear`).
- **Keypad sheet timing.** Quantities are entered in a modal bottom sheet (`askQuantity`) that slides in; a tap during the slide
  misses. `Enter-Qty` waits for the `تأكيد` node and then 1 s. A transfer **receive** opens TWO sheets per line, one after the other:
  "الكمية المستلمة (المرسل n)" (pre-filled with the dispatched qty) and "منها تالف (المرسل n)" (pre-filled 0); each needs its own
  `تأكيد`, so the driver waits for each title (`transfer_pages.dart:67,71`). Confirming only once leaves the second sheet open and
  nothing is sent.
- **Host facts are the primary evidence, UI text is secondary.** Outbox rows are Arabic (op titles "استلام: إرسال",
  "استلام: الأصناف"; status chips "مقبولة" / "بانتظار الإرسال" / "مرفوضة"; counter line "بانتظار الإرسال: N · مرفوضة: M"; offline
  banner "لا اتصال بالمكتب. العمليات المحفوظة: N"). Never match internal op names such as `receipt_submit`; assert the document /
  event / stock on the host first, then the visible text. The outbox also lists every op queued earlier in the run (including the
  rejected W3.3 dispatch), so pending counters are compared with `>=`, not `==`, except right after a drain.

### Host command channel (warehouse phases)

`cmd.txt` lines are acknowledged in `ack.txt` (`<line-index>|<message>`; `Host-Do` in `lab_lib.ps1` waits for it, bounded).
Commands (`|` separated): `setting|key|value`, `product|key|barcode|name|cost|trackExpiry|qtyB1|qtyB1b|qtyB2` (stock goes in through
the real `adjustStock`), `po|key|prod:qty,...` (open PO in B1 Main WH), `count|key|prod,...` (cycle-count task), `facts|name`
(`facts-<name>.json`: stock per warehouse, `wh_mobile_docs` + lines, `wh_mobile_doc_events` = audit rows with actor/device/command id,
purchase orders + received quantities, invoices, journal lines of `wh*`/`purchase*` entries, goods-in-transit balance, stock movements,
batches, count tasks, settings, paired devices), `convert|receiptGid` (accountant step: the real `WhReceiptPosting.convert`),
`api|label|user|METHOD|path|json|idempotencyKey` (a REAL HTTPS call to the host from a second paired *probe* warehouse phone that lives
in the host process; response in `api-<label>.json`; `revoke-all` spares the probe). `fixtures.json` lists what `product/po/count` created.
Every scenario creates its own products / PO / count task, so scenarios do not depend on each other's leftovers; the staged-transfer
setting (`wh_staged_transfers_enabled`) is OFF until W3.2 switches it ON.

Seeded personas (branch B1 unless noted): `clerk1`, `clerk3` (warehouse clerk: receive + count + lookup/labels), `store1`
(`مخزني`: receive, count, transfer, NO approve), `super1` (warehouse supervisor incl. `stock_adjust_approve`; warehouses B1+B1b+B2),
`mgr1` (`مدير مخزون`), `acct1` (`محاسب`: no warehouse-app access), `cashier1` (no warehouse-app access), `clerk2` (B2).
Warehouses: `B1 Main WH`, `B1 Second WH` (transfers stay inside the device's branch), `B2 Main WH`.

## Scenarios and what they prove

| Id | Proves |
|---|---|
| S1.1 | warehouse APK launches, no crash, shows the pairing screen |
| S1.2 | a host that speaks plain HTTP is refused (app is HTTPS-only) |
| S1.3 | a wrong certificate fingerprint is refused (pin enforced) and the pairing code is not consumed |
| S1.4 | pairing with code + correct fingerprint over `10.0.2.2` succeeds (same code as S1.3) |
| S1.5 | wrong password refused; a user without `warehouse_mobile_access` refused |
| S1.6 | login + role-aware home (branch, role badge, only the device branch's warehouse) |
| S1.7 | item lookup returns stock only for the device branch's warehouses (barcode and name) |
| S1.8 | host revokes the device -> the app wipes and returns to pairing on its next call |
| S2a/S2b/S3 | cashier, admin and Van APKs launch without crash and render their first screen |
| S2a.2/S2b.2 | cashier/admin LAN pairing: `NOT_APPLICABLE` with evidence (cashier has none yet - gap P7; admin pairs with the cloud) |
| S4 | Wi-Fi/data off + airplane mode: honest network error, no stale rows, no crash; recovery when back |
| S5 | force-stop/restart and background/resume keep the pairing; `pm clear` -> unpaired |
| LOGCAT | no `FATAL EXCEPTION`/ANR for `com.picpos.*` over the whole run |
| W0 | fixtures seeded through the real services; transfer setting OFF by default |
| W2.1 | receive against a PO by typed barcode + keypad quantity: a `po_receipt` document is `submitted`; **no stock and no ledger entry** until the accountant converts (design R-A, `wh_receipt_handlers.dart:11`); the PO's `received_quantity` is bumped at submit |
| W2.2 | replaying the same command id returns `replayed:true` and creates nothing; a fresh id on an already-posted receipt is refused |
| W2.3 | receiving 11 of 10 is refused by the host (`over_receipt`), nothing is counted, and the user is told (outbox: rejected + reason) |
| W2.4 | accountant `convert` posts stock exactly once (invoice + balances); a second convert is refused |
| W3.1 | transfer with the setting OFF: host answers `409 staged_transfers_disabled`, the Transfers screen says so, no document |
| W3.2 | setting ON: request (store1) -> approve (super1, a different user) -> dispatch (source stock down, goods-in-transit entry) -> receive (destination up, in-transit cleared, sum conserved) -> replays / new ids never double |
| W3.3 | transfer larger than available (8 of 3): dispatch refused (`stock_changed`), stock unchanged, never negative |
| W4.1 | blind count: the counter's UI (lookup, count page) and API DTOs (tasks, items) carry no expected quantity; `review` is 403 for him |
| W4.2 | variance -> second count by ANOTHER counter -> supervisor approves in the inbox -> adjustment posted once; the counter cannot approve (403); early approval = `recount_required` |
| W5.1 | approvals inbox hidden (UI tile + API 403) for clerk / storekeeper, visible for supervisor and stock manager; the accountant cannot sign in |
| W5.2 | label print with no printer: honest "no printer connected", no fake success, no stock effect |
| W5.3 | offline: receipt queued in the outbox, survives app relaunch, replays exactly once when the network returns, a second drain adds nothing |
| W5.4 | device revoked while the outbox holds a receipt: nothing is replayed; what the user is told |

## Limits

- No camera/QR scan, no Arabic typing, no Bluetooth/printer/scale hardware, no real Wi-Fi radio (emulated NAT).
- The Van app pairs with the cloud server (`/mobile/pair`), not the LAN host; here it is a launch smoke test only.
- The desktop Windows app is **not** launched: it has no data-directory switch (DB path is
  `getApplicationDocumentsDirectory()`, prefs in `%APPDATA%`, secrets in Credential Manager), so a smoke launch would touch the
  owner's real data (`C:\Users\Dell\Documents\picpos_unified.db*`). It needs a throwaway Windows user/VM or a
  `PICPOS_DATA_DIR` product override first.
- The offline check is for the warehouse app, which has no dedicated "offline" banner (see results).
- The warehouse app has no Semantics labels / resource-ids; the W scenarios match Arabic text, the `NavigationBar` tab labels
  (`<label> علامة التبويب n من 5`) and keypad digits (`Tap-Last`: the display and the key share the same text).
- Camera scan is replaced by typing the barcode in the scan field + Enter; quantities go through the on-screen keypad.
- No printer hardware: W5.2 only proves the honest "no printer" state; a real Bluetooth/network printer path is not exercised.
- The accountant `convert` and the API-level replay/DTO probes are done by the host process (real service / real HTTPS socket), not by the
  app (the app has no convert screen).
- A persona change inside one run uses Settings > Sign out on the same paired phone (the outbox survives sign-out); ~40 s each.
- UI matching is by Arabic text/index of fields (Flutter exposes no resource-ids); a UI copy change can break the driver.
