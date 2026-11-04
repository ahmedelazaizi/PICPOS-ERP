# طباعة الباركود من القوالب المخزنة — تقرير التنفيذ والتحقق (2026-11-03)

## التنفيذ

- أُضيفت قائمة «قالب الملصق» إلى حوار الدفعات، تعرض قوالب فئة `barcode` التي جلبها `IInvoiceTemplatesRepository` عبر مزود المستودع. يظهر خيار «التصميم الافتراضي القديم» دائمًا؛ يُستخدم القالب المعيّن افتراضيًا إن وُجد، وإلا يبقى التصميم القديم هو الاختيار. استُبقي اختيار «باركود الميزان» ومسار الوزن، وأُبقيت الطباعة القديمة كما هي عند اختيار التصميم القديم.
- عند اختيار قالب مخزّن، يمرّر الحوار معرّفه إلى `TemplatedInvoiceService.printBarcodeWithTemplate`؛ ومن ثم تُقرأ عناصره ومقاسه المخزنان عند إنشاء PDF. لم تُضف شاشة العرض استيرادًا من `data/database`، ولم يتغير مخطط قاعدة البيانات.
- كان سبب ظهور الملصق أعلى صفحة A4 عيبًا في أبعاد PDF الفعلية، لا أداة اللقطة: الخدمة كانت تحدد `PdfPageFormat.a4` وتضع الملصقات ضمن شبكة. أصبحت كل نسخة صفحة مستقلة بحجم القالب. يثبت اختبار قالب الميزان أن `MediaBox` يساوي `164.40945 × 113.38583` نقطة، أي `58×40 mm`، كما يثبت أن تغيير موضع عنصر مخزّن يغيّر PDF المرسل إلى راسل الاختبار الوهمي.
- عُدّل اختبار الطباعة التجريبية لحقن مرسل PDF وهمي، والتحقق من ترويسة/حجم البايتات ومن رسالة النجاح «أُرسلت 1 صفحة إلى الطابعة». بقي اختبار رفض الطباعة للقالب المتجاوز قائمًا.

## التحقق

- نجح الأمر الموحّد بـ`flutter test --concurrency=1 --dart-define=APP_BRAND=picpos` على اختبارات الطباعة المعدّلة، واختبارات `barcode_label_layout_test.dart` و`scale_barcode_label_dialog_test.dart` و`scale_barcode_label_pdf_test.dart`، والحراس الستة: `file_size_ratchet_test.dart` و`i18n_coverage_test.dart` و`i18n_runtime_safety_test.dart` و`dark_mode_guard_test.dart` و`analytics_parity_test.dart` و`presentation_db_import_guard_test.dart`، وكذلك `printing_characterization_test.dart`.
- نجح `git diff --check` بلا مخرجات. لم يُشغّل `build_runner` ولم يُرفع سقف `file_size_ratchet_test`.
- أُجري `flutter analyze lib`: لا أخطاء تحليل جديدة؛ بقيت ملاحظتا `use_build_context_synchronously` المعروفَتان في `purchase_returns_picpos_logic.dart:48` و`sales_returns_picpos_logic.dart:84`، لذا يخرج الأمر بالحالة 1.
- أعاد اختبار الميزان إنشاء `docs/plans/scale_label_2026-11-03/scale_label_preview.pdf`، فظهر الملف الثنائي معدّلًا في حالة الشجرة. تُرك كما أنتجه الاختبار ولم يُستعد أو يُحذف.

لم تُرسل طباعة إلى جهاز فعلي. لم تُعدّل ملفات محرر/مكتبة القوالب المحمية أو أصول القوالب.
