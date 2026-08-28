// كلُّ منادٍ للطباعة يمرّر نوعَ المستند — وإلّا فسلسلةُ الرابطات ميّتة.
//
// ── فئةُ العطب ────────────────────────────────────────────────────────────
// `printWithTemplate` تستشير `TemplateBindings` **فقط حين يصلها**
// `documentType`. والوسيطُ اختياريٌّ، فمنادٍ يتركه `null` يسقط فوراً إلى
// `isDefault` القديم — ولا يقول شيئاً.
//
// وهذا وقع فعلاً: وُصلت السلسلةُ بالخدمة، ثمّ أظهر القياسُ أنّ **صفراً** من
// المنادين الستّة يمرّرها. فزرُّ «تفعيل كافتراضي» في المكتبة يكتب رابطةً لا
// تصل ورقةً أبداً، والخطوتان ٦ و٧ من فحص القبول مستحيلتان بنيويّاً.
//
// ── ولماذا حارسٌ بنيويٌّ لا سلوكيّ ────────────────────────────────────────
// الاختبارُ السلوكيُّ يقيس منادياً واحداً استدعيناه نحن. وفئةُ العطب هنا
// «منادٍ **جديد** يُكتب غداً وينسى الوسيط» — ولا يمسكها إلّا فحصُ المصدر:
// كلُّ موضعِ نداءٍ يجب أن يحمل الوسيط، بلا استثناء.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// الملفّاتُ التي تنادي الطباعةَ بقالب.
const _callerFiles = <String>[
  'lib/services/invoice_generator.dart',
  'lib/services/printing_service.dart',
  'lib/services/printing/shift_closing_print.dart',
];

/// أنواعُ المستندات المعترَفُ بها — نسخةُ `TemplateResolver.documentTypes`.
///
/// ⚠️ ومطابقتُها تُفحص أدناه: نسخةٌ تنحرف عن أصلها تجعل الحارسَ يبارك
/// نوعاً لا تعرفه السلسلةُ فيسقط الحسمُ صامتاً.
const _knownTypes = <String>{
  'sales_invoice',
  'sales_return',
  'purchase_invoice',
  'purchase_return',
  'sales_receipt',
  'quotation',
  'kitchen_order',
  'shift_closing',
  'party_statement',
  'report',
};

void main() {
  test('كلُّ نداءٍ لـ`printWithTemplate` يمرّر `documentType`', () {
    final missing = <String>[];

    for (final path in _callerFiles) {
      final src = File(path).readAsStringSync();
      final lines = src.split('\n');

      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains('printWithTemplate(')) continue;

        // جسدُ النداء حتى قوسِ إغلاقه — نافذةٌ سخيّةٌ تسع أطولَ نداءٍ قائم.
        final end = (i + 60).clamp(0, lines.length);
        final body = lines.sublist(i, end).join('\n');
        final close = body.indexOf('\n      );');
        final call = close < 0 ? body : body.substring(0, close);

        if (!call.contains('documentType:')) {
          missing.add('$path:${i + 1}');
        }
      }
    }

    expect(missing, isEmpty,
        reason: 'هذه النداءاتُ لا تمرّر نوعَ المستند، فتتخطّى سلسلةَ '
            'الرابطات وتسقط إلى `isDefault`:\n  ${missing.join('\n  ')}');
  });

  test('وكلُّ نوعٍ مُمرَّرٍ تعرفه السلسلة', () {
    // نوعٌ مكتوبٌ بخطأٍ مطبعيٍّ يمرّ من الحارس الأوّل ويسقط الحسمَ صامتاً.
    final unknown = <String>[];
    final re = RegExp(r"documentType:\s*'([a-z_]+)'");

    for (final path in _callerFiles) {
      for (final m in re.allMatches(File(path).readAsStringSync())) {
        final t = m.group(1)!;
        if (!_knownTypes.contains(t)) unknown.add('$path → $t');
      }
    }

    expect(unknown, isEmpty, reason: 'أنواعٌ لا تعرفها السلسلة:\n'
        '  ${unknown.join('\n  ')}');
  });

  group('ضابط: الحارسُ يمسك ما يدّعي', () {
    test('يرى نداءاتٍ فعلاً — لا صفراً', () {
      // بلا هذا يمرّ الفحصُ الأوّلُ على مجموعةٍ فارغة: تغييرُ اسم الدالّة
      // أو نقلُ الملفّ يجعله أخضرَ وهو أعمى.
      var calls = 0;
      for (final path in _callerFiles) {
        expect(File(path).existsSync(), isTrue, reason: 'مسارٌ بائت: $path');
        calls += File(path)
            .readAsStringSync()
            .split('printWithTemplate(')
            .length -
            1;
      }
      expect(calls, greaterThanOrEqualTo(6),
          reason: 'عددُ النداءات المرصودة $calls — كانت ستّةً عند الكتابة');
    });

    test('وقائمةُ الأنواع تطابق أصلَها في `TemplateResolver`', () {
      final src =
          File('lib/services/printing/template_resolver.dart').readAsStringSync();
      final block = RegExp(r'documentTypes = <String>\[(.*?)\]', dotAll: true)
          .firstMatch(src);
      expect(block, isNotNull, reason: 'لم يعد للأنواع قائمةٌ في مصدرها');

      final fromSource = RegExp(r"'([a-z_]+)'")
          .allMatches(block!.group(1)!)
          .map((m) => m.group(1)!)
          .toSet();

      expect(fromSource, _knownTypes,
          reason: 'نسخةُ الأنواع هنا انحرفت عن أصلها — فيبارك الحارسُ نوعاً '
              'لا تعرفه السلسلة، أو يرفض نوعاً صار مشروعاً');
    });
  });
}
