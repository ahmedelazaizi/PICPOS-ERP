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
import '../helpers/library_source.dart';
import 'package:ural_erp/services/printing/template_resolver.dart';

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

/// كلُّ نوعٍ يمرّره منادٍ، مقروءاً من المصدر.
///
/// ⚠️ **لا يكفي `documentType:\s*'…'`**: أحدُ المنادين يمرّر تعبيراً شرطيّاً
/// على سطرين — `documentType:\n  isReturn ? 'purchase_return' :
/// 'purchase_invoice',` — فالنمطُ المُلصَقُ بعلامة الاقتباس مباشرةً **لا يراه**،
/// ويسقط نوعان من القياس بلا أن يقول شيئاً. وهو عينُ «صفرُ المطابقات = نمطٌ
/// غلط»، إلّا أنّه هنا نقصٌ لا صفرٌ فيمرّ أهدأ.
///
/// فالقراءةُ على مرحلتين: قيمةُ الوسيط حتى فاصلته، ثمّ كلُّ نصٍّ حرفيٍّ فيها.
Set<String> _typesPassedIn(String src) {
  final out = <String>{};
  for (final m in RegExp(r'documentType:([^,]*),', dotAll: true)
      .allMatches(src)) {
    for (final lit in RegExp(r"'([a-z_]+)'").allMatches(m.group(1)!)) {
      out.add(lit.group(1)!);
    }
  }
  return out;
}

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

    for (final path in _callerFiles) {
      for (final t in _typesPassedIn(File(path).readAsStringSync())) {
        if (!_knownTypes.contains(t)) unknown.add('$path → $t');
      }
    }

    expect(unknown, isEmpty, reason: 'أنواعٌ لا تعرفها السلسلة:\n'
        '  ${unknown.join('\n  ')}');
  });

  test('و`wiredDocumentTypes` تطابق ما يمرّره المنادون فعلاً', () {
    // شاشةُ الحسم تقرأ هذا الثابتَ لتقول «محسومٌ وينتظر توصيلاً». وثابتٌ
    // يُحدَّث باليد يبيت: نوعٌ يُوصَل غداً تبقى الشاشةُ تصفه منتظِراً، ونوعٌ
    // يُفقد توصيلُه تبقى تصفه عاملاً. فيُشتقّ من المصدر لا من الذاكرة.
    final passed = <String>{};
    for (final path in _callerFiles) {
      passed.addAll(_typesPassedIn(File(path).readAsStringSync()));
    }

    // ضابطٌ على القارئ نفسِه: الشرطيُّ يمرّر نوعين من موضعٍ واحد، فحضورُهما
    // معاً هو الدليلُ أنّ القراءةَ تعبر السطر ولا تقف عند علامة الاقتباس.
    expect(passed, containsAll(['purchase_return', 'purchase_invoice']),
        reason: 'النوعان يُمرَّران بتعبيرٍ شرطيٍّ على سطرين — غيابُهما يعني '
            'أنّ القارئَ عاد يقف عند علامة الاقتباس');

    final src =
        File('lib/services/printing/template_resolver.dart').readAsStringSync();
    final block = RegExp(r'wiredDocumentTypes = <String>\{(.*?)\}', dotAll: true)
        .firstMatch(src);
    expect(block, isNotNull, reason: 'لم يعد للثابت وجودٌ في مصدره');

    final declared = RegExp(r"'([a-z_]+)'")
        .allMatches(block!.group(1)!)
        .map((m) => m.group(1)!)
        .toSet();

    expect(declared, passed,
        reason: 'ثابتُ الأنواع الموصولة انحرف عمّا يمرّره المنادون:\n'
            '  المعلَن: ${declared.toList()..sort()}\n'
            '  المرصود: ${passed.toList()..sort()}');
  });

  group('سياقُ كلِّ نوعٍ يطابق ما يسأل به منادِيه', () {
    // المستوى الخامسُ يُفهرَس بـ(النوع الورقيّ + الفئة). فشاشةُ الحسم تسأل
    // بنفس الزوج أو تعرض قالباً غيرَ الذي يخرج من الطابعة.
    late final String callerSrc = _callerFiles
        .map((p) => File(p).readAsStringSync())
        .join('\n');

    test('كلُّ نوعٍ معلَنٍ له سياق — بلا زيادةٍ ولا نقص', () {
      final src = File('lib/services/printing/template_resolver.dart')
          .readAsStringSync();
      final block = RegExp(r'documentTypes = <String>\[(.*?)\]', dotAll: true)
          .firstMatch(src)!;
      final declared = RegExp(r"'([a-z_]+)'")
          .allMatches(block.group(1)!)
          .map((m) => m.group(1)!)
          .toSet();

      final contexts = RegExp(
              r"documentContexts = <String, \(\{String type, String category\}\)>\{(.*?)\n  \};",
              dotAll: true)
          .firstMatch(src);
      expect(contexts, isNotNull, reason: 'لم يعد للسياقات وجودٌ في مصدرها');

      final keyed = RegExp(r"^\s*'([a-z_]+)':", multiLine: true)
          .allMatches(contexts!.group(1)!)
          .map((m) => m.group(1)!)
          .toSet();

      expect(keyed, declared,
          reason: 'نوعٌ بلا سياقٍ لا تستطيع الشاشةُ عرضَ مستواه الخامس، '
              'وسياقٌ بلا نوعٍ صفٌّ ميّت');
    });

    test('وفئةُ كلِّ نوعٍ موصولٍ مكتوبةٌ في ملفِّ منادِيه', () {
      // ⚠️ الفئةُ قد تُمرَّر متغيّراً (`category: category`) فلا تُقرأ من
      //    موضع النداء — لكنّ نصَّها الحرفيَّ يبقى في الملفّ حيث يُشتقّ.
      final missing = <String>[];
      for (final type in TemplateResolver.wiredDocumentTypes) {
        final ctx = TemplateResolver.documentContexts[type];
        expect(ctx, isNotNull, reason: 'نوعٌ موصولٌ بلا سياق: $type');
        if (!callerSrc.contains("'${ctx!.category}'")) {
          missing.add('$type → ${ctx.category}');
        }
      }
      expect(missing, isEmpty,
          reason: 'فئاتٌ يدّعيها السياقُ ولا أثرَ لها في المنادين:\n'
              '  ${missing.join('\n  ')}');
    });

    test('وافتراضيُّ `type` في `printWithTemplate` ما زال `thermal`', () {
      // `printing_service` لا تمرّر `type`، فسياقُ `sales_receipt` يعتمد على
      // هذا الافتراضيّ. تغييرُه يبدّل قالبَ الكاشير صامتاً.
      final src =
          readLibrarySource('lib/services/templated_invoice_service.dart');
      expect(src, contains("String type = 'thermal',"));
      expect(TemplateResolver.documentContexts['sales_receipt']!.type,
          'thermal');
    });
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
