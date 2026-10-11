@echo off
REM ======================================================================
REM PicPos - build the Windows installer (Inno Setup 6).
REM
REM NOTE: this file is intentionally ASCII-only, same rule as
REM build_picpos.bat - cmd.exe reads .bat files in the OEM codepage, so a
REM single non-ASCII comment can silently drop `set` lines and produce a
REM broken build that still reports SUCCESS. Keep every .bat in English.
REM
REM Run build_picpos.bat FIRST. This script packages whatever is currently
REM in build\windows\x64\runner\Release, so packaging without a fresh
REM PicPos build would wrap the other brand's binaries. The .iss refuses to
REM compile if PicPos.exe is not there, but that guard only catches the
REM obvious case - a stale PicPos build still packages silently.
REM ======================================================================

setlocal

set BRAND_ID=picpos
set ISS_FILE=installer\setup.iss
set ISCC="C:\Program Files (x86)\Inno Setup 6\ISCC.exe"

echo ============================================
echo   Building %BRAND_ID% installer
echo ============================================
echo.

REM Fail fast if the codepage mangled the variables above.
if "%BRAND_ID%"=="" (
    echo FAILED: BRAND_ID is empty - this script was parsed incorrectly.
    exit /b 1
)

if not exist %ISCC% (
    echo FAILED: Inno Setup 6 not found at %ISCC%
    echo Install it from https://jrsoftware.org/isdl.php
    exit /b 1
)

REM --- 1) Verify the Release output belongs to PicPos --------------------
echo [1/2] Checking build output...
if not exist "build\windows\x64\runner\Release\PicPos.exe" (
    echo FAILED: build\windows\x64\runner\Release\PicPos.exe is missing.
    echo Run build_picpos.bat first.
    exit /b 1
)
if exist "build\windows\x64\runner\Release\UralCash.exe" (
    echo FAILED: UralCash.exe found in the Release output - mixed build.
    echo Run build_picpos.bat to rebuild cleanly.
    exit /b 1
)

REM --- 2) Compile the installer -----------------------------------------
echo [2/2] Compiling %ISS_FILE% for %BRAND_ID%...
REM Optional signing of the installer + uninstaller (finding B-02). Enabled
REM ONLY when PICPOS_SIGN_PFX or PICPOS_SIGN_THUMBPRINT is set; the secrets stay
REM in the environment and are read by tool\sign_file.cmd, never put on this
REM command line. Without them the installer is built unsigned.
set SIGN_ARGS=
if defined PICPOS_SIGN_PFX set SIGN_ARGS=/DSignInstaller=1 "/Spicpossign=$q%~dp0tool\sign_file.cmd$q $f"
if defined PICPOS_SIGN_THUMBPRINT set SIGN_ARGS=/DSignInstaller=1 "/Spicpossign=$q%~dp0tool\sign_file.cmd$q $f"
if not defined SIGN_ARGS echo unsigned build - PICPOS_SIGN_PFX / PICPOS_SIGN_THUMBPRINT not set.
%ISCC% /DBrandId=%BRAND_ID% %SIGN_ARGS% %ISS_FILE%
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo INSTALLER BUILD FAILED!
    exit /b 1
)

echo.
echo ============================================
echo   SUCCESS
echo   installer\output\
echo ============================================

endlocal
