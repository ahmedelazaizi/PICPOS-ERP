// حارسٌ بنيويّ: ثوابتُ `AppColors` الداكنةُ تطابق رموزَ ثيم PicPos.
//
// ═══ العطبُ الذي وُلد له ═══
//
// كان `AppColors.cardDark` (فرع PicPos) `#0A2E63` و`borderDark` `#0250D3`،
// بينما `PicPosTheme` يرسم بطاقاته `#121C2E` وحدودَه `#243247`. والقيمتان
// الأوليان **لا تظهران في أيّ موضعٍ آخرَ من الشجرة**: لا الثيمُ يقرؤهما
// ولا التصميمُ يذكرهما.
//
// فكانت الشاشةُ الواحدةُ تحمل **سطحَين بلونَين**: ما يأخذ لونَه من الثيم
// (`Card` · `Dialog` · `DataTable`)، وما يأخذه من `AppColors.…Dark` عبر
// `context.picposCard` و`picposHairline` وودجتاتٍ مشتركةٍ ثلاث. وهو ما ظهر
// في صور المالك 2026-08-24 بعد أن وُسّع استعمالُ المُلحق إلى تسعين موضعاً.
//
// ═══ لماذا حارسٌ لا تعليق ═══
//
// لأنّ الرمزَين يعيشان في ملفَّين، وتعديلُ أحدِهما لا يلفت النظرَ إلى
// الآخر. والتضاربُ صامتٌ تماماً: يُترجَم، ويمرُّ التحليلَ، ولا يمسكه
// اختبارٌ لا يقارن الملفَّين — ولا يظهر إلّا لعينِ المالك على شاشةٍ داكنة.
//
// ⚠️ ولا يفحص هذا الحارسُ فرعَ UralCash: قيمُه مستقلّةٌ ولها ثيمُها.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// يقرأ `static const Color <name> = ... Color(0xAABBCCDD)` من ملفّ.
///
/// يعيد **كلَّ** قيم `Color(0x…)` في تعريفِ الرمز مرتَّبةً، فيلتقط فرعَي
/// الشرط الثلاثيِّ في `AppColors` معاً.
List<String> _colorsOf(String src, String name) {
  final decl = RegExp(
    'static const Color $name\\s*=([^;]*);',
    multiLine: true,
  ).firstMatch(src);
  if (decl == null) return const [];
  return RegExp(r'Color\(0x([0-9A-Fa-f]{8})\)')
      .allMatches(decl.group(1)!)
      .map((m) => m.group(1)!.toUpperCase())
      .toList();
}

void main() {
  test('ثوابتُ AppColors الداكنةُ تطابق رموزَ ثيم PicPos', () {
    final colors = File('lib/core/theme/app_colors.dart');
    final theme = File('lib/core/theme/picpos_theme.dart');
    expect(colors.existsSync() && theme.existsSync(), isTrue,
        reason: 'يُشغَّل من جذر المستودع');

    final cSrc = colors.readAsStringSync();
    final tSrc = theme.readAsStringSync();

    // الرمزُ في `AppColors` ونظيرُه في ثيم PicPos.
    const pairs = <String, String>{
      'cardDark': '_cardDark',
      'borderDark': '_hairlineDark',
    };

    final mismatches = <String>[];

    for (final entry in pairs.entries) {
      final themeValues = _colorsOf(tSrc, entry.value);
      expect(themeValues, hasLength(1),
          reason: 'رمزُ الثيم ${entry.value} لم يُقرأ — تبدّلت صياغتُه؟');

      final appValues = _colorsOf(cSrc, entry.key);
      expect(appValues, isNotEmpty,
          reason: 'ثابتُ ${entry.key} لم يُقرأ — تبدّلت صياغتُه؟');

      // فرعُ PicPos هو **الأوّل** في `Brand.isPicPos ? أ : ب`.
      final picpos = appValues.first;
      final wanted = themeValues.single;
      if (picpos != wanted) {
        mismatches.add(
          'AppColors.${entry.key} = #$picpos '
          'بينما PicPosTheme.${entry.value} = #$wanted',
        );
      }
    }

    expect(
      mismatches,
      isEmpty,
      reason: 'ثابتٌ داكنٌ يخالف رمزَ الثيم ⇒ سطحان بلونَين على الشاشة '
          'الواحدة: ما يأخذ من الثيم، وما يأخذ من `AppColors` عبر '
          '`context.picposCard` / `picposHairline`.\n'
          'وحِّد القيمةَ في فرع PicPos من `AppColors`، ولا تمسّ فرعَ '
          'UralCash.\n'
          'المخالفات:\n  ${mismatches.join('\n  ')}',
    );
  });
}
