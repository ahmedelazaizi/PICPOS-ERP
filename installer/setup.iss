; ═══════════════════════════════════════════════════════════════════════════
;  Windows installer (Inno Setup 6) — one script, one installer per brand.
;  Installs the app + publisher certificate, auto-installs the Visual C++
;  runtime if missing, and optionally downloads/installs PostgreSQL (server
;  machines only). Arabic RTL wizard.
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
;  The publisher certificate is OPTIONAL: if the .cer is absent the cert
;  install/uninstall steps are compiled out entirely. PicPos has no signing
;  certificate yet, and UralCash's cert is produced out-of-tree.
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
  ; Confirmed by the product owner 2026-09-01: the registered form is exactly
  ; "PicPos" — no fuller legal entity to carry. This is the publisher string
  ; Windows shows in Add/Remove Programs and in the UAC prompt.
  #define Publisher    "PicPos"
  ; No domain yet (owner, 2026-09-01). Left empty on purpose — the [Setup]
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
#define AppVersion    "3.2.3.266"

; ── Brand-derived paths — no brand names below this line ─────────────────
#define ReleaseDir    "..\build\windows\x64\runner\Release"
#define CertFile      "..\build\windows\x64\runner\" + CertName
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
arabic.InstallingCert=جارٍ تثبيت شهادة الناشر في الجهات الموثوقة...
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
