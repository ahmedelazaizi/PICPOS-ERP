@echo off
REM ======================================================================
REM Optional Authenticode signing of ONE file. ASCII-only on purpose (see
REM build_picpos.bat: cmd.exe reads .bat/.cmd in the OEM codepage).
REM
REM Usage:  tool\sign_file.cmd <file>
REM
REM Signing happens ONLY when an identity is configured through environment
REM variables. Nothing secret is stored in the repository:
REM   PICPOS_SIGN_PFX               path to a .pfx file          (option A)
REM   PICPOS_SIGN_PFX_PASSWORD      its password (if it has one)
REM   PICPOS_SIGN_THUMBPRINT        SHA-1 thumbprint of a cert in the
REM                                 Windows cert store / token   (option B)
REM Optional:
REM   PICPOS_SIGNTOOL               full path to signtool.exe (else PATH, else
REM                                 the newest Windows Kits x64 copy)
REM   PICPOS_SIGN_TIMESTAMP_URL     default http://timestamp.digicert.com
REM
REM Exit codes: 0 = signed, or skipped quietly because nothing is configured
REM ("unsigned build"); non-zero = signing WAS requested but failed - the
REM caller must stop, never ship a half-signed build.
REM ======================================================================
setlocal

set "TARGET=%~1"
if "%TARGET%"=="" (
    echo sign_file: no file given.
    exit /b 2
)

if not defined PICPOS_SIGN_PFX if not defined PICPOS_SIGN_THUMBPRINT (
    echo [sign] unsigned build - PICPOS_SIGN_PFX / PICPOS_SIGN_THUMBPRINT not set, skipping %~nx1
    exit /b 0
)

if not exist "%TARGET%" (
    echo [sign] FAILED: file not found: %TARGET%
    exit /b 2
)

set "TSURL=%PICPOS_SIGN_TIMESTAMP_URL%"
if not defined TSURL set "TSURL=http://timestamp.digicert.com"

set "SIGNTOOL=%PICPOS_SIGNTOOL%"
if not defined SIGNTOOL for /f "delims=" %%S in ('where signtool.exe 2^>nul') do if not defined SIGNTOOL set "SIGNTOOL=%%S"
if not defined SIGNTOOL for /f "delims=" %%S in ('dir /b /s /o-n "%ProgramFiles(x86)%\Windows Kits\10\bin\*signtool.exe" 2^>nul ^| findstr /i "\\x64\\"') do if not defined SIGNTOOL set "SIGNTOOL=%%S"
if not defined SIGNTOOL (
    echo [sign] FAILED: signing was requested but signtool.exe was not found.
    echo        Install the Windows SDK or set PICPOS_SIGNTOOL to its full path.
    exit /b 3
)

if defined PICPOS_SIGN_PFX (
    if not exist "%PICPOS_SIGN_PFX%" (
        echo [sign] FAILED: PICPOS_SIGN_PFX points to a missing file.
        exit /b 3
    )
    if defined PICPOS_SIGN_PFX_PASSWORD (
        "%SIGNTOOL%" sign /fd sha256 /tr "%TSURL%" /td sha256 /f "%PICPOS_SIGN_PFX%" /p "%PICPOS_SIGN_PFX_PASSWORD%" "%TARGET%"
    ) else (
        "%SIGNTOOL%" sign /fd sha256 /tr "%TSURL%" /td sha256 /f "%PICPOS_SIGN_PFX%" "%TARGET%"
    )
) else (
    "%SIGNTOOL%" sign /fd sha256 /tr "%TSURL%" /td sha256 /sha1 "%PICPOS_SIGN_THUMBPRINT%" "%TARGET%"
)
if errorlevel 1 (
    echo [sign] FAILED: signtool could not sign %TARGET%
    exit /b 1
)
echo [sign] signed %~nx1
exit /b 0
