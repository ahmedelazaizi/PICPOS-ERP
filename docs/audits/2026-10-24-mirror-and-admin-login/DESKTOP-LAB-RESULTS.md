# Desktop lab results (2026-10-26)

Branch `feat/tables-reservations-permissions` @ 565e2d52 + uncommitted work. Evidence under `D:\qa\desktop-lab\`.
Real data (`C:\Users\Dell\Documents`, `%APPDATA%\PicPos*`) was never opened by the app or an installer; before/after metadata diff = **0 changes** on every run.

| # | Item | Status |
|---|---|---|
| 1 | `PICPOS_DATA_DIR` isolation | **Done** |
| 2 | Desktop smoke, isolated | **Done** (graceful close not possible, see below) |
| 3 | Installer, install/upgrade/uninstall | **Partial** — lab copies of the script, not the shipped exe |
| 4 | PostgreSQL HQ first-run on live PG | **Done**, 5/5 pass, no product bug found in the HQ path |
| 5 | GUI check of offline-login tile / banner | **Not driven end to end** |

## 1. Data-dir isolation
- New: `lib/core/config/data_dir.dart` (2.9 KB), `lib/core/config/data_dir_plugins.dart` (3.4 KB: file-backed SharedPreferences + secure storage when the variable is set; the Windows plugins hard-code `%APPDATA%`, so the path_provider override alone would not have been enough).
- 15 call sites routed (backup_service, diagnostic_logger, excel_export_helper, log_writer_io, first_run_storage_probe, connection_io ×6, database_startup, db_key_startup, main.dart, settings_picpos_about, settings_screen, stock_movements_screen, api_server_error_log, api_data_system `%APPDATA%`). `main()` gets one line `installDataDirPluginRedirects();`.
- `pubspec.yaml`: `shared_preferences_platform_interface` and `flutter_secure_storage_platform_interface` declared as direct deps (already in the lock; `pubspec.lock` gets 2 lines).
- Tests: `test/unit/config/data_dir_test.dart` (6), `test/static/data_dir_guard_test.dart` (2). Docs: `docs/testing/DESKTOP-LAB.md`.
- Ratchet headroom (bytes, LF): main.dart 72134 / 74674; connection_io.dart 31888 / 31987; database.dart 40448 / 40457; settings_screen.dart 62764 / 62826; settings_picpos_screen.dart 26786 (unlisted, < 30 KB). No ratcheted file grew.
- Not redirected (documented): Desktop-folder export fallbacks, TEMP fallback of the startup log; startup log is also written beside the exe by design.

## 2. Desktop smoke
Build: `build_picpos.bat` failed three times on others' in-flight edits / the sqlite3.dll `PathExistsException` collision in its brand-test step; built with a copy of the script minus that step (`build_nobrandtest.bat`), everything else identical → SUCCESS, SQLCipher dll verified by the script. (The brand test itself passed when run alone.)
- `smoke1-*`: empty data dir, alive 40 s, `RECONCILE-OK fresh install` in `picpos_login_log_standalone.txt`; files created in the data dir only: db, keyinfo, WAL/SHM, `backups\` (auto-backup at start), logs, `support\secure_storage.json`.
- `smoke2-*` screenshot `window.png`: first-run setup wizard (step 1/6 "طريقة التشغيل") for the empty data dir; a second launch on the same dir (restart) gave the same state and `RECONCILE-OK`.
- Close: the window ignores `CloseMainWindow` for 15 s, the script then force-stops its own pid. Graceful exit was therefore **not** demonstrated.
- The first attempt's screenshot (`CopyFromScreen`) captured another window (the desktop, not the app) and was deleted; `PrintWindow` is used since.
- Startup log text is mojibake when read as ANSI (UTF-8 emoji/box chars) — cosmetic, not changed.

## 3. Installer
Why not the shipped `PicPos-Setup-3.9.2.277.exe`: `PrivilegesRequired=admin` (this session is not elevated, no UAC possible) and `preupgrade_backup.isi` copies `{userdocs}\picpos_*.db` into `{userdocs}\backups\pre-upgrade` — it would read and write the owner's real Documents. So lab copies were compiled (`make-lab-installers.ps1`): different AppId, `PrivilegesRequired=lowest`, `{userdocs}`→`%PICPOS_LAB_DOCS%` (fake-docs dir). Everything else is the repo script (files, icons, uninstaller, backup logic, version handling).
- Install 3.9.2.276 to `D:\qa\desktop-lab\install-test\` (`/VERYSILENT /CURRENTUSER /COMPONENTS=app /MERGETASKS=desktopicon`): exit 0, 66 files, `PicPos.exe` + `unins000.exe`, HKCU uninstall key (DisplayVersion 3.9.2.276, Publisher PicPos), Desktop and Start-menu shortcuts (+ uninstall shortcut).
- Ran that install with `PICPOS_DATA_DIR` → data created; copied the db into fake-docs; installed 3.9.2.277 over it: exit 0, DisplayVersion 3.9.2.277, **pre-upgrade backup created** (`picpos_unified_preupgrade_<stamp>.db` + `-wal`, sizes equal to the source), data dir db hash unchanged by the installer, second app run OK (`RECONCILE-OK`).
- Uninstall (`unins000.exe /VERYSILENT`): exit 0, install dir gone, registry key gone, both shortcuts gone, backups in fake-docs kept.
- **Not tested**: the shipped exe and the admin (HKLM / Program Files) path; a real *schema* migration across versions (both lab installers carry the same build; the app's own migration was not exercised); `/COMPONENTS` default (would download PostgreSQL 374 MB); VC++ redist branch (already installed here).
- Observation: the install log notes "Deleting uninstall key left over from previous non administrative install" on the upgrade — normal Inno housekeeping.

## 4. PostgreSQL HQ (live postgres:16-alpine, random port, removed afterwards)
`test/integration_pg/first_run_hq_pg_test.dart` (5 tests): `flutter test test/integration_pg/first_run_hq_pg_test.dart --tags pg --run-skipped` with `PG_TEST_DSN` set as `scripts/run_pg_tests.dart` does → **All tests passed** (01:24).
Covers: seeded `admin/admin` present on a fresh PG; `ServerSetupWriter.write` + `armPostgresMode` → record in PG (mode=server, port 8099, pgConfigured, selfCheckPending, setupCompletedAt), derived keys, `setup_completed` committed in the final transaction (proved with `xmin` ordering of the settings rows), admin password replaced (`admin/admin` dead, new password works, `retireSeededAdmin` = false), HQ user created with force-change; local `ModeActivator.commit(server)` → `CommitOk`; restart on a new `AppDatabase` → `ProvisioningApplier.ensure` no backfill, no repairs, gate = selfCheck, `reconcileWithDb` → server, `SelfCheckRunner` all pass, then gate = ready; a backfill-shaped record without `pgConfigured` fails the HQ self-check (blocking); second finish is idempotent (0 created / 1 updated user, row counts equal, first completion stamp kept).
Observation (not fixed, non-fatal, pre-existing): opening a second `AppDatabase` on an already seeded PG logs `23505 role_permissions_pkey` for the journal-approval / return-approve / HR attendance / HR payroll permission backfills (`lib/data/database/database_startup.dart:1351` and siblings) — the inserts are not idempotent on PG; each is caught and logged.

## 5. GUI check of offline-login tile / banner
Not driven in the real app (no reliable UI automation for the Flutter surface). Existing widget tests pass (`test/widget/settings/offline_login_enforce_widgets_test.dart`, 37 pass in that run) but they pin a single 900×900 surface; no goldens at real desktop sizes were added in the time available.

## Commands run
- `dart analyze lib test`: no errors; 10 infos, all in others' files except my 2 which I then fixed (re-analysed that file: clean). The 2 "known" infos are among the 8 remaining others' infos (legacy_token_section, lan_device_route_policy, pos_device_pairing_test, apk_scan_test, purchase/sales returns).
- `flutter test test/structural/file_size_ratchet_test.dart test/structural/i18n_coverage_test.dart test/structural/brand_artifact_guard_test.dart test/static test/unit/deployment test/unit/config/data_dir_test.dart` → 206 passed.
- Not run: whole desktop suites (lead runs them); the mobile packages.

## Files
New: `lib/core/config/data_dir.dart`, `lib/core/config/data_dir_plugins.dart`, `test/unit/config/data_dir_test.dart`, `test/static/data_dir_guard_test.dart`, `test/integration_pg/first_run_hq_pg_test.dart`, `docs/testing/DESKTOP-LAB.md`, this file. Edited: the 15 call-site files above, `lib/services/api/api_data_handler.dart` (one import), `lib/data/database/database.dart` (import), `pubspec.yaml`, `pubspec.lock`. `assets/i18n/en.json` was not touched by me. Lab scripts live outside the repo in `D:\qa\desktop-lab\`.
