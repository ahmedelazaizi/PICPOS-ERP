@echo off
REM ----------------------------------------------------------------------
REM UralCash - single unified release build (Phase E)
REM
REM After the runtime business-profile migration (Phases A-D), the project
REM no longer needs per-flavor binaries. The active profile + feature
REM overrides are chosen by the developer in the setup wizard / developer
REM tools and stored in the database. One build serves every customer.
REM
REM --dart-define=APP_FLAVOR=unified stays as a compile-time fallback for
REM the very first boot before the settings table has a business_profile
REM row -- giving the wizard a sane "all features visible" starting point.
REM ----------------------------------------------------------------------

REM ----------------------------------------------------------------------
REM UralCash brand identity - set explicitly on purpose.
REM
REM These match the CMake defaults, so in theory they are redundant. In
REM practice they are required: build_picpos.bat copies the PicPos icon over
REM app_icon.ico, so without restoring it here a UralCash build that follows
REM a PicPos build would ship the PicPos icon. Every brand script must set
REM its identity in full and never assume a clean previous state.
REM
REM NOTE: keep this file ASCII-only - cmd.exe reads .bat in the OEM codepage
REM and UTF-8 comments corrupt the parser, silently dropping `set` lines.
REM ----------------------------------------------------------------------
set BRAND_ID=uralcash
set BRAND_BINARY_NAME=UralCash
set BRAND_PRODUCT_NAME=UralCash ERP
set BRAND_COMPANY_NAME=Monexia

if "%BRAND_BINARY_NAME%"=="" (
    echo FAILED: BRAND_BINARY_NAME is empty - this script was parsed incorrectly.
    exit /b 1
)

echo Building UralCash (single unified release)...
echo =============================================

echo Applying %BRAND_ID% icon...
copy /Y "windows\runner\resources\app_icon_%BRAND_ID%.ico" "windows\runner\resources\app_icon.ico" >nul

REM Same reason as build_picpos.bat: the CMake cache remembers the executable
REM name, so switching brands without clearing produces a mixed artifact.
echo Clearing build\windows (prevents mixed CMake cache)...
if exist "build\windows" rmdir /S /Q "build\windows"

REM `call` is REQUIRED: `flutter` on Windows is flutter.bat, and invoking a
REM batch file from a batch file WITHOUT `call` transfers control permanently
REM and never returns. This script used to omit it, so everything below --
REM including the copy to FlavorBuilds\Unified -- never ran, while the script
REM still exited 0 (it inherited flutter.bat's exit code). The build output
REM was correct; the published folder silently kept an older copy.
call flutter build windows --dart-define=APP_FLAVOR=unified --dart-define=APP_BRAND=%BRAND_ID% --release
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo BUILD FAILED!
    exit /b 1
)

set EXE_PATH=build\windows\x64\runner\Release\%BRAND_BINARY_NAME%.exe
if not exist "%EXE_PATH%" (
    echo.
    echo FAILED: %BRAND_BINARY_NAME%.exe was not produced.
    exit /b 1
)

REM Guard against the other brand's executable being left in the output.
if exist "build\windows\x64\runner\Release\PicPos.exe" (
    echo.
    echo FAILED: PicPos.exe found in the UralCash output - mixed build.
    exit /b 1
)

echo.
echo SUCCESS! Build complete.
echo Output: build\windows\x64\runner\Release\

REM Replace the published folder wholesale. Copying into an existing folder
REM leaves orphaned files from previous builds (e.g. a renamed executable).
if exist "FlavorBuilds\Unified" rmdir /S /Q "FlavorBuilds\Unified"
mkdir "FlavorBuilds\Unified"
xcopy /E /Y /I /Q "build\windows\x64\runner\Release\*" "FlavorBuilds\Unified\" >nul
if not exist "FlavorBuilds\Unified\%BRAND_BINARY_NAME%.exe" (
    echo FAILED: copy to FlavorBuilds\Unified did not produce the executable.
    exit /b 1
)
echo Copied to FlavorBuilds\Unified\
