// Spec 133 / FR-012 — Cheque receipt voucher symmetry guard.
//
// The double-credit bug (field-confirmed on build 3.1.0+202) was rooted
// in an asymmetry between the receipt-voucher pipeline and the
// payment-voucher pipeline: createPaymentVoucher accepted skipJournalEntry
// / skipSafeTransaction + the wire carried paperType, while
// createReceiptVoucher and its wire path did not. Result: a cheque
// receipt produced two customer-credit JEs (one from the voucher path,
// one from the commercial-papers autopost).
//
// This grep-style test pins the symmetry: any future regression that
// removes `paperType` from the client interceptor, the server proxy, or
// the server-side `postReceipt` handler will fail this test before it
// ships. Mirrors the orchestrator_gate_predicate_test.dart pattern.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Cheque receipt symmetry guard (Spec 133 / FR-012)', () {
    test(
      'cwi_commerce.dart::createReceipt accepts paperType and forwards it',
      () {
        final source = File('lib/services/interceptor/cwi_commerce.dart')
            .readAsStringSync();

        // The method exists.
        expect(
          source,
          contains('static Future<int?> createReceipt('),
          reason: 'createReceipt method must remain on _CwiCommerce. '
              'Spec 133 routes the cheque indicator through it.',
        );

        // The signature accepts paperType.
        // ISS-26 (#4) inserted a ~150-line local-cache block into
        // createReceipt, pushing the payload literal and serverCall forward
        // for paperType past the old 4000-char window. 7000 covers them.
        final sigRegion = _regionAfter(source, 'static Future<int?> createReceipt(', 7000);
        expect(
          sigRegion,
          contains('String? paperType'),
          reason: 'createReceipt must accept `String? paperType` so the '
              'dialog can flag cheque receipts. Spec 133 Commit B added '
              'this; mirror createExpense which already has it.',
        );

        // The payload carries paperType (non-null, non-empty).
        expect(
          sigRegion,
          contains("'paperType': paperType"),
          reason: 'createReceipt must include paperType in the _tryOrQueue '
              'payload so outbox replays carry the cheque flag.',
        );

        // The serverCall forwards paperType.
        expect(
          sigRegion,
          contains('paperType: paperType'),
          reason: 'createReceipt must forward paperType to '
              '_proxy.submitReceipt — otherwise the wire reaches the server '
              'with paperType=null and the duplicate JE bug returns.',
        );
      },
    );

    test(
      'server_proxy.dart::submitReceipt accepts paperType and sends it on the wire',
      () {
        final source =
            File('lib/services/server_proxy.dart').readAsStringSync();

        expect(
          source,
          contains('Future<int?> submitReceipt('),
          reason: 'submitReceipt must remain on ServerProxy.',
        );

        final sigRegion = _regionAfter(source, 'Future<int?> submitReceipt(', 3000);
        expect(
          sigRegion,
          contains('String? paperType'),
          reason: 'submitReceipt must accept paperType (Spec 133 Commit B).',
        );

        expect(
          sigRegion,
          contains("'paperType': paperType"),
          reason: 'submitReceipt must include paperType in the POST '
              '/api/receipts JSON body. Same shape as submitExpense '
              'established for Spec 081.',
        );
      },
    );

    test(
      'api_data_handler.dart::postReceipt reads paperType and computes the skip flag',
      () {
        final source = File('lib/services/api/api_data_handler.dart')
            .readAsStringSync();

        expect(
          source,
          contains('postReceipt'),
          reason: 'postReceipt endpoint handler must exist on _ApiDataHandler.',
        );

        // Locate the postReceipt method body and search within it.
        final methodStart = source.indexOf('Future<Response> postReceipt(');
        expect(methodStart, greaterThan(-1),
            reason: 'postReceipt method signature must exist.');
        final methodRegion = source.substring(
          methodStart,
          (methodStart + 8000).clamp(0, source.length),
        );

        expect(
          methodRegion,
          contains("data['paperType']"),
          reason: 'postReceipt must read paperType from the request body. '
              'Without this, the server cannot skip the cash-leg JE for '
              'cheque receipts and the duplicate JE bug returns server-side.',
        );

        expect(
          methodRegion,
          contains('skipJournalEntry'),
          reason: 'postReceipt must pass skipJournalEntry to '
              'db.createReceiptVoucher when the receipt is a cheque.',
        );

        expect(
          methodRegion,
          contains('skipSafeTransaction'),
          reason: 'postReceipt must pass skipSafeTransaction to '
              'db.createReceiptVoucher when the receipt is a cheque.',
        );
      },
    );

    test(
      'treasury_dao.dart::createReceiptVoucher exposes skipJournalEntry + skipSafeTransaction',
      () {
        final source = File('lib/data/database/daos/treasury_voucher_dao.dart')
            .readAsStringSync();

        final methodStart =
            source.indexOf('Future<int> createReceiptVoucher(');
        expect(methodStart, greaterThan(-1),
            reason: 'createReceiptVoucher must exist on the DAO.');
        final sigRegion = source.substring(
          methodStart,
          (methodStart + 2000).clamp(0, source.length),
        );

        expect(
          sigRegion,
          contains('bool skipJournalEntry'),
          reason: 'createReceiptVoucher must accept skipJournalEntry — '
              'symmetric with createPaymentVoucher (Spec 081). Spec 133 '
              'depends on the caller (repo + server handler) passing this '
              'true for cheque receipts.',
        );

        expect(
          sigRegion,
          contains('bool skipSafeTransaction'),
          reason: 'createReceiptVoucher must accept skipSafeTransaction.',
        );
      },
    );

    test(
      'treasury_repository_impl.dart::createReceiptVoucher detects isCheckPayment',
      () {
        final source =
            File('lib/data/repositories/treasury_repository_impl.dart')
                .readAsStringSync();

        // Find the createReceiptVoucher impl (not the createPaymentVoucher
        // one) by anchoring on the override annotation that precedes it.
        final methodStart =
            source.indexOf('Future<int> createReceiptVoucher(');
        expect(methodStart, greaterThan(-1));
        final methodRegion = source.substring(
          methodStart,
          (methodStart + 3000).clamp(0, source.length),
        );

        expect(
          methodRegion,
          contains("paperType == 'cheque'"),
          reason: 'repo createReceiptVoucher must derive isCheckPayment '
              "from paperType. Spec 133 Commit A's contract.",
        );

        expect(
          methodRegion,
          contains('skipJournalEntry: isCheckPayment'),
          reason: 'repo createReceiptVoucher must pass isCheckPayment '
              'into the DAO skip flag.',
        );

        expect(
          methodRegion,
          contains('skipSafeTransaction: isCheckPayment'),
          reason: 'repo createReceiptVoucher must pass isCheckPayment '
              'into the DAO skip flag.',
        );
      },
    );

    test(
      'receipt_voucher_dialog.dart runs the FR-013 pre-flight before any write',
      () {
        final source = File(
                'lib/presentation/treasury/widgets/receipt_voucher_dialog.dart')
            .readAsStringSync();

        expect(
          source,
          contains('ChequeReceiptPreflight.validate'),
          reason: 'dialog must call ChequeReceiptPreflight.validate before '
              'any write so the operator gets a clear Arabic message when '
              'Notes Receivable or the customer sub-account is unmapped, '
              'instead of a silent zero-credit. FR-013.',
        );

        expect(
          source,
          contains("paperType: paymentMethod == 'check' ? 'cheque' : null"),
          reason: 'dialog must thread paperType into '
              'ClientWriteInterceptor.createReceipt for the cheque path. '
              'Without this the wire carries paperType=null and the bug '
              'returns end-to-end.',
        );
      },
    );
  });
}

/// Return a substring of [source] starting at the first occurrence of
/// [needle] and extending up to [length] characters. Used to scope each
/// assertion to one method body so a marker reappearing in a different
/// neighboring method doesn't accidentally satisfy the test.
String _regionAfter(String source, String needle, int length) {
  final idx = source.indexOf(needle);
  if (idx < 0) return '';
  final end = (idx + length).clamp(0, source.length);
  return source.substring(idx, end);
}
