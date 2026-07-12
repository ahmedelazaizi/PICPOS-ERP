import 'dart:async' show unawaited;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';

import '../../core/logging/diagnostic_logger.dart';
import '../../data/database/database.dart';
import '../sync_service.dart';
import 'mirror_settings_keys.dart';
import 'sync_warning.dart';

/// Orchestrates the *first* sync that runs after the user pairs the device
/// to a server in the Setup Wizard.
///
/// The contract (Constitution Principle III — server is the source of truth):
///
/// 1. The local seeder runs at first DB open with `isClientMode=false`
///    because the mode is unknown then. It inserts a default branch,
///    warehouse, units, safes, chart of accounts, and three delivery-company
///    parties.
/// 2. When the user later picks **client** mode, those local seeds are by
///    definition wrong: the authoritative versions live on the server.
/// 3. Before pulling from the server we therefore wipe the seeded rows
///    via [AppDatabase.wipeSeededMasterDataForClient], then run
///    [SyncService.fullSync] to populate the tables from the server.
/// 4. On success we persist `client_first_sync_completed = 'true'` so
///    subsequent runs skip the wipe (incremental sync only).
/// 5. If any step fails the flag stays `false` and the next attempt
///    re-wipes — the invariant is "either fully synced or fully empty".
///
/// Reused utilities (Principle II):
///   - [AppDatabase.wipeSeededMasterDataForClient] — already implements
///     the per-table delete + transaction wrap (Principle IV).
///   - [AppDatabase.getSettingValue] / direct insert into `settings` —
///     same pattern the sync strategies use.
class ClientFirstSyncService {
  /// Default constructor — uses the original `client_first_sync_completed`
  /// flag set, kept for backwards compatibility with all existing call
  /// sites in the client-mode wizard path.
  ClientFirstSyncService({required this.db})
      : _flagKey = 'client_first_sync_completed',
        _atKey = 'client_first_sync_at',
        _warningsKey = 'client_first_sync_warnings_count';

  /// Mirror-mode variant (Feature 006 / MM.E hot-fix). Reuses the same
  /// wipe-and-pull machinery against a separate flag set so the two
  /// modes can't fight over each other's completion state. Mirror needs
  /// the same first-sync as client mode — the locally-seeded "الفرع
  /// الرئيسي" / safes / accounts collide with HQ's authoritative copies
  /// and were producing duplicate rows in the branch picker.
  ClientFirstSyncService.mirror({required this.db})
      : _flagKey = 'mirror_first_sync_completed',
        _atKey = 'mirror_first_sync_at',
        _warningsKey = 'mirror_first_sync_warnings_count';

  final AppDatabase db;

  final String _flagKey;
  final String _atKey;
  final String _warningsKey;

  /// True when this device is in client mode and has not yet completed a
  /// post-pairing first sync. Callers (the Setup Wizard) should invoke
  /// [performFirstSync] before any normal incremental sync runs.
  Future<bool> isFirstSyncPending() async {
    final v = await db.getSettingValue(_flagKey);
    return v != 'true';
  }

  /// Resets the flag — call when the user re-pairs the device to a
  /// different server, so the next sync starts from a clean wipe.
  Future<void> reset() async {
    await _saveSetting(_flagKey, 'false');
  }

  /// Wipes locally-seeded master data, runs a full pull from the server,
  /// and on success sets `client_first_sync_completed = 'true'`.
  ///
  /// Returns a [FirstSyncResult] with the counts and any warnings emitted
  /// by the per-table strategies (e.g. fallback matches that succeeded but
  /// weren't on the strongest dedup tier).
  ///
  /// Throws [FirstSyncException] if the wipe or pull fails. The flag stays
  /// `false` on failure so the next attempt re-wipes.
  Future<FirstSyncResult> performFirstSync({
    required SyncService syncService,
    void Function(String stage)? onProgress,
  }) async {
    final stopwatch = Stopwatch()..start();
    final warnings = <SyncWarning>[];

    try {
      onProgress?.call('wipe');
      debugPrint('[FirstSync] Wiping locally-seeded master data');

      // Spec 131 (FR-007) — count rows BEFORE wipe so the breadcrumb can
      // report what was actually removed. Cheap COUNT(*) over small master
      // tables; total budget < 10 ms.
      final beforeWipe = await _snapshotMasterDataCounts();
      await db.wipeSeededMasterDataForClient();
      final afterWipe = await _snapshotMasterDataCounts();
      unawaited(DiagnosticLogger.log(
        'MIRROR-WIPE',
        'removed '
        'warehouses=${beforeWipe['warehouses']! - afterWipe['warehouses']!} '
        'branches=${beforeWipe['branches']! - afterWipe['branches']!} '
        'safes=${beforeWipe['safes']! - afterWipe['safes']!} '
        'parties=${beforeWipe['parties']! - afterWipe['parties']!} '
        'units=${beforeWipe['units']! - afterWipe['units']!} '
        'categories=${beforeWipe['categories']! - afterWipe['categories']!} '
        'accounts=${beforeWipe['accounts']! - afterWipe['accounts']!}',
      ));

      onProgress?.call('sync');
      // Phase 6 (T3) — surface the gate state up front so a wizard log
      // reader can verify catalog-only first-sync without diffing the
      // [Sync] tier prints. The gate itself lives inside fullSync.
      if (syncService.isClient && !syncService.clientPullsTransactionalEnabled) {
        debugPrint('[FirstSync] tier-3 will be skipped (client-isolated mode) — '
            'sales/purchases/journals/safe_transactions/shifts/etc are '
            'managed locally and pushed via outbox only');
      }
      // Spec 151 P1-8b — this first-sync runs PRE-LOGIN, so the device holds
      // no session token. `fullSync` pulls REFERENCE/master tables fully
      // (branches, warehouses, products, safes, users, accounts, …) — the
      // wizard branch list and POS product grid populate, so a fresh client is
      // never bricked — but SKIPS the branch-scoped transactional tables
      // (server fail-closes them tokenless) and, via the guarded
      // `DeltaPullService.seedWatermarks`, leaves their watermarks UNSEEDED so
      // DeltaPull backfills them from scratch on first login (scoped to the
      // user's branch). A skipped table returns `false` from fullSync (neither
      // synced nor failed), so `syncResult.success` stays true — the skip is
      // expected and never aborts first-sync. The mirror path mints an admin
      // token at pairing (`MirrorPairingService.pair`), so `hasSessionToken()`
      // is already true here and its transactional first-sync pulls in full.
      debugPrint('[FirstSync] Starting full sync from ${syncService.serverUrl}');
      final syncStopwatch = Stopwatch()..start();
      final syncResult = await syncService.fullSync();
      syncStopwatch.stop();

      if (!syncResult.success) {
        throw FirstSyncException(
          'fullSync failed: ${syncResult.message}',
          tablesSynced: syncResult.itemsSynced,
        );
      }

      // Spec 131 (FR-007) — what did the pull actually produce? Count master
      // tables AFTER the sync. Comparing counts (rather than syncResult's
      // per-tier map) gives a uniform, mirror-mode-relevant snapshot that
      // matches the audit dialog's view (FR-010).
      final afterSync = await _snapshotMasterDataCounts();
      unawaited(DiagnosticLogger.log(
        'MIRROR-FIRST-SYNC',
        'pulled '
        'warehouses=${afterSync['warehouses']} '
        'branches=${afterSync['branches']} '
        'safes=${afterSync['safes']} '
        'parties=${afterSync['parties']} '
        'units=${afterSync['units']} '
        'categories=${afterSync['categories']} '
        'accounts=${afterSync['accounts']} '
        'duration=${syncStopwatch.elapsedMilliseconds}ms',
      ));

      // Persist the completion flag inside a single statement — using the
      // settings table directly (matches the strategy pattern in sync
      // strategies that write via `db.into(db.X).insertOnConflictUpdate`).
      onProgress?.call('finalize');
      await _saveSetting(_flagKey, 'true');
      await _saveSetting(_atKey, DateTime.now().toIso8601String());
      await _saveSetting(_warningsKey, warnings.length.toString());

      // Spec 131 (A5 upgrade trigger) — mark this build's mirror-cache fix
      // as applied. Set unconditionally (client + mirror both get it) so a
      // single boolean check on the reconciler's mirror branch is enough.
      // Clients carry the flag harmlessly.
      await _saveSetting(kMirrorCacheIntegrityV1AppliedFlag, 'true');

      stopwatch.stop();
      debugPrint(
        '[FirstSync] ✓ complete in ${stopwatch.elapsedMilliseconds}ms — '
        '${syncResult.itemsSynced} tables, ${warnings.length} warnings',
      );

      return FirstSyncResult(
        tablesSynced: syncResult.itemsSynced,
        warnings: warnings,
        elapsed: stopwatch.elapsed,
      );
    } catch (e, st) {
      stopwatch.stop();
      debugPrint('[FirstSync] ✗ failed: $e\n$st');
      if (e is FirstSyncException) rethrow;
      throw FirstSyncException(e.toString());
    }
  }

  Future<void> _saveSetting(String key, String value) async {
    await db.into(db.settings).insertOnConflictUpdate(
          SettingsCompanion(
            key: Value(key),
            value: Value(value),
          ),
        );
  }

  /// Spec 131 (FR-007) — uniform count snapshot of the master-data tables
  /// touched by `wipeSeededMasterDataForClient`. Used to compute removed /
  /// pulled deltas for the [MIRROR-WIPE] and [MIRROR-FIRST-SYNC] breadcrumbs.
  /// Cheap COUNT(*) per table; all 7 take well under 10 ms on SQLite.
  Future<Map<String, int>> _snapshotMasterDataCounts() async {
    Future<int> countOf(String table) async {
      final row = await db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle();
      return row.read<int>('n');
    }

    return {
      'warehouses': await countOf('warehouses'),
      'branches': await countOf('branches'),
      'safes': await countOf('safes'),
      'parties': await countOf('parties'),
      'units': await countOf('units'),
      'categories': await countOf('categories'),
      'accounts': await countOf('accounts'),
    };
  }
}

/// Result of a successful [ClientFirstSyncService.performFirstSync] call.
class FirstSyncResult {
  const FirstSyncResult({
    required this.tablesSynced,
    required this.warnings,
    required this.elapsed,
  });

  final int tablesSynced;
  final List<SyncWarning> warnings;
  final Duration elapsed;

  /// Convenience getter — used by the wizard banner "(M تحذير)".
  int get warningCount => warnings.length;
}

/// Thrown when wipe or sync fails. The Setup Wizard catches this and
/// surfaces a localised error to the user; the completion flag stays
/// `false` so the next attempt re-wipes.
class FirstSyncException implements Exception {
  FirstSyncException(this.message, {this.tablesSynced = 0});

  final String message;
  final int tablesSynced;

  @override
  String toString() => 'FirstSyncException: $message';
}
