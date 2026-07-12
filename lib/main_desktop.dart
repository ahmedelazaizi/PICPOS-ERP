import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';
import 'package:path/path.dart' as p;
import 'core/config/app_config.dart';
import 'core/utils/platform_init.dart';
import 'core/services/backup_service.dart';
import 'services/scale_service_io.dart';
import 'services/network_service.dart';
import 'services/mirror_state.dart';
import 'services/mirror_heartbeat_service.dart';
import 'services/delta_pull_service.dart';
import 'services/server_proxy.dart';
import 'services/sync_service.dart';
import 'services/websocket_sync_client.dart';
import 'services/offline_sync_worker.dart';
import 'services/client_write_interceptor.dart';
import 'services/adaptive_poll_timer.dart';
import 'services/cheque_receipt_drift_audit_service.dart';
import 'data/database/database.dart';
import 'data/database/pg_config.dart';

import 'data/database/connection_io.dart' show testPostgresConnection;
import 'services/offline_fallback_sync_service.dart';

/// Initialize desktop-specific features
Future<void> initPlatform() async {
  // Initialize window manager for desktop platforms
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    // Set window title based on flavor
    await windowManager.setTitle(AppConfig.appName);
    // #3: Start in fullscreen mode for POS usability
    await windowManager.setFullScreen(true);
  }
  initFileUtils();
  // Load saved network mode (standalone/server/client/mirror)
  await NetworkService.instance.loadSettings();
  await MirrorState.instance.loadSettings();

  // NOTE: Client mode now intentionally uses local SQLite for fast reads,
  // with HTTP sync to keep data in sync with the server.
  // We no longer reset client+SQLite to standalone.
}

bool isDesktop() {
  return !kIsWeb &&
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
}

/// Exit application with safety cleanup
Future<void> exitApp() async {
  try {
    // Stop network server if running
    await NetworkService.instance.dispose();
    // Perform backup before exit (#PIR Phase 0)
    final dbFile = File(
      p.join(p.dirname(Platform.resolvedExecutable), 'database.sqlite'),
    );
    if (await dbFile.exists()) {
      await BackupService.performBackup(dbFile.path);
    }
  } catch (e) {
    debugPrint('Shutdown backup failed: $e');
  }
  exit(0);
}

/// Auto-start the embedded HTTP API server.
/// Must be called AFTER AppDatabase is available.
/// The HTTP API is ALWAYS started regardless of network mode because:
///   - Server mode: serves data to clients
///   - Standalone mode: enables future client connections
///   - Client mode: may still need the API for local tools (CFD, menu)
Future<void> autoStartNetworkServer(AppDatabase db) async {
  final ns = NetworkService.instance;

  // SAFETY: Never auto-change mode for standalone users.
  // The old auto-fix silently promoted standalone → server when PostgreSQL
  // was on localhost, causing fresh installs to sync unexpected data.
  // Now, only explicitly configured servers start the HTTP API.
  if (ns.isStandalone) {
    debugPrint('[NetworkService] 📴 Standalone mode — HTTP API server NOT started');
    return;
  }

  // Auto-fix: Only when NOT standalone and PostgreSQL is on localhost
  if (!ns.isServer) {
    try {
      final dbMode = await PostgresConfig.loadMode();
      if (dbMode == DatabaseMode.postgres) {
        final pgConfig = await PostgresConfig.load();
        final pgHost = pgConfig.host.trim();
        if (pgHost == 'localhost' || pgHost == '127.0.0.1') {
          print('[NetworkService] ⚙️ PostgreSQL on localhost detected — auto-setting server mode');
          await ns.setMode(NetworkMode.server, db: db);
          await ns.saveSettings();
        }
      }
    } catch (e) {
      print('[NetworkService] ⚠️ Could not check PostgreSQL config: $e');
    }
  }

  // Start the HTTP API server for server/client modes
  try {
    final ok = await ns.startServer(db);
    print('[NetworkService] HTTP API server: ${ok ? "✅ Running on port ${ns.serverPort}" : "❌ Failed to start"}');
  } catch (e) {
    print('[NetworkService] ❌ HTTP API server error: $e');
  }

  // Spec 133 FR-011 — emit a one-line diagnostic signal listing
  // customer count + total over-credit amount for historical cheque-
  // receipt double-credits (the bug Commits A-D fix). Server-mode only:
  // standalone never ran client/server so couldn't be amplified, and
  // client/mirror installs sync from the server's authoritative state.
  // Web target is not affected — server mode is desktop-only and the
  // audit query uses local SQLCipher.
  if (ns.isServer) {
    try {
      await ChequeReceiptDriftAuditService(db).emitStartupSignal();
    } catch (e) {
      // Audit must never block boot — the service swallows its own
      // errors internally too; this outer catch is belt-and-braces.
      debugPrint('[CHEQUE-RECEIPT-DRIFT] startup emit failed: $e');
    }
  }
}

/// Auto-sync from server when the device is in client OR mirror mode.
/// Must be called AFTER AppDatabase is available.
///
/// Mirror mode (Feature 006 MM.B) reuses the entire client-side sync
/// machinery — token fetch, initial bootstrap, periodic delta pull,
/// WebSocket push, and the safety-net fullSync — so the HQ console has
/// fresh master data to read locally. Mirror has no outbox in MM.B
/// (writes land in MM.C), so the periodic outbox drain inside this
/// function is a harmless no-op against an empty queue.
Future<void> autoSyncIfClient(AppDatabase db) async {
  final ns = NetworkService.instance;
  if (!ns.isClient && !ns.isMirror) return;

  // NOTE: ClientWriteInterceptor + OfflineSyncWorker are initialized
  // unconditionally in `main.dart` right after `sharedDb` is created.
  // Don't re-initialize here — it would be a no-op but leaving the call
  // invited the earlier regression where this method was the ONLY path
  // that wired those state holders (see Phase A–E sync fix).

  final serverUrl = ns.buildServerUrl();
  final modeLabel = ns.isMirror ? 'Mirror' : 'Client';
  print('[Sync] $modeLabel mode detected — syncing from $serverUrl');

  // Fetch API token from server (critical — without this, all POST/GET requests fail auth)
  // The token is only populated by testServerConnection, which calls /api/health
  final addr = ns.serverAddress ?? '';
  final port = ns.serverPort;
  
  if (addr.trim().isEmpty || addr.trim() == 'localhost') {
    print('[Sync] Skipping API token fetch — no valid server address configured.');
    return;
  }

  print('[Sync] Fetching API token from $addr:$port...');
  final healthResult = await ns.testServerConnection(addr, port);
  if (healthResult['success'] == true) {
    print('[Sync] ✅ API token fetched successfully');
  } else {
    print('[Sync] ⚠️ Could not fetch API token: ${healthResult['error']}');
    print('[Sync] Sales sync will NOT work without API token');
  }

  final syncService = SyncService(serverUrl: serverUrl, localDb: db);

  // Initial sync — prefer incremental when watermarks exist (returning client)
  // and fall back to a full strategy-based bootstrap on first launch. This
  // prevents the "N clients × full dump" stampede that a naive fullSync-on-
  // every-launch would create with many seats.
  final hasWatermark = await DeltaPullService.instance.hasAnyWatermark();
  if (hasWatermark) {
    try {
      await DeltaPullService.instance.pullAll();
      print('[Sync] Initial delta pull ✅ (watermarks found)');
    } catch (e) {
      print('[Sync] Initial delta pull failed, will retry periodically: $e');
    }
  } else {
    final result = await syncService.fullSync();
    print(
      '[Sync] Initial full bootstrap: ${result.success ? "✅" : "❌"} ${result.message}',
    );
    // Seed watermarks so the next periodic delta pull is truly incremental
    // rather than redundantly dumping what the strategies just downloaded.
    // Use the authoritative server clock — a client clock running ahead of
    // the server would otherwise skip rows modified in the skew window.
    if (result.success) {
      final serverSec = await ServerProxy.instance.fetchServerTime();
      final seedSec = serverSec ??
          (DateTime.now().millisecondsSinceEpoch ~/ 1000) - 60;
      await DeltaPullService.instance.seedWatermarks(seedSec);
    }
  }

  // Immediately drain any pending outbox items (e.g. from previous session)
  OfflineSyncWorker.instance.drainOutbox(force: true);

  // Start WebSocket for real-time push (best-effort, not critical)
  WebSocketSyncClient.instance.connect();

  // ── Periodic delta pull (runs every 30s regardless of WS) ──
  // Pulls server→client changes for all 40 sync-hardened tables via
  // /api/sync/pull using last-modified watermarks. Scales cleanly because
  // only changed rows cross the wire; unchanged tables cost one empty query.
  //
  // A slower `fullSync` runs every 5 minutes as a safety net for the handful
  // of legacy tables that are not yet sync-hardened (settings, permissions,
  // role_permissions, document_sequences, account_mappings, user_*_access,
  // product_batches, offers, inventory_balances).
  // Spec 129 F7 (FR-701..703) — adaptive poll cadence. The fixed 30-second
  // safety-net was firing 2,880 HTTP polls per device per day even when the
  // WS was healthy and delivering data_changed events in real time. The
  // AdaptivePollTimer drops to 300 s while the WS is connected (the
  // safety-net only catches up tables the WS doesn't broadcast) and snaps
  // back to 30 s on disconnect so the catch-up latency stays bounded.
  //
  // The fullSync-every-10th-tick semantic stays (counter increments per
  // tick regardless of interval), so on a 300 s cadence fullSync now runs
  // every ~50 min — acceptable safety-net frequency for the legacy tables
  // it covers (settings, permissions, role_permissions, document_sequences,
  // account_mappings, user_*_access, product_batches, offers,
  // inventory_balances).
  int periodicTick = 0;
  late final AdaptivePollTimer pollTimer;
  pollTimer = AdaptivePollTimer.start(
    connected: WebSocketSyncClient.instance.connected,
    onTick: () async {
      // Cancel cleanly if the operator switched away from a networked mode
      // (client → standalone, or mirror → standalone). Mirror joins client
      // here so a paused mirror device stops hammering the server.
      if (!ns.isClient && !ns.isMirror) {
        pollTimer.stop();
        return;
      }

      // ALWAYS drain outbox (client → server) first — independent of pull
      try {
        OfflineSyncWorker.instance.drainOutbox(force: true);
      } catch (e) {
        print('[Sync] Outbox drain error: $e');
      }

      // Delta pull: 40 hardened tables, in FK-dependency order
      try {
        await DeltaPullService.instance.pullAll();
        print('[Sync] Delta pull ✅');
      } catch (e) {
        print('[Sync] Delta pull failed: $e');
      }

      // Every 10th tick: safety-net fullSync for non-hardened tables.
      periodicTick++;
      if (periodicTick % 10 == 0) {
        try {
          final r = await syncService.fullSync();
          print('[Sync] Legacy fullSync ${r.success ? "✅" : "partial: ${r.message}"}');
        } catch (e) {
          print('[Sync] Legacy fullSync failed: $e');
        }
      }
    },
  );
  print('[Sync] Adaptive poll started — WS-connected: 300s, WS-disconnected: 30s');

  // ─── Mirror-mode heartbeat (MM.B + MM.E hot-fix) ───────────────────────
  // The ticker is now a static service so it can be (re)started both at
  // boot AND when the user pairs to mirror mode at runtime via the setup
  // wizard. The previous inline implementation only fired at boot, so a
  // wizard-initiated pairing would leave the badge red until the next
  // app restart — see MirrorHeartbeatService for the full rationale.
  MirrorHeartbeatService.start();
}

/// Whether PostgreSQL server has been confirmed reachable while in offline mode.
/// Used by the UI to show the "Sync now" option.
bool pgServerReachable = false;

/// Start a periodic reconnection timer when in offline fallback mode.
/// Every 60 seconds, tests PostgreSQL connectivity. When the server
/// becomes reachable, automatically triggers the offline-to-PostgreSQL
/// data sync so all data created during the offline period is pushed.
void startOfflineReconnectionTimer() {
  if (!PostgresConfig.isOfflineFallback) return;

  debugPrint('[Offline] Starting PostgreSQL reconnection + auto-sync timer (every 60s)');
  Timer.periodic(const Duration(seconds: 60), (timer) async {
    if (!PostgresConfig.isOfflineFallback) {
      timer.cancel();
      pgServerReachable = false;
      return;
    }
    try {
      final pgConfig = await PostgresConfig.load();
      final error = await testPostgresConnection(pgConfig);
      if (error == null) {
        pgServerReachable = true;

        // Auto-trigger sync when PostgreSQL becomes reachable
        final syncService = OfflineFallbackSyncService.instance;
        if (!syncService.isSyncing) {
          debugPrint('[Offline] ✅ PostgreSQL reachable — starting auto-sync...');
          // Get the local SQLite database
          // (the default AppDatabase singleton when pgDb was null at startup)
          final localDb = AppDatabase();
          final success = await syncService.syncToPostgres(localDb);
          if (success) {
            debugPrint('[Offline] ✅ Auto-sync completed! All data pushed to server.');
            timer.cancel(); // Stop checking — sync is done
          } else {
            debugPrint('[Offline] ⚠️ Auto-sync failed — will retry next cycle');
          }
        }
      } else {
        pgServerReachable = false;
        debugPrint('[Offline] ⏳ PostgreSQL still unreachable: $error');
      }
    } catch (e) {
      debugPrint('[Offline] Reconnection check error: $e');
    }
  });
}

/// Auto-connect to the last used scale port
Future<void> autoConnectScale() async {
  await ScaleService.instance.autoConnect();
}

/// Show touch keyboard on Windows
void showTouchKeyboard() {
  if (!Platform.isWindows) return;

  try {
    Process.run('cmd', [
      '/c',
      'start',
      '',
      r'C:\Program Files\Common Files\microsoft shared\ink\TabTip.exe',
    ]);
  } catch (e) {
    // Fallback to osk.exe
    try {
      Process.run('cmd', ['/c', 'start', 'osk.exe']);
    } catch (_) {}
  }
}

/// Returns the NetworkService singleton for server-mode checks.
NetworkService getNetworkService() => NetworkService.instance;

