// ═══════════════════════════════════════════════════════════════════════════
// الوصل: كلُّ مستندٍ يخرج من BaseGenerator.newDocument يرسم العربيةَ كاملةً
// ═══════════════════════════════════════════════════════════════════════════
//
// حارسُ التغطية (`pdf_arabic_glyph_coverage_test`) يقيس ما **في** الأصول.
// وهذا الملفُّ يقيس ما يصل **الرسّامَ** فعلاً — وهما شيئان مختلفان، والفرقُ
// بينهما هو ما ضلّل الجلسةَ السابقة.
//
// ── الآليةُ الحقيقية (مقروءةٌ من مصدر الحزمة 3.12.0، ومقيسةٌ هنا) ─────────
// ١. `_preProcessSpans` يختار الخطَّ لكلّ نقطةٍ في النصّ **المنطقيّ**:
//        if (!font.isRuneSupported(rune)) { for (final fb in style.fontFallback) … }
//    أي على `ص ب ر ي` (U+0635 U+0628 U+0631 U+064A).
// ٢. ثم `text.dart:957` يحوّل النصَّ إلى **أشكال العرض** ويرسمها بالخطّ الذي
//    اختير في الخطوة ١.
//
// ⇒ لو كان الأساسيُّ يحمل النقاطَ المنطقية (وCairo يحملها) فالاحتياطيُّ **لا
//   يُستدعى إطلاقاً**، ثم يُطلب منه رسمُ شكلٍ لا يملكه فيسقط بصمت.
//   أي أن `fontFallback` **لا يمكن** أن يعالج العربية. الأساسيُّ هو الحلّ.
//
// والاحتياطيُّ يبقى نافعاً للاتينيّ والأرقام: غيرُ مُشكَّلةٍ، فنقاطُها
// المنطقيةُ هي نفسُها المرسومة، والخطوةُ ١ تراها على حقيقتها.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:picpos_erp/services/generators/base_generator.dart';

/// «صبري» — الياءُ فيها **منفصلةٌ** لأن الراءَ حرفٌ غيرُ موصولٍ بما بعده،
/// فتُرسم U+FEF1 وهي بالضبط ما ينقص Cairo.
const _nameWithDetachedYa = 'صبري';

/// `textDirection: rtl` شرطٌ للتحويل أصلاً (‏`text.dart:957`)، ومولّداتُ
/// الإنتاج تضبطه. بدونه تُرسم النقاطُ المنطقية ولا يُقاس شيء.
Future<pw.Document> _render(String text) async {
  final doc = await BaseGenerator.newDocument();
  doc.addPage(pw.Page(
    textDirection: pw.TextDirection.rtl,
    build: (_) => pw.Text(text, textDirection: pw.TextDirection.rtl),
  ));
  await doc.save(); // الرسمُ الفعليّ — قبله لا يُضمَّن خط
  return doc;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ⚠️ رُوجع عن قصدٍ 2026-08-10 — وهو ما كان السطرُ أدناه يطلبه صراحةً.
  //
  // كان الأساسُ نسخةً **عربيةً مقصوصة** من Noto (١٤٦ ك.ب) ينقصها ٥٢ حرفاً
  // لاتينياً، فكان الاحتياطيُّ (Cairo) ضرورةً. واستُبدل بالأصل **الكامل**
  // (‏static، ١٩٩ ك.ب) المقيسِ صفرَ نقصٍ في الأربعة: أشكالُ العرض ·
  // العربيةُ الأساسية · `A-Z a-z` · الأرقامُ والعلامات.
  //
  // فسقط مبرِّرُ الاحتياطيّ، وسقط معه ضررُه: أيُّ رمزٍ يقع على خطٍّ آخر
  // يقسم السطرَ بين خطَّين — ومقيسٌ بالرسم أن ذلك كان **يعكس اللاتينيَّ**
  // داخل السطر العربيّ (`SINV-24` ⇒ `24-V NIS`).
  test('المستندُ بلا احتياطيّ — الأصلُ الكاملُ يُغني', () async {
    final doc = await BaseGenerator.newDocument();
    expect(doc.theme, isNotNull);
    expect(
      doc.theme!.defaultTextStyle.fontFallback,
      isEmpty,
      reason: 'الاحتياطيُّ يقسم السطرَ بين خطَّين فيعكس اللاتينيَّ داخله. '
          'ولو رجع الأساسُ ناقصاً فالعلاجُ أصلٌ كامل لا احتياطيّ.',
    );
  });

  test('الأساسُ وحدَه يحمل اللاتينيَّ والأرقام — لا حاجةَ لاحتياطيّ', () async {
    final doc = await BaseGenerator.newDocument();
    final base = (await BaseGenerator.initFont())
        .getFont(pw.Context(document: doc.document));
    for (final c in const [0x41, 0x5A, 0x61, 0x7A, 0x30, 0x39, 0x25, 0x2F]) {
      expect(base.isRuneSupported(c), isTrue,
          reason: 'U+${c.toRadixString(16).toUpperCase()} مش في الأساس ⇒ '
              'هتطلع مربّعاً على كلّ مطبوع (‏ومنها رقمُ الفاتورة نفسُه)');
    }
  });

  test('الأساسيُّ نفسُه يحمل الياءَ المنفصلة U+FEF1', () async {
    final base = await BaseGenerator.initFont();
    // نفسُ الاختبار الذي يجريه الرسّام: PdfFont.isRuneSupported.
    final doc = await BaseGenerator.newDocument();
    final pdfFont = base.getFont(pw.Context(document: doc.document));
    expect(pdfFont.isRuneSupported(0xFEF1), isTrue,
        reason: 'الاحتياطيُّ لا يُستدعى لأشكال العرض إطلاقاً — لو ما كانش '
            'الأساسيُّ حاملَها فالحرفُ يُحذف بالسكوت من كلّ مطبوع.');
  });

  test('«صبري» تُرسم بخطٍّ واحدٍ — الأساسيُّ يكفيها', () async {
    final doc = await _render(_nameWithDetachedYa);
    expect(doc.document.fonts, hasLength(1),
        reason: 'أكترُ من خطٍّ هنا معناه إن الاسمَ اتقسم بين خطّين جوه '
            'الكلمة الواحدة — مظهرٌ مكسور.');
  });

  test('النصُّ المختلط يُرسم بخطٍّ **واحد** — عربيُّه ولاتينيُّه', () async {
    final doc = await _render('فاتورة INV-1024 — صبري 1,250.00');
    expect(
      doc.document.fonts,
      hasLength(1),
      reason: 'خطّان هنا معناهما أن السطرَ انقسم — ومقيسٌ بالرسم أن الانقسامَ '
          'يعكس اللاتينيَّ داخل السطر العربيّ (`SINV-24` ⇒ `24-V NIS`). '
          'الأصلُ الكاملُ يرسم السطرَ كلَّه بخطٍّ واحد.',
    );
  });

  test('كلُّ حروف «صبري» المرسومة مدعومةٌ فعلاً — لا حرفَ يسقط', () async {
    final doc = await BaseGenerator.newDocument();
    final ctx = pw.Context(document: doc.document);
    final base = (await BaseGenerator.initFont()).getFont(ctx);
    // الأشكالُ التي قِيس أن التحويلَ ينتجها لـ«صبري».
    for (final rune in const [0xFEF1, 0xFEAE, 0xFE92, 0xFEBB]) {
      expect(base.isRuneSupported(rune), isTrue,
          reason: 'U+${rune.toRadixString(16).toUpperCase()} مش مدعومة في '
              'الخطّ الأساسيّ ⇒ هتتحذف من الاسم على الإيصال');
    }
  });
}
