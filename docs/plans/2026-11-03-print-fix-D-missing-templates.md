# تقرير تنفيذ قوالب الطباعة الناقصة — Print Fix D

التاريخ: 2026-11-03

المشروع: `D:\PICPOS-ERP`

## النتيجة

أُضيفت ستة قوالب JSON مفقودة، وسُجلت في مكتبة القوالب، وأُثبت حفظ `layoutVersion: 2` عند الاستيراد. كما وُصل تمرير `ShiftClosingSnapshot` إلى مسار v2 باستعمال محلّل قيم الوردية نفسه المستخدم في المسار القديم؛ لا تغييرات في منطق المحاسبة أو مخطط Drift.

- حراري 58mm: [مرتجع المبيعات](../../assets/invoice_templates/thermal58_sales_return.json)، [طلب المطبخ](../../assets/invoice_templates/thermal58_kitchen.json)، [إغلاق الوردية](../../assets/invoice_templates/thermal58_shift_closing.json)، [فاتورة المشتريات](../../assets/invoice_templates/thermal58_purchase_invoice.json).
- A5: [مرتجع المبيعات](../../assets/invoice_templates/a5_sales_return.json)، [فاتورة المشتريات](../../assets/invoice_templates/a5_purchase_invoice.json).
- أُدرجت الملفات في [قائمة القوالب الجاهزة](../../lib/data/database/daos/invoice_template_dao.dart)، وتتحقق اختبارات مسار الإعداد من الربط بنوع المستند، اختيار القالب المرتبط، وفحص ملاءمة الورق. الملاءمة المقبولة: 58mm على طابعة 72mm، و148mm (A5) على 210mm.

## مراجعة العرض

أُنتجت 350 ورقة PDF (25 قالباً × 14 سيناريو)، ورُسمت 56 عيّنة في لوحة التواصل الرئيسية و53 صورة منتقاة بواسطة PDFium. راجعت القوالب الستة عبر السيناريوهات الخمسة، إضافة إلى صفحات النهاية لعينتي A5 ذواتي 120 بنداً.

- القوالب الستة تعلن `layoutVersion: 2`، ولا تستخدم رموزاً تعبيرية، وأقل حجم خط معلن فيها 7pt (7.2pt في A5، و8pt في المطبخ).
- أظهرت عينات الوردية القيم والملخص والتذييل؛ وأظهر المطبخ رقم الطلب والطاولة والملاحظات. قيم المبالغ ذات 8 أرقام ظاهرة كاملة في العينات الحرارية وA5.
- طباعة A5 لسيناريو 120 بنداً امتدت إلى 7 صفحات؛ صفحة النهاية تعرض آخر البنود والتذييل بوضوح. إيصالات 58mm بقيت صفحة مستمرة واحدة لكل سيناريو.
- في الجدول الحراري الضيق، يختصر عرض الاسم الطويل بعلامة حذف ليتسع مع الأعمدة؛ أسماء البنود في A5 تلتف على الأسطر. قياس `clipped_text_runs` في CSV تقديريّ (13 للمطبخ، و1 لكل من المرتجع الحراري وفاتورة المشتريات الحرارية)، وليس قياساً دقيقاً لحدود الحروف؛ الفحص البصري للعينات لم يُظهر قصاً عند حواف الورق.

اللوحة المرئية: [صور السيناريوهات الثلاثين للقوالب الجديدة](print_fix_D_2026-11-03/new_templates_contact_sheet.png).

صفحتا A5 الأخيرتان: [مرتجع المبيعات](print_fix_D_2026-11-03/a5_sales_return_S5_120_items_last_page.png)، [فاتورة المشتريات](print_fix_D_2026-11-03/a5_purchase_invoice_S5_120_items_last_page.png).

مخرجات PDF وCSV: `D:\qa\print_fix_D\invoices`.

## الاختبارات والمقارنة

نجح الأمر الجامع للاختبارات التالية، مع `RUN_PRINT_AUDIT=1` لمصفوفة الطباعة:

- [مصفوفة الفواتير](../../test/print_audit/invoices/print_matrix_test.dart) و[مسار الإعداد](../../test/print_audit/setup_path/setup_path_audit_test.dart).
- [اكتمال القوالب](../../test/structural/template_files_are_complete_test.dart) و[ربطها بالنطاقات](../../test/unit/seeded_templates_map_to_bands_test.dart).
- [قيم الوردية](../../test/unit/shift_template_values_test.dart)، [مسار v2](../../test/unit/printing_layout_v2_test.dart)، و[بصمات التوصيف](../../test/unit/printing_characterization_test.dart).
- حراس [حجم الملف](../../test/structural/file_size_ratchet_test.dart)، وi18n، والوضع الداكن، وتكافؤ التحليلات، واستيراد قاعدة البيانات من طبقة العرض. لم تُرفع حدود حارس حجم الملف.

المقارنة النقطية مع `D:\qa\print_fix_C\invoices`: القوالب الـ19 السابقة، 266 ملف PDF و326 صفحة؛ 0 اختلافات بكسلية و0 ملفات مفقودة. أُضيفت ست بصمات ذهبية جديدة للقوالب الجديدة، ونجح [اختبار بصمات التوصيف](../../test/unit/printing_characterization_test.dart) بعد تحديثها.

نجح التحليل المحدد للملفات المعدلة. أما `flutter analyze lib` فلم ينجح بسبب ملاحظتي معلومات في ملفي [مسار مرتجعات المشتريات](../../lib/presentation/purchase_returns_picpos/screens/purchase_returns_picpos_logic.dart#L48) و[مسار مرتجعات المبيعات](../../lib/presentation/sales_returns_picpos/screens/sales_returns_picpos_logic.dart#L84) (`use_build_context_synchronously`)، وهما خارج نطاق التغيير. لم يُشغّل `build_runner`.

ظهرت أثناء الاختبارات رسائل `MissingPluginException` الخاصة بـ`path_provider` وتحذيرات خطّ emoji من قوالب أقدم؛ لم تمنع الاختبارات من النجاح، وهذه الرسائل ليست من القوالب الستة الجديدة.
