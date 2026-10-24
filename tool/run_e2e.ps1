<#
.SYNOPSIS
  يشغّل كل مجموعات اختبارات E2E بالترتيب ويطبع جدولًا نهائيًا.

.DESCRIPTION
  الترتيب: Postgres ← server ← packages ← mobile ← mobile_admin ← mobile_pos ← mobile_warehouse ← root ← web.
  أوامر flutter تُشغَّل تتابعيًا دائمًا (لا تتوازى أبدًا) وتُعاد تلقائيًا إن ظهر قفل
  الإقلاع أو انهيار نسخ native_assets الناتج عن تشغيل flutter آخر بالتوازي.
  رمز الخروج غير صفري عند فشل أي مجموعة. التفاصيل: docs/testing/E2E.md.

.PARAMETER Only
  تشغيل مجموعات محددة فقط: server, packages, mobile, mobile_admin, mobile_pos, mobile_warehouse, root, web.

.PARAMETER Skip
  استبعاد مجموعات.

.PARAMETER NoPostgres
  عدم فحص/تشغيل Postgres (تفترض أنه يعمل).

.PARAMETER SyncHelpers
  ينسخ server/test/e2e/support/e2e_cloud.dart إلى مواضع النسخ المطابقة ثم يخرج.

.EXAMPLE
  pwsh tool/run_e2e.ps1
  pwsh tool/run_e2e.ps1 -Only server,mobile
#>
[CmdletBinding()]
param(
  [string[]] $Only = @(),
  [string[]] $Skip = @(),
  [switch] $NoPostgres,
  [switch] $SyncHelpers,
  [int] $FlutterRetries = 3
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$logDir = Join-Path $root 'build\e2e_logs'
New-Item -ItemType Directory -Force $logDir | Out-Null

# ───────── نسخ المساعد المشترك (dart:io فقط) إلى حزم Flutter ─────────
$helperSrc = Join-Path $root 'server\test\e2e\support\e2e_cloud.dart'
$helperCopies = @(
  'packages\picpos_api_client\test\e2e\support\e2e_cloud.dart',
  'mobile\test\e2e\support\e2e_cloud.dart',
  'mobile_admin\test\e2e\support\e2e_cloud.dart',
  'test\e2e\support\e2e_cloud.dart'
)
if ($SyncHelpers) {
  foreach ($c in $helperCopies) { Copy-Item $helperSrc (Join-Path $root $c) -Force; "synced $c" }
  exit 0
}
# تحذير إن اختلفت النسخ عن الأصل (لا يمنع التشغيل).
foreach ($c in $helperCopies) {
  $p = Join-Path $root $c
  if ((Test-Path $p) -and ((Get-FileHash $p).Hash -ne (Get-FileHash $helperSrc).Hash)) {
    Write-Warning "$c يختلف عن server/test/e2e/support/e2e_cloud.dart — شغّل: pwsh tool/run_e2e.ps1 -SyncHelpers"
  }
}

# ───────── Postgres ─────────
function Test-Port([int] $port) {
  try {
    $c = [System.Net.Sockets.TcpClient]::new()
    $ok = $c.ConnectAsync('127.0.0.1', $port).Wait(1500)
    $c.Dispose(); return $ok
  } catch { return $false }
}

function Ensure-Postgres {
  if (Test-Port 55432) { Write-Host '[e2e] Postgres يعمل على 55432' -ForegroundColor DarkGray; return $true }
  if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { Write-Host '[e2e] docker غير موجود ولا Postgres على 55432' -ForegroundColor Red; return $false }
  Write-Host '[e2e] تشغيل Postgres: docker compose up -d postgres' -ForegroundColor Yellow
  Push-Location (Join-Path $root 'docker')
  try { docker compose up -d postgres 2>&1 | Out-Host } finally { Pop-Location }
  for ($i = 0; $i -lt 60; $i++) {
    if (Test-Port 55432) { Start-Sleep -Seconds 2; return $true }
    Start-Sleep -Seconds 1
  }
  Write-Host '[e2e] Postgres لم يستجب خلال 60 ثانية' -ForegroundColor Red
  return $false
}

# ───────── تشغيل مجموعة ─────────
$results = New-Object System.Collections.Generic.List[object]

function Invoke-Suite {
  param([string] $Name, [string] $Dir, [string] $Exe, [string[]] $CmdArgs, [bool] $IsFlutter)
  $log = Join-Path $logDir "$Name.log"
  $start = Get-Date
  $exit = 1
  $text = ''
  $attempts = if ($IsFlutter) { $FlutterRetries } else { 1 }
  for ($a = 1; $a -le $attempts; $a++) {
    Write-Host ("`n══════ [{0}] {1} {2}  (محاولة {3}/{4}) ══════" -f $Name, $Exe, ($CmdArgs -join ' '), $a, $attempts) -ForegroundColor Cyan
    Push-Location (Join-Path $root $Dir)
    try {
      & $Exe @CmdArgs 2>&1 | ForEach-Object { "$_" } | Tee-Object -FilePath $log | Out-Host
      $exit = $LASTEXITCODE
    } finally { Pop-Location }
    $text = Get-Content $log -Raw -ErrorAction SilentlyContinue
    $transient = $IsFlutter -and $exit -ne 0 -and $text -match 'PathExistsException|release the startup lock|Cannot copy file to|FileSystemException: Cannot'
    if (-not $transient) { break }
    Write-Host '[e2e] تعارض مع أمر flutter آخر — انتظار ثم إعادة...' -ForegroundColor Yellow
    Start-Sleep -Seconds (15 * $a)
  }
  # عدّادات: آخر سطر تقدّم «+N ~M -K:» (flutter و dart test كلاهما).
  $passed = 0; $skipped = 0; $failed = 0
  $m = [regex]::Matches($text, '(?m)^\s*\d\d:\d\d \+(\d+)(?: ~(\d+))?(?: -(\d+))?:')
  if ($m.Count -gt 0) {
    $last = $m[$m.Count - 1]
    $passed = [int]$last.Groups[1].Value
    if ($last.Groups[2].Success) { $skipped = [int]$last.Groups[2].Value }
    if ($last.Groups[3].Success) { $failed = [int]$last.Groups[3].Value }
  }
  $status = if ($exit -eq 0) { 'PASS' } else { 'FAIL' }
  $results.Add([pscustomobject]@{
    Suite = $Name; Status = $status; Passed = $passed; Skipped = $skipped; Failed = $failed
    Seconds = [int]((Get-Date) - $start).TotalSeconds; Log = $log
  })
}

$suites = @(
  @{ Name = 'server';       Dir = 'server';                    Exe = 'dart';    Args = @('test', '-j', '1', 'test/e2e');       Flutter = $false; NeedsPg = $true },
  @{ Name = 'packages';     Dir = 'packages\picpos_api_client'; Exe = 'dart';   Args = @('test', 'test/e2e');                  Flutter = $false; NeedsPg = $true },
  @{ Name = 'mobile';       Dir = 'mobile';                    Exe = 'flutter'; Args = @('test', 'test/e2e');                  Flutter = $true;  NeedsPg = $true },
  @{ Name = 'mobile_admin'; Dir = 'mobile_admin';              Exe = 'flutter'; Args = @('test', 'test/e2e');                  Flutter = $true;  NeedsPg = $true },
  @{ Name = 'mobile_pos';   Dir = 'mobile_pos';                Exe = 'flutter'; Args = @('test', 'test/e2e');                  Flutter = $true;  NeedsPg = $false },
  @{ Name = 'mobile_warehouse'; Dir = 'mobile_warehouse';      Exe = 'flutter'; Args = @('test', 'test/e2e');                  Flutter = $true;  NeedsPg = $false },
  @{ Name = 'root';         Dir = '.';                         Exe = 'flutter'; Args = @('test', 'test/e2e');                  Flutter = $true;  NeedsPg = $true },
  @{ Name = 'web';          Dir = '.';                         Exe = 'flutter'; Args = @('test', 'test/integration/web_client_e2e_test.dart'); Flutter = $true; NeedsPg = $false }
)
if ($Only.Count -gt 0) { $suites = $suites | Where-Object { $Only -contains $_.Name } }
if ($Skip.Count -gt 0) { $suites = $suites | Where-Object { $Skip -notcontains $_.Name } }

$pgOk = $true
if (-not $NoPostgres -and ($suites | Where-Object { $_.NeedsPg })) { $pgOk = Ensure-Postgres }

foreach ($s in $suites) {
  if ($s.NeedsPg -and -not $pgOk) {
    $results.Add([pscustomobject]@{ Suite = $s.Name; Status = 'FAIL'; Passed = 0; Skipped = 0; Failed = 0; Seconds = 0; Log = '(Postgres غير متاح)' })
    continue
  }
  Invoke-Suite -Name $s.Name -Dir $s.Dir -Exe $s.Exe -CmdArgs $s.Args -IsFlutter $s.Flutter
}

Write-Host "`n══════════════ ملخص E2E ══════════════" -ForegroundColor Green
$results | Format-Table Suite, Status, Passed, Skipped, Failed, Seconds -AutoSize | Out-Host
Write-Host ('المجموع: نجح {0} · تخطّى {1} · فشل {2}' -f ($results | Measure-Object Passed -Sum).Sum, ($results | Measure-Object Skipped -Sum).Sum, ($results | Measure-Object Failed -Sum).Sum)
Write-Host "السجلات: $logDir"
$bad = @($results | Where-Object { $_.Status -ne 'PASS' })
if ($bad.Count -gt 0) {
  Write-Host ('فشلت المجموعات: ' + (($bad | ForEach-Object Suite) -join ', ')) -ForegroundColor Red
  exit 1
}
Write-Host 'كل مجموعات E2E نجحت' -ForegroundColor Green
exit 0
