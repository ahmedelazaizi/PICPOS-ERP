// ═══════════════════════════════════════════════════════════════════════════
// SPEC 085 — Cancel-dialog mounted guard (sales invoice)
// ═══════════════════════════════════════════════════════════════════════════
//
// Pins:
//   1. The cancel handler uses `if (!mounted) return;` after the async
//      UnsavedChangesDialog.show() call. State.mounted is null-safe;
//      State.context (via context.mounted) is not.
//   2. The buggy pattern `if (context.mounted) Navigator.of(context).pop();`
//      must not return — it crashes with "Null check operator used on a
//      null value" when the parent State is disposed during the await
//      (field bug from mirror smoke V148, 20 crashes in 30 seconds).
//
// Spec 090 (2026-05-23) moved the cancel logic out of the inline dialog
// in `sales_invoice_dialogs.dart` and into `_handleCancel()` on the
// extracted SalesInvoiceForm widget. The invariant pinned here travels
// with that helper — see `sales_invoice_form.dart`.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Spec 085 — cancel-handler mounted guard (post Spec 090)', () {
    late String formSrc;
    late String dialogsSrc;

    setUpAll(() {
      formSrc = File(
        'lib/presentation/screens/widgets/sales_invoices/sales_invoice_form.dart',
      ).readAsStringSync();
      dialogsSrc = File(
        'lib/presentation/screens/widgets/sales_invoices/sales_invoice_dialogs.dart',
      ).readAsStringSync();
    });

    test('_handleCancel guards Navigator.pop with State.mounted', () {
      final fnStart = formSrc.indexOf('Future<void> _handleCancel()');
      expect(
        fnStart,
        isNot(-1),
        reason: '_handleCancel signature moved or renamed in '
            'sales_invoice_form.dart — update this pin to match.',
      );

      // Spec 090 added DiagnosticLogger breadcrumbs inside _handleCancel, so
      // the helper body grew and the !mounted guard now sits further down (and
      // is a block form, not a one-liner). 900 chars covers the expanded body.
      final body =
          formSrc.substring(fnStart, (fnStart + 900).clamp(0, formSrc.length));

      expect(
        body,
        contains('if (!mounted) {'),
        reason: '_handleCancel must guard the post-await Navigator.pop '
            'with State.mounted (null-safe). context.mounted is NOT safe — '
            'it accesses State.context which throws on disposed State.',
      );
    });

    test('buggy context.mounted pattern is gone from form + dialogs', () {
      for (final src in [formSrc, dialogsSrc]) {
        expect(
          src.contains('if (context.mounted) Navigator.of(context).pop()'),
          isFalse,
          reason: 'Field-reproducible crash: State.context getter does '
              '`_element!` in release builds. If _element is null after the '
              'State is disposed during an async gap, evaluating '
              '`context.mounted` throws "Null check operator used on a null '
              'value" before .mounted is ever read. Use !mounted instead.',
        );
      }
    });

    test('Spec 090 — sales-invoice dialog no longer uses PopScope or StatefulBuilder', () {
      // The whole point of Spec 090: the new form does its own setState
      // and exposes an explicit Cancel button — no PopScope re-entry,
      // no StatefulBuilder rebuild storms, no AlertDialog 800x650 freeze.
      // Match constructor invocation (`Foo(`) so the explanatory comments
      // in the file don't trigger false positives.
      expect(
        dialogsSrc.contains('PopScope('),
        isFalse,
        reason: 'Spec 090 removed PopScope from _createNewInvoice. The '
            'cancel guard lives in SalesInvoiceForm._handleCancel.',
      );
      expect(
        dialogsSrc.contains('StatefulBuilder('),
        isFalse,
        reason: 'Spec 090 removed StatefulBuilder from _createNewInvoice. '
            'SalesInvoiceForm is a real ConsumerStatefulWidget.',
      );
    });
  });
}
