// كلُّ منادٍ لـ`saveReceiptSettings` يمرّر `logoImage:` صراحةً.
//
// ═══ 🔴 لماذا حارسٌ بنيويٌّ لا اختبارُ سلوك ═══
//
// أُصلح في 2026-09-20 عقدُ `logoImage`: صار `null` يعني **«امسح»** لا «لا
// تمسّ» — لأنّ مُنادِيَها الثلاثةَ يقرؤون الحالةَ القائمةَ ثمّ يحفظون
// الاستمارةَ كاملةً، فلا أحدَ منهم يحتاج «لا تمسّ» أصلاً.
//
// **وثمنُ ذلك مقيسٌ ومقصود**: منادٍ **جديدٌ** يحفظ حقلاً واحداً (اسمَ
// المنشأة مثلاً) ويُسقط `logoImage:` **يمحو شعارَ المنشأة** — بلا رسالةٍ
// ولا استثناء. ولا يُسقط ذلك اختبارَ سلوكٍ واحداً: كلُّ اختبارٍ قائمٍ
// يمرّر الحقلَ، والمناداةُ الجديدةُ هي وحدَها الخطرة.
//
// فالحارسُ يقرأ المناداةَ نفسَها. وبديلُه الوحيدُ وسيطٌ ثانٍ (`clearLogo`)
// يُنتج مصدرَي حقيقةٍ يختلفان: `logoImage: bytes, clearLogo: true`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// نصُّ الملفّ بلا أسطر التعليق — فذكرُ الاسم في شرحٍ ليس مناداةً له.
String _code(String raw) => [
      for (final line in raw.split('\n'))
        if (!line.trimLeft().startsWith('//')) line,
    ].join('\n');

/// المناداةُ كاملةً من `saveReceiptSettings(` إلى قوسها المغلق، ومعها ما
/// يسبق الاسمَ — به وحدَه يُفرَّق التعريفُ عن المناداة.
List<({String args, String before})> _callsIn(String code) {
  const needle = 'saveReceiptSettings(';
  final out = <({String args, String before})>[];
  var at = code.indexOf(needle);
  while (at != -1) {
    final open = at + needle.length - 1;
    var depth = 0;
    for (var k = open; k < code.length; k++) {
      if (code[k] == '(') depth++;
      if (code[k] == ')') {
        depth--;
        if (depth == 0) {
          out.add((
            args: code.substring(open, k + 1),
            before: code.substring(at < 40 ? 0 : at - 40, at),
          ));
          break;
        }
      }
    }
    at = code.indexOf(needle, at + needle.length);
  }
  return out;
}

/// تعريفٌ لا مناداة — **يُعرَف بنوعِ الإرجاع الذي يسبق الاسمَ** لا بقائمةٍ
/// يدويّةٍ من أشكال الوسائط.
///
/// ⚠️ وأوّلُ صياغةٍ لهذا الحارس عدّت الشكلَ يدويّاً فأبلغت عن تعريف
///    `SettingsController.saveReceiptSettings(Map<String, dynamic>)` على
///    أنّه مناداةٌ مخالفة — بلاغٌ كاذبٌ يُفقد الحارسَ ثقتَه.
bool _isDeclaration(({String args, String before}) hit) {
  final b = hit.before.trimRight();
  return b.endsWith('>') || b.endsWith('void') || b.endsWith('Future');
}

void main() {
  late List<({String path, String code})> sources;

  setUpAll(() {
    sources = [
      for (final f in Directory('lib').listSync(recursive: true))
        if (f is File &&
            f.path.endsWith('.dart') &&
            !f.path.endsWith('.g.dart'))
          (path: f.path.replaceAll(r'\', '/'), code: _code(f.readAsStringSync()))
    ];
  });

  test('مرساةٌ — شجرةُ المصدر قُرئت غيرَ فارغة', () {
    expect(sources.length, greaterThan(300));
  });

  test('مرساةٌ — الكاشفُ يجد المناداةَ المعروفة', () {
    // بلا هذه المرساة يمرّ الحارسُ أخضرَ لأنّ الكاشفَ عمي، لا لأنّ
    // المناداةَ سليمة.
    final hits = [
      for (final s in sources)
        if (s.path.contains('receipt_settings_widget') ||
            s.path.contains('company_info_widget') ||
            s.path.contains('settings_controller') ||
            s.path.contains('settings_repository_impl'))
          ..._callsIn(s.code).where((c) => !_isDeclaration(c)),
    ];
    expect(hits, isNotEmpty,
        reason: 'لم أجد مناداةً واحدةً — صيغةُ النداء تبدّلت فالحارسُ أعمى');
  });

  test('🔴 وكلُّ مناداةٍ تمرّر `logoImage:` — إسقاطُه يمحو الشعار', () {
    final offenders = <String>[];
    for (final s in sources) {
      if (s.path.endsWith('/daos/settings_dao.dart')) continue;
      for (final call in _callsIn(s.code)) {
        if (_isDeclaration(call)) continue;
        // مناداةٌ بخريطةٍ (`saveReceiptSettings({...})` في المتحكّم) تحمل
        // المفتاحَ نصّاً لا وسيطاً مُسمّى.
        final passes = call.args.contains('logoImage:') ||
            call.args.contains("'logoImage'");
        if (!passes) offenders.add('${s.path}: ${call.args}');
      }
    }
    expect(offenders, isEmpty,
        reason: 'مناداةٌ بلا `logoImage:` — و`null` الضمنيُّ صار يمحو:\n'
            '  ${offenders.join('\n  ')}');
  });

  test('والمحرّكُ يكتب الحقلَ في الفرعَين — لا في التحديث وحدَه', () {
    final dao = _code(
        File('lib/data/database/daos/settings_dao.dart').readAsStringSync());
    expect('logoImage: Value(logoImage)'.allMatches(dao).length, 2,
        reason: 'فرعُ الإدراج أو فرعُ التحديث فقد كتابتَه — '
            'والإدراجُ كان يُسقط الحقلَ إسقاطاً تامّاً قبل 2026-09-20');
    expect(dao.contains('logoImage != null'), isFalse,
        reason: 'عاد الشرطُ الذي يجعل الشعارَ غيرَ قابلٍ للمحو');
  });
}
