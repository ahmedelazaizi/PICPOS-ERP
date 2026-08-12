// «عريض» في المصمّم يجب أن يصل الورقةَ وجهاً عريضاً.
//
// ── فئةُ العطب (مقيسٌ من مصدر الحزمة 2026-08-12) ──────────────────────────
// `_getStyle` كان يبني النمطَ هكذا:
//     pw.TextStyle(font: _arabicFont, fontWeight: element.isBold ? bold : …)
//
// و`pdf-3.12.0/lib/src/widgets/text_style.dart:150-153`:
//     fontBold = fontBold ?? (… fontWeight == FontWeight.bold ? font : null)
//
// فحين `isBold` يُركَّب **الوجهُ العاديُّ في خانة العريض**، ثم `merge` يمرّره
// فوق ثيم المستند فيدهس `NotoNaskhArabic-Bold` المحمَّل فعلاً في
// `BaseGenerator.newDocument()`. والنتيجة: لا شيءَ في المطبوع يخرج عريضاً —
// لا «الإجمالي النهائي»، ولا «طلب رقم» في تذكرة المطبخ (مبذورةٌ 20pt bold)،
// ولا أيُّ حقلٍ علّمه المالكُ بزرّ B. والوحيدُ الناجي صفُّ عناوين الجدول،
// لأنه يمرّر `font: _arabicBoldFont` صراحةً.
//
// وهذا صُلبُ قرار الخيار (ب): الطابعةُ تحترم تخطيطَ المصمّم — والوزنُ منه.
//
// والقياسُ هنا على **وجه الخطّ بعد الدمج**، لا على `fontWeight` — فالنيّةُ
// كانت صحيحةً دائماً والوجهُ هو الذي كان يخون.

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:ural_erp/services/generators/base_generator.dart';
import 'package:ural_erp/services/templated_invoice_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// وجهُ الخطّ الذي سيُرسَم به فعلاً — بعد الدمج فوق ثيم المستند، كما يحدث
  /// داخل `pw.Page` تماماً.
  Future<String?> renderedFaceOf({required bool isBold}) async {
    final base = await BaseGenerator.initFont();
    final bold = await BaseGenerator.initBoldFont();
    final theme = pw.ThemeData.withFont(base: base, bold: bold ?? base);
    final style = theme.defaultTextStyle
        .merge(await TemplatedInvoiceService.debugStyleFor(isBold: isBold));
    return style.font?.fontName;
  }

  test('الحقلُ المعلَّمُ عريضاً يُرسم بالوجه العريض', () async {
    expect(await renderedFaceOf(isBold: true), contains('Bold'));
  });

  test('ضابط: الحقلُ العاديُّ يبقى على الوجه العادي', () async {
    expect(await renderedFaceOf(isBold: false), isNot(contains('Bold')));
  });
}
