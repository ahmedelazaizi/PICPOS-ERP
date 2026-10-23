// F-PLU-1 (HIGH-1, R1) — encodeCP1256 assumed Arabic letters are contiguous
// from ط (U+0637) onward. Windows-1256 actually interleaves Latin-1 bytes
// (× at 0xD7, à at 0xE0, â at 0xE2, ç/è at 0xE7/0xE8, ë at 0xEB), so every
// letter from ط on was encoded one-or-more bytes low, corrupting Arabic PLU
// names on the scale LCD.
//
// These are the authoritative CP1256 byte values (Unicode.org CP1256.TXT).
// NOTE: byte-correctness is verified here; end-to-end display still needs a
// real CAS/DIGI/Dibal scale (R1 — needs on-device verification).

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/scale_transport.dart';

void main() {
  final t = ScaleTransport();

  test('encodeCP1256 uses the authoritative table from ط onward (F-PLU-1)', () {
    // ط ظ ع غ  — the interleave starts here (× occupies 0xD7).
    expect(t.encodeCP1256('طظعغ'), [0xD8, 0xD9, 0xDA, 0xDB]);

    // ف ق ك ل م ن ه و ي — the letters the audit called out.
    expect(t.encodeCP1256('فقكلمنهوي'),
        [0xDD, 0xDE, 0xDF, 0xE1, 0xE3, 0xE4, 0xE5, 0xE6, 0xEA]);
  });

  test('letters before the interleave (≤ ض) are unchanged', () {
    // ب ت س ص ض  — contiguous region, already correct.
    expect(t.encodeCP1256('بتسصض'), [0xC8, 0xCA, 0xD3, 0xD5, 0xD6]);
  });
}
