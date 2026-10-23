<#
.SYNOPSIS
  Removes assets that belong to the alternate brand from a PicPos Windows bundle.

.DESCRIPTION
  Flutter cannot declare brand-conditional assets on Windows (no --flavor), so
  pubspec.yaml still lists the alternate brand's `logo.PNG` for that brand's own
  build and for the shared test bundle. A PicPos release must not carry it
  (owner requirement 2026-10-23: nothing of the other product in a PicPos
  artifact). This script deletes it from the *built* bundle.

  Called by build_picpos.bat and by the CI `build-windows` job. The guard
  test/structural/brand_artifact_guard_test.dart verifies the result.

.PARAMETER Bundle
  The Release directory (the folder that contains PicPos.exe and `data`).
#>
param(
  [Parameter(Mandatory = $true)][string]$Bundle
)

$ErrorActionPreference = 'Stop'

$assets = Join-Path $Bundle 'data\flutter_assets'
if (-not (Test-Path -LiteralPath $assets)) {
  Write-Error "flutter_assets not found under '$Bundle' (expected '$assets')."
  exit 1
}

# Files declared in pubspec.yaml that only the alternate brand uses.
$foreign = @(
  'logo.PNG'
)

foreach ($rel in $foreign) {
  $path = Join-Path $assets $rel
  if (Test-Path -LiteralPath $path) {
    Remove-Item -LiteralPath $path -Force
    Write-Host "  pruned: flutter_assets\$rel"
  }
  if (Test-Path -LiteralPath $path) {
    Write-Error "could not prune $path"
    exit 1
  }
}

Write-Host "  OK - bundle contains only PicPos brand assets."
exit 0
