# PostgreSQL mode — backup and restore (operator runbook)

**Audit B BKP-004.** In PostgreSQL server mode the application has **no in-app
backup**: the backup button and the automatic startup backup only cover the
local SQLCipher/SQLite file. Backing up the PostgreSQL server is the
**operator's responsibility**, and this is the supported way to do it.

## Backup

```powershell
$env:PGPASSWORD = '<password>'   # or a pgpass.conf entry; never on the command line
powershell -File scripts\backup_postgres.ps1 -Database picpos -OutDir D:\pg-backups -KeepDays 14
```

[`scripts/backup_postgres.ps1`](../../scripts/backup_postgres.ps1) takes a custom-format `pg_dump`,
verifies it with `pg_restore --list`, writes a `.sha256` and prunes dumps older than `-KeepDays`.
Exit codes: `0` ok · `2` tools missing · `3` dump failed · `4` verification failed.

* Schedule it at least **daily** (Windows Task Scheduler / cron) and alert on a non-zero exit code.
* Copy `OutDir` **off the server** (second disk, NAS, cloud). A dump on the same disk is not a backup.
* Dumps are **not encrypted** by the script — protect the folder (NTFS ACL) or encrypt the volume.
* Keep one dump from before every application upgrade.

## Restore drill (do it once per quarter, on a throw-away server)

```bash
createdb -U postgres picpos_restore_test
pg_restore --no-owner --dbname picpos_restore_test D:\pg-backups\picpos_pg_<stamp>.dump
```

Then start a **test** copy of the app against `picpos_restore_test`, log in and check: trial balance is
balanced, party balances equal the ledger (reconciliation screen), and the latest invoice is present.
A backup that was never restored is unproven.

## What the in-app backup still does in PG mode

Nothing for the server data. The local SQLite file (settings of this PC, offline fallback) is still
backed up by the app as usual.
