// ═══════════════════════════════════════════════════════════════════════════
// متطلبات العميل 2026-07-25 · م4 · البند 4 — «عند تعريف صنف جديد يمكن إضافة
// أي رقم في خانة الضريبة وهذا غير منطقي، حيث أن النسب الواردة كالتالي:
// معفي، 0%، 1%، 2%، 4%، 5%، 10%، 16%».
// ═══════════════════════════════════════════════════════════════════════════
//
// الحقل كان `TextField` عارياً بلا `validator` ولا `inputFormatters`، وبلا أي
// فحص في الـDAO أو الخادم أو استيراد Excel، وبلا قيد CHECK في السكيمة.
// النتيجة: 37.5 أو 999 أو **‑16** تُحفظ حرفياً — والأخيرة تولّد ضريبة سالبة
// في كل سطر بيع وشراء لذلك الصنف.
//
// السياسة قابلة للتهيئة عمداً: هذا منتج متعدد الدول (فيه مسارا ETA مصر
// وJoFotara الأردن)، فترميز سلّم واحد صلباً سيكون خاطئاً للعميل التالي.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/tax/tax_rate_policy.dart';

void main() {
  test('السلّم الافتراضي هو ما طلبه العميل بالضبط', () {
    expect(TaxRatePolicy.defaultAllowedRates, [0, 1, 2, 4, 5, 10, 16]);
  });

  test('النسب المسموحة تُقبل', () {
    for (final rate in TaxRatePolicy.defaultAllowedRates) {
      expect(TaxRatePolicy.isAllowed(rate), isTrue, reason: 'النسبة $rate');
    }
  });

  test('النسب العشوائية تُرفض', () {
    for (final rate in [37.5, 123.45, 999, 14, 3, 7.5]) {
      expect(TaxRatePolicy.isAllowed(rate.toDouble()), isFalse,
          reason: 'النسبة $rate ليست في السلّم القانوني');
    }
  });

  test('النسبة السالبة تُرفض — كانت تولّد ضريبة سالبة في كل سطر', () {
    expect(TaxRatePolicy.isAllowed(-16), isFalse);
    expect(TaxRatePolicy.isAllowed(-0.01), isFalse);
  });

  test('assertAllowed ترمي رسالة عربية تذكر النسبة والسلّم', () {
    expect(
      () => TaxRatePolicy.assertAllowed(37.5),
      throwsA(predicate((e) =>
          e.toString().contains('37.5') && e.toString().contains('16'))),
    );
  });

  test('assertAllowed تمرّ بصمت للنسب المسموحة', () {
    expect(() => TaxRatePolicy.assertAllowed(16), returnsNormally);
    expect(() => TaxRatePolicy.assertAllowed(0), returnsNormally);
  });

  test('فروق الفاصلة العائمة لا تُسقط نسبة مشروعة', () {
    // 16 قادمة من حساب عائم قد تصل كـ 15.999999999999998
    expect(TaxRatePolicy.isAllowed(15.999999999999998), isTrue);
    expect(TaxRatePolicy.isAllowed(16.000000000000004), isTrue);
    // لكن انحرافاً حقيقياً يبقى مرفوضاً
    expect(TaxRatePolicy.isAllowed(16.01), isFalse);
  });

  test('السلّم قابل للتهيئة لدولة أخرى', () {
    // مصر: 14% — يجب أن يكون التهيئة ممكنة دون تعديل الكود.
    const egypt = [0.0, 5.0, 10.0, 14.0];
    expect(TaxRatePolicy.isAllowed(14, allowed: egypt), isTrue);
    expect(TaxRatePolicy.isAllowed(16, allowed: egypt), isFalse);
  });

  test('parseAllowedRates تقرأ إعداداً نصياً وتتجاهل المشوَّه', () {
    expect(TaxRatePolicy.parseAllowedRates('0,5,16'), [0, 5, 16]);
    expect(TaxRatePolicy.parseAllowedRates(' 0 , 16 '), [0, 16]);
    expect(TaxRatePolicy.parseAllowedRates('0,abc,16'), [0, 16],
        reason: 'قيمة مشوَّهة تُتجاهل لا تُسقط الإعداد كله');
    expect(TaxRatePolicy.parseAllowedRates(''),
        TaxRatePolicy.defaultAllowedRates,
        reason: 'إعداد فارغ ⇒ السلّم الافتراضي');
    expect(TaxRatePolicy.parseAllowedRates(null),
        TaxRatePolicy.defaultAllowedRates);
    expect(TaxRatePolicy.parseAllowedRates('abc'),
        TaxRatePolicy.defaultAllowedRates,
        reason: 'إعداد فاسد بالكامل ⇒ لا تترك النظام بلا سلّم');
  });
}
