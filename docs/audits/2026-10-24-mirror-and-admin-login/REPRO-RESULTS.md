# نتائج الاختبارات التوثيقية (Repro) — وضع Mirror، المستخدمون، دخول الـ admin

> تاريخ التشغيل: 2026-10-24 · الفرع `feat/tables-reservations-permissions` · **لم يُعدَّل أي كود منتج** (`lib/ server/ packages/ mobile*/` قراءة فقط) ولم يُنفَّذ commit.
> الملفات المضافة: `test/repro_mirror/` (5 ملفات، كلها < 30KB) وهذا الملف فقط.

## 1. الأوامر والمخرجات الحقيقية

```
> flutter test test/repro_mirror --reporter expanded
01:23 +33 ~1 -24: Some tests failed.        (exit code 1 — متوقَّع)

> dart analyze test/repro_mirror
Analyzing repro_mirror...
No issues found!
```

الحصيلة: **58 اختبار = 33 PASS · 24 FAIL · 1 BLOCKED (مُتخطّى بـ `skip:` مع سبب)**.
- `REPRO-*` اختبار يصف عيبًا ويؤكّد السلوك **الصحيح** ⇒ يفشل اليوم (24 اختبارًا، وكلها فشلت فعلًا).
- `CHAR-*` يوثّق السلوك الحالي المقبول أو يسجّله ⇒ ينجح (33).
- لا شيء مسجَّل في CI ولا في أي قائمة structural. الملف المساعد `peer_harness.dart` ليس اختبارًا.

## 2. الـ Harness (ما الذي يعمل فعلًا في-process)

| الطرف | التنفيذ |
|---|---|
| Host | `AppDatabase.forTesting()` + `ApiHandler(host).buildRouter().call(shelf.Request)` — نفس نمط `test/integration/api_p1_8b_sync_scope_test.dart`. هوية الجلسة تُحقن عبر `ApiUserCtx.userIdKey`، ونافذة الاقتران عبر `ApiAuthMiddleware.openPairingWindow()/closePairingWindow()`. |
| Client | `AppDatabase.forTesting()` ثانية (فيها `admin/admin` المزروع كجهاز جديد). |
| "السلك" | JSON الـ router يُطبَّق على الـ client بنفس كود الجهاز: `UserSyncStrategy.syncFromJson` (first sync / login fallback) أو `DeltaPullService.upsertRowForTest` (delta). |
| الأوضاع | `ClientWriteInterceptor.setup()` الحقيقي + `NetworkService.debugSetModeForTests` + `MirrorState.debugSetForTests`؛ الـ host غير المتاح = `127.0.0.1:1`. |
| First-run | `serverBoundFinisher` الحقيقي + `DeploymentModeCommitter` الحقيقي + `NetworkService.reconcileWithDb` الحقيقي (R4). |

Fixture: host فيه `admin` (id 1) بكلمة مرور مخصّصة، `cashier1` (كلمة أولية + `forcePasswordChange`)، `acct1` (كلمة أولية)، `mgr1` (دور مخصّص، فرعان). Client = جهاز جديد.

## 3. الجداول (id · السيناريو · المتوقَّع · الفعلي · الحالة · موضع الكود · الثقة)

### R1 — تسليم الاعتمادات (first sync) ونافذة الاقتران
ملف: `r1_r2_r7_credentials_test.dart`

| id | السيناريو | المتوقَّع | الفعلي (مخرج الاختبار) | الحالة | الكود المسؤول | الثقة |
|---|---|---|---|---|---|---|
| CHAR-R1-a | نافذة الاقتران **مفتوحة** + first sync | تصل الهاشات؛ دخول admin بالكلمة المخصّصة وcashier/acct بالأولية يعمل؛ `admin/admin` لا يعمل | كما هو متوقَّع | PASS | `api_get_users.dart:25-37,127` | عالية |
| CHAR-R1-b | نافذة **مغلقة** وبلا جلسة | لا `passwordHash/Salt` في `/api/users` ولا `password_hash/pin` في `/api/sync/pull?table=users` | كما هو متوقَّع | PASS | `api_get_sync_pull.dart:264-282` | عالية |
| CHAR-R1-c | نافذة مغلقة: من يصل؟ (تسجيل) | admin+cashier1+acct1 يصلون؛ `mgr1` (دور مخصّص) **لا** يصل | كما هو | PASS | `api_get_users.dart:34-37` (sentinel `-1`) + `:56-96` | عالية |
| **REPRO-R1-d** | نافذة مغلقة (first sync قبل الدخول = الحالة العادية) | `admin/admin` **لا** يعمل على الجهاز المقترن | `Expected: false  Actual: <true>` | **FAIL** | `database_seeder.dart:29-50` (admin المزروع salt غير فارغ) يحميه شرط `user_sync_strategy.dart:111-113` | عالية |
| **REPRO-R1-e** | نفس السيناريو | admin بالكلمة المخصّصة يدخل | `Expected: true  Actual: <false>` — "host admin custom password never reached this device" | **FAIL** | `api_get_users.dart:25-37` | عالية |
| **REPRO-R1-f** | نفس السيناريو | cashier/acct بالكلمة الأولية يدخلان | `Expected: true  Actual: <false>` | **FAIL** | `user_sync_strategy.dart:128-137` (UnusableCredential) | عالية |
| **REPRO-R1-g** | جلسة **كاشير** (نافذة مغلقة) على `/api/users` | لا تصله اعتمادات الآخرين وخصوصًا admin | `Expected: false  Actual: <true>` (admin.passwordHash موجود) | **FAIL** | `api_get_users.dart:25-31,99-127` + `:92` (admin دائمًا ضمن النطاق) | متوسطة (قد يكون مقصودًا للدخول offline، لكنه تسريب هاش admin لكل جلسة) |

### R2 — CRED-WIPE
| id | السيناريو | المتوقَّع | الفعلي | الحالة | الكود | الثقة |
|---|---|---|---|---|---|---|
| CHAR-R2-pre | جهاز بعد first sync مفتوح | صفوف Argon2 مخزَّنة بـ `salt == ''` | كما هو | PASS | `user_dao.dart:191,284` | عالية |
| **REPRO-R2-a** | هاش صالح محليًا → كلمة خاطئة → fallback `performTableSync('users')` بلا اعتمادات → الكلمة الصحيحة | الهاش المحلي **ينجو** | `Expected: true  Actual: <false>` — "UserSyncStrategy requires passwordSalt.isNotEmpty… replaced by UnusableCredential" | **FAIL** | `user_sync_strategy.dart:111-113` (يشترط `passwordSalt.isNotEmpty`) و`:128-137` | عالية جدًا |
| **REPRO-R2-b** | نفس الشيء عبر delta pull (صفوف بلا `password_hash`) | الهاش ينجو | `Expected: true  Actual: <false>` | **FAIL** | `delta_pull_service.dart:1278-1301` (`localHash.isNotEmpty && localSalt.isNotEmpty`) | عالية جدًا |
| **REPRO-R2-c** | بعد المسح | لا يبقى مستخدم موسوم `forcePasswordChange` وهو لا يستطيع الدخول | `Expected: false  Actual: <true>` | **FAIL** | `delta_pull_service.dart:1310-1313` | عالية |

أُكّد يدويًا بسجل `[DeltaPull] users id=1 username="admin": no usable credentials — stored an unusable credential` (وكذلك cashier1/acct1/mgr1) أثناء التطوير.

### R3 — Mirror تحديدًا
ملف: `r3_mirror_modes_test.dart`

| id | السيناريو | المتوقَّع | الفعلي | الحالة | الكود | الثقة |
|---|---|---|---|---|---|---|
| CHAR-R3-a | client | `NS.isClient=true · ServerProxy.isClientMode=true · SI.isClientMode=true · SI.isMirrorMode=false · WR.isMirrorActive=false` | مطابق | PASS | `cwi_core.dart:6-9` | عالية |
| CHAR-R3-b | mirror (handshake تم) | `NS.isClient=false · ServerProxy.isClientMode=false · SI.isClientMode=true · SI.isMirrorMode=true · WR.isMirrorActive=true` | مطابق — **`NetworkService.isClient` و`ServerProxy.isClientMode` يستثنيان mirror، و`SyncInterceptor.isClientMode` يشمله** | PASS | `server_proxy.dart:192`, `write_router.dart:74-76` | عالية |
| CHAR-R3-c | mode=mirror بلا handshake | يتصرّف كـ **standalone** (كل المحمولات false) | مطابق | PASS (تسجيل) | `write_router.dart:74-76`؛ يحميه `network_service.dart:565` عند الإقلاع فقط | عالية |
| CHAR-R3-d | server/standalone | `SyncInterceptor.isClientMode=false` | مطابق | PASS | — | عالية |
| **REPRO-R3-e** | حارس "فشل المصادقة المحلية ⇒ اسحب المستخدمين ثم أعد المحاولة" | يشمل mirror | `Expected: true  Actual: <false>` | **FAIL** | `login_screen.dart:142` (`isClient` فقط) | عالية (فحص ثابت للمصدر) |
| **REPRO-R3-f** | تحديث الدور/الشاشة/الصلاحيات بعد الدخول | يشمل mirror | `Expected: true  Actual: <false>` | **FAIL** | `login_screen.dart:184` | عالية |
| **REPRO-R3-g** | `_bootTimeAdminHeal` (قد يعيد admin لـ admin/admin) | يُتخطّى على mirror كما على client | `Expected: true  Actual: <false>` | **FAIL** | `main.dart:868` (`!isClient` ⇒ يعمل على mirror) | منخفضة–متوسطة (الحارس ثابت، لكن الشرط الفعلي للإصلاح `adminPasswordNeedsHeal` ضيّق) |
| CHAR-R3-h | مواقع `SyncInterceptor.isClientMode` (auth repo / session / branch gate / offline policy) | تشمل mirror | مطابق | PASS | `auth_repository_impl.dart:168,200,294,370,464` | عالية |
| CHAR-R3-i | جلسة admin على mirror | كل المستخدمين + الاعتمادات؛ دخول mgr1/admin يعمل | مطابق | PASS | `api_get_users.dart` | عالية |
| **REPRO-R3-j** | مدير بفرعين، mirror، `GET /api/users` | يرى مستخدمي **الفرعين** | `Expected: contains all of ['mgr1','cashier1','b2cashier']  Actual: ['admin','cashier1','acct1','mgr1']` | **FAIL** | `api_get_users.dart:34-37` تستعمل `_extractBranchId` (رأس القائمة فقط)، بينما التوسيع FR-1 موجود فقط في `api_branch_scope.dart:105-141` / sync-pull | عالية |
| CHAR-R3-j2 | نفس المدير عبر `sync/pull?table=users` | الجميع يصل (لا branch scope على users) | مطابق | PASS (تسجيل) | `api_get_sync_pull.dart` | متوسطة |
| **REPRO-R3-k** | إقلاع mirror قبل الدخول (بلا جلسة/نافذة) يعيد توصيل users | الاعتمادات لا تُمسح | `Expected: true  Actual: <false>` (cashier1) | **FAIL** | `main_desktop.dart:142-193` (`pullAll()`/`fullSync()` قبل أي دخول) + R2 | عالية للآلية؛ متوسطة لتكرارها (يلزم أن يكون الصف ضمن delta/أو لا watermark) |
| CHAR-R3-l | مصدر صلاحيات دخول mirror | من DB المحلي (`role_permissions`)، وتبقى قديمة بعد تعديل HQ حتى pull | مطابق (host أقل صلاحية، mirror لم يتغيّر) | PASS | `auth_repository_impl.dart:437-439` | عالية |
| CHAR-R3-m | نطاق الفروع: mirror، مدير بفرعين | `{b1,b2}`، ليس fullAccess | مطابق | PASS | `branch_scope_provider.dart` | عالية |
| CHAR-R3-n | نفس المدير على client مربوط بفرع 1 | `branchScopeProvider` يعطي `{b1,b2}` أيضًا (التقييد بالجهاز في مكان آخر) | مطابق | PASS (تسجيل) | `auth_repository_impl.dart:199-253` | متوسطة |
| CHAR-R3-o | mirror + HQ غير متاح: تعديل صلاحية فرع | يُرفض `MirrorOfflineException` | مطابق | PASS | `write_router.dart`, `auth_repository_impl.dart:168` | عالية |
| CHAR-R3-p | client + HQ غير متاح: نفس التعديل | يُحفظ في `sync_outbox` | مطابق | PASS | `cwi_core_support.dart` | عالية |
| **REPRO-R3-q** | mirror + HQ غير متاح: `toggleUserActive / setUserLocked / assignRoleToUser / updateUserPassword` | تُرفض أو تُرسَل — **لا تُطبَّق محليًا بصمت** | `Expected: empty  Actual: ['toggleUserActive','setUserLocked','assignRoleToUser','updateUserPassword']` | **FAIL** | `auth_repository_impl.dart:138-155` (مباشرة إلى `db.*` بلا interceptor) | عالية جدًا |

### R4 — ثبات النمط (first-run ⇒ إعادة تشغيل)
ملف: `r4_mode_persistence_test.dart` (ينفّذ `serverBoundFinisher` ⇒ `DeploymentModeCommitter` ⇒ `reconcileWithDb`)

| id | السيناريو | المتوقَّع | الفعلي | الحالة | الكود | الثقة |
|---|---|---|---|---|---|---|
| CHAR-R4-a | finish mirror ثم إقلاع | `ReconcileOk(mirror)`، `network_mode=mirror`، `deployment_mode=mirror`، `forceFirstSync=false` | مطابق | PASS | `first_run_finish_tail.dart:25-50`, `network_service.dart:549-575` | عالية — **بشرط** أن أعلام first-sync مضبوطة (انظر BLOCKED) |
| CHAR-R4-b | finish client (branch) ثم إقلاع | client | مطابق | PASS | idem | عالية (نفس الشرط) |
| CHAR-R4-c | finish HQ ثم إقلاع | server | مطابق | PASS | idem | عالية |
| CHAR-R4-d | `MirrorState` بعد إعادة تشغيل العملية | يعود `isConfigured` من prefs | مطابق | PASS | `mirror_state.dart:65-102` | عالية |
| CHAR-R4-h | حمولة settings من الـ host فيها `network_mode=server` | لا تكتب فوق mirror | مطابق | PASS | `setting_sync_strategy.dart:110-111` | عالية |
| **REPRO-R4-f** | mirror منتهٍ، prefs ضاعت (الـDB سليمة) | يعود mirror أو يعرض إعادة اقتران قابلة للإصلاح | `Expected: <Instance of 'ReconcileOk'>  Actual: <Instance of 'ReconcileInconsistent'>` (`mirrorPairingMissing`) | **FAIL** | `network_service.dart:565-573`؛ هوية الاقتران محفوظة في SharedPreferences فقط (`mirror_state.dart:85-101`) | متوسطة (قد يكون تصميمًا مقصودًا: شاشة Fatal) |
| **REPRO-R4-g** | مفاتيح `DeploymentSettingsKeys.ownedKeys` | كلها device-local | `Actual: ['last_committed_mode','server_setup_completed','standalone_setup_completed']` غير محمية | **FAIL** | `setting_sync_strategy.dart:103-152` vs `deployment/settings_keys.dart:42-49` | عالية للتناقض؛ الأثر منخفض–متوسط |
| BLOCKED-R4-e | ساق first-sync داخل الـ committer لـ mirror/client | — | مُتخطّى (`skip:`) | **BLOCKED** | `deployment_mode_committer.dart:159-231`, `:443-488` | — |

سبب الـ BLOCKED: `performFirstSync` يحتاج `SyncService` يتحدّث HTTP حقيقيًا مع host (يلزم `shelf_io.serve` في Isolate مستقل كما في `test/scenarios/sc_n_api_sale_test.dart` + bearer/اقتران LAN). لم يُبنَ في هذا الـ harness؛ اختبارات R4-a/b سبقتها بضبط `mirror_first_sync_completed` و`mirror_cache_integrity_v1_applied` (أو `client_first_sync_completed`) كما يتركها `performFirstSync`.

### R5 — الدخول دون اتصال
ملف: `r5_r6_offline_forcechange_test.dart` (`AuthRepositoryImpl` + `OfflineLoginPolicy` بساعة محقونة)

| id | السيناريو | المتوقَّع | الفعلي | الحالة | الكود | الثقة |
|---|---|---|---|---|---|---|
| CHAR-R5-a | مستخدم متزامن، آخر تحقق قبل يوم | يدخل | مطابق | PASS | `auth_repository_impl.dart:293-319` | عالية |
| CHAR-R5-b | آخر تحقق قبل 8 أيام (المهلة 7) | يُرفض `StateError` | مطابق | PASS | idem | عالية |
| CHAR-R5-c | مستخدم لم يُزامَن | `null` | مطابق | PASS | `user_dao.dart:338-412` | عالية |
| CHAR-R5-d | ساعة الجهاز رجعت للخلف | يُرفض | مطابق | PASS | `offline_login_policy.dart:112-114` | عالية |
| CHAR-R5-e | بلا طابع: verdict=`neverVerified`، `allowed=false`، والمستودع يُدخله | موثَّق | مطابق | PASS | `auth_repository_impl.dart:317-318` | عالية |
| **REPRO-R5-f** | جهاز لم يصل الخادم أبدًا: دخول يوم 0 ثم يوم +60 | يُرفض في مرحلة ما | `Expected: true  Actual: <false>` — "no stamp is ever written without a server session" | **FAIL** | `offline_login_policy.dart:122`؛ لا يُكتب طابع بلا جلسة (`auth_repository_impl.dart:298-301`) | عالية |
| CHAR-R5-g | admin (id 1) بعد 10 أيام بلا تحقق | **ليس مستثنى** ⇒ يُرفض | مطابق | PASS (تسجيل — يتعارض مع "الـ admin يدخل على كل جهاز" إن اعتُبر شرطًا مطلقًا) | `auth_repository_impl.dart:293-319` | عالية |
| CHAR-R5-h | mirror (handshake تم) | تنطبق نفس المهلة | مطابق | PASS | idem | عالية |

### R6 — تغيير الكلمة الأولية (force-password-change)
| id | السيناريو | المتوقَّع | الفعلي | الحالة | الكود | الثقة |
|---|---|---|---|---|---|---|
| **REPRO-R6-a** | first sync (نافذة مفتوحة): علم `forcePasswordChange=true` من الـ host | يصل الجهاز | `Expected: true  Actual: <false>` (الحمولة لا تحوي الحقل أصلًا) | **FAIL** | `api_get_users.dart:100-137`; `user_sync_strategy.dart:139-141,162` | عالية |
| CHAR-R6-a2 | نفس الشيء عبر delta | يصل (`force_password_change=1`) | مطابق | PASS | `delta_pull_service.dart` | عالية |
| CHAR-R6-b | تغيير الكلمة محليًا على الجهاز | ينجح محليًا؛ القديمة تفشل | مطابق | PASS | `force_change_password_dialog.dart:62` | عالية |
| **REPRO-R6-c** | client: الكلمة المغيَّرة | تصل الـ host أو تُوضع في `sync_outbox` | `Expected: true  Actual: <false>` | **FAIL** | `auth_repository_impl.dart:138-141` ⇒ `db.updateUserPassword` فقط | عالية جدًا |
| **REPRO-R6-d** | client: بعد المزامنة التالية يدخل بالكلمة الجديدة | نعم | `Expected: true  Actual: <false>` — المزامنة تعيد هاش الـ host (الأولية) ⇒ يضيع التغيير وتتكرر الدورة | **FAIL** | idem + `user_sync_strategy.dart:100-110` | عالية |
| **REPRO-R6-e** | mirror + HQ غير متاح: تغيير كلمة مرور | يُرفض/يُوضع في الطابور | `Expected: true  Actual: <false>` | **FAIL** | idem | عالية |
| CHAR-R6-f | نقطة host `POST /api/users/<id>/password` بهوية admin | تعمل | مطابق | PASS | `api_routes_write.dart:106` | عالية |
| **REPRO-R6-g** | وجود مُنادٍ إنتاجي لـ `ClientWriteInterceptor.updateUserPassword` | ≥ 1 | `Expected: a value greater than <0>  Actual: <0>` | **FAIL** | `cwi_catalog_operations.dart:427-439` (دالة يتيمة) | عالية جدًا |

### R7 — هوية الـ admin على جهاز مقترن
| id | السيناريو | المتوقَّع | الفعلي | الحالة | الكود | الثقة |
|---|---|---|---|---|---|---|
| CHAR-R7-a | نافذة مفتوحة، admin بـ id 1 على الطرفين | admin المتزامن يحلّ محل المزروع (نفس id والهاش) | مطابق | PASS | `user_sync_strategy.dart:143-164` | عالية |
| **REPRO-R7-b** | admin على الـ host بـ id ≠ 1 (حالة PG موثَّقة في الكود) | يصل ولا يظلّله المزروع | `Expected: true  Actual: <false>` | **FAIL** | `user_sync_strategy.dart:48-55` ("never rename bootstrap admin" ⇒ `continue`) | متوسطة (الشرط البيئي حقيقي لكنه نادر) |
| **REPRO-R7-c** | تدوير كلمة admin على الـ host بعد المزامنة، نافذة مغلقة | الجهاز يتقارب (الجديدة تعمل أو القديمة تُبطل) | `Expected: true  Actual: <false>` — القديمة ما زالت تعمل والجديدة لا | **FAIL** | سبب القديمة: صف مكرر (R7-e)؛ سبب الجديدة: R2 | عالية |
| CHAR-R7-d | جلسة admin، نافذة مغلقة | الهاشات تُسلَّم | مطابق | PASS | `api_get_users.dart:26-31` | عالية |
| **REPRO-R7-e** | full sync ثم delta (نافذة مفتوحة، لا شيء شاذ) | صف `admin` نشط **واحد** | `Expected: [1]  Actual: [1, 1000000001]` | **FAIL** | admin المزروع له `global_id` مختلف ولا يوحّده `UserSyncStrategy` ⇒ `DeltaPullService` يعيد ترقيمه (`delta_pull_service.dart:~1170-1179`) ويُبقي الصفّين نشطين؛ هاش قديم صالح يبقى على الصف المكرر | عالية (ثابت في الاختبار؛ أثره التشغيلي يحتاج جهازًا حقيقيًا) |

## 4. أهم 10 عيوب مؤكَّدة (بالدليل)

1. **CRED-WIPE** — أي إعادة تسليم لصف مستخدم بلا اعتمادات تستبدل الهاش المحلي الصالح بـ `UnusableCredential`، لأن الحارسين يشترطان `salt` غير فارغ بينما صفوف Argon2 تُخزَّن بـ `salt=''` (`user_sync_strategy.dart:111-113`، `delta_pull_service.dart:1281`، `user_dao.dart:191,284`). *Evidence:* R2-a/b/c، R3-k، وسجلات `[DeltaPull] … stored an unusable credential`.
2. **المسارات التي تُشغَّل قبل الدخول بلا جلسة تُطلق العيب 1 تلقائيًا**: `main_desktop.dart:142-193` (`pullAll()` أو `fullSync()` عند كل إقلاع لـ client/mirror) و`login_screen.dart:142-170` (كلمة مرور خاطئة ⇒ سحب users بلا اعتمادات). على mirror لا يوجد fallback أصلًا. *Evidence:* R2-a، R3-e، R3-k.
3. **الاعتمادات مربوطة بنافذة الاقتران/الجلسة، وأول مزامنة قبل الدخول** ⇒ الجهاز المقترن بعد إغلاق النافذة لا يحصل على أي كلمة (admin المخصّصة ولا الأولية). *Evidence:* R1-e، R1-f.
4. **`admin/admin` الافتراضي يبقى صالحًا على الجهاز المقترن** (المزروع محميّ بالحارس نفسه) ⇒ خرق مباشر لمطلب "admin بكلمة مخصّصة فقط". *Evidence:* R1-d.
5. **تكرار admin بعد أول delta** (`id 1` + `1000000001`) لأن `global_id` المزروع ≠ الـhost ولا يوحّده `UserSyncStrategy`؛ الصف المكرر يُبقي هاشًا قديمًا صالحًا (تدوير الكلمة لا يُبطل القديمة). *Evidence:* R7-e، R7-c.
6. **تغيير الكلمة (الأولية أو إدارية) على client/mirror لا يصل الـ host أبدًا** — `ClientWriteInterceptor.updateUserPassword` بلا مُنادٍ؛ والمزامنة التالية تعيد الهاش القديم ⇒ دورة force-change لا تنتهي. *Evidence:* R6-c/d/e/g.
7. **عمليات إدارة المستخدمين من mirror (تعطيل/قفل/تغيير دور/كلمة) تُطبَّق محليًا بصمت** بينما `setUserBranchAccess` وحدها تُوجَّه للـ HQ ⇒ تناقض داخل `AuthRepositoryImpl`، وأول pull يعيد القديم. *Evidence:* R3-q مقابل R3-o.
8. **Mirror مُستثنى من مسارين في `login_screen`** (fallback سحب المستخدمين، وتحديث الدور/الصلاحيات بعد الدخول) ، وحارس `_bootTimeAdminHeal` (`!isClient`) يسمح بتشغيله على mirror. *Evidence:* R3-e/f/g، R3-l.
9. **`GET /api/users` لمدير متعدّد الفروع (mirror) يعيد مستخدمي الفرع الأول فقط** (FR-1 مطبَّق على sync-pull فقط)، وعلم `forcePasswordChange` لا يصل بالـ full sync. *Evidence:* R3-j، R6-a. (ويُضاف: جلسة أي كاشير تتسلّم هاش admin — R1-g.)
10. **`neverVerified` لا ينتهي أبدًا** على جهاز لم يتصل بالخادم، و**admin غير مستثنى من مهلة offline**، و**مفاتيح الـ committer الثلاثة غير device-local** (تُسحب من الـ host). *Evidence:* R5-f، R5-g، R4-g.

## 5. ثبات النمط (R4) — خلاصة صادقة

لم أستطع إعادة إنتاج بلاغ "اختيار mirror في first-run لا يثبت" داخل الـ harness: ‏النمط يثبت (R4-a/b/c) عندما تنجح مرحلة first-sync. الفرضيات القائمة على القراءة وغير المُختبرة بسبب BLOCKED-R4-e:
- فشل `performFirstSync` داخل `DeploymentModeCommitter` يُرجع `CommitFailed` ويستدعي `_rollbackPairing()` فيمسح `MirrorState` (`deployment_mode_committer.dart:170,186,215,530-543`) فيبقى الجهاز بلا mirror ويُضطر المستخدم لـ Dev Tools.
- هوية الاقتران محفوظة في SharedPreferences فقط (R4-f).
لذلك يُوصى بإعادة إنتاجه بجهاز + host حقيقيين، أو ببناء host في Isolate (انظر الحدود).

## 6. حدود الـ Harness (ما لم يُشغَّل فعلًا)

- لا sockets/TLS ولا `ServerProxy` HTTP؛ `GET`ات الـ router تُحقَن مباشرة. لذا `acquireSession` يفشل بسرعة (الـ host `127.0.0.1:1`) ولا يُختبر مسار `X-Session-Token` الحقيقي إلا عبر حقن `ApiUserCtx.userIdKey`.
- لا UI: فحوص `login_screen.dart` و`main.dart` ثابتة (قراءة المصدر حول الـ anchor) وليست تنفيذًا للشاشة؛ وقابلة للكسر إن تغيّر نصّ الـ anchor (مذكور في كل اختبار).
- `performFirstSync` الحقيقي (HTTP) غير مُشغَّل ⇒ BLOCKED-R4-e؛ ولم يُختبر boot الحقيقي (`main.dart`) بل `reconcileWithDb` فقط.
- PostgreSQL غير مُغطّى (SQLite في الذاكرة على الطرفين)؛ ومسألة `admin id ≠ 1` (R7-b) أُعيد إنتاجها بإعادة ترقيم الصف في SQLite.
- `forTesting()` لا يفرض FK؛ أُدرج دور مخصّص في الـ client يدويًا ليحاكي مزامنة roles السابقة لـ users.
- المهلة/الساعة لـ R5 محقونة؛ لم يُختبر `SecureStorageService` الحقيقي.
- أرقام الأسطر مأخوذة من قراءتي لـ HEAD الحالي وقد تنزاح.
