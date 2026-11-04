<#
.SYNOPSIS
  Restore a PicPos PostgreSQL dump (from backup_postgres.ps1) into a NEW database.

.DESCRIPTION
  Creates database -TargetDatabase and runs pg_restore into it. Refuses to touch
  an existing database unless -Force is given AND the operator types the database
  name to confirm (interactive). The password comes from PGPASSWORD or
  %APPDATA%\postgresql\pgpass.conf, never from the command line.
  postgres/template0/template1 can never be a target.

.PARAMETER DumpFile        Path to the .dump file.
.PARAMETER TargetDatabase  Name of the database to create and restore into.
.PARAMETER Force           Allow dropping and recreating an EXISTING target (asks to type its name).
.PARAMETER AdminDatabase   Maintenance database used to create/drop (default postgres).

.NOTES
  Exit codes: 0 ok, 1 bad arguments/aborted, 2 tool missing, 3 target exists (no -Force),
  4 create/drop failed, 5 pg_restore failed, 6 checksum mismatch.
#>
param(
  [Parameter(Mandatory)][string]$DumpFile,
  [Parameter(Mandatory)][string]$TargetDatabase,
  [string]$DbHost = 'localhost',
  [ValidateRange(1, 65535)][int]$Port = 5432,
  [string]$User = 'postgres',
  [string]$AdminDatabase = 'postgres',
  [string]$PgBin = '',
  [switch]$Force
)
$ErrorActionPreference = 'Stop'

function Die([int]$code, [string]$msg) { [Console]::Error.WriteLine($msg); exit $code }

if ($TargetDatabase -notmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}$') { Die 1 'Invalid -TargetDatabase (letters, digits, underscore).' }
if ($TargetDatabase -in 'postgres', 'template0', 'template1') { Die 1 "Refusing to restore into '$TargetDatabase'." }
if ($AdminDatabase -notmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}$') { Die 1 'Invalid -AdminDatabase.' }
if (-not (Test-Path -LiteralPath $DumpFile -PathType Leaf)) { Die 1 "Dump file not found: $DumpFile" }

function Find-PgTool([string]$name) {
  $candidates = @()
  if ($PgBin) { $candidates += (Join-Path $PgBin "$name.exe") }
  $root = Join-Path ${env:ProgramFiles} 'PostgreSQL'
  if (Test-Path $root) {
    $candidates += Get-ChildItem $root -Directory -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -match '^\d+(\.\d+)*$' } |
      Sort-Object { [version]($_.Name -replace '^(\d+)$', '$1.0') } -Descending |
      ForEach-Object { Join-Path $_.FullName "bin\$name.exe" }
  }
  foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
  $cmd = Get-Command $name -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return $null
}
$psql = Find-PgTool 'psql'
$pgRestore = Find-PgTool 'pg_restore'
if (-not $psql -or -not $pgRestore) { Die 2 'psql / pg_restore not found. Install PostgreSQL client tools or pass -PgBin.' }

$sumFile = "$DumpFile.sha256"
if (Test-Path -LiteralPath $sumFile) {
  $want = (Get-Content -LiteralPath $sumFile -Raw).Trim()
  $got = (Get-FileHash -Algorithm SHA256 -LiteralPath $DumpFile).Hash
  if ($want -ne $got) { Die 6 'SHA-256 mismatch: the dump is corrupt or modified.' }
}

$conn = @('--host', $DbHost, '--port', $Port, '--username', $User, '--no-password')
$ErrorActionPreference = 'Continue'
$exists = & $psql @conn --dbname $AdminDatabase -v ON_ERROR_STOP=1 -tAc "SELECT 1 FROM pg_database WHERE datname='$TargetDatabase'"
if ($LASTEXITCODE -ne 0) { Die 4 'Cannot query the server (check host/port/user/password).' }
$exists = ("$exists").Trim() -eq '1'

if ($exists) {
  if (-not $Force) { Die 3 "Database '$TargetDatabase' already exists. Choose a new name (or -Force to drop and recreate it)." }
  $typed = Read-Host "DESTRUCTIVE: database '$TargetDatabase' will be DROPPED. Type its name to confirm"
  if ($typed -ne $TargetDatabase) { Die 1 'Confirmation mismatch; aborted. Nothing was changed.' }
  & $psql @conn --dbname $AdminDatabase -v ON_ERROR_STOP=1 -c "DROP DATABASE `"$TargetDatabase`" WITH (FORCE)"
  if ($LASTEXITCODE -ne 0) { Die 4 'DROP DATABASE failed.' }
}
& $psql @conn --dbname $AdminDatabase -v ON_ERROR_STOP=1 -c "CREATE DATABASE `"$TargetDatabase`""
if ($LASTEXITCODE -ne 0) { Die 4 'CREATE DATABASE failed.' }

& $pgRestore @conn --dbname $TargetDatabase --no-owner --exit-on-error $DumpFile
if ($LASTEXITCODE -ne 0) { Die 5 "pg_restore failed (exit $LASTEXITCODE). The partially restored database '$TargetDatabase' was left for inspection." }
Write-Host "OK: restored $DumpFile into '$TargetDatabase'."
exit 0
