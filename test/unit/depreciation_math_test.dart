// test/unit/depreciation_math_test.dart
//
// حسابُ الإهلاك — **نسخةٌ واحدةٌ للمحرّك والشاشة والحوار**.
//
// ═══ العطبُ الذي يحرسه هذا الملفّ ═══
//
// الصيغةُ مصدرُها `runMonthlyDepreciation` في `fixed_assets_dao_ext.dart` —
// وهي التي **تكتب** القيد. وشاشةُ الأصول تعرض القسطَ قبل ترحيله، وحوارُ «أصل
// جديد» يعرض جدولَ الإهلاك قبل الإنشاء.
//
// 🔴 فانحرافُ أيٍّ منها عن المحرّك يعني **رقماً يُقرأ وغيرَه يُقيَّد** —
// والمستخدمُ يقرّر على المعروض. ولذلك القيمُ هنا **مثبَّتةٌ محسوبةً بيد**، لا
// «أكبرُ من صفر»: مصالحةٌ تتّفق عند رقمٍ خاطئٍ تمرّ خضراء.
//
// ⚠️ **والقسطُ المتناقصُ مضاعفٌ** (`2/(n×12)`) لا ٢٠٪ كما يفترض نصُّ
// التصميم. وهذا الملفُّ يثبّت الصيغةَ التي في المحرّك لا التي في النصّ.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/depreciation_math.dart';

void main() {
  group('القسط الثابت', () {
    test('أرقامُ التصميم بالضبط — ٦٤٠٠٠ و٤٠٠٠ و٧ سنوات', () {
      // (64,000 − 4,000) ÷ (7 × 12) = 60,000 ÷ 84 = 714.285714…
      final monthly = monthlyDepreciation(
        purchasePrice: 64000,
        salvageValue: 4000,
        usefulLifeYears: 7,
        depreciationMethod: kStraightLine,
      );

      expect(monthly, closeTo(714.2857142857143, 1e-9));
      // والسنويُّ في لوحة التصميم 8,571.43 — وهو ١٢ ضعفاً بالضبط.
      expect(monthly * 12, closeTo(8571.428571428572, 1e-9));
    });

    test('التخريديّةُ تُخصَم قبل القسمة لا بعدها', () {
      // لو قُسم الثمنُ كاملاً لكان 64000/84 = 761.90 — رقمٌ أعلى بـ٤٧.٦٢.
      final withSalvage = monthlyDepreciation(
        purchasePrice: 64000,
        salvageValue: 4000,
        usefulLifeYears: 7,
        depreciationMethod: kStraightLine,
      );
      final withoutSalvage = monthlyDepreciation(
        purchasePrice: 64000,
        salvageValue: 0,
        usefulLifeYears: 7,
        depreciationMethod: kStraightLine,
      );

      expect(withoutSalvage, closeTo(761.9047619047619, 1e-9));
      expect(withoutSalvage - withSalvage, closeTo(47.61904761904762, 1e-9));
    });

    test('المجمَّعُ لا يغيّر القسطَ الثابت', () {
      // الثابتُ لا يقرأ `accumulatedDepreciation` إطلاقاً — بخلاف المتناقص.
      final fresh = monthlyDepreciation(
        purchasePrice: 64000,
        salvageValue: 4000,
        usefulLifeYears: 7,
        depreciationMethod: kStraightLine,
      );
      final halfway = monthlyDepreciation(
        purchasePrice: 64000,
        salvageValue: 4000,
        usefulLifeYears: 7,
        depreciationMethod: kStraightLine,
        accumulatedDepreciation: 30000,
      );

      expect(halfway, equals(fresh));
    });
  });

  group('القسط المتناقص', () {
    test('مضاعفٌ ٢/(n×12) لا ٢٠٪ — والأساسُ الرصيدُ الدفتريّ', () {
      // 64,000 × 2/(7×12) = 64,000 × 2/84 = 1,523.809523…
      final first = monthlyDepreciation(
        purchasePrice: 64000,
        salvageValue: 4000,
        usefulLifeYears: 7,
        depreciationMethod: kDecliningBalance,
      );

      expect(first, closeTo(1523.8095238095239, 1e-9));

      // ⚠️ ولو كانت ٢٠٪ سنويّاً لكان القسطُ 64,000×0.2/12 = 1,066.67 —
      //    فرقٌ ٤٥٧ جنيهاً في أوّل شهر. الرقمُ لا الاتّجاه.
      expect(first, isNot(closeTo(1066.6666666666667, 0.01)));
    });

    test('الأساسُ الثمنُ ناقصَ المجمَّع فيتناقص فعلاً', () {
      // (64,000 − 20,000) × 2/84 = 44,000 × 2/84 = 1,047.619047…
      final later = monthlyDepreciation(
        purchasePrice: 64000,
        salvageValue: 4000,
        usefulLifeYears: 7,
        depreciationMethod: kDecliningBalance,
        accumulatedDepreciation: 20000,
      );

      expect(later, closeTo(1047.6190476190477, 1e-9));
    });

    test('السقفُ يمنع الهبوطَ تحت القيمة التخريديّة', () {
      // القابلُ للإهلاك 60,000 والمجمَّعُ 59,800 ⇒ الباقي ٢٠٠ لا الحساب
      // المعتاد (64,000−59,800)×2/84 = 100.0 … بل الأقلُّ منهما هو ما
      // يُقيَّد. هنا الحسابُ ١٠٠ وهو دونَ الباقي، فيمرّ كما هو.
      final capped = monthlyDepreciation(
        purchasePrice: 64000,
        salvageValue: 4000,
        usefulLifeYears: 7,
        depreciationMethod: kDecliningBalance,
        accumulatedDepreciation: 59800,
      );
      expect(capped, closeTo(100.0, 1e-9));

      // وحين يتجاوز الحسابُ الباقيَ، يُقصّ إليه:
      // (64,000−59,990)×2/84 = 95.48 وهو أكبرُ من الباقي ١٠ ⇒ يصير ١٠.
      final clipped = monthlyDepreciation(
        purchasePrice: 64000,
        salvageValue: 4000,
        usefulLifeYears: 7,
        depreciationMethod: kDecliningBalance,
        accumulatedDepreciation: 59990,
      );
      expect(clipped, closeTo(10.0, 1e-9));
    });

    test('مجمَّعٌ بلغ القابلَ للإهلاك ⇒ صفرٌ لا سالب', () {
      final done = monthlyDepreciation(
        purchasePrice: 64000,
        salvageValue: 4000,
        usefulLifeYears: 7,
        depreciationMethod: kDecliningBalance,
        accumulatedDepreciation: 60000,
      );
      expect(done, 0);
    });
  });

  group('الحدود', () {
    test('عمرٌ صفريٌّ ⇒ صفرٌ لا Infinity', () {
      // 🔴 القسمةُ على صفرٍ في Dart تعطي `Infinity` لا استثناءً — فتُعرَض
      //    للمستخدم «∞» في لوحة الجدول لو لم تُحرَس قبل الحساب.
      final z = monthlyDepreciation(
        purchasePrice: 64000,
        salvageValue: 4000,
        usefulLifeYears: 0,
        depreciationMethod: kStraightLine,
      );
      expect(z, 0);
      expect(z.isFinite, isTrue);
    });

    test('تخريديّةٌ تساوي الثمنَ ⇒ لا إهلاك', () {
      expect(
        monthlyDepreciation(
          purchasePrice: 64000,
          salvageValue: 64000,
          usefulLifeYears: 7,
          depreciationMethod: kStraightLine,
        ),
        0,
      );
    });

    test('تخريديّةٌ تتجاوز الثمنَ ⇒ صفرٌ لا قسطٌ سالب', () {
      expect(
        monthlyDepreciation(
          purchasePrice: 10000,
          salvageValue: 15000,
          usefulLifeYears: 5,
          depreciationMethod: kStraightLine,
        ),
        0,
      );
    });

    test('المبلغُ القابل للإهلاك فرقٌ مباشر', () {
      expect(
        depreciableAmount(purchasePrice: 64000, salvageValue: 4000),
        60000,
      );
    });
  });

  group('نهاية العمر', () {
    test('سبعُ سنواتٍ من ٢٠٢٦-٠٨ ⇒ ٢٠٣٣-٠٨ كما في لوحة التصميم', () {
      final end = endOfLife(
        purchaseDate: DateTime(2026, 8, 25),
        usefulLifeYears: 7,
      );
      expect(end.year, 2033);
      expect(end.month, 8);
    });

    test('نصفُ سنةٍ يُقرَّب إلى ستّة أشهر', () {
      final end = endOfLife(
        purchaseDate: DateTime(2026, 1, 15),
        usefulLifeYears: 0.5,
      );
      expect(end.year, 2026);
      expect(end.month, 7);
    });
  });
}
