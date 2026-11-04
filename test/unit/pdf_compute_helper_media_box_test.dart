import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:picpos_erp/services/printing/pdf_compute_helper.dart';
import 'package:printing/printing.dart';

import '../helpers/pdf_probe.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    PdfComputeHelper.directPrintOverride = null;
    PdfComputeHelper.nativeLayoutOverride = null;
    PdfComputeHelper.lastRequestedFormat = null;
  });

  test(
    'injected print adapters receive the saved PDF MediaBox format',
    () async {
      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          pageFormat: const PdfPageFormat(
            80 * PdfPageFormat.mm,
            double.infinity,
            marginAll: 4 * PdfPageFormat.mm,
          ),
          build: (_) => pw.SizedBox(width: 30, height: 24),
        ),
      );
      final output = await PdfComputeHelper.saveToBytesWithMediaBox(pdf);
      final mediaBox = probePdf(output.bytes).pages.single;

      expect(output.format.width, closeTo(mediaBox.widthPts, 0.01));
      expect(output.format.height, closeTo(mediaBox.heightPts, 0.01));

      PdfComputeHelper.directPrintOverride = (_, _) async => true;
      await PdfComputeHelper.directPrintDocument(
        printer: Printer(name: 'Test printer', url: 'test://printer'),
        pdf: pdf,
      );
      expect(
        PdfComputeHelper.lastRequestedFormat!.width,
        closeTo(mediaBox.widthPts, 0.01),
      );
      expect(
        PdfComputeHelper.lastRequestedFormat!.height,
        closeTo(mediaBox.heightPts, 0.01),
      );

      PdfComputeHelper.nativeLayoutOverride = (_, _) async => true;
      await PdfComputeHelper.layoutPdfWithMediaBox(pdf);
      expect(
        PdfComputeHelper.lastRequestedFormat!.width,
        closeTo(mediaBox.widthPts, 0.01),
      );
      expect(
        PdfComputeHelper.lastRequestedFormat!.height,
        closeTo(mediaBox.heightPts, 0.01),
      );
    },
  );
}
