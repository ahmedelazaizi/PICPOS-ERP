import 'package:picpos_cloud/picpos_cloud.dart';
import 'package:test/test.dart';

void main() {
  group('effectiveItemTaxRate (parity with ural_erp lib/core/tax)', () {
    test('exempt is always 0', () {
      expect(effectiveItemTaxRate(rate: 16, exempt: true, companyDefault: 16), 0);
    });
    test('positive item rate wins', () {
      expect(effectiveItemTaxRate(rate: 8, exempt: false, companyDefault: 16), 8);
    });
    test('zero item rate falls back to company default', () {
      expect(effectiveItemTaxRate(rate: 0, exempt: false, companyDefault: 16), 16);
    });
  });

  test('computeTotals: per-line tax on net, 2dp rounding', () {
    final t = computeTotals([
      LineInput(quantity: 3, unitPrice: 2.5, discount: 0.5, taxRate: 16),
      LineInput(quantity: 2, unitPrice: 1, discount: 0, taxRate: 0),
    ]);
    expect(t.subtotal, 9.5);
    expect(t.discount, 0.5);
    expect(t.tax, 1.12); // (7.5 - 0.5) * 16 %
    expect(t.total, 10.12);
  });

  test('integrity payload uses the desktop sales format', () {
    final date = DateTime.utc(2026, 1, 2, 3, 4, 5);
    final payload = salesIntegrityPayload(
      number: 'VS-100000',
      date: date,
      total: 10.12,
      subtotal: 9.5,
      discount: 0.5,
      tax: 1.12,
      paid: 10.12,
      customerId: null,
      userId: 7,
      paymentMethod: 'cash',
    );
    expect(payload,
        'VS-100000|2026-01-02T03:04:05.000Z|10.1200|9.5000|0.5000|1.1200|10.1200|0|7|cash');
    final sig = signV2('secret', payload);
    expect(sig, startsWith('v2:'));
    expect(sig, signV2('secret', payload));
    expect(sig, isNot(signV2('other', payload)));
  });

  test('PIN hash round trip', () {
    final h = hashPin('1234', iterations: 1000);
    expect(verifyPin('1234', h), isTrue);
    expect(verifyPin('1235', h), isFalse);
  });

  test('session tokens verify and reject tampering', () {
    final t = SessionTokens('x' * 40);
    final tok = t.issue(employeeId: 1, devicePk: 2, companyId: 3);
    expect(t.verify(tok)!['did'], 2);
    expect(t.verify('${tok}a'), isNull);
    expect(SessionTokens('y' * 40).verify(tok), isNull);
  });
}
