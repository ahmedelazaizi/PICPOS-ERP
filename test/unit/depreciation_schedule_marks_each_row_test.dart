// جدولُ إهلاك الأصل — **وسمٌ لكلّ صفّ**، وعمرٌ يُعرَض بالشهور.
//
// ═══ ما يُقاس هنا ولماذا ═══
//
// قرارُ المالك على الصورة `(8)`: التصميمُ يضع وسمَ «معاينة غير مرحّلة»
// **واحداً فوق الجدول كلِّه**، والوسمُ يصير **على كلّ صفّ**.
//
// والسبب: جدولُ أصلٍ نصفُه مُرحَّلٌ ونصفُه توقّعٌ هو **الحالةُ الطبيعيّة**
// بعد أوّل شهرٍ من عمره. فوسمٌ واحدٌ إمّا يقول «غيرُ مرحّلة» على أشهرٍ دخلت
// الأستاذَ فعلاً، أو يقول «مرحّلة» على توقّعٍ لم يُقيَّد. وكلاهما رقمٌ
// يُقرَّر عليه.
//
// ═══ و🔴 الشهورُ مقابلَ السنوات ═══
//
// العمودُ `usefulLifeYears` **بالسنوات** وكلُّ صيغةٍ تضرب في ١٢؛ والتصميمُ
// يعرض «٣٦ شهراً». و٣٦ تُكتَب في حقل سنواتٍ = إهلاكٌ على ستٍّ وثلاثين سنةً
// بدل ثلاث: القسطُ جزءٌ من اثنَي عشرَ ممّا يجب، والقيدُ **متّزنٌ على الرقم
// الخاطئ** فلا فحصَ اتّزانٍ يمسكه.

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/models/depreciation_math.dart';

void main() {
  group('🔴 العمرُ: شهورٌ للعرض وسنواتٌ للتخزين', () {
    test('ثلاثُ سنواتٍ = ٣٦ شهراً', () {
      expect(usefulLifeMonths(3), 36);
    });

    test('والعودةُ تُغلق الدائرة', () {
      expect(usefulLifeYearsFromMonths(36), 3);
    });

    test('🔴 والكسرُ يبقى كسراً — ٣٠ شهراً ليست ٣ سنوات', () {
      expect(usefulLifeYearsFromMonths(30), 2.5,
          reason: 'التقريبُ إلى ٣ يُطيل العمرَ سدسَه ويخفّض القسطَ بنفس '
              'النسبة — والعمودُ `real` فيحتمل الكسر');
    });

    test('ونصفُ سنةٍ = ٦ أشهر', () {
      expect(usefulLifeMonths(0.5), 6);
    });
  });

  group('🔴 الجدول: المرحَّلُ يُقرأ والمتوقَّعُ يُحسَب', () {
    // ١٢٠٠٠ على ٣ سنواتٍ بالقسط الثابت = ٣٣٣٫٣٣… شهريّاً — مثالُ التصميم.
    List<DepreciationScheduleRow> schedule({
      List<PostedDepreciation> posted = const [],
      DateTime? until,
    }) =>
        buildDepreciationSchedule(
          purchasePrice: 12000,
          salvageValue: 0,
          usefulLifeYears: 3,
          depreciationMethod: kStraightLine,
          purchaseDate: DateTime(2026, 1, 1),
          until: until ?? DateTime(2026, 6, 30),
          posted: posted,
        );

    test('بلا ترحيلٍ: ستّةُ أشهرٍ كلُّها **متوقَّعة**', () {
      final rows = schedule();
      expect(rows, hasLength(6));
      expect(rows.every((r) => !r.posted), isTrue);
      expect(rows.first.amount, closeTo(333.33, 0.01));
      expect(rows.last.accumulated, closeTo(2000, 0.01));
      expect(rows.last.bookValue, closeTo(10000, 0.01));
    });

    test('🔴 وشهران مرحَّلان وأربعةٌ متوقَّعة — في جدولٍ واحد', () {
      final rows = schedule(posted: [
        (
          periodDate: DateTime(2026, 1, 28),
          amount: 333.33,
          accumulated: 333.33,
          bookValue: 11666.67
        ),
        (
          periodDate: DateTime(2026, 2, 28),
          amount: 333.33,
          accumulated: 666.66,
          bookValue: 11333.34
        ),
      ]);
      expect(rows, hasLength(6));
      expect([for (final r in rows) r.posted],
          [true, true, false, false, false, false],
          reason: 'وسمٌ واحدٌ على الجدول كان سيكذب على أحد النصفين');
    });

    test('🔴 والمرحَّلُ يُقرأ كما هو لا يُعاد حسابُه', () {
      // ‏`revalueAsset` تغيّر `purchasePrice` ولا تكتب صفَّ إهلاك — فإعادةُ
      //   حساب الماضي بالتكلفة الجديدة تُظهر رقماً يخالف القيدَ المرحَّل.
      final rows = schedule(posted: [
        (
          periodDate: DateTime(2026, 1, 28),
          amount: 111.11,
          accumulated: 111.11,
          bookValue: 11888.89
        ),
      ]);
      expect(rows.first.amount, 111.11,
          reason: 'أُعيد حسابُ شهرٍ دخل الأستاذَ — فالشاشةُ تخالف الدفتر');
      // والتوقّعُ بعده يتفرّع من المتراكم المرحَّل لا من صفر.
      expect(rows[1].accumulated, closeTo(111.11 + 333.33, 0.01));
    });

    test('🔴 والتوقّعُ يتوقّف عند استنفاد المبلغ القابل للإهلاك', () {
      final rows = buildDepreciationSchedule(
        purchasePrice: 1200,
        salvageValue: 0,
        usefulLifeYears: 1,
        depreciationMethod: kStraightLine,
        purchaseDate: DateTime(2026, 1, 1),
        // عشرُ سنواتٍ من المدى مقابلَ عمرٍ سنةً واحدة.
        until: DateTime(2036, 1, 1),
      );
      expect(rows, hasLength(12),
          reason: 'الجدولُ امتدّ إلى ما بعد العمر — بقسطٍ صفريٍّ أو بإهلاكٍ '
              'يتجاوز التكلفة');
      expect(rows.last.accumulated, closeTo(1200, 0.01));
      expect(rows.last.bookValue, closeTo(0, 0.01));
    });

    test('والقيمةُ التخريديّةُ تُترَك على الدفاتر', () {
      final rows = buildDepreciationSchedule(
        purchasePrice: 1200,
        salvageValue: 200,
        usefulLifeYears: 1,
        depreciationMethod: kStraightLine,
        purchaseDate: DateTime(2026, 1, 1),
        until: DateTime(2030, 1, 1),
      );
      expect(rows.last.accumulated, closeTo(1000, 0.01));
      expect(rows.last.bookValue, closeTo(200, 0.01));
    });

    test('ومدىً قبل تاريخ الاقتناء يعطي جدولاً فارغاً لا سالباً', () {
      final rows = schedule(until: DateTime(2025, 12, 31));
      expect(rows, isEmpty);
    });

    test('والقسطُ المتناقصُ يتناقص فعلاً', () {
      final rows = buildDepreciationSchedule(
        purchasePrice: 12000,
        salvageValue: 0,
        usefulLifeYears: 3,
        depreciationMethod: kDecliningBalance,
        purchaseDate: DateTime(2026, 1, 1),
        until: DateTime(2026, 4, 30),
      );
      expect(rows, hasLength(4));
      for (var i = 1; i < rows.length; i++) {
        expect(rows[i].amount, lessThan(rows[i - 1].amount),
            reason: 'قسطٌ متناقصٌ لا يتناقص ⇒ المتراكمُ لا يُمرَّر للشهر '
                'التالي');
      }
    });
  });

  group('🔴 «كما في»: أصلٌ لم يكن قد وُجد لا يظهر', () {
    test('المشتَرى بعد التاريخ يسقط', () {
      expect(assetOnBooksAt(DateTime(2026, 12, 1), DateTime(2026, 6, 30)),
          isFalse,
          reason: '🔴 جردُ يونيو كان يعرض أصلَ ديسمبر بتكلفته كاملةً '
              'ومجمَّعِ صفرٍ — فيكبر الصافي بقيمته كاملة');
    });

    test('والمشتَرى قبله يبقى', () {
      expect(assetOnBooksAt(DateTime(2026, 1, 1), DateTime(2026, 6, 30)),
          isTrue);
    });

    test('🔴 والمشتَرى **في** يوم النظر يبقى — المقارنةُ باليوم لا باللحظة',
        () {
      expect(
        assetOnBooksAt(DateTime(2026, 6, 30), DateTime(2026, 6, 30, 23, 59)),
        isTrue,
      );
      expect(
        assetOnBooksAt(DateTime(2026, 6, 30, 14, 0), DateTime(2026, 6, 30)),
        isTrue,
        reason: 'ساعةُ الشراء أسقطت أصلاً اشتُري في يوم النظر نفسِه',
      );
    });
  });
}
