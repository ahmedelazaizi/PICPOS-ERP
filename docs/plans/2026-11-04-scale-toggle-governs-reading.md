# مؤشرا باركود الميزان يحكمان القراءة في POS

## القرار والتوافق الخلفي

قبل التغيير، كان `ScaleBarcodeHandler` يفسّر البادئات في البيع بصرف النظر عن `scale_weight_enabled` و`scale_price_enabled`، كما كان مسارا البحث يجرّبان استخراج PLU والكمية مباشرةً بعد فشل المحلّل. لذلك لم يكن تعطيل الخيار يمنع إضافة الصنف كوزن/سعر.

بعد التغيير، يقرأ الـhandler الإعداد عبر `ScaleBarcodeConfig`، وهو مصدر المفاتيح والبدائل القديمة. المؤشر الصريح `false` يمنع نمطه. إذا غاب مفتاح المؤشر تماماً، يُعدّ النمط مفعّلاً فقط عند وجود بادئة محفوظة له: بادئة الوزن الجديدة أو القديمة `scale_barcode_prefix`، وبادئة السعر الجديدة أو القديمة `scale_qty_prefix`. إذا لم توجد بادئة محفوظة فلا يُفعّل شيء افتراضياً. يحافظ هذا على سلوك من سبق أن ضبط إعداد الميزان، بينما يمنع التفعيل الضمني على إعداد جديد. المفاتيح القديمة `scale_qty_enabled` والمفاتيح الأخرى تبقى قراءةً احتياطية وفق `ScaleBarcodeConfig.legacyFallbacks`؛ لا تغيير schema أو migration.

تتحقق واجهتا بحث PicPos وPOS القديم من الإعداد نفسه قبل مسار تحليل الميزان أو fallback PLU. عند تعطيل بادئة مطابقة، يجري البحث العادي بالباركود الخام أولاً؛ إذا لم يوجد صنف (ولم يُعثر على صنف غير نشط)، تظهر الرسالة «باركود ميزان — فعّل باركود الميزان من الإعدادات» ولا يُعرض quick-add.

## ما نُفّذ

- إضافة توافق المؤشر المفقود في `ScaleBarcodeConfig.fromSettings` وتعليق يشرح سبب الافتراضي.
- إضافة قراءة إعداد مركزي في `ScaleBarcodeHandler`، ورفض تحليل النمط المعطّل.
- تمرير القرار من خلال إعداد مشترك في متحكمي البحث، وإظهار رسالة توجيهية عند مسح بادئة معطّلة لا تطابق صنفاً خاماً.
- إضافة ترجمة إنجليزية واختبارات إعداد ومحلّل لحالات التفعيل، والتعطيل الصريح، والمفتاح المفقود مع بادئة، والمفتاح المفقود بلا بادئة.

## التحقق

أُعيد تشغيل الحزمة المطلوبة بعد فصل `searchBarcode` إلى `picpos_search_controller_barcode.dart`، وشملت اختبارات الإعداد والمحلّل ولوحة الإعداد والطباعة والحوار وPLU والسيناريو والحراس الستة، بالأمر:

```powershell
. D:\qa\luna_tools.ps1; Clear-SqliteLock; flutter test --concurrency=1 --dart-define=APP_BRAND=picpos test/unit/scale_barcode_config_test.dart test/services/scale_barcode_handler_test.dart test/widget/scale_barcode_settings_panel_test.dart test/widget/scale_label_print_flow_test.dart test/widget/scale_barcode_label_dialog_test.dart test/widget/picpos_scale_plu_test.dart test/scenarios/picpos_quick_return_cart_test.dart test/structural/file_size_ratchet_test.dart test/structural/i18n_coverage_test.dart test/structural/i18n_runtime_safety_test.dart test/structural/dark_mode_guard_test.dart test/structural/analytics_parity_test.dart test/unit/presentation_db_import_guard_test.dart
```

النتيجة: `+52: All tests passed!`، بما فيها حارس حجم الملفات بعد استخراج الدالة. شغّلت `flutter analyze lib`؛ لم تظهر أخطاء/تحذيرات مرتبطة بهذه التغييرات، لكن انتهى الأمر بـ2 issue معلوماتية قديمة من `use_build_context_synchronously` فقط في `purchase_returns_picpos_logic.dart:48` و`sales_returns_picpos_logic.dart:84` (exit code 1). اختبارات config/handler تغطي enabled، و`false` الصريح، وغياب المؤشر مع بادئة محفوظة، وغياب المفتاح والبادئة؛ لم يُنشأ اختبار Widget جديد يمرر المسح فعلياً عبر شاشة POS، ولذلك تغطية المسح الفعلية تظل من parser/config لا من تفاعل واجهة.
