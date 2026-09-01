@echo off
REM ======================================================================
REM PicPos - build a standalone product from the shared codebase.
REM
REM NOTE: this file is intentionally ASCII-only. cmd.exe reads .bat files in
REM the OEM codepage, so UTF-8 comments (e.g. Arabic) corrupt the parser and
REM silently drop `set` lines - which produced a build with an empty
REM BINARY_NAME that still reported SUCCESS. Keep every .bat in English.
REM
REM The engine (accounting, inventory, treasury, sync) is shared with
REM UralCash. What differs: name, logo, colours, exe name, icon, data file.
REM
REM Three mechanisms, because each value is fixed in a different layer:
REM   --dart-define=APP_BRAND   -> Dart code (name, logo, colours)
REM   BRAND_* environment vars  -> CMake (exe name, exe file properties)
REM   icon file copy            -> Win32 resource (Runner.rc reads a fixed path)
REM
REM WARNING: build\windows is deleted first. The CMake cache remembers the
REM executable name, so building one brand after the other in the same
REM directory yields a mixed artifact. Cost: a full rebuild per brand switch.
REM ======================================================================

setlocal

set BRAND_ID=picpos
set BRAND_BINARY_NAME=PicPos
set BRAND_PRODUCT_NAME=PicPos
REM The legal entity shown in the exe file properties and the copyright line.
REM Confirmed by the product owner 2026-09-01: the registered form is exactly
REM "PicPos" - there is no fuller legal entity to carry here. Keep this in
REM step with `Publisher` in installer\setup.iss; they are the same fact
REM told to two different parts of Windows (file properties vs Add/Remove).
set BRAND_COMPANY_NAME=PicPos
set OUT_DIR=FlavorBuilds\PicPos

echo ============================================
echo   Building %BRAND_BINARY_NAME%
echo ============================================
echo.

REM Fail fast if the codepage mangled the variables above.
if "%BRAND_BINARY_NAME%"=="" (
    echo FAILED: BRAND_BINARY_NAME is empty - this script was parsed incorrectly.
    exit /b 1
)

REM --- 1) Verify brand isolation BEFORE building -------------------------
REM Catches any UralCash leak in the name, logo, colours or data file.
REM Failing here is far cheaper than discovering the mix after shipping.
echo [1/6] Verifying brand isolation...
call flutter test --dart-define=APP_BRAND=%BRAND_ID% test\unit\brand_picpos_test.dart
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo FAILED: brand isolation tests did not pass. Build aborted.
    exit /b 1
)

REM --- 2) Brand icon ----------------------------------------------------
echo [2/6] Applying %BRAND_ID% icon...
copy /Y "windows\runner\resources\app_icon_%BRAND_ID%.ico" "windows\runner\resources\app_icon.ico" >nul
if %ERRORLEVEL% NEQ 0 (
    echo FAILED: could not apply icon.
    exit /b 1
)

REM --- 3) Clean build directory ------------------------------------------
echo [3/6] Clearing build\windows (prevents mixed CMake cache)...
if exist "build\windows" rmdir /S /Q "build\windows"

REM --- 4) Build ---------------------------------------------------------
echo [4/6] Building...
call flutter build windows --release --dart-define=APP_BRAND=%BRAND_ID% --dart-define=APP_FLAVOR=unified
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo BUILD FAILED!
    exit /b 1
)

set EXE_PATH=build\windows\x64\runner\Release\%BRAND_BINARY_NAME%.exe
if not exist "%EXE_PATH%" (
    echo.
    echo FAILED: %BRAND_BINARY_NAME%.exe was not produced.
    echo Check that BRAND_BINARY_NAME reached CMake ^(windows\CMakeLists.txt^).
    exit /b 1
)

REM Guard against the other brand's executable being left in the output.
if exist "build\windows\x64\runner\Release\UralCash.exe" (
    echo.
    echo FAILED: UralCash.exe found in the PicPos output - mixed build.
    exit /b 1
)

REM --- 5) Force the SQLCipher engine into the bundle ---------------------
REM
REM WHY: package:sqlite3 ships a native-assets build hook that downloads a
REM PLAIN sqlite3.dll and the Flutter tool copies it next to the exe, where
REM it SHADOWS the SQLCipher dll that sqlcipher_flutter_libs provides. Both
REM are named sqlite3.dll and the native-assets copy lands last, so it wins.
REM
REM Measured 2026-08-30: the shipped sqlite3.dll was 1,665,536 bytes with
REM zero "sqlcipher" markers, and the live database file began with the
REM plaintext header "SQLite format 3". PRAGMA key does NOT fail on plain
REM sqlite3 - it is silently ignored - so nothing ever reported a problem,
REM while the audit dashboard showed a green hardcoded "encrypted" tick.
REM
REM Removing the direct sqlite3 dependency from pubspec.yaml is NOT enough:
REM drift pulls it transitively and the hook still runs. Verified by
REM building after the removal - the plain dll was still shipped.
REM
REM So: overwrite it here, then PROVE the result is SQLCipher. The runtime
REM guard in connection_io.dart (PRAGMA cipher_version) is the second layer;
REM it refuses to open an unencrypted database rather than trusting this.
echo [5/6] Enforcing SQLCipher engine...
set CIPHER_SRC=build\windows\x64\plugins\sqlcipher_flutter_libs\Release\sqlite3.dll
set SHIPPED_DLL=build\windows\x64\runner\Release\sqlite3.dll
if not exist "%CIPHER_SRC%" (
    echo FAILED: SQLCipher dll not found at %CIPHER_SRC%
    exit /b 1
)
copy /Y "%CIPHER_SRC%" "%SHIPPED_DLL%" >nul
if %ERRORLEVEL% NEQ 0 (
    echo FAILED: could not overwrite the shipped sqlite3.dll.
    exit /b 1
)
findstr /M /C:sqlcipher "%SHIPPED_DLL%" >nul
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo FAILED: the shipped sqlite3.dll is NOT SQLCipher.
    echo The database would be written in PLAINTEXT. Build aborted.
    exit /b 1
)
echo        OK - shipped sqlite3.dll carries the SQLCipher engine.

REM --- 6) Separate output directory --------------------------------------
echo [6/6] Copying to %OUT_DIR%...
if exist "%OUT_DIR%" rmdir /S /Q "%OUT_DIR%"
mkdir "%OUT_DIR%"
xcopy /E /Y /I /Q "build\windows\x64\runner\Release\*" "%OUT_DIR%\" >nul
if not exist "%OUT_DIR%\%BRAND_BINARY_NAME%.exe" (
    echo FAILED: copy to %OUT_DIR% did not produce the executable.
    exit /b 1
)

echo.
echo ============================================
echo   SUCCESS
echo   %OUT_DIR%\%BRAND_BINARY_NAME%.exe
echo ============================================

endlocal
