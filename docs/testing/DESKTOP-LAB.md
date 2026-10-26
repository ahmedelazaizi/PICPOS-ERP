# Desktop lab — testing the Windows app without touching real data

## `PICPOS_DATA_DIR`

Set the environment variable `PICPOS_DATA_DIR` to an **absolute** directory and
the app keeps *every* persistent file there. Unset = the shipped behaviour,
byte for byte (Documents folder, `%APPDATA%`). A relative value is rejected with
a `StateError` (it never silently falls back to real data).

```powershell
$env:PICPOS_DATA_DIR = 'D:\qa\desktop-lab\run-1\data'
Start-Process build\windows\x64\runner\Release\PicPos.exe
```

| What | Where (override set) | Default |
|---|---|---|
| database `picpos_unified.db*`, `.keyinfo.json`, key-migration lock | `<dir>\` | Documents |
| logs (`picpos_startup_log.txt`, login log, diagnostic log, API error log) | `<dir>\` | Documents |
| backups (`backups\`, auto/manual/pre-migration), exports | `<dir>\` | Documents |
| client backups of the API (`…/<backupFolderName>/clients`) | `<dir>\appdata\` | `%APPDATA%` |
| SharedPreferences (device-local settings, pairing, mode cache) | `<dir>\support\shared_preferences.json` | `%APPDATA%\PicPos\PicPos\shared_preferences.json` |
| secure storage (PG password, LAN TLS cert/key, device tokens, remote-backup secrets) | `<dir>\support\secure_storage.json` (**plain text — lab only**) | Windows credential file under `%APPDATA%` |

Code: `lib/core/config/data_dir.dart` (paths) and
`lib/core/config/data_dir_plugins.dart` (redirects the two plugins whose
Windows implementations hard-code `%APPDATA%`; installed first thing in
`main()`, a no-op when the variable is unset).

Guards: `test/unit/config/data_dir_test.dart` enumerates the resolved locations
with and without the override; `test/static/data_dir_guard_test.dart` fails when
any file under `lib/` other than `data_dir.dart` imports `path_provider` or calls
a `getApplication*Directory` / temp / downloads API. Use `DataDir.documents()` /
`DataDir.support()` / `DataDir.roamingAppData()`.

Not redirected (user-chosen export destinations, not app data): the
`%USERPROFILE%\Desktop` fallbacks of the scale/PLU/activity-log exports and the
`TEMP` fallback of the startup log. The startup log is also written next to the
exe (build dir) by design.

## Desktop smoke (`D:\qa\desktop-lab\smoke.ps1`)

Starts the exe with an empty isolated data dir, takes a `PrintWindow` screenshot,
keeps it alive N seconds, closes it, then diffs a before/after metadata snapshot of
`C:\Users\Dell\Documents` and `%APPDATA%\PicPos*` (must be zero changes) and greps
the logs for `RECONCILE-OK`. The app ignores `CloseMainWindow` (tray/close
guard), so the script force-stops **its own** pid after 15 s.

## Installer lab

The shipped `installer\setup_picpos.iss` needs admin (`PrivilegesRequired=admin`)
and its pre-upgrade backup reads and writes `{userdocs}` (real Documents) — so it
must not be run on a machine holding owner data. `D:\qa\desktop-lab\make-lab-installers.ps1`
compiles *copies* with four differences only: other AppId, `PrivilegesRequired=lowest`,
output dir, and `{userdocs}` → `%PICPOS_LAB_DOCS%` in `preupgrade_backup.isi`.
Run them with `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CURRENTUSER /DIR=… /LOG=… /COMPONENTS=app`
(`/COMPONENTS=app` is essential: the default silent type includes the 374 MB PostgreSQL download).

## PostgreSQL HQ test

`test/integration_pg/first_run_hq_pg_test.dart`, run with a throwaway container:

```powershell
$n = "picpos-lab-pg-$(Get-Random)"; docker run -d --rm --name $n -e POSTGRES_PASSWORD=postgres -p 0:5432 postgres:16-alpine
$port = (docker port $n 5432/tcp | Select -First 1).Split(':')[-1]
$env:PG_TEST_DSN = "postgres://postgres:postgres@localhost:$port/postgres"
flutter test test/integration_pg/first_run_hq_pg_test.dart --tags pg --run-skipped
docker rm -f $n
```

(or `dart run scripts/run_pg_tests.dart`, which does the same for the whole folder).
