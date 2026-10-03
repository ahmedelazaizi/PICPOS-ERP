# Fails (exit 1) if a signing or Firebase secret is tracked by git
# (ARCHITECTURE-M §4.3): *.jks, *.keystore, key.properties,
# google-services.json, and Firebase service-account JSON files.
# Usage (repo root or anywhere inside it):  powershell -File tool/check_no_secrets.ps1
# CI runs it before building the mobile APKs/AABs.
$ErrorActionPreference = 'Stop'
$root = (& git rev-parse --show-toplevel).Trim()
if ($LASTEXITCODE -ne 0) { Write-Error 'not a git repository'; exit 2 }

$tracked = & git -C $root ls-files
$pattern = '(^|/)(key\.properties|google-services\.json|[^/]*firebase-adminsdk[^/]*\.json)$|\.(jks|keystore)$'
$hits = @($tracked | Where-Object { $_ -match $pattern })

if ($hits.Count -gt 0) {
  Write-Host 'FAIL: secret files are tracked by git (remove with `git rm --cached` and rotate the secret):' -ForegroundColor Red
  $hits | ForEach-Object { Write-Host "  $_" }
  exit 1
}

# The ignore rules must also cover the mobile apps' signing files.
$probe = @('mobile_admin/android/key.properties', 'mobile_pos/android/key.properties',
           'mobile_admin/android/app/upload.jks', 'mobile_pos/android/app/google-services.json')
$notIgnored = @()
foreach ($p in $probe) {
  & git -C $root check-ignore -q $p
  if ($LASTEXITCODE -ne 0) { $notIgnored += $p }
}
if ($notIgnored.Count -gt 0) {
  Write-Host 'FAIL: these secret paths are not git-ignored:' -ForegroundColor Red
  $notIgnored | ForEach-Object { Write-Host "  $_" }
  exit 1
}

Write-Host "PASS: no keystore / key.properties / google-services.json tracked ($($tracked.Count) tracked files checked)."
exit 0
