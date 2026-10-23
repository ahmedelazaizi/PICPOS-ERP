// SEC-006 / SEC-015 (audit 2026-10-23): small hardening helpers.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/services/api/constant_time.dart';
import 'package:ural_erp/services/cash_drawer_service_io.dart';

void main() {
  test('ConstantTime.equals', () {
    expect(ConstantTime.equals('abc', 'abc'), isTrue);
    expect(ConstantTime.equals('abc', 'abd'), isFalse);
    expect(ConstantTime.equals('abc', 'abcd'), isFalse);
    expect(ConstantTime.equals('', ''), isTrue);
  });

  test('cash drawer printer names with cmd metacharacters are rejected', () {
    expect(CashDrawerServiceIO.isSafePrinterName('EPSON TM-T20II'), isTrue);
    expect(CashDrawerServiceIO.isSafePrinterName('طابعة الكاشير 1'), isTrue);
    for (final bad in ['a & calc', 'a|b', 'a>b', 'a"b', 'a%PATH%', 'a^b', '']) {
      expect(CashDrawerServiceIO.isSafePrinterName(bad), isFalse, reason: bad);
    }
  });
}