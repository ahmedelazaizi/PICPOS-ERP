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
import '../helpers/library_source.dart';

void main() {
  const relPath = 'lib/services/offline_sync_worker.dart';
  late String source;

  setUpAll(() {
    final file = File(relPath);
    expect(file.existsSync(), isTrue, reason: 'expected worker at $relPath');
    source = readLibrarySource(relPath);
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

  // ── The seven never-dispatched tables ─────────────────────────────────────
  //
  // Sibling of the group above, one level worse. Those cases existed but
  // handled too few ops; these seven tables had NO case at all, so every
  // queued row fell to `default:` → StateError → isPermanentError →
  // markAsSyncDeadLetter. "Retry all" resets them to pending with attempts=0,
  // they throw the same StateError, and dead-letter again: a loop the admin
  // can never clear. Eighteen enqueue sites feed it (cwi_admin ×12,
  // cwi_catalog ×5, cwi_sync ×1) and every one of them already had a working
  // ServerProxy method — the dispatch table was simply missing.
  //
  // Client-mode only: mirror mode throws MirrorOfflineException instead of
  // queueing, so nothing of this reaches the outbox there.
  group('Offline outbox — permanently dead-lettered admin tables', () {
    const expectedDispatch = <String, String>{
      'branches/insert': 'proxy.createBranch(',
      'branches/update': 'proxy.updateBranch(',
      'branches/delete': 'proxy.deleteBranch(',
      'accounts/insert': 'proxy.createAccount(',
      'accounts/update': 'proxy.updateAccount(',
      'accounts/delete': 'proxy.deleteAccount(',
      'account_mappings/upsert': 'proxy.setAccountMapping(',
      'account_mappings/delete': 'proxy.deleteAccountMapping(',
      'cost_centers/insert': 'proxy.createCostCenter(',
      'cost_centers/update': 'proxy.updateCostCenter(',
      'cost_centers/delete': 'proxy.deleteCostCenter(',
      'user_region_access/upsert': 'proxy.setUserRegionAccess(',
      'warehouses/insert': 'proxy.createWarehouse(',
      'warehouses/update': 'proxy.updateWarehouse(',
      'warehouses/update(setDefault)': 'proxy.setDefaultWarehouse(',
      'warehouses/update(unsetDefault)': 'proxy.unsetDefaultWarehouse(',
      'activity_logs/insert': 'proxy.pushActivityLog(',
    };

    expectedDispatch.forEach((op, call) {
      test('$op replays via $call', () {
        expect(source.contains(call), isTrue,
            reason: '$op is enqueued by the interceptor but had no case in '
                '_replayOperation, so it dead-lettered forever. It must '
                'replay via $call.');
      });
    });

    test('every one of the seven tables has a case', () {
      const tables = [
        'branches',
        'accounts',
        'account_mappings',
        'cost_centers',
        'user_region_access',
        'warehouses',
        'activity_logs',
      ];
      final missing =
          tables.where((t) => !source.contains("case '$t':")).toList();
      expect(missing, isEmpty,
          reason: 'these tables reach `default:` → StateError → dead-letter, '
              'and "retry all" loops them forever: $missing');
    });
  });

  // ── safes: silent success, the worst failure mode of the three ────────────
  //
  // `safes/insert` and `safes/delete` ARE enqueued (cwi_admin) but the safes
  // case covered only close/update — so they hit `break`, _replayOperation
  // returned null without throwing, and drainOutbox marked them a SUCCESS and
  // cleared the row. No dead-letter, no log, no trace. Same for a generic
  // safe edit (rename / bank details / isActive), whose inner
  // `payload['isDefault'] == true` check failed and fell through.
  //
  // A dead-letter at least shows up in the sync dialog. This did not.
  group('Offline outbox — safes silent success', () {
    test('safes/insert replays via proxy.createSafe', () {
      expect(source.contains('proxy.createSafe('), isTrue,
          reason: 'a safe created offline was cleared from the outbox as if '
              'it had synced — it never existed on HQ.');
    });

    test('safes/delete replays via proxy.deleteSafe', () {
      expect(source.contains('proxy.deleteSafe('), isTrue,
          reason: 'a safe deleted offline came back on the next DeltaPull, '
              'and the outbox row was already gone.');
    });

    test('a generic safes/update replays via proxy.updateSafe', () {
      expect(source.contains('proxy.updateSafe('), isTrue,
          reason: 'renaming a bank safe offline was silently discarded: the '
              "update branch only handled payload['isDefault'] == true.");
    });
  });
}
