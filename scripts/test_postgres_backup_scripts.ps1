# Offline tests (no PostgreSQL needed): syntax parse, retention logic, -WhatIf.
# Run: powershell -NoProfile -File scripts\test_postgres_backup_scripts.ps1
$ErrorActionPreference = 'Stop'
$scripts = $PSScriptRoot
$fail = 0
function Check([string]$name, [bool]$ok) { if ($ok) { Write-Host "PASS $name" } else { Write-Host "FAIL $name"; $script:fail++ } }

foreach ($n in 'backup_postgres', 'restore_postgres', 'register_postgres_backup_task') {
  $errs = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile("$scripts\$n.ps1", [ref]$null, [ref]$errs)
  Check "parse $n" ($errs.Count -eq 0)
}

# Retention: 20 consecutive days (one dump/day, plus a second older-in-day one) + other db file.
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("pgret_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $tmp | Out-Null
try {
  $base = [datetime]'2026-06-30'
  for ($i = 0; $i -lt 60; $i++) {
    $d = $base.AddDays(-$i)
    foreach ($t in '010000', '230000') {
      $f = "$tmp\db1_$($d.ToString('yyyyMMdd'))_$t.dump"
      'x' | Set-Content $f; 'h' | Set-Content "$f.sha256"
    }
  }
  'x' | Set-Content "$tmp\other_20200101_000000.dump"
  & powershell -NoProfile -File "$scripts\backup_postgres.ps1" -Database db1 -OutDir $tmp -PruneOnly -KeepDaily 14 -KeepWeekly 8 | Out-Null
  Check 'prune exit 0' ($LASTEXITCODE -eq 0)
  $left = @(Get-ChildItem $tmp -Filter 'db1_*.dump')
  $days = @($left | ForEach-Object { $_.Name.Substring(4, 8) } | Sort-Object -Unique)
  Check 'only newest dump of each day kept' (@($left | Where-Object Name -like '*_010000.dump').Count -eq 0)
  Check 'last 14 days all present' ((0..13 | Where-Object { Test-Path "$tmp\db1_$($base.AddDays(-$_).ToString('yyyyMMdd'))_230000.dump" }).Count -eq 14)
  Check '14 daily + 5 extra weekly = 19 kept' ($left.Count -eq 19)
  Check 'old (60d) removed' (-not (Test-Path "$tmp\db1_$($base.AddDays(-59).ToString('yyyyMMdd'))_230000.dump"))
  Check 'sha256 sidecar of removed dump removed' (-not (Test-Path "$tmp\db1_$($base.AddDays(-59).ToString('yyyyMMdd'))_230000.dump.sha256"))
  Check 'other database untouched' (Test-Path "$tmp\other_20200101_000000.dump")
  Check 'log written without PGPASSWORD' ((Test-Path "$tmp\backup.log") -and -not ((Get-Content "$tmp\backup.log" -Raw) -match 'PGPASSWORD='))
  Write-Host ("kept {0} dumps over {1} days" -f $left.Count, $days.Count)

  # unreachable server (port 1, nothing listens) -> must exit non-zero
  $ErrorActionPreference = 'Continue'
  & powershell -NoProfile -File "$scripts\backup_postgres.ps1" -Database db1 -DbHost 127.0.0.1 -Port 1 -OutDir $tmp 2>$null | Out-Null
  $rc = $LASTEXITCODE; $ErrorActionPreference = 'Stop'
  Check 'backup exits non-zero when pg_dump cannot connect' ($rc -ne 0)
}
finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }

$out = & powershell -NoProfile -File "$scripts\register_postgres_backup_task.ps1" -WhatIf 2>&1 | Out-String
Check 'register -WhatIf mentions 02:30' ($out -match '02:30' -and $LASTEXITCODE -eq 0)
Check 'register: task not created' (-not (Get-ScheduledTask -TaskName 'PicPos PostgreSQL Backup' -ErrorAction SilentlyContinue))
if ($fail) { Write-Host "$fail FAILED"; exit 1 } else { Write-Host 'ALL PASSED'; exit 0 }


