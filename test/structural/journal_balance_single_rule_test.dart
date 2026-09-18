// حارسُ العقد: «هل يتّزن القيد؟» **سؤالٌ واحدٌ بجوابٍ واحد**.
//
// ═══ فئةُ العطب ═══
//
// كان الجوابُ مكتوباً بيده في **ستّة مواضع**، وبقيمتَين مختلفتَين:
//
//   ‏• شاشةُ اليومية (العرض)       `abs() < 0.005`  ← **الأشدّ**
//   ‏• حوارا الإنشاء وحوارُ القوالب وتقريرُ الميزان  `abs() < 0.01`
//
// وجانبُ **الكتابة** لا يكتبها: يقرأ `FinancialUtils.balanceTolerance`،
// وهي مُعلَنةٌ صراحةً «‏the ONE allowed debit-vs-credit tolerance» (‏Spec 139)
// ويقرؤها كاتبُ القيد ومصنعُه ومُصادِقُ المزامنة.
//
// 🔴 **فشاشةُ العرض أشدُّ من المُصادِق.** قيدٌ يصل بالمزامنة بفرق ٠٫٠٠٧
// يقبله `journal_sync_strategy` ويكتبه، ثمّ تعرضه الشاشةُ «غير متوازن» —
// والمستخدمُ لا يملك ما يصلحه به.
//
// ⚠️ **ولا تخترع القاعدةُ الجديدةُ سماحيّةً**: تقرأ القائمةَ حرفاً. وحارسٌ
// أدناه يمنع أن تصير هي المصدرَ الثاني.
//
// وقرارُ المالك 2026-09-18 يجعله مرئيّاً: «الفرق» **رقماً وشارةً معاً** —
// فالرقمُ والشارةُ يخرجان من حسابٍ واحدٍ أو يتناقضان على الشاشة نفسِها.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// نصُّ الملفّ بلا أسطر التعليق وبلا `\r` — أغلبُ الملفّات هنا CRLF.
String _code(String path) => [
      for (final line in File(path).readAsStringSync().split('\n'))
        if (!line.trimLeft().startsWith('//')) line.replaceAll('\r', ''),
    ].join('\n');

const _formulaPath = 'lib/domain/models/journal_balance.dart';

/// المواضعُ التي كانت تكتب القاعدةَ بيدها — بمساراتها، فنقلُ أحدها يُسقط
/// المرساةَ بدل أن يمرَّ صامتاً.
const _readers = <String>[
  'lib/presentation/accounting_picpos/journal_entries_picpos_screen.dart',
  'lib/presentation/accounting_picpos/journal_entries_picpos_create_dialog.dart',
  'lib/presentation/screens/journal_entry_create_dialog.dart',
  'lib/presentation/screens/create_journal_template_dialog.dart',
  'lib/data/database/daos/accounting_reports_dao.dart',
];

void main() {
  test('مرساةٌ — القاعدةُ موجودةٌ وتقرأ السماحيّةَ القائمة', () {
    final code = _code(_formulaPath);
    expect(code.contains('class JournalBalance'), isTrue,
        reason: 'القاعدةُ اختفت — فلا لُحمةَ تُحرَس');
    expect(code.contains('FinancialUtils.balanceTolerance'), isTrue,
        reason: 'القاعدةُ اخترعت سماحيّةً — فصارت المصدرَ الثاني بدل أن '
            'تُنهي الثاني');
    // 🔴 ولا رقمٌ مكتوبٌ فيها إطلاقاً.
    expect(RegExp(r'0\.0\d').hasMatch(code), isFalse,
        reason: 'رقمُ سماحيّةٍ مكتوبٌ في القاعدة نفسِها');
  });

  test('والقُرّاءُ الخمسةُ يقرؤونها فعلاً', () {
    for (final path in _readers) {
      expect(_code(path).contains('JournalBalance'), isTrue,
          reason: '$path لا يقرأ القاعدةَ — فهو يحسب بنفسه');
    }
  });

  test('🔴 ولا سماحيّةٌ مكتوبةٌ بيدها خارجَ القاعدة', () {
    // ⚠️ **النمطُ على العتبة المكتوبة رقماً** لا على المقارنة وحدَها:
    // `journal_entry_factory` و`journal_sync_strategy` يقيسان الفرقَ نفسَه
    // لكن **على `FinancialUtils.balanceTolerance`** — وهما القُدوة لا
    // المخالفة. فالمحظورُ رقمٌ يُكتَب في موضعه.
    final bad = RegExp(
      r'\(\s*\w*[Dd]ebit\w*\s*-\s*\w*[Cc]redit\w*\s*\)\.abs\(\)\s*[<>]=?\s*0*\.\d');
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final path = f.path.replaceAll(r'\', '/');
      if (path == _formulaPath) continue;
      if (bad.hasMatch(_code(f.path))) offenders.add(path);
    }
    expect(offenders, isEmpty,
        reason: 'سماحيّةٌ مكتوبةٌ بيدها خارجَ `JournalBalance`: '
            '${offenders.join(", ")}. وقيمتان مختلفتان تعنيان قيداً '
            'يقبله الإدخالُ ويرفضه العرض.');
  });

  test('🔴 ولا عتبةٌ رقميّةٌ على نتيجة القاعدة نفسِها', () {
    // 🔴 **وهذا الفحصُ وُلد من طفرةٍ نجت.** الفحصُ أعلاه يبحث عن شكلِ
    // `(debit - credit).abs() < 0.005`؛ فطفرةٌ كتبت `balance.magnitude < 0.005`
    // مرّت أمامَه خضراء — وهي عينُ العطب: الشاشةُ تستعمل القاعدةَ لتجمع
    // وتتجاهلها لتحكم.
    final bad = RegExp(
        r'\.(magnitude|difference)\s*[<>]=?\s*0*\.\d');
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final path = f.path.replaceAll(r'', '/');
      if (path == _formulaPath) continue;
      if (bad.hasMatch(_code(f.path))) offenders.add(path);
    }
    expect(offenders, isEmpty,
        reason: 'حكمٌ على الاتّزان بعتبةٍ مكتوبةٍ بدل `isBalanced`: '
            '${offenders.join(", ")}');
  });

  test('ومرساةُ النمطَين — يمسكان النسخةَ اليدويّةَ لو عادت', () {
    // بلا هذه المرساة يمرّ الفحصُ أعلاه أخضرَ لأنّ نمطَه صار لا يطابق شيئاً
    // إطلاقاً، لا لأنّ المستودعَ نظيف.
    const planted = 'final ok = (totalDebit - totalCredit).abs() < 0.01;';
    final bad = RegExp(
      r'\(\s*\w*[Dd]ebit\w*\s*-\s*\w*[Cc]redit\w*\s*\)\.abs\(\)\s*[<>]=?\s*0*\.\d');
    expect(bad.hasMatch(planted), isTrue,
        reason: 'النمطُ ما عاد يطابق السماحيّةَ اليدويّةَ نفسَها');

    const planted2 = 'final ok = balance.magnitude < 0.005;';
    final bad2 = RegExp(r'\.(magnitude|difference)\s*[<>]=?\s*0*\.\d');
    expect(bad2.hasMatch(planted2), isTrue,
        reason: 'نمطُ العتبة على نتيجة القاعدة ما عاد يطابق نفسَه');
  });

  test('وجانبُ الكتابة يقرأ القائمةَ كما كان — لم يتغيّر', () {
    // مرساةٌ على المصدر الأصليّ: لو نُقلت أو أُعيدت تسميتُها سقط هذا قبل أن
    // تصمت القاعدةُ الجديدةُ على قيمةٍ أخرى.
    expect(
      _code('lib/core/utils/financial_utils.dart')
          .contains('static const double balanceTolerance = 0.01'),
      isTrue,
      reason: 'سماحيّةُ النظام تغيّرت — وهي عقدٌ مع محرّك الترحيل لا تفصيلُ '
          'عرض',
    );
    expect(
      _code('lib/services/sync/strategies/journal_sync_strategy.dart')
          .contains('FinancialUtils.balanceTolerance'),
      isTrue,
      reason: 'مُصادِقُ المزامنة ما عاد يقرأ القائمة',
    );
  });
}
