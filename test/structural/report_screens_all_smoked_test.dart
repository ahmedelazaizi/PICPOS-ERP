// ═══════════════════════════════════════════════════════════════════════════
// كلُّ شاشةِ تقريرٍ تُضاف لا بدّ أن تدخل حارسَ الدخان.
// ═══════════════════════════════════════════════════════════════════════════
//
// قائمةُ `reportScreens` يدويةٌ لأن Dart لا يعدّد الأصناف وقت التشغيل. وقائمةٌ
// يدويةٌ بلا حارسٍ **تتعفّن**: هذا بالضبط ما حدث لـ`scripts/gate.sh` حين بقيت
// ستُّ مجلدات اختبارٍ خارج البوابة أشهراً بلا أن يلاحظ أحد.
//
// فالحارسُ هنا يقرأ `lib/presentation/screens/reports/` ويفشل لأيّ شاشةٍ ذاتِ
// مُنشئٍ بلا معاملاتٍ مطلوبة ولا تُذكر في القائمة.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('كلُّ شاشةِ تقريرٍ قابلةٍ للإنشاء مذكورةٌ في حارس الدخان', () {
    final dir = Directory('lib/presentation/screens/reports');
    expect(dir.existsSync(), isTrue, reason: 'مجلدُ شاشات التقارير غير موجود');

    final smokeSrc =
        File('test/widget/reports_screens_smoke_test.dart').readAsStringSync();

    final missing = <String>[];
    for (final f in dir.listSync().whereType<File>()) {
      if (!f.path.endsWith('_screen.dart')) continue;
      final src = f.readAsStringSync();
      final m = RegExp(
              r'class (\w+) extends (?:Consumer)?(?:Stateful|Stateless)Widget')
          .firstMatch(src);
      if (m == null) continue;
      final cls = m.group(1)!;

      // شاشةٌ بمعاملاتٍ مطلوبة لا تُفتَح آلياً بلا تجهيزةٍ خاصة — تُستثنى.
      if (!RegExp('const $cls\\(\\{\\s*super\\.key\\s*\\}\\)').hasMatch(src)) {
        continue;
      }
      if (!smokeSrc.contains(cls)) missing.add(cls);
    }

    expect(missing, isEmpty,
        reason: 'شاشاتُ تقاريرَ خارج حارس الدخان — أضفها إلى '
            '`reportScreens` في `test/widget/reports_screens_smoke_test.dart`:\n'
            '${missing.join('\n')}');
  });
}
