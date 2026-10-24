<#
.SYNOPSIS
  INTERNAL TESTING ONLY - creates a SELF-SIGNED code-signing certificate (audit REL-002).

.DESCRIPTION
  A self-signed certificate is NOT trusted by Windows or SmartScreen on any other machine
  and does NOT remove the "unknown publisher" warning for customers. Use it only to
  exercise the signing pipeline (tool\sign_file.cmd, build_*.bat, the CI signing guard)
  on a developer / test machine. For customer releases buy an OV/EV code-signing
  certificate - see docs/ops/WINDOWS-SIGNING.md.

  Output (default D:\keys\, never inside the repo):
    picpos-selftest-codesign.pfx   password-protected (password from -Password or prompt)
    picpos-selftest-codesign.cer   public part only

  The certificate is created in Cert:\CurrentUser\My and is NOT added to any Root or
  TrustedPublisher store (the installer policy B-01 forbids trusting self-signed
  publishers on customer machines). To trust it on YOUR test PC only, import the .cer
  into CurrentUser\TrustedPublisher + Root manually.

.EXAMPLE
  pwsh tool\gen_selfsigned_codesign.ps1
  $env:PICPOS_SIGN_PFX='D:\keys\picpos-selftest-codesign.pfx'; $env:PICPOS_SIGN_PFX_PASSWORD='...'
  build_picpos.bat
#>
[CmdletBinding()]
param(
  [string]$OutDir = 'D:\keys',
  [string]$Subject = 'CN=PicPos SELF-SIGNED TEST (not for distribution), O=PicPos',
  [int]$ValidYears = 2,
  [securestring]$Password
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$full = [IO.Path]::GetFullPath($OutDir).TrimEnd('\') + '\'
if ($full.StartsWith($repo.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
  throw "Refusing to write key material inside the repository ($OutDir)."
}
if (-not $Password) { $Password = Read-Host -AsSecureString 'PFX password' }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject $Subject `
  -KeyAlgorithm RSA -KeyLength 3072 -HashAlgorithm SHA256 -KeyExportPolicy Exportable `
  -NotAfter (Get-Date).AddYears($ValidYears) -CertStoreLocation Cert:\CurrentUser\My
$pfx = Join-Path $OutDir 'picpos-selftest-codesign.pfx'
$cer = Join-Path $OutDir 'picpos-selftest-codesign.cer'
Export-PfxCertificate -Cert $cert -FilePath $pfx -Password $Password | Out-Null
Export-Certificate -Cert $cert -FilePath $cer | Out-Null

Write-Host '*** SELF-SIGNED TEST CERTIFICATE - INTERNAL TESTING ONLY ***' -ForegroundColor Yellow
Write-Host "Thumbprint : $($cert.Thumbprint)"
Write-Host "PFX        : $pfx"
Write-Host "CER        : $cer"
Write-Host 'Use: set PICPOS_SIGN_PFX / PICPOS_SIGN_PFX_PASSWORD (or PICPOS_SIGN_THUMBPRINT) then run build_picpos.bat'
Write-Host 'Customers will STILL see the unknown-publisher warning. Buy an OV/EV certificate for release.'
