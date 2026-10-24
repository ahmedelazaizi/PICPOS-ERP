// قرارُ المالك: نسبُ ضريبة معالج الإعداد بالضبط 0 · 1 · 2 · 4 · 5 · 10 · 14 · 15 · 16
// وهي نفسُ سلّم `TaxRatePolicy` — فلا تُختار في المعالج نسبةٌ يرفضها الصنفُ
// أو استيرادُ Excel أو الـAPI.

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/tax/tax_rate_policy.dart';
import 'package:picpos_erp/domain/models/first_run/first_run_currency.dart';

void main() {
  const owner = <double>[0, 1, 2, 4, 5, 10, 14, 15, 16];

  test('قائمةُ المعالج هي قائمةُ المالك بالضبط، وتشمل 14 و15', () {
    expect(kFirstRunVatRates, owner);
    expect(kFirstRunVatRates, containsAll(<double>[14, 15]));
  });

  test('كلُّ نسبةٍ في المعالج مقبولةٌ في سياسة الضريبة (صنف · Excel · API)', () {
    TaxRatePolicy.resetForTests();
    for (final r in kFirstRunVatRates) {
      expect(TaxRatePolicy.isAllowed(r), isTrue, reason: 'النسبة $r');
    }
  });

  test('السلّمان متطابقان — لا نسبةَ تُقبل في أحدهما وتُرفض في الآخر', () {
    expect(TaxRatePolicy.defaultAllowedRates, kFirstRunVatRates);
    expect(TaxRatePolicy.defaultAllowedRates, owner);
  });
}
