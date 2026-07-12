// ═══════════════════════════════════════════════════════════════════════════
// Spec 131 — Mirror cache integrity upgrade trigger (FR / A5)
// ═══════════════════════════════════════════════════════════════════════════
//
// Source-level invariants for the one-shot upgrade trigger:
//   1. ReconcileOk carries a `forceFirstSync` flag.
//   2. network_service.reconcileWithDb sets it under the mirror branch when
//      `mirror_cache_integrity_v1_applied` is missing/`!= 'true'`.
//   3. client_first_sync_service.performFirstSync sets the flag on success.
//   4. main.dart consumes the flag and runs performFirstSync silently.
//   5. The literal flag key lives in mirror_settings_keys.dart and matches
//      `'mirror_cache_integrity_v1_applied'` exactly.
//
// Behavioural / end-to-end coverage lives in quickstart.md Cell 6 (manual
// smoke). These structural pins ensure the wires can't drift apart.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/services/sync/mirror_settings_keys.dart';

void main() {
  group('Spec 131 — mirror_cache_integrity_v1_applied flag literal', () {
    test('canonical constant matches the documented key', () {
      expect(kMirrorCacheIntegrityV1AppliedFlag,
          'mirror_cache_integrity_v1_applied');
    });

    test('5 pos_default_* exact keys are present in the canonical list',
        () {
      expect(kPosDefaultExactKeys, [
        'pos_default_warehouse_id',
        'pos_default_safe_id',
        'pos_default_customer_id',
        'pos_default_branch_id',
        'pos_default_cost_center_id',
      ]);
    });

    test('per-branch warehouse override LIKE prefix is exact', () {
      expect(kPosDefaultWarehouseBranchPrefix, 'pos_default_warehouse_branch_');
    });
  });

  group('Spec 131 — ReconcileOk forceFirstSync wiring', () {
    final src =
        File('lib/services/deployment/reconcile_result.dart').readAsStringSync();

    test('ReconcileOk carries an optional forceFirstSync field', () {
      expect(src, contains('this.forceFirstSync = false'),
          reason: 'ReconcileOk must accept an optional forceFirstSync flag '
              'so the launcher can detect the Spec 131 upgrade trigger.');
      expect(src, contains('final bool forceFirstSync;'),
          reason: 'forceFirstSync must be a final bool field.');
    });

    test('ReconcileFatalKind enum gained the Spec 131 variant', () {
      expect(src, contains('mirrorCacheDivergence'),
          reason: 'ReconcileFatalKind must include mirrorCacheDivergence to '
              'route divergence events through the Fatal screen.');
    });

    test('ReconcileReasonCode exposes MIRROR_CACHE_DIVERGENCE', () {
      expect(src, contains("'MIRROR_CACHE_DIVERGENCE'"));
    });
  });

  group('Spec 131 — NetworkService.reconcileWithDb sets forceFirstSync', () {
    final src =
        File('lib/services/network_service.dart').readAsStringSync();

    test('imports the canonical settings-keys file', () {
      expect(src, contains("import 'sync/mirror_settings_keys.dart'"),
          reason: 'reconcile must use the canonical flag literal, not a copy.');
    });

    test('mirror branch reads kMirrorCacheIntegrityV1AppliedFlag', () {
      expect(
          src, contains('getSettingValue(kMirrorCacheIntegrityV1AppliedFlag)'),
          reason: 'reconcile must read the flag to detect the upgrade trigger.');
    });

    test('forces first sync when flag is absent on a mirror', () {
      // The block sets `forceFirstSync: true` and logs MIRROR-UPGRADE-FORCED-SYNC.
      expect(src, contains('forceFirstSync: true'));
      expect(src, contains("'MIRROR-UPGRADE-FORCED-SYNC'"));
    });
  });

  group('Spec 131 — performFirstSync sets the flag', () {
    final src = File('lib/services/sync/client_first_sync_service.dart')
        .readAsStringSync();

    test('writes kMirrorCacheIntegrityV1AppliedFlag = true on success', () {
      // The save lives next to the existing _saveSetting(_flagKey, 'true') call.
      expect(
          src,
          contains(
              "_saveSetting(kMirrorCacheIntegrityV1AppliedFlag, 'true')"),
          reason: 'Without this write the upgrade trigger fires every boot.');
    });

    test('emits [MIRROR-WIPE] and [MIRROR-FIRST-SYNC] breadcrumbs', () {
      expect(src, contains("'MIRROR-WIPE'"),
          reason: 'FR-007: MIRROR-WIPE breadcrumb on every wipe.');
      expect(src, contains("'MIRROR-FIRST-SYNC'"),
          reason: 'FR-007: MIRROR-FIRST-SYNC breadcrumb after pull.');
    });
  });

  group('Spec 131 — main.dart consumes the upgrade trigger', () {
    final src = File('lib/main.dart').readAsStringSync();

    test('inspects ReconcileOk.forceFirstSync', () {
      expect(
          src,
          contains(
              'reconcileResult is ReconcileOk && reconcileResult.forceFirstSync'));
    });

    test('invokes ClientFirstSyncService.mirror.performFirstSync inline', () {
      expect(src, contains('ClientFirstSyncService.mirror(db: dbForReconcile)'),
          reason: 'Silent re-sync must use the mirror-mode constructor.');
      expect(src, contains('firstSyncService.performFirstSync('));
    });

    test('falls back to the Fatal screen on re-sync failure', () {
      expect(
          src,
          contains(
              "setSetting('mirror_first_sync_completed', 'false')"),
          reason: 'On failure we flip the existing first-sync flag so the '
              'next reconcile pass routes through the Spec 125 Fatal screen.');
    });
  });
}
