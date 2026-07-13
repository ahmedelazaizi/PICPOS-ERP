// Pre-deploy BLOCKER (sync audit 2026-07-13) — the offline outbox silently
// DROPPED writes for UNHANDLED operations on KNOWN tables.
//
// Root cause: `OfflineSyncWorker._replayOperation`'s per-table `case` handled
// only some operations (e.g. `case 'parties'`: insert/delete). An unhandled op
// — `parties/update` (a customer credit-limit / balance / phone edit queued
// while the server link was down, cwi_commerce.dart) or `sales/update` (an
// invoice edit) — matched no `if/else if` branch, hit the trailing `break`, and
// the method returned null WITHOUT throwing. `drainOutbox` then called
// `markAsSyncSuccess(item.id)` unconditionally → the edit was cleared from the
// outbox having NEVER reached the server → silent data loss, reverted on the
// next serverWins DeltaPull. The Spec-151 fail-loud `default:` only caught
// unknown TABLES, not unhandled OPS on known tables.
//
// Source-level guard (mirrors offline_sync_worker_journal_dispatch_test.dart):
// `_replayOperation` is a private instance method needing a live AppDatabase +
// ServerProxy, so we assert the dispatch source closes the confirmed paths.
// All three assertions FAIL against pre-fix source.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const relPath = 'lib/services/offline_sync_worker.dart';
  late String source;

  setUpAll(() {
    final file = File(relPath);
    expect(file.existsSync(), isTrue, reason: 'expected worker at $relPath');
    source = file.readAsStringSync();
  });

  group('Offline outbox — unhandled-op silent-drop blocker', () {
    test('parties/update replays via proxy.updateParty (customer edits reach HQ)',
        () {
      expect(
        source.contains('proxy.updateParty('),
        isTrue,
        reason:
            'parties/update is queued offline (credit-limit/balance/phone edits) '
            'but the parties case handled only insert/delete → the edit hit '
            'break→null→markAsSyncSuccess and was silently dropped. It must '
            'replay via proxy.updateParty.',
      );
    });

    test('sales/update replays via proxy.updateSalesInvoice (invoice edits reach HQ)',
        () {
      expect(
        source.contains('proxy.updateSalesInvoice('),
        isTrue,
        reason:
            'sales/update is queued offline (invoice edits) but the sales case '
            'handled only insert/delete/void/payment → silently dropped. It '
            'must replay via proxy.updateSalesInvoice.',
      );
    });

    test('unhandled ops on a known table FAIL LOUD (never break→null→success)',
        () {
      expect(
        source.contains('Unhandled op '),
        isTrue,
        reason:
            'a known-table case whose operation matches no branch must throw '
            "(routed to dead-letter), not fall through `break` and be marked a "
            'sync success. Add an `else { throw StateError(\'Unhandled op ...\') }`.',
      );
    });
  });
}
