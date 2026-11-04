# ملصق الميزان — تقرير التنفيذ والتحقق (2026-11-03)

## التنفيذ

- `ScaleBarcodeEncoder` في `lib/presentation/pos/services/scale_barcode_encoder.dart` يولّد EAN-13 من إعداد بادئة الوزن/السعر، PLU، معامل القسمة وطول الخانات، ويحسب check digit؛ ويرفض الـPLU/القيمة الخارجة عن النطاق أو البادئة التي لا يبدأ بها محلّل الميزان بدلاً من إخراج رمز غير صالح.
- حوار الملصقات يعرض خيار «باركود الميزان» للمنتج الموزون، ويقبل الوزن بالكيلوجرام، ويعرض نص الباركود الناتج. قيمة غير صالحة أو تجاوز الخانات يعطّل زر الطباعة ويظهر رسالة خطأ. الملصقات العادية تبقى على مسارها السابق.
- جرى تمرير بيانات المنتج الموزون إلى قالب «ملصق ميزان» ذي 58×40mm: الاسم، الوزن، سعر الوحدة/كجم، الإجمالي، تاريخ التعبئة، وEAN-13. يعرض الراسم نص الأرقام أسفل القضبان لمنع تداخل النص مع الباركود.
- أضيفت بذرة idempotent للقالب الجديد في `lib/data/database/daos/scale_barcode_template_seeder.dart`، منفصلة عن البذرة الستية، فتضيفه لقواعد البيانات القديمة دون تكرار القوالب أو تغيير المخطط. اختبار PDF يحذف قالب الميزان مع إبقاء القوالب الستة، يعيد البذر، ويتحقق من عدم التكرار.

## التحقق

- نجحت الحزمة النهائية بـ212 اختباراً عبر `flutter test --concurrency=1 --dart-define=APP_BRAND=picpos`: اختبارات المشفّر والـround-trip والواجهة والـPDF و`scale_barcode_handler_test.dart` و`picpos_scale_plu_test.dart` واختبارات layout/dialog للملصقات.
- نجحت `seeded_templates_map_to_bands_test.dart` و`template_files_are_complete_test.dart` و`printing_characterization_test.dart` و`printing_element_types_lockstep_test.dart` بعد استقرار تغييرات قوالب 80mm؛ لم أغيّر بصمات characterization أو عدد القوالب غير الباركود.
- نجحت الحراس الستة: `file_size_ratchet_test.dart` و`i18n_coverage_test.dart` و`i18n_runtime_safety_test.dart` و`dark_mode_guard_test.dart` و`analytics_parity_test.dart` و`presentation_db_import_guard_test.dart`.
- أُجري `flutter analyze lib`: لا توجد أخطاء تحليل جديدة؛ بقيت ملاحظتا `use_build_context_synchronously` المعروفتان في `purchase_returns_picpos_logic.dart:48` و`sales_returns_picpos_logic.dart:84` (الأمر يخرج بالحالة 1 بسبب هاتين الملاحظتين).
- لقطة PDFium موجودة في [قصّ الملصق](<docs/plans/scale_label_2026-11-03/scale_label_crop.png>) و[صفحة PDF كاملة](<docs/plans/scale_label_2026-11-03/scale_label_page.png>)، والملف المولّد في [PDF المعاينة](<docs/plans/scale_label_2026-11-03/scale_label_preview.pdf>). لا تتوفر `pyzbar` أو `zxingcpp` أو `cv2` في بيئة Python؛ لذلك التحقق من الباركود بصري مع اختبار round-trip للنص نفسه عبر `ScaleBarcodeHandler` وcheck digit، وليس فكاً آلياً لصورة القضبان.

لم تُرسل أي مهمة لطابعة فعلية. لم أعدّل `presentation/template_library_picpos` أو `presentation/template_editor_picpos`.