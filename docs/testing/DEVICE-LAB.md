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
- Release APKs copied to `D:\qa\device-lab\apks\` as `warehouse.apk`, `pos.apk`, `admin.apk`, `van.apk`
  (copy from `<app>\build\app\outputs\flutter-apk\app-release.apk`; the lab never runs `flutter build`).
- Ports 18443 (HTTPS host) and 18080 (plain-HTTP decoy) free.
- Only `emulator-5554` is ever touched (`LAB_SERIAL` overrides); other adb devices are ignored.

## Run

```powershell
powershell -ExecutionPolicy Bypass -File tool\device_lab\run_lab.ps1            # host from the working tree
powershell -ExecutionPolicy Bypass -File tool\device_lab\run_lab.ps1 -Snapshot  # host from `git archive HEAD` in D:\qa\device-lab\src
                                                                                 #   (use when lib/ is mid-edit and does not compile)
# options: -SkipHostStart (a host is already running)  -KeepEmulator  -HostMinutes 45  -RunId x
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

## Limits

- No camera/QR scan, no Arabic typing, no Bluetooth/printer/scale hardware, no real Wi-Fi radio (emulated NAT).
- The Van app pairs with the cloud server (`/mobile/pair`), not the LAN host; here it is a launch smoke test only.
- The desktop Windows app is **not** launched: it has no data-directory switch (DB path is
  `getApplicationDocumentsDirectory()`, prefs in `%APPDATA%`, secrets in Credential Manager), so a smoke launch would touch the
  owner's real data (`C:\Users\Dell\Documents\picpos_unified.db*`). It needs a throwaway Windows user/VM or a
  `PICPOS_DATA_DIR` product override first.
- The offline check is for the warehouse app, which has no dedicated "offline" banner (see results).
- UI matching is by Arabic text/index of fields (Flutter exposes no resource-ids); a UI copy change can break the driver.
