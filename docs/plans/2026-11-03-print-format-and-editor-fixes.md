# إصلاح مقاس الطباعة ومحرّر الملصقات وفئات المرتجعات — 2026-11-03

## النتيجة

اكتملت الإصلاحات الأربعة المطلوبة. مسارات الطباعة الحرارية المباشرة والحوارية تمرّر الآن مقاس صفحة الـPDF النهائي، لا مقاساً ابتدائياً بارتفاع لا نهائي؛ إضافة عناصر الملصق تبحث عن موضع خالٍ داخل الحدود؛ وحُدّثت فئتا قالبَي مرتجع المبيعات. بقيت حدود حجم الملفات كما هي، ولم يتغير schema أو ملف نشر القوالب الجاهزة.

## الإصلاحات

1. **مقاس الطباعة النهائي:** بعد حفظ المستند، تستخرج [pdf_compute_helper.dart](../../lib/services/printing/pdf_compute_helper.dart) `PdfPageFormat` من صفحة PDF الناتجة. هذا مهم لأن مكتبة `pdf` تحسم الارتفاع (وأحياناً العرض) من `double.infinity` أثناء التخطيط؛ لذلك لا يطابق المقاس الابتدائي MediaBox النهائي. تستخدمه مولدات الإيصالات والسندات ومسارات المطبخ والوردية، وكذلك المسار المبني على القالب في [template_pdf_renderer.dart](../../lib/services/printing/template_pdf_renderer.dart)، في الإرسال المباشر وحوار الطباعة. بقيت واجهة `TemplatePdfRenderer.generatePdf` التي تعيد البايتات كما هي. [printing_service.dart](../../lib/services/printing_service.dart) يختار مسار القالب أو المولّد الاحتياطي ولا يبني الصفحة بنفسه؛ لذلك عولج تمرير المقاس في المولّدات التي تملك الـPDF.

2. **حارس قنوات الوردية:** بعد refactor `e505b10c` أصبح محلّل القيم في [print_values.dart](../../lib/domain/printing/print_values.dart)، لا [templated_invoice_service.dart](../../lib/services/templated_invoice_service.dart). عُدّل [shift_template_wired_test.dart](../../test/structural/shift_template_wired_test.dart) ليفحص القنوات الست في طبقة القيم مع إبقاء فحص الطبقات الأربع: القيم، ولوحة المصمم، ومحرر الأقسام، والبذرة.

3. **موضع عنصر الملصق:** `addLabelElement` في [label_design.dart](../../lib/domain/printing/label_design.dart) يجرب إحداثيات حواف العناصر الموجودة بترتيب تصاعدي، ويرفض المستطيلات المتداخلة، ثم يستخدم موضعاً احتياطياً محصوراً إذا امتلأت الصفحة. يثبت الاختبار في [label_design_store_test.dart](../../test/unit/label_design_store_test.dart) عدم التداخل واحترام الحدود عند إضافة عنصر سعر بجوار اسم الصنف.

4. **فئة مرتجع المبيعات:** عُدّلت `templateCategory` إلى `sales_return` في [a4_sales_return.json](../../assets/invoice_templates/a4_sales_return.json) و[thermal80_sales_return.json](../../assets/invoice_templates/thermal80_sales_return.json). تأكدت من أن `importTemplateFromJson` في [invoice_template_dao.dart](../../lib/data/database/daos/invoice_template_dao.dart) يحفظ الفئة المصرّح بها في JSON، ثم أضيف [return_template_categories_test.dart](../../test/unit/return_template_categories_test.dart) للتأكد من الفئة والنوع بعد الاستيراد. اتُّبعت الفئة في حالة A4 باختبار الضريبة. تغيّرت بيانات الفئة فقط في بصمتَي [asset_a4_sales_return.txt](../../test/goldens/printing/asset_a4_sales_return.txt) و[asset_thermal80_sales_return.txt](../../test/goldens/printing/asset_thermal80_sales_return.txt)؛ لم يتغير الرسم أو MediaBox.

## التحقق

اجتازت مجموعة الانحدار المحددة `267` اختباراً مع تخطي اختبارين، بخروج `0`. شملت حارس MediaBox المحقون، حارس الطبقات الأربع، حارس حجم الملفات، اكتمال القوالب، فئات المرتجعات، محرّرات الملصقات والقوالب، بصمات الطباعة، القوالب المبذورة، وحزمة [test/print_audit](../../test/print_audit).

```powershell
. D:\qa\luna_tools.ps1; flutter test --concurrency=1 --dart-define=APP_BRAND=picpos test/unit/pdf_compute_helper_media_box_test.dart test/structural/thermal_direct_print_formats_test.dart test/structural/shift_template_wired_test.dart test/structural/template_files_are_complete_test.dart test/structural/file_size_ratchet_test.dart test/structural/i18n_coverage_test.dart test/structural/i18n_runtime_safety_test.dart test/structural/dark_mode_guard_test.dart test/structural/analytics_parity_test.dart test/unit/presentation_db_import_guard_test.dart test/unit/return_template_categories_test.dart test/unit/label_design_store_test.dart test/unit/label_template_page_and_preview_test.dart test/unit/ready_template_deployment_test.dart test/unit/printing_characterization_test.dart test/unit/seeded_templates_map_to_bands_test.dart test/widget/label_editor_screen_test.dart test/widget/template_editor_screen_test.dart test/print_audit
```

واجتاز أيضاً الاختبار المحدد لحالة A4 في [go_blockers_template_tax_rate_not_hardcoded_test.dart](../../test/unit/go_blockers_template_tax_rate_not_hardcoded_test.dart). يثبت [pdf_compute_helper_media_box_test.dart](../../test/unit/pdf_compute_helper_media_box_test.dart) أن العرض والارتفاع اللذين يصلان إلى محوّل الطباعة/الحوار يطابقان MediaBox المقروء من البايتات المحفوظة؛ والحارس البنيوي [thermal_direct_print_formats_test.dart](../../test/structural/thermal_direct_print_formats_test.dart) يربط مسارات الإنتاج العشرة بالمقاس النهائي.

شُغّل `flutter analyze lib`؛ خرج برمز `1` بسبب معلومتين قائمتين من نوع `use_build_context_synchronously` في [purchase_returns_picpos_logic.dart:48](../../lib/presentation/purchase_returns_picpos/screens/purchase_returns_picpos_logic.dart#L48) و[sales_returns_picpos_logic.dart:84](../../lib/presentation/sales_returns_picpos/screens/sales_returns_picpos_logic.dart#L84)، دون أخطاء تحليل. ظهرت أثناء الاختبارات رسائل `MissingPluginException` غير حاجبة من `path_provider` في مهام بدء التشغيل المؤجلة؛ انتهت مجموعة الانحدار برمز `0` رغمها. لم أشغّل بناء Windows أو `build_runner`، ولم أغيّر [ready_template_deployment.dart](../../lib/data/database/ready_template_deployment.dart) أو أرفع حد [file_size_ratchet_test.dart](../../test/structural/file_size_ratchet_test.dart).
