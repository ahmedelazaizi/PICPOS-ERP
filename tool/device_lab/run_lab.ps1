# DEVICE LAB orchestrator - see docs/testing/DEVICE-LAB.md
#   pwsh tool\device_lab\run_lab.ps1 [-Snapshot] [-SkipHostStart] [-KeepEmulator]
# host (flutter test, REAL production LAN stack, TLS) -> emulator -> adb install -> drive apps
# (uiautomator dump + input tap/text, no Appium) -> screenshots/dumps/logcat -> summary.
param(
  [switch]$Snapshot,        # run the host from `git archive HEAD` in D:\qa\device-lab\src (when lib/ is mid-edit)
  [switch]$SkipHostStart,   # a host (test/device_lab/serve_host_test.dart) is already running
  [switch]$KeepEmulator,
  [switch]$SkipLegacy,      # skip S1-S5 (pairing/lookup/revoke/other apps) and run only the W2-W5 warehouse scenarios
  [switch]$SkipWarehouse,   # skip the W2-W5 scenarios
  [switch]$SkipCashier,     # skip the C1-C5 cashier (mobile_pos) scenarios
  [switch]$SkipNew,         # skip W15/W14/W30 (Addendum 4 warehouse scenarios)
  [switch]$SkipW15, [switch]$SkipW14, [switch]$SkipW30,
  [int]$HostMinutes = 45,
  [string]$RunId = (Get-Date -Format 'yyyyMMdd-HHmmss')
)
$ErrorActionPreference = 'Continue'
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$env:LAB_DIR = if ($env:LAB_DIR) { $env:LAB_DIR } else { 'D:\qa\device-lab' }
. "$PSScriptRoot\lab_lib.ps1"
Init-Run $RunId
Log "run $RunId repo=$Repo"
$Apk = @{ wh = "$($env:LAB_DIR)\apks\warehouse.apk"; pos = "$($env:LAB_DIR)\apks\pos.apk"
          admin = "$($env:LAB_DIR)\apks\admin.apk"; van = "$($env:LAB_DIR)\apks\van.apk" }
$Pkg = @{ wh = 'com.picpos.warehouse'; pos = 'com.picpos.pos'; admin = 'com.picpos.admin'; van = 'com.picpos.picpos_van' }
# Always copy the LATEST signed APKs fresh (an older copy in apks\ was once used by mistake) and log size + SHA-256 of each.
$srcApk = @{ wh = 'mobile_warehouse'; pos = 'mobile_pos'; admin = 'mobile_admin'; van = 'mobile' }
foreach ($k in 'wh', 'pos', 'admin', 'van') {
  $src = Join-Path $Repo "$($srcApk[$k])\build\app\outputs\flutter-apk\app-release.apk"
  if (Test-Path $src) {
    New-Item -ItemType Directory -Force (Split-Path $Apk[$k]) | Out-Null
    Copy-Item $src $Apk[$k] -Force
  }
  if (Test-Path $Apk[$k]) {
    $it = Get-Item $Apk[$k]; $sha = (Get-FileHash $Apk[$k] -Algorithm SHA256).Hash
    $built = (Get-Item $src -ErrorAction SilentlyContinue).LastWriteTime
    Log "$k APK source=$src built=$built copied=$($it.FullName) size=$($it.Length) sha256=$sha"
    Record "ENV-APK-$k identity" 'PASS' "$($it.Name) size=$($it.Length) sha256=$sha (copied fresh from $src, built $built)"
  }
}
foreach ($k in $Apk.Keys) { if (-not (Test-Path $Apk[$k])) { Record "ENV-APK-$k" 'BLOCKED' "missing $($Apk[$k]) (copy the release APK there first)" } }
$PIN = '123456'
$HostProc = $null

# ───────────────────────── 1. host ─────────────────────────
if (-not $SkipHostStart) {
  $root = $Repo
  if ($Snapshot) {
    $root = Join-Path $env:LAB_DIR 'src'
    Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory $root | Out-Null
    git -C $Repo archive HEAD -o "$($env:LAB_DIR)\head.tar"; tar -xf "$($env:LAB_DIR)\head.tar" -C $root
    New-Item -ItemType Directory -Force "$root\test\device_lab" | Out-Null
    Copy-Item "$Repo\test\device_lab\serve_host_test.dart" "$root\test\device_lab\" -Force
    Push-Location $root; flutter pub get | Out-Null; Pop-Location
  }
  Remove-Item "$($env:LAB_DIR)\host.json", "$($env:LAB_DIR)\cmd.txt", "$($env:LAB_DIR)\devices.json" -ErrorAction SilentlyContinue
  $env:LAB_HOST = '1'; $env:LAB_MINUTES = "$HostMinutes"
  $HostProc = Start-Process "$PSHOME\powershell.exe" -WindowStyle Hidden -PassThru -ArgumentList '-NoProfile', '-Command',
    "cd '$root'; flutter test test/device_lab/serve_host_test.dart --reporter expanded *> '$($env:LAB_DIR)\logs\host-flutter.log'"
  Log "host process started pid=$($HostProc.Id) root=$root"
}
$t0 = Get-Date
while (-not (Test-Path "$($env:LAB_DIR)\host.json") -and ((Get-Date) - $t0).TotalSeconds -lt 420) { Start-Sleep 3 }
if (-not (Test-Path "$($env:LAB_DIR)\host.json")) {
  Record 'ENV-HOST' 'BLOCKED' 'host.json never appeared; see logs\host-flutter.log'
  Get-Content "$($env:LAB_DIR)\logs\host-flutter.log" -Tail 20 | ForEach-Object { Log "  host> $_" }
  return
}
$H = Host-Json
Record 'ENV-HOST' 'PASS' "REAL NetworkService.startServer https 0.0.0.0:$($H.port) fp=$($H.fingerprint)"
$info = (curl.exe -sk "https://127.0.0.1:$($H.port)/api/m1/info"); Log "host /api/m1/info => $info"
Copy-Item "$($env:LAB_DIR)\host.json" "$($script:RunDir)\host.json"

# ───────────────────────── 2. emulator + install ─────────────────────────
try { & "$PSScriptRoot\start_emulator.ps1" -LabDir $env:LAB_DIR | ForEach-Object { Log "emu> $_" } }
catch { Record 'ENV-EMULATOR' 'BLOCKED' "$_"; return }
Record 'ENV-EMULATOR' 'PASS' "booted $($script:Serial) api $((A shell getprop ro.build.version.sdk) -join '')"
A logcat -c | Out-Null
foreach ($k in 'wh', 'pos', 'admin', 'van') {
  if (-not (Test-Path $Apk[$k])) { continue }
  if ((A shell pm list packages $Pkg[$k]) -match $Pkg[$k]) { $sig = (A install -r $Apk[$k]) -join ' '; if ($sig -match 'UPDATE_INCOMPATIBLE') { Log "${k}: pre-existing package signed differently on the lab AVD -> uninstall (lab emulator only)"; A uninstall $Pkg[$k] | Out-Null } }
  $r = (A install -r $Apk[$k]) -join ' '
  Log "install $k => $r"
  if ($r -notmatch 'Success') { Record "ENV-INSTALL-$k" 'FAIL' $r } else { Record "ENV-INSTALL-$k" 'PASS' 'adb install -r Success' }
}

# ───────────────────────── helpers ─────────────────────────
function New-Code([string]$branch = 'B1') {
  $n = @($(Host-Json).codes).Count
  Cmd-Host "issue $branch"
  for ($i = 0; $i -lt 20; $i++) { Start-Sleep -Milliseconds 700; if (@($(Host-Json).codes).Count -gt $n) { break } }
  return @($(Host-Json).codes)[-1].code
}
# True when the i-th EditText of the pairing form already holds the wanted value.
function Edit-Has([int]$i, [string]$v) {
  $e = @(All-Nodes (Get-Dump) | Where-Object { $_.class -eq 'android.widget.EditText' })
  if ($e.Count -le $i) { return $false }
  return ("$($e[$i].text)").Contains($v)   # FULL value: ports 18080/18443 share a 10-char prefix
}
function Pair-Form([string]$addr, [string]$code, [string]$fp) {
  # Type each field, then VERIFY it from the dump and retype a field that stayed empty (S5.3 once left the
  # address empty right after "pm clear" -> app said "بيانات الإقران ناقصة" and the lab blamed the product).
  $vals = @($addr, $code, $fp)
  for ($round = 0; $round -lt 3; $round++) {
    for ($i = 0; $i -lt 3; $i++) { if (-not (Edit-Has $i $vals[$i])) { Type-Edit $i $vals[$i] | Out-Null } }
    if ((Edit-Has 0 $vals[0]) -and (Edit-Has 1 $vals[1]) -and (Edit-Has 2 $vals[2])) { break }
    Log "Pair-Form: a field is still empty, retyping (round $round)"
  }
  Hide-Keyboard; Start-Sleep 3   # let the IME animation + Flutter semantics settle (a dump taken too early misses the button)
  if (-not (Tap-Node '^\|ربط$' 25)) {
    # fallback: the button sits ~171 px under the fingerprint field (seen in every dump of this form)
    $e = @(All-Nodes (Get-Dump) | Where-Object { $_.class -eq 'android.widget.EditText' })
    if ($e.Count -ge 3 -and $e[2].bounds -match '\[\d+,\d+\]\[\d+,(\d+)\]') { Log 'Pair-Form fallback tap by geometry'; Tap-Xy 540 ([int]$Matches[1] + 171) }
  }
  # pairing = TLS handshake + /api/m1/info + /api/pair; poll (bounded) instead of a fixed sleep
  for ($w = 0; $w -lt 10; $w++) { Start-Sleep 2; if (On-Login) { break } }
}
function On-Onboarding { (Screen-Text) -match 'أو أدخل البيانات يدوياً' }
function On-Login { $s = Screen-Text; ($s -match 'بحسابك في PicPos') -and ($s -match 'فك الربط') }
function Login([string]$u, [string]$p) {
  Type-Edit 0 $u | Out-Null; Type-Edit 1 $p | Out-Null; Hide-Keyboard
  Tap-Node '^\|دخول$' | Out-Null; Start-Sleep 6
}
function Handle-Pin {   # create-PIN screen on first login, unlock screen on later launches
  $s = Screen-Text
  if ($s -match 'أنشئ رمز قفل') {
    Type-Edit 0 $PIN | Out-Null; Type-Edit 1 $PIN | Out-Null; Hide-Keyboard
    Tap-Node '^\|حفظ الرمز$' | Out-Null; Start-Sleep 5; return 'created'
  }
  if ($s -match 'رمز' -and (@(All-Nodes (Get-Dump) | Where-Object { $_.class -eq 'android.widget.EditText' })).Count -ge 1 -and $s -notmatch 'مرحباً') {
    Type-Edit 0 $PIN | Out-Null; A shell input keyevent KEYCODE_ENTER | Out-Null; Start-Sleep 3
    if ((Screen-Text) -match 'مرحباً|الرئيسية') { return 'unlocked' }
    $b = Find-Node '^\|(فتح|دخول|تأكيد|إلغاء القفل)'; if ($b) { $c = Center $b; Tap-Xy $c[0] $c[1]; Start-Sleep 3 }
    return 'unlock-attempted'
  }
  return 'none'
}
function Fresh-Pair-And-Login([string]$user, [string]$pw, [string]$branch = 'B1') {
  A shell pm clear $Pkg.wh | Out-Null; Launch $Pkg.wh; Start-Sleep 4
  # ONE pending pairing offer exists on the host at a time: a retry must issue a NEW code (the old one is gone/consumed).
  for ($attempt = 1; $attempt -le 2; $attempt++) {
    $code = New-Code $branch
    Pair-Form $H.address $code $H.fingerprint
    if (On-Login) { break }
    Log "Fresh-Pair-And-Login: not on the login screen after attempt $attempt (screen text length $((Screen-Text).Length))"
    if ($attempt -eq 1) { A shell pm clear $Pkg.wh | Out-Null; Launch $Pkg.wh; Start-Sleep 4 }
  }
  if (-not (On-Login)) { return $false }
  Login $user $pw
  $null = Handle-Pin
  return ((Screen-Text) -match 'مرحباً')
}
function Tab([string]$name) { Tap-Node "^\|$name" | Out-Null; Start-Sleep 2 }
function Lookup([string]$text) {
  Tab 'بحث صنف'
  Type-Edit 0 $text | Out-Null; A shell input keyevent KEYCODE_ENTER | Out-Null; Start-Sleep 5; Hide-Keyboard
  return Screen-Text
}

if (-not $SkipLegacy) {
# ───────────────────────── S1 warehouse ─────────────────────────
A shell pm clear $Pkg.wh | Out-Null; A shell input keyevent KEYCODE_WAKEUP | Out-Null
Launch $Pkg.wh; Start-Sleep 5
$s = Shot 's1-launch'; Save-Dump 's1-launch' | Out-Null
$cc = Crash-Check $Pkg.wh
if ($cc.Alive -and -not $cc.Crashes -and (On-Onboarding)) { Record 'S1.1 launch (no crash, onboarding)' 'PASS' "$s" }
else { Record 'S1.1 launch (no crash, onboarding)' 'FAIL' "alive=$($cc.Alive) crashes=$($cc.Crashes) shot=$s" }

# plain-HTTP host refused
$code = New-Code
Pair-Form $H.plainHttpAddress $code $H.fingerprint
$s = Shot 's1-plain-http'; $txt = Screen-Text
if ((On-Onboarding) -and ($txt -match 'تعذ')) { Record 'S1.2 plain-HTTP host refused' 'PASS' "stays on pairing, error shown; $s" }
elseif (On-Onboarding) { Record 'S1.2 plain-HTTP host refused' 'PASS' "stays on pairing (error text differs: $($txt.Substring([Math]::Max(0,$txt.Length-200)))); $s" }
else { Record 'S1.2 plain-HTTP host refused' 'FAIL' "left pairing screen; $s" }

# wrong fingerprint refused (and the code is NOT consumed)
Pair-Form $H.address $code ('a' * 64)
$s = Shot 's1-wrong-fp'; $txt = Screen-Text
if ((On-Onboarding) -and ($txt -match 'تعذ|بصمة')) { Record 'S1.3 wrong fingerprint refused (pin enforced)' 'PASS' "network/pin error shown, still unpaired; $s" }
else { Record 'S1.3 wrong fingerprint refused (pin enforced)' 'FAIL' "paired or no error; $s" }

# correct pairing with the SAME code => proves the wrong-pin attempt never reached /api/pair
Pair-Form $H.address $code $H.fingerprint
$s = Shot 's1-paired'
if (On-Login) { Record 'S1.4 pair over 10.0.2.2 with code + fingerprint (TLS)' 'PASS' "login screen shown; same code still valid after the refused attempts; $s" }
else { Record 'S1.4 pair over 10.0.2.2 with code + fingerprint (TLS)' 'FAIL' "$(Screen-Text); $s" }
Cmd-Host 'list'; Start-Sleep 2
if (Test-Path "$($env:LAB_DIR)\devices.json") { Log "host devices: $(Get-Content "$($env:LAB_DIR)\devices.json" -Raw)" }

# login failures / permission
Login 'clerk1' 'wrong-password-1'
$s = Shot 's1-login-bad'; if ((Screen-Text) -match 'غير صحيحة' -and (On-Login)) { Record 'S1.5a wrong password refused' 'PASS' $s } else { Record 'S1.5a wrong password refused' 'FAIL' $s }
Login 'cashier1' 'Cashier#2026'
$s = Shot 's1-login-cashier'; $txt = Screen-Text
if ((On-Login) -and $txt -match 'صلاحية') { Record 'S1.5b user without warehouse_mobile_access refused' 'PASS' "403 message shown; $s" }
else { Record 'S1.5b user without warehouse_mobile_access refused' 'FAIL' "$txt ; $s" }

# good login
Login 'clerk1' 'WhClerk#2026'
$pinStep = Handle-Pin; Log "pin step: $pinStep"
$s = Shot 's1-home'; Save-Dump 's1-home' | Out-Null; $txt = Screen-Text
if ($txt -match 'مرحباً Lab Clerk' -and $txt -match 'Branch One' -and $txt -match 'B1 Main WH' -and $txt -notmatch 'B2 Main WH') {
  Record 'S1.6 login + role-aware home (clerk: branch One, only B1 warehouse)' 'PASS' "$s ; role badge 'موظف مخزن'; no supervisor-only capabilities: $(-not ($txt -match 'اعتماد الجرد'))"
} else { Record 'S1.6 login + role-aware home' 'FAIL' "$txt ; $s" }

# item lookup scoped to branch
$txt = Lookup '6221234567890'; $s = Shot 's1-lookup-barcode'
if ($txt -match 'Lab Milk' -and $txt -match '12' -and $txt -notmatch '\b99\b') { Record 'S1.7 item lookup scoped to the device branch' 'PASS' "Lab Milk qty 12 (B1) shown, B2 qty 99 absent; $s" }
else { Record 'S1.7 item lookup scoped to the device branch' 'FAIL' "$txt ; $s" }
$txt = Lookup 'Lab'; $s = Shot 's1-lookup-name'
if ($txt -match 'Lab Juice' -and $txt -notmatch '\b55\b') { Record 'S1.7b name search also branch-scoped' 'PASS' $s } else { Record 'S1.7b name search also branch-scoped' 'FAIL' "$txt ; $s" }

# S4 offline (wifi + data off) while paired + logged in
A shell svc wifi disable | Out-Null; A shell svc data disable | Out-Null; A shell cmd connectivity airplane-mode enable | Out-Null
Start-Sleep 4
$txt = Lookup '6229876543210'; $s = Shot 's4-offline-lookup'; Save-Dump 's4-offline' | Out-Null
$cc = Crash-Check $Pkg.wh
if ($cc.Alive -and ($txt -match 'تعذ') -and $txt -notmatch 'Lab Juice') { Record 'S4 offline: honest error, no stale/fake data, no crash' 'PASS' "network error text; no 'Lab Juice' row; $s" }
else { Record 'S4 offline: honest error, no stale/fake data, no crash' 'FAIL' "alive=$($cc.Alive) $txt ; $s" }
A shell cmd connectivity airplane-mode disable | Out-Null; A shell svc wifi enable | Out-Null; A shell svc data enable | Out-Null
Start-Sleep 8
$txt = Lookup '6229876543210'; $s = Shot 's4-back-online'
if ($txt -match 'Lab Juice') { Record 'S4b recovery after network returns' 'PASS' $s } else { Record 'S4b recovery after network returns' 'FAIL' "$txt ; $s" }

# S5 persistence
A shell am force-stop $Pkg.wh | Out-Null; Start-Sleep 2; Launch $Pkg.wh; Start-Sleep 5
$s = Shot 's5-restart'; $txt = Screen-Text
if (-not (On-Onboarding)) {
  $pinStep = Handle-Pin; $s2 = Shot 's5-after-unlock'
  Record 'S5.1 force-stop + restart keeps pairing' 'PASS' "not on pairing screen ($pinStep); $s / $s2"
} else { Record 'S5.1 force-stop + restart keeps pairing' 'FAIL' "back at pairing; $s" }
A shell input keyevent KEYCODE_HOME | Out-Null; Start-Sleep 2; A shell monkey -p $Pkg.wh -c android.intent.category.LAUNCHER 1 | Out-Null; Start-Sleep 3
$s = Shot 's5-background-resume'
if (-not (On-Onboarding)) { Record 'S5.2 background/resume keeps pairing' 'PASS' $s } else { Record 'S5.2 background/resume keeps pairing' 'FAIL' $s }

# revoke on the host => wipe on next call
$null = Handle-Pin
Cmd-Host 'revoke-all'; Start-Sleep 3
$txt = Lookup '6221234567890'; $s = Shot 's1-after-revoke'
$txt2 = Screen-Text
if (On-Onboarding) { Record 'S1.8 host revokes device -> app wipes/locks on next call' 'PASS' "returned to pairing screen after lookup; $s" }
else { Record 'S1.8 host revokes device -> app wipes/locks on next call' 'FAIL' "still $(if (On-Login) {'on login'} else {'in app'}): $txt2 ; $s" }
# a revoked device really is refused by the host even with a fresh pairing attempt using the old token? (host side evidence)
Cmd-Host 'list'; Start-Sleep 2
if (Test-Path "$($env:LAB_DIR)\devices.json") { Log "host devices after revoke: $(Get-Content "$($env:LAB_DIR)\devices.json" -Raw)" }

# S5.3 pm clear => unpaired (pair again first so there is something to clear)
$ok = Fresh-Pair-And-Login 'clerk1' 'WhClerk#2026'
$s = Shot 's5-repaired'
A shell pm clear $Pkg.wh | Out-Null; Launch $Pkg.wh; Start-Sleep 5; $s2 = Shot 's5-after-pm-clear'
if ($ok -and (On-Onboarding)) { Record 'S5.3 pm clear -> unpaired' 'PASS' "paired+logged in ($s) then onboarding after clear ($s2)" }
else { Record 'S5.3 pm clear -> unpaired' 'FAIL' "repair ok=$ok onboarding=$(On-Onboarding) $s2" }

# ───────────────────────── S2 / S3 other apps ─────────────────────────
foreach ($k in 'pos', 'admin', 'van') {
  $id = @{ pos = 'S2a'; admin = 'S2b'; van = 'S3' }[$k]
  A shell pm clear $Pkg[$k] | Out-Null; Launch $Pkg[$k]; Start-Sleep 6
  $s = Shot "$id-$k-launch"; $d = Save-Dump "$id-$k"; $txt = Screen-Text; $cc = Crash-Check $Pkg[$k]
  Log "$k screen: $txt"
  if ($cc.Alive -and -not $cc.Crashes -and $txt.Length -gt 10) { Record "$id $k launch (no crash, UI renders)" 'PASS' "$s ; text: $($txt.Substring(0, [Math]::Min(160, $txt.Length)))" }
  else { Record "$id $k launch (no crash, UI renders)" 'FAIL' "alive=$($cc.Alive) crashes=$($cc.Crashes) $s" }
}
# cashier pairing: expected NOT_APPLICABLE (onboarding button is disabled in the app)
A shell pm clear $Pkg.pos | Out-Null; Launch $Pkg.pos; Start-Sleep 5
$dd = Get-Dump; $dis = @(All-Nodes $dd | Where-Object { $_.class -match 'Button' -and $_.enabled -eq 'false' })
$ed = @(All-Nodes $dd | Where-Object { $_.class -eq 'android.widget.EditText' -and $_.enabled -eq 'false' })
Record 'S2a.2 cashier LAN pairing' 'NOT_APPLICABLE' "SUPERSEDED by C1-C5 (Addendum 4): the cashier app now pairs (mobile_pos/lib/session/pos_session.dart pair()); dump of the fresh screen shows disabled buttons=$($dis.Count) disabled fields=$($ed.Count); shot $(Shot 's2a-pos-disabled')"
Record 'S2b.2 admin pairing against the lab host' 'NOT_APPLICABLE' 'mobile_admin pairs with the CLOUD (/manage/pair, Ed25519 key confirm: admin_session.dart:109, manage_client.dart:226); the LAN host serves no /manage/pair and the app has no LAN /api/pair leg'

}   # end of legacy S1-S5 / S2 / S3

# ───────────────────────── W2-W5 warehouse phases ─────────────────────────
. "$PSScriptRoot\wh_scenarios.ps1"   # helpers (Pass, Tail, Scan ...) are shared by the later phases
if (-not $SkipWarehouse) {
  Run-WarehouseScenarios
}
if (-not $SkipCashier) {
  . "$PSScriptRoot\pos_scenarios.ps1"
  Run-CashierScenarios
}
if (-not $SkipNew) {
  . "$PSScriptRoot\wh_android_scenarios.ps1"
  Run-NewWarehouseScenarios
}

# ───────────────────────── 3. logcat + wrap up ─────────────────────────
$lc = Join-Path $script:RunDir 'logcat.txt'; A logcat -d | Set-Content $lc -Encoding utf8
$fatal = Select-String -Path $lc -Pattern 'FATAL EXCEPTION|AndroidRuntime: Process: com\.picpos|ANR in com\.picpos' | Select-Object -First 10
if ($fatal) { Record 'LOGCAT crashes' 'FAIL' ($fatal | ForEach-Object { $_.Line.Trim() } | Out-String) } else { Record 'LOGCAT crashes' 'PASS' "no FATAL EXCEPTION / ANR for com.picpos.* in $lc" }
Copy-Item "$($env:LAB_DIR)\host.log" "$($script:RunDir)\host.log" -ErrorAction SilentlyContinue
Cmd-Host 'stop'
if (-not $KeepEmulator) { & "$PSScriptRoot\stop_emulator.ps1" | ForEach-Object { Log $_ } }
Select-String -Path "$($env:LAB_DIR)\logs\host-flutter.log" -Pattern '\[API\]' -ErrorAction SilentlyContinue | Select-Object -Last 60 | ForEach-Object { $_.Line } | Set-Content "$($script:RunDir)\host-api.log"

$md = @("# Device lab run $RunId", '', '| Id | Status | Evidence |', '|---|---|---|')
foreach ($r in $script:Results) { $md += "| $($r.Id) | $($r.Status) | $(($r.Evidence -replace '\|','/' -replace '\r?\n',' ')) |" }
Set-Content "$($script:RunDir)\summary.md" $md -Encoding utf8
$script:Results | Format-Table Id, Status -AutoSize | Out-String | Write-Host
Log "summary: $($script:RunDir)\summary.md"

