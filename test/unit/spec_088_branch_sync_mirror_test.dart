// ═══════════════════════════════════════════════════════════════════════════
// SPEC 088 USR-2 — Mirror mode preserves all branches (source pins)
// ═══════════════════════════════════════════════════════════════════════════
//
// Field bug: signing into a mirror as مدير كل الفروع triggered SYNC-WARN
// lines that deactivated three regional branches locally because the
// sync response's `branches` array didn't include them (server-side
// scope filter for the calling user — NOT a delete signal).
//
// Fix: branch_sync_strategy gates ALL three deactivation passes on a new
// mirror-only predicate. The client-mode behavior (where the absence
// really does mean delete, per Cluster 023) stays unchanged.
//
// These pins ensure:
//   1. SyncInterceptor has a new `isMirrorMode` getter — symmetric to the
//      existing isClientMode but stricter (mirror-only, NOT client OR
//      mirror).
//   2. ClientWriteInterceptor implements isMirrorModeImpl via
//      WriteRouter.isMirrorActive.
//   3. branch_sync_strategy.dart wraps the deactivation passes in an
//      `if (SyncInterceptor.isMirrorMode)` early-return, with a
//      SYNC-INFO line per skipped branch list.
//   4. The SYNC-WARN log line (the field-visible smoking gun) is still
//      emitted on client mode but NOT on mirror.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Spec 088 USR-2 — mirror branch-deactivation gate', () {
    test('SyncInterceptor declares isMirrorMode static getter', () {
      final src =
          File('lib/data/database/sync_interceptor.dart').readAsStringSync();
      expect(
          src,
          contains(
              'static bool get isMirrorMode => instance?.isMirrorModeImpl'),
          reason: 'Without the static getter, branch_sync_strategy and any '
              'future caller would have to import NetworkService directly '
              '— breaking the abstract-interceptor layer that 60+ files '
              'rely on.');
      expect(src, contains('bool get isMirrorModeImpl'),
          reason: 'The abstract getter is what every concrete interceptor '
              'must implement; without it the static getter has nothing '
              'to delegate to.');
    });

    test('ClientWriteInterceptor implements isMirrorModeImpl', () {
      final src =
          File('lib/services/interceptor/cwi_core.dart').readAsStringSync();
      expect(src,
          contains('bool get isMirrorModeImpl => WriteRouter.isMirrorActive'),
          reason: 'Mirror-only predicate must NOT be the broadened R9 gate '
              '(which is true for both client AND mirror). It must narrow '
              'to mirror exclusively, otherwise USR-2 would silently '
              'disable client-mode branch deactivation too.');
    });

    test('isMirrorMode is NOT redefined as ServerProxy.isClientMode-style OR',
        () {
      final src =
          File('lib/services/interceptor/cwi_core.dart').readAsStringSync();
      // Make sure nobody re-broadens isMirrorMode the same way isClientMode
      // is broadened (which would defeat the whole point of USR-2).
      expect(
          src.contains('isMirrorModeImpl =>\n      ServerProxy.isClientMode'),
          isFalse,
          reason: 'isMirrorMode must NOT include client mode. If it does, '
              'client-mode branches stop deactivating on absence → '
              'regresses Cluster 023.');
    });

    test('branch_sync_strategy imports SyncInterceptor', () {
      final src =
          File('lib/services/sync/strategies/branch_sync_strategy.dart')
              .readAsStringSync();
      expect(
          src,
          contains(
              "import 'package:picpos_erp/data/database/sync_interceptor.dart'"),
          reason:
              'Without the explicit import, isMirrorMode reference is unresolved '
              '(database.dart does not re-export sync_interceptor.dart).');
    });

    test('branch_sync_strategy gates the deactivation passes on isMirrorMode',
        () {
      final src =
          File('lib/services/sync/strategies/branch_sync_strategy.dart')
              .readAsStringSync();
      expect(src, contains('if (SyncInterceptor.isMirrorMode) {'),
          reason: 'The mirror skip-gate is the heart of USR-2. Without it, '
              'a mirror signed in as a scope-limited user still flips '
              'live branches to isActive=false.');
    });

    test('mirror gate emits a SYNC-INFO line (not SYNC-WARN) listing skipped',
        () {
      final src =
          File('lib/services/sync/strategies/branch_sync_strategy.dart')
              .readAsStringSync();
      // The SYNC-INFO line must reference "mirror mode" and list the
      // skipped branches so an auditor can confirm the skip after smoke.
      expect(
          src,
          contains(
              "'branches skipped — mirror mode: not deactivating "),
          reason: 'Field operators grep for this exact phrase to confirm '
              'the gate fired. Changing the wording silently breaks the '
              'quickstart smoke.');
      expect(src, contains("'SYNC-INFO',"),
          reason: 'Mirror skip is informational, NOT a warning. Using '
              'SYNC-WARN would re-flag every legitimate sync as a '
              'problem in the operator dashboard.');
    });

    test('client-mode SYNC-WARN deactivation log is still present', () {
      // FR-204: client mode unchanged. The pre-088 SYNC-WARN must still
      // be emitted when client mode deactivates a branch on absence.
      final src =
          File('lib/services/sync/strategies/branch_sync_strategy.dart')
              .readAsStringSync();
      expect(
          src,
          contains(
              'branches deactivated locally because absent from server response'),
          reason: 'Removing the client-mode SYNC-WARN would regress '
              'Cluster 023 — client devices need to know when a branch '
              'is truly deleted upstream.');
    });

    test('three deactivation passes remain inside the else branch', () {
      // Pin that the three passes (orphan, same-name dedup, Cluster 029)
      // are STILL there for the non-mirror code path. Otherwise USR-2
      // accidentally deletes the entire client-mode contract.
      final src =
          File('lib/services/sync/strategies/branch_sync_strategy.dart')
              .readAsStringSync();
      expect(src, contains('Cluster 023 / Issue 5 propagation'),
          reason: 'Orphan-deactivate pass identity must survive.');
      expect(src, contains('Cluster 023 / Issue 5 dedup'),
          reason: 'Same-name dedup pass identity must survive.');
      expect(src, contains('Cluster 029 retroactive cleanup'),
          reason: 'Cluster 029 cleanup pass identity must survive.');
    });
  });
}
