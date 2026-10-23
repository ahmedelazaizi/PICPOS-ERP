<#
.SYNOPSIS
  Operator backup of the PicPos PostgreSQL database (BKP-004).

.DESCRIPTION
  In PostgreSQL server mode the app has NO in-app backup (the SQLCipher backup
  button only covers the local SQLite file). This script is the supported
  backup: it takes a custom-format `pg_dump`, verifies it is readable with
  `pg_restore --list`, writes a SHA-256 next to it and prunes old dumps.

  Schedule it (Task Scheduler / cron) at least daily and copy the output folder
  OFF the server (second disk, NAS, cloud). A backup on the same disk is not a
  backup. Details and the restore drill: docs/ops/POSTGRES-BACKUP.md.

  The password is never taken on the command line: use the PGPASSWORD
  environment variable, a ~/.pgpass (pgpass.conf on Windows) entry, or a
  service account with peer/SSPI auth.

.PARAMETER Database   Database name (default picpos).
.PARAMETER DbHost     Server host (default localhost).
.PARAMETER Port       Server port (default 5432).
.PARAMETER User       Role used for the dump (default postgres).
.PARAMETER OutDir     Destination folder (default .\pg-backups).
.PARAMETER KeepDays   Delete dumps older than this many days (default 14, min 1).
.PARAMETER PgBin      Folder containing pg_dump/pg_restore if not on PATH.

.EXAMPLE
  $env:PGPASSWORD = '...'; powershell -File scripts\backup_postgres.ps1 -Database picpos -OutDir D:\pg-backups

.NOTES
  Exit codes: 0 ok, 2 tool missing, 3 pg_dump failed, 4 verification failed.
#>
param(
  [string]$Database = 'picpos',
  [string]$DbHost = 'localhost',
  [int]$Port = 5432,
  [string]$User = 'postgres',
  [string]$OutDir = (Join-Path (Get-Location) 'pg-backups'),
  [ValidateRange(1, 3650)][int]$KeepDays = 14,
  [string]$PgBin = ''
)
$ErrorActionPreference = 'Stop'

function Find-Tool([string]$name) {
  if ($PgBin) {
    $c = Join-Path $PgBin "$name.exe"
    if (Test-Path $c) { return $c }
    $c = Join-Path $PgBin $name
    if (Test-Path $c) { return $c }
  }
  $cmd = Get-Command $name -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return $null
}

$pgDump = Find-Tool 'pg_dump'
$pgRestore = Find-Tool 'pg_restore'
if (-not $pgDump -or -not $pgRestore) {
  [Console]::Error.WriteLine('pg_dump / pg_restore not found. Install the PostgreSQL client tools or pass -PgBin.')
  exit 2
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$stamp = Get-Date -Format 'yyyy-MM-ddTHH-mm-ss'
$file = Join-Path $OutDir "$Database`_pg_$stamp.dump"

& $pgDump --host $DbHost --port $Port --username $User --format=custom --no-password `
  --file $file $Database
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $file) -or (Get-Item $file).Length -eq 0) {
  if (Test-Path $file) { Remove-Item $file -Force }
  [Console]::Error.WriteLine("pg_dump failed (exit $LASTEXITCODE).")
  exit 3
}

# A dump that cannot be listed cannot be restored: verify before trusting it.
& $pgRestore --list $file *> $null
if ($LASTEXITCODE -ne 0) {
  [Console]::Error.WriteLine("Verification failed: pg_restore --list cannot read $file")
  exit 4
}
(Get-FileHash -Algorithm SHA256 $file).Hash | Set-Content -Path "$file.sha256" -Encoding ascii

# Retention: only this database's dumps, only after the new one is verified.
Get-ChildItem $OutDir -Filter "$Database`_pg_*.dump" |
  Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$KeepDays) } |
  ForEach-Object { Remove-Item $_.FullName -Force; Remove-Item "$($_.FullName).sha256" -Force -ErrorAction SilentlyContinue }

Write-Host "OK: $file ($([math]::Round((Get-Item $file).Length / 1MB, 2)) MB)"
exit 0
