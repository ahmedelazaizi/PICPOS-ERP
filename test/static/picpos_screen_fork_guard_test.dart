import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// شاشاتٌ لها توأمٌ picpos ⇒ سطرُ بنائها لا بدّ أن يتفرّع بـ`Brand.isPicPos`.
///
/// الطاولاتُ كانت الشاشةَ الوحيدةَ بين جيرانها بلا تفرّعٍ ولم يلاحظ أحد —
/// وهذا الحارسُ يقفل ذلك النوعَ من السهو، لا هذه الحالةَ وحدَها.
///
/// ويقيس **التفرّعَ نفسَه** لا ذكرَ الاسم: `contains('TablesPicposScreen')`
/// وحدَه يمرّ على سطرِ استيرادٍ ميّتٍ لا يبني شيئاً، وذلك بعينه العطبُ الذي
/// جاء الحارسُ يمنعه. فالمقياسُ أن يُبنى التوأمان معاً على طرفَي `?:`.
void main() {
  test('كلُّ شاشةٍ لها توأمُ picpos تتفرّع في app_main_screen', () {
    final src = File('lib/app_main_screen.dart').readAsStringSync();
    const twins = {
      'TablesPicposScreen': 'TablesScreen',
      'ProductsPicposScreen': 'ProductsScreen',
    };
    for (final entry in twins.entries) {
      expect(src.contains(entry.key), isTrue,
          reason: 'التوأمُ ${entry.key} غيرُ مذكورٍ في app_main_screen');
      final fork = RegExp(
        r'Brand\.isPicPos\s*\?\s*const\s+'
        '${entry.key}'
        r'\(\)\s*:\s*const\s+'
        '${entry.value}'
        r'\(\)',
      );
      expect(fork.hasMatch(src), isTrue,
          reason: 'سطرُ بناء ${entry.value} لا يتفرّع إلى ${entry.key} '
              'بـ`Brand.isPicPos`');
    }
  });
}
