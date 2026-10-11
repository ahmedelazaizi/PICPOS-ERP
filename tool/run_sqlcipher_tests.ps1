<#
.SYNOPSIS
  يشغّل اختبارات flutter على محرّك SQLCipher الحقيقيّ بدل sqlite3 العاديّة.

.DESCRIPTION
  flutter test يحمّل sqlite3.dll العاديّة التي يُنزلها hook الحزمة sqlite3 إلى
  .dart_tool\hooks_runner\shared\sqlite3\build\download-*\sqlite3.dll
  (والمسارُ المستعمَل مسجَّلٌ في .dart_tool\hooks_runner\sqlite3\*\output.json).
  لا يوجد في sqlite3 3.x مفتاحُ DynamicLibrary.overrideFor ولا متغيّر بيئة، فيستبدل
  هذا السكربتُ تلك الملفات مؤقّتًا بـ SQLCipher DLL ثم يعيد الأصل في finally
  (وعند التشغيل التالي إن قُتل السكربت: ملفات *.plain-bak تُستعاد أوّلًا).

  لا يعدّل شيئًا في المستودع؛ كلُّ التغيير داخل .dart_tool (مُتجاهَل git).

.PARAMETER TestArgs
  كلُّ ما بعد اسم السكربت يُمرَّر إلى flutter test (مسارات/‎--plain-name…).
  الافتراضي: اختبارا المحرّك الحقيقيّ.

  مسار SQLCipher DLL يُؤخذ من المتغيّر PICPOS_SQLCIPHER_DLL، وافتراضيّه ما
  يبنيه sqlcipher_flutter_libs أثناء flutter build windows (يعتمد عليه
  build_picpos.bat الخطوة 5).

.EXAMPLE
  powershell -File tool\run_sqlcipher_tests.ps1
  powershell -File tool\run_sqlcipher_tests.ps1 test/integration/db_key_real_engine_test.dart --plain-name AppDatabase
  $env:PICPOS_BIG_DB_MB=200; powershell -File tool\run_sqlcipher_tests.ps1 test/integration/db_key_real_engine_test.dart --plain-name MB
#>
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$TestArgs
)
if (-not $TestArgs) {
  $TestArgs = @('test/integration/db_key_rekey_engine_test.dart',
                'test/integration/db_key_real_engine_test.dart')
}
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

$Dll = if ($env:PICPOS_SQLCIPHER_DLL) { $env:PICPOS_SQLCIPHER_DLL } else { 'build\windows\x64\plugins\sqlcipher_flutter_libs\Release\sqlite3.dll' }
if (-not (Test-Path $Dll)) {
  throw "SQLCipher DLL not found: $Dll`nBuild it first: flutter build windows --release --dart-define=APP_BRAND=picpos --dart-define=APP_FLAVOR=unified"
}
$dllFull = (Resolve-Path $Dll).Path
# ملفٌّ تنفيذيّ حقيقيّ (ترويسة MZ) وبحجم SQLCipher (>3MB؛ العاديّة ~1.6MB).
$head = [IO.File]::ReadAllBytes($dllFull)[0..1]
if ($head[0] -ne 0x4D -or $head[1] -ne 0x5A -or (Get-Item $dllFull).Length -lt 3MB) {
  throw "$dllFull is not a Windows DLL of SQLCipher size."
}
# نفس فحص build_picpos.bat الخطوة 5: السلسلة sqlcipher داخل الملف.
if (-not (Select-String -Path $dllFull -Pattern 'sqlcipher' -Quiet)) {
  throw "$dllFull is not a SQLCipher build (no 'sqlcipher' marker)."
}

$hooks = '.dart_tool\hooks_runner\sqlite3'
$cacheRoot = '.dart_tool\hooks_runner\shared\sqlite3\build'

# استعادة بقايا تشغيلٍ سابقٍ قُتل قبل finally.
Get-ChildItem $cacheRoot -Recurse -Filter 'sqlite3.dll.plain-bak' -ErrorAction SilentlyContinue | ForEach-Object {
  $orig = $_.FullName -replace '\.plain-bak$', ''
  Move-Item $_.FullName $orig -Force
}

# الملفات التي يستعملها flutter test فعلًا (أصول الـhook ذات الحالة success).
$targets = @()
Get-ChildItem $hooks -Directory -ErrorAction SilentlyContinue | ForEach-Object {
  $out = Join-Path $_.FullName 'output.json'
  if (Test-Path $out) {
    $json = Get-Content $out -Raw | ConvertFrom-Json
    foreach ($a in @($json.assets)) {
      $f = $a.encoding.file
      if ($f -and (Test-Path $f) -and $f -like '*sqlite3.dll') { $targets += $f }
    }
  }
}
$targets = $targets | Select-Object -Unique
if (-not $targets) {
  throw "No hook-built sqlite3.dll found under $hooks. Run 'flutter test' once (any test) to let the hook run."
}

$swapped = @()
try {
  foreach ($t in $targets) {
    Move-Item $t "$t.plain-bak" -Force
    Copy-Item $dllFull $t -Force
    $swapped += $t
  }
  Write-Host "SQLCipher DLL swapped into $($swapped.Count) hook cache file(s): $dllFull"
  $env:PICPOS_REQUIRE_SQLCIPHER = '1'
  & flutter test @TestArgs -r expanded
  $code = $LASTEXITCODE
}
finally {
  Remove-Item Env:\PICPOS_REQUIRE_SQLCIPHER -ErrorAction SilentlyContinue
  foreach ($t in $swapped) {
    if (Test-Path "$t.plain-bak") { Move-Item "$t.plain-bak" $t -Force }
  }
}
exit $code
