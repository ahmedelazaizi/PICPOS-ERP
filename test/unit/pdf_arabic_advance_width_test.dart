// عرضُ التقدّم للرسوم العربية — وجودُ الرسم لا يكفي.
//
// ── الفجوةُ التي تركها حارسُ التغطية ──────────────────────────────────────
// `pdf_arabic_glyph_coverage_test` يسأل: **هل الرسمُ موجودٌ في الخط؟**
// وهذا سؤالٌ ناقص. الرسمُ قد يكون موجوداً وعرضُ تقدّمه **صفراً** — فيُرسَم
// ولا يتحرّك القلم، فيقع الحرفُ التالي فوقه.
//
// مقيسٌ ميدانياً 2026-08-10 على إيصالٍ مطبوع: «صبري» ظهرت والياءُ **راكبةٌ
// على الراء**. وحارسُ التغطية أخضرُ في نفس اللحظة — لأنه يقيس الوجودَ لا
// العرض. وكذلك «لوز ارباع» طُبعت «لوزارباع»: المسافةُ ضاعت.
//
// و«صبري» بالذات: الراءُ لا توصل لما بعدها، فالياءُ تأخذ **الشكلَ المنفصل**
// U+FEF1 لا المتّصل. فأيُّ كلمةٍ آخرُها ي بعد (ر ز د ذ و ا) تصيبها العلّة.
//
// القياسُ هنا من نفس الجدول الذي يقرؤه الرسمُ وقتَ التشغيل (`hmtx` عبر
// `TtfParser.glyphInfoMap`)، لا من محلِّلٍ مكتوبٍ يدوياً.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

TtfParser _parse(String path) {
  final bytes = File(path).readAsBytesSync();
  return TtfParser(ByteData.sublistView(Uint8List.fromList(bytes)));
}

/// عرضُ تقدّم نقطةٍ في خطّ — `null` لو الرسمُ غيرُ موجودٍ أصلاً.
double? _advance(TtfParser f, int rune) {
  final gi = f.charToGlyphIndexMap[rune];
  if (gi == null) return null;
  return f.glyphInfoMap[gi]?.advanceWidth;
}

/// نقاطٌ لا تُرسم بلا عرض: أشكالُ عرضٍ عربية + المسافة.
const _kIsolatedYaa = 0xFEF1; // ي منفصلة — «صبري»
const _kFinalRaa = 0xFEAE; // ر نهائية
const _kIsolatedAlef = 0xFE8D; // ا منفصلة
const _kSpace = 0x0020; // المسافة — «لوز ارباع»

void main() {
  late TtfParser noto;

  setUpAll(() {
    noto = _parse('assets/fonts/NotoNaskhArabic-Regular.ttf');
  });

  test('الخطُّ الأساسيُّ يحمل الياءَ المنفصلة برسمٍ **وعرضٍ**', () {
    final adv = _advance(noto, _kIsolatedYaa);

    expect(adv, isNotNull,
        reason: 'U+FEF1 غيرُ موجودةٍ في الخطّ الأساسيّ — حارسُ التغطية '
            'كان يمسك هذه الحالة');
    expect(
      adv,
      greaterThan(0.0),
      reason: 'الرسمُ موجودٌ وعرضُ تقدّمه صفر ⇒ القلمُ لا يتحرّك بعد رسمه '
          'فيقع الحرفُ التالي فوقه. هذا هو «ي راكب على ر» المقيسُ على '
          'الإيصال المطبوع.',
    );
  });

  test('والمسافةُ لها عرضٌ — وإلا التصقت الكلمات', () {
    final adv = _advance(noto, _kSpace);

    expect(adv, isNotNull, reason: 'المسافةُ نفسُها غيرُ موجودةٍ في الخطّ');
    expect(adv, greaterThan(0.0),
        reason: '«لوز ارباع» طُبعت «لوزارباع» — المسافةُ رُسمت بعرضٍ صفر');
  });

  test('ضابط: أشكالُ العرض المجاورة لها عرضٌ فعلاً', () {
    // لو كان **كلُّ** شيءٍ صفراً فالعلّةُ في القراءة لا في الخطّ، وهذا
    // الضابطُ يفرّق بين الاثنين.
    for (final rune in <int>[_kFinalRaa, _kIsolatedAlef]) {
      final adv = _advance(noto, rune);
      expect(adv, isNotNull,
          reason: 'U+${rune.toRadixString(16).toUpperCase()} مفقودة');
      expect(adv, greaterThan(0.0),
          reason: 'U+${rune.toRadixString(16).toUpperCase()} عرضُها صفر — '
              'لو كلُّ الأعراض صفرٌ فالقراءةُ غلطٌ لا الخطّ');
    }
  });
}
