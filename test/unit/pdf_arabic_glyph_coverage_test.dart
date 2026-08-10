// ═══════════════════════════════════════════════════════════════════════════
// حارسُ تغطية الرسوم العربية في خطوط الطباعة
// ═══════════════════════════════════════════════════════════════════════════
//
// حزمةُ `pdf` لا تُشكّل بـOpenType: تحوّل النصَّ العربيَّ إلى **أشكال العرض**
// (Presentation Forms-B، المدى U+FE70..FEFF) قبل الرسم. ثم تختار الخطَّ لكلّ
// نقطةٍ بـ`PdfFont.isRuneSupported`، وهي حرفياً:
//
//     font.charToGlyphIndexMap.containsKey(charCode)      // ttffont.dart:205
//
// فالقياسُ هنا بنفس الخريطة التي يقرؤها الرسمُ وقتَ التشغيل، عبر `TtfParser`
// الذي تصدّره الحزمةُ نفسُها — **لا بمحلِّلِ cmap مكتوبٍ يدوياً** (‏محلِّلٌ
// كهذا أعطى ٥٢ نقصاً كاذباً في جلسةٍ سابقة).
//
// ── لماذا هذا الحارس ──────────────────────────────────────────────────────
// `Cairo-Regular.ttf` المرفوع ينقصه **الياءُ المنفصلة U+FEF1**، وعرضُ الرسم
// المفقود **صفرٌ مطابقٌ لـ`.notdef`** — فالحرفُ يُحذف بالسكوت ولا يظهر
// مربّعاً يلفت النظر. يصيب كلَّ كلمةٍ آخرُها ي بعد حرفٍ غيرِ موصول:
// «صبري» · «بدري» · «خيري» · «المصري».
//
// وإعادةُ تنزيل Cairo لا تُصلحه: المرفوعُ مطابقٌ للرسميِّ بايت ببايت، أي أن
// الخطَّ الرسميَّ نفسَه بلا الرسم. الحلُّ خطٌّ احتياطيّ.
//
// الحارسُ يثبّت النتيجة: أيُّ تبديلٍ لخطٍّ يُسقط التغطيةَ يُسقط هذا الاختبار.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

/// أشكالُ العرض العربية — المدى الذي ترسم الحزمةُ منه فعلاً.
/// النهايةُ FEFC: ما بعدها (‏FEFD..FEFF) ليس أشكالَ حروف.
const _kFormsStart = 0xFE70;
const _kFormsEnd = 0xFEFC;

/// U+FE75 نقطةٌ **غيرُ مخصَّصةٍ** في يونيكود — لا خطَّ يحملها ولا يُنتظر منه.
const _kUnassigned = {0xFE75};

TtfParser _parse(String path) {
  final bytes = File(path).readAsBytesSync();
  return TtfParser(ByteData.sublistView(Uint8List.fromList(bytes)));
}

/// كلُّ نقاطِ المدى المخصَّصة فعلاً.
Iterable<int> expectedRunes() sync* {
  for (var c = _kFormsStart; c <= _kFormsEnd; c++) {
    if (!_kUnassigned.contains(c)) yield c;
  }
}

void main() {
  late TtfParser cairo;
  late TtfParser noto;

  setUpAll(() {
    cairo = _parse('assets/fonts/Cairo-Regular.ttf');
    noto = _parse('assets/fonts/NotoNaskhArabic-Regular.ttf');
  });

  test('الأصلان محزومان وقابلان للتحليل', () {
    expect(cairo.charToGlyphIndexMap, isNotEmpty);
    expect(noto.charToGlyphIndexMap, isNotEmpty);
  });

  test('التوثيق مقيس: Cairo وحدَه ينقصه الياءُ المنفصلة U+FEF1', () {
    expect(
      cairo.charToGlyphIndexMap.containsKey(0xFEF1),
      isFalse,
      reason: 'لو بقى Cairo يغطّيها فالخطُّ اتبدّل — راجع سببَ وجود '
          'الاحتياطيِّ أصلاً قبل ما تشيله.',
    );
  });

  test('الخطُّ **الأساسيُّ** وحدَه يغطّي أشكالَ العرض كلَّها', () {
    // ⚠️ الاحتياطيُّ لا يُنقذ هنا: الحزمةُ تختاره على النصّ **المنطقيّ** قبل
    // التحويل، فلا يُستدعى لشكلٍ ناقصٍ إطلاقاً (‏اقرا
    // `pdf_document_font_fallback_wiring_test`). فالتغطيةُ لازم تكون في
    // الأساسيّ وحدَه — وهو Noto Naskh بقرار المالك 2026-08-10.
    final missing = expectedRunes()
        .where((r) => !noto.charToGlyphIndexMap.containsKey(r))
        .map((r) => 'U+${r.toRadixString(16).toUpperCase()}')
        .toList();
    expect(
      missing,
      isEmpty,
      reason: 'نقاطٌ الأساسيُّ لا يحملها ⇒ الحرفُ يُحذف بالسكوت من كلّ '
          'مطبوع. الناقص: ${missing.join(', ')}',
    );
  });

  test('الاحتياطيّ (Cairo) يغطّي اللاتينيَّ الذي ينقص الأساسيَّ', () {
    // اللاتينيُّ والأرقامُ غيرُ مُشكَّلة، فنقاطُها المنطقيةُ هي نفسُها
    // المرسومة — وهنا يعمل `fontFallback` فعلاً.
    final ascii = [for (var c = 0x20; c <= 0x7E; c++) c];
    final notoLacks =
        ascii.where((c) => !noto.charToGlyphIndexMap.containsKey(c)).toList();
    expect(notoLacks, isNotEmpty,
        reason: 'ضابط: لو الأساسيُّ بقى يغطّي اللاتينيَّ كلَّه فالاحتياطيُّ '
            'ما بقاش لازماً — راجع الوصلَ عن قصد');
    for (final c in notoLacks) {
      expect(cairo.charToGlyphIndexMap.containsKey(c), isTrue,
          reason: 'المحرف ${String.fromCharCode(c)} (U+'
              '${c.toRadixString(16).toUpperCase()}) مش في أيٍّ من الخطّين');
    }
  });

  test('حروفُ الأسماء الشائعة: «صبري» بأشكالها المرسومة', () {
    // مقيس: «صبري» ⇒ U+FEF1 U+FEAE U+FE92 U+FEBB
    // (الياءُ منفصلةٌ لأن الراءَ حرفٌ غيرُ موصولٍ بما بعده).
    for (final rune in const [0xFEBB, 0xFE92, 0xFEAE, 0xFEF1]) {
      expect(noto.charToGlyphIndexMap.containsKey(rune), isTrue,
          reason: 'U+${rune.toRadixString(16).toUpperCase()} مش في الأساسيّ — '
              'الاسمُ هيتطبع ناقصَ حرف');
    }
  });
}
