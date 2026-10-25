# Device-lab helpers (adb only, no Appium). Dot-source: . tool\device_lab\lab_lib.ps1
# Every step is logged with a timestamp to $script:LogFile (+ console).
$script:Sdk    = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } else { 'D:\dev-cache\android-sdk' }
$script:Adb    = Join-Path $script:Sdk 'platform-tools\adb.exe'
$script:Serial = if ($env:LAB_SERIAL) { $env:LAB_SERIAL } else { 'emulator-5554' }   # NEVER touch other devices
$script:LabDir = if ($env:LAB_DIR) { $env:LAB_DIR } else { 'D:\qa\device-lab' }
$script:RunDir = $script:LabDir
$script:LogFile = $null
$script:Results = [System.Collections.Generic.List[object]]::new()
$script:ShotN = 0

function Init-Run([string]$RunId) {
  $script:RunDir = Join-Path $script:LabDir $RunId
  New-Item -ItemType Directory -Force $script:RunDir | Out-Null
  $script:LogFile = Join-Path $script:RunDir 'steps.log'
  Set-Content $script:LogFile ''
}
function Log([string]$m) {
  $l = '{0} {1}' -f (Get-Date -Format 'HH:mm:ss.fff'), $m
  if ($script:LogFile) { Add-Content $script:LogFile $l -Encoding utf8 }
  Write-Host $l
}
function A { & $script:Adb -s $script:Serial @args 2>&1 }
function Record([string]$Id, [string]$Status, [string]$Evidence) {
  $script:Results.Add([pscustomobject]@{ Id = $Id; Status = $Status; Evidence = $Evidence })
  Log "RESULT $Id => $Status :: $Evidence"
}
function Shot([string]$Name) {
  $script:ShotN++
  $f = Join-Path $script:RunDir ('{0:D2}-{1}.png' -f $script:ShotN, $Name)
  cmd /c "`"$($script:Adb)`" -s $($script:Serial) exec-out screencap -p > `"$f`""
  Log "screenshot $f"
  return $f
}
function Get-Dump {
  A shell uiautomator dump /sdcard/ui.xml | Out-Null
  $raw = (cmd /c "`"$($script:Adb)`" -s $($script:Serial) exec-out cat /sdcard/ui.xml") -join "`n"
  try { return [xml]$raw } catch { return $null }
}
function Save-Dump([string]$Name) {
  $d = Get-Dump
  if ($d) { $d.Save((Join-Path $script:RunDir "$Name.xml")) }
  return $d
}
function Node-Text($n) { "$($n.text)|$($n.'content-desc')" }
function All-Nodes($d) { if ($d) { $d.SelectNodes('//node') } else { @() } }
function Screen-Text {
  (All-Nodes (Get-Dump) | ForEach-Object { Node-Text $_ } | Where-Object { $_ -ne '|' }) -join ' ## '
}
function Find-Node([string]$Pattern, $d = $null) {
  if (-not $d) { $d = Get-Dump }
  foreach ($n in (All-Nodes $d)) {
    if ((Node-Text $n) -match $Pattern -or $n.'resource-id' -match $Pattern) { return $n }
  }
  return $null
}
function Center($n) {
  if ($n.bounds -match '\[(\d+),(\d+)\]\[(\d+),(\d+)\]') {
    return @([int](([int]$Matches[1] + [int]$Matches[3]) / 2), [int](([int]$Matches[2] + [int]$Matches[4]) / 2))
  }
}
function Tap-Xy($x, $y) { A shell input tap $x $y | Out-Null; Start-Sleep -Milliseconds 700 }
function Wait-Node([string]$Pattern, [int]$Seconds = 20) {
  $end = (Get-Date).AddSeconds($Seconds)
  while ((Get-Date) -lt $end) {
    $n = Find-Node $Pattern
    if ($n) { return $n }
    Start-Sleep -Milliseconds 800
  }
  return $null
}
function Tap-Node([string]$Pattern, [int]$Seconds = 15) {
  $n = Wait-Node $Pattern $Seconds
  if (-not $n) { Log "TAP FAIL: no node /$Pattern/"; return $false }
  $c = Center $n; Log "tap /$Pattern/ at $($c -join ',') ($(Node-Text $n))"
  Tap-Xy $c[0] $c[1]; return $true
}
# Flutter text field: tap, clear, type ASCII.
function Type-Into([string]$Pattern, [string]$Text) {
  if (-not (Tap-Node $Pattern)) { return $false }
  A shell input keyevent KEYCODE_MOVE_END | Out-Null
  A shell input keyevent (@(67) * 70) | Out-Null
  $esc = $Text -replace ' ', '%s' -replace '([&|<>();`"''\\$#])', '\$1'
  A shell input text $esc | Out-Null
  Start-Sleep -Milliseconds 400
  Log "typed into /$Pattern/ ($($Text.Length) chars)"
  return $true
}
function Hide-Keyboard {
  if ((A shell dumpsys input_method) -match 'mInputShown=true') { A shell input keyevent KEYCODE_BACK | Out-Null; Start-Sleep -Milliseconds 500 }
}
function Launch([string]$Pkg) { A shell monkey -p $Pkg -c android.intent.category.LAUNCHER 1 | Out-Null; Start-Sleep 3 }
function Crash-Check([string]$Pkg) {
  $log = (A logcat -d -b crash) -join "`n"
  $anr = (A logcat -d -s ActivityManager:E) -join "`n"
  $hit = ($log -split "`n" | Where-Object { $_ -match $Pkg -or $_ -match 'FATAL EXCEPTION' }) | Select-Object -First 5
  $alive = (A shell pidof $Pkg) -join ''
  return [pscustomobject]@{ Crashes = $hit; Alive = [bool]$alive.Trim(); Anr = ($anr -match "ANR in $Pkg") }
}
function Cmd-Host([string]$Line) { Add-Content (Join-Path $script:LabDir 'cmd.txt') $Line; Log "host cmd: $Line" }
function Host-Json { Get-Content (Join-Path $script:LabDir 'host.json') -Raw | ConvertFrom-Json }

# i-th (0-based) EditText on screen (Flutter fields carry no labels in the dump).
function Type-Edit([int]$Index, [string]$Text) {
  $d = Get-Dump
  $e = @(All-Nodes $d | Where-Object { $_.class -eq 'android.widget.EditText' })
  if ($e.Count -le $Index) { Log "EDIT FAIL: only $($e.Count) fields"; return $false }
  $c = Center $e[$Index]; Tap-Xy $c[0] $c[1]
  A shell input keyevent KEYCODE_MOVE_END | Out-Null
  A shell input keyevent (@(67) * 70) | Out-Null
  $esc = $Text -replace ' ', '%s' -replace '([&|<>();`"''\\$#])', '\$1'
  A shell input text $esc | Out-Null
  Start-Sleep -Milliseconds 400
  Log "typed edit[$Index] ($($Text.Length) chars)"
  return $true
}


# ───────────── warehouse W2-W5 helpers (host command channel with ack) ─────────────
# Sends one '|' separated command to the host and waits (bounded) for its ack line "<n>|<msg>".
function Host-Do([string]$Line, [int]$TimeoutSec = 45) {
  $cmd = Join-Path $script:LabDir 'cmd.txt'; $ack = Join-Path $script:LabDir 'ack.txt'
  $n = if (Test-Path $cmd) { @([IO.File]::ReadAllLines($cmd)).Count } else { 0 }
  [IO.File]::AppendAllText($cmd, $Line + "`r`n")
  $end = (Get-Date).AddSeconds($TimeoutSec)
  while ((Get-Date) -lt $end) {
    if (Test-Path $ack) {
      foreach ($l in [IO.File]::ReadAllLines($ack)) { if ($l.StartsWith("$n|")) { Log "host-do[$n] $Line => $($l.Substring($l.IndexOf('|') + 1))"; return $l.Substring($l.IndexOf('|') + 1) } }
    }
    Start-Sleep -Milliseconds 400
  }
  Log "host-do[$n] $Line => TIMEOUT"; return 'TIMEOUT'
}
function Get-Facts([string]$Name) {
  $r = Host-Do "facts|$Name"
  $f = Join-Path $script:LabDir "facts-$Name.json"
  if (-not (Test-Path $f)) { Log "facts $Name missing ($r)"; return $null }
  Copy-Item $f (Join-Path $script:RunDir "facts-$Name.json") -Force
  return (Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json)
}
function Fixtures { Get-Content (Join-Path $script:LabDir 'fixtures.json') -Raw -Encoding UTF8 | ConvertFrom-Json }
# Real HTTPS call from the host's probe phone; returns @{status; body} (also kept in the run dir).
function Api-Call([string]$Label, [string]$User, [string]$Method, [string]$Path, [string]$Body = '', [string]$Key = '') {
  $r = Host-Do "api|$Label|$User|$Method|$Path|$Body|$Key"
  $f = Join-Path $script:LabDir "api-$Label.json"
  if (-not (Test-Path $f)) { return $null }
  Copy-Item $f (Join-Path $script:RunDir "api-$Label.json") -Force
  return (Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json)
}
function Doc-Of($facts, [string]$Kind) { @($facts.docs | Where-Object { $_.kind -eq $Kind }) }
function Qty($facts, [string]$Barcode, $WhId) { $s = $facts.stock.$Barcode; if ($null -eq $s) { return $null }; $v = $s."$WhId"; if ($null -eq $v) { 0 } else { [double]$v } }