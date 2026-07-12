// ═══════════════════════════════════════════════════════════════════════════
// SPEC 087 — partyId end-to-end on submitSafeTransaction (source pins)
// ═══════════════════════════════════════════════════════════════════════════
//
// The user-visible field bug: receipt/payment vouchers don't appear
// in the customer/supplier statement. Root cause: the generic
// /api/safes/transaction endpoint and its caller chain silently
// dropped partyId, so the server's safe_transactions row had
// party_id=NULL even when the operator picked a party in the dialog.
//
// These pins are source-grep checks because the end-to-end flow
// crosses HTTP boundaries that are awkward to wire up in a unit
// test. The cross-mode smoke checklist exercises the actual data
// path.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Spec 087 — partyId end-to-end on submitSafeTransaction', () {
    test('SyncInterceptor.submitSafeTransaction interface has partyId params',
        () {
      final src =
          File('lib/data/database/sync_interceptor.dart').readAsStringSync();
      // Find the submitSafeTransaction signature block.
      final start = src.indexOf('Future<void> submitSafeTransaction({');
      expect(start, isNot(-1));
      final block = src.substring(start, start + 1500);
      expect(block, contains('int? partyId'),
          reason: 'Without partyId on the interface, callers cannot '
              'preserve the party link through the sync path → '
              'vouchers land on the server with party_id=NULL.');
      expect(block, contains('String? partyGlobalId'),
          reason: 'partyGlobalId is required for cross-instance '
              'resolution (mirror vs server have different '
              'autoincrement partyIds).');
    });

    test('cwi_sync passes partyId/partyGlobalId to the proxy', () {
      final src =
          File('lib/services/interceptor/cwi_sync.dart').readAsStringSync();
      final start = src.indexOf('static Future<void> submitSafeTransaction');
      expect(start, isNot(-1));
      final block = src.substring(start, start + 2500);
      expect(block, contains('partyId: partyId'),
          reason: 'Forwarding partyId on the serverCall keeps the '
              'party link intact when the outbox replays the request.');
      expect(block, contains('partyGlobalId: partyGlobalId'),
          reason: 'Server-side resolver needs the globalId; without '
              'it cross-instance partyIds collide.');
    });

    test('server_proxy includes partyId in the POST body', () {
      final src = File('lib/services/server_proxy.dart').readAsStringSync();
      final start = src.indexOf('Future<void> submitSafeTransaction');
      expect(start, isNot(-1));
      final block = src.substring(start, start + 2000);
      expect(block, contains("'partyId': ?partyId"),
          reason: 'The HTTP payload must include partyId; otherwise '
              'the server endpoint never sees it.');
      expect(block, contains("'partyGlobalId': partyGlobalId"),
          reason: 'Same for partyGlobalId — required for cross-'
              'instance resolution.');
    });

    test('postSafeTransaction resolves partyId and writes to companion', () {
      final src =
          File('lib/services/api/api_data_handler.dart').readAsStringSync();
      final start = src.indexOf('Future<Response> postSafeTransaction');
      expect(start, isNot(-1));
      // 10000 chars covers the handler body comfortably (the partyId
      // resolution is ~3700 chars in; the Companion insert is later).
      final endIdx = (start + 10000).clamp(0, src.length);
      final block = src.substring(start, endIdx);
      expect(block, contains("data['partyId']"),
          reason: 'Handler must read the incoming partyId from the '
              'request payload.');
      expect(block, contains('resolvePartyId('),
          reason: 'Use the existing resolvePartyId helper to honour '
              'partyGlobalId remapping. Mirrors postReceipt.');
      expect(block, contains('partyId: Value(resolvedStPartyId)'),
          reason: 'The resolved partyId must be written into the '
              'SafeTransactionsCompanion. Without this the row '
              'lands with party_id=NULL and the voucher is missing '
              "from the party's statement.");
    });

    test('treasury_dao threads partyId into both submitSafeTransaction calls',
        () {
      final src = File('lib/data/database/daos/treasury_dao.dart')
          .readAsStringSync();
      // Both calls (receipt + payment) should include partyId.
      final pidCount = 'partyId: partyId,'.allMatches(src).length;
      // There are several other partyId: partyId occurrences (the inner
      // _createVoucherJournalEntry calls); the spec only requires the
      // two submitSafeTransaction call sites to be wired. Count >= 4
      // (2 existing JE refs + 2 new submitSafeTransaction additions).
      expect(pidCount, greaterThanOrEqualTo(4),
          reason: 'Both createReceiptVoucher and createPaymentVoucher '
              'must forward partyId to submitSafeTransaction. Total '
              "occurrences should be >= 4 (2 existing internal refs "
              '+ 2 new sync-call refs).');
      // The party-globalId lookup pattern must appear twice (once per
      // voucher type).
      final gidLookups = 'partyRow?.globalId'.allMatches(src).length;
      expect(gidLookups, greaterThanOrEqualTo(2),
          reason: 'Each voucher type must look up the party globalId '
              'before calling submitSafeTransaction so the server '
              'can resolve cross-instance.');
    });
  });
}
