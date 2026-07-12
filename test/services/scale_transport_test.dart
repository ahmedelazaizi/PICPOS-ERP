import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/services/scale_transport.dart';

void main() {
  late ScaleTransport transport;

  setUp(() {
    transport = ScaleTransport();
  });

  // ═══════════════════════════════════════════════════════════════
  // CP1256 Encoding
  // ═══════════════════════════════════════════════════════════════

  group('CP1256 Encoding', () {
    test('ASCII characters pass through unchanged', () {
      final result = transport.encodeCP1256('Hello 123');
      expect(result, equals(Uint8List.fromList(
        [0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x20, 0x31, 0x32, 0x33],
      )));
    });

    test('empty string returns empty bytes', () {
      final result = transport.encodeCP1256('');
      expect(result, isEmpty);
    });

    test('Arabic Alif (ا = U+0627) maps to 0xC7', () {
      final result = transport.encodeCP1256('ا');
      expect(result.length, 1);
      expect(result[0], 0xC7);
    });

    test('Arabic Ba (ب = U+0628) maps to 0xC8', () {
      final result = transport.encodeCP1256('ب');
      expect(result.length, 1);
      expect(result[0], 0xC8);
    });

    test('Arabic common letters map correctly', () {
      // F-PLU-1: authoritative CP1256 — Latin-1 interleaves among the letters.
      // م (Meem) = U+0645 → 0xE3
      // و (Waw)  = U+0648 → 0xE6
      // ز (Zay)  = U+0632 → 0xD2 (before the interleave, unchanged)
      final result = transport.encodeCP1256('موز');
      expect(result.length, 3);
      expect(result[0], 0xE3); // م
      expect(result[1], 0xE6); // و
      expect(result[2], 0xD2); // ز
    });

    test('Arabic Fa (ف = U+0641) maps to 0xDD', () {
      final result = transport.encodeCP1256('ف');
      expect(result[0], 0xDD);
    });

    test('Arabic Ya (ي = U+064A) maps to 0xEA', () {
      final result = transport.encodeCP1256('ي');
      expect(result[0], 0xEA);
    });

    test('Arabic Lam (ل = U+0644) maps to 0xE1', () {
      final result = transport.encodeCP1256('ل');
      expect(result[0], 0xE1);
    });

    test('Arabic Noon (ن = U+0646) maps to 0xE4', () {
      final result = transport.encodeCP1256('ن');
      expect(result[0], 0xE4);
    });

    test('Arabic Ha (ه = U+0647) maps to 0xE5', () {
      final result = transport.encodeCP1256('ه');
      expect(result[0], 0xE5);
    });

    test('Arabic diacritics map correctly', () {
      // F-PLU-1 authoritative CP1256:
      // Fatha  (U+064E) → 0xEF ;  Shadda (U+0651) → 0xF3
      final fatha = transport.encodeCP1256('\u064E');
      expect(fatha[0], 0xEF); // F-PLU-1: was 0xE9
      final shadda = transport.encodeCP1256('\u0651');
      expect(shadda[0], 0xF3); // F-PLU-1: was 0xEC
    });

    test('unmapped characters become ? (0x3F)', () {
      final result = transport.encodeCP1256('中');
      expect(result[0], 0x3F);
    });

    test('mixed Arabic-Latin string', () {
      final result = transport.encodeCP1256('ABC دجاج');
      // A=0x41, B=0x42, C=0x43, space=0x20
      // د=0xCF, ج=0xCC, ا=0xC7, ج=0xCC
      expect(result[0], 0x41);
      expect(result[3], 0x20);
      expect(result[4], 0xCF); // د
      expect(result[5], 0xCC); // ج
      expect(result[6], 0xC7); // ا
      expect(result[7], 0xCC); // ج
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // UTF-16 LE Encoding
  // ═══════════════════════════════════════════════════════════════

  group('UTF-16 LE Encoding', () {
    test('starts with BOM (FF FE)', () {
      final result = transport.encodeUtf16LE('A');
      expect(result[0], 0xFF);
      expect(result[1], 0xFE);
    });

    test('ASCII A encodes as 41 00', () {
      final result = transport.encodeUtf16LE('A');
      expect(result[2], 0x41);
      expect(result[3], 0x00);
    });

    test('empty string returns just BOM', () {
      final result = transport.encodeUtf16LE('');
      expect(result.length, 2); // just BOM
      expect(result[0], 0xFF);
      expect(result[1], 0xFE);
    });

    test('Arabic Alif (U+0627) encodes as 27 06', () {
      final result = transport.encodeUtf16LE('ا');
      expect(result[2], 0x27);
      expect(result[3], 0x06);
    });

    test('multi-char string has correct length', () {
      final result = transport.encodeUtf16LE('Hello');
      // BOM(2) + 5 chars * 2 bytes = 12
      expect(result.length, 12);
    });

    test('tab character encodes as 09 00', () {
      final result = transport.encodeUtf16LE('\t');
      expect(result[2], 0x09);
      expect(result[3], 0x00);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Arabic Text Reversal
  // ═══════════════════════════════════════════════════════════════

  group('reverseArabicForScale', () {
    test('empty string returns empty', () {
      expect(ScaleTransport.reverseArabicForScale(''), '');
    });

    test('pure ASCII stays unchanged', () {
      expect(ScaleTransport.reverseArabicForScale('Hello'), 'Hello');
    });

    test('pure Arabic is reversed', () {
      // "موز" should become "زوم" for visual LTR display
      final result = ScaleTransport.reverseArabicForScale('موز');
      expect(result, 'زوم');
    });

    test('single Arabic char stays the same', () {
      expect(ScaleTransport.reverseArabicForScale('م'), 'م');
    });

    test('longer Arabic word is reversed', () {
      // "دجاج" (d-j-a-j) → "جاجد" for visual LTR
      final result = ScaleTransport.reverseArabicForScale('دجاج');
      expect(result, 'جاجد');
    });

    test('Arabic with numbers: Arabic reversed, digits preserved', () {
      // "لحم 500g" — Arabic "لحم " reversed, "500g" preserved
      final result = ScaleTransport.reverseArabicForScale('لحم 500g');
      // Arabic run "لحم " reversed = " محل", then "500g"
      expect(result, contains('500g'));
    });

    test('digits-only string stays unchanged', () {
      expect(ScaleTransport.reverseArabicForScale('12345'), '12345');
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // padRight Utility
  // ═══════════════════════════════════════════════════════════════

  group('padRight', () {
    test('pads short string', () {
      expect(transport.padRight('Hi', 5), 'Hi   ');
    });

    test('truncates long string', () {
      expect(transport.padRight('Hello World', 5), 'Hello');
    });

    test('exact length stays same', () {
      expect(transport.padRight('Hello', 5), 'Hello');
    });
  });
}
