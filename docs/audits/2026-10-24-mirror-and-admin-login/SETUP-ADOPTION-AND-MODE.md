# SETUP-ADOPTION-AND-MODE — اعتماد قيم الإعداد الأول ووضع التشغيل — 2026-10-24

> النسخة: `feat/tables-reservations-permissions` @ `add15ede3b01809428381eeee8cadaf26a21ca7f`. قراءة كود فقط، ولم يُشغَّل أي شيء (NOT_RUN). المعالج القديم حُذف في `3361de8e`، وقُرئ من التاريخ بـ`git show 3361de8e^:<path>`.
>
> الوسوم:
> - **[مقروء]**: VERIFIED-BY-READING.
> - **[مقروء*]**: قرأه قارئ مساعد، ويُعاد فحصه قبل التنفيذ.
> - **[استنتاج]**: INFERRED.
>
> وثائق شقيقة: [MIRROR-AUDIT.md](<MIRROR-AUDIT.md>) و[ADMIN-IDENTITY-AND-DEVICE-ROLES.md](<ADMIN-IDENTITY-AND-DEVICE-ROLES.md>).

## فهرس
- §0 الخلاصة: لماذا لم «يثبت» اختيار المرآة
- §1 أين يُكتب كل اختيار (الإعداد الجديد)، ومن يقرؤه عند الإقلاع
- §2 الأسباب الجذرية لعدم ثبات المرآة (الجديد والقديم)، مرتبة بالأدلة
- §3 جدول اعتماد كل قيمة إعداد في النظام كله
- §4 «عقد الاعتماد» Adoption Contract (التصميم)
- §5 النتائج ADP-001…ADP-012 ومعايير القبول
- §6 ما لم يُتحقق منه

---

## §0 الخلاصة
اختيار «مرآة» في الإعداد الأول لا يُطبَّق بخطوة واحدة. يتوزّع على خمسة مخازن ومسارين زمنيين.

**المخازن الخمسة:**
1. **prefs:** `network_mode`، العنوان، المفتاح، `mirror_*`.
2. **الـDB:** `network_mode`، `deployment_mode`، `setup_completed`، أعلام المزامنة الأولى.
3. **ذاكرة** `NetworkService` و`MirrorState`.
4. **providers Riverpod:** `deploymentModeProvider`، العملة.
5. **حلقة المزامنة** التي لا تبدأ إلا عند الإقلاع.

**المساران الزمنيان:**
- خطوة «الربط»، وتكتب الاقتران فورًا.
- «الإنهاء»، ويكتب الوضع لاحقًا.

**ما يحدث عند فشل أي مرحلة:**
- يبقى الاقتران محفوظًا، والبيانات المزروعة ممسوحة، والوضع «مستقل»، بلا تراجع.
- عند النجاح: الوضع مكتوب، لكن المزامنة لا تعمل حتى إعادة التشغيل.
- إن ظهرت شاشة الخطأ القاتل: نصها يطلب «خيارات المطوّر»، وزرّاها لا يفعلان شيئًا يُخرج منها.

**لماذا نجحت أدوات المطوّر؟** لأنها تمرّ بمسار مختلف:
- `forceResync: true`.
- تقترن عبر حوار مستقل إن لم يكن الجهاز مقترنًا.
- تعمل على جهاز «مستقل» مكتمل الإعداد.

النتيجة: **لا يوجد مصدر حقيقة واحد للوضع ولا اعتماد ذرّي**. والحل «عقد الاعتماد» في §4.

---

## §1 مواضع الكتابة والقراءة

### 1.1 مسار المرآة في الإعداد الجديد [مقروء]
| الخطوة | الكتابة | الموضع |
|---|---|---|
| `link` | prefs: `network_server_address`/port، و`network_mode` (القيمة الحالية `standalone`)، و`network_api_token` (من `/api/health` داخل نافذة الاقتران)، و`mirror_server_display_name`، و`mirror_last_handshake_at`، و`mirror_admin_user_id`. ذاكرة: `SyncInterceptor.currentUserId = HQ admin`، رمز جلسة | `first_run_ops.dart:216-235` ثم `client_link_service.dart:240-276` [مقروء*] ثم `mirror_pairing_service.dart:74-144`؛ `network_service.dart:1099-1105` |
| finish/settings | DB: `setup_in_progress='true'` | `first_run_finish_server.dart:96-97` |
| finish/mode | `commitDeploymentMode(mirror)`: اعتماد فارغ ⇒ لا اقتران. علم غائب ⇒ `_firstSync` (wipe ثم `fullSync`) ⇒ DB: `mirror_first_sync_completed`، `mirror_cache_integrity_v1_applied` ⇒ حارس «سيرفر فارغ» ⇒ `setMode(mirror)` ⇒ DB `network_mode` (فشلها يُبتلع) ⇒ prefs ⇒ heartbeat ⇒ DB `last_committed_mode` | `setup_persistence_riverpod.dart:138-147`؛ `deployment_mode_committer.dart:101-322`؛ `network_service.dart:713-751` |
| finish/tail | DB: `deployment_mode='mirror'` (مخزَّن cached)، ثم `runExtras` (overrides + `touchMode`)، ثم `setup_completed='true'`، ثم `setup_in_progress=''`، ثم تدقيق، ثم rehydrate | `first_run_finish_tail.dart:35-57`؛ `first_run_finish_server.dart:141-149` |
| بعد النجاح | صفحة نجاح ⇒ «ابدأ الاستخدام» ⇒ `MainScreen` **بلا إعادة تشغيل** (للمرآة) | `first_run_success_page.dart:117-130` [مقروء*] |
| بعد الفشل | `SetupRunResult(ok:false, failedStage: mode)` ⇒ رجوع للمراجعة برسالة | `first_run_finish_tail.dart:26-34`؛ `first_run_controller.dart:220-228` [مقروء*] |

### 1.2 مسار أدوات المطوّر (الذي «نجح») [مقروء]
`developer_tools_screen.dart:575-646` ينفّذ بالترتيب:
1. إن لم يكن `MirrorState.isConfigured` ⇒ `MirrorPairingDialog`.
2. تأكيد بالكتابة.
3. `buildContract(target: mirror, serverHost: current)`.
4. `commit(forceResync: true)`، وفيه `svc.reset()` ثم wipe ثم `fullSync` (`deployment_mode_committer.dart:451-457`).
5. `deploymentModeProvider.notifier.applyFromService(mirror)`، وهذا **في الذاكرة فقط** (`business_profile_provider.dart:104-106`).
6. toast: «يفضّل إعادة تشغيل التطبيق».

**الفروق عن الإعداد الأول:**
- يعمل على جهاز `setup_completed=true`، فلا بوابة إعداد.
- `forceResync`.
- لا يكتب `deployment_mode` في الـDB، فيعرض النمط القديم بعد إعادة التشغيل.
- يُنصح بإعادة التشغيل، وإعادة التشغيل تبدأ `autoSyncIfClient`.

### 1.3 الإقلاع [مقروء]
1. **`initPlatform`:** `NetworkService.loadSettings()` من **prefs** (`network_mode ?? 'standalone'`، `network_service.dart:249-255` [مقروء*]) ثم `MirrorState.loadSettings()` من prefs (`main_desktop.dart:40-41` [مقروء*]).
2. **`reconcileWithDb`:** الـDB يفوز، ثم `_checkConsistency` (`network_service.dart:324-576`):
   - **المرآة:** `mirror_first_sync_completed` + `MirrorState.isConfigured`، وإلا Fatal.
   - **DB فارغ + prefs=mirror:** standalone بصمت (`:442-464`).
3. **Fatal:** شاشة بلا مخرج فعلي (`main.dart:340-375`).
4. **Spec 131:** إعادة مزامنة قسرية للمرآة عند الإقلاع (`main.dart:385-431`).
5. **`MaterialApp`:** `home: isAuthenticated ? _SetupGate : LoginScreen` (`main.dart:1406-1408`). و`_SetupGate` يقرأ `setup_completed` (`:1558-1565`).
6. **`_startSyncIfReady`:** **مرة واحدة** في `initState`، ومشروط بـ`setup_completed=='true'` (`main.dart:1310-1341`).

### 1.4 تصنيف المفاتيح [مقروء]
- **`kDeviceLocalSettingKeys`** (`setting_sync_strategy.dart:103-152`): `network_mode`، `deployment_mode`، `setup_completed`، `setup_draft_v2`، `setup_progress_v2`، `client_first_sync_completed`، `mirror_first_sync_completed`، `mirror_cache_integrity_v1_applied`، `client_branch_id`، `pos_*_safe_id`، `pos_default_warehouse_id`، `device_id`، `machine_id`، `pos_receipt_printer`، `pos_kitchen_printer`، `pos_open_drawer_on_print`، `pos_receipt_template`، `touchMode`. وأي مفتاح يبدأ بـ`_watermark__`.
- **ليست محلية فتُكتب فوقها قيم السيرفر عند السحب** (`:21-25`):
  - `setup_in_progress`، `standalone_setup_completed`، `server_setup_completed`، `last_committed_mode`.
  - `business_profile`، `company_*`، `system_currency`، `feature.*`، `tax_*`، `show_*_einvoice`، `offline_login_grace_days`.
  - `login_lockouts_v1` (P0 خطة المستخدمين).
  - **`device_locale`** إن كان في جدول `settings` [استنتاج، لم يُتحقق من مخزنه].
- **مفاتيح المرآة `mirror_*` ليست في الـDB أصلًا** (prefs فقط، `mirror_state.dart:21-23`).

---

## §2 الأسباب الجذرية لعدم ثبات المرآة
> الحكم القاطع على جهاز المالك يحتاج سجلّه: `${dbPrefix}_startup_log` / DiagnosticLogger بأسطر `COMMIT-*` و`RECONCILE-*` و`NETMODE-RECONCILE`، وقيم `settings` الخاصة بـ`network_mode` و`deployment_mode` و`setup_completed` و`mirror_first_sync_completed`، وprefs `mirror_*`. هذا **BLOCKED** لعدم توفر الجهاز. ما يلي أسباب مثبتة في الكود، مرتبة باحتمال تطابقها مع البلاغ.

| # | السبب | الدليل | الثقة أنه موجود في الكود | التطابق مع البلاغ |
|---|---|---|---|---|
| **R1** | **فشل الاعتماد بلا تراجع (نصف تفعيل).** `_firstSync` أو حارس «السيرفر فارغ» ⇒ `CommitFailed` ⇒ لا `network_mode` ولا `setup_completed`. والاقتران باقٍ في prefs، والمزروع ممسوح. المستخدم يخرج من الإعداد بمسار آخر (في القديم: «تخطي الإعداد» ⇒ `resetToStandalone`، الملف القديم `setup_wizard_screen.dart:1357-1381` @`3361de8e^`)، ثم ينجح من أدوات المطوّر لأن `MirrorState` مقترن مسبقًا و`forceResync` يعيد المزامنة | `deployment_mode_committer.dart:131-189`، `:530-543`؛ `first_run_finish_tail.dart:26-34` | عالية | **عالٍ**: يفسر «اضطررت لخيارات المطوّر». أدوات المطوّر تتجاهل اختيار «مرآة» إن كان `deployment_mode` المعروض مرآة أصلًا (`developer_tools_screen.dart:576`)، فنجاحها يعني أن الإعداد لم يبلغ `:35` في الذيل |
| **R2** | **النجاح بلا تفعيل وقت التشغيل.** لا `autoSyncIfClient` بعد الإنهاء، فلا delta ولا WS حتى إعادة التشغيل | `main.dart:1310-1341`؛ `first_run_finish_tail.dart` | عالية | متوسط-عالٍ: «لم يأخذ الإعداد» (المرآة بلا بيانات حيّة) |
| **R3** | **فخ شاشة Fatal.** reconcile مرآة غير متسقة ⇒ Fatal يقول «ادخل خيارات المطور». «خيارات المطوّر» لا يفعل شيئًا، و«إعادة الإعداد» يُبقي `network_mode=mirror` ⇒ حلقة | `network_service.dart:565-571`؛ `main.dart:345-373` | عالية | متوسط: النص نفسه يوجّه إلى خيارات المطوّر |
| **R4** | **`setMode` يبتلع فشل كتابة الـDB.** prefs=mirror ⇒ الإقلاع التالي (DB فارغ) ⇒ standalone صامت مع `setup_completed=true` | `network_service.dart:742-748`؛ `:442-464` | عالية للكود، ومنخفضة الحدوث | منخفض-متوسط: «يفتح مستقلًا» |
| **R5** | **المعالج القديم:** مسار المرآة 8 خطوات تكتب **محليًا قبل الاعتماد** (الشركة، العملة، `business_profile`، إعادة تسمية الفرع/المخزن، منتجات، مستخدمون، سنة مالية بعد الاعتماد لغير العميل). ثم wipe يمسح جزءًا (المزروع بعلم `isSystemDefault`) | `setup_finish_runner.dart:262-439` (ما زال موجودًا ويستعمله المستقل)؛ ترتيب القديم `setup_step_order.dart:138-148` @`3361de8e^` | عالية | يفسر تكرار الفروع والسنوات المالية على المرآة (وجود `branch_dedup_extension.dart` و`fiscal_year_dedup_extension.dart` [مقروء*: الأسماء]) |
| **R6** | **الاقتران القديم بعمر 30 يومًا (MIR-001).** بعد انتهاء نافذة الانتقال: «الخادم غير مفتوح لاقتران جهاز جديد» حتى والنافذة مفتوحة | `network_service.dart:785-789`، `:1106-1118`؛ `lan_pairing_service.dart:585-611` | عالية | لا يفسر هذا البلاغ (أدوات المطوّر ستفشل أيضًا)، لكنه يفسر آلامًا أخرى |
| **R7** | **مصدران للنمط:** `deployment_mode` (يعرضه دَف تولز والـsnapshot) مقابل `network_mode` (السلوك). أدوات المطوّر لا تكتب الأول. ورقائق إعدادات الشبكة لا تكتب الأول ولا تمرّ بالمعتمِد | `business_profile_provider.dart:97-106`، `:167-173` [مقروء*]؛ `developer_tools_screen.dart:635`؛ `network_mode_settings_picpos.dart:122-126` | عالية | يجعل التشخيص مضلِّلًا: الشاشة تعرض نمطًا والجهاز يعمل بآخر |

**التوصية التشخيصية الفورية (لا كود):** أن يرسل المالك ملف السجل وقيم المفاتيح أعلاه من الجهاز. R1 يظهر كسطر `COMMIT-FAIL firstSync threw` أو `MIRROR_SERVER_EMPTY`، وR4 كسطر `STALE PREFS`، وR3 كسطر `RECONCILE-FAIL mirrorPairingMissing`.

---

## §3 اعتماد كل قيمة إعداد في النظام كله
| القيمة | standalone: أين تُكتب | hq: أين تُكتب | client / mirror | من يقرؤها وقت التشغيل | تُحدَّث بلا إعادة تشغيل؟ | الفجوة |
|---|---|---|---|---|---|---|
| وضع التشغيل | `SetupFinishRunner` ⇒ committer | committer محليًا + `network_mode` على PG [مقروء*] | committer | `NetworkService.mode` (من DB/prefs) | الوضع نعم، والمزامنة **لا** | ADP-001/002/003 |
| `deployment_mode` | runner `:415-423` | الذيل على SQLite المحلي. **غائب على PG** [مقروء*] | الذيل | `deploymentModeProvider` (أدوات المطوّر والـsnapshot فقط) | invalidate | ADP-004 |
| اسم الشركة وهويتها | runner `:272-299` | PG (writer) + `company_name` محليًا (`first_run_finish_server.dart:110-112`) | من السحب (ليس محليًا) | شاشات الشركة، الطباعة | يُقرأ من الإعدادات عند الطلب [استنتاج] | — |
| العملة | runner `:301` (`setCurrency`) | PG | من السحب | `systemCurrencyProvider`: **`init()` مرة واحدة** (`main.dart:1313` [مقروء]؛ `providers.dart:397-409` [مقروء*]) | **لا** | ADP-005 |
| `business_profile`/الباقة | runner `:265` | PG | من السحب | `businessProfileProvider` | نعم (rehydrate، `business_profile_provider.dart:409-428`) | على المرآة: افتراضات المسودة عبر `runExtras` (MIR-022) |
| overrides الميزات (طاولات/توصيل) | extras | PG | extras بافتراضات (MIR-022) | `featureOverridesProvider` | نعم | ADP-006 |
| الفرع والمخزن الافتراضي | runner `_branchAndWarehouse` `:303-311` | PG (فروع متعددة) | عميل: `client_branch_id` (prefs + DB؟) + `writeClientBranchSettings`؛ مرآة: لا | `activeBranchIdProvider`، POS | [استنتاج] نعم عند القراءة التالية | `saveClientBranchId` يكتب **prefs** (`setup_persistence_riverpod.dart:150-153` [مقروء])، بينما المفتاح في قائمة الـDB المحلية: ازدواجية |
| الخزائن | runner `:313-324` (مستقل فقط) | تهيئة PG | من السحب | — | — | — |
| المستخدمون | runner `:358-372` (`forcePasswordChange:true`) | PG + `UserBranchAccess` | من السحب (بصمات بشروط، انظر ADMIN-IDENTITY) | الدخول | — | ADMIN-IDENTITY ADM-002/003 |
| كلمة `admin` | runner `:345-356` | PG (writer) | **لا شيء** | الدخول | — | ADM-001/002 |
| كلمة المطوّر | runner `:266-270` (فشلها تحذير فقط) | PG | **لا شيء** ⇒ «عيّن أول مرة» | `DeveloperPasswordGate` | — | ADM-009 |
| الضريبة والفوترة الإلكترونية | runner `:374-398` | PG | من السحب | POS، الفواتير | [استنتاج] عند القراءة | — |
| السنة المالية | runner `:426-439` (لغير العميل، **ويشمل المرآة في القديم**) | PG | العميل: من السحب. المرآة في الجديد: لا كتابة ✓ | المحاسبة | — | R5 (القديم) |
| الطاولات | extras / stages v2 | PG | لا | المطاعم | — | — |
| `touchMode` | extras | extras على **SQLite المحلي**، بينما التطبيق يقرأ PG بعد إعادة التشغيل ⇒ يضيع [استنتاج] | extras | `touchModeProvider` (invalidate) | نعم | ADP-007 |
| اللغة `device_locale` | فوري | فوري | فوري | `userLocaleProvider` | نعم | غير مصنَّف محليًا [استنتاج] ⇒ ADP-008 |
| مدة الأوفلاين | — | PG `offline_login_grace_days` | من السحب | `OfflineLoginPolicy` | — | — |
| الطابعات | **مؤجَّل** (B16) | مؤجَّل | محلية للجهاز | POS | — | خارج الإعداد بقرار |
| `setup_completed` | الذيل | PG + محلي | الذيل | `_SetupGate`، `_startSyncIfReady` | البوابة لا تُعاد بناؤها، و`_start` ينتقل مباشرةً | ADP-002 |

---

## §4 «عقد الاعتماد» (Adoption Contract)

### 4.1 المبادئ
1. **مصدر حقيقة واحد لكل نطاق:**
   - **حالة الجهاز:** سجل واحد `device_provisioning_v1` (JSON في `settings`، **محلي للجهاز**، يُضاف إلى `kDeviceLocalSettingKeys`). يحوي: `{version, mode, deviceKind, serverHost, serverPort, tlsPin?, deviceId, branchId?, pairedAt, firstSyncAt, setupCompletedAt, appVersion}`.
     - `network_mode` و`deployment_mode` و`setup_completed` و`*_first_sync_completed` و`client_branch_id` و`mirror_*` **تُشتق منه** وتُكتب معه في معاملة واحدة.
     - prefs **ذاكرة مؤقتة فقط**، تُعاد كتابتها من السجل عند كل إقلاع.
   - **حالة المؤسسة** (الشركة، العملة، الباقة، الضريبة، السنة، الفروع، المخازن، المستخدمون): مالكها **السيرفر** للعميل والمرآة، فلا يكتبها إعداد الجهاز أبدًا. ومالكها الإعداد الأول (كاتب واحد) للمستقل والمقر.
2. **التطبيق الذرّي:** `ModeActivator.commit(plan)` يملك **الاقتران + المزامنة الأولى + الوضع** معًا (ينقل الاقتران من خطوة «الربط» إلى «اختبار فقط»، أو يحفظ نتيجته في ذاكرة الـactivator ثم يثبّتها عند الإنهاء).
   - المزامنة الأولى تسحب إلى القاعدة، ثم تمسح المزروع **بعد** نجاح السحب.
   - عند الفشل: تراجع كامل (مسح الاقتران، لا مسّ للمزروع).
   - عند النجاح: معاملة واحدة تكتب السجل وكل المفاتيح المشتقة، ثم prefs.
   - `setMode` لا يبتلع فشل الـDB: يرمي ⇒ `CommitFailed`.
3. **إعادة التطبيق idempotent عند كل إقلاع:** `ProvisioningApplier.ensure(db)` قبل `reconcileWithDb`:
   - يقرأ السجل، ويقارن الـDB وprefs و`MirrorState`.
   - السجل يفوز، ويصلح ويسجّل `ADOPT-REPAIR key=… from=… to=…`.
   - إن غاب السجل في تركيب قديم: يُبنى من المفاتيح الحالية مرة واحدة (`ADOPT-BACKFILL`). هذا الترحيل لا يغيّر المخطط.
4. **التفعيل وقت التشغيل:** للأوضاع الشبكية (server, client, mirror) **إعادة تشغيل إلزامية** بزر «إعادة التشغيل الآن» في صفحة النجاح (كما المقر اليوم).
   - السبب: مسار الإقلاع هو المسار المختبَر الوحيد الذي يبدأ المزامنة وheartbeat والـWS بالترتيب.
   - بديل مرفوض: تشغيل `autoSyncIfClient` داخل الجلسة، لأنه مسار ثانٍ يحتاج اختبارًا وتفكيكًا لحالة الإعداد.
5. **فحص ذاتي بعد الإنهاء** (شاشة «فحص اعتماد الإعداد»): يُعرض **مرة واحدة** في أول إقلاع بعد الإنهاء، **قبل الدخول**. يقرأ من النظام الجاري (لا من المسودة):

   | الفحص | المصدر | PASS عندما |
   |---|---|---|
   | الوضع | `NetworkService.instance.mode`، `deploymentModeProvider` | كلاهما = `record.mode` |
   | الاقتران | `MirrorState.isConfigured` / رمز الجهاز / `client_branch_id` | حسب النوع |
   | السيرفر | `/api/health` | 200 + `sessionKeyId` + TLS مطابق للبصمة |
   | المزامنة الأولى | العلم المناسب | `true` + عدّ الفروع والمخازن > 0 |
   | المستخدمون | طوابع الاعتماد (خطة المستخدمين P3) | ≥ 1 مستخدم مختوم + `admin` مختوم |
   | الشركة والعملة والباقة | `companyName`، `systemCurrencyProvider`، `businessProfileProvider` | مطابقة لقيم السيرفر (client/mirror) أو المسودة (standalone/hq) |
   | حلقة المزامنة | `DeltaPullService` آخر سحب | سحب واحد ناجح خلال 60 ثانية |
   | لا `admin/admin` | `db.authenticateUser('admin','admin')` | null |
   
   - **FAIL** في أي بند ⇒ رسالة بالسبب + «إعادة المحاولة» + «إعادة توفير الجهاز». **لا** دخول بحالة FAIL في بنود الوضع والاقتران والمزامنة الأولى.
   - النتيجة تُسجَّل في سجل العمليات (`setup_self_check`).
6. **مدخل واحد لتغيير الوضع:** «إعادة توفير الجهاز»:
   - تحذف الرقائق من شاشة إعدادات الشبكة (تبقى للعرض فقط).
   - «تغيير الوضع» في أدوات المطوّر يُحوَّل إليه.
   - شاشة Fatal تستدعيه.
   - حارس static: لا مستدعٍ لـ`NetworkService.setMode` إلا `ModeActivator`.
7. **ما لا يُكتب على العميل والمرآة:** أي مفتاح مؤسسي. `runExtras` لهما = `touchMode` فقط.

### 4.2 تسلسل الإنهاء المستهدف للمرآة
```
review ─finish─▶ ModeActivator.commit(MirrorPlan{host,port,pairingCode})
  1 pair(/api/pair, deviceKind=mirror) ─fail─▶ CommitFailed (لا أثر)
  2 firstSync→staging ─fail─▶ unpair + CommitFailed (المزروع سليم)
  3 replace seeded by pulled (transaction)
  4 verify-first-user (server) ─passwordChangeRequired─▶ change on server
  5 txn{ device_provisioning_v1, network_mode, deployment_mode,
         mirror_first_sync_completed, setup_completed }
  6 prefs ← record
  ▶ success page «إعادة التشغيل الآن» ▶ boot: ProvisioningApplier.ensure
  ▶ reconcile OK ▶ self-check (PASS) ▶ LoginScreen
```

### 4.3 أثره على الإصلاحات الأخرى
- يغلق MIR-005، MIR-006، MIR-007، MIR-014، MIR-015، MIR-022.
- يتطلب MIR-001 (إقران برمز للمرآة) للخطوة 1.
- يعتمد على P0/P3 في خطة المستخدمين لبند «المستخدمون» في الفحص الذاتي.

---

## §5 النتائج ومعايير القبول
| ID | العنوان | الخطورة/الأولوية | الثقة | الموضع | القبول (NOT_RUN) |
|---|---|---|---|---|---|
| ADP-001 | الاعتماد غير ذرّي: الاقتران خارج الاعتماد، والـwipe قبل السحب، ولا تراجع (= MIR-006) | عالٍ / P0 | عالية [مقروء] | `deployment_mode_committer.dart:131-189`، `:530-543` | فشل مصطنع في `fullSync` ⇒ لا `mirror_*` في prefs، والمزروع سليم، ويمكن إعادة المحاولة |
| ADP-002 | لا تفعيل وقت التشغيل بعد النجاح (= MIR-005) | عالٍ / P0 | عالية [مقروء] | `main.dart:1310-1341` | صفحة النجاح للأوضاع الشبكية تفرض إعادة التشغيل، ثم الفحص الذاتي PASS |
| ADP-003 | `setMode` يبتلع فشل كتابة `network_mode` | متوسط / P0 | عالية [مقروء] | `network_service.dart:716-720`، `:742-748` | استثناء DB مصطنع ⇒ `CommitFailed(SETMODE_FAILED)` |
| ADP-004 | مصدران للنمط (`deployment_mode`/`network_mode`)، وأدوات المطوّر تكتب الذاكرة فقط، وPG بلا `deployment_mode` | متوسط / P1 | عالية [مقروء] + PG [مقروء*] | `business_profile_provider.dart:97-106`؛ `developer_tools_screen.dart:635` | `deployment_mode` مشتق من السجل دائمًا، ومتطابق بعد إعادة التشغيل على SQLite وPG |
| ADP-005 | العملة لا تُحدَّث بلا إعادة تشغيل | متوسط / P1 | متوسطة [مقروء*] | `main.dart:1313`؛ `providers.dart:397-409` | بعد الإنهاء: الفحص الذاتي يقرأ العملة = المسودة أو السيرفر |
| ADP-006 | الإعداد الأول للعميل والمرآة يكتب overrides مؤسسية بافتراضات (= MIR-022) | منخفض-متوسط / P1 | عالية [مقروء] لنداء `runExtras` | `first_run_finish_server.dart:139`، `:148` | لا مفتاح `feature.*` يُكتب على العميل والمرآة في الإنهاء |
| ADP-007 | `touchMode` في مسار المقر يُكتب في SQLite المحلي لا PG | منخفض / P2 | منخفضة [استنتاج] | `first_run_finish_server.dart:119-121` | بعد إعادة تشغيل المقر: `touchMode` كما اختير |
| ADP-008 | اللغة `device_locale` غير مصنَّفة كمحلية للجهاز (إن كانت في `settings`) | منخفض / P2 | منخفضة [استنتاج] | `setting_sync_strategy.dart:103-152` | تحقق المخزن، ثم إضافتها إن لزم |
| ADP-009 | شاشة Fatal بلا مخرج (= MIR-007) | عالٍ / P0 | عالية [مقروء] | `main.dart:345-373` | من كل Fatal للمرآة يُصل إلى إعداد صالح بإعادة تشغيل واحدة |
| ADP-010 | ثلاثة مداخل لتغيير الوضع (= MIR-014) | متوسط / P1 | عالية [مقروء] | `network_mode_settings_picpos.dart:122-126`؛ `developer_tools_screen.dart:575-646` | حارس static: `setMode` عبر `ModeActivator` فقط |
| ADP-011 | `client_branch_id` يُكتب في prefs بينما المفتاح مصنَّف محليًا في الـDB | منخفض-متوسط / P1 | عالية [مقروء] لكتابة prefs | `setup_persistence_riverpod.dart:150-153`؛ `auth_repository_impl.dart:201-202` (يقرأ prefs) | فرع الجهاز يُقرأ من السجل. مسح prefs لا يفقد الفرع |
| ADP-012 | لا اختبار يثبت أن الوضع **فُعِّل فعلًا** بعد الإنهاء | عالٍ / P0 | عالية [مقروء*] | `first_run_acceptance_branch_additional_and_mirror_test.dart:59-89`؛ `deployment_mode_committer_test.dart:17-97` | اختبار تكامل: committer حقيقي + سيرفر مزيّف، ثم «إعادة إقلاع» (إنشاء الخدمات من جديد) ⇒ `reconcile` OK و`NetworkService.mode==mirror` و`MirrorState.isConfigured` والعلم `true` |

| ADP-013 | مفاتيح المعتمِد `last_committed_mode` و`server_setup_completed` و`standalone_setup_completed` ليست محلية للجهاز، فتُسحب من السيرفر | منخفض-متوسط / P1 | عالية: `REPRO-R4-g` = FAIL (`REPRO-RESULTS.md:94`، جلسة أخرى)؛ والقائمة [مقروء] | `setting_sync_strategy.dart:103-152` مقابل `deployment/settings_keys.dart:42-49` [مقروء*] | تشتق من السجل وتُضاف إلى القائمة المحلية |

**يمنع الإصدار:** ADP-001، ADP-002، ADP-009، ADP-012.

**تقاطع مع اختبارات جلسة أخرى** (`REPRO-RESULTS.md` في هذا المجلد، لم أشغّلها):
- `CHAR-R4-a/b/c` = PASS: الوضع يثبت بعد إعادة الإقلاع **إن** كانت أعلام المزامنة الأولى مضبوطة. وساق المزامنة الأولى الحقيقية BLOCKED هناك. هذا يحصر السبب في R1 وR2 أعلاه (مرحلة المزامنة/التفعيل)، لا في الـreconcile ذاته.
- `REPRO-R4-f` = FAIL: ضياع prefs مع سلامة الـDB ⇒ `mirrorPairingMissing`. يدعم MIR-015 وعقد الاعتماد (§4.1-1).
- فرضيتهم أن الفشل «يمسح `MirrorState` عبر `_rollbackPairing`» **غير صحيحة** لمسارَي الإعداد وأدوات المطوّر، لأن `pairingDone=false` (`deployment_mode_committer.dart:137-148`، `:170`، `:186` [مقروء]). فـ`MirrorState` يبقى، وهذا ما يجعل أدوات المطوّر تتخطّى الاقتران وتنجح (R1). السبب أنها تجعل «ما يُختار في الإعداد يُطبَّق» غير مضمون، وهذا متطلب المالك 4.

---

## §6 ما لم يُتحقق منه
- **سجل جهاز المالك:** BLOCKED (غير متاح). §2 يعطي الأسطر المطلوبة.
- **سلوك الإنهاء الفعلي:** لم يُشغَّل الإعداد الأول ولا أي اختبار (NOT_RUN).
- **[مقروء*]:** `first_run_success_page.dart`، `first_run_controller.dart`، `first_run_finish.dart:75-100`، `server_setup_writer.dart`، `providers.dart:397-409`، `client_first_sync_service.dart`.
- **مخزن `device_locale`:** لم يُتحقق منه.
- **أثر `armPostgresMode` على أي قاعدة تُقرأ بعد إعادة تشغيل المقر:** [استنتاج].
- **مراحل خطة الإعداد المنفَّذة:** `3361de8e` يقول «complete new first-run setup (main-server, branch, mirror paths; offline-login grace policy partial)… remove old wizard». فالمراحل P0–P3 وP5 وP6 وP8 منفَّذة **بحسب رسالة الـcommit ووجود الملفات** [استنتاج]. ولم أراجع كل ملف مقابل الخطة.
