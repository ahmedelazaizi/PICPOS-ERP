; ═══════════════════════════════════════════════════════════════════════════
;  Windows installer (Inno Setup 6) — one script, one installer per brand.
;  Installs the app, auto-installs the Visual C++ runtime if missing, and
;  optionally downloads/installs PostgreSQL (server machines only). Arabic
;  RTL wizard. Every downloaded prerequisite is SHA-256 verified before it is
;  executed (see "Pinned prerequisites" below).
;
;  Build (PicPos — the live product):
;    ISCC.exe /DBrandId=picpos installer\setup.iss
;    (or just run build_installer_picpos.bat)
;  Build (UralCash — work is halted; kept compiling so the script stays honest):
;    ISCC.exe /DBrandId=uralcash installer\setup.iss
;
;  The brand is MANDATORY. See the #ifndef below for why there is no default.
;
;  Prereq: build\windows\x64\runner\Release\ must exist for the brand you are
;  packaging — that directory is produced by `flutter build windows --release`
;  with the matching --dart-define=APP_BRAND. Building one brand's installer
;  over the other brand's Release output produces a MIXED package; the
;  [Files] guard below fails the compile if the expected exe is missing.
;
;  CERTIFICATES (security finding B-01, decision 2026-10): this installer NEVER
;  adds any certificate to the client machine's trust stores - not Root, not
;  TrustedPublisher. Trusting a self-signed publisher cert as a Root CA lets
;  whoever holds its private key mint trusted code (and possibly TLS certs) on
;  every customer PC. The proper fix is a real Authenticode certificate.
;
;  SIGNING (B-02) is OPTIONAL and off by default. Pass /DSignInstaller=1 plus
;  /Spicpossign="<command> $f" to ISCC to sign the installer and uninstaller;
;  build_installer_picpos.bat does this only when PICPOS_SIGN_PFX or
;  PICPOS_SIGN_THUMBPRINT is set. Without them the build is simply unsigned.
;
;  Everything brand-bound lives in the one block below. Nothing anywhere else
;  in this file may name a brand.
; ═══════════════════════════════════════════════════════════════════════════

; The brand being packaged — REQUIRED, no default.
;
; ⚠️ This used to default to `uralcash`, from a time when UralCash was the only
;    product. PicPos is the live product now and UralCash work is halted, so a
;    silent default is worse than useless: a bare `ISCC installer\setup.iss`
;    would quietly package the WRONG brand's metadata (AppId, publisher, name)
;    around whatever Release output happens to be on disk. The [Files] guard
;    below catches only the case where the expected exe is missing entirely —
;    it cannot catch a UralCash-labelled package built over a UralCash build.
;
;    Flipping the default to `picpos` would just move the trap. Requiring the
;    brand removes it: every caller states which product it is packaging, and
;    the compile fails loudly if it doesn't.
#ifndef BrandId
  #error BrandId is required. Pass /DBrandId=picpos (or /DBrandId=uralcash).
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
  ; Confirmed by the product owner 2026-09-01: the registered form is exactly
  ; "PicPos" — no fuller legal entity to carry. This is the publisher string
  ; Windows shows in Add/Remove Programs and in the UAC prompt.
  #define Publisher    "PicPos"
  ; No domain yet (owner, 2026-09-01). Left empty on purpose — the [Setup]
  ; directive is omitted rather than pointed at UralCash's site.
  #define PublisherURL ""
  #define ExeName      "PicPos.exe"


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
#define AppVersion    "3.9.2.277"

; ── Brand-derived paths — no brand names below this line ─────────────────
#define ReleaseDir    "..\build\windows\x64\runner\Release"
#define IconFile      "..\windows\runner\resources\app_icon.ico"
#define InfoFile      "info-ar-" + BrandId + ".txt"

; ── صورُ المعالج ──────────────────────────────────────────────────────────
;
; Inno 6 يختار الصورةَ بمطابقة مقاسها لنسبة تكبير الشاشة، ويقبل قائمةً
; مفصولةً بفواصل. وصورةٌ واحدةٌ عند ١٦٤×٣١٤ تُمطُّ على شاشات ١٥٠٪ و٢٠٠٪ —
; وهي الأغلبُ اليومَ — فتظهر ضبابيّةً في أوّلِ ما يراه العميل.
;
; المقاساتُ الأربعةُ يولّدها `tool/gen_installer_art.dart` بمحرّك Flutter
; (‏`flutter test tool/gen_installer_art.dart`). ولا يولّدها المولّدُ القديم
; `make_wizard_images.py`: فذاك يرسم بـPillow، وPillow لا تشكّل العربيّةَ ولا
; تعكس اتّجاهَها — فبقيت صورةُ PicPos بلا سطرٍ عربيٍّ هرباً من العطب.
;
; ⚠️ UralCash ما زال على صورتَيه المشحونتَين بمقاسٍ واحد. لا تُدرج له
;    لواحقَ لا وجودَ لها: Inno يفشل بالترجمة على ملفٍّ مفقود.
#if BrandId == "picpos"
  #define WizardLarge "assets\wizard-large-picpos.bmp,assets\wizard-large-picpos-125.bmp,assets\wizard-large-picpos-150.bmp,assets\wizard-large-picpos-200.bmp"
  #define WizardSmall "assets\wizard-small-picpos.bmp,assets\wizard-small-picpos-125.bmp,assets\wizard-small-picpos-150.bmp,assets\wizard-small-picpos-200.bmp"
#else
  #define WizardLarge "assets\wizard-large-" + BrandId + ".bmp"
  #define WizardSmall "assets\wizard-small-" + BrandId + ".bmp"
#endif

; -- Pinned prerequisites (security finding B-03) ---------------------------
; Nothing downloaded is executed unless its SHA-256 matches the value below;
; a mismatch deletes the file and blocks the installation (see
; NextButtonClick). A download that merely fails (offline) stays tolerated -
; nothing is executed in that case.
;
; VC++ redist: aka.ms/vs/17/release/vc_redist.x64.exe is Microsoft's "latest"
;   link, so the bytes change whenever Microsoft ships a new redist. Pinned
;   2026-10 to 14.44.35211.0 (25,635,768 bytes), downloaded from the official
;   URL, Authenticode status Valid, signer CN=Microsoft Corporation.
;   WHEN MICROSOFT UPDATES IT the installer will refuse with the hash-mismatch
;   message: re-download, check the signature, recompute with
;   Get-FileHash -Algorithm SHA256, and update VCRedistSha256
;   (see docs/security/release-integrity.md).
; PostgreSQL: version-pinned URL (16.4-1), 374,221,136 bytes, Authenticode
;   Valid, signer CN=EnterpriseDB Corporation. Hash computed from the official
;   download; NOT cross-checked against a checksum published by EDB.
;   EMBEDDED since 2026-10: the exe is no longer downloaded by the installer. It
;   is placed in installer\prereqs\ by tool\fetch_prereqs.ps1 (SHA-256 +
;   Authenticode checked, git-ignored) and compiled into the setup; at install
;   time it is extracted to {tmp} and its hash is checked again before running.
#define VCRedistFile   "prereqs\vc_redist.x64.exe"
#define VCRedistSha256 "cc0ff0eb1dc3f5188ae6300faef32bf5beeba4bdd6e8e445a9184072096b713b"
#define PGUrl          "https://get.enterprisedb.com/postgresql/postgresql-16.4-1-windows-x64.exe"
#define PGSha256       "f4bf0ac4b33471f18aad7d1d9cc52613003f3a3a612aae167366bf7f7840b2bc"

; Guard against packaging the wrong brand's build output. Without this the
; compile succeeds and ships an installer whose shortcuts point at an exe
; that isn't in the package.
#if !FileExists(AddBackslash(SourcePath) + ReleaseDir + "\" + ExeName)
  #error Release output for this brand is missing. Run the brand's build script first.
#endif
#if !FileExists(AddBackslash(SourcePath) + VCRedistFile)
  #error installer\prereqs\vc_redist.x64.exe is missing. Run: powershell -ExecutionPolicy Bypass -File tool\fetch_prereqs.ps1
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
#ifdef SignInstaller
; Defined on the ISCC command line (/Spicpossign=...) by build_installer_picpos.bat
; only when a signing identity is configured through environment variables.
SignTool=picpossign
SignedUninstaller=yes
#endif
WizardStyle=modern
WizardImageFile={#WizardLarge}
WizardSmallImageFile={#WizardSmall}
; اللوحةُ الجانبيّةُ تملأ الارتفاعَ بدل شريطٍ في الأعلى — هي الفرقُ بين
; «مثبِّتٍ افتراضيّ» و«منتَجٍ له هويّة».
WizardImageStretch=yes
; ١٢٠٪ من المقاس الافتراضيّ. المعالجُ الافتراضيُّ ضيّقٌ على نصٍّ عربيٍّ طويل،
; والاتّساعُ يمنع التفافَ الأسطر في صفحتَي المعلومات والمكوّنات.
WizardSizePercent=120
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
arabic.PreparingReqs=جارٍ تجهيز متطلبات النظام

; ── الجسرُ إلى معالج البدء ────────────────────────────────────────────────
;
; ⚠️ **المثبِّتُ لا يسأل سؤالاً تجاريّاً واحداً** — لا نمطَ عملٍ ولا بياناتِ
;    شركةٍ ولا فروعاً ولا مستخدمين. تلك كلُّها يملكها معالجُ البدء داخلَ
;    التطبيق، وهو مبنيٌّ بلغة PicPos البصريّة ومختبَرٌ ويقرأ إعدادَ
;    `setup_completed` عند الإقلاع فيفتح نفسَه إن كان فارغاً.
;
;    فوظيفةُ هذه الصفحة أن تكون **عتبةً لا نهاية**: تقول للعميل إنّ ما انتهى
;    هو تجهيزُ الملفّات، وإنّ إعدادَ النظام يبدأ الآن. وبلا هذا يظنّ العميلُ
;    أنّ «تمّ التثبيت» تعني أنّ النظامَ جاهزٌ للعمل، فيغلق ثمّ يفتح فيفاجَأ
;    بمعالجٍ لم يتوقّعه.
arabic.LaunchApp=ابدأ إعداد النظام الآن
arabic.FinishedHeading=تمّ تجهيز {#ShortName} على هذا الجهاز
arabic.FinishedLabel=نُسخت ملفات النظام وجُهّزت متطلباته.%n%nالخطوة التالية هي إعداد النظام نفسه: نمط العمل، وبيانات المنشأة، والفروع، والمستخدمون، ودليل الحسابات — ويتولاها معالج الإعداد داخل البرنامج.%n%nاترك الخيار أدناه مفعّلاً ليبدأ المعالج فور إغلاق هذه النافذة.

[Components]
Name: "app";   Description: "{cm:CompApp}"; Types: full compact custom; Flags: fixed
Name: "pgsql"; Description: "{cm:CompPg}";  Types: full

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion; Components: app
; Embedded VC++ redist: not copied to the target; extracted to {tmp} on demand.
Source: "{#VCRedistFile}"; DestName: "vc_redist.x64.exe"; Flags: dontcopy

[Icons]
Name: "{group}\{#ShortName}";                       Filename: "{app}\{#ExeName}"
Name: "{group}\{cm:UninstallProgram,{#ShortName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#ShortName}";                 Filename: "{app}\{#ExeName}"; Tasks: desktopicon

[Run]
; No certificate is installed into any trust store (B-01) - see the header.
; Optional launch at the end.
Filename: "{app}\{#ExeName}"; Description: "{cm:LaunchApp}"; Flags: nowait postinstall skipifsilent

[Code]

{ ── هويّةُ العلامة داخلَ نافذة المعالج ──────────────────────────────────────

  ⚠️ **مصيدةُ ترتيب القنوات**: `TColor` في Delphi هو `$00BBGGRR` لا `$00RRGGBB`
     — أي **معكوسٌ** عن ترميز CSS الذي تُكتب به ألوانُ العلامة. فـ`#0250D3`
     يصير `$00D35002` لا `$000250D3`. وكتابتُه بترتيب CSS تُنتج لوناً آخرَ
     تماماً يمرُّ بلا خطأِ ترجمةٍ ولا يلاحظه أحدٌ إلّا بالعين.

  والقيمُ مأخوذةٌ من `lib/core/theme/app_colors.dart` — نفسُ اللون الذي يراه
  العميلُ في التطبيق بعد لحظات. }
const
  BrandDark  = $00582201;  { #012258 }
  BrandMid   = $00D35002;  { #0250D3 }
  BrandWhite = $00FFFFFF;

var
  DownloadPage: TDownloadWizardPage;
  NeedVC, NeedPG: Boolean;

{ يصبغ شريطَ الرأس بلون العلامة ويجعل نصَّه أبيض.

  ⚠️ **الرأسُ وحدَه، لا الأزرار**: أزرارُ Inno عناصرُ Win32 أصليّةٌ ترسمها
     ثيمةُ ويندوز، فضبطُ لونِ خلفيّتها يُقبَل بلا خطأٍ **ولا يُرسَم**. ومحاولةُ
     رسمها يدويّاً تكسر حالاتِ التعطيل والتركيز. فنكتفي بما يُرسَم فعلاً.

  ⚠️ **ونصبغ المقدّمةَ والخلفيّةَ معاً دائماً**: ضبطُ الخلفيّة وحدَها يُنتج
     نصّاً أسودَ على أزرقَ غامقٍ في ثيمةٍ فاتحة، وأبيضَ على أبيضَ في الغامقة. }
procedure ApplyBrandChrome();
begin
  WizardForm.MainPanel.Color := BrandDark;
  WizardForm.PageNameLabel.Font.Color := BrandWhite;
  WizardForm.PageDescriptionLabel.Font.Color := BrandWhite;
  WizardForm.PageNameLabel.Font.Style := [fsBold];

  { ⚠️ `Bevel1` هو الخطُّ الرماديُّ **تحت شريط الرأس**، و`Bevel` خطٌّ آخرُ فوق
       صفِّ الأزرار في الأسفل. المطلوبُ إخفاءُ الأوّل وحدَه: خطٌّ رماديٌّ تحت
       شريطٍ أزرقَ غامقٍ يقطعه، والثاني يفصل الأزرارَ ووجودُه صحيح. وخلطُهما
       يُنتج نافذةً بلا فاصلٍ للأزرار وبخطٍّ نافرٍ تحت الرأس — عكسُ المقصود. }
  WizardForm.Bevel1.Visible := False;

  WizardForm.WelcomeLabel1.Font.Color := BrandDark;
  WizardForm.WelcomeLabel1.Font.Style := [fsBold];
  WizardForm.FinishedHeadingLabel.Font.Color := BrandDark;
  WizardForm.FinishedHeadingLabel.Font.Style := [fsBold];
end;

{ True if the VC++ 2015-2022 x64 runtime is already registered. }
function VCRedistInstalled(): Boolean;
var
  v: Cardinal;
begin
  Result := RegQueryDWordValue(HKLM64,
    'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'Installed', v) and (v >= 1);
end;

{ True when `F` is absent (nothing to execute) or its SHA-256 equals `Expected`.
  On a mismatch the file is deleted so it can never be run by accident. }
function PrereqHashOk(const F, Expected: String): Boolean;
begin
  Result := True;
  if FileExists(F) then
    if CompareText(GetSHA256OfFile(F), Expected) <> 0 then
    begin
      DeleteFile(F);
      Result := False;
    end;
end;

procedure InitializeWizard();
begin
  DownloadPage := CreateDownloadPage(SetupMessage(msgWizardPreparing),
    ExpandConstant('{cm:PreparingReqs}'), nil);
  ApplyBrandChrome();
end;

{ صفحةُ النهاية ليست نهايةً بل **عتبة**: ما انتهى هو تجهيزُ الملفّات، وإعدادُ
  النظام يبدأ في معالج البدء داخلَ التطبيق. وبلا هذا النصّ يظنّ العميلُ أنّ
  «تمّ التثبيت» تعني أنّ النظامَ جاهزٌ للعمل.

  ⚠️ ويُضبَط في `CurPageChanged` لا في `[Messages]`: Inno يعيد بناءَ نصِّ هذه
     الصفحة عند عرضها، فأيُّ ضبطٍ أبكرَ يُدهَس. }
procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpFinished then
  begin
    WizardForm.FinishedHeadingLabel.Caption :=
      ExpandConstant('{cm:FinishedHeading}');
    WizardForm.FinishedLabel.Caption := ExpandConstant('{cm:FinishedLabel}');
  end;
end;

{ On the Ready page, download whatever prerequisites are needed. A download that
  FAILS (offline) never blocks the install - the missing piece is reported at
  the post-install step. A download that arrives with the WRONG SHA-256 blocks
  the install (B-03): the file is deleted and nothing is executed. }
function NextButtonClick(CurPageID: Integer): Boolean;
var
  vcFile, pgFile: String;
begin
  Result := True;
  if CurPageID = wpReady then
  begin
    NeedVC := not VCRedistInstalled();
    NeedPG := WizardIsComponentSelected('pgsql');
    vcFile := ExpandConstant('{tmp}\vc_redist.x64.exe');
    pgFile := ExpandConstant('{tmp}\postgresql-x64.exe');
    { VC++ is embedded: extract only when it is actually needed, verify the hash. }
    if NeedVC then
    begin
      DeleteFile(vcFile);
      ExtractTemporaryFile('vc_redist.x64.exe');
      if not PrereqHashOk(vcFile, '{#VCRedistSha256}') then
      begin
        MsgBox('فشل التحقق من سلامة ملف Visual C++ المضمَّن في المثبّت (بصمة SHA-256 لا تطابق المتوقعة).' + #13#10 +
          'حُذف الملف ولم يُنفَّذ، وأُوقف التثبيت حمايةً لجهازك.' + #13#10 +
          'قد يكون ملف المثبّت تالفًا أو معدَّلًا؛ نزّل المثبّت من جديد من القناة الرسمية وتحقق من بصمته، أو أبلغ الدعم الفني.',
          mbCriticalError, MB_OK);
        Result := False;
        Exit;
      end;
    end;
    if NeedPG then
    begin
      DeleteFile(pgFile);
      DownloadPage.Clear;
      DownloadPage.Add('{#PGUrl}', 'postgresql-x64.exe', '');
      DownloadPage.Show;
      try
        try
          DownloadPage.Download;
        except
          SuppressibleMsgBox('تعذّر تنزيل مثبّت PostgreSQL:' + #13#10 +
            AddPeriod(GetExceptionMessage) + #13#10 +
            'سيكمل التثبيت؛ ثبّت PostgreSQL يدوياً لاحقاً.',
            mbError, MB_OK, IDOK);
        end;
      finally
        DownloadPage.Hide;
      end;
      if not PrereqHashOk(pgFile, '{#PGSha256}') then
      begin
        MsgBox('فشل التحقق من سلامة مثبّت PostgreSQL المنزَّل (بصمة SHA-256 لا تطابق المتوقعة).' + #13#10 +
          'حُذف الملف ولم يُنفَّذ، وأُوقف التثبيت حمايةً لجهازك.' + #13#10 +
          'أبلغ الدعم الفني، أو ألغِ اختيار مكوّن PostgreSQL وثبّته يدوياً من موقع EDB.',
          mbCriticalError, MB_OK);
        Result := False;
        Exit;
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
      if FileExists(f) and PrereqHashOk(f, '{#VCRedistSha256}') then
        Exec(f, '/install /quiet /norestart', '', SW_SHOW, ewWaitUntilTerminated, rc)
      else
        SuppressibleMsgBox('تعذّر تثبيت وقت تشغيل Visual C++ المضمَّن.' + #13#10 +
          'إن لم يبدأ البرنامج، ثبّته يدوياً من موقع مايكروسوفت (vc_redist.x64.exe).',
          mbInformation, MB_OK, IDOK);
    end;
    if NeedPG then
    begin
      f := ExpandConstant('{tmp}\postgresql-x64.exe');
      if FileExists(f) and PrereqHashOk(f, '{#PGSha256}') then
        Exec(f, '', '', SW_SHOW, ewWaitUntilTerminated, rc)
      else
        SuppressibleMsgBox('لم يُنزَّل مثبّت PostgreSQL.' + #13#10 +
          'نزّله يدوياً من موقع EDB إن احتجت تشغيل الجهاز كخادم.',
          mbInformation, MB_OK, IDOK);
    end;
  end;
end;
