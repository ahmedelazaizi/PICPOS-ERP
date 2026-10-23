import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/utils/phone_normalizer.dart';

void main() {
  group('normalizePhone', () {
    test('formats of the same Egyptian mobile give one key', () {
      const variants = [
        '01012345678',
        '+20 101 234 5678',
        '0020 101-234-5678',
        '+20 (0) 1012345678',
        '201012345678',
        '١٠١٢٣٤٥٦٧٨', // Arabic-Indic digits, no zero
        '٠١٠١٢٣٤٥٦٧٨',
      ];
      for (final v in variants) {
        expect(normalizePhone(v), '1012345678', reason: v);
      }
    });

    test('Jordan / KSA numbers lose country code and trunk zero', () {
      expect(normalizePhone('0791234567'), '791234567');
      expect(normalizePhone('+962 79 123 4567'), '791234567');
      expect(normalizePhone('00962791234567'), '791234567');
      expect(normalizePhone('+966 50 123 4567'), '501234567');
    });

    test('a short local number starting with a country code is NOT stripped', () {
      // 20xxxxxxx (9 digits) is a local number, not +20.
      expect(normalizePhone('201234567'), '201234567');
    });

    test('empty / junk / too short is not a phone', () {
      expect(normalizePhone(null), '');
      expect(normalizePhone(''), '');
      expect(normalizePhone('abc'), '');
      expect(normalizePhone('12345'), '');
      expect(normalizePhone('+'), '');
    });

    test('phoneTail9 keeps the last nine digits', () {
      expect(phoneTail9('+20 101 234 5678'), '012345678');
      expect(phoneTail9('0791234567'), '791234567');
    });

    test('samePhone is formatting-insensitive and false for empty', () {
      expect(samePhone('0101 234 5678', '+201012345678'), isTrue);
      expect(samePhone('0101 234 5678', '+201112345678'), isFalse);
      expect(samePhone('', ''), isFalse);
      expect(samePhone(null, '01012345678'), isFalse);
    });
  });

  group('normalizePersonName', () {
    test('trims, collapses spaces, lowercases, drops tashkeel and tatweel', () {
      expect(normalizePersonName('  أحمـد   عَلي '), 'أحمد علي');
      expect(normalizePersonName('Ahmed   ALI'), 'ahmed ali');
      expect(normalizePersonName(null), '');
    });

    test('does not merge different Arabic spellings (exact match only)', () {
      expect(normalizePersonName('احمد'), isNot(normalizePersonName('أحمد')));
    });
  });
}
