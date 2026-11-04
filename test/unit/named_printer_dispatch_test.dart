import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:printing/printing.dart';
import 'package:picpos_erp/services/printing/pdf_compute_helper.dart';

void main() {
  tearDown(() => PdfComputeHelper.directPrintOverride = null);

  test(
    'direct print sends the PDF bytes to the selected named printer',
    () async {
      final printer = Printer(
        name: 'Microsoft Print to PDF',
        url: 'winspool://Microsoft%20Print%20to%20PDF',
      );
      final bytes = Uint8List.fromList([0x25, 0x50, 0x44, 0x46]);
      Printer? receivedPrinter;
      Uint8List? receivedBytes;

      PdfComputeHelper.directPrintOverride = (target, data) async {
        receivedPrinter = target;
        receivedBytes = data;
        return true;
      };

      expect(
        await PdfComputeHelper.directPrintBytes(printer: printer, bytes: bytes),
        isTrue,
      );
      expect(receivedPrinter, same(printer));
      expect(receivedPrinter!.name, 'Microsoft Print to PDF');
      expect(receivedBytes, orderedEquals(bytes));
    },
  );

  test('direct print propagates a native queue rejection', () async {
    PdfComputeHelper.directPrintOverride = (_, _) async => false;

    expect(
      await PdfComputeHelper.directPrintBytes(
        printer: Printer(name: 'Unavailable queue', url: 'winspool://missing'),
        bytes: Uint8List.fromList([0x25, 0x50, 0x44, 0x46]),
      ),
      isFalse,
    );
  });
}
