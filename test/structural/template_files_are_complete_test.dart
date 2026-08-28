// كلُّ ملفِّ قالبٍ في الأصول يصله مسارُ استيراد.
//
// ── فئةُ العطب ────────────────────────────────────────────────────────────
// ملفٌّ يُكتب في `assets/invoice_templates/` ويُشحن مع التطبيق، ولا يُدرَج في
// قائمة «النماذج الجاهزة» ⇒ **لا يراه المالكُ قطّ**. لا رسالةَ خطأٍ ولا مدخلَ
// معطَّل — غيابٌ تامّ.
//
// وقد وقع فعلاً: كان في الـDAO **دالّتان بنفس الاسم**، إحداهما بثمانيةِ
// ملفّاتٍ والأخرى بأربعة والثانيةُ محجوبةٌ لا تُنادى. فمن تسعةَ عشرَ ملفاً
// بقي أحدَ عشرَ بلا مسار — وفيها كلُّ ما بُني المحرّكُ الجديدُ لأجله.
//
// والحارسُ يقيس **الطرفين**: لا ملفَّ بلا مدخل، ولا مدخلَ بلا ملفّ. فالأوّلُ
// يُخفي عملاً مشحوناً، والثاني يعرض على المالك خياراً ينهار عند الضغط.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

const _dir = 'assets/invoice_templates';

List<String> _assetFiles() => (Directory(_dir)
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((n) => n.endsWith('.json'))
        .toList())
  ..sort();

void main() {
  test('كلُّ ملفٍّ في الأصول له مدخلٌ في قائمة النماذج الجاهزة', () {
    final onDisk = _assetFiles().toSet();
    final listed = kReadyTemplateFiles.map((e) => e['file']!).toSet();

    final missing = onDisk.difference(listed).toList()..sort();
    expect(missing, isEmpty,
        reason: 'هذه الملفّاتُ مشحونةٌ ولا يصلها مسارُ استيراد — لا يراها '
            'المالكُ قطّ:\n  ${missing.join('\n  ')}');
  });

  test('ولا مدخلَ يشير إلى ملفٍّ غيرِ موجود', () {
    final onDisk = _assetFiles().toSet();
    final listed = kReadyTemplateFiles.map((e) => e['file']!).toSet();

    final ghosts = listed.difference(onDisk).toList()..sort();
    expect(ghosts, isEmpty,
        reason: 'خيارٌ يُعرض على المالك وينهار عند الضغط:\n'
            '  ${ghosts.join('\n  ')}');
  });

  test('واسمُ المدخل ونوعُه يطابقان ما في الملفّ', () {
    // الاسمُ في القائمةِ يُعرض **قبل** فتح الملفّ، فانحرافُه يعني أن
    // المالكَ يختار «فاتورة مشتريات» فيُفتح له كشفُ حساب. ولا يمسكه إلّا
    // مقارنةٌ بالمصدر.
    final drift = <String>[];
    for (final e in kReadyTemplateFiles) {
      final f = File('$_dir/${e['file']}');
      if (!f.existsSync()) continue;
      final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;

      final name = json['name'] as String?;
      if (name != null && name != e['name']) {
        drift.add('${e['file']}: الاسم «${e['name']}» ≠ «$name»');
      }
      final type = json['type'] as String?;
      if (type != null && type != e['type']) {
        drift.add('${e['file']}: النوع «${e['type']}» ≠ «$type»');
      }
    }
    expect(drift, isEmpty, reason: drift.join('\n'));
  });

  group('ضابط: الحارسُ يمسك ما يدّعي', () {
    test('يقرأ ملفّاتٍ فعلاً ومدخلاتٍ فعلاً', () {
      // بلا هذا يمرّ كلُّ ما فوقه على مجموعتين فارغتين.
      expect(_assetFiles().length, greaterThanOrEqualTo(19),
          reason: 'عددُ ملفّات الأصول انهار — الحارسُ يقيس فراغاً');
      expect(kReadyTemplateFiles.length, greaterThanOrEqualTo(19),
          reason: 'القائمةُ انكمشت — والفرقُ هو عينُ ما يحرسه هذا الملفّ');
    });

    test('كلُّ مدخلٍ يحمل المفاتيحَ الثلاثة', () {
      for (final e in kReadyTemplateFiles) {
        expect(e['file'], isNotNull, reason: 'مدخلٌ بلا ملفّ: $e');
        expect(e['name'], isNotNull, reason: 'مدخلٌ بلا اسم: $e');
        expect(e['type'], isNotNull, reason: 'مدخلٌ بلا نوع: $e');
      }
    });

    test('لا ملفَّ مكرَّرٌ في القائمة', () {
      final files = kReadyTemplateFiles.map((e) => e['file']!).toList();
      expect(files.toSet().length, files.length,
          reason: 'ملفٌّ مذكورٌ مرّتين — يُعرض خياران متطابقان');
    });
  });
}
