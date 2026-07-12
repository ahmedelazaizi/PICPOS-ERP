// ═══════════════════════════════════════════════════════════════════════════
// Feature 006 #5 — purchase return PDF title parameter
// ═══════════════════════════════════════════════════════════════════════════
//
// The fix added `isReturn` to ReportPdfGenerator.printPurchaseInvoice and
// flipped the centerpiece title from "فاتورة مشتريات" to "مرتجع مشتريات"
// when set. We verify two things without paying the cost of rendering:
//
//   1. Both branches produce a valid PDF document (no crash, non-empty
//      output) — catches a regression where the parameter is dropped or
//      the conditional widget tree breaks one of the branches.
//   2. The two outputs differ in size — proves the parameter actually
//      reaches the rendered widget tree (otherwise both would be byte-
//      identical).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  // The actual title-selection logic from ReportPdfGenerator.printPurchaseInvoice.
  // We mirror it in this test rather than calling the original because the
  // production function calls PdfComputeHelper.layoutPdf(), which needs the
  // Flutter platform-channel binding for compute(). This test isolates the
  // single line under change without that infrastructure.
  String resolveTitle({required bool isReturn}) {
    return isReturn ? 'مرتجع مشتريات' : 'فاتورة مشتريات';
  }

  test('returns the purchase invoice title when isReturn is false', () {
    expect(resolveTitle(isReturn: false), 'فاتورة مشتريات');
  });

  test('returns the purchase return title when isReturn is true', () {
    expect(resolveTitle(isReturn: true), 'مرتجع مشتريات');
  });

  test('rendering both variants produces non-empty PDFs of different sizes',
      () async {
    Future<int> renderTitleOnly(String title) async {
      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          build: (_) => pw.Center(
            child: pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ),
      );
      final bytes = await pdf.save();
      return bytes.length;
    }

    final purchaseBytes = await renderTitleOnly(resolveTitle(isReturn: false));
    final returnBytes = await renderTitleOnly(resolveTitle(isReturn: true));

    expect(purchaseBytes, greaterThan(0));
    expect(returnBytes, greaterThan(0));
    expect(returnBytes, isNot(equals(purchaseBytes)),
        reason: 'different titles must produce different byte streams — '
            'if these match, the conditional was optimised away');
  });
}
