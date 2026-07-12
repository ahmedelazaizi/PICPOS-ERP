import 'package:flutter/material.dart';

/// Guards every PDF print path with a non-dismissible loading overlay.
///
/// ## Why PDF generation is synchronous (by design)
///
/// `pdf.save()` and the pw.Document page-build closures reference Flutter font
/// data loaded into the main isolate.  Moving the work to a background isolate
/// requires deep-copying those font objects across the isolate boundary, which
/// reliably corrupts Arabic glyphs (rendered as ■■■).
///
/// As a result **ALL PDF generation runs on the main thread**, which means the
/// UI is blocked for the 1-3 s the render takes.  Without feedback the user
/// cannot tell if the tap registered.
///
/// ## What this guard does
///
/// 1. Shows a non-dismissible dialog with a [CircularProgressIndicator] and the
///    message "جاري إنشاء الملف…" (file is being prepared).
/// 2. Calls [action] — the synchronous-on-main-thread PDF pipeline.
/// 3. Pops the dialog and propagates any exception to the caller.
///
/// ## Usage
///
/// ```dart
/// // Before (no feedback):
/// await InvoiceGenerator.printSalesReport(...);
///
/// // After (with loading overlay):
/// await PdfPrintGuard.run(context, () async {
///   await InvoiceGenerator.printSalesReport(...);
/// });
/// ```
///
/// ## Tested paths (ISS-PERF-01 audit — 2026-04-24)
///
/// | Screen                          | Method              | Status            |
/// |---------------------------------|---------------------|-------------------|
/// | POS                             | printInvoice        | via PrintingService.printReceipt |
/// | Sales report                    | _printReport        | uses InvoiceGenerator |
/// | Purchases report                | _printReport        | uses InvoiceGenerator |
/// | Inventory report                | _printReport        | uses InvoiceGenerator |
/// | Treasury closing                | _printReport        | uses InvoiceGenerator |
/// | Financial statements            | _printReport        | uses InvoiceGenerator |
/// | Shifts report                   | _printReport        | uses InvoiceGenerator |
/// | Sales returns report            | _printReport        | uses InvoiceGenerator |
/// | Purchase returns report         | _printReport        | uses InvoiceGenerator |
/// | Sales by classification report  | _printReport        | uses InvoiceGenerator |
/// | Purchase invoice details        | printInvoice        | uses InvoiceGenerator |
///
/// All paths use [PdfComputeHelper.layoutPdf] internally, which calls
/// `pdf.save()` on the main thread and then hands the bytes to the native
/// [printing.Printing.layoutPdf] dialog.
class PdfPrintGuard {
  PdfPrintGuard._();

  /// Run [action] under a loading overlay anchored to [context].
  ///
  /// The overlay is removed whether [action] completes normally or throws.
  /// Any exception is re-thrown after the dialog is dismissed so the caller
  /// can show an appropriate error toast.
  static Future<void> run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    // Show the non-dismissible loading dialog.
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _PdfLoadingDialog(),
    );

    try {
      await action();
    } finally {
      // Always pop — even if action throws.
      if (navigator.canPop()) navigator.pop();
    }
  }
}

class _PdfLoadingDialog extends StatelessWidget {
  const _PdfLoadingDialog();

  @override
  Widget build(BuildContext context) {
    return const AlertDialog(
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Text('جاري إنشاء الملف…'),
        ],
      ),
    );
  }
}
