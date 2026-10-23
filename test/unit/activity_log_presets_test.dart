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
//     هذا بالضبط؛ اثنان منها (`print_report` · `print_return`) صارا حيَّين
//     ببناء تسجيل الطباعة (أمرُ المالك 2026-08-26)، وبقي `update_payment`
//     تسميةً موروثةً بلا كاتب — وهذا الفحصُ يمنع إدراجَه.
//  ‏٣) قائمةٌ فارغةٌ ⇒ `presetActions` يسقط إلى فرع «بلا ترشيح» في
//     `loadLogs`، فيفتح التقريرُ السجلَّ كاملاً بلا أن يشتكيَ أحد.
//
// ═══ لماذا «ملفٌّ كاتب» لا «سطرُ `action:` حرفيّ» ═══
//
// كان الفحصُ يبحث عن `action: '<key>'` حرفيّاً. وطباعةُ الإيصال تختار
// مفتاحَها بحسب نوع المستند (`isReturn ? 'print_return' : 'print_invoice'`)،
// فالمفتاحان يوجدان في الكود ولا يوجدان بذلك النمط — أي أنّ الفحصَ كان
// سيحكم عليهما بالموت **وهما حيّان**. فالمعيارُ صار: المفتاحُ يظهر نصّاً في
// ملفٍّ **ينادي `logActivity(`** فعلاً. وهذا يستبعد ملفّاتِ العرض التي تحمل
// المفتاحَ في `switch` للتسمية ولا تكتب شيئاً — وقد قِيس أنّ
// `activity_timeline.dart` منها.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/presentation/activity_log_picpos/screens/activity_log_picpos_screen.dart';

const _screen =
    'lib/presentation/activity_log_picpos/screens/activity_log_picpos_screen.dart';

/// خرائطُ التسميات — تحمل كلَّ مفتاحٍ ولا تكتب شيئاً، فتُستثنى من عدّ الكتّاب.
bool _isLabelMap(String path) {
  final p = path.replaceAll('\\', '/');
  return p.contains('activity_log_picpos_screen.dart') ||
      p.contains('screens/activity_log_screen.dart');
}

List<File> _libDartFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

/// كلُّ مفاتيح `actionLabels` مقروءةً من الشاشة نفسِها.
Set<String> _actionLabelKeys() {
  final src = File(_screen).readAsStringSync();
  final start = src.indexOf('final Map<String, String> actionLabels = {');
  if (start < 0) {
    throw StateError('لم يُعثر على actionLabels في $_screen');
  }
  final end = src.indexOf('\n  };', start);
  if (end < 0) throw StateError('لم تُغلَق actionLabels في $_screen');
  return RegExp("'([a-z0-9_]+)':\\s*(?:tr\\(\\s*)?'")
      .allMatches(src.substring(start, end))
      .map((m) => m.group(1)!)
      .toSet();
}

/// عددُ الملفّات التي تكتب هذا الفعلَ سجلّاً — بأيٍّ من صورتَين:
///
///  ‏١) `action: '<key>'` حرفيّاً — أوضحُها وأكثرُها شيوعاً.
///  ‏٢) المفتاحُ نصّاً في ملفٍّ ينادي `logActivity(` — يلتقط ما يُبنى في
///     متغيّرٍ (‏`isReturn ? 'print_return' : 'print_invoice'`).
///
/// والاتّحادُ ضروريٌّ لا احتياطيّ: النمطُ الأوّلُ وحدَه يُميت مفتاحَي
/// الطباعة الحيَّين، والثاني وحدَه يفوته مرفقُ `services/logging` الذي
/// يمرّر الفعلَ إلى دالّةٍ اسمُها `log` لا `logActivity`.
int _writerFiles(String action) {
  var n = 0;
  for (final f in _libDartFiles()) {
    if (_isLabelMap(f.path)) continue;
    final src = f.readAsStringSync();
    final literal = src.contains("action: '$action'");
    final viaLogger = src.contains("'$action'") && src.contains('logActivity(');
    if (literal || viaLogger) n++;
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

  test('كلُّ مفتاحٍ يكتبه التطبيقُ فعلاً في ملفٍّ واحدٍ على الأقلّ', () {
    // مرساةٌ مزدوجة: فعلٌ معروفُ الكتابة لا بدّ أن يُقرأ، وملفُّ عرضٍ معروفٌ
    // لا بدّ ألّا يُعَدَّ كاتباً — وإلّا صار الفحصُ يمرّ على كلّ شيء.
    expect(_writerFiles('table_partial_transfer'), greaterThan(0),
        reason: 'مرساةُ البحث سقطت — النمطُ أو المسارُ غلط');
    expect(
        File('lib/presentation/widgets/activity_timeline.dart')
            .readAsStringSync()
            .contains('logActivity('),
        isFalse,
        reason: 'ملفُّ العرض صار يكتب — معيارُ «الكاتب» لم يعد مميِّزاً');

    for (final e in presets.entries) {
      for (final key in e.value) {
        expect(_writerFiles(key), greaterThan(0),
            reason: '${e.key}: «$key» تسميةٌ بلا كاتب — تقريرٌ يعود فارغاً');
      }
    }
  });

  test('«update_payment» تسميةٌ بلا كاتبٍ فلا تدخل نطاقاً', () {
    // بقيت وحدَها بعد أن بُني تسجيلُ الطباعة. ولو كُتبت يوماً فهذا الفحصُ
    // هو الذي يُسقط ويقول: أدخِلها في `documentEdits`.
    expect(_writerFiles('update_payment'), 0,
        reason: 'صار لها كاتبٌ — أضِفها إلى ActivityLogPresets.documentEdits');
    for (final e in presets.entries) {
      expect(e.value, isNot(contains('update_payment')),
          reason: '${e.key}: «update_payment» لا يكتبه التطبيق');
    }
  });

  test('طباعةُ الفواتير والتقارير صارت مسجَّلةً — الفجوةُ سُدّت', () {
    // الحارسُ العكسيّ لأمر المالك 2026-08-26: لو حُذف تسجيلُ الطباعة يوماً
    // عاد «سجل الطباعة» يعرض فاتورةَ الطاولة وباركودَ العرض وحدَهما، ولا
    // يحمرّ شيءٌ آخر.
    for (final key in const [
      'print_invoice',
      'print_return',
      'print_purchase_invoice',
      'print_report',
    ]) {
      expect(ActivityLogPresets.printed, contains(key));
      expect(_writerFiles(key), greaterThan(0),
          reason: 'كاتبُ «$key» اختفى — تسجيلُ الطباعة انحسر');
    }
  });
}
