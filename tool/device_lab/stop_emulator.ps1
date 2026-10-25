# Stops ONLY the lab emulator (emulator-5554); never touches other adb devices.
param([string]$Serial = 'emulator-5554')
$sdk = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } else { 'D:\dev-cache\android-sdk' }
$adb = Join-Path $sdk 'platform-tools\adb.exe'
if ((& $adb devices) -match "^$Serial\s+device") {
  & $adb -s $Serial emu kill | Out-Null
  Start-Sleep 5
}
Get-Process -Name 'qemu-system-x86_64*' -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$sdk*" } | Stop-Process -Force -ErrorAction SilentlyContinue
Write-Host 'emulator stopped'
