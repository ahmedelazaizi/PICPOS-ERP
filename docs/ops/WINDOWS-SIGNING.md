# Windows code signing (PicPos.exe, sqlite3.dll, installer)

Audit finding **REL-002**. The scripts sign only when an identity is configured; nothing secret is
stored in the repo. The installer never adds a certificate to any trust store (policy B-01).

## Production: use a real certificate

1. Buy an OV or EV code-signing certificate (or use Azure Trusted Signing). A self-signed
   certificate does **not** remove SmartScreen's "unknown publisher" warning for customers.
2. Configure ONE of these in the build environment:

   | Variable | Meaning |
   |---|---|
   | `PICPOS_SIGN_PFX` + `PICPOS_SIGN_PFX_PASSWORD` | path to a `.pfx` (kept outside the repo) |
   | `PICPOS_SIGN_THUMBPRINT` | SHA-1 thumbprint of a cert in the Windows store / hardware token |
   | `PICPOS_SIGNTOOL` (optional) | full path to `signtool.exe` |
   | `PICPOS_SIGN_TIMESTAMP_URL` (optional) | default `http://timestamp.digicert.com` |

3. Run `build_picpos.bat` then `build_installer_picpos.bat` (`tool\sign_file.cmd` does the work).
4. Verify: `signtool verify /pa /v installer\output\PicPos-Setup-<ver>.exe`, and
   `Get-AuthenticodeSignature` on `PicPos.exe` and `sqlite3.dll`.
5. Generate `SHA256SUMS.txt` **after** signing (`tool\make_release_checksums.ps1`).

## CI (`.github/workflows/ci.yml`, job `build-windows`)

| Secret | Content |
|---|---|
| `PICPOS_SIGN_PFX_BASE64` | base64 of the `.pfx` (`[Convert]::ToBase64String([IO.File]::ReadAllBytes(...))`) |
| `PICPOS_SIGN_PFX_PASSWORD` | its password |
| `PICPOS_SIGN_THUMBPRINT` | alternative for self-hosted runners that hold the certificate |

- A **version tag** (`v*.*.*`) with neither secret **fails** at the step "Windows signing identity",
  unless `ALLOW_UNSIGNED` is `true` (manual dispatch input `allow_unsigned`, or the repository
  variable `ALLOW_UNSIGNED`). Pushes to `main` only warn.
- When an identity is present, the job verifies that `PicPos.exe` and `sqlite3.dll` carry a
  signature, and deletes the decoded `.pfx` at the end.
- The GitHub Release job also depends on the Android job (see `ANDROID-SIGNING.md`).

## Internal testing only: self-signed certificate

```powershell
powershell -File tool\gen_selfsigned_codesign.ps1      # writes D:\keys\picpos-selftest-codesign.pfx/.cer
$env:PICPOS_SIGN_PFX = 'D:\keys\picpos-selftest-codesign.pfx'
$env:PICPOS_SIGN_PFX_PASSWORD = '<the password you chose>'
build_picpos.bat
```

The certificate is labelled `PicPos SELF-SIGNED TEST (not for distribution)`, lives in
`Cert:\CurrentUser\My` and is not placed in any Root/TrustedPublisher store. It only exercises the
pipeline. Never ship artifacts signed with it.

## Not verified here

The CI workflow logic and `gen_selfsigned_codesign.ps1` were reviewed/parsed but not executed on a
GitHub runner; no real certificate was available.
