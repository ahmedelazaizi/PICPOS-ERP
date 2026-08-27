; ═══════════════════════════════════════════════════════════════════════════
;  Windows installer (Inno Setup 6) — one script, one installer per brand.
;  Installs the app + publisher certificate, auto-installs the Visual C++
;  runtime if missing, and optionally downloads/installs PostgreSQL (server
;  machines only). Arabic RTL wizard.
;
;  Build (UralCash — the default, unchanged):
;    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer\UralCash.iss
;  Build (PicPos):
;    ISCC.exe /DBrandId=picpos installer\UralCash.iss
;    (or just run build_installer_picpos.bat)
;
;  Prereq: build\windows\x64\runner\Release\ must exist for the brand you are
;  packaging — that directory is produced by `flutter build windows --release`
;  with the matching --dart-define=APP_BRAND. Building one brand's installer
;  over the other brand's Release output produces a MIXED package; the
;  [Files] guard below fails the compile if the expected exe is missing.
;
;  The publisher certificate is OPTIONAL: if the .cer is absent the cert
;  install/uninstall steps are compiled out entirely. PicPos has no signing
;  certificate yet, and UralCash's cert is produced out-of-tree.
;
;  Everything brand-bound lives in the one block below. Nothing anywhere else
;  in this file may name a brand.
; ═══════════════════════════════════════════════════════════════════════════

; The brand being packaged. Defaults to `uralcash` so an old, bare
; `ISCC installer\UralCash.iss` keeps producing exactly what it always did.
#ifndef BrandId
  #define BrandId "uralcash"
#endif

#if BrandId == "uralcash"

  ; ── UralCash — every value below is LITERAL AND FROZEN ─────────────────
  ; AppId identifies the product to Windows' installed-programs database.
  ; It is the one value that must never change for a shipped product: a new
  ; AppId makes every existing install invisible to the upgrade path, so the
  ; next setup installs alongside the old one instead of replacing it.
  #define AppId        "{{9C4B2F1A-7E3D-4A6B-9F2C-1D8E5A0B3C77}"
  #define AppName      "UralCash ERP"
  #define ShortName    "UralCash"
  #define Publisher    "Monexia"
  #define PublisherURL "https://uralcash.app"
  #define ExeName      "UralCash.exe"
  #define CertName     "UralCash-PublicCert.cer"
  ; Subject of the code-signing cert, as passed to `certutil -delstore`.
  #define CertSubject  "UralCash Code Signing (Monexia)"

#elif BrandId == "picpos"

  ; ── PicPos ────────────────────────────────────────────────────────────
  ; A DIFFERENT AppId, generated fresh. Reusing UralCash's would make
  ; Windows treat the two products as one: installing PicPos would silently
  ; upgrade-over an existing UralCash install, and uninstalling either would
  ; remove the other's registry entry. This single value is the difference
  ; between two products and one product with two skins.
  #define AppId        "{{6700CCE0-EF37-4843-A057-F7799252DAA9}"
  #define AppName      "PicPos ERP"
  #define ShortName    "PicPos"
  ; TODO(product owner): if PicPos is registered under a fuller legal name,
  ; put that exact form here — this string is the publisher shown by Windows.
  ; Same open question as the copyright line in build_picpos.bat.
  #define Publisher    "PicPos"
  ; TODO(product owner): no domain yet. Left empty on purpose — the [Setup]
  ; directive is omitted rather than pointed at UralCash's site.
  #define PublisherURL ""
  #define ExeName      "PicPos.exe"
  #define CertName     "PicPos-PublicCert.cer"
  #define CertSubject  "PicPos Code Signing (PicPos)"

#else
  #error Unknown BrandId. Use /DBrandId=uralcash or /DBrandId=picpos.
#endif

; ── Shared across brands — same engine, same release train ───────────────
;
; ⚠️ MUST track `pubspec.yaml`'s `version:` — `3.1.3+248` becomes `3.1.3.248`
;    (Inno wants four dotted numerals; pubspec's `+build` is the fourth).
;
; 🔴 Drifted once and shipped a lie: pubspec was bumped to 3.1.3+248 on
;    2026-08-03 ("نظافة الإصدار") while this line was last touched
;    2026-07-26, so the installer labelled a 3.1.3+248 build as 3.1.2.247.
;    Nothing reads pubspec from here — Inno never sees Dart — so the only
;    thing keeping the two in step is this comment and the guard test
;    `test/static/installer_version_matches_pubspec_test.dart`.
;
;    Why it matters beyond cosmetics: Inno uses AppVersion for upgrade
;    detection and it is what Add/Remove Programs shows. A stale number
;    means support cannot tell which build a customer is running, and two
;    different builds can claim the same version.
#define AppVersion    "3.1.3.248"

; ── Brand-derived paths — no brand names below this line ─────────────────
#define ReleaseDir    "..\build\windows\x64\runner\Release"
#define CertFile      "..\build\windows\x64\runner\" + CertName
#define IconFile      "..\windows\runner\resources\app_icon.ico"
#define InfoFile      "info-ar-" + BrandId + ".txt"
#define WizardLarge   "assets\wizard-large-" + BrandId + ".bmp"
#define WizardSmall   "assets\wizard-small-" + BrandId + ".bmp"
#define VCRedistUrl   "https://aka.ms/vs/17/release/vc_redist.x64.exe"
; Official EDB PostgreSQL x64 installer (best-effort; download is fault-tolerant)
#define PGUrl         "https://get.enterprisedb.com/postgresql/postgresql-16.4-1-windows-x64.exe"

; Guard against packaging the wrong brand's build output. Without this the
; compile succeeds and ships an installer whose shortcuts point at an exe
; that isn't in the package.
#if !FileExists(AddBackslash(SourcePath) + ReleaseDir + "\" + ExeName)
  #error Release output for this brand is missing. Run the brand's build script first.
#endif

; The signing certificate is optional — see the header.
#if FileExists(AddBackslash(SourcePath) + CertFile)
  #define HaveCert
#endif

[Setup]
AppId={#AppId}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#Publisher}
#if PublisherURL != ""
AppPublisherURL={#PublisherURL}
#endif
DefaultDirName={autopf}\{#ShortName}
DefaultGroupName={#ShortName}
DisableProgramGroupPage=yes
OutputDir=output
OutputBaseFilename={#ShortName}-Setup-{#AppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
WizardImageFile={#WizardLarge}
WizardSmallImageFile={#WizardSmall}
InfoBeforeFile={#InfoFile}
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#ExeName}
#if FileExists(AddBackslash(SourcePath) + IconFile)
SetupIconFile={#IconFile}
#endif

[Languages]
Name: "arabic"; MessagesFile: "compiler:Languages\Arabic.isl"

[CustomMessages]
arabic.CompApp=نظام {#ShortName} (أساسي)
arabic.CompPg=خادم PostgreSQL (للسيرفر/الفرع الرئيسي فقط — اختياري)
arabic.InstallingCert=جارٍ تثبيت شهادة الناشر في الجهات الموثوقة...
arabic.LaunchApp=تشغيل {#ShortName} الآن
arabic.PreparingReqs=جارٍ تجهيز متطلبات النظام

[Components]
Name: "app";   Description: "{cm:CompApp}"; Types: full compact custom; Flags: fixed
Name: "pgsql"; Description: "{cm:CompPg}";  Types: full

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion; Components: app
#ifdef HaveCert
Source: "{#CertFile}";     DestDir: "{app}"; Flags: ignoreversion;                                Components: app
#endif

[Icons]
Name: "{group}\{#ShortName}";                       Filename: "{app}\{#ExeName}"
Name: "{group}\{cm:UninstallProgram,{#ShortName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#ShortName}";                 Filename: "{app}\{#ExeName}"; Tasks: desktopicon

[Run]
#ifdef HaveCert
; Trust the publisher certificate so the signed exe stops warning "Unknown Publisher".
Filename: "{sys}\certutil.exe"; Parameters: "-addstore -f Root ""{app}\{#CertName}"""; \
  StatusMsg: "{cm:InstallingCert}"; Flags: runhidden waituntilterminated
Filename: "{sys}\certutil.exe"; Parameters: "-addstore -f TrustedPublisher ""{app}\{#CertName}"""; \
  StatusMsg: "{cm:InstallingCert}"; Flags: runhidden waituntilterminated
#endif
; Optional launch at the end.
Filename: "{app}\{#ExeName}"; Description: "{cm:LaunchApp}"; Flags: nowait postinstall skipifsilent

#ifdef HaveCert
[UninstallRun]
Filename: "{sys}\certutil.exe"; Parameters: "-delstore Root ""{#CertSubject}"""; \
  Flags: runhidden; RunOnceId: "DelCertRoot"
Filename: "{sys}\certutil.exe"; Parameters: "-delstore TrustedPublisher ""{#CertSubject}"""; \
  Flags: runhidden; RunOnceId: "DelCertPub"
#endif

[Code]
var
  DownloadPage: TDownloadWizardPage;
  NeedVC, NeedPG: Boolean;

{ True if the VC++ 2015-2022 x64 runtime is already registered. }
function VCRedistInstalled(): Boolean;
var
  v: Cardinal;
begin
  Result := RegQueryDWordValue(HKLM64,
    'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'Installed', v) and (v >= 1);
end;

procedure InitializeWizard();
begin
  DownloadPage := CreateDownloadPage(SetupMessage(msgWizardPreparing),
    ExpandConstant('{cm:PreparingReqs}'), nil);
end;

{ On the Ready page, download whatever prerequisites are needed. Fault-tolerant:
  a failed download never blocks the install — the missing piece is handled (or
  reported) at the post-install step. }
function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if CurPageID = wpReady then
  begin
    NeedVC := not VCRedistInstalled();
    NeedPG := WizardIsComponentSelected('pgsql');
    if NeedVC or NeedPG then
    begin
      DownloadPage.Clear;
      if NeedVC then
        DownloadPage.Add('{#VCRedistUrl}', 'vc_redist.x64.exe', '');
      if NeedPG then
        DownloadPage.Add('{#PGUrl}', 'postgresql-x64.exe', '');
      DownloadPage.Show;
      try
        try
          DownloadPage.Download;
        except
          SuppressibleMsgBox('تعذّر تنزيل أحد المتطلبات:' + #13#10 +
            AddPeriod(GetExceptionMessage) + #13#10 +
            'سيكمل التثبيت؛ ثبّت المتطلب الناقص يدوياً لاحقاً.',
            mbError, MB_OK, IDOK);
        end;
      finally
        DownloadPage.Hide;
      end;
    end;
  end;
end;

{ After files are copied: silently install VC++ (if it was missing) and launch
  the interactive PostgreSQL installer (if the server component was chosen —
  the admin sets the port and superuser password there; we never embed one). }
procedure CurStepChanged(CurStep: TSetupStep);
var
  rc: Integer;
  f: String;
begin
  if CurStep = ssPostInstall then
  begin
    if NeedVC then
    begin
      f := ExpandConstant('{tmp}\vc_redist.x64.exe');
      if FileExists(f) then
        Exec(f, '/install /quiet /norestart', '', SW_SHOW, ewWaitUntilTerminated, rc)
      else
        SuppressibleMsgBox('لم يُنزَّل وقت تشغيل Visual C++.' + #13#10 +
          'إن لم يبدأ البرنامج، ثبّته من:' + #13#10 +
          'https://aka.ms/vs/17/release/vc_redist.x64.exe',
          mbInformation, MB_OK, IDOK);
    end;
    if NeedPG then
    begin
      f := ExpandConstant('{tmp}\postgresql-x64.exe');
      if FileExists(f) then
        Exec(f, '', '', SW_SHOW, ewWaitUntilTerminated, rc)
      else
        SuppressibleMsgBox('لم يُنزَّل مثبّت PostgreSQL.' + #13#10 +
          'نزّله يدوياً من موقع EDB إن احتجت تشغيل الجهاز كخادم.',
          mbInformation, MB_OK, IDOK);
    end;
  end;
end;
