// دقّةُ العملة تتبع العملة — قرارُ المالك 2026-08-23.
//
// «ممكن المستخدم يحتاج تنصيب النظام على عملة مختلفة». والدينارُ ثلاثُ خاناتٍ
// والجنيهُ خانتان، فتنصيبةٌ بالجنيه كانت تحسب وتعرض بثلاث — شرائحُ الخزينة
// `0.000` والمجموعُ `0.00`.
//
// ⚠️ **المصيدةُ التي وُلدت منها أخطرُ حارسٍ هنا:** `_multiplier` كان
//    `static final`، و`static final` في دارت **كسولٌ يُحسب عند أوّل وصولٍ ثمّ
//    يثبت للأبد**. فلو لمس أيُّ كودٍ `FinancialUtils` قبل `setCurrency`
//    (و`init()` تقرأ القاعدةَ بعد إقلاعٍ كامل) لتجمّد المضاعفُ على ١٠٠٠
//    وبقيت الحساباتُ بثلاث خاناتٍ رغم اختيار الجنيه — **صامتةً**.
//
//    ولهذا لا يكفي أن يُقاس `decimalPlaces` بعد التبديل: لا بدّ من قياس
//    **`toMinorUnits`** نفسِها، لأنها وحدَها تكشف المضاعفَ المتجمّد.
//
// ⚠️ وكلُّ اختبارٍ هنا يعيد العملةَ في `tearDown` — الحالةُ ساكنةٌ، وتركُها
//    مبدَّلةً يسرّب إلى ملفّاتٍ أخرى فيُسقطها بترتيبٍ عشوائيّ (نفسُ صنفِ
//    تسريبِ أدوارِ PostgreSQL المسجَّل).
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/constants/app_constants.dart';
import 'package:ural_erp/core/utils/financial_utils.dart';

void main() {
  // الافتراضُ `JOD` — ولا يُبدَّل. سويّةُ الاختبارات كلُّها مبنيّةٌ عليه.
  tearDown(() => AppConstants.setCurrency('JOD'));

  group('العملةُ تحمل دقّتَها', () {
    test('الدينارُ ثلاثُ خاناتٍ والجنيهُ خانتان', () {
      expect(CurrencyInfo.jod.decimals, 3);
      expect(CurrencyInfo.egp.decimals, 2);
    });

    test('كلُّ عملةٍ مدعومةٍ لها دقّةٌ معقولة', () {
      for (final c in CurrencyInfo.all) {
        expect(c.decimals, inInclusiveRange(0, 4),
            reason: 'دقّةٌ خارج [0,4] تكسر التقريبَ والوحداتِ الصغرى');
      }
    });
  });

  group('التبديلُ يصل الحسابَ لا العرضَ وحدَه', () {
    test('setCurrency(EGP) يضبط الدقّةَ على خانتين', () {
      AppConstants.setCurrency('EGP');
      expect(AppConstants.decimalPlaces, 2);
      expect(AppConstants.currencyCode, 'EGP');
    });

    test('setCurrency(JOD) يعيدها ثلاثاً — التبديلُ ذو اتّجاهين', () {
      AppConstants.setCurrency('EGP');
      AppConstants.setCurrency('JOD');
      expect(AppConstants.decimalPlaces, 3);
    });

    // ── الحارسُ الذي يمسك م-١ ────────────────────────────────────────────
    test('المضاعفُ لا يتجمّد: toMinorUnits تتبع العملةَ بعد لمسٍ مسبق', () {
      // لمسٌ **قبل** التبديل — هذا بالضبط ما كان يجمّد `static final`.
      expect(FinancialUtils.toMinorUnits(12.345), 12345);

      AppConstants.setCurrency('EGP');
      // ⚠️ ‏١٢٣٥ لا ١٢٣٤: التقريبُ نصفُه لأعلى، فـ12.345 بخانتين = 12.35.
      // (مسوّدةُ المواصفة كتبت ١٢٣٤ سهواً — والرقمُ الصحيحُ هو الموافقُ
      //  لـ`round` أدناه، وإلّا تناقض حارسان.)
      // والمقصودُ من الحارس أنها **ليست ١٢٣٤٥**: ذاك هو المضاعفُ المتجمّد.
      expect(FinancialUtils.toMinorUnits(12.345), 1235,
          reason: 'لو رجعت 12345 فالمضاعفُ متجمّدٌ على ١٠٠٠ — والحساباتُ '
              'كلُّها بثلاث خاناتٍ رغم اختيار الجنيه، صامتةً');
    });

    test('fromMinorUnits تتبع العملةَ أيضاً', () {
      AppConstants.setCurrency('EGP');
      expect(FinancialUtils.fromMinorUnits(1234), closeTo(12.34, 1e-9));
    });

    test('round تتبع العملة', () {
      expect(FinancialUtils.round(12.345), closeTo(12.345, 1e-9));
      AppConstants.setCurrency('EGP');
      expect(FinancialUtils.round(12.345), closeTo(12.35, 1e-9));
    });
  });

  group('سماحُ الاتّزان يبقى متّسقاً', () {
    test('الوحداتُ الصغرى للسماح تتبع الدقّة', () {
      expect(FinancialUtils.balanceToleranceMinorUnits, 10);
      AppConstants.setCurrency('EGP');
      expect(FinancialUtils.balanceToleranceMinorUnits, 1,
          reason: 'م-٣: بخانتين يضيق الهامشُ إلى وحدةٍ صغرى واحدة');
    });

    test('قيدٌ متّزنٌ بالجنيه يبقى متّزناً', () {
      AppConstants.setCurrency('EGP');
      // ٧٠٫٠٠ + ١١٫٢٠ = ٨١٫٢٠ — نفسُ أرقامِ SINV-2 الحقيقيّة.
      const debit = 81.20;
      const credit = 70.00 + 11.20;
      expect(() => FinancialUtils.assertBalanced(debit, credit),
          returnsNormally);
    });
  });
}
