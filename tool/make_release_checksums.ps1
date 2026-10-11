# Generates SHA256SUMS.txt for a PicPos release (installer .exe + .zip) so it
# can be published next to the release assets (finding B-02/C-01: with no
# Authenticode signature yet, the checksum is the customer's integrity check).
#
# Usage (repo root):
#   powershell -ExecutionPolicy Bypass -File tool\make_release_checksums.ps1
#   powershell -ExecutionPolicy Bypass -File tool\make_release_checksums.ps1 -Version 3.9.1.275
#   powershell -ExecutionPolicy Bypass -File tool\make_release_checksums.ps1 -Files a.exe,b.zip
#
# Default: reads `#define AppVersion` from installer\setup.iss and hashes
# installer\output\PicPos-Setup-<version>.exe (required) and .zip (if present).
# Output: SHA256SUMS.txt next to the files, in `sha256sum` format
# ("<hash> *<name>"), UTF-8 without BOM, LF line endings.
#
# NOTE: *.ps1 is ignored by .gitignore - add this file with `git add -f`.
[CmdletBinding()]
param(
    [string]$Version,
    [string]$Dir,
    [string[]]$Files
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

if (-not $Files) {
    if (-not $Dir) { $Dir = Join-Path $root 'installer\output' }
    if (-not $Version) {
        $iss = Get-Content (Join-Path $root 'installer\setup.iss') -Raw -Encoding UTF8
        $m = [regex]::Match($iss, '(?m)^\s*#define\s+AppVersion\s+"([^"]+)"')
        if (-not $m.Success) { throw 'Could not read AppVersion from installer\setup.iss; pass -Version.' }
        $Version = $m.Groups[1].Value
    }
    $exe = Join-Path $Dir "PicPos-Setup-$Version.exe"
    if (-not (Test-Path -LiteralPath $exe)) { throw "Installer not found: $exe (build it first, or pass -Version/-Dir/-Files)." }
    $Files = @($exe)
    $zip = Join-Path $Dir "PicPos-Setup-$Version.zip"
    if (Test-Path -LiteralPath $zip) { $Files += $zip }
    else { Write-Warning "No zip found at $zip - only the installer is listed." }
}

$resolved = @($Files | ForEach-Object {
    if (-not (Test-Path -LiteralPath $_)) { throw "File not found: $_" }
    (Resolve-Path -LiteralPath $_).Path
})
$outDir = Split-Path -Parent $resolved[0]
$out = Join-Path $outDir 'SHA256SUMS.txt'

$lines = foreach ($f in $resolved) {
    $h = (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash.ToLowerInvariant()
    '{0} *{1}' -f $h, (Split-Path -Leaf $f)
}
$text = ($lines -join "`n") + "`n"
[IO.File]::WriteAllText($out, $text, (New-Object Text.UTF8Encoding($false)))

Write-Host "Wrote $out"
$lines | ForEach-Object { Write-Host "  $_" }
Write-Host 'Publish SHA256SUMS.txt with the release assets.'
