# دراسة الواجهات وصحة المشروع — 2026-10-30

> دراسة قراءة فقط: لم يُعدَّل أي ملف مصدر. الملف الوحيد المُنشأ هو هذا التقرير (ومؤقتٌ حُذف: `.analyze_tmp.txt`).
> **حدود الدراسة:** لم أُحمِّل مهارة `impeccable` (وفّرتُ التوكنز)؛ المراجعة البصرية هنا **ساكنة من الكود** (grep + قراءة) دون تشغيل التطبيق أو لقطات شاشة، فكل بند «تداخل ألوان» هو **خطر مرشّح** يحتاج مرور عين في الوضعين قبل الحكم النهائي.
> الأرقام أدناه من `grep` على `lib/presentation` (925 ملف).

---

## (أ) مراجعة تصميم الواجهات

### أ.1 الصورة العامة (أرقام)

| المؤشر | العدد | الدلالة |
|---|---|---|
| `fontSize:` رقمية مباشرة | ~3678 | أغلب النصوص تتجاهل `textTheme` |
| `TextStyle(` | ~3942 | معظمها بلا `color` ⇒ يرث لون الأب/الثيم، والباقي لون ثابت |
| `Colors.white` | 874 | خلفيات/نصوص ثابتة |
| `Color(0xFF…)` | 628 | ألوان صلبة خارج `ColorScheme` |
| `Colors.grey/blueGrey` | 458 | رمادي ثابت لا يتبدّل بالوضع |
| `AppColors.textPrimary/textSecondary` | 74 / 79 | ألوان **داكنة ثابتة** للنص (`#374151` للثانوي) ⇒ خطر نص داكن على خلفية داكنة |
| `AppColors.border` / `AppColors.surface` | 209 / 97 | حدود/أسطح فاتحة ثابتة (يوجد `borderDark/surfaceDark` لكن لا يُختار تلقائياً) |
| `Theme.of(context).colorScheme` | 102 فقط | الاستعمال الصحيح أقل بكثير من الثابت |
| `isDark`/`brightness` فروع يدوية | ~121 | ترقيع شاشة-بشاشة |
| `BorderRadius.circular` | 2155 (8:685، 12:396، 10:227، 6:185، 4:137، 16:83، 11:83، 14:82، 9:68، 13:24) | 12+ قيمة؛ الثيم يحدد `_radiusCard=14`, `_radiusControl=10` |
| ارتفاعات `height: 3x–5x` (أزرار/حقول مرشّحة) | 30:32، 32:69، 34:35، 36:48، 38:25، 40:64، 42:13، 44:28، 46:4، 48:21، 50:8، 56:11 | 12 ارتفاعاً مختلفاً للتحكمات |
| عرض `PicPosDialog(width:)` | 420,460,520,560,620,640,660,680,700,720,760(افتراضي),820,880,900,980,1480 | 16 عرضاً بلا سلّم |

**توزيع أحجام الخط** (الأكثر): 12→1049، 11→660، 13→467، 10→281، 14→185، 16→170، 18→130، 10.5→100، 12.5→137، 11.5→139.
المربك: وجود **أنصاف** (8.5/9.5/10.5/11.5/12.5/13.5/14.5 ≈ 465 موضعاً) ومقاسات ≤10 (≈ 400 موضع، منها `9`→61، `9.5`→36، `8`→12) وهي أصغر من حدّ القراءة على شاشة كاشير. سلّم الثيم الرسمي (`app_theme.dart:459`): 10/11/12/12/14/14/16/18/20/24 — فالمقاسات 10.5/11.5/12.5/13.5 كلها خارج السلّم.

**ملاحظة بنيوية مهمة:** `PicPosTheme` (`lib/core/theme/picpos_theme.dart`) يجعل المتن `w600` والعناوين `w700` (اختبار `picpos_theme_bold_text_test` ينجح)، لكن ثيم الملف نفسه يعترف (سطر 45–47) أن كثيراً من الجداول تضبط `fontWeight`/`fontSize` موضعياً فتتجاهله — هذا ما تؤكده الأرقام أعلاه.

### أ.2 جدول المواضع (ملف:سطر) — مرتّبة بالخطورة

الخطورة: **عالية** = نص/أيقونة قد تختفي أو تقلّ قراءتها في الوضع الداكن/الفاتح؛ **متوسطة** = اتساق أو قراءة؛ **منخفضة** = تجميلي/مقصود.

| # | الموضع | المشكلة | الخطورة | الإصلاح المقترح |
|---|---|---|---|---|
| 1 | `lib/presentation/widgets/common_widgets.dart:180` | `color: Colors.black54` | عالية (مرشّحة) | `colorScheme.onSurfaceVariant` |
| 2 | `lib/presentation/widgets/help_panel_overlay.dart:82` (+سطران آخران بالملف) | `Colors.black54` فوق طبقة | عالية (مرشّحة) | `onSurface.withValues(alpha:…)` / `scrim` |
| 3 | `lib/presentation/screens/settings/widgets/security_alerts_panel.dart:115` | `TextStyle(color: Colors.black54, fontSize:12)` ضمن شاشة إعدادات | **عالية** (نص غامق على بطاقة داكنة) | `Theme.of(context).textTheme.bodySmall` |
| 4 | `lib/presentation/screens/purchase_returns/return_details_panel.dart:237` ، `lib/presentation/screens/sales_returns/return_details_panel.dart:487` | `Colors.black87` ثابت | **عالية** | `colorScheme.onSurface` |
| 5 | `lib/presentation/screens/invoice_designer/invoice_designer_ui.dart:362` | `Colors.black87, w600` في واجهة المصمم | عالية | `onSurface` (مع إبقاء «ورقة المعاينة» بيضاء عمداً) |
| 6 | `lib/presentation/widgets/touch_keyboard.dart:336` | `foregroundColor: Colors.black87` | عالية (إن كانت خلفية الزر تتبع الثيم) | `onSurface` أو زوج `…Container/on…Container` |
| 7 | `lib/presentation/pos/screens/…` و`lib/presentation/screens/dashboard_screen.dart:470,790` | `AppColors.textPrimary` صلب (داكن) | عالية | `colorScheme.onSurface` |
| 8 | `lib/presentation/pos/widgets/cart_widgets.dart:30`, `lib/presentation/pos/widgets/product_pricing_inquiry.dart:279` | `AppColors.textSecondary/textPrimary` على سطح POS | عالية | نفس ما سبق |
| 9 | `lib/presentation/purchase_returns_picpos/screens/purchase_returns_picpos_screen.dart:346,385` | `TextStyle(fontSize:13, color: AppColors.textPrimary)` | عالية | `textTheme.bodyMedium` |
| 10 | `lib/presentation/settings_picpos/screens/cfd_settings_card_picpos.dart:123,885` ، `…/payment_methods_settings_picpos.dart:139` | `AppColors.textSecondary` (`#374151`) في **شاشات الإعدادات** | **عالية** — رمادي داكن على بطاقة `#121C2E` تقريباً غير مقروء | `colorScheme.onSurfaceVariant` |
| 11 | `lib/presentation/settings_picpos/screens/network_mode_settings_picpos.dart:258-261,406` | `AppColors.surface` / `AppColors.border` فاتحان ثابتان كخلفية وحدّ لبطاقة حالة الخادم | عالية (بطاقة فاتحة ناصعة داخل داكن، أو العكس) | `picposField/picposHairline` (ملحقات الثيم) أو `colorScheme.surfaceContainer` |
| 12 | `lib/presentation/settings_picpos/widgets/web_access_settings_panel.dart:70` | `Border.all(color: AppColors.border)` | متوسطة | `Theme.of(context).dividerColor` (الثيم يضبطه `_hairline`) |
| 13 | `lib/presentation/settings_picpos/widgets/quick_sale_cashier_preview.dart:22-27` | لوحة معاينة داكنة ثابتة (`_canvas 0B1220`…) داخل شاشة فاتحة؛ ثم إيصال أبيض بنص `Colors.black` (368-390) بخط **9–10** | منخفضة (مقصودة: محاكاة) لكنها **غير متّسقة** مع الوضع | تثبيتها كـ«PreviewPalette» موثّقة، ورفع الخط الأدنى إلى 10–11 |
| 14 | `lib/presentation/settings_picpos/screens/quick_sale_policy_screen_picpos.dart:35-63` | 29 لوناً صلباً لأيقونات السياسات (`0xFF0250D3`, `0xFF4A80E8`…) بدل `AppColors.primary/info` | متوسطة | حصر في `Map<String, ColorRole>` تُحلّ من `ColorScheme`/`AppColors` |
| 15 | `lib/presentation/settings_picpos/widgets/permissions_matrix_picpos.dart:937-945,1021-1057` | ~20 لوناً صلباً للأدوار/الأقسام، و`width: 1480` (347) | متوسطة | توليد ألوان من palette واحدة (`ColorScheme.fromSeed` لكل دور) + `LayoutBuilder` بدل 1480 ثابت |
| 16 | `lib/presentation/settings_picpos/screens/cfd_settings_card_picpos.dart:267,295,443,513,649,733,742,978` | `fontSize` ≤ 10 | متوسطة | `labelSmall` (10) كحدّ أدنى؛ يفضَّل 11 |
| 17 | `…/network_mode_settings_picpos.dart:183,482` ، `…/quick_sale_policy_screen_picpos.dart:196,323,331,342,458` ، `…/settings_picpos_about.dart:130` ، `…/permissions_matrix_picpos.dart:527` ، `…/quick_sale_cashier_preview.dart:123,193-260` | خط 8–10 | متوسطة | نفسه |
| 18 | `lib/presentation/settings_picpos/screens/settings_picpos_tiles.dart:298-300` | `showDialog` بـ`Dialog` خام + `maxWidth:720` + padding 16 — بينما بقية الإعدادات `PicPosDialog` | متوسطة (اتساق) | `PicPosDialog(width:…)` |
| 19 | `lib/presentation/settings_picpos/widgets/database_encryption_dialogs.dart:83-100` | `Dialog` خام، `radius 16`، padding 20، عنوان `titleLarge w800` | متوسطة (اتساق: رأس مختلف عن بقية الحوارات + وزن w800 خارج عقد الوزنين) | `PicPosDialog` |
| 20 | عروض حوارات الإعدادات: `settings_picpos_screen.dart:254,312,357`, `settings_picpos_support.dart:309`, `admin_home_settings_picpos.dart:37`, `field_expense_categories_screen.dart:77` = 460؛ `cfd_settings_card_picpos.dart:835`, `linked_devices_section.dart:576`, `server_security_block.dart:242`, `database_encryption_dialogs.dart:337` = 520؛ `general_settings_widgets_picpos.dart:505/513` = 560/500؛ `cheques_picpos_*_dialog.dart` = 860/880/880؛ `warehouse_devices_body.dart:156` = 420 | 7 عروض مختلفة بلا سلّم؛ 500 و560 داخل ملف واحد | متوسطة | ثلاثة أحجام (S=460, M=560, L=880) كـ`enum PicPosDialogSize` |
| 21 | `lib/presentation/settings_picpos/screens/settings_picpos_about.dart:21,101,119` | ظل `Colors.black.withValues(0.1)` وألوان علامات (فيسبوك/واتساب) | منخفضة (مقصودة) | تبقى؛ ظل → `colorScheme.shadow` |
| 22 | `lib/presentation/categories_picpos/screens/categories_picpos_screen.dart:810` ، `lib/presentation/screens/categories_screen.dart:787` | حدّ `Colors.black` لتحديد عنصر | متوسطة | `colorScheme.onSurface` (أسود غير مرئي على الداكن) |
| 23 | ملفات ذات كثافة عالية من الألوان الصلبة: `screens/hr/widgets/hr_dashboard_tab.dart` (31)، `screens/dashboard_screen.dart` (12)، `widgets/settings/permissions_management_widget.dart` (16)، `screens/tables/widgets/table_order_panel.dart` (13) | ألوان صلبة | متوسطة | مرور مركزي بعد تحديد tokens |
| 24 | `Colors.white` كخلفية: `screens/login_screen.dart` (31)، `pos_picpos/widgets/picpos_top_bar.dart` (17)، `screens/journal_entries_screen.dart` (15)، `shell/app_shell.dart` (14)، `widgets/settings/branch_scope_admin_dialog.dart` (13)، `screens/chart_of_accounts_screen.dart` (12)، `pos/screens/table_pos_dialogs.dart` (12) | بطاقة بيضاء ثابتة ⇒ توهّج/عدم تناسق داكن | عالية في `app_shell` و`branch_scope_admin_dialog` (حوار إعدادات) | `colorScheme.surface` / `surfaceContainerLow` |
| 25 | `lib/core/theme/app_theme.dart` (نسخة UralCash): الثيم الداكن (سطر 280–430) يعرّف `elevatedButtonTheme` فقط؛ **لا `outlinedButtonTheme` ولا `textButtonTheme`** كما في الفاتح (89/107)؛ ونص الجداول `Colors.white70` ثابت (384) | تباين الأزرار الثانوية في الداكن يعتمد على الافتراضي | متوسطة | مساواة الثيمين (أو اشتقاق الداكن من نفس دالة البناء) |
| 26 | `lib/core/theme/app_theme.dart:56` و`:84,:102` | AppBar 16، أزرار 13، حقول 12 مقابل PicPos 13–15 (مختلف عمداً حسب تعليقات الملف) | منخفضة | لا إصلاح؛ فقط عدم خلط التوكنز بين الثيمين |

> الأسطر 1–9 و22–24 عيّنات من أكبر القوائم (73 `Colors.black`، 153 استعمال `AppColors.text*` ثابت). القائمة الكاملة تُستخرج بنفس الـ grep المذكور في أ.4.

### أ.3 أنماط عامة تُصلح مركزياً (بدل ترقيع كل شاشة)

1. **ThemeExtension دلالي واحد** (`AppSemanticColors`/`PicPosTokens`) في `lib/core/theme/` يوفّر: `textStrong/textMuted`, `surfaceCard/surfaceField`, `hairline`, `success/warning/danger(+onX)`, `chartPalette`. يُسجَّل في `lightTheme/darkTheme` معاً. ثم يُستبدل `AppColors.textPrimary/textSecondary/surface/border/card` (≈ 460 موضعاً) بـ`context.tokens.…` عبر codemod. الثيم يكشف الآن `lightHairline/lightFieldFill` فقط؛ نظائرها الداكنة خاصة (`_hairlineDark`, `_fieldFillDark`) فتُكشف.
2. **سلّم خطوط مغلق:** إنشاء `PicPosText`-style ثابتات (`caption=11, body=13, bodyStrong=13/w700, title=15, headline=18, display=24`) وإلغاء الأنصاف و≤10. قاعدة lint مخصّصة (أو اختبار هيكلي مثل `test/structural/dark_tokens_match_picpos_theme_test.dart`) تفشل عند ظهور `fontSize:` حرفي جديد خارج `lib/core/theme`.
3. **ارتفاعات التحكمات في الثيم:** `FilledButton/ElevatedButton/OutlinedButton minimumSize`, `InputDecorationTheme.constraints`, `VisualDensity` و`materialTapTargetSize` ثابتة (مثلاً 40 للفئة الافتراضية، 32 للمدمجة)، بدل `SizedBox(height: 3x–5x)` اليدوي (12 قيمة حالياً).
4. **أنصاف الأقطار:** ثلاثة رموز (`radiusControl=10`, `radiusCard=14`, `radiusPill`) تُقرأ من الثيم/الامتداد؛ ما عداها (3,4,6,8,9,11,13…) يُحوَّل.
5. **ثيم الحوارات:** `DialogThemeData` + `PicPosDialog` بأحجام معيارية `S/M/L`، وحظر `Dialog(`/`AlertDialog(` الخام في `settings_picpos` (68 `Dialog(` مقابل 76 `PicPosDialog`).
6. **حراسة اختبارية للوضع الداكن:** اختبار هيكلي (على نمط الموجود) يفحص بـ regex أن `Colors.black*` و`AppColors.text(Primary|Secondary)` لا تظهر في `color:` داخل `lib/presentation` إلا في قائمة استثناءات مسمّاة (معاينات الورق/الطباعة).
7. **معاينات ثابتة اللون** (`quick_sale_*_preview`, `invoice_designer_*`): تُعزل في ملف palette واحد مُسمّى «ورق/محاكاة» ليبقى الاستثناء مقصوداً ومعلناً.

### أ.4 أوامر إعادة الإنتاج
`Select-String 'Colors\.black(87|54)?\b'`, `'color: *AppColors\.text(Primary|Secondary)'`, `'fontSize:\s*(8|9|10)(\.5)?\b'`, `'width: *\d{3,4}'` داخل `lib/presentation/settings_picpos`.

---

## (ب) تقرير الصحة والاستقرار

### ب.1 ما شُغِّل
| الفحص | النتيجة |
|---|---|
| `flutter analyze --no-pub` (كامل المشروع، 411 ثانية) | **21 info، 0 error، 0 warning.** `avoid_print` في `build/tmp_reach.dart` و`scripts/*.dart`، `use_build_context_synchronously` في `purchase_returns_picpos_logic.dart:48` و`sales_returns_picpos_logic.dart:84`، `unintended_html_in_doc_comment` في `tool/ci/apk_scan.dart:271`. |
| `test/unit/pg_compat_sql_test.dart` + `pg_compat_test.dart` + `picpos_theme_bold_text_test.dart` | نجحت (55 اختباراً مع المجموعة الأولى) |
| `test/unit/deployment/provisioning_applier_test.dart` + `test/structural/dark_tokens_match_picpos_theme_test.dart` | نجحت (14) |
| **لم يُشغَّل:** باقي مجموعة الاختبارات، واختبارات PostgreSQL الحقيقية (`scripts/run_pg_tests.dart`)؛ لا يوجد PG هنا ولا سجلات المستخدم (لم أجد `server_errors.log` في `~/Documents`). | — |

> **فجوة تغطية مهمة:** كل الاختبارات الناجحة تعمل على SQLite/ذاكرة؛ الأخطاء (1) و(2) أدناه **لا يمكن أن تظهر** فيها. نجاح `provisioning_applier_test` لا يعني سلامة المسار على PostgreSQL.

### ب.2 الخطأ (1): `type 'String' is not a subtype of type 'num?'` — `party_profile_dao.dart:262`
- **السبب (مؤكَّد من الكود):** `customSelect` سطر 212-216 يحسب `COALESCE(AVG(gap_days), 0) AS avg_days`؛ في PostgreSQL `AVG()` على عمود صحيح ترجع **`numeric`**، وسائق `postgres` يسلّمها في `row.data` كـ`String`، بينما سطر 262 يفعل `(settle.data['avg_days'] as num?)?.toDouble()`. SQLite يُرجع `num` فلا يظهر الخطأ.
- **الإصلاح الفوري:** في SQL: `CAST(COALESCE(AVG(gap_days),0) AS DOUBLE PRECISION) AS avg_days` (يعمل على SQLite أيضاً: `REAL`/`DOUBLE PRECISION` مقبول)، أو في Dart: دالة `asDouble(Object? v)` (`v is num ? v.toDouble() : double.tryParse('$v') ?? 0`). الأفضل **الاثنان** مع الدالة مشتركة.
- **نطاق المشكلة (خطر أوسع):** يوجد ~**411** `data['x'] as num` و~**230** `as int` في طبقة قاعدة البيانات، وأهم الملفات التي تستعمل `AVG(`/`SUM(`: `accounting_reports_dao.dart` (39)، `sales_analytics_dao.dart` (36)، `party_reconciliation_dao.dart` (14)، `manufacturing_v180_dao.dart` (12)، `treasury_reports_dao.dart` (11). `SUM(bigint)` و`AVG()` و`ROUND(x,2)` كلها `numeric` ⇒ **كل تقرير يُجمّع عبر PG معرَّض للانفجار نفسه** إن لم يكن قد أُحيط بـ`CAST`. لا يوجد مساعد عام (الوحيد: `report_builder_dao.dart:762` محلي).
- **توصية:** مساعد واحد `lib/data/database/sql_value.dart` (`asDouble/asInt/asDecimal`) + اختبار هيكلي يفشل إن ظهر `data['…'] as num` جديد، + رفع `CAST` في SQL الجديدة.

### ب.3 الخطأ (2): `ADOPT-FAIL / RECONCILE-FAIL DB_READ_ERROR 42601 syntax error at or near ","`

**التسلسل الفعلي** (`network_service.dart:323-340`): `reconcileWithDb` تستدعي أولاً `ProvisioningApplier.ensure(db)` (`provisioning_applier.dart:50`) التي تلتقط أي استثناء وتسجّل `ADOPT-FAIL` بـ`$e` فقط (بلا SQL)؛ ثم داخل `try` ضيّق **واحد فقط** هو `db.getSettingValue('network_mode')` (سطر 327) ⇒ إن ظهر `DB_READ_ERROR` فالفاشل هو **قراءة `settings` نفسها** (أو جلسة PG تالفة) لا سطر آخر. أي أن نفس الخطأ تكرّر في خطوتين متتاليتين.

الاستعلامات المتورطة (كلها عبر `SettingsDao` في `settings_dao.dart:26-69`):
- `getSetting`: `select(settings)..where(key = ?)..limit(1)` (Drift يولّد `SELECT … FROM settings WHERE key = $1 LIMIT 1`).
- `setSetting`: `into(settings).insertOnConflictUpdate(...)` ⇒ `INSERT … ON CONFLICT (key) DO UPDATE SET key = …, value = …`.
- خطوات الـApplier: `ProvisioningStore.read/write` (`provisioning_record.dart:253-267`، يخزن JSON في `settings`)، `db.setSetting` للمفاتيح المشتقة (سطر 98)، `_repairCache` (لا SQL إلا عبر `saveSettings` للـNetworkService)، و`repairDuplicateAdmins` (`admin_duplicate_repair.dart:55-104`: `select users` + `UPDATE users SET username=?, is_active=?, global_id=?` داخل `transaction`؛ استثناؤه مبتلع ويسجَّل `ADMIN-DEDUP` لا `ADOPT-FAIL`، فهو **غير** السبب المباشر).

**الاحتمالات مرتّبةً بالأرجحية:**
1. **(الأرجح ~40%) إعادة كتابة `PgCompatSql.fixSql` مرتين تُفسد جملة/قيمة** — تُطبَّق في `database.dart:622/636` (`customStatement/customSelect`) **ثم** مرة أخرى في `_PgCompatInterceptor` (`connection_io.dart:166`). الدالة مصمَّمة idempotent لكن regexes الـ`GROUP_CONCAT`/`julianday`/`strftime` (`[^)]+`، `[^,()]+?`) قد تلتهم فواصل `,` في عبارات متداخلة، فينتج ‏`syntax error at or near ","`. الفاصلة هي بالضبط ما تمسّه هذه الـregexes (فواصل وسائط `strftime(...)`, `julianday(a, 'unixepoch')`, `GROUP_CONCAT(x, ',')`). لكن جملة `settings` البسيطة لا تحتوي أيّاً منها، ⇒ هذا الاحتمال يتحقق فقط إن كانت **جملة أخرى** هي التي فشلت وأُسندت للقراءة (انظر 2).
2. **(~25%) جلسة/اتصال PG مشترك يعيد خطأ جملة سابقة غير مُنتظَرة** (تقاطع pipelining): جملة DDL/seed تُطلَق بـ`unawaited` أو ضمن مسار الإقلاع المتوازي (`database_startup.dart` مرحلة مؤجَّلة) فيصل خطؤها لأقرب منتظر. الدليل غير المباشر: نفس الخطأ ظهر في خطوتين لا يشتركان بأي SQL حرفي.
3. **(~15%) جملة DDL من `PG parity` / `database_pg_create.dart` تحتوي قائمة أعمدة/قيم بفاصلة زائدة** (trailing comma في `CREATE INDEX (a, )` أو `INSERT … VALUES (…,)`)، وتُنفَّذ قبل أو بالتوازي مع `reconcile` (ملف `database_pg_parity.dart` يسجّل `PG-PARITY-*`). مرشّحة لأن ترتيب سجلات المستخدم يجمع `PG-PARITY-EXTRA` مع الإقلاع.
4. **(~10%) `insertOnConflictUpdate` على جدول `settings` في PG:** إن كان جدول `settings` في قاعدة PG أُنشئ قديماً **بلا PK** (التعليق بـ`settings_dao.dart:21-25` يعترف بوجود بيانات قديمة تنتهك PK) فالخطأ الناتج `42P10` وليس `42601`، لذا أقل ترجيحاً، لكنه يُبقي مسار الكتابة هشّاً.
5. **(~10%) محرّف (alias) أو اسم عمود محجوز:** `key`/`value` محجوزتان نسبياً في PG؛ لو ولّد مولّد SQL مخصّص (`customSelect` يدوي) `SELECT key, value FROM settings` بلا اقتباس أو بقائمة غير صحيحة. الأقل احتمالاً لأن Drift يقتبس.

> **صراحةً:** لم أستطع تعيين الجملة من الكود وحده؛ الترتيب أعلاه استدلالي.

**كيف نكشف الجملة (أقل تغيير):**
- **هذا موجود أصلاً:** `_PgCompatInterceptor._logFailed` (`connection_io.dart:174`) يكتب `sql: …` و`args: …` إلى `Documents/server_errors.log` (يكتب `PG FAIL` + نوع العملية). **أول خطوة: اطلب من المستخدم ملف `server_errors.log` حول وقت الإقلاع** — فيه الجملة بالنص الكامل.
- ثغرات التسجيل الحالية (تُصلح): (أ) `ADOPT-FAIL` و`RECONCILE-FAIL` يسجّلان `$e` بلا `StackTrace` ولا اسم المفتاح؛ مرّر `catch (e, st)` وسجّل `key=network_mode`. (ب) `runBatched` يلصق الجمل بـ`' ; '` فيضيع أي فاصل؛ (ج) `_logFailed` يتجاهل أخطاء `transaction begin/commit` ومسار `customStatement` المباشر؛ (د) لا تسجيل للجملة **قبل** `fixSql` فلا يمكن مقارنة الأصل بالمحوَّل ⇒ أضف `original:` إلى السجل.
- فحص مؤقت للتشخيص: في `PgCompatSql.fixSql` أضف (تحت متغير بيئة `PICPOS_SQL_TRACE`) قيد `assert`/تسجيل عندما `fixSql(fixSql(s)) != fixSql(s)` (اختبار idempotency حي)، واكتب `s` الأصلية.
- اختبار وحدة جديد: لكل `customSelect/customStatement` نصي في `lib/` (حوالي مئات) يشغَّل `fixSql` ثم يتأكد من توازن الأقواس وعدم وجود `,)` و`(,` و`,,` (يلتقط الفواصل الزائدة آلياً).

### ب.4 التحذيرات (3): `PG-PARITY-EXTRA`
- المصدر: `database_pg_parity.dart:387-425`. تُسجَّل لكل جدول موجود في PG **وغير** موجود في مخطط Drift ولا في القائمة البيضاء `rawSqlManagedTables` (سطر 390). السلوك `action=preserved`: **غير ضارّ** (لا حذف)، لكنه ضجيج يخفي إشارات حقيقية.
- **مرشّحة للإضافة للقائمة** (جداول تُنشأ بـ`CREATE TABLE IF NOT EXISTS` خام ولا تظهر في القائمة؛ تحقّق بمقارنة سجلك الفعلي لأن بعضها قد يكون جدول Drift أيضاً):
  `cloud_sync_documents` (`cloud_sync_schema.dart:21`)، `remote_id_mappings` و`e_invoice_status_log` (`database_pg_sync_infra.dart:42,207`)، `field_expense_categories` (`field_expense_schema.dart:228`)، `lan_paired_devices` و`lan_branch_terminal_codes` (`lan_pairing_schema.dart:8,29`)، `party_dedup_suspects` (`reservation_parties_schema.dart:103`)، `wh_mobile_docs`/`wh_mobile_doc_lines`/`wh_mobile_doc_events` (`wh_mobile_docs_schema.dart:39-56`)، وجداول حقب الهجرة (`sync_logs`, `warehouse_transfers`, `pricing_rules`, `budgets`, `approval_*`, `sod_*`, `entities`, `restatements`, `regions`, `party_groups`, `failed_autoposts` … في `migrations/epoch_2.dart`, `epoch_3_*.dart`) — الأخيرة غالباً مطابقة لجداول Drift فلا تُحسب إضافية؛ تحقّق منها.
- **الحل المستدام:** بدل القائمة اليدوية، اجمع أسماء الجداول من منطق إنشاء الجداول الخام تلقائياً (سجل `registerRawTable(name)` يُستدعى حيث `CREATE TABLE`)، ورقّ السجل من `PG-PARITY-EXTRA` إلى سطر ملخّص واحد `count=N names=[…]`.

### ب.5 مخاطر استقرار/استدامة أخرى (بالخطورة)

| # | الخطورة | الخطر | الدليل | الأثر |
|---|---|---|---|---|
| 1 | **حرجة** | أرقام `numeric` من PG كنصوص ⇒ استثناء `TypeError` في التقارير | ~411 `as num`، (انظر ب.2) | تقارير ولوحات تنهار على PG فقط ولا تكشفها اختبارات SQLite |
| 2 | **حرجة** | جمل SQLite الخاصة في مسار مشترك: `INSERT OR REPLACE` (20 موضعاً — **لا** يترجمه `PgCompatSql`، بل يترجم `OR IGNORE` فقط ⇒ `42601 near "OR"`)، `last_insert_rowid` (2)، `sqlite_master` (10)، `PRAGMA` (73، يجب حراستها بـ`_isPostgres`) ، `substr(` (9، مقبولة في PG كـ`substr` فعلاً) | grep | أخطاء 42601 جديدة عند الإقلاع/التشغيل على PG؛ تشبه نمط الحادث الموثَّق في `pg_compat_sql.dart:98-101` |
| 3 | **عالية** | **ترجمة SQL بـregex** هشّة (`[^)]+`, `[^,()]+?`) وتُطبَّق مرتين (database.dart + interceptor) | `pg_compat_sql.dart:25-90`, `database.dart:622,636` | فاصلة/قوس داخل نص حرفي أو تعبير متداخل ⇒ جملة خاطئة؛ لا يوجد parser |
| 4 | **عالية** | استثناءات مبتلعة: `catch (_) {}` ≈ **225** موضعاً في `lib` (منها ~100 في `lib/services`، مثال: `scale_service_io.dart` ×17، `server_proxy.dart:91,98,114,129`، `login_lockout_store.dart:41`، `license_service.dart:236,246`، `sync_service.dart:698`، `table_checkout_coordinator.dart:147,204`) | grep | فشل صامت لحفظ الرمز/القفل/الترخيص/السداد؛ أسوأها ما كان في `login_lockout_store`, `license_service`, `credential_stamp_store.dart:260` (أمنية) |
| 5 | **عالية** | `unawaited` كثيف (~100 في الخدمات، معظمه `DiagnosticLogger.log` وهو مقبول)، لكن الخطر في غير التسجيل: `unawaited(DeltaPullService.instance.pullAll())` (`cwi_core_support.dart:218`, `offline_sync_worker_drain.dart:475`)، `unawaited(syncNow())` (`cloud_sync_service.dart:315`)، `unawaited(StorageKeyMigration.write/delete)` و`_writeTokenToPrefs` (`server_proxy.dart:64-83,122`)، `unawaited(_db!.storeFkMapping(...))` (`offline_sync_worker_drain.dart:142`) | grep | سباقات: كتابة رمز الجهاز تتأخر عن قراءته (`restoreToken` ثم `apiToken` في Applier)، ضياع `storeFkMapping` عند الإغلاق |
| 6 | **عالية** | **أول إقلاع على PG يعتمد على تسجيل بلا انتظار:** `reconcileWithDb` يستخدم `unawaited(DiagnosticLogger.log(...))` قبل `return`، بينما `ADOPT-FAIL` يُنتظر — ترتيب السجلات في ملف المستخدم قد يُظهر `RECONCILE-FAIL` قبل `ADOPT-FAIL` فيضلل التشخيص | `network_service.dart:330` مقابل `provisioning_applier.dart:56` | تشخيص مضلّل |
| 7 | **متوسطة** | `Timer.periodic` ×23 مقابل `cancel()` ×106 و`.listen(` ×42: يلزم مراجعة أن كل مؤقت/اشتراك يُلغى في `dispose` (خاصةً `mirror_heartbeat_service.dart:50-58`، `network_service.dart:925-928` يُنشئ `worker.runOnce` دورياً بلا ضمان عدم التداخل) | grep | تسريب مؤقتات/تشغيل متداخل للمزامنة |
| 8 | **متوسطة** | `use_build_context_synchronously` ×2 (`purchase_returns_picpos_logic.dart:48`, `sales_returns_picpos_logic.dart:84`) | analyze | استخدام `context` بعد `await` ⇒ استثناء عند إغلاق الشاشة |
| 9 | **متوسطة** | `repairDuplicateAdmins` و`ProvisioningApplier.ensure` يبتلعان كل شيء (`ADOPT-FAIL` ثم إكمال الإقلاع) ثم `reconcile` يحكم على مفاتيح خام قد تكون معطوبة | الملفان | قد يدخل جهاز في وضع خاطئ بصمت؛ يحتاج إظهاراً في `AdoptReport.error` |
| 10 | **متوسطة** | `saveSettings` فيه معاملة (جيد)، لكن `setSetting` المفرد بلا معاملة والكاتبون المتزامنون (Applier + شاشات الإعدادات + مزامنة) بلا قفل | `settings_dao.dart:50-69` | سباق «آخر كاتب يفوز» على مفاتيح النشر |
| 11 | **متوسطة** | `_logFailed` يكتب ملفاً بـ`flush: true` على **كل** فشل ويتجاهل أخطاءه؛ تحت عاصفة أخطاء يصبح عنق زجاجة، ولا تدوير (rotation) للملف | `connection_io.dart:174-202` | تضخم القرص/بطء |
| 12 | **منخفضة** | اختلاط اللهجات والعربية في التعليقات وملف `tool/`/`build/tmp_reach.dart` داخل نتائج `analyze` (`avoid_print`) | analyze | ضجيج؛ استبعد `build/` و`scripts/` في `analysis_options.yaml` |
| 13 | **منخفضة** | زمن `flutter analyze` 411 ثانية | — | يستحق استبعاد المجلدات غير الإنتاجية |

---

## خطة الإصلاح (بالأولوية) — مهام مستقلة لا تتقاطع ملفاتها

> كل مهمة تلمس مجموعة ملفات منفصلة تماماً، فيمكن تنفيذها بالتوازي.

| ترتيب | المهمة | الملفات (حصرياً) | الخطوات | معيار القبول |
|---|---|---|---|---|
| **1** | **تصحيح `avg_days` + مساعد تحويل الأرقام** | `lib/data/database/daos/party_profile_dao.dart`، ملف جديد `lib/data/database/sql_value.dart`، اختبار جديد `test/unit/sql_value_test.dart` | `CAST(... AS DOUBLE PRECISION)` + `asDouble`؛ اختبار يغذّي `'12.5'` و`12` و`null` | كشف عميل/مورد يعمل على PG؛ الاختبار ناجح |
| **2** | **كشف جملة 42601** (تسجيل فقط، لا تغيير سلوك) | `lib/data/database/connection_io.dart`، `lib/services/network_service.dart` (كتلة `reconcileWithDb` فقط)، `lib/services/deployment/provisioning_applier.dart` | `catch (e, st)` + `key`، تسجيل `original` قبل `fixSql`، تغطية `transaction/customStatement`، تدوير `server_errors.log`، فحص idempotency تحت `PICPOS_SQL_TRACE` | عند تكرار الخطأ تظهر الجملة الكاملة في سجل واحد |
| **3** | **تقوية `PgCompatSql`** | `lib/data/database/pg_compat_sql.dart`، `test/unit/pg_compat_sql_test.dart`، ملف جديد `test/unit/pg_sql_lint_test.dart` | إزالة التطبيق المزدوج (احتفظ بالمعترض فقط أو العكس)، دعم `INSERT OR REPLACE` ⇒ `ON CONFLICT … DO UPDATE` أو منع استعماله، لفّ regex بمحلل أقواس، اختبار لينت لكل SQL نصي (فواصل `,)`، `(,`) | الاختبارات الحالية (51) + الجديدة ناجحة |
| **4** | **تقليل ضجيج `PG-PARITY-EXTRA`** | `lib/data/database/database_pg_parity.dart` فقط | إضافة الجداول الخام للقائمة أو تجميعها تلقائياً + سطر ملخّص واحد | سجل إقلاع بلا تحذيرات كاذبة |
| **5** | **مسح `as num` في التقارير الثقيلة** (ملف/ملفات لكل عامل) | (أ) `accounting_reports_dao.dart` (ب) `sales_analytics_dao.dart` (ج) `party_reconciliation_dao.dart` + `treasury_reports_dao.dart` (د) `manufacturing_v180_dao.dart` | استبدال `as num?` بـ`asDouble/asInt` من مهمة 1؛ اختبار هيكلي يمنع `data['…'] as num` جديداً | لا استعمال خام متبقٍ في هذه الملفات |
| **6** | **ابتلاع الاستثناءات الأمنية** | `lib/services/login_lockout_store.dart`, `license_service.dart`, `server_proxy.dart`, `auth/credential_stamp_store.dart` | استبدال `catch (_) {}` بتسجيل `DiagnosticLogger.log` مع سبب؛ انتظار `StorageKeyMigration.write` حيث يُقرأ لاحقاً | لا `catch (_) {}` صامت في هذه الملفات |
| **7** | **مؤقتات وسباقات المزامنة** | `lib/services/mirror_heartbeat_service.dart`, `lib/services/network_service.dart` (كتلة السطر 900-930 فقط، بعد المهمة 2)، `lib/services/cloud_sync/cloud_sync_service.dart` | حارس إعادة دخول (`_running`) + إلغاء في `dispose` | لا تداخل لتشغيلين من `runOnce/syncNow` |
| **8** | **إصلاح `use_build_context_synchronously`** | `purchase_returns_picpos_logic.dart`, `sales_returns_picpos_logic.dart` | `if (!context.mounted) return;` | `flutter analyze` على الملفين نظيف |
| **9** | **ثيم مركزي: tokens + سلّم خطوط** | `lib/core/theme/app_colors.dart`، `picpos_theme.dart`, `picpos_theme_dark.dart`، ملف جديد `lib/core/theme/app_tokens.dart`، اختبار هيكلي جديد | ThemeExtension (أ.3-1)، سلّم الخطوط، توحيد ارتفاعات التحكمات، مساواة الثيم الداكن لـUralCash (`app_theme.dart:280+`) — **ثيم UralCash لا يُغيَّر شكله** إلا بإضافة أزرار ثانوية داكنة | اختبارات الثيم الموجودة + الاختبار الهيكلي |
| **10** | **ترحيل شاشات الإعدادات إلى الـtokens** (بعد 9) | `lib/presentation/settings_picpos/**` فقط | بنود 10–20 من جدول أ.2: إزالة `AppColors.textSecondary/surface/border` الصلبة، `PicPosDialogSize`، تحويل `Dialog` الخام إلى `PicPosDialog` (`settings_picpos_tiles.dart:298`, `database_encryption_dialogs.dart:83`)، رفع الخط ≥ 11 | لقطات الوضعين لشاشات: الشبكة، CFD، طرق الدفع، أمان الخادم |
| **11** | **ترحيل نصوص POS/المرتجعات/المعاونة** (بعد 9) | `lib/presentation/widgets/common_widgets.dart`, `help_panel_overlay.dart`, `touch_keyboard.dart`, `screens/settings/widgets/security_alerts_panel.dart`, `screens/{purchase,sales}_returns/return_details_panel.dart`, `pos/widgets/cart_widgets.dart`, `pos/widgets/product_pricing_inquiry.dart`, `purchase_returns_picpos/**`, `categories_picpos/**`, `screens/categories_screen.dart` | بنود 1–9 و22 من الجدول | مرور بصري داكن/فاتح |
| **12** | **حارس CI للألوان الصلبة** | ملف اختبار هيكلي جديد فقط + قائمة استثناءات | regex للـ`Colors.black*` و`AppColors.text*` | يفشل عند إضافة مخالفة جديدة |
| **13** | **تنظيف التحليل** | `analysis_options.yaml` فقط | استبعاد `build/**`, `scripts/**`, `tool/**` من `avoid_print`/lints؛ إصلاح تعليق `tool/ci/apk_scan.dart:271` | `flutter analyze` أسرع ونظيف |

**ترتيب التنفيذ المقترح:** (1، 2) فوراً ⇒ (3، 4، 5أ-د، 6، 7، 8) بالتوازي ⇒ 9 ثم (10، 11 بالتوازي) ⇒ 12 ⇒ 13.
**تنبيه تقاطع:** المهمتان 2 و7 تمسّان `network_service.dart` (كتلتان منفصلتان: ~323-460 و~900-930)؛ نفِّذهما بالتتابع أو أسندهما لعامل واحد.
