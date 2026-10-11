<#
  Fetches / verifies the VC++ redistributable that setup.iss EMBEDS in the
  installer. Output: installer\prereqs\vc_redist.x64.exe (git-ignored).

  Checks, in order (any failure => exit 1, build must stop):
    1. SHA-256 equals the pinned value below (must equal VCRedistSha256 in
       installer\setup.iss).
    2. Authenticode status Valid, signer subject CN=Microsoft Corporation.

  If the file is already present and valid nothing is downloaded. If it is
  absent, it is downloaded from -Url (Microsoft's "latest" link by default);
  that only works while Microsoft's current file still has the pinned hash.
  Otherwise supply the pinned file manually (see docs/security/release-integrity.md).

  NOTE: *.ps1 is git-ignored: add with `git add -f tool/fetch_prereqs.ps1`.
#>
param(
  [string]$Url = 'https://aka.ms/vs/17/release/vc_redist.x64.exe',
  [string]$ExpectedSha256 = 'cc0ff0eb1dc3f5188ae6300faef32bf5beeba4bdd6e8e445a9184072096b713b'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$dir  = Join-Path $root 'installer\prereqs'
$file = Join-Path $dir 'vc_redist.x64.exe'

function Test-Prereq([string]$f) {
  $h = (Get-FileHash -Algorithm SHA256 -LiteralPath $f).Hash
  if ($h -ne $ExpectedSha256.ToUpperInvariant()) {
    return "SHA-256 mismatch: expected $ExpectedSha256 but got $($h.ToLowerInvariant())"
  }
  $sig = Get-AuthenticodeSignature -LiteralPath $f
  if ($sig.Status -ne 'Valid') { return "Authenticode status is '$($sig.Status)', expected Valid" }
  if ($sig.SignerCertificate.Subject -notmatch '(^|,\s*)CN=Microsoft Corporation(,|$)') {
    return "Signer is '$($sig.SignerCertificate.Subject)', expected CN=Microsoft Corporation"
  }
  return $null
}

try {
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  if (-not (Test-Path -LiteralPath $file)) {
    Write-Host "Downloading $Url ..."
    $tmp = "$file.download"
    Invoke-WebRequest -Uri $Url -OutFile $tmp -UseBasicParsing
    Move-Item -Force -LiteralPath $tmp -Destination $file
  }
  $err = Test-Prereq $file
  if ($err) {
    Remove-Item -Force -LiteralPath $file -ErrorAction SilentlyContinue
    throw $err
  }
  Write-Host "OK: $file (SHA-256 pinned, Authenticode Valid, Microsoft Corporation)"
  exit 0
} catch {
  Write-Host "FAILED: vc_redist.x64.exe could not be prepared: $($_.Exception.Message)" -ForegroundColor Red
  Write-Host "See docs/security/release-integrity.md (updating the VC++ redistributable)."
  exit 1
}
