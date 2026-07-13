// Pre-deploy BLOCKER (sync audit 2026-07-13) — stock-audit & cycle-count
// finalize wrote inventory movements + the settlement JE DIRECTLY to the local
// DB with NO SyncInterceptor.isClientMode gate and NO interceptor/outbox
// routing. On a client (or mirror) device the corrected stock + shrinkage/
// surplus movements + the settlement JE reached local SQLite only, never HQ;
// the server (SoT) kept the uncorrected stock and, on the next DeltaPull,
// serverWins overwrote currentStock back — the whole count was silently
// reverted (R4 violation).
//
// Stopgap fix (owner-approved option B): the count subsystem is not yet
// sync-aware, so finalize is BLOCKED on client/mirror (do it on the server)
// rather than writing local-only. This guard asserts the write path (the repo
// impls, closest to the local write) refuses when SyncInterceptor.isClientMode.
// Full client-side sync-aware counting is a follow-up spec.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Jard finalize blocked on client/mirror (BLOCKER, option B)', () {
    test('inventory_repository_impl.finalizeAudit gates on SyncInterceptor.isClientMode',
        () {
      const p = 'lib/data/repositories/inventory_repository_impl.dart';
      final src = File(p).readAsStringSync();
      expect(
        src.contains('SyncInterceptor.isClientMode'),
        isTrue,
        reason:
            '$p finalizeAudit must refuse on client/mirror (it wrote inventory + '
            'settlement JE local-only, never reaching HQ → reverted on pull).',
      );
    });

    test('cycle_count_repository_impl.finalizeCycleCountTask gates on SyncInterceptor.isClientMode',
        () {
      const p = 'lib/data/repositories/cycle_count_repository_impl.dart';
      final src = File(p).readAsStringSync();
      expect(
        src.contains('SyncInterceptor.isClientMode'),
        isTrue,
        reason:
            '$p finalizeCycleCountTask must refuse on client/mirror for the same '
            'local-only silent-loss reason as stock-audit finalize.',
      );
    });
  });
}
