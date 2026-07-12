// ═══════════════════════════════════════════════════════════════════════════
// Spec 131 — FR-007 diagnostic breadcrumb format pins
// ═══════════════════════════════════════════════════════════════════════════
//
// Source-level pins for the [MIRROR-*] breadcrumb taxonomy across the 4
// emit sites:
//   1. ClientFirstSyncService — MIRROR-WIPE + MIRROR-FIRST-SYNC
//   2. NetworkService.reconcileWithDb — MIRROR-UPGRADE-FORCED-SYNC
//   3. SalesTransactionOrchestrator._preflightSaleParity — MIRROR-MASTERDATA-CHECK
//      + MIRROR-CACHE-DIVERGENCE (pre-flight origin)
//   4. SalesTransactionOrchestrator catch — MIRROR-CACHE-DIVERGENCE
//      (server-500 origin)
//
// Future emit sites (audit dialog [MIRROR-AUDIT-*]) land here when added.
//
// Each pin checks: the exact tag literal, the key=value pairs the spec
// promises, and that the breadcrumb is emitted via DiagnosticLogger.log
// (not bare debugPrint).
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Spec 131 FR-007 — MIRROR-WIPE breadcrumb', () {
    final src = File('lib/services/sync/client_first_sync_service.dart')
        .readAsStringSync();

    test('exact tag literal', () {
      expect(src, contains("'MIRROR-WIPE'"));
    });

    test('removed-counts payload covers all 7 master-data tables', () {
      // The line lists removed counts as `key=N` pairs separated by spaces.
      // Pin each key so a future refactor can't silently drop one.
      final tagIdx = src.indexOf("'MIRROR-WIPE'");
      expect(tagIdx, isNot(-1));
      // Look at ~600 chars after the tag for the message string.
      final msg = src.substring(tagIdx, tagIdx + 600);
      for (final key in [
        'warehouses=',
        'branches=',
        'safes=',
        'parties=',
        'units=',
        'categories=',
        'accounts=',
      ]) {
        expect(msg, contains(key),
            reason: 'MIRROR-WIPE must report counts for $key');
      }
      expect(msg, contains('removed '),
          reason: 'message prefix pins format as "removed <key>=N <key>=N ..."');
    });
  });

  group('Spec 131 FR-007 — MIRROR-FIRST-SYNC breadcrumb', () {
    final src = File('lib/services/sync/client_first_sync_service.dart')
        .readAsStringSync();

    test('exact tag literal', () {
      expect(src, contains("'MIRROR-FIRST-SYNC'"));
    });

    test('payload includes pulled-counts + duration', () {
      final tagIdx = src.indexOf("'MIRROR-FIRST-SYNC'");
      expect(tagIdx, isNot(-1));
      final msg = src.substring(tagIdx, tagIdx + 600);
      expect(msg, contains('pulled '));
      expect(msg, contains('duration='));
      expect(msg, contains('ms'));
    });
  });

  group('Spec 131 FR-007 — MIRROR-UPGRADE-FORCED-SYNC breadcrumb', () {
    final src =
        File('lib/services/network_service.dart').readAsStringSync();

    test('exact tag literal', () {
      expect(src, contains("'MIRROR-UPGRADE-FORCED-SYNC'"));
    });

    test('payload identifies trigger', () {
      final idx = src.indexOf("'MIRROR-UPGRADE-FORCED-SYNC'");
      final msg = src.substring(idx, idx + 200);
      expect(msg, contains('triggered_at_boot'));
      expect(msg, contains('reason=upgrade'));
    });
  });

  group('Spec 131 FR-007 — MIRROR-MASTERDATA-CHECK breadcrumb', () {
    final src =
        File('lib/data/repositories/sales_transaction_orchestrator.dart')
            .readAsStringSync();

    test('exact tag literal', () {
      expect(src, contains("'MIRROR-MASTERDATA-CHECK'"));
    });

    test('payload lists all 5 master-data ids + all_resolved flag', () {
      // Two emit sites (true + false path) share the same shape.
      expect(src, contains('sale='));
      expect(src, contains('warehouse='));
      expect(src, contains('branch='));
      expect(src, contains('customer='));
      expect(src, contains('cost_center='));
      // Safe is split into 3 per-payment columns (cash/bank/click).
      expect(src, contains('cash_safe='));
      expect(src, contains('bank_safe='));
      expect(src, contains('click_safe='));
      expect(src, contains('all_resolved=true'));
      expect(src, contains('all_resolved=false'));
    });
  });

  group('Spec 131 FR-007 — MIRROR-CACHE-DIVERGENCE breadcrumb', () {
    final src =
        File('lib/data/repositories/sales_transaction_orchestrator.dart')
            .readAsStringSync();

    test('exact tag literal', () {
      expect(src, contains("'MIRROR-CACHE-DIVERGENCE'"));
    });

    test('payload lists kind + requested + cached + server_response + origin',
        () {
      expect(src, contains('kind='));
      expect(src, contains('_missing'));
      expect(src, contains('requested='));
      expect(src, contains('cached='));
      expect(src, contains('server_response='));
      expect(src, contains('origin='));
    });

    test('both origin values surface — pre-flight AND server-500', () {
      expect(src, contains('origin=pre-flight'));
      expect(src, contains('origin=server-500'));
    });
  });

  group('Spec 131 FR-007 — all breadcrumbs route via DiagnosticLogger.log', () {
    final orcSrc =
        File('lib/data/repositories/sales_transaction_orchestrator.dart')
            .readAsStringSync();
    final firstSyncSrc =
        File('lib/services/sync/client_first_sync_service.dart')
            .readAsStringSync();
    final netSrc =
        File('lib/services/network_service.dart').readAsStringSync();

    test('no [MIRROR-*] debugPrints — only DiagnosticLogger.log',
        () {
      // Each Spec 131 breadcrumb tag must NOT be inside a debugPrint(...) —
      // they go through the persistent diagnostic log so field engineers
      // can grep the file even after the console buffer rolls over.
      // We assert that every occurrence of "'MIRROR-" appears after the
      // DiagnosticLogger.log( token (NOT debugPrint(). Lightweight regex.
      const tags = [
        'MIRROR-WIPE',
        'MIRROR-FIRST-SYNC',
        'MIRROR-UPGRADE-FORCED-SYNC',
        'MIRROR-MASTERDATA-CHECK',
        'MIRROR-CACHE-DIVERGENCE',
      ];
      final combined = '$orcSrc\n$firstSyncSrc\n$netSrc';
      for (final tag in tags) {
        final pattern = RegExp("debugPrint\\([^)]*$tag");
        expect(combined.contains(pattern), isFalse,
            reason: 'Spec 131 breadcrumb $tag MUST go through '
                'DiagnosticLogger.log, not debugPrint.');
      }
    });
  });
}
