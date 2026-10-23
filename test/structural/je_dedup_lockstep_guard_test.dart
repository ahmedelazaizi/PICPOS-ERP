// حارسُ العقد: إعفاءُ القيد المتعدّد يُكتَب مرّةً واحدةً — لا مرّتين.
//
// ═══ فئةُ العطب ═══
//
// منعُ ترحيلِ القيد التلقائيِّ مرّتين له **طبقتان**:
//
//   ‏١) حارسٌ برمجيٌّ في `createJournalEntry` يقرأ [kMultiJeReferenceTypes].
//   ‏٢) وفهرسٌ فريدٌ جزئيٌّ في القاعدة —
//      [kCreateJeAutopostDedupIndexSql] — يحمل نفسَ الاستثناءات في
//      `NOT IN (...)`.
//
// وكانتا قائمتَين منفصلتَين بنصٍّ مكرَّر، والوثيقةُ تقول «لا بدّ أن تبقيا
// متطابقتَين» — ولا شيءَ يفرض ذلك.
//
// 🔴 **ووقع فعلاً 2026-08-27:** أُضيف `asset_depreciation` إلى الحارس
// البرمجيِّ وحدَه. فصار القيدُ يمرّ الحارسَ ثمّ يصطدم بالفهرس:
// `UNIQUE constraint failed: journal_entries.reference_type,
// journal_entries.reference_id`. و`runMonthlyDepreciation` يلتقط الاستثناءَ
// **لكلِّ أصلٍ على حدة** ويتخطّاه، فتتراجع معاملةُ ذلك الأصل كاملةً: لا
// قيدَ ولا صفَّ إهلاكٍ ولا بطاقةً متقدّمة.
//
// أي أنّ نصفَ الإصلاح **أوقف** الإهلاكَ بدل أن يُنقصه — وهو أسوأُ من العطب
// الأصليّ. والأخطرُ أنّ مصالحةَ الأصول مرّت **خضراءَ** حينها: الطرفان
// تساويا (٢٠٠ = ٢٠٠) عند الرقم الخاطئ.
//
// ═══ لماذا حارسُ بنيةٍ لا اختبارُ سلوك ═══
//
// الفهرسُ يُنشَأ في ثلاثةِ مسارات (‏هجرةُ v150/v168 · `onCreate` للتنصيب
// الجديد · شفاءُ `ensureSchemaDefaults` كلَّ إقلاع). واختبارُ سلوكٍ على
// قاعدةٍ واحدةٍ لا يثبت أنّ **نصَّ** الفهرس يوافق الحارس؛ وهذا يثبته.

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

/// يستخرج قائمةَ `NOT IN ('a', 'b', …)` من نصِّ إنشاء الفهرس.
Set<String> _exemptionsInIndexSql(String sql) {
  final m = RegExp(r"NOT\s+IN\s*\(([^)]*)\)", caseSensitive: false)
      .firstMatch(sql);
  if (m == null) return <String>{};
  return RegExp(r"'([a-z_]+)'")
      .allMatches(m.group(1)!)
      .map((x) => x.group(1)!)
      .toSet();
}

void main() {
  group('مرساةُ الكشف — قبلَ أيِّ حكم', () {
    test('الاستخراجُ يعمل على نصٍّ مضبوط', () {
      // بلا هذه المرساةِ يمرّ الفحصُ الرئيسُ أخضرَ لو عاد الاستخراجُ فارغاً
      // **والحارسُ فارغٌ أيضاً** — أو لو تغيّر شكلُ الجملة فصار المستخرَجُ
      // لا شيء.
      const sample = "CREATE UNIQUE INDEX x ON t(a, b) WHERE p = 1 "
          "AND reference_type NOT IN ('alpha', 'beta_gamma')";
      expect(_exemptionsInIndexSql(sample), {'alpha', 'beta_gamma'});
    });

    test('ويعيد فارغاً حين لا NOT IN — لا يخترع', () {
      expect(_exemptionsInIndexSql('CREATE INDEX x ON t(a)'), isEmpty);
    });

    test('والحارسُ البرمجيُّ ليس فارغاً', () {
      // مجموعتان فارغتان متساويتان — ويمرّ الفحصُ الرئيسُ بلا معنى.
      expect(kMultiJeReferenceTypes, isNotEmpty);
      expect(_exemptionsInIndexSql(kCreateJeAutopostDedupIndexSql), isNotEmpty);
    });
  });

  test('🔴 الحارسُ البرمجيُّ والفهرسُ يحملان الاستثناءاتِ نفسَها', () {
    final inIndex = _exemptionsInIndexSql(kCreateJeAutopostDedupIndexSql);

    expect(
      inIndex,
      equals(kMultiJeReferenceTypes),
      reason: 'افترقت القائمتان.\n'
          '  في الحارس وليس في الفهرس: '
          '${kMultiJeReferenceTypes.difference(inIndex)}\n'
          '  في الفهرس وليس في الحارس: '
          '${inIndex.difference(kMultiJeReferenceTypes)}\n\n'
          'نوعٌ في الحارس وحدَه ⇒ القيدُ يمرّ ثمّ يصطدم بـ`UNIQUE '
          'constraint failed`، والمنادي يلتقط الاستثناءَ ويتخطّى — '
          'فيتوقّف الترحيلُ بدل أن يقع.\n'
          'ونوعٌ في الفهرس وحدَه ⇒ الحارسُ يبتلع القيدَ الثانيَ صامتاً '
          'ويعيد رقمَ القيد الأوّل، فيبدو الترحيلُ واقعاً وهو لم يقع.\n\n'
          'أضِفه في `kMultiJeReferenceTypes` **و**في '
          '`kCreateJeAutopostDedupIndexSql`، ومعهما هجرةٌ تُسقط الفهرسَ '
          'وتعيد إنشاءه — `CREATE ... IF NOT EXISTS` لا يبدّل شكلَ فهرسٍ '
          'قائم.',
    );
  });

  test('🔴 والإهلاكُ منها — على البلاغ نفسِه', () {
    // فحصٌ باسمه لا عضويّةٌ في مجموعة: هذا هو النوعُ الذي وقع عليه العطب،
    // وغيابُه عن أيِّ طرفٍ يُعيد إيقافَ الإهلاك أو ابتلاعَه.
    expect(kMultiJeReferenceTypes, contains('asset_depreciation'),
        reason: 'الإهلاكُ قيدٌ لكلِّ شهرٍ و`referenceId` رقمُ الأصل بلا '
            'فترة — فبدون الإعفاء يُرحَّل شهرٌ واحدٌ لكلِّ أصلٍ إلى الأبد.');
    expect(_exemptionsInIndexSql(kCreateJeAutopostDedupIndexSql),
        contains('asset_depreciation'));
  });

  test('والفهرسُ ما زال فريداً وجزئيّاً — لا مجرّدَ فهرس', () {
    // لو سقطت `UNIQUE` أو `WHERE is_auto_posted = 1` لصار الفهرسُ بلا أثرٍ
    // حمائيٍّ أصلاً، ومرّ الفحصُ أعلاه أخضرَ وهو يحرس لا شيء.
    final sql = kCreateJeAutopostDedupIndexSql.toLowerCase();
    expect(sql, contains('unique index'));
    expect(sql, contains('is_auto_posted = 1'));
    expect(sql, contains('journal_entries(reference_type, reference_id)'));
  });
}
