; ═══════════════════════════════════════════════════════════════════════════
;  UralCash ERP — Windows installer (Inno Setup 6)
;  Installs the app + publisher certificate, auto-installs the Visual C++
;  runtime if missing, and optionally downloads/installs PostgreSQL (server
;  machines only). Arabic RTL wizard.
;
;  Build:  "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer\UralCash.iss
;  Prereqs: build\windows\x64\runner\Release\  and  UralCash-PublicCert.cer
;           must exist (flutter build windows --release + sign_release.ps1).
; ═══════════════════════════════════════════════════════════════════════════

#define AppName       "UralCash ERP"
#define AppVersion    "3.1.1.246"
#define Publisher     "Monexia"
#define ExeName       "UralCash.exe"
#define ReleaseDir    "..\build\windows\x64\runner\Release"
#define CertFile      "..\build\windows\x64\runner\UralCash-PublicCert.cer"
#define IconFile      "..\windows\runner\resources\app_icon.ico"
#define VCRedistUrl   "https://aka.ms/vs/17/release/vc_redist.x64.exe"
; Official EDB PostgreSQL x64 installer (best-effort; download is fault-tolerant)
#define PGUrl         "https://get.enterprisedb.com/postgresql/postgresql-16.4-1-windows-x64.exe"

[Setup]
AppId={{9C4B2F1A-7E3D-4A6B-9F2C-1D8E5A0B3C77}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#Publisher}
AppPublisherURL=https://uralcash.app
DefaultDirName={autopf}\UralCash
DefaultGroupName=UralCash
DisableProgramGroupPage=yes
OutputDir=output
OutputBaseFilename=UralCash-Setup-{#AppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
WizardImageFile=assets\wizard-large.bmp
WizardSmallImageFile=assets\wizard-small.bmp
InfoBeforeFile=info-ar.txt
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
arabic.CompApp=نظام UralCash (أساسي)
arabic.CompPg=خادم PostgreSQL (للسيرفر/الفرع الرئيسي فقط — اختياري)
arabic.InstallingCert=جارٍ تثبيت شهادة الناشر في الجهات الموثوقة...
arabic.LaunchApp=تشغيل UralCash الآن
arabic.PreparingReqs=جارٍ تجهيز متطلبات النظام

[Components]
Name: "app";   Description: "{cm:CompApp}"; Types: full compact custom; Flags: fixed
Name: "pgsql"; Description: "{cm:CompPg}";  Types: full

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion; Components: app
Source: "{#CertFile}";     DestDir: "{app}"; Flags: ignoreversion;                                Components: app

[Icons]
Name: "{group}\UralCash";                       Filename: "{app}\{#ExeName}"
Name: "{group}\{cm:UninstallProgram,UralCash}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\UralCash";                 Filename: "{app}\{#ExeName}"; Tasks: desktopicon

[Run]
; Trust the publisher certificate so the signed exe stops warning "Unknown Publisher".
Filename: "{sys}\certutil.exe"; Parameters: "-addstore -f Root ""{app}\UralCash-PublicCert.cer"""; \
  StatusMsg: "{cm:InstallingCert}"; Flags: runhidden waituntilterminated
Filename: "{sys}\certutil.exe"; Parameters: "-addstore -f TrustedPublisher ""{app}\UralCash-PublicCert.cer"""; \
  StatusMsg: "{cm:InstallingCert}"; Flags: runhidden waituntilterminated
; Optional launch at the end.
Filename: "{app}\{#ExeName}"; Description: "{cm:LaunchApp}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\certutil.exe"; Parameters: "-delstore Root ""UralCash Code Signing (Monexia)"""; \
  Flags: runhidden; RunOnceId: "DelCertRoot"
Filename: "{sys}\certutil.exe"; Parameters: "-delstore TrustedPublisher ""UralCash Code Signing (Monexia)"""; \
  Flags: runhidden; RunOnceId: "DelCertPub"

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
