# فرز الاختبارات القديمة الفاشلة — 2026-11-03

## النطاق والنتيجة

- بدأ الفحص والرأس الحالي هو `cb39b85d`، لا commit المرجعي `5d6b3153`؛ لذلك تثبت النتائج أدناه الحالة الحالية فقط، ولا تثبت أن الملفات كانت سليمة عند المرجع.
- لم يتغير أي منطق إنتاجي، أو جدول Drift، أو منطق محاسبي، ولم يُشغّل `build_runner` أو يُرفع سقف `file_size_ratchet_test`.
- اختُبرت الملفات المنفذة منفردةً مع `--concurrency=1 --dart-define=APP_BRAND=picpos`، عدا `brand_isolation_test.dart` الذي جرى تشغيله بلا define كما ينص تعليقه.

## سجل كل بند معروف

| الاختبار | السبب الجذري والتصنيف | ما تغيّر / النتيجة |
|---|---|---|
| `test/unit/brand_isolation_test.dart` (13 المذكورة) | لم يظهر عطل حالي؛ عقده يخص UralCash ويتطلب تشغيله بلا `APP_BRAND`، وقد اجتاز 17 حالة. | لا تغيير. |
| `test/unit/db_connection_strategy_test.dart` | الاختبار قديم: `PostgresConfig.fromJson({})` يستخدم `Brand.pgIdentifier` عمدًا، لا القيمة الثابتة `uralcash` مع PicPos. | أصبح التوقع قائمًا على `Brand.pgIdentifier` مع تعليق؛ الاختبار يمر. |
| `test/unit/picpos_lite_kitchen_policy_test.dart` | الاختبار قديم: فرض أن العلامة ليست PicPos ثم أكد سياسة UralCash، رغم تشغيل التحقق بعلامة PicPos؛ `fromProfile` يختار السياسة حسب العلامة في الكود. | صار تحقق السياسة متوافقًا مع `Brand.isPicPos`؛ الاختبار يمر. |
| `test/unit/sidebar_owner_layout_test.dart` | الاختبار قديم: افترض أن كل تشغيل هو UralCash، بينما فهارس التقاعد خاصة بـPicPos والظهور يتبع العلامة. | صار التأكيد يتبع العلامة المبنية؛ الاختبار يمر. |
| `test/widget/first_run/first_run_standalone_flow_test.dart` | لم يصل الاختبار للتنفيذ: فشل ترجمة إنتاجي في `lib/presentation/print_test_picpos/screens/print_test_picpos_screen.dart:157` بسبب غياب `FilePicker.platform`. هذا الملف ضمن مجال العامل الآخر؛ لا أغيّره. | مؤجل، بلا تعديل. يلزم إصلاح/حسم التعارض في ملف الطباعة ثم إعادة التشغيل. |
| `test/widget/first_run/first_run_currency_test.dart` | السبب نفسه: فشل ترجمة `FilePicker.platform` قبل تحميل الاختبار. | مؤجل، بلا تعديل. |
| `test/widget/first_run/first_run_company_name_roundtrip_test.dart` | السبب نفسه: فشل ترجمة `FilePicker.platform` قبل تحميل الاختبار. | مؤجل، بلا تعديل. |
| `test/widget/first_run/first_run_stepper_resume_test.dart` | السبب نفسه: فشل ترجمة `FilePicker.platform` قبل تحميل الاختبار. | مؤجل، بلا تعديل. |
| `test/widget/picpos_scale_plu_test.dart` | الاختبار قديم: توقع مساواة ناتج `forProfile` بالقائمة الأساسية كاملةً؛ الإنتاج يضيف عناصر ميزات (مثل الاقتباسات) بعد اختيار نطاق العلامة. العقد المقصود هو وجود `scalePlu` حسب العلامة. | بقي تأكيد النطاقين الأساسيين، وقيس invariant الخاص بـ`scalePlu` على الناتج المحسوب مع تعليق؛ الاختبار يمر. |
| `test/widget/report_filter_bar_test.dart` | الاختبار قديم بالنسبة لفرع PicPos: `ReportFilterBar` يسلّم إلى `PicPosReportFilterBar`، الذي يعرض الفترات عبر `InkWell` وتنسيق مخصص لا `ChoiceChip`. النص «اليوم» والنقر واستدعاء callback هو عقد المستخدم. | غُيّر البحث من نوع `ChoiceChip` إلى النص الظاهر ثم النقر؛ جميع حالات الاختبار الأربع تمر. |
| `test/widget/sales_by_classification_report_test.dart` | كان الـfinder قديمًا: فرع PicPos يرسم التبويبات كـ`InkWell` بعناوين داخل `PicPosReportTabs`، وليس عناصر `Tab` المرئية. تحديث الـfinder إلى النص المرسوم سمح بتشغيل التحققين الفعليين؛ شاشة التقرير تحتوي بالفعل حارس generation لكلتا الاستجابتين. | استُبدل finder `Tab` بfinder النص مع تعليق توضيحي. الحالتان اجتازتا، بما فيهما `late older filter responses cannot replace the latest report`؛ لا عيب سباق ظاهر ولا تعديل `lib/`. |
| `test/integration/sales_by_classification_scale_test.dart` | تجميع 2,048 فاتورة ونطاقات الفروع/المستودعات اجتاز. رسائل logging و`Binding has not yet been initialized` من startup لم تفشل الاختبار. | لا تغيير؛ `All tests passed!`. |

## التحقق

- مرّت الملفات المعدّلة: `db_connection_strategy_test.dart` و`picpos_lite_kitchen_policy_test.dart` و`sidebar_owner_layout_test.dart` و`picpos_scale_plu_test.dart` و`report_filter_bar_test.dart`، كلٌ على حدة بالأمر المطلوب.
- مرّ `i18n_runtime_safety_test.dart` و`dark_mode_guard_test.dart` و`analytics_parity_test.dart` و`presentation_db_import_guard_test.dart`، وكذلك الحراس البنيوية للعلامة: `pg_application_name_is_branded_test.dart` و`brand_artifact_guard_test.dart` و`brand_picpos_test.dart` و`scale_brand_connection_test.dart` و`searchable_dropdown_brand_theme_test.dart` (الأخير أظهر اختبارًا متخطّى بالفعل).
- في التشغيل السابق ظهر فشل `file_size_ratchet_test` بسبب `printers_screen.dart` ومفتاح `حفظ PDF` المفقود؛ أُعيد تشغيل الحارسين الآن على الحالة الحالية واجتازا، دون رفع أي سقف حجمي أو تعديل `lib/`/الترجمة.
- `flutter analyze lib` أُعيد: لا أخطاء، فقط المعلومتان المعروفتان `use_build_context_synchronously` في `purchase_returns_picpos_logic.dart:48` و`sales_returns_picpos_logic.dart:84` (رمز خروج 1 بسبب info).
- نتائج التشغيل النهائية على `c0e6cf92`:
  - `test/widget/sales_by_classification_report_test.dart`: 2/2 اجتازت. البحث عن `Tab` كان قديمًا؛ التبويب الحالي `InkWell` داخل `PicPosReportTabs`. الـfinder النصي الجديد يختبر فشل الاستعلام الثانوي وكذلك سباق الاستجابات المتأخرة، وقد ثبت أن الاستجابة الأقدم لا تستبدل الأحدث. لم يلزم تعديل إنتاج.
  - `test/integration/sales_by_classification_scale_test.dart`: 1/1 اجتاز؛ إجماليات 2,048 فاتورة ونطاقات الفرع/المستودع صحيحة. رسائل startup المتعلقة بـ`Binding has not yet been initialized` تشخيصية ولم تفشل الاختبار.
  - `test/widget/first_run/first_run_acceptance_hq_full_test.dart`: 5/5 اجتازت، وتشمل اختبار هندسة جديدًا على 1280×720 يقيس زر الإضافة بالنسبة إلى viewport بعد السحب وبعد `ensureVisible`، ثم ينقره ويتحقق من إضافة حقل المستخدم.
  - `test/widget/first_run/first_run_server_render_sweep_test.dart`: 71/71 اجتازت، بما فيها رحلتا المقر والفرع.
- السبب في first_run كان helper الاختبار: `ensureVisible` وحده قد يترك مركز الزر عند حافة القص؛ helper صار يمرّر فعليًا على `SingleChildScrollView`، ويجري سحبًا إضافيًا للزر قبل النقر عند تلك الحافة. اختبار الهندسة أثبت إمكانية إظهار الزر ونقره بعد التمرير؛ لم يتغير `lib/` ولا حُذف/تُخطّي أي تأكيد.
- الحراس الستة على الحالة الحالية اجتازت: `file_size_ratchet_test` و`i18n_coverage_test` و`i18n_runtime_safety_test` و`dark_mode_guard_test` و`analytics_parity_test` و`test/unit/presentation_db_import_guard_test.dart`. ظهرت رسائل startup غير مانعة عن `Binding has not yet been initialized` وDB deferred work في `analytics_parity_test`، لكن نتيجة الاختبار `All tests passed!`. `flutter analyze lib` لم يجد إلا المعلومتين أعلاه. لا build_runner، لا تغيير schema، لا commit/push.

## التغييرات المتوازية المحفوظة

حُفظت دون تعديل تغييرات الشجرة التي لم أنشئها، بما فيها `lib/presentation/print_test_picpos/screens/print_test_picpos_screen.dart` و`lib/services/printing/report_pdf_generator.dart` و`lib/presentation/screens/printers_screen.dart` و`assets/i18n/en.json`، وملفات DAO/التقارير `lib/data/database/daos/sales_dao.dart` و`lib/data/database/daos/sales_returns_ledger_dao.dart` و`lib/data/providers/print_test_providers.dart` و`lib/data/repositories/reporting_repository_impl.dart` و`lib/domain/models/sales_returns_netting.dart` و`lib/domain/repositories/sales_reporting_repository.dart` و`lib/presentation/screens/reports/sales_report_screen.dart`، إضافة إلى الملفات غير المتعقبة والمجلدات الموجودة مسبقًا. لم أستعد أو أستبدل أي ملف منها.
