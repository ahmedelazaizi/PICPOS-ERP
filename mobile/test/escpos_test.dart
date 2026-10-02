import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_van/printing/escpos.dart';
import 'package:picpos_van/printing/receipt_model.dart';
import 'package:picpos_van/printing/receipt_renderer.dart';

/// White RGBA image with black pixels where [black] says so.
Uint8List rgba(int w, int h, bool Function(int x, int y) black) {
  final b = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      final v = black(x, y) ? 0 : 255;
      b
        ..[i] = v
        ..[i + 1] = v
        ..[i + 2] = v
        ..[i + 3] = 255;
    }
  }
  return b;
}

/// Offsets of `GS v 0` headers in [bytes].
List<int> gsv0(List<int> bytes) => [
      for (var i = 0; i + 3 < bytes.length; i++)
        if (bytes[i] == 0x1D && bytes[i + 1] == 0x76 && bytes[i + 2] == 0x30) i,
    ];

void main() {
  test('monochrome packs MSB first, 1 = black; transparent counts as white', () {
    final bmp = monochrome(rgba(10, 2, (x, y) => (x == 0 && y == 0) || (x == 9 && y == 1)), 10, 2);
    expect(bmp.widthBytes, 2);
    expect(bmp.data, [0x80, 0x00, 0x00, 0x40]);
    expect(bmp.isBlack(0, 0), isTrue);
    expect(bmp.isBlack(9, 1), isTrue);
    expect(bmp.isBlack(1, 0), isFalse);
    final clear = Uint8List(8 * 4); // alpha 0 everywhere
    expect(monochrome(clear, 8, 1).data, [0]);
  });

  for (final paper in PaperWidth.values) {
    test('GS v 0 header for ${paper.name}: ${paper.dots} dots = ${paper.dots ~/ 8} bytes per row', () {
      final bmp = monochrome(rgba(paper.dots, 10, (x, y) => x < 8), paper.dots, 10);
      final job = EscPos.job(bmp);
      expect(job.sublist(0, 2), EscPos.init);
      expect(job.sublist(2, 10), [0x1D, 0x76, 0x30, 0x00, paper.dots ~/ 8, 0, 10, 0]);
      expect(job[10], 0xFF, reason: 'first 8 dots black');
      expect(job.length, 2 + 8 + (paper.dots ~/ 8) * 10 + 3 + 4);
      expect(job.sublist(job.length - 4), EscPos.cut);
    });
  }

  test('tall images are split into bands (printer buffer limit)', () {
    final bmp = monochrome(rgba(384, 300, (x, y) => false), 384, 300);
    final bytes = EscPos.raster(bmp, maxBandRows: 256);
    final at = gsv0(bytes);
    expect(at, [0, 8 + 48 * 256]);
    expect(bytes.sublist(6, 8), [0x00, 0x01]); // 256 rows
    expect(bytes.sublist(at[1] + 6, at[1] + 8), [44, 0]); // 300 - 256
  });

  for (final paper in PaperWidth.values) {
    testWidgets('rasterized receipt is exactly ${paper.dots} dots wide (${paper.name})', (tester) async {
      final receipt = ReceiptBuilder(const ReceiptCompany(nameAr: 'شركة الوادي', taxNumber: '123', commercialRegister: '9'))
          .salesInvoice(
        globalId: 'g',
        number: 'VS-100000',
        date: DateTime(2026, 5, 1),
        party: const ReceiptParty(customerName: 'بقالة', repName: 'مندوب'),
        lines: const [ReceiptLineData(name: 'مياه', quantity: 2, unitPrice: 2.5, total: 5.8)],
        net: 5,
        tax: 0.8,
        total: 5.8,
        paid: 5.8,
      );
      final (w, h, bytes) = (await tester.runAsync(() async {
        final img = await renderReceipt(receipt, paper);
        final out = (img.width, img.height, await rasterizeReceipt(receipt, paper));
        img.dispose();
        return out;
      }))!;
      expect(w, paper.dots);
      expect(h, greaterThan(300));
      expect(bytes.sublist(0, 2), EscPos.init);
      final at = gsv0(bytes);
      expect(at.first, 2);
      expect(bytes[at.first + 4], paper.dots ~/ 8);
      expect(bytes[at.first + 5], 0);
      final rows = [for (final i in at) bytes[i + 6] | (bytes[i + 7] << 8)].reduce((a, b) => a + b);
      expect(rows, h);
      // Something was drawn (identity text, barcode, QR).
      final black = bytes.skip(10).where((b) => b != 0).length;
      expect(black, greaterThan(500));
    });
  }
}
