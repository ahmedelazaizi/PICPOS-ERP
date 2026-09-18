// حارسُ خطوةِ الشبكة في مصمّم القاعة.
//
// ═══ لماذا حارسٌ بنيويٌّ لا اختبارُ وحدة ═══
//
// العطبُ المحروسُ هنا **حلقةٌ لا تنتهي**: `_GridPainter.paint` يزيد
// `x += gridSize`، فبقيمةٍ صفرٍ أو سالبةٍ أو `NaN` يدور إلى الأبد **على خيط
// الواجهة** — الإطارُ لا يكتمل فتسودّ الشاشةُ ويتجمّد التطبيقُ بلا استثناءٍ
// يُرمى، أي بلا سطرٍ واحدٍ في اللوج.
//
// واختبارُ وحدةٍ يُرى أحمرَ هنا **يعني تعليقَ سويّة الاختبارات كلِّها** لا
// فشلاً يُقرأ — والبوّابةُ تأخذ أربعاً وثلاثين دقيقة. فالحارسُ يقرأ الشيفرةَ
// بدل أن يُشغّلها، وحذفُ سطرِ الحارس يُسقطه، وهذا ما تقتضيه الطفرة.
//
// و`_GridPainter` صنفٌ خاصٌّ في ملفّ العرض فلا يُستورَد أصلاً.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// نصُّ الملفّ بلا أسطر التعليق.
///
/// ⚠️ **وهذا ليس تزيُّداً — أوّلُ صياغةٍ لهذا الحارس سقطت به.** التعليقُ الذي
/// يشرح العطبَ يكتب `x += gridSize` حرفيّاً، وهو **فوق** الحارس. فقارن
/// الحارسُ موضعَ تعليقه بموضع حارسه فقال «الحارسُ بعد الحلقة» وهو قبلها.
/// حارسٌ يقرأ نثرَه أسوأُ من لا حارس.
String _code(String raw) => [
      for (final line in raw.split('\n'))
        if (!line.trimLeft().startsWith('//')) line,
    ].join('\n');

void main() {
  late String src;

  setUpAll(() {
    final f = File('lib/presentation/screens/tables/floor_plan_designer.dart');
    expect(f.existsSync(), isTrue,
        reason: 'مصمّمُ القاعة انتقل — حدِّث مسارَ الحارس');
    src = _code(f.readAsStringSync());
  });

  test('مرساةٌ — الحلقةُ التي يحرسها الحارسُ ما زالت موجودة', () {
    // بلا هذه المرساة يمرّ الحارسُ أخضرَ لو حُذف الرسّامُ كلُّه، فيحرس عدماً.
    expect(src.contains('x += gridSize'), isTrue,
        reason: 'حلقةُ الشبكة تبدّلت — راجع الحارسَ قبل أن تثق به');
  });

  test('وخطوةُ الشبكة محروسةٌ قبل الدوران', () {
    expect(src.contains('if (!(gridSize > 0) || !gridSize.isFinite) return;'),
        isTrue,
        reason: 'حارسُ `gridSize` سقط — صفرٌ أو NaN يجمّد التطبيقَ بلا استثناء');
  });

  test('والحارسُ يسبق الحلقةَ لا يتبعها', () {
    final guard = src.indexOf('!(gridSize > 0)');
    final loop = src.indexOf('x += gridSize');
    expect(guard, greaterThan(-1));
    expect(loop, greaterThan(-1));
    expect(guard, lessThan(loop),
        reason: 'الحارسُ بعد الحلقة لا يمنعها — الترتيبُ هو الحماية');
  });
}
