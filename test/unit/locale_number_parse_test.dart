import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/utils/number_utils.dart';

/// Spec 137 BUG-U14/U25: numeric fields must accept Arabic-locale input
/// (Arabic-Indic digits and comma as the decimal separator).
void main() {
  group('NumberUtils.tryParseLocale', () {
    test('parses a plain Western number', () {
      expect(NumberUtils.tryParseLocale('10.5'), 10.5);
    });

    test('accepts comma as the decimal separator', () {
      expect(NumberUtils.tryParseLocale('10,50'), 10.5);
    });

    test('accepts the Arabic comma separator', () {
      expect(NumberUtils.tryParseLocale('10،50'), 10.5);
    });

    test('parses Arabic-Indic digits', () {
      expect(NumberUtils.tryParseLocale('١٢٣'), 123);
      expect(NumberUtils.tryParseLocale('١٠٫٥'), 10.5); // arabic decimal mark
    });

    test('returns null for empty / non-numeric', () {
      expect(NumberUtils.tryParseLocale(''), isNull);
      expect(NumberUtils.tryParseLocale(null), isNull);
      expect(NumberUtils.tryParseLocale('abc'), isNull);
    });

    test('negative with comma decimal', () {
      expect(NumberUtils.tryParseLocale('-5,5'), -5.5);
    });

    // Documented contract (Spec 137 follow-up): comma is ALWAYS the decimal
    // separator (Arabic locale). Thousands grouping is NOT supported — '1,000'
    // means 1.0, not 1000 — and any input with more than one separator is
    // rejected (null) rather than silently mis-parsed.
    test('comma is decimal, not a thousands separator', () {
      expect(NumberUtils.tryParseLocale('1,000'), 1.0);
    });

    test('ambiguous mixed separators are rejected (null)', () {
      expect(NumberUtils.tryParseLocale('1.234,5'), isNull);
      expect(NumberUtils.tryParseLocale('1,234.5'), isNull);
    });
  });
}
