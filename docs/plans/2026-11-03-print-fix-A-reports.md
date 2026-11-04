# إصلاح التقارير متعددة الصفحات — إصلاح A

## النتيجة

أُصلح تكرار رؤوس جداول التقارير وترقيم الصفحات «صفحة x من y» في مسارات `ReportPdfGenerator`، وأُضيف التذييل المشترك أيضاً إلى تقارير `ReportGenerator` القديمة التي تظهر في مصفوفة الطباعة. لا تغيير في الحسابات أو الأرقام. حزمة `pdf` المثبتة في `pubspec.lock` هي `3.12.0` وتدعم `pw.TableRow.repeat`.

## قبل / بعد

| المسار | قبل | بعد |
|---|---|---|
| الميزان، كشف الطرف، المبيعات، الأستاذ، المخزون والجداول الأخرى | رؤوس الجداول لا تتكرر على صفحات الاستمرار؛ أغلب تقارير A4 بلا ترقيم | `repeat: true` على صفوف الرؤوس، والتذييل المشترك على كل صفحات `MultiPage` |
| مبيعات `ReportGenerator` القديم | بلا رأس متكرر أو ترقيم | رأس متكرر وترقيم عبر دالة التذييل المشتركة |
| كشف 25 حركة | صفحتان؛ الصفحة الثانية حركتان والإجمالي | بقيت صفحتين، الرأس والترقيم موجودان في كلتيهما؛ وثّق أدناه سبب بقاء الصفحة قصيرة |

اختبار المصفوفة التقط **17 PDF**. من الحالات الرئيسية: كشف 25 حركة صفحتان، كشف 200 حركة 7 صفحات، ميزان 150 حساباً 7 صفحات، المبيعات 300 صف 14 صفحة، دفتر الأستاذ 300 حركة 14 صفحة، والمخزون 300 صنف 22 صفحة. كل صفحتين فأكثر فُحصتا بنص `pdf_probe` لرأس الجدول عند وجود جدول وترقيم الصفحة؛ لا تختبر الأرقام المحاسبية أو حدود glyph الدقيقة هذه الإضافة.

## الصفحة شبه الفارغة في كشف 25 حركة

السبب: ارتفاع مساحة ثابتة قبل الجدول (هوية الشركة، عنوان الكشف، الرصيد الحالي) مع ارتفاع صفوف الحركة، ثم صف الإجماليات الذي يبقى بعد آخر حركة. تتسع الصفحة الأولى لـ23 حركة فقط، فتنتقل حركتان وصف الإجماليات إلى الصفحة الثانية. لم أغيّر ارتفاعات العناوين/الرصيد أو حجم الخط فقط لدفع صفّين إلى الصفحة الأولى؛ ذلك تعديل تخطيط قد يضر قابلية القراءة في الكشوف الأطول. لذلك بقيت الحالة موثقة بدل إدخال معالجة تخطيطية غير مضمونة.

## المراجعة البصرية

تحولت PDFs عبر `tool/print_audit_reports/render_sheets.py` باستخدام PDFium، وفُحصت لوحات الصفحات بصرياً. الرأس والترقيم ظاهران في صفحات الاستمرار في العينات التالية:

- [كشف العميل](<print_fix_A_2026-11-03/party_customer_contact.png>) — بما فيه حالة 25 حركة والصفحة القصيرة.
- [ميزان المراجعة](<print_fix_A_2026-11-03/trial_balance_contact.png>).
- [المبيعات](<print_fix_A_2026-11-03/sales_contact.png>).
- [المبيعات القديمة](<print_fix_A_2026-11-03/legacy_sales_contact.png>).
- [دفتر الأستاذ](<print_fix_A_2026-11-03/ledger_contact.png>).
- [المخزون](<print_fix_A_2026-11-03/inventory_contact.png>).

القراءة البصرية تثبت تكرار الرأس والترقيم للصفحات المعروضة، ولا تثبت خلو كل glyph من القص في جميع البيانات. أدوات القياس الحالية لا تعرض عرض glyph أو صناديق الصفوف؛ لذا بقي تداخل الصف/انقسامه وقياس القص الدقيق غير محسومين.

## الملفات

- `lib/services/printing/report_pdf_generator.dart`: تكرار رؤوس الجداول، تذييل مشترك يستدعي `tr()` وقت البناء بخط التقرير واتجاه RTL، وحد صفحات 40 لتقرير المخزون الذي يتجاوز 20 صفحة بعد إضافة التذييل والرأس المتكرر.
- `lib/services/printing/financial_statement_pdf_sections.dart`: فصل أقسام قائمة الدخل والمركز المالي حتى يبقى المولّد دون سقف الحجم الحالي.
- `lib/services/generators/report_generator.dart`: تذييل مشترك ورؤوس متكررة للمولّد القديم الذي تغطيه المصفوفة.
- `test/print_audit/reports/report_matrix_test.dart`: تأكيد آلي على الرأس/الترقيم في نص كل صفحة متعددة الصفحات.
- اللقطات: `docs/plans/print_fix_A_2026-11-03/`.

## التحقق والقيود

- `flutter test --run-skipped --concurrency=1 --dart-define=APP_BRAND=picpos test/print_audit/reports/report_matrix_test.dart` — نجح (`All tests passed!`). عُلّق تخطي المصفوفة عبر `--run-skipped` لأن الاختبار موسوم بـ`auditSkip`. سجل logger رسائل `MissingPluginException` من `path_provider` لكنها لم تفشل الاختبار.
- `flutter test --concurrency=1 test/structural/i18n_coverage_test.dart` — نجح.
- `flutter test --concurrency=1 test/structural/i18n_runtime_safety_test.dart` — نجح.
- `flutter test --concurrency=1 test/structural/dark_mode_guard_test.dart` — نجح.
- `flutter test --concurrency=1 test/unit/presentation_db_import_guard_test.dart` — نجح.
- `flutter test --concurrency=1 test/structural/file_size_ratchet_test.dart` — فشل بسبب ملف خارج النطاق `lib/services/invoice_generator.dart` (30,758 بايت، ملف جديد/كبير). بعد استخراج أقسام القوائم المالية بقي مولّد التقارير تحت سقفه دون تعديل أي سقف في الاختبار.
- `flutter test --concurrency=1 test/structural/analytics_parity_test.dart` — تعذر تحميل الاختبار بسبب أخطاء موديل الطابعة غير المتعلقة بهذه المهمة: `printer_dao.dart` و`template_binding_dao.dart` يمرران/يقرآن `paperWidthMm` غير المتاح في `Printer`/`PrintersCompanion` الحاليين.
- `flutter analyze lib` — فشل لأخطاء `paperWidthMm` الثلاثة نفسها. ظهرت أيضاً ملاحظتا `use_build_context_synchronously` القديمتان المسموح بهما في `purchase_returns_picpos_logic.dart` و`sales_returns_picpos_logic.dart`.
- `flutter analyze` على ملفات مولّد التقرير وقسم القوائم المالية — نجح بعد استخراج الدوال. لم يُجرَ تحليل شامل نظيف بسبب أخطاء الطابعة المذكورة.

لم أعدّل ملفات DAO أو `invoice_generator.dart`، ولم أعمل commit أو push.