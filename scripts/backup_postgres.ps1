<#
.SYNOPSIS
  Operator backup of the PicPos PostgreSQL database (BKP-004).

.DESCRIPTION
  In PostgreSQL server mode the app has NO in-app backup (the SQLCipher backup
  button only covers the local SQLite file). This script is the supported
  backup: a compressed custom-format `pg_dump` (-Fc), written to
  <OutDir>\<db>_yyyyMMdd_HHmmss.dump, verified (non-empty + `pg_restore --list`),
  with a SHA-256 sidecar, a secret-free log (backup.log) and daily/weekly retention.

  The password is NEVER taken on the command line and never logged: use the
  PGPASSWORD environment variable or %APPDATA%\postgresql\pgpass.conf.

  pg_dump/pg_restore are looked up in: -PgBin, then the newest
  C:\Program Files\PostgreSQL\<ver>\bin, then PATH.

  Retention (by the timestamp in the file name, only this database's dumps):
  keep the newest dump of each of the last -KeepDaily days that have a dump,
  plus the newest dump of each of the last -KeepWeekly (Mon-Sun) weeks that
  have a dump. Everything else (and its .sha256) is deleted, only after the
  new dump verified OK.

.PARAMETER Database   Database name (default picpos).
.PARAMETER DbHost     Server host (default localhost).
.PARAMETER Port       Server port (default 5432).
.PARAMETER User       Role used for the dump (default postgres).
.PARAMETER OutDir     Destination folder (default <repo>\backups\postgres).
.PARAMETER KeepDaily  Number of daily dumps to keep (default 14; legacy alias KeepDays).
.PARAMETER KeepWeekly Number of weekly dumps to keep (default 8).
.PARAMETER PgBin      Folder containing pg_dump/pg_restore (overrides discovery).
.PARAMETER PruneOnly  Skip the dump; only apply retention to OutDir (used by tests).

.EXAMPLE
  $env:PGPASSWORD = '...'; powershell -File scripts\backup_postgres.ps1 -Database picpos

.NOTES
  Exit codes: 0 ok, 1 bad arguments, 2 tool missing, 3 pg_dump failed,
  4 verification failed, 5 retention failed (dump itself is fine).
#>
param(
  [string]$Database = 'picpos',
  [string]$DbHost = 'localhost',
  [ValidateRange(1, 65535)][int]$Port = 5432,
  [string]$User = 'postgres',
  [string]$OutDir = '',
  [Alias('KeepDays')][ValidateRange(0, 3650)][int]$KeepDaily = 14,
  [ValidateRange(0, 520)][int]$KeepWeekly = 8,
  [string]$PgBin = '',
  [switch]$PruneOnly
)
$ErrorActionPreference = 'Stop'

if (-not $OutDir) { $OutDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'backups\postgres' }
if ($Database -notmatch '^[A-Za-z_][A-Za-z0-9_\-]{0,62}$') {
  [Console]::Error.WriteLine('Invalid -Database name.'); exit 1
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$LogFile = Join-Path $OutDir 'backup.log'

function Write-Log([string]$level, [string]$msg) {
  $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $level, $msg
  Add-Content -Path $LogFile -Value $line -Encoding UTF8
  if ($level -eq 'ERROR') { [Console]::Error.WriteLine($line) } else { Write-Host $line }
}
function Fail([int]$code, [string]$msg) { Write-Log 'ERROR' $msg; exit $code }

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

function Invoke-Retention([string]$dir, [string]$db, [int]$daily, [int]$weekly) {
  $rx = '^' + [regex]::Escape($db) + '_(\d{8})_(\d{6})\.dump$'
  $items = foreach ($f in Get-ChildItem $dir -File -Filter "$db`_*.dump") {
    if ($f.Name -match $rx) {
      $ts = [datetime]::ParseExact($Matches[1] + $Matches[2], 'yyyyMMddHHmmss', [Globalization.CultureInfo]::InvariantCulture)
      $weekStart = $ts.Date.AddDays(-(([int]$ts.DayOfWeek + 6) % 7))
      [pscustomobject]@{ File = $f; Ts = $ts; Day = $ts.Date; Week = $weekStart }
    }
  }
  $items = @($items)
  $keep = @{}
  if ($daily -gt 0) {
    $items | Group-Object Day | Sort-Object { $_.Group[0].Day } -Descending | Select-Object -First $daily |
      ForEach-Object { $keep[($_.Group | Sort-Object Ts -Descending | Select-Object -First 1).File.FullName] = $true }
  }
  if ($weekly -gt 0) {
    $items | Group-Object Week | Sort-Object { $_.Group[0].Week } -Descending | Select-Object -First $weekly |
      ForEach-Object { $keep[($_.Group | Sort-Object Ts -Descending | Select-Object -First 1).File.FullName] = $true }
  }
  $removed = 0
  foreach ($i in $items) {
    if (-not $keep.ContainsKey($i.File.FullName)) {
      Remove-Item $i.File.FullName -Force
      Remove-Item "$($i.File.FullName).sha256" -Force -ErrorAction SilentlyContinue
      Write-Log 'INFO' "Retention removed $($i.File.Name)"
      $removed++
    }
  }
  Write-Log 'INFO' "Retention: kept $($keep.Count), removed $removed (daily=$daily weekly=$weekly)"
}

if ($PruneOnly) {
  try { Invoke-Retention $OutDir $Database $KeepDaily $KeepWeekly; exit 0 }
  catch { Fail 5 "Retention failed: $($_.Exception.Message)" }
}

$pgDump = Find-PgTool 'pg_dump'
$pgRestore = Find-PgTool 'pg_restore'
if (-not $pgDump -or -not $pgRestore) {
  Fail 2 'pg_dump / pg_restore not found. Install PostgreSQL client tools or pass -PgBin.'
}
$pgpass = Join-Path ([string]$env:APPDATA) 'postgresql\pgpass.conf'
if (-not $env:PGPASSWORD -and -not (Test-Path $pgpass)) {
  Write-Log 'WARN' 'Neither PGPASSWORD nor pgpass.conf found; relying on trust/SSPI auth.'
}
Write-Log 'INFO' "Start backup db=$Database host=$DbHost port=$Port user=$User tool=$pgDump"

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$final = Join-Path $OutDir "$Database`_$stamp.dump"
$part = "$final.partial"
$errFile = Join-Path ([IO.Path]::GetTempPath()) ("pgbk_" + [guid]::NewGuid().ToString('N') + '.err')

try {
  $ErrorActionPreference = 'Continue'
  & $pgDump --host $DbHost --port $Port --username $User --format=custom --compress=6 --no-password `
    --file $part $Database 2> $errFile
  $code = $LASTEXITCODE
  $ErrorActionPreference = 'Stop'
  $errText = if (Test-Path $errFile) { (Get-Content $errFile -Raw) } else { '' }
  if ($code -ne 0 -or -not (Test-Path $part) -or (Get-Item $part).Length -eq 0) {
    if (Test-Path $part) { Remove-Item $part -Force }
    Fail 3 "pg_dump failed (exit $code). $($errText.Trim())"
  }

  $ErrorActionPreference = 'Continue'
  & $pgRestore --list $part > $null 2> $errFile
  $code = $LASTEXITCODE
  $ErrorActionPreference = 'Stop'
  if ($code -ne 0) {
    $errText = (Get-Content $errFile -Raw)
    Remove-Item $part -Force
    Fail 4 "Verification failed: pg_restore --list exit $code. $($errText.Trim())"
  }
  Move-Item $part $final -Force
  (Get-FileHash -Algorithm SHA256 $final).Hash | Set-Content -Path "$final.sha256" -Encoding ascii
  $mb = [math]::Round((Get-Item $final).Length / 1MB, 2)
  Write-Log 'INFO' "OK $final ($mb MB) verified with pg_restore --list"
}
finally {
  Remove-Item $errFile -Force -ErrorAction SilentlyContinue
}

try { Invoke-Retention $OutDir $Database $KeepDaily $KeepWeekly }
catch { Fail 5 "Retention failed: $($_.Exception.Message)" }
exit 0
