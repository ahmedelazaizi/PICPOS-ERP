# Boots AVD PicPos_Van headless and waits for sys.boot_completed.
# Usage: pwsh tool\device_lab\start_emulator.ps1 [-Avd PicPos_Van] [-TimeoutSec 300] [-Gpu swiftshader_indirect]
param([string]$Avd = 'PicPos_Van', [int]$TimeoutSec = 300, [string]$Gpu = 'swiftshader_indirect',
      [string]$LabDir = 'D:\qa\device-lab')
$ErrorActionPreference = 'Stop'
$sdk = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } else { 'D:\dev-cache\android-sdk' }
$env:ANDROID_SDK_ROOT = $sdk
$adb = Join-Path $sdk 'platform-tools\adb.exe'
$emu = Join-Path $sdk 'emulator\emulator.exe'
$serial = 'emulator-5554'
New-Item -ItemType Directory -Force "$LabDir\logs" | Out-Null
foreach ($f in $adb, $emu) { if (-not (Test-Path $f)) { throw "missing $f" } }
if (-not ((& $emu -list-avds) -contains $Avd)) { throw "AVD $Avd not found (avdmanager create avd ...)" }

$up = (& $adb devices) -match "^$serial\s+device"
if ($up) { Write-Host "$serial already running"; }
else {
  Start-Process $emu -ArgumentList '-avd', $Avd, '-no-window', '-no-audio', '-no-boot-anim', '-gpu', $Gpu, '-no-snapshot', '-no-metrics' `
    -RedirectStandardOutput "$LabDir\logs\emu.out" -RedirectStandardError "$LabDir\logs\emu.err" -WindowStyle Hidden
}
$end = (Get-Date).AddSeconds($TimeoutSec)
$ErrorActionPreference = 'Continue'   # adb writes 'device not found' to stderr until the emulator appears
while ((Get-Date) -lt $end) {
  $b = (& $adb -s $serial shell getprop sys.boot_completed 2>$null) -join ''
  if ($b.Trim() -eq '1') { break }
  Start-Sleep 3
}
$ErrorActionPreference = 'Stop'
if ($b.Trim() -ne '1') { throw "emulator did not boot within ${TimeoutSec}s; see $LabDir\logs\emu.err (check hypervisor: 'emulator -accel-check')" }
& $adb -s $serial shell settings put global window_animation_scale 0
& $adb -s $serial shell settings put global transition_animation_scale 0
& $adb -s $serial shell settings put global animator_duration_scale 0
& $adb -s $serial shell settings put secure show_ime_with_hard_keyboard 1 | Out-Null
& $adb -s $serial shell input keyevent KEYCODE_WAKEUP
Write-Host "BOOTED $serial api=$((& $adb -s $serial shell getprop ro.build.version.sdk) -join '') ; host reachable from the guest at 10.0.2.2"
