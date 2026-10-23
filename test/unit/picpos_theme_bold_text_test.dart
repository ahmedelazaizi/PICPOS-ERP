// ═══════════════════════════════════════════════════════════════════════════
// §٧ — الخطُّ غامقٌ ومتناسقٌ من الثيم، لا ودجتاً ودجتاً
// ═══════════════════════════════════════════════════════════════════════════
//
// طلبُ المالك: «الخطُّ في النظام بالكامل يجب أن يكون غامقاً بولد ومتناسقاً
// للوضوح».
//
// والجذرُ مقيس: أنماطُ **المتن** الثلاثة (`bodyLarge` · `bodyMedium` ·
// `bodySmall`) كانت بلا `fontWeight` إطلاقاً — أي `w400`. وهي معظمُ ما يُقرأ
// في الشاشات: نصوصُ الجداول والبطاقات والقوائم. فالعناوينُ `w700` والمتنُ
// `w400` في البطاقة الواحدة، وهذا هو التفاوتُ الذي رآه المالك.
//
// ── لماذا لا تُبنى `ThemeData` هنا ─────────────────────────────────────────
// **مقيسٌ في هذا المستودع سلفاً** (‏`brand_picpos_test.dart:152`): بناءُ
// `ThemeData` يستدعي `GoogleFonts` لأوزانٍ غيرِ مضمَّنةٍ في الـassets
// (‏`pubspec.yaml` يحمل `Cairo-Regular.ttf` وحدَه) فيرمي في الاختبار. وأكّدتُه
// بالتجربة: تعطيلُ الجلب أعطى
// «allowRuntimeFetching is false but font Cairo-Bold was not found».
//
// فالقياسُ على شيئين لا يحتاجان بناءً:
//   ١. ثابتا الوزن — عقدُ «وزنان اثنان» صريحاً.
//   ٢. ونصُّ `_textTheme` نفسُه: **كلُّ** نمطٍ يحمل وزناً. وهذا هو الشاهدُ
//      على العطب الأصليّ بعينه — نمطٌ بلا وزنٍ يقع على `w400` صامتاً.
//
// ⚠️ والتعليقاتُ تُجرَّد قبل أيّ قياسٍ نصّيّ: تعليقٌ يذكر `fontWeight` كان
// سيُحسب إنفاذاً وهو ليس كوداً.
//
// ⚠️ وحدُّ هذا الحارس مكتوبٌ صراحةً: يقيس **الثيم** لا ما تراه العين. وكثيرٌ
// من الجداول تضبط `fontWeight` في موضع الرسم وتتجاهل الثيمَ تماماً — تلك لا
// يمسّها هذا الملفّ ولا يدّعي أنه يفعل، وتحتاج مرورَ عينٍ بعد البناء.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/theme/picpos_theme.dart';

/// أخفُّ وزنٍ مقبولٍ في النظام. ما دونه يُقرأ باهتاً بجانب جاره.
const FontWeight _minWeight = FontWeight.w600;

/// جسمُ `_textTheme` مجرَّداً من التعليقات.
String _textThemeBody() {
  final source = File('lib/core/theme/picpos_theme.dart').readAsStringSync();

  final stripped = source
      .split('\n')
      .map((line) {
        final idx = line.indexOf('//');
        return idx == -1 ? line : line.substring(0, idx);
      })
      .join('\n');

  const marker = 'static TextTheme _textTheme(';
  final start = stripped.indexOf(marker);
  // ⚠️ `indexOf` يرجع `-1` وهو «أصغرُ من» كلِّ شيء، فيمرّ أيُّ شرطٍ لاحقٍ
  // على مقطعٍ فارغ. الفشلُ هنا صريحٌ بدل قياسِ العدم.
  if (start == -1) {
    throw StateError('لم يُعثر على `_textTheme` — تغيّر اسمُها؟');
  }
  return stripped.substring(start);
}

void main() {
  group('عقدُ الوزنين', () {
    test('كلاهما لا يقلّ عن w600', () {
      expect(PicPosTheme.bodyWeight.index,
          greaterThanOrEqualTo(_minWeight.index));
      expect(PicPosTheme.headingWeight.index,
          greaterThanOrEqualTo(_minWeight.index));
    });

    test('والعنوانُ أثقلُ من المتن فلا يضيع التراتبُ البصريّ', () {
      // توحيدُ الاثنين يمحو الفرقَ بين العنوان والنصّ فيصير الكلُّ كتلةً.
      expect(
        PicPosTheme.headingWeight.index,
        greaterThan(PicPosTheme.bodyWeight.index),
      );
    });
  });

  group('جدولُ الأنماط', () {
    test('لا نمطَ بلا وزنٍ صريح', () {
      final body = _textThemeBody();
      final chunks = body.split('GoogleFonts.cairo(');

      expect(chunks.length - 1, greaterThanOrEqualTo(14),
          reason: 'عددُ الأنماط أقلُّ من المتوقَّع — تغيّر شكلُ الجدول');

      for (var i = 1; i < chunks.length; i++) {
        expect(
          chunks[i].contains('fontWeight:'),
          isTrue,
          reason: 'النمطُ رقم $i بلا وزنٍ — يقع على w400 الافتراضيّ صامتاً',
        );
      }
    });

    test('والأوزانُ من الثابتَين لا أرقاماً مبعثرة', () {
      final body = _textThemeBody();

      // ‏`FontWeight.wNNN` حرفيّاً في الجدول يعني وزناً ثالثاً تسلّل خارجَ
      // العقد — وهو بابُ عودةِ التفاوت.
      expect(
        body.contains('fontWeight: FontWeight.w'),
        isFalse,
        reason: 'وزنٌ حرفيٌّ في الجدول خارجَ ثابتَي §٧',
      );
    });
  });
}
