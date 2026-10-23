// Audit B DATA-002 — owner rule F.1 keeps stripping the country code from the
// canonical key, but two numbers that BOTH carry a (different) country code are
// different people; a local number (no code) still matches either.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/utils/phone_normalizer.dart';

void main() {
  test('F.1 unchanged: canonical key still drops the country code', () {
    expect(normalizePhone('+966501234567'), '501234567');
    expect(normalizePhone('+971501234567'), '501234567');
    expect(normalizePhone('0501234567'), '501234567');
  });

  test('country code is detected only when the number carries one', () {
    expect(phoneCountryCode('+966501234567'), '966');
    expect(phoneCountryCode('00971501234567'), '971');
    expect(phoneCountryCode('0501234567'), isNull);
    expect(phoneCountryCode('201234567'), isNull); // short local number
  });

  test('different explicit country codes are NOT the same phone', () {
    expect(samePhone('+966501234567', '+971501234567'), isFalse);
  });

  test('same explicit code, or local vs international, still match (F.1)', () {
    expect(samePhone('+966501234567', '00966 50 123 4567'), isTrue);
    expect(samePhone('0501234567', '+966501234567'), isTrue);
    expect(samePhone('0501234567', '+971501234567'), isTrue);
    expect(samePhone('0501234567', '501234567'), isTrue);
  });
}
