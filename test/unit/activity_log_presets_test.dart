// نطاقاتُ تقارير السجلّ — `ActivityLogPresets`.
//
// ═══ ما يحمي هذا الملفّ ═══
//
// مركزُ التقارير يفتح `ActivityLogPicposScreen` بقائمةِ أفعالٍ ثابتة. وهي
// أسهلُ ما يموت بصمت:
//
//  ‏١) مفتاحٌ بلا تسميةٍ في `actionLabels` ⇒ صفوفٌ بلا اسمٍ مقروء.
//  ‏٢) مفتاحٌ **لا يكتبه التطبيقُ في أيّ موضع** ⇒ استعلامٌ يعود فارغاً
//     دائماً، فيبدو التقريرُ مغطّياً وهو لا يغطّي. وقعت ثلاثةُ مفاتيحَ في
//     هذا بالضبط (`print_report` · `print_return` · `update_payment`)
//     فاستُبعدت — وهذا الفحصُ يمنع عودتَها.
//  ‏٣) قائمةٌ فارغةٌ ⇒ `presetActions` يسقط إلى فرع «بلا ترشيح» في
//     `loadLogs`، فيفتح التقريرُ السجلَّ كاملاً بلا أن يشتكيَ أحد.
//
// والقياسُ من المصدر لا من نسخةٍ ثانيةٍ للقائمة: لو كُتبت التوقّعاتُ هنا
// يدويّاً لصارتا نسختَين تنحرفان.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/presentation/activity_log_picpos/screens/activity_log_picpos_screen.dart';

const _screen =
    'lib/presentation/activity_log_picpos/screens/activity_log_picpos_screen.dart';

/// كلُّ مفاتيح `actionLabels` مقروءةً من الشاشة نفسِها.
Set<String> _actionLabelKeys() {
  final src = File(_screen).readAsStringSync();
  final start = src.indexOf('final Map<String, String> actionLabels = {');
  if (start < 0) {
    throw StateError('لم يُعثر على actionLabels في $_screen');
  }
  final end = src.indexOf('\n  };', start);
  if (end < 0) throw StateError('لم تُغلَق actionLabels في $_screen');
  return RegExp("'([a-z0-9_]+)':\\s*'")
      .allMatches(src.substring(start, end))
      .map((m) => m.group(1)!)
      .toSet();
}

/// عددُ المواضع التي **تكتب** الفعلَ سجلّاً — أي `action: '<key>'` في `lib`
/// خارجَ ملفَّي شاشتَي السجلّ (‏فهما خرائطُ تسمياتٍ لا كتابة).
int _writeSites(String action) {
  var n = 0;
  for (final f in Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))) {
    final p = f.path.replaceAll('\\', '/');
    if (p.contains('activity_log_picpos_screen.dart') ||
        p.contains('screens/activity_log_screen.dart')) {
      continue;
    }
    // الشرطةُ مضاعفةٌ عمداً — واحدةٌ في نصٍّ عاديٍّ تجعل الحرفَ عاديّاً
    // فيقرأ الفحصُ صفراً ويمرّ كاذباً. أمسكته المرساةُ أدناه.
    n += RegExp("action:\\s*'$action'").allMatches(f.readAsStringSync()).length;
  }
  return n;
}

void main() {
  final presets = <String, List<String>>{
    'voided': ActivityLogPresets.voided,
    'printed': ActivityLogPresets.printed,
    'documentEdits': ActivityLogPresets.documentEdits,
  };

  test('القوائمُ الثلاثُ غيرُ فارغة', () {
    // فارغةٌ = التقريرُ يفتح السجلَّ كاملاً بلا ترشيح.
    for (final e in presets.entries) {
      expect(e.value, isNotEmpty, reason: 'النطاق ${e.key} فارغ');
    }
  });

  test('كلُّ مفتاحٍ له تسميةٌ في actionLabels', () {
    final labels = _actionLabelKeys();
    // مرساة: لو انكسر النمطُ لقرأ صفراً ومرّ الفحصُ كاذباً.
    expect(labels.length, greaterThan(50),
        reason: 'قراءةُ actionLabels فشلت — النمطُ غلط');
    for (final e in presets.entries) {
      for (final key in e.value) {
        expect(labels, contains(key),
            reason: '${e.key}: «$key» بلا تسميةٍ في actionLabels');
      }
    }
  });

  test('كلُّ مفتاحٍ يكتبه التطبيقُ فعلاً في موضعٍ واحدٍ على الأقلّ', () {
    // مرساة: فعلٌ معروفُ الكتابة — لو قرأ صفراً فالبحثُ نفسُه معطوب.
    expect(_writeSites('table_partial_transfer'), greaterThan(0),
        reason: 'مرساةُ البحث سقطت — النمطُ أو المسارُ غلط');
    for (final e in presets.entries) {
      for (final key in e.value) {
        expect(_writeSites(key), greaterThan(0),
            reason: '${e.key}: «$key» تسميةٌ بلا كاتب — تقريرٌ يعود فارغاً');
      }
    }
  });

  test('المفاتيحُ الميّتةُ الثلاثةُ لا تعود', () {
    for (final dead in ['print_report', 'print_return', 'update_payment']) {
      for (final e in presets.entries) {
        expect(e.value, isNot(contains(dead)),
            reason: '${e.key}: «$dead» لا يكتبه التطبيق');
      }
    }
  });
}
