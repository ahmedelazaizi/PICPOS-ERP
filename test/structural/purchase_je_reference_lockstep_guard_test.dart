// حارسُ العقد: **قائمةٌ واحدةٌ** لأنواع مرجع قيدِ فاتورة المشتريات.
//
// ═══ فئةُ العطب ═══
//
// لقيدِ فاتورة المشتريات **اسمان**، يكتبهما مصدران مختلفان لنفس المستند:
//   • `createPurchaseInvoice` (المسارُ المُدمَج) يختم `'purchase_invoice'`.
//   • `autoPostPurchase` (الترحيلُ الآليّ) يختم `'purchase'`.
//
// وله **ثلاثةُ قُرّاء**: عكسُ القيد عند التعديل، وعكسُه عند الإلغاء، وعمودُ
// «حالة الترحيل» في شاشة الاستعلام. وأيُّ قارئٍ يفحص اسماً واحداً يقرأ
// نصفَ الفواتير خطأً — و«نصفٌ» هنا ليست مبالغةً بل قسمةُ المسارَين.
//
// 🔴 **وهذه عينُ عائلةِ العطب التي وقعت فعلاً** في تصنيف تدفّقات الأصول
// (‏`ias7_reference_type_lockstep_guard_test.dart`): طرفٌ يكتب وطرفٌ يقرأ
// ولا يعرف أحدُهما الآخر، فانحرفا وبقيت كلُّ الحسابات متّزنةً والفصلُ
// مكسوراً — ولم يمسكه فحصُ اتّزانٍ واحد.
//
// ⚠️ **ولا يُقاس بوجود الرمز** بل بغياب النمط: مُرشِّحٌ يكتب اللفظَ بيده
// (`referenceType.equals('purchase')`) هو بعينه ما يُمنَع، ولو كان بجواره
// نداءٌ للقائمة.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _listPath = 'lib/data/database/database.dart';

String _code(String raw) => [
      for (final line in raw.split('\n'))
        if (!line.trimLeft().startsWith('//')) line,
    ].join('\n');

List<({String path, String code})> _libSources() => [
      for (final f in Directory('lib').listSync(recursive: true))
        if (f is File && f.path.endsWith('.dart'))
          (
            path: f.path.replaceAll(r'\', '/'),
            code: _code(f.readAsStringSync()),
          ),
    ];

void main() {
  test('مرساةٌ — القائمةُ موجودةٌ وتحمل الاسمَين معاً', () {
    final src = File(_listPath).readAsStringSync();
    final at = src.indexOf('const Set<String> kPurchaseJeReferenceTypes = {');
    expect(at, greaterThan(0), reason: 'القائمةُ اختفت — فلا لُحمةَ تُحرَس');
    final body = src.substring(at, src.indexOf('};', at));
    for (final t in const ['purchase_invoice', 'purchase']) {
      expect(body.contains("'$t'"), isTrue,
          reason: 'الاسمُ `$t` سقط من القائمة — والمسارُ الذي يكتبه '
              'يصير غيرَ مقروءٍ من كلّ القُرّاء الثلاثة');
    }
  });

  test('ومن يكتب اسماً يجده في القائمة', () {
    // ⚠️ **يُشتقُّ ما يُكتَب من الشجرة لا من قائمةٍ أنسخُها وتشيخ.** كلُّ
    // `referenceType: '<x>'` يرافق `referenceId` فاتورةَ شراءٍ يجب أن يكون
    // عضواً — وإلّا كُتب نوعٌ لا يقرؤه أحد.
    final src = File(_listPath).readAsStringSync();
    final at = src.indexOf('const Set<String> kPurchaseJeReferenceTypes = {');
    final listed = RegExp(r"'([a-z_]+)'")
        .allMatches(src.substring(at, src.indexOf('};', at)))
        .map((m) => m.group(1)!)
        .toSet();

    // الكاتبان المعروفان — بمواضعهما، فنقلُ أحدِهما يُسقط المرساة.
    const writers = <String, String>{
      'lib/data/database/daos/purchase_dao.dart': 'purchase_invoice',
      'lib/data/database/daos/accounting_autopost_dao.dart': 'purchase',
    };
    for (final MapEntry(key: path, value: type) in writers.entries) {
      final code = _code(File(path).readAsStringSync());
      expect(code.contains("referenceType: '$type'"), isTrue,
          reason: 'الكاتبُ $path ما عاد يختم `$type` — '
              'راجع الخريطةَ هنا قبل أن تُصدّق الأخضر');
      expect(listed.contains(type), isTrue,
          reason: '`$type` يُكتَب في $path وليس في القائمة');
    }
  });

  test('ولا قارئَ يكتب اللفظَ بيده', () {
    // ⚠️ **والنمطُ الأوّلُ أمسك مطابقتَين كاذبتَين** — قِسْ قبل أن تُصلح:
    // `safeTransactions.referenceType.equals('purchase_invoice')` و
    // `stockMovements.referenceType.equals('purchase')`. الجدولان لهما
    // مفرداتُهما الخاصّةُ لأنواع المرجع، ولا شأنَ لهما بقيدِ الأستاذ —
    // ولو «أصلحتُهما» لكسرتُ عكسَ الخزينة وحارسَ التكرار في المزامنة.
    //
    // فالنمطُ يمشي **إلى الوراء** من كلّ مطابقةٍ إلى أقرب `select(` أو
    // `selectOnly(` ويقرأ الجدولَ المسمَّى فيه: ما لم يكن `journalEntries`
    // فليست هذه المطابقةُ لنا.
    final offenders = <String>[];
    final bad = RegExp(
      r"referenceType\s*\.?\s*equals\(\s*'purchase(_invoice)?'\s*\)",
    );
    final selector = RegExp(r'select(?:Only)?\(\s*(?:db\.)?(\w+)');
    for (final s in _libSources()) {
      for (final m in bad.allMatches(s.code)) {
        final before = s.code.substring(0, m.start);
        final owner = selector.allMatches(before).lastOrNull?.group(1);
        if (owner == 'journalEntries') offenders.add('${s.path}:$owner');
      }
    }
    expect(offenders, isEmpty,
        reason: 'مُرشِّحٌ على قيدٍ يكتب اسمَ المرجع بيده بدل '
            '`kPurchaseJeReferenceTypes`: ${offenders.join(", ")}. '
            'وهو يقرأ نصفَ الفواتير: `createPurchaseInvoice` يختم '
            '`purchase_invoice` و`autoPostPurchase` يختم `purchase`.');
  });

  test('ومرساةُ النمط — يمسك مُرشِّحاً مكتوباً بيده لو عاد', () {
    // بلا هذه المرساة يمرّ الحارسُ أخضرَ لأنّ نمطَه صار لا يطابق شيئاً
    // إطلاقاً، لا لأنّ المستودعَ نظيف.
    const planted = '''
      final x = await (select(journalEntries)
            ..where((e) => e.referenceType.equals('purchase_invoice')))
          .get();
    ''';
    final bad = RegExp(
      r"referenceType\s*\.?\s*equals\(\s*'purchase(_invoice)?'\s*\)",
    );
    final selector = RegExp(r'select(?:Only)?\(\s*(?:db\.)?(\w+)');
    final m = bad.firstMatch(planted);
    expect(m, isNotNull, reason: 'النمطُ ما عاد يطابق مُرشِّحاً صريحاً');
    final owner = selector
        .allMatches(planted.substring(0, m!.start))
        .lastOrNull
        ?.group(1);
    expect(owner, 'journalEntries',
        reason: 'مُحدِّدُ الجدول ما عاد يُرجِع مالكَ المُرشِّح');
  });

  test('والقُرّاءُ الثلاثةُ يقرؤونها فعلاً', () {
    final dao = _code(
      File('lib/data/database/daos/purchase_dao.dart').readAsStringSync(),
    );
    final uses = RegExp('kPurchaseJeReferenceTypes').allMatches(dao).length;
    expect(uses, greaterThanOrEqualTo(3),
        reason: 'وُجد $uses نداءً فقط — عكسُ التعديل وعكسُ الإلغاء وقارئُ '
            'حالة الترحيل ثلاثةٌ، فأحدُها عاد يكتب لفظَه بيده أو حُذف');
  });
}
