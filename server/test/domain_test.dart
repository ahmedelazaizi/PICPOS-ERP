import 'package:picpos_cloud/picpos_cloud.dart';
import 'package:test/test.dart';

// Tax, totals, pricing, integrity and barcode rules live in
// packages/picpos_rules (tested there with the shared parity fixture).
void main() {
  test('the cloud signs with the shared rules package', () {
    final payload = salesIntegrityPayload(
      number: 'VS-100000',
      date: DateTime.utc(2026, 1, 2, 3, 4, 5),
      total: 10.12,
      subtotal: 9.5,
      discount: 0.5,
      tax: 1.12,
      paid: 10.12,
      customerId: null,
      userId: 7,
      paymentMethod: salesPaymentMethod(paid: 10.12, remaining: 0),
    );
    expect(payload, 'VS-100000|2026-01-02T03:04:05.000Z|10.1200|9.5000|0.5000|1.1200|10.1200|0|7|cash');
    expect(signV2('secret', payload), startsWith('v2:'));
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
