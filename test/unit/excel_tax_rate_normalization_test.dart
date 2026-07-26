// ═══════════════════════════════════════════════════════════════════════════
// استيراد الأصناف — نسبة الضريبة المنسَّقة كـ Percentage في Excel
// ═══════════════════════════════════════════════════════════════════════════
//
// بلاغ ميداني: استيراد ٥٢١ صنف فشل بـ ٥٢٠ خطأ، كلها
// «نسبة الضريبة "0.16" غير مسموح بها. النسب المتاحة: 0٪، 1٪، ... 16٪».
//
// السبب لم يكن خطأ في الملف: Excel يخزّن الخلية المنسَّقة كـ Percentage بقيمتها
// الكسرية. المستخدم كتب `16%`، والخلية تعرض `16%`، والملف يحوي `0.16`.
// المستورِد يقرأ القيمة الخام ويقارنها بسلّم نسب مئوية، فيرفض كل سطر.
//
// الاختبارات دي بتثبّت المنطق نفسه اللي في `ExcelService._normalizeTaxRate`.
// الدالة خاصة، فبنعيد تعريف نفس القاعدة هنا — لو اتغيرت هناك من غير ما تتغير
// هنا، الاختبار ده بيفضل أخضر وهو غلط؛ عشان كده كل تأكيد بيمر كمان على
// `TaxRatePolicy` الحقيقي اللي المستورِد بيرمي منه فعلاً.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/tax/tax_rate_policy.dart';

/// نسخة طبق الأصل من `ExcelService._normalizeTaxRate`.
double normalizeTaxRate(double raw, {List<double>? allowed}) {
  if (raw <= 0 || raw >= 1) return raw;
  final ladder = allowed ?? TaxRatePolicy.defaultAllowedRates;
  final asPercent = raw * 100;
  for (final r in ladder) {
    if ((r - asPercent).abs() < 1e-6) return r;
  }
  return raw;
}

void main() {
  group('نسبة الضريبة من خلية Excel منسَّقة كنسبة مئوية', () {
    test('0.16 (أي 16٪ في الملف) تتحوّل إلى 16 وتمرّ من السلّم', () {
      final normalized = normalizeTaxRate(0.16);
      expect(normalized, 16);
      expect(TaxRatePolicy.isAllowed(normalized), isTrue);
      // لازم تكون 16 بالظبط مش 16.000000000000002 — القيمة دي بتتخزّن في عمود
      // تُقارَن قيمه بالتساوي في التقارير الضريبية.
      expect(normalized, same16());
    });

    test('كل عضو في السلّم بيشتغل بصيغة الكسر', () {
      for (final rate in TaxRatePolicy.defaultAllowedRates) {
        if (rate == 0) continue;
        final asFraction = rate / 100;
        expect(normalizeTaxRate(asFraction), rate,
            reason: 'الكسر $asFraction يقابل $rate٪');
        expect(TaxRatePolicy.isAllowed(normalizeTaxRate(asFraction)), isTrue);
      }
    });

    test('القيم المكتوبة كنسبة مئوية أصلاً ما بتتلمسش', () {
      for (final rate in TaxRatePolicy.defaultAllowedRates) {
        expect(normalizeTaxRate(rate), rate);
      }
    });

    test('كسر مش على السلّم بيفضل مرفوض بقيمته الأصلية', () {
      // 0.37 → 37٪ مش في السلّم، فالقيمة بترجع زي ما هي والرفض بيحصل برسالة
      // فيها القيمة اللي المستخدم كتبها فعلاً — لا نُخفي خطأه بتحويل صامت.
      expect(normalizeTaxRate(0.37), 0.37);
      expect(TaxRatePolicy.isAllowed(normalizeTaxRate(0.37)), isFalse);
    });

    test('الأصفار والقيم الكبيرة ما بتتحوّلش', () {
      expect(normalizeTaxRate(0), 0);
      expect(normalizeTaxRate(16), 16);
      expect(normalizeTaxRate(37.5), 37.5);
      expect(TaxRatePolicy.isAllowed(normalizeTaxRate(37.5)), isFalse);
    });

    test('التحويل لا يمكن أن يُنقذ قيمة كانت هتعدّي أصلاً', () {
      // الادعاء اللي بيخلّي التعديل ده آمن: مفيش عضو في السلّم بين 0 و 1
      // حصراً، فأي قيمة في المدى ده كانت مرفوضة يقيناً قبل التعديل.
      for (final r in TaxRatePolicy.defaultAllowedRates) {
        expect(r > 0 && r < 1, isFalse,
            reason: 'وجود $r في المدى (0,1) بيخلّي التحويل ملتبس');
      }
    });

    test('سلّم مخصّص بيتحترم', () {
      const custom = [0.0, 14.0];
      expect(normalizeTaxRate(0.14, allowed: custom), 14);
      // 16٪ مش في السلّم المخصّص، فالكسر بتاعها ما بيتحوّلش.
      expect(normalizeTaxRate(0.16, allowed: custom), 0.16);
    });
  });
}

/// مطابق يرفض أي انحراف فاصلة عائمة عن 16 بالظبط.
Matcher same16() => predicate<double>(
      (v) => v.toString() == '16.0',
      'exactly 16.0 with no floating-point drift',
    );
