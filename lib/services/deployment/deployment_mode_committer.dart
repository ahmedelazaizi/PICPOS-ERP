// ═══════════════════════════════════════════════════════════════════════════
// DEPLOYMENT MODE COMMITTER — Spec 125 Mirror Foundation
// ═══════════════════════════════════════════════════════════════════════════
//
// Single atomic entry-point for "commit this device to deployment mode X".
// Used by BOTH Setup Wizard (first-time) and Developer Tools (later toggle)
// so they produce identical results.
//
// Pipeline order (per contracts/deployment-mode-committer.md):
//   1. preCheck      — verify pre-conditions
//   2. pairing       — mirror/client: handshake + verify admin
//   3. firstSync     — mirror/client: wipe seeded + pull from server
//   4. setMode       — NetworkService writes network_mode + manages services
//   5. startHeartbeat — mirror only
//   6. finalDbCommit — atomic write of our owned settings keys
//
// On failure at any step: rollback in reverse, return CommitFailed,
// NO DB mutation to network_mode (NetworkService.setMode is the last
// step before our own flag writes, so if it threw, none of our flags
// were written either).
//
// Per Spec 125 contracts/deployment-mode-committer.md.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:drift/drift.dart' show Value;

import '../../core/logging/diagnostic_logger.dart';
import '../../data/database/database.dart';
import '../id_namespace_service.dart';
import '../mirror_heartbeat_service.dart';
import '../mirror_pairing_service.dart';
import '../mirror_state.dart';
import '../network_service.dart';
import '../sync/client_first_sync_service.dart';
import '../sync_service.dart';
import 'commit_result.dart';
import 'settings_keys.dart';
import 'setup_contract.dart';

/// Signature for the progress callback fired between steps of [commit].
typedef CommitProgressCallback = void Function(
  CommitStep step,
  String messageAr,
);

/// Single atomic entry-point for committing the system to a deployment mode.
class DeploymentModeCommitter {
  DeploymentModeCommitter({
    required this.db,
    SyncService Function()? syncServiceProvider,
  }) : _syncServiceProvider = syncServiceProvider ??
            (() {
              final s = SyncService.instance;
              if (s == null) {
                throw StateError(
                  'DeploymentModeCommitter: SyncService.instance is null '
                  '— commit(client|mirror) requires a configured SyncService.',
                );
              }
              return s;
            });

  final AppDatabase db;
  final SyncService Function() _syncServiceProvider;

  bool _committing = false;

  /// Commits the system to [contract.targetMode] atomically.
  ///
  /// Returns [CommitOk] on success.
  /// Returns [CommitFailed] on failure (no DB mutation to network_mode).
  /// Throws [StateError] if another commit is already in progress.
  ///
  /// [forceResync] — when true, re-pairs AND re-runs first-sync even if
  /// already done. Used by Dev Tools mode toggle (Phase 6). The wizard
  /// passes false because pairing/sync usually happened in an earlier
  /// wizard step (`_connectAndSync` / `_pairMirror`) — re-doing it would
  /// be wasteful and risk a double-wipe.
  Future<CommitResult> commit({
    required SetupContract contract,
    CommitProgressCallback? onProgress,
    bool forceResync = false,
  }) async {
    if (_committing) {
      throw StateError(
        'DeploymentModeCommitter.commit() called while a previous commit '
        'is still in progress',
      );
    }
    _committing = true;
    final stopwatch = Stopwatch()..start();
    final target = contract.targetMode;

    unawaited(DiagnosticLogger.log(
      'COMMIT-BEGIN',
      'mode=${target.name} (${contract.displayNameAr})',
    ));

    try {
      // ── Step 1: preCheck ───────────────────────────────────────────────
      onProgress?.call(CommitStep.preCheck, 'جارٍ التحقق من الإعدادات...');
      final preCheckFailure = await _preCheck(contract);
      if (preCheckFailure != null) {
        unawaited(DiagnosticLogger.log(
          'COMMIT-FAIL',
          'preCheck failed: ${preCheckFailure.reasonCode} — ${preCheckFailure.reasonAr}',
        ));
        return preCheckFailure;
      }

      // Pair + sync are decoupled gates (Spec 125 Cell 10 fix):
      //   • needsPair — only true when the CALLER explicitly provided
      //     credentials. Wizard's mirror/client branches finish in two
      //     steps: the earlier step (_pairMirror / _connectAndSync)
      //     already paired and left MirrorState populated; the contract
      //     reaching us here has empty creds, signalling "pairing done
      //     elsewhere — don't re-attempt". Dev Tools (Phase 6) will pass
      //     real creds → re-pair.
      //   • needsSync — gated on the per-mode first-sync flag.
      //     forceResync (Dev Tools) overrides both gates.
      final isMirror = contract is MirrorContract;
      final isClient = contract is ClientContract;
      final isMirrorOrClient = isMirror || isClient;
      final hasCreds = _hasCredentials(contract);
      final flagPending =
          isMirrorOrClient ? await _isFirstSyncPending(isMirror) : false;

      // ── Step 2: pairing (mirror/client) ────────────────────────────────
      var pairingDone = false;
      if (isMirrorOrClient) {
        // needsPair = ONLY when caller explicitly provides creds.
        // forceResync does NOT trigger pair — Dev Tools handles pairing
        // via MirrorPairingDialog BEFORE invoking the committer, then
        // sets forceResync=true to force the post-pair re-sync.
        final needsPair = hasCreds;
        if (needsPair) {
          onProgress?.call(CommitStep.pairing, 'جارٍ ربط الجهاز بالسيرفر...');
          final pairFailure = await _pair(contract);
          if (pairFailure != null) {
            unawaited(DiagnosticLogger.log(
              'COMMIT-FAIL',
              'pairing failed: ${pairFailure.reasonCode} — ${pairFailure.reasonAr}',
            ));
            return pairFailure;
          }
          pairingDone = true;
        } else {
          unawaited(DiagnosticLogger.log(
            'COMMIT-SKIP',
            'pair: empty creds + not forced (assumed already paired '
            'via _pairMirror/_connectAndSync); '
            'MirrorState.isConfigured=${MirrorState.instance.isConfigured}',
          ));
        }
      }

      // ── Step 3: firstSync ──────────────────────────────────────────────
      var firstSyncDone = false;
      if (isMirrorOrClient) {
        final needsSync = forceResync || flagPending;
        if (needsSync) {
          onProgress?.call(
            CommitStep.firstSync,
            'جارٍ المزامنة الأولى مع السيرفر...',
          );
          final syncFailure = await _firstSync(contract, force: forceResync);
          if (syncFailure != null) {
            if (pairingDone || isMirror) await _rollbackPairing();
            return syncFailure;
          }
          firstSyncDone = true;

          // Spec 131 FR-008 — empty-server guard. After a successful mirror
          // first-sync, if the server reported zero warehouses or zero
          // branches, the mirror has nothing useful to mirror. Refuse to
          // complete the commit with an Arabic error rather than landing
          // the user in a broken POS screen. The flag-bumping inside
          // performFirstSync ran, but we explicitly DO NOT roll it back —
          // the wipe was correct (the server really is empty); we just
          // can't proceed.
          if (isMirror) {
            final emptyServerFailure = await _checkMirrorMasterDataNonEmpty();
            if (emptyServerFailure != null) {
              if (pairingDone || isMirror) await _rollbackPairing();
              return emptyServerFailure;
            }
          }
        } else {
          unawaited(DiagnosticLogger.log(
            'COMMIT-SKIP',
            'first-sync already done (flag=true)',
          ));

          // Spec 136 ISS-3 — flag=true must NOT mean "commit blindly". A prior
          // first-sync can have committed an EMPTY master-data window (the
          // field bug: the branch/warehouse DeltaPull returned 0 because the
          // server's rows weren't settled yet, the empty-server guard fired,
          // but because the flag was already true the next commit skipped sync
          // AND the guard and landed the mirror with no branches/warehouses).
          // So when sync is skipped, still verify the mirror's master data is
          // non-empty; if it's empty, attempt ONE forced re-pull recovery and
          // re-check. Only fail (or proceed) after that — never commit an
          // empty window silently.
          if (isMirror) {
            final emptyNow = await _checkMirrorMasterDataNonEmpty();
            if (emptyNow != null) {
              unawaited(DiagnosticLogger.log(
                'COMMIT-RECOVER',
                'flag=true but mirror master-data empty — forcing one re-pull',
              ));
              final resyncFailure = await _firstSync(contract, force: true);
              if (resyncFailure != null) {
                if (pairingDone || isMirror) await _rollbackPairing();
                return resyncFailure;
              }
              firstSyncDone = true;
              final stillEmpty = await _checkMirrorMasterDataNonEmpty();
              if (stillEmpty != null) {
                if (pairingDone || isMirror) await _rollbackPairing();
                return stillEmpty;
              }
              unawaited(DiagnosticLogger.log(
                'COMMIT-RECOVER',
                'mirror master-data recovered via forced re-pull',
              ));
            }
          }
        }
      }

      final previousMode = NetworkService.instance.mode;
      // ── Step 4: setMode (delegates to NetworkService) ──────────────────
      // NetworkService.setMode writes network_mode to DB + manages HTTP
      // server/SyncService lifecycle. We delegate rather than duplicate.
      try {
        if (contract is ServerContract) {
          onProgress?.call(
            CommitStep.startHttpServer,
            'جارٍ تشغيل خادم الشبكة...',
          );
          NetworkService.instance.serverPort; // touched to keep import live
          // Persist port BEFORE setMode so HTTP starts on the right port.
          // (NetworkService.setServerAddress writes both address+port to prefs.)
          NetworkService.instance.setServerAddress(
            NetworkService.instance.serverAddress ?? '0.0.0.0',
            port: contract.port,
          );
          await NetworkService.instance.saveSettings();
        }
        await NetworkService.instance.setMode(target, db: db);
      } catch (e, st) {
        unawaited(DiagnosticLogger.log(
          'COMMIT-FAIL',
          'setMode threw at step=setMode mode=${target.name}: $e\n$st',
        ));
        if (firstSyncDone || pairingDone || isMirror) {
          await _rollbackPairing();
        }
        return CommitFailed(
          failedAtStep: target == NetworkMode.server
              ? CommitStep.startHttpServer
              : CommitStep.finalDbCommit,
          reasonAr: target == NetworkMode.server
              ? 'تعذّر تشغيل خادم الشبكة. قد يكون المنفذ مشغولاً.'
              : 'تعذّر حفظ إعدادات النظام النهائية.',
          reasonCode: 'SETMODE_FAILED',
          underlying: e,
        );
      }

      // ── Step 5: startHeartbeat (mirror only) ───────────────────────────
      if (contract is MirrorContract) {
        onProgress?.call(
          CommitStep.startHeartbeat,
          'جارٍ تفعيل مراقبة الاتصال...',
        );
        try {
          MirrorHeartbeatService.start();
        } catch (e) {
          // Heartbeat start failures are non-fatal — reconciler will retry
          // on next boot. But log loudly so we notice.
          unawaited(DiagnosticLogger.log(
            'COMMIT-WARN',
            'heartbeat start failed (non-fatal): $e',
          ));
        }
      }

      // ── Step 6: finalDbCommit (atomic settings transaction) ────────────
      onProgress?.call(
        CommitStep.finalDbCommit,
        'جارٍ حفظ الإعدادات النهائية...',
      );
      try {
        await _writeOwnedSettings(target);
      } catch (e, st) {
        // A0 (ADP-001): the mode is already set in memory/DB here. Undo it,
        // stop the heartbeat and (mirror) drop the pairing so the device is not
        // left half-activated.
        unawaited(DiagnosticLogger.log(
          'COMMIT-FAIL',
          'final settings write threw mode=${target.name}: $e\n$st',
        ));
        if (isMirror) MirrorHeartbeatService.stop();
        try {
          await NetworkService.instance.setMode(previousMode, db: db);
        } catch (_) {}
        if (isMirror || firstSyncDone || pairingDone) await _rollbackPairing();
        return CommitFailed(
          failedAtStep: CommitStep.finalDbCommit,
          reasonAr: 'تعذّر حفظ إعدادات النظام النهائية.',
          reasonCode: 'FINAL_COMMIT_FAILED',
          underlying: e,
        );
      }

      // Spec 136 ISS-22 — re-apply the client id-namespace floor (>=1B) AFTER
      // committing client OR mirror mode. The boot-time floor (main.dart) is
      // gated on NetworkService.isClient (false on mirror) and runs before this
      // commit; a re-pair/first-sync here wipes+repulls server rows and can
      // leave `sqlite_sequence` for transactional tables below 1B. Without
      // re-flooring, the next OFFLINE sale gets a low local id (1,2,3…) that
      // collides with a server id — DeltaPull's INSERT OR REPLACE then clobbers
      // the offline invoice, so it vanishes from the cashier's device and the
      // shift shows a cash variance. Covers both client and mirror.
      if (target == NetworkMode.client || target == NetworkMode.mirror) {
        try {
          await IdNamespaceService.instance.ensureClientFloor(db);
        } catch (e) {
          unawaited(DiagnosticLogger.log(
            'COMMIT-WARN',
            'ensureClientFloor after commit failed (non-fatal): $e',
          ));
        }
      }

      stopwatch.stop();
      unawaited(DiagnosticLogger.log(
        'COMMIT-OK',
        'mode=${target.name} duration=${stopwatch.elapsedMilliseconds}ms',
      ));
      return CommitOk(mode: target, totalDuration: stopwatch.elapsed);
    } finally {
      _committing = false;
    }
  }

  /// Convenience builder — wizard/dev-tools call this to construct the
  /// right contract subclass from in-memory form data.
  SetupContract buildContract({
    required NetworkMode target,
    int? serverPort,
    String? serverHost,
    String? adminUsername,
    String? adminPassword,
  }) {
    switch (target) {
      case NetworkMode.standalone:
        return const StandaloneContract();
      case NetworkMode.server:
        if (serverPort == null) {
          throw ArgumentError('serverPort required for ServerContract');
        }
        return ServerContract(port: serverPort);
      case NetworkMode.client:
        return ClientContract(
          serverHost: serverHost ?? '',
          serverPort: serverPort ?? 8080,
          adminUsername: adminUsername ?? '',
          adminPassword: adminPassword ?? '',
        );
      case NetworkMode.mirror:
        return MirrorContract(
          serverHost: serverHost ?? '',
          serverPort: serverPort ?? 8080,
          adminUsername: adminUsername ?? '',
          adminPassword: adminPassword ?? '',
        );
    }
  }

  // ── private helpers ──────────────────────────────────────────────────────

  /// Returns true when the contract carries non-empty admin credentials.
  /// Used as the "explicit pair-now" signal — wizard branches pass empty
  /// creds (pairing was done in an earlier step), Dev Tools passes real
  /// creds (wants re-pair).
  bool _hasCredentials(SetupContract contract) {
    if (contract is MirrorContract) {
      return contract.adminUsername.trim().isNotEmpty &&
          contract.adminPassword.isNotEmpty;
    }
    if (contract is ClientContract) {
      return contract.adminUsername.trim().isNotEmpty &&
          contract.adminPassword.isNotEmpty;
    }
    return false;
  }

  Future<CommitFailed?> _preCheck(SetupContract contract) async {
    if (contract is ServerContract) {
      // Port-busy check is best-effort — full check happens on setMode call.
      if (contract.port < 1 || contract.port > 65535) {
        return const CommitFailed(
          failedAtStep: CommitStep.preCheck,
          reasonAr: 'رقم المنفذ غير صالح (يجب أن يكون بين 1 و 65535).',
          reasonCode: 'INVALID_PORT',
        );
      }
    }
    if (contract is MirrorContract || contract is ClientContract) {
      // Server reachability is tested as part of pairing (NetworkService
      // .testServerConnection inside MirrorPairingService.pair). We don't
      // duplicate it here to avoid double-network-round-trip on the wizard.
    }
    return null;
  }

  Future<CommitFailed?> _pair(SetupContract contract) async {
    String host;
    int port;
    String user;
    String pass;
    if (contract is MirrorContract) {
      host = contract.serverHost;
      port = contract.serverPort;
      user = contract.adminUsername;
      pass = contract.adminPassword;
    } else if (contract is ClientContract) {
      host = contract.serverHost;
      port = contract.serverPort;
      user = contract.adminUsername;
      pass = contract.adminPassword;
    } else {
      return null;
    }

    final result = await MirrorPairingService.instance.pair(
      host: host,
      port: port,
      adminUsername: user,
      adminPassword: pass,
      // Spec 151 P1-8b — mint an admin session token for MIRROR re-pairs so
      // the first-sync pulls all-branch transactions. A CLIENT re-pair must
      // NOT get full access (it stays branch-isolated), so leave it false.
      acquireAdminSession: contract is MirrorContract,
    );
    if (result.isSuccess) return null;
    return CommitFailed(
      failedAtStep: CommitStep.pairing,
      reasonAr: result.message ?? 'فشل الاتصال بالسيرفر',
      reasonCode: 'PAIRING_${result.outcome.name.toUpperCase()}',
    );
  }

  Future<bool> _isFirstSyncPending(bool isMirror) async {
    final svc = isMirror
        ? ClientFirstSyncService.mirror(db: db)
        : ClientFirstSyncService(db: db);
    return svc.isFirstSyncPending();
  }

  Future<CommitFailed?> _firstSync(
    SetupContract contract, {
    required bool force,
  }) async {
    try {
      final svc = (contract is MirrorContract)
          ? ClientFirstSyncService.mirror(db: db)
          : ClientFirstSyncService(db: db);
      if (force) {
        // Dev Tools re-toggle: wipe the flag so performFirstSync re-runs
        // the wipe-and-pull. The wizard never forces — _connectAndSync /
        // _pairMirror have already done the work, so we skip via the
        // isFirstSyncPending gate in commit().
        await svc.reset();
      }

      // Resolve a SyncService. Client mode populates SyncService.instance
      // during _connectAndSync; mirror mode does NOT (it builds one inline
      // because mirror reuses client's wire protocol without owning the
      // singleton). Match that pattern here so committer works for both.
      final SyncService syncService;
      final hosted = SyncService.instance;
      if (hosted != null) {
        syncService = hosted;
      } else if (contract is MirrorContract || contract is ClientContract) {
        final serverUrl = NetworkService.instance.buildServerUrl();
        syncService = SyncService(serverUrl: serverUrl, localDb: db);
      } else {
        syncService = _syncServiceProvider();
      }

      await svc.performFirstSync(syncService: syncService);
      return null;
    } catch (e, st) {
      unawaited(DiagnosticLogger.log(
        'COMMIT-FAIL',
        'firstSync threw: $e\n$st',
      ));
      return CommitFailed(
        failedAtStep: CommitStep.firstSync,
        reasonAr: 'تعذّرت المزامنة الأولى مع السيرفر: $e',
        reasonCode: 'FIRSTSYNC_FAILED',
        underlying: e,
      );
    }
  }

  /// Spec 131 FR-008 — empty-server guard. After a mirror first-sync, the
  /// mirror MUST have at least one warehouse AND one branch to be usable.
  /// Returns a CommitFailed describing the gap (in Arabic) when either
  /// count is zero, or null when both have rows.
  Future<CommitFailed?> _checkMirrorMasterDataNonEmpty() async {
    try {
      final whRow = await db
          .customSelect('SELECT COUNT(*) AS n FROM warehouses')
          .getSingle();
      final brRow = await db
          .customSelect('SELECT COUNT(*) AS n FROM branches')
          .getSingle();
      final whCount = whRow.read<int>('n');
      final brCount = brRow.read<int>('n');
      if (whCount == 0 || brCount == 0) {
        unawaited(DiagnosticLogger.log(
          'COMMIT-FAIL',
          'mirror empty-server guard: warehouses=$whCount branches=$brCount',
        ));
        return const CommitFailed(
          failedAtStep: CommitStep.firstSync,
          reasonAr: 'السيرفر لا يحتوى على فروع/مخازن — يرجى إعداد السيرفر '
              'أولاً (إضافة فرع ومخزن على الأقل) ثم المحاولة مرة أخرى.',
          reasonCode: 'MIRROR_SERVER_EMPTY',
        );
      }
      return null;
    } catch (e, st) {
      unawaited(DiagnosticLogger.log(
        'COMMIT-FAIL',
        'mirror empty-server guard threw: $e\n$st',
      ));
      // Don't fail the commit on a query error here — better to let the
      // user proceed and surface the bug at sale time than block on a
      // diagnostic that itself broke. The pre-flight (Spec 131 US2) is
      // the safety net.
      return null;
    }
  }

  Future<void> _rollbackPairing() async {
    // Best-effort: clear pairing state so reconciler doesn't see a
    // half-paired device on next boot. Heartbeat is only started AFTER
    // setMode succeeds, so we don't need to stop it here.
    try {
      await MirrorState.instance.clear();
    } catch (_) {
      // Silent — rollback failures don't override the original CommitFailed.
    }
    unawaited(DiagnosticLogger.log(
      'COMMIT-ROLLBACK',
      'pairing state cleared',
    ));
  }

  /// Atomic write of the owned settings keys (excluding network_mode which
  /// NetworkService.setMode already wrote). Per data-model.md §2.2.
  Future<void> _writeOwnedSettings(NetworkMode mode) async {
    final companions = <SettingsCompanion>[
      SettingsCompanion(
        key: const Value(DeploymentSettingsKeys.lastCommittedMode),
        value: Value(mode.name),
      ),
    ];
    switch (mode) {
      case NetworkMode.standalone:
        companions.add(const SettingsCompanion(
          key: Value(DeploymentSettingsKeys.standaloneSetupCompleted),
          value: Value('true'),
        ));
        break;
      case NetworkMode.server:
        companions.add(const SettingsCompanion(
          key: Value(DeploymentSettingsKeys.serverSetupCompleted),
          value: Value('true'),
        ));
        break;
      case NetworkMode.client:
        // client_first_sync_completed is set by ClientFirstSyncService itself.
        break;
      case NetworkMode.mirror:
        // mirror_first_sync_completed is set by ClientFirstSyncService.mirror.
        break;
    }
    await db.transaction(() async {
      for (final c in companions) {
        await db.into(db.settings).insertOnConflictUpdate(c);
      }
    });
  }
}
