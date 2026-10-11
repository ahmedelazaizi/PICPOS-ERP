# خريطة الدخول إلى معمارية PicPos ERP

> وثيقة للمطوّر الجديد. كُتبت بقراءة الكود الفعلي (`ls`/`grep`) في الفرع الحالي، والمصطلحات التقنية بالإنجليزية كما في الكود.
> الملخّص المختصر في [`ARCHITECTURE.md`](../ARCHITECTURE.md)، وهذه الوثيقة هي التفصيل.
> ما لم يمكن التحقق منه مذكور في §8. الأرقام لقطة وقت الكتابة.

## 0. القراءة بالترتيب

1. [`README.md`](../README.md) — المكوّنات والأوامر. [`PRODUCT.md`](../PRODUCT.md) و[`DESIGN.md`](../DESIGN.md) — المنتج ونظام التصميم.
2. هذه الوثيقة، ثم [`docs/handoff/SYNC_ARCHITECTURE.md`](handoff/SYNC_ARCHITECTURE.md) (المزامنة: outbox، FK tiers، conflict policies).
3. الجوال والسيرفر: [`docs/mobile/ARCHITECTURE-I.md`](mobile/ARCHITECTURE-I.md) (السيرفر السحابي + تطبيق المندوب، منفَّذ جزئيًا)، و[`ARCHITECTURE-M.md`](mobile/ARCHITECTURE-M.md) / [`ARCHITECTURE-MC.md`](mobile/ARCHITECTURE-MC.md) (ترويستاهما «plan only»).
4. الاختبارات: [`docs/testing/E2E.md`](testing/E2E.md). الويب: [`2026-09-01-saas-web-design.md`](superpowers/specs/2026-09-01-saas-web-design.md) و[`2026-web-write-audit.md`](superpowers/specs/2026-web-write-audit.md). الأمن: §5.
5. `docs/handoff` أرشيف تاريخي متراكم (آخره `2026-09-03-next-session-prompt.md`)، وليس مرجعًا حيًّا.

## 1. خريطة المجلدات

### 1.1 الجذر

| المسار | الدور |
|---|---|
| `lib/` | تطبيق Windows desktop (Flutter) + نقطة دخول الويب. المنتج الأساسي. |
| `web/` | قوالب Flutter web فقط (`index.html`, `manifest.json`, `sqlite3.wasm`, `icons/`). **لا كود Dart هنا.** |
| `windows/` | مشروع Windows (CMake / Runner). |
| `mobile/` `mobile_admin/` `mobile_pos/` | تطبيقات Android: Van (`picpos_van`) · Admin (`picpos_admin`) · Cashier (`picpos_pos`). لكلٍّ `lib/` و`test/` و`pubspec.yaml` وREADME. |
| `packages/` | `picpos_rules` · `picpos_api_client` · `picpos_ui` · `picpos_device` (فعّالة)، و`accounting core inventory pos shared_widgets treasury` (هياكل قديمة — راجع `docs/mobile/ARCHITECTURE-M.md` F12). |
| `server/` | السيرفر السحابي `picpos_cloud` (Dart خالص، `shelf` + PostgreSQL): `bin/`, `lib/src/{http,service,db,whatsapp}`, `test/` (+ `test/e2e`). |
| `test/` | اختبارات الجذر — §4. |
| `tool/` | `run_e2e.ps1`, `run_sqlcipher_tests.ps1`, `check_no_secrets.ps1`, `make_release_checksums.ps1`, `fetch_prereqs.ps1`, `sign_file.cmd`, `gen_*.dart`، ومجلدات `i18n/` `license/` `perf/` `mobile_icons/`. |
| `scripts/` | `gate.sh` (بوابة جودة محلية)، `check_coverage.dart`، `run_pg_tests.dart`، `git-hooks/`، سكربتات SQL وصيانة. |
| `tools/` | أدوات التفعيل/الترخيص (`picpos-activation/`) وإرشادات `postgresql_setup_guide.md`. |
| `docs/` | الوثائق: `audit/ handoff/ i18n/ mobile/ perf/ security/ superpowers/ testing/` + `DEPLOYMENT.md`. |
| `installer/` | Inno Setup (`setup.iss`) وأصول المثبّت. |
| `docker/` | حزمة اختبار (PostgreSQL + API) — **للاختبار فقط**. |
| `.github/workflows/ci.yml` | خط CI الوحيد. |
| `supabase/` `web_app/` `db/` `patches-for-uralcash/` | موجودة؛ لم أتحقق من أنها ضمن مسار التسليم (§8). |

### 1.2 `lib/` — الطبقات

```
lib/
  main.dart · main_desktop.dart · main_web.dart · main_web_entry.dart   نقاط الدخول (الويب: main_web_entry.dart)
  app_main_screen.dart        الغلاف: ScreenConfig لكل شاشة (فرع العلامة هنا)
  core/                       config(Brand, AppFlavor) · auth · permissions · navigation(ScreenId, ScreenRegistry)
                              enums(AppScreen) · errors · i18n(tr) · logging · networking · tax · theme · design_system · widgets ...
  data/
    database/                 Drift: database.dart (+ parts) — §2.3
    repositories/             واجهات/تنفيذات Drift (drift_*_repository, *_impl)
    repositories_impl/ · mappers/ · providers/ · services/
  domain/                     entities · models · printing · repositories(واجهات) · usecases
  application/services/
  services/                   الخدمات — §1.4
  presentation/               الشاشات — §1.3
  web/                        عميل الويب — §1.5
  l10n/                       app_ar.arb · app_en.arb
```

### 1.3 `lib/presentation/`

- نمط **`<feature>_picpos/`**: شاشات إعادة التصميم (PicPos) لكل ميزة (`sales_invoices_picpos`, `treasury_picpos`, `hr_picpos`, `pos_picpos`, `tables_picpos`, `reports_picpos`…). بجانبها مجلدات «الشاشة المشتركة» القديمة (`screens/`, `pos/`, `treasury/`, `settings/`, `products/`…) التي ما زالت تخدم علامة UralCash.
- `picpos_shell/`: لبنات UI المشتركة لشاشات PicPos (`picpos_screen_scaffold.dart`, `picpos_page_header.dart`, `picpos_data_table.dart`, `picpos_dialog.dart`, `picpos_filter_strip.dart`…). `shell/`: الإطار العام (`app_shell.dart`, `nav_widgets.dart`).
- `providers/` Riverpod، `shared_widgets/`، `widgets/`، `dialogs/`، `db_key/` (شاشة حجب مفتاح القاعدة).
- حارس `test/static/picpos_screen_fork_guard_test.dart` يشترط أن شاشةً لها توأم picpos تتفرّع بـ`Brand.isPicPos`.

### 1.4 `lib/services/`

| المجلد/الملف | الدور |
|---|---|
| `api/` | خادم HTTP المضمَّن (`shelf`): `api_handler.dart` (الموجّه) + `routes/`، `api_data_handler.dart` + `data/`، ومعالجات النطاقات `api_sales_/purchase_/product_/party_/voucher_/auth_/web_session_/terminals_/display_handler.dart`، والوسائط: `api_auth_middleware.dart`, `api_session_token.dart`, `api_user_context.dart`, `api_rate_limiter.dart`, `api_errors.dart`, `server_secrets.dart`, `web_session_guard.dart`, `web_security_headers.dart`. |
| `web_read/` | قناة `/webdb` للقراءة: `web_read_channel_host.dart`, `web_read_policy_interceptor.dart`, `drift_json_channel.dart`. |
| `interceptor/` | تنفيذ `ClientWriteInterceptor` (`cwi_core.dart`, `cwi_catalog_*`, `cwi_commerce`, `cwi_sync_*`, `cwi_trading_*`, `cwi_vouchers`, `cwi_admin`). نقطة الدخول `lib/services/client_write_interceptor.dart` (~1.7KB) فقط. |
| `sync/` + `delta_pull_service.dart` | المزامنة LAN: `sync_strategy.dart`, `sync_worker.dart`, `client_first_sync_service.dart`, `mirror_*`. قائمة `pullTables` في `delta_pull_service.dart`. |
| `cloud_sync/` | المزامنة مع السيرفر السحابي: `cloud_sync_service.dart`, `cloud_link_*`, `cloud_*_poster.dart`, `cloud_master_exporter.dart`. |
| `scale_protocols.dart` + `scale_protocols/` | بروتوكولات الموازين (CAS, Digi, Aclas, Rongta, Mettler Toledo, TEM, Dibal, NVK) — §2.1. |
| `db_key_*.dart`, `sqlcipher_engine.dart`, `db_encryption_actions.dart`, `security_service.dart`, `secret_store.dart` | مفتاح القاعدة والتشفير — §5. |
| `admin/`, `auth/`, `backup/`, `cfd/`, `deployment/`, `e_invoicing/`, `generators/`, `logging/`, `printing/`, `admin_snapshots/` | خدمات متخصصة. |

### 1.5 الويب
- `lib/main_web_entry.dart` ← `lib/web/` (`web_shell.dart`, `web_session.dart`, `web_providers.dart`, `web_remote_connection.dart`, `web_screen_registry.dart`, `web_screen_scope.dart`, `web_write_guard.dart`).
- الويب **عميل مرآة**: قراءة عبر `/webdb` (drift remote) وكتابة عبر HTTP API. الحارس `test/structural/web_entry_scope_test.dart` يمنع وصول سلسلة الاستيراد من نقطة الويب إلى شاشات POS/مطبخ/طاولات/ميزان/إقفال وردية/اختبار طباعة.
- بناء الويب: `-t lib/main_web_entry.dart` (§6).

## 2. الملفات المقسَّمة: `part` / `part of`

**الفكرة:** ملف ضخم قُسِّم إلى ملفات أصغر **بلا تغيير سلوك**. الملف الأم هو الـlibrary ويعلن `part 'x.dart';`، وكل ملف فرعي أوله `part of '…';`، فتبقى كل الأعضاء الخاصة (`_name`) مشتركة. الأجزاء عادةً `extension` على الصنف الأم.

### 2.1 جدول الأجزاء

| الأم | الأجزاء | الملاحظة |
|---|---|---|
| `ApiHandler` — `lib/services/api/api_handler.dart` (~7.8KB) | `lib/services/api/routes/*.dart` | `api_routes_read/write/auth_public.dart` تسجّل المسارات؛ `api_get_*.dart` معالجات GET؛ `api_sync_pull_tables.dart`, `api_branch_scope.dart`. **ترتيب التسجيل أمني** (أول تطابق يفوز). |
| `ApiDataHandler` — `lib/services/api/api_data_handler.dart` (~6.8KB) | `lib/services/api/data/api_data_*.dart` (12 ملفًا: accounting, attachments, cash, commercial_papers, documents, expenses, inventory, operations, org_structure, system, treasury, users_roles) | كل جزء `extension ApiData…Routes on ApiDataHandler`. أوله `part of '../api_data_handler.dart';`. |
| `AppDatabase` — `lib/data/database/database.dart` (~40KB) | جداول: `tables/*_tables.dart` (34 ملفًا) · DAOs: `daos/*.dart` · ترحيلات: `migrations/epoch_1..3.dart` · مخططات خام: `*_schema.dart` · `database_*.dart` (seeder, startup, migrations, numbering, pg_create, pg_parity, pg_sync_infra, sql_constants, types, misc_dao_methods, schema_history, design_notes) · `models/projections.dart` | كل DAO هو `extension XDao on AppDatabase`. `database.g.dart` مولَّد (~8.7MB) ومُلتزَم في الريبو. |
| `TreasuryDao` — `daos/treasury_dao.dart` | `treasury_shift_dao`, `treasury_shift_models`, `treasury_shift_settlement_dao`, `treasury_shift_close_safes_dao`, `treasury_shift_aggregates_dao`, `treasury_safe_queries_dao`, `treasury_safe_resolution_dao`, `treasury_safe_linking_dao`, `treasury_transactions_dao`, `treasury_voucher_dao`, `treasury_reports_dao` | كلها مُعلَنة في `database.dart` (`part 'daos/treasury_*'`) وأول سطر في كلٍّ منها `part of '../database.dart';`. |
| `scale_protocols.dart` | `lib/services/scale_protocols/*.dart` (16 ملفًا: `aclas_*`, `cas_protocol`, `digi_protocol`, `dibal_protocol`, `mettler_toledo_protocol`, `nvk_protocol`, `tem_protocol`, `rongta_*`, `csv_upload`, `tcp_upload_helpers`, `brand_dispatch`, `upload_types`) | الجذر ~8.7KB. |
| `picpos_pos_screen.dart` | `lib/presentation/pos_picpos/screens/picpos_pos_*.dart` (`operations`, `decisions`, `product_entry`, `barcode_scan`, `cart_edit`, `checkout`, `checkout_support`, `invoice_actions`, `return`, `exchange`, `drawer`, حواران quick-return) | `picpos_pos_operations.dart` نسخة مقلَّصة مقصودة من منطق POS الأصلي (شرح الرأس). |
| `ClientWriteInterceptor` | `lib/services/interceptor/cwi_*.dart` | **ليست `part`**: ملفات عادية يجمعها المدخل `client_write_interceptor.dart`. |

### 2.2 قواعد العمل مع الأجزاء
1. **نقل بحت:** عند التقسيم انقل الكود حرفيًا؛ لا إعادة صياغة ولا تغيير ترتيب/سلوك في نفس الـcommit.
2. الجزء الجديد: أضف `part 'مسار.dart';` في الأم، وأول سطر في الجزء `part of '…';` بمسار نسبي صحيح (`'../api_data_handler.dart'` من مجلد فرعي).
3. **اختبارات source-grep** تقرأ المصدر المقسَّم عبر helpers: `test/helpers/api_handler_source.dart` (يقرأ `api_handler.dart` + `routes/`) و`api_data_handler_source.dart` (+ `data/`) و`database_source.dart`. إن أضفت مجلد أجزاء جديدًا لأصل آخر فأنشئ helper مثلها بدل أن تكسر الحراس.
4. بعد التقسيم **اخفض عتبة** الملف في CI (§4.4)، ولا ترفعها.
5. بعد أي تعديل في الجداول/الأعمدة: أعد توليد `database.g.dart` محليًا وأرفقه بالـcommit (CI لا يشغّل codegen).

## 3. وصفات: أين أضيف…؟

### 3.1 نقطة API جديدة (على الخادم المضمَّن)
1. اكتب المعالج: في الجزء المناسب من `lib/services/api/data/` (امتداد `ApiDataHandler`)، أو في معالج النطاق الموجود (`api_sales_handler.dart`…)، أو ملف جزء جديد (ثم `part` في `api_data_handler.dart`).
2. صلاحية أولًا: `ApiUserCtx.requirePermission(request, db, PermissionCodes.xxx)` (`api_user_context.dart`، الرموز في `lib/core/permissions/permission_codes.dart`).
3. الأخطاء: عبر `ApiErrors` (`api_errors.dart`) — لا تُرجع `$e` خامًا للعميل.
4. سجّل المسار في `lib/services/api/routes/api_routes_write.dart` (POST/PUT/DELETE) أو `api_routes_read.dart` + `api_get_*.dart` (GET). راعِ الترتيب.
5. إن كان المسار حرجًا ماليًا راجع تصنيف `RateLimitClass` في `api_rate_limiter.dart`. وإن كان يجب أن يقبله رمز **الويب** فأضف البادئة في `webWritePrefixes` (`api_auth_middleware.dart`) والقائمة البيضاء في `web_session_guard.dart`؛ وإلا فهو مرفوض للويب.
6. من طرف العميل: مرّر الكتابة عبر `ClientWriteInterceptor.dispatchWrite` (أضف الدالة في `interceptor/cwi_*.dart` المناسب) — حارسا `mirror_write_dispatch_test` و`no_bare_client_write_submit_test` يمنعان النداء العاري.
7. **حدّث** `test/golden/api_routes.txt` (نفس ترتيب التسجيل) وشغّل `test/unit/api_routes_golden_test.dart`.
8. اختبارات واجبة: وحدة/تكامل للمعالج، و`test/unit/api_handler_perm_gate_grep_test.dart` لبوابة الصلاحية.

### 3.2 شاشة جديدة
1. الشاشة في `lib/presentation/<feature>_picpos/screens/` (وللويب أيضًا: لا تستورد ما تمنعه `web_entry_scope_test.dart`). استعمل لبنات `picpos_shell/`.
2. سجّلها: قيمة في `lib/core/enums/app_screen.dart` و`ScreenId` في `lib/core/navigation/screen_id.dart`، وأدرجها في ملفات الشاشات حسب النشاط في `screen_registry.dart`، ثم `ScreenConfig(appScreen:, builder:, label:, icon:)` في `lib/app_main_screen.dart` — **مع فرع `Brand.isPicPos`** إن كان لها توأم قديم.
3. صلاحية: رمز في `permission_codes.dart` + بذرته في `lib/data/database/database_seeder_permissions.dart` + إنفاذ فعلي في الشاشة (`picpos_permission_parity_test`).
4. نصوص: `tr('…')` (`lib/core/i18n/tr.dart`) وملفات `lib/l10n/*.arb`؛ يفحصها `i18n_coverage_test.dart`.
5. للويب (اختياري): `kWebScreenIds` في `lib/web/web_screen_scope.dart` وباني في `web_screen_registry.dart`، بشرط ألا تسحب POS/مطبخ/ميزان.
6. اختبارات: widget لها؛ وتأكد من `screenconfig_builds_the_picpos_fork_test`, `allowed_screens_can_render_test`, `screen_tabs_are_wired_test`, `picpos_screen_fork_guard_test`. شاشات التقارير: `report_screens_all_smoked_test`, `reports_hub_groups_test`.

### 3.3 جدول جديد (Drift)
1. عرّف الصنف في ملف `lib/data/database/tables/<x>_tables.dart` (`part of '../database.dart';`) — أو جدول SQL خام في `*_schema.dart` للأنماط الحديثة.
2. أضف `part 'tables/<x>_tables.dart';` والصنف في `tables: [...]` داخل `@DriftDatabase` في `database.dart`.
3. DAO: ملف `daos/<x>_dao.dart` (`extension … on AppDatabase`) + `part` في `database.dart`.
4. ارفع `schemaVersion` وأضف الترحيل — §3.4.
5. أعد توليد `database.g.dart` (build_runner) محليًا وأرفقه.
6. **المزامنة:** إن كان الجدول يُزامَن فأضفه إلى `pullTables` (`delta_pull_service.dart`)، و`_syncPullTables` (`api/routes/api_sync_pull_tables.dart`)، و`_syncHardenedTables` في `database.dart` (ختم `last_modified_at` على PostgreSQL). وإن لم يُزامَن فسجّل ذلك صراحةً — حراس: `sync_coverage_guard_test`, `sync_column_membership_guard_test`, `pg_sync_hardened_tables_guard_test`, `unsynced_tables_have_no_writer_test`.
7. PostgreSQL parity: راجع `database_pg_create.dart` / `database_pg_parity.dart` (اختبار `test/unit/pg_schema_parity_static_test.dart`).
8. ويب: الجدول لا يظهر في `/webdb` إلا بإضافته لسياسة `WebTablePolicy` (`lib/core/permissions/web_table_policy.dart`) — الافتراضي الرفض.

### 3.4 ترحيل جديد (Migration)
1. ارفع `int get schemaVersion` في `database.dart` (الحالي **195**).
2. أضف كتلة `if (from < N) { … }` في **نهاية** `_migrateEpoch3` في `lib/data/database/migrations/epoch_3.dart` (يعمل `_migrateEpoch3` دائمًا، أما epoch 1 فعند `from < 60` وepoch 2 عند `from < 81` — `database_migrations.dart`).
3. لفّ كل خطوة DDL بـ`_safeMigrate('vN …', () => …)`، وبصيغة idempotent (`IF NOT EXISTS`). `ADD COLUMN … UNIQUE` غير مسموح في SQLite: عمود عادي + فهرس فريد جزئي.
4. تجنّب `m.alterTable` على جدول مُزامَن (`alter_table_sync_columns_guard_test`).
5. أضف سطر التاريخ في `database_schema_history.dart` (تعليقات فقط).
6. حراس/اختبارات: `test/structural/migration_numbering_test.dart` (ترقيم الدمج)، اختبار ترحيل في `test/integration/` ينطلق من قاعدة قديمة، و`ensureSchemaDefaults` في `database_startup.dart` كطبقة دفاع إضافية.
7. لا تحرّر ترحيلًا قديمًا مُنشَرًا؛ أضف جديدًا.
8. السيرفر السحابي له ترحيلاته المستقلة: `server/lib/src/db/migrations.dart`.

## 4. الاختبارات و CI

### 4.1 بنية `test/`
`unit/` (الأكبر) · `widget/` · `integration/` · `integration_pg/` (وسم `pg` — مُتخطّى افتراضيًا بـ`dart_test.yaml`) · `structural/` (حراس بنيوية — §4.3) · `static/` · `e2e/` · `golden/` (`api_routes.txt`) · `goldens/` (صور) · `helpers/` · `core/ data/ domain/ presentation/ security/ services/ perf/ spike/`.

### 4.2 التشغيل
```powershell
flutter test                                   # اختبارات الجذر (لا تشغّل أمري flutter بالتوازي)
flutter test test/structural                   # الحراس البنيوية
flutter test test/unit/api_routes_golden_test.dart
powershell -NoProfile -ExecutionPolicy Bypass -File tool/run_e2e.ps1          # E2E (-Only server,mobile …)
powershell -NoProfile -ExecutionPolicy Bypass -File tool\run_sqlcipher_tests.ps1   # محرّك SQLCipher الحقيقي
cd server; dart test -j 1                      # السيرفر (تتابعي)
dart run scripts/run_pg_tests.dart             # integration_pg على PostgreSQL حقيقي
```
- `tool\run_sqlcipher_tests.ps1`: يبدّل مؤقتًا `sqlite3.dll` في `.dart_tool` بـDLL الخاصة بـSQLCipher ثم يعيدها (تحتاج بناء `flutter build windows --release` سابقًا أو `PICPOS_SQLCIPHER_DLL`)، ويضبط `PICPOS_REQUIRE_SQLCIPHER=1`. الافتراضي: `db_key_rekey_engine_test` و`db_key_real_engine_test`. التفاصيل: [`docs/security/db-key-engine-validation.md`](security/db-key-engine-validation.md).
- `tool/run_e2e.ps1`: Postgres (docker) ← server ← packages ← mobile ← mobile_admin ← mobile_pos ← root ← web. التفاصيل: [`docs/testing/E2E.md`](testing/E2E.md).
- `scripts/gate.sh`: بوابة محلية (تنظيف `build/native_assets`، analyze، السويّات، `--pg` اختياري).

### 4.3 ماذا تحرس 	est/structural و	est/static (أمثلة)
- **المزامنة:** `sync_coverage_guard`, `sync_column_membership_guard`, `pg_sync_hardened_tables_guard`, `unsynced_tables_have_no_writer`.
- **الكتابة/الترحيل:** `mirror_write_dispatch`, `no_bare_client_write_submit`, `migration_numbering`, `alter_table_sync_columns_guard`.
- **الويب:** `web_entry_scope`, `static/no_direct_network_mode_writes`.
- **واجهة PicPos:** `static/picpos_screen_fork_guard`, `screenconfig_builds_the_picpos_fork`, `dark_mode_guard`, `pdf_pages_are_rtl`.
- **المال والصلاحيات:** `journal_balance_single_rule`, `safe_balance_single_write`, `picpos_permission_parity`, `no_legacy_password_kdf`.
- **مسارات API:** `test/unit/api_routes_golden_test.dart` يقارن قائمة (method, path) المسجَّلة بـ`test/golden/api_routes.txt` ويبني الـrouter فعليًا ليتأكد أن كل GET بلا بارامترات يُحل إلى معالج لا إلى 404 الـcatch-all.
### 4.4 سياسة CI (`.github/workflows/ci.yml`)
- يعمل على كل push وpull_request؛ وبناء Windows على `main` ووسوم `v*.*.*`؛ والإصدار على الوسوم.
- الوظائف: `secrets` → `gitleaks` (استشاري) · `root_static` (`flutter analyze lib/` + بوابة الأحجام) · `root_tests` (12 shard) · `coverage_gate` · `packages_and_mobile` · `server` (Postgres 16) · `e2e` (Linux) · `web` · `build-windows` · `release`.
- **Shards:** تُقسَّم **حسب الملف** (لا `--shard-index`): `find test -name '*_test.dart' -not -path 'test/e2e/*'`، ترتيب `LC_ALL=C sort`، الملف رقم i إلى الشارد `(i % 12)+1`. يفشل إن زاد طول قائمة المسارات عن 7500 حرف (حد cmd.exe)، فارفع عدد الـshards عندئذٍ.
- **التغطية:** يدمج `coverage_gate` ملفات lcov ويطبّق **حدًّا أدنى 18%** (أرضية انحدار لا طموح؛ المقاس ≈21% وقت كتابة التعليق) — ارفعه ولا تخفضه.
- **بوابة الأحجام (God-File):** في `root_static` جدول `THRESHOLDS` (بايت، بعد حذف CR) لملفات: `tables_screen`, `pos_table_service_screen`, `client_write_interceptor`, ملفات `interceptor/cwi_*`, `treasury_voucher_dao`, `treasury_dao`, `api_data_handler`, `api_handler`, `database.dart`, `scale_protocols.dart`. القاعدة المكتوبة: *«اخفض العتبة عند التقسيم ولا ترفعها أبدًا»*. مثال: `database.dart` ≈39,989 مقابل 40,500.


## 5. الأمن (ملخّص المبادئ)

| المبدأ | كيف يتحقق في الكود |
|---|---|
| **الويب: قراءة فقط عبر `/webdb`** مع سياسة جداول | `web_read_channel_host.dart` يستهلك تذكرة (مرة واحدة، 30 ث)، ويحسب الجداول من أكواد المستخدم (`WebTablePolicy.allowedTables`)، ويلفّ المنفِّذ بـ`WebReadPolicyInterceptor`: كل الكتابات والمعاملات مرفوضة؛ `runSelect` أمر واحد SELECT/WITH بلا PRAGMA/ATTACH/sqlite_master/pg_*؛ جداول FROM/JOIN ضمن القائمة المسموحة؛ الأعمدة الحساسة تُفرَّغ. **الرفض عند الشك.** |
| **الكتابة من الويب عبر HTTP** | تمر عبر `ClientWriteInterceptor` إلى API بصلاحية المستخدم؛ دوال `AppDatabase` التي تكتب مباشرة تُمنع بـ`WebWriteGuard` برسالة عربية ([`2026-web-write-audit.md`](superpowers/specs/2026-web-write-audit.md)). رمز الويب يقبل فقط `webWritePrefixes` المسموحة. |
| **فصل أسرار الخادم عن مفتاح القاعدة** | `ServerSecrets` (`lib/services/api/server_secrets.dart`) يولّد سرّين عشوائيين مستقلّين (جلسات + رموز فواتير الطاولات) في `SecretStore`، ويُنشئها `NetworkService` — لا اشتقاق من مفتاح SQLCipher. |
| **ترحيل مفتاح القاعدة (يدوي)** | المفتاح القديم مشتق من الجهاز؛ الجديد عشوائي 256-bit في `flutter_secure_storage` بترحيل `sqlcipher_export` إلى ملف جديد فتحقق فتبديل مع **تأكيد في الإقلاع التالي**. تبدأه إجراءات المدير (`db_encryption_actions.dart`: حالات `legacy → requested → pendingConfirm → migrated`) وتنفّذه `db_key_migration_service.dart` عند الإقلاع قبل فتح القاعدة (`resolveDatabaseKey` في `db_key_startup.dart`). مفتاح مفقود لقاعدة مرحَّلة ⇒ شاشة حجب (`presentation/db_key/db_key_blocked_screen.dart`) ولا قاعدة فارغة أبدًا. |
| **الجلسات والإبطال** | HMAC sessions (`api_session_token.dart`)؛ رمز الويب 12 ساعة؛ `POST /api/web/logout` يستدعي `revokeSid`، و`revokeUser` يُبطل جلسات مستخدم، و`WebSessionGuard` يتحقق من حال المستخدم (كاش ≤15 ث)، وقناة `/webdb` تُغلق بالرمز 4401 عند تعطيل المستخدم أو تغيّر صلاحياته. حدود المعدل (`api_rate_limiter.dart`, `server_login_throttle.dart`). |
| **الأخطاء المركزية** | `ApiErrors`: التفاصيل (e + stack) تُسجَّل محليًا فقط ويُرجَع `{"error":"internal_error","request_id":…}`؛ رسائل الأعمال المقصودة تبقى كما هي لأن `OfflineSyncWorker` يصنّف الفشل الدائم بنصها. |

مراجع (مراجعات أمنية بتاريخها — **تحقق من حال كل بند في الكود**؛ مثلًا `part2b-api-auth.md` كان يصف `revokeSid` ككود ميت لكنه يُستعمل الآن في `logout`):
[`part1-cloud-mobile.md`](security/part1-cloud-mobile.md) · [`part2a-webdb.md`](security/part2a-webdb.md) · [`part2b-api-auth.md`](security/part2b-api-auth.md) · [`part3-secrets-supplychain.md`](security/part3-secrets-supplychain.md) · [`db-key-design.md`](security/db-key-design.md) · [`db-key-engine-validation.md`](security/db-key-engine-validation.md) · [`release-integrity.md`](security/release-integrity.md).

## 6. أوامر التشغيل والبناء

```powershell
flutter pub get
# Desktop (Windows) — مرّر APP_BRAND دائمًا: الافتراضي عند غيابه uralcash
flutter run -d windows --dart-define=APP_BRAND=picpos --dart-define=APP_FLAVOR=unified
.\build_picpos.bat                 # بناء الإصدار (يفحص عزل العلامة، يحذف build\windows، يتحقق من SQLCipher؛ المخرجات FlavorBuilds\PicPos)
.\build_installer_picpos.bat       # المثبّت (بعد build_picpos.bat)
# الويب
flutter build web --release --no-tree-shake-icons --no-wasm-dry-run -t lib/main_web_entry.dart
# الجوال (من مجلد كل تطبيق)
cd mobile; flutter build apk --release        # كذلك mobile_admin و mobile_pos
# السيرفر السحابي
cd server; dart run bin/server.dart           # متغيرات البيئة: server/README.md
# حزمة Docker التجريبية (اختبار فقط): postgres:55432 · api:18080
cd docker; docker compose up -d --build; curl.exe http://localhost:18080/health
```
ملفات `.bat` يجب أن تبقى ASCII فقط (تعليق في رأس `build_picpos.bat`). النشر المحلي: [`docs/DEPLOYMENT.md`](DEPLOYMENT.md).

## 7. قواعد المساهمة

1. **حجم الملف:** الملفات **الجديدة ≤ 30KB**. (القاعدة مطلوبة من فريق المشروع؛ لا يفرضها اختبار أو CI — فقط عتبات God-File المحددة. يوجد اليوم ملفات قديمة كثيرة تتجاوزها: ≈186 ملف Dart غير مولَّد تتخطى 30KB.) لا تُضخِّم ملفًا قريبًا من عتبته.
2. **التقسيم = نقل بحت** (§2.2) ثم تخفيض العتبة في `ci.yml`.
3. **لا أسرار في الريبو:** شغّل `powershell -File tool/check_no_secrets.ps1` (يفشل إن تُتُبِّع `*.jks`/`key.properties`/`google-services.json`…)، وإعدادات Gitleaks في `.gitleaks.toml`. القوالب: `.env.example` بقيم وهمية. كلمات مرور docker للاختبار فقط.
4. **العلامتان `picpos` و`uralcash`:** تُحدَّدان وقت البناء بـ`--dart-define=APP_BRAND` (`lib/core/config/brand.dart`؛ **الافتراضي `uralcash`**). المنتج الحالي PicPos؛ فرّع الواجهة بـ`Brand.isPicPos`، ولا تُظهر أسماء UralCash في منتج PicPos. `build_picpos.bat` ينفّذ `APP_BRAND=picpos APP_FLAVOR=unified`، و`build_release.bat` يخص UralCash. الـflavors: `lib/core/config/app_flavor.dart`.
5. **مبدأ الطبقات:** يُفضَّل أن تمر الشاشات عبر Repositories/providers لا `AppDatabase` مباشرةً (تنبيه: ≈140 ملفًا في `presentation/` تلامس `databaseProvider`/`AppDatabase` اليوم — المبدأ غير مُطبَّق بالكامل).
6. **الاختبار مع كل تغيير:** حارس أو اختبار يفشل بدون إصلاحك. اللغة: التعليقات والنصوص كما في الملف المجاور (عربي/إنجليزي).
7. لا تشغّل أوامر `flutter` متوازية (قفل الإقلاع وتعارض `sqlite3.dll`).

## 8. ما لم يتم التحقق منه

- لم أشغّل `flutter` ولا أي اختبار أو بناء: كل ما سبق من القراءة والبحث النصي، ولا أدّعي أن أي اختبار مذكور ينجح.
- لم أفتح كل الحراس في §4.3 بل رؤوس عيّنة منها (الأسماء موجودة فعلًا).
- `supabase/`, `web_app/`, `db/`, `patches-for-uralcash/`, `tools/` وحزم `packages/` القديمة: لم أتحقق من حالتها.
- `scripts/git-hooks/pre-commit` يستدعي `pre-commit-schema-parity.ps1` وهو **غير موجود** في المجلد (الـhook تحذيري ويتخطاه).
- حالة بنود المراجعات الأمنية: تحقّقت فقط من `logout/revokeSid/ServerSecrets/ApiErrors/WebReadPolicyInterceptor`.
- وصفات §3 مبنية على تتبّع الملفات وأسماء الحراس؛ جرّبها على حالة صغيرة (قد توجد حراس إضافية).
