// حارسٌ بنيويٌّ ضدّ تجاوزِ `headingRowColor` وحدَه في طبقة العرض.
//
// ═══ العقدُ المكسور ═══
//
// `dataTableTheme` يعرّف **شقّين مقترنَين**: خلفيّةَ رأس الجدول ولونَ نصِّه.
// وقد قِيسا في 2026-08-22:
//
//   • PicPos (الوضعان معاً) — `headingTextStyle.color = Colors.white`
//     على `headingRowColor = AppColors.primaryDark`.
//   • UralCash الفاتح — نصٌّ داكنٌ (`textPrimary`) على `AppColors.surface`.
//
// فتجاوزُ **الخلفيّةِ وحدَها** إلى لونٍ فاتح — `cardColor` أو
// `grey.shade50` أو `surfaceContainerLow` أو تظليلٍ بنسبةٍ صغيرة — يكسر
// الاقتران: يبقى النصُّ أبيضَ من الثيم، فيصير **أبيضَ على فاتح** ويختفي
// رأسُ الجدول تماماً تحت هويّة PicPos. بلاغٌ ميدانيّ 2026-08-21.
//
// ═══ ولماذا الحذفُ لا استبدالُ اللون ═══
//
// لأن الثيمَ يملك الشقّين معاً ويعرّفهما لكلّ علامةٍ ووضع. فحذفُ التجاوز
// يعيد الرأسَ إلى زوجٍ صحيحٍ **في العلامتَين** بلا سطرٍ إضافيّ. أمّا اختيارُ
// لونٍ «مناسب» يدويّاً فيصحّ في وضعٍ ويكسر الآخر.
//
// ═══ الاستثناءُ الوحيد ═══
//
// `app_data_table.dart` يتجاوز **الشقّين معاً**: خلفيّةً فاتحةً
// (`primary` بنسبة ٦٪) **و**لونَ نصٍّ داكناً (`AppColors.primaryDark`)
// يُلبَس لكلّ عمودٍ في `_styleColumn`. فالاقترانُ محفوظٌ والنصُّ مقروء.
// وهذا هو المعيار: من تجاوز الخلفيّةَ فليتجاوز النصَّ معها، أو فليترك
// الاثنين للثيم.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ملفّاتٌ يُسمَح لها بتجاوز `headingRowColor` لأنها تتجاوز لونَ النصِّ معه.
///
/// إضافةُ ملفٍّ هنا **ليست إعفاءً**: هي تعهّدٌ بأن الملفَّ يضبط الشقّين.
/// راجعه بعينك قبل أن تضيفه.
const _pairsBothHalves = <String>{
  'lib/presentation/widgets/common/app_data_table.dart',
};

void main() {
  test('لا تجاوزَ لخلفيّةِ رأس الجدول وحدَها في طبقة العرض', () {
    final root = Directory('lib/presentation');
    expect(root.existsSync(), isTrue,
        reason: 'يُشغَّل من جذر المستودع');

    final offenders = <String>[];

    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final rel = entity.path.replaceAll(r'\', '/');
      if (_pairsBothHalves.contains(rel)) continue;

      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (!line.contains('headingRowColor')) continue;
        // التعليقاتُ التي تشرح القاعدةَ ليست مخالفةً لها.
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('//') || trimmed.startsWith('///')) continue;
        offenders.add('$rel:${i + 1}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'كلُّ موضعٍ هنا يتجاوز خلفيّةَ الرأس ويترك لونَ النصِّ للثيم '
          '— فيصير أبيضَ على فاتحٍ تحت هوية PicPos ويختفي الرأس.\n'
          'الإصلاحُ **حذفُ السطر** لا اختيارُ لونٍ آخر: الثيمُ يملك '
          'الشقّين ويعرّفهما لكلّ علامةٍ ووضع.\n'
          'المواضع:\n  ${offenders.join('\n  ')}',
    );
  });
}
