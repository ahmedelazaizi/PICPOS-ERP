import 'package:picpos_erp/core/i18n/tr.dart';

import '../../../../services/printing/barcode_label_spec.dart';
import '../../../pos/services/scale_barcode_config.dart';
import '../../../pos/services/scale_barcode_encoder.dart';

/// لماذا لا يُتاح «ملصق ميزان» في حوار طباعة الباركود. `null` ⇒ متاح.
///
/// كان الخيارُ يظهر أو يختفي بصمت (التحقّق الحيّ final3: «لم أجد ملصق
/// ميزان»)؛ الآن يبقى في القائمة معطّلاً ومعه السبب.
enum ScaleLabelBlock {
  noTemplate,
  notWeighed,
  multipleWeighed,
  missingPlu,
  settingDisabled,
  invalidSettings,
}

/// الترتيب مقصود: الأساسيُّ (قالب/صنف) قبل الإعداد، فلا يُطلب من المستخدم
/// تفعيلُ إعدادٍ لن يُفيد صنفاً غير موزون.
ScaleLabelBlock? scaleLabelBlockFor({
  required int? scaleTemplateId,
  required List<BarcodeLabelItem> items,
  required ScaleBarcodeConfig config,
}) {
  if (scaleTemplateId == null) return ScaleLabelBlock.noTemplate;
  final weighed = items.where((i) => i.isSoldByWeight).toList();
  if (weighed.isEmpty) return ScaleLabelBlock.notWeighed;
  if (weighed.length > 1) return ScaleLabelBlock.multipleWeighed;
  if (weighed.single.scalePluNumber == null) return ScaleLabelBlock.missingPlu;
  if (!config.weightEnabled) return ScaleLabelBlock.settingDisabled;
  if (!config.profileValid(ScaleBarcodeValueKind.weight)) {
    return ScaleLabelBlock.invalidSettings;
  }
  return null;
}

/// يُستدعى من `build` (‏`tr()` وقت الرسم).
String scaleLabelBlockText(ScaleLabelBlock block) => switch (block) {
  ScaleLabelBlock.noTemplate => tr(
    'قالب «ملصق ميزان» غير موجود في مكتبة الملصقات — أعد تشغيل البرنامج ليُضاف تلقائياً',
  ),
  ScaleLabelBlock.notWeighed => tr(
    'ملصق الميزان للأصناف المباعة بالوزن فقط — اجعل نوع الصنف «ميزان» وأدخل رقم PLU من شاشة تعديل الصنف',
  ),
  ScaleLabelBlock.multipleWeighed => tr(
    'ملصق الميزان يُطبع لصنف موزون واحد في كل مرة',
  ),
  ScaleLabelBlock.missingPlu => tr(
    'الصنف بلا رقم PLU — أدخله من شاشة تعديل الصنف',
  ),
  ScaleLabelBlock.settingDisabled => tr(
    'باركود الوزن غير مفعّل — فعّله من الإعدادات ← الأجهزة والطباعة ← باركود الميزان، ثم أعد فتح نافذة الطباعة',
  ),
  ScaleLabelBlock.invalidSettings => tr(
    'إعداد باركود الوزن غير صالح — صحّحه من الإعدادات ← الأجهزة والطباعة ← باركود الميزان',
  ),
};
