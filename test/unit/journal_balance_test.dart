// اتّزانُ القيد — **سماحيّةٌ واحدةٌ يقرؤها العرضُ والإدخالُ والكاتب.**
//
// ═══ ما تحرسه هذه الحزمة ═══
//
// كانت شاشةُ اليومية تقيس `< 0.005` بينما مُصادِقُ المزامنة يقبل حتى
// `FinancialUtils.balanceTolerance` (‏٠٫٠١، وهي المُعلَنةُ «‏the ONE allowed
// debit-vs-credit tolerance» في Spec 139).
//
// 🔴 **فالفجوةُ بين ٠٫٠٠٥ و٠٫٠١ منطقةٌ يكتب فيها النظامُ قيداً ويعرضه
// «غير متوازن».** ولا يملك المستخدمُ ما يصلحه به: القيدُ وصل بالمزامنة،
// وسطورُه كما أرسلها المصدر.

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/utils/financial_utils.dart';
import 'package:picpos_erp/domain/models/journal_balance.dart';

void main() {
  group('الاتّزان', () {
    test('مدينٌ يساوي دائناً ⇒ متوازنٌ وفرقُه صفر', () {
      const b = JournalBalance(debit: 1000, credit: 1000);
      expect(b.difference, 0);
      expect(b.isBalanced, isTrue);
    });

    test('🔴 والفجوةُ التي كانت تتناقض: ٠٫٠٠٧ متوازنٌ الآن', () {
      // قيدٌ يقبله مُصادِقُ المزامنة ويكتبه، وكانت الشاشةُ تعرضه «غير متوازن».
      const b = JournalBalance(debit: 1000.007, credit: 1000);
      expect(b.magnitude, closeTo(0.007, 0.0001));
      expect(b.isBalanced, isTrue,
          reason: 'العرضُ ما زال أشدَّ من الكاتب — قيدٌ مكتوبٌ يُعرَض مكسوراً');
    });

    test('وبقيّةٌ عند الحدِّ تماماً متوازنةٌ — كما يَعُدُّها الكاتب', () {
      // 🔴 **وهذا ما يمنع تناقضاً أشدَّ من الأوّل.** `accounting_dao_writes`
      // يقيّد بقيّةً في حدِّ السماحيّة في حساب «فروق التقريب» ويَعُدُّ القيدَ
      // متوازناً (`residualMinor.abs() <= balanceToleranceMinorUnits`).
      // فعرضٌ يرفضها يناقض الدفترَ الذي كتبها — ولذلك `<=` لا `<`.
      //
      // ⚠️ والحدُّ يُقرأ من الثابت لا يُكتَب رقماً: عملةٌ بثلاث منازلَ تجعله
      // ١٠ وحداتٍ صغرى لا واحدة.
      final cap = FinancialUtils.balanceToleranceMinorUnits;
      final atCap = FinancialUtils.fromMinorUnits(cap);
      final b = JournalBalance(debit: 1000 + atCap, credit: 1000);
      expect(b.differenceMinorUnits.abs(), cap);
      expect(b.isBalanced, isTrue);
    });

    test('وما فوق الحدِّ بوحدةٍ واحدةٍ فرقٌ حقيقيٌّ يُرفَض', () {
      final over =
          FinancialUtils.fromMinorUnits(FinancialUtils.balanceToleranceMinorUnits + 1);
      final b = JournalBalance(debit: 1000 + over, credit: 1000);
      expect(b.isBalanced, isFalse,
          reason: 'التوحيدُ ابتلع فرقاً حقيقيّاً');
    });

    test('🔴 وكلُّ طرفٍ يُحوَّل وحدَه — لا الفرقُ بعد طرحه', () {
      // 🔴 **وهذه طفرةٌ نجت أوّلاً.** `toMinorUnits(debit - credit)` تعطي
      // نفسَ الجواب على الأرقام المستديرة، وتفارقه حين يحمل الطرفان بقيّةً
      // دون الوحدة الصغرى: الطرحُ قبل التحويل يبتلعها، والتحويلُ قبل الطرح
      // يقرّب كلَّ طرفٍ كما يفعل **كاتبُ القيد** (يجمع وحداتِ كلّ سطرٍ على
      // حدة). والمطابقةُ له هي كلُّ غرضِ هذه الوحدة.
      // كلُّ طرفٍ يُقرَّب وحدَه: ‏٠٫٠٠٠٥ ← ١ و٠٫٠٠٠٤ ← ٠، فالفرقُ ١.
      // والطرحُ أوّلاً يعطي ٠٫٠٠٠٠٩٩٩… ← ٠.
      const b = JournalBalance(debit: 0.0005, credit: 0.0004);
      expect(b.differenceMinorUnits, 1,
          reason: 'الفرقُ حُوِّل بعد الطرح فابتُلعت بقيّةُ التقريب');
      expect(FinancialUtils.toMinorUnits(0.0005 - 0.0004), 0,
          reason: 'التجهيزةُ لا تصف الفرقَ المقصود');
    });

    test('🔴 والقياسُ بالوحدات الصغرى لا بالكسر العائم', () {
      // `(1000.01 - 1000)` يعطي `0.009999999999990905`. فالمقارنةُ
      // `< 0.01` تمرّ **بالمصادفة**، و`== 0.01` تسقط — والاعتمادُ على تلك
      // المصادفة يعني قاعدةً تتغيّر بتغيّر الأرقام المحيطة لا بتغيّر المقصود.
      const raw = 1000.01 - 1000;
      expect(raw < 0.01, isTrue, reason: 'التجهيزةُ لا تصف ضجيجَ الفاصلة');
      expect(raw, isNot(0.01));
      // والقاعدةُ تعطي الجوابَ **بالبناء**: عددٌ صحيحٌ يساوي الحدَّ تماماً.
      expect(
        const JournalBalance(debit: 1000.01, credit: 1000)
            .differenceMinorUnits,
        FinancialUtils.balanceToleranceMinorUnits,
      );
    });
  });

  group('الفرقُ بإشارته', () {
    test('مدينٌ زائدٌ ⇒ موجب', () {
      expect(const JournalBalance(debit: 150, credit: 100).difference, 50);
    });

    test('ودائنٌ زائدٌ ⇒ سالب', () {
      // ⚠️ «الفرق ٥٠» لا يقول أيَّ الطرفَين ناقص، و«٥٠−» يقوله.
      expect(const JournalBalance(debit: 100, credit: 150).difference, -50);
      expect(const JournalBalance(debit: 100, credit: 150).magnitude, 50);
    });
  });

  group('الاتّزانُ وحدَه لا يكفي للترحيل', () {
    test('قيدٌ فارغٌ متوازنٌ حسابيّاً وغيرُ قابلٍ للترحيل', () {
      // 🔴 خلطُ الشرطَين في رايةٍ واحدةٍ كان يجعل «متوازن» تعني شيئَين:
      // حوارُ الإنشاء يشترط قيمةً موجبةً فوق الاتّزان، والعرضُ لا يشترطها.
      const b = JournalBalance(debit: 0, credit: 0);
      expect(b.isBalanced, isTrue);
      expect(b.isEmpty, isTrue);
      expect(b.isPostable, isFalse);
    });

    test('وقيدٌ بقيمةٍ موجبةٍ متوازنٍ قابلٌ للترحيل', () {
      expect(const JournalBalance(debit: 500, credit: 500).isPostable, isTrue);
    });
  });

  group('الجمعُ من السطور ومن القيود', () {
    test('‏`of` تجمع سطوراً', () {
      final b = JournalBalance.of(const [
        (debit: 600.0, credit: 0.0),
        (debit: 0.0, credit: 250.0),
        (debit: 0.0, credit: 350.0),
      ]);
      expect(b.debit, 600);
      expect(b.credit, 600);
      expect(b.isBalanced, isTrue);
    });

    test('و`sum` تجمع قيوداً', () {
      final b = JournalBalance.sum(const [
        JournalBalance(debit: 100, credit: 100),
        JournalBalance(debit: 250, credit: 250),
      ]);
      expect(b.debit, 350);
      expect(b.credit, 350);
    });

    test('🔴 و`worstOf` لا يبتلع كسرَين متعاكسَين', () {
      // قيدان: مدينُ الأوّل زائدٌ ١٠٠ ودائنُ الثاني زائدٌ ١٠٠. مجموعُهما
      // فرقُه **صفر** — فشريطٌ يعرض فرقَ المجموع يقول «متوازن» وفي الصفحة
      // قيدان مكسوران.
      const a = JournalBalance(debit: 200, credit: 100);
      const b = JournalBalance(debit: 100, credit: 200);
      expect(JournalBalance.sum([a, b]).difference, 0,
          reason: 'التجهيزةُ لا تصف الحالةَ المقصودة');
      expect(JournalBalance.sum([a, b]).isBalanced, isTrue);
      expect(JournalBalance.worstOf([a, b]), 100,
          reason: 'أسوأُ فرقٍ ابتُلع في المجموع');
    });

    test('و`worstOf` على قيودٍ سليمةٍ صفر', () {
      expect(
        JournalBalance.worstOf(const [
          JournalBalance(debit: 100, credit: 100),
          JournalBalance(debit: 50, credit: 50),
        ]),
        0,
      );
    });

    test('وبلا قيودٍ إطلاقاً أصفارٌ لا أخطاء', () {
      expect(JournalBalance.sum(const []).debit, 0);
      expect(JournalBalance.worstOf(const []), 0);
      expect(JournalBalance.of(const []).isBalanced, isTrue);
    });
  });
}
