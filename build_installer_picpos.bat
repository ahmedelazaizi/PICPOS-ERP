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
REM PicPos build would wrap stale binaries. The .iss refuses to compile if
REM PicPos.exe is not there, but that guard only catches the obvious case -
REM a stale PicPos build still packages silently.
REM ======================================================================

setlocal

set BRAND_ID=picpos
set ISS_FILE=installer\setup_picpos.iss
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
echo [1/3] Checking build output...
if not exist "build\windows\x64\runner\Release\PicPos.exe" (
    echo FAILED: build\windows\x64\runner\Release\PicPos.exe is missing.
    echo Run build_picpos.bat first.
    exit /b 1
)
for %%F in ("build\windows\x64\runner\Release\*.exe") do (
    if /I not "%%~nxF"=="PicPos.exe" (
        echo FAILED: unexpected executable %%~nxF in the Release output - mixed build.
        echo Run build_picpos.bat to rebuild cleanly.
        exit /b 1
    )
)
if exist "build\windows\x64\runner\Release\data\flutter_assets\logo.PNG" (
    echo FAILED: non-PicPos asset in the Release output - run build_picpos.bat.
    exit /b 1
)

REM --- 2) Fetch + verify the embedded VC++ redist ------------------------
echo [2/3] Preparing embedded VC++ redistributable...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tool\fetch_prereqs.ps1"
if errorlevel 1 (
    echo FAILED: installer\prereqs\vc_redist.x64.exe is missing or does not match the pinned SHA-256 / Microsoft signature.
    echo See docs\security\release-integrity.md ^(updating the VC++ redistributable^).
    exit /b 1
)
if not exist "installer\prereqs\vc_redist.x64.exe" (
    echo FAILED: installer\prereqs\vc_redist.x64.exe is missing.
    exit /b 1
)

REM --- 3) Compile the installer -----------------------------------------
echo [3/3] Compiling %ISS_FILE% for %BRAND_ID%...
REM Optional signing of the installer + uninstaller (finding B-02). Enabled
REM ONLY when PICPOS_SIGN_PFX or PICPOS_SIGN_THUMBPRINT is set; the secrets stay
REM in the environment and are read by tool\sign_file.cmd, never put on this
REM command line. Without them the installer is built unsigned.
set SIGN_ARGS=
if defined PICPOS_SIGN_PFX set SIGN_ARGS=/DSignInstaller=1 "/Spicpossign=$q%~dp0tool\sign_file.cmd$q $f"
if defined PICPOS_SIGN_THUMBPRINT set SIGN_ARGS=/DSignInstaller=1 "/Spicpossign=$q%~dp0tool\sign_file.cmd$q $f"
if not defined SIGN_ARGS echo unsigned build - PICPOS_SIGN_PFX / PICPOS_SIGN_THUMBPRINT not set.
REM REL-002: a RELEASE build (set RELEASE=1) without a signing identity FAILS,
REM unless ALLOW_UNSIGNED=1 is set explicitly (internal testing only).
if not defined SIGN_ARGS if "%RELEASE%"=="1" if not "%ALLOW_UNSIGNED%"=="1" (
    echo FAILED: RELEASE=1 requires PICPOS_SIGN_PFX or PICPOS_SIGN_THUMBPRINT. Set ALLOW_UNSIGNED=1 only for internal test builds.
    exit /b 1
)
%ISCC% %SIGN_ARGS% %ISS_FILE%
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
