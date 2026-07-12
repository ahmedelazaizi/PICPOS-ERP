// Spec 136 (field 2026-06-10) — robust numeric parsing for Excel product
// import. Bulk import was dropping the cost of rows whose cost cell held
// Arabic-Indic digits, thousands separators, currency text, or European
// decimals — double.tryParse returned null and silently became 0. These cases
// lock the normaliser that fixes it.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/services/excel_service.dart';

void main() {
  num? p(String s) => ExcelService.normalizeNumericString(s);

  group('normalizeNumericString', () {
    test('plain numbers still parse', () {
      expect(p('1500'), 1500);
      expect(p('12.5'), 12.5);
      expect(p(' 12.5 '), 12.5); // surrounding whitespace
      expect(p('0'), 0);
    });

    test('Arabic-Indic digits', () {
      expect(p('١٢٣٤'), 1234); // ٠-٩
      expect(p('١٢٫٥'), 12.5); // Arabic decimal separator ٫
      expect(p('۱۲۳'), 123); // Extended Arabic-Indic ۰-۹
    });

    test('thousands separators (English grouping)', () {
      expect(p('1,500'), 1500);
      expect(p('1,234,567'), 1234567);
      expect(p('1,234.56'), 1234.56); // comma group + dot decimal
    });

    test('Arabic thousands separator ٬', () {
      expect(p('1٬500'), 1500);
    });

    test('European decimals', () {
      expect(p('12,5'), 12.5); // comma as decimal
      expect(p('1.234,56'), 1234.56); // dot group + comma decimal
    });

    test('currency / stray text is stripped', () {
      expect(p('1500 ج.م'), 1500);
      expect(p(r'$ 1,250.75'), 1250.75);
      expect(p('1500EGP'), 1500);
    });

    test('non-breaking / thin spaces as grouping', () {
      expect(p('1 500'), 1500); // NBSP
      expect(p('1 500'), 1500); // thin space
    });

    test('blank / non-numeric returns null (caller defaults to 0)', () {
      expect(p(''), isNull);
      expect(p('   '), isNull);
      expect(p('-'), isNull);
      expect(p('abc'), isNull);
    });

    test('formula strings cannot be evaluated → null (not a wrong number)', () {
      // The excel package does not evaluate formulas; we must not invent a value.
      expect(p('B2*1.1'), isNull);
      expect(p('=SUM(A1:A3)'), isNull);
    });
  });
}
