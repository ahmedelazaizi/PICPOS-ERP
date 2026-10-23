import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/constants/app_constants.dart';
import 'package:ural_erp/core/utils/number_utils.dart';

void main() {
  tearDown(() => AppConstants.setCurrency('JOD'));

  test('float noise is removed (JOD, 3 decimals)', () {
    AppConstants.setCurrency('JOD');
    expect(moneyFieldText(0.27999999999999997), '0.28');
    expect(0.27999999999999997.fieldText, '0.28');
  });

  test('plain values: 5.0, 1234.5, 0, 0.35, negative zero', () {
    AppConstants.setCurrency('JOD');
    expect(moneyFieldText(5.0), '5');
    expect(moneyFieldText(1234.5), '1234.5');
    expect(moneyFieldText(0), '0');
    expect(moneyFieldText(0.350), '0.35');
    expect(moneyFieldText(-0.0000001), '0');
    expect(moneyFieldText(10), '10');
    expect(moneyFieldText(100), '100');
  });

  test('uses the currency decimals; explicit decimals override', () {
    AppConstants.setCurrency('EGP');
    expect(moneyFieldText(0.27999999999999997), '0.28');
    expect(moneyFieldText(12.3456), '12.35');
    expect(moneyFieldText(12.3456, decimals: 3), '12.346');
  });

  test('result round-trips through the locale parser', () {
    for (final v in [0.27999999999999997, 5.0, 1234.5, 0.0]) {
      expect(NumberUtils.tryParseLocale(moneyFieldText(v)), closeTo(v, 1e-9));
    }
  });
}
