import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../core/logging/diagnostic_logger.dart';
import '../data/database/database.dart';
import 'delta_pull_service.dart';
import 'device_identity_service.dart';
import 'network_service.dart';
import 'offline_sync_worker.dart';
import 'sync_service.dart';
import 'tls_trust.dart';

/// WebSocket client for real-time data sync in client mode.
/// Connects to the server's /ws endpoint and listens for data_changed events.
/// On each event, triggers an incremental sync for the affected table(s).
class WebSocketSyncClient {
  static WebSocketSyncClient? _instance;
  static WebSocketSyncClient get instance =>
      _instance ??= WebSocketSyncClient._();
  WebSocketSyncClient._();

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectDelay = 60; // seconds
  static const Duration _pingInterval = Duration(seconds: 30);

  /// Per-table debounce timers for `data_changed` events. The server can
  /// fire several events for the same table in rapid succession (e.g. when
  /// a transaction inserts header + lines + posts a journal entry); without
  /// debouncing we issue one full pull per event. A 500 ms window collapses
  /// the storm into a single pull while still feeling instantaneous to the
  /// user. (Issue 4)
  final Map<String, Timer> _pullDebounce = {};
  static const Duration _pullDebounceWindow = Duration(milliseconds: 500);

  /// Branch this client is subscribed to — set on connect, used to filter events.
  int? _clientBranchId;

  /// Whether the WebSocket is currently connected
  final ValueNotifier<bool> connected = ValueNotifier<bool>(false);

  /// Spec 129 F1 / FR-101 — pure-function helper that builds the WS connect
  /// URI. Extracted so the URL-construction logic is independently testable
  /// (see test/unit/mirror_ws_connect_test.dart) without spinning up a real
  /// SharedPreferences or DeviceIdentityService.
  ///
  /// For client mode: appends `branch_id=<id>` when [clientBranchId] is non-null.
  /// For mirror mode: appends `mode=mirror` and (when non-null) `device_id=<id>`.
  /// Mirror NEVER appends `branch_id` because the mirror sees all branches.
  ///
  /// When neither branch nor mirror metadata applies (legacy client without
  /// a stored branch), returns [base] unchanged.
  @visibleForTesting
  static Uri buildConnectUri({
    required Uri base,
    required bool isMirror,
    int? clientBranchId,
    String? mirrorDeviceId,
  }) {
    final params = <String, String>{};
    if (isMirror) {
      params['mode'] = 'mirror';
      if (mirrorDeviceId != null && mirrorDeviceId.isNotEmpty) {
        params['device_id'] = mirrorDeviceId;
      }
    } else if (clientBranchId != null) {
      params['branch_id'] = '$clientBranchId';
    }
    if (params.isEmpty) return base;
    return base.replace(queryParameters: params);
  }

  /// Start connecting to the server's WebSocket endpoint.
  /// Works in **client** and **mirror** modes (Spec 129 F1 / FR-101).
  void connect() {
    final ns = NetworkService.instance;
    if (!ns.isClient && !ns.isMirror) return;
    _doConnect();
  }

  /// Feature 005 Phase 8 — manual immediate reconnect, bypassing the
  /// exponential backoff schedule. Used by the "إعادة المحاولة الآن" button
  /// on the AdminElevationBanner so the operator can recover the read-only
  /// state without waiting up to 60 s for the next scheduled retry. Resets
  /// the attempt counter so subsequent failures restart from the 5 s delay
  /// rather than the long tail.
  ///
  /// Spec 129: also enabled in mirror mode.
  void forceReconnectNow() {
    final ns = NetworkService.instance;
    if (!ns.isClient && !ns.isMirror) return;
    _reconnectTimer?.cancel();
    _reconnectAttempts = 0;
    _cleanup();
    _doConnect();
  }

  void _doConnect() async {
    try {
      final ns = NetworkService.instance;
      final addr = ns.serverAddress;
      if (addr == null || addr.trim().isEmpty || addr.trim() == 'localhost') {
        debugPrint('[WS-Client] Skipping connection — no valid server address configured.');
        return;
      }

      // Spec 129 F1: client reads its branch_id; mirror skips that and reads
      // its device_id from DeviceIdentityService (warmed at app boot —
      // tryGetDeviceId returns null if warmup hasn't run, which we tolerate
      // as a degraded "device=unknown" path per contracts/ws-subscriber-protocol.md §1).
      String? mirrorDeviceId;
      if (ns.isMirror) {
        _clientBranchId = null;
        mirrorDeviceId = DeviceIdentityService.instance.tryGetDeviceId();
      } else {
        try {
          final prefs = await SharedPreferences.getInstance();
          _clientBranchId = prefs.getInt('client_branch_id');
        } catch (_) {
          // Missing branch preference degrades to an unscoped client pull.
        }
      }

      final baseUri = Uri.parse(ns.buildWsUrl());
      final wsUrl = buildConnectUri(
        base: baseUri,
        isMirror: ns.isMirror,
        clientBranchId: _clientBranchId,
        mirrorDeviceId: mirrorDeviceId,
      );
      final modeLabel = ns.isMirror ? 'mirror' : 'client';
      debugPrint('[WS-Client] Connecting to $wsUrl (mode=$modeLabel, branch=$_clientBranchId, device=${mirrorDeviceId ?? "n/a"})...');

      // 🔴 كان `WebSocketChannel.connect` بعميلٍ افتراضيٍّ بلا خطّافِ
      // شهادة، فقناةُ المزامنة الحيّة **تُخفق على `wss://`** بينما بقيّةُ
      // المسارات تنجح — أي مزامنةٌ صامتةُ التعطّل بلا رسالةٍ مفهومة.
      // و`IOWebSocketChannel` تقبل عميلاً مخصّصاً، فتمرّ من نفس نقطة
      // التثبيت التي تمرُّ منها كلُّ نداءات HTTP.
      _channel = wsUrl.scheme == 'wss'
          ? IOWebSocketChannel.connect(wsUrl,
              customClient: TlsTrust.ioClient())
          : WebSocketChannel.connect(wsUrl);
      _subscription = _channel!.stream.listen(
        _onMessage,
        onDone: _onDisconnected,
        onError: (e) {
          debugPrint('[WS-Client] Error: $e');
          _onDisconnected();
        },
      );

      // connected.value is set to true only when server confirms via 'connected' event
      _reconnectAttempts = 0;
      debugPrint('[WS-Client] Channel opened, waiting for server handshake...');
      _startPing();
    } catch (e) {
      debugPrint('[WS-Client] Connection failed: $e');
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic message) {
    try {
      final data = json.decode(message as String) as Map<String, dynamic>;
      final event = data['event'] as String?;

      if (event == 'connected') {
        connected.value = true;
        debugPrint('[WS-Client] Server confirmed connection');
        // Spec 129 FR-OBS-1 — log the accepted lifecycle event.
        final ns = NetworkService.instance;
        final modeLabel = ns.isMirror ? 'mirror' : 'client';
        final deviceId = ns.isMirror
            ? (DeviceIdentityService.instance.tryGetDeviceId() ?? 'unknown')
            : 'n/a';
        DiagnosticLogger.log(
          DiagnosticLogger.wsConnect,
          'mode=$modeLabel device=$deviceId branch=${_clientBranchId ?? "all"}',
        );
        // Re-fetch the API token and then drain offline outbox
        _refreshTokenAndDrain();
        return;
      }

      if (event == 'data_changed') {
        final table = data['table'] as String?;
        final eventBranchId = data['branch_id'] as int?;
        // Ignore events scoped to a branch this client doesn't serve
        if (_clientBranchId != null && eventBranchId != null && eventBranchId != _clientBranchId) {
          debugPrint('[WS-Client] Ignoring data_changed/$table for branch $eventBranchId (client=branch $_clientBranchId)');
          return;
        }
        debugPrint('[WS-Client] Data changed: $table');
        _triggerSync(table);
      }

      // Handle record deletion events from server
      if (event == 'record_deleted') {
        final table = data['table'] as String?;
        final recordId = data['recordId'];
        final eventBranchId = data['branch_id'] as int?;
        if (_clientBranchId != null && eventBranchId != null && eventBranchId != _clientBranchId) {
          return;
        }
        debugPrint('[WS-Client] Record deleted: $table#$recordId');
        _handleRecordDeleted(table, recordId);
      }
    } catch (e) {
      debugPrint('[WS-Client] Message parse error: $e');
    }
  }

  /// Re-fetch the API token from the server, drain the outbox, and pull any
  /// server changes that arrived while the client was offline (catch-up sync).
  /// Without the delta pull, clients miss all server writes that happened
  /// during a network gap and only re-sync on the next WebSocket push.
  Future<void> _refreshTokenAndDrain() async {
    try {
      final ns = NetworkService.instance;
      final addr = ns.serverAddress ?? '';
      final port = ns.serverPort;
      if (addr.isNotEmpty) {
        await ns.testServerConnection(addr, port);
      }
    } catch (e) {
      debugPrint('[WS-Client] Token refresh failed: $e');
    }
    // 1. Drain outbox — push any local writes that queued while offline.
    OfflineSyncWorker.instance.drainOutbox(force: true);
    // 2. Catch-up pull — fetch all server changes missed during the offline gap.
    unawaited(DeltaPullService.instance.pullAll().catchError((Object e) {
      debugPrint('[WS-Client] Catch-up pull after reconnect failed: $e');
    }));
  }


  void _onDisconnected() {
    connected.value = false;
    _cleanup();
    debugPrint('[WS-Client] ❌ Disconnected');
    // Spec 129 FR-OBS-1 — log the disconnect.
    final ns = NetworkService.instance;
    final modeLabel = ns.isMirror ? 'mirror' : 'client';
    DiagnosticLogger.log(
      DiagnosticLogger.wsDisconnect,
      'mode=$modeLabel reason=transport',
    );
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    final ns = NetworkService.instance;
    if (!ns.isClient && !ns.isMirror) return;
    _reconnectTimer?.cancel();
    final delay = (_reconnectAttempts < 3 ? 5 : _reconnectAttempts < 6 ? 10 : _maxReconnectDelay);
    _reconnectAttempts++;
    debugPrint(
      '[WS-Client] Reconnecting in $delay seconds (attempt $_reconnectAttempts)',
    );
    _reconnectTimer = Timer(Duration(seconds: delay), _doConnect);
  }

  /// Spec 136 — coarse broadcast aliases → concrete delta-pull table names.
  ///
  /// The server broadcasts generic event names after a write (e.g. a POS sale
  /// fires `broadcast('sales')` + `broadcast('accounting')`), but
  /// [DeltaPullService.pullTables] is keyed on concrete table names. Before this
  /// map a `'sales'` event matched NEITHER pullTables NOR any
  /// `SyncService.syncTable` strategy (whose tableName is `sales_invoices`), so
  /// it silently did nothing — the new invoice only appeared on the mirror at
  /// the next 300s poll (the field "بياخّر في الظهور على الميرور" report).
  /// Expanding the alias makes the pull immediate (real-time, per the no-defer
  /// sync rule). Only concrete names that exist in pullTables are pulled; an
  /// unknown table falls through unchanged.
  static const Map<String, List<String>> _broadcastAliasToTables = {
    'sales': ['sales_invoices', 'sales_invoice_items'],
    'purchases': ['purchase_invoices', 'purchase_invoice_items'],
    'accounting': ['journal_entries'],
    'journals': ['journal_entries'],
    'treasury': ['safe_transactions'],
    'inventory': ['stock_movements'],
  };

  /// Expand a broadcast event name to the concrete table name(s) to pull.
  /// Returns `[table]` unchanged when it is not a known alias.
  @visibleForTesting
  static List<String> pullTargetsFor(String table) =>
      _broadcastAliasToTables[table] ?? [table];

  void _triggerSync(String? table) {
    if (table == null) return;
    // Expand a coarse alias to its concrete delta-pull tables (or keep the
    // table as-is when it is already concrete).
    final targets = pullTargetsFor(table);
    for (final t in targets) {
      // Debounce repeated events for the same table. Issue 4 — keeps the
      // client responsive without re-pulling once per FK-cascade event.
      _pullDebounce[t]?.cancel();
      _pullDebounce[t] = Timer(_pullDebounceWindow, () {
        _pullDebounce.remove(t);
        if (DeltaPullService.pullTables.contains(t)) {
          unawaited(DeltaPullService.instance.pullTable(t));
          return;
        }
        // Fallback: full re-fetch via SyncService strategy for other tables.
        SyncService.instance?.syncTable(t);
      });
    }
  }

  /// Handle server-pushed deletion events — soft-delete the record locally.
  /// All P2.1 sync tables use `deleted_at` (epoch ms); hard-delete for others.
  ///
  /// `recordId` is the server-side id. For master tables pulled via /api/sync/pull
  /// the client reuses the server id, so direct match works. For client-created
  /// transactional rows the local id differs from the server id, so we resolve
  /// via `remote_id_mappings` first and fall back to the raw remoteId.
  Future<void> _handleRecordDeleted(String? table, dynamic recordId) async {
    if (table == null || recordId == null) return;
    final remoteId = int.tryParse(recordId.toString());
    if (remoteId == null) return;

    final db = SyncService.instance?.localDb;
    if (db == null) return;

    final localId = await db.resolveLocalId(table, remoteId) ?? remoteId;

    final nowEpochSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    try {
      await db.customStatement(
        'UPDATE $table SET deleted_at = ? WHERE id = ? AND deleted_at IS NULL',
        [nowEpochSeconds, localId],
      );
      debugPrint('[WS-Client] Soft-deleted $table#$localId (remote=$remoteId)');
    } catch (error, stack) {
      await DiagnosticLogger.logError(
        'SYNC-WS',
        'soft-delete apply failed for $table#$localId',
        error,
        stack,
      );
      // Table has no deleted_at — trigger a pull to get server state
      _triggerSync(table);
      return;
    }

    // For tables where client-originated rows use local auto-increment ids
    // that don't match the server's (e.g. safe_transactions created via
    // client→server routing) the id-based UPDATE above is a no-op on those
    // rows. Trigger a sync so the strategy can reconcile by globalId and
    // replicate `deletedAt` onto the client's local copy.
    if (table == 'safe_transactions') {
      _triggerSync(table);
    }
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(_pingInterval, (_) {
      try {
        _channel?.sink.add(json.encode({'event': 'ping'}));
      } catch (_) {
        // A closed socket is expected while reconnecting; the reconnect loop
        // owns recovery and no financial state is changed here.
      }
    });
  }

  void _cleanup() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _subscription?.cancel();
    _subscription = null;
    for (final t in _pullDebounce.values) {
      t.cancel();
    }
    _pullDebounce.clear();
    try {
      _channel?.sink.close();
    } catch (_) {
      // Cleanup is idempotent; a channel already closed needs no recovery.
    }
    _channel = null;
  }

  /// Disconnect and stop reconnecting
  void disconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _cleanup();
    connected.value = false;
    debugPrint('[WS-Client] Manually disconnected');
  }

  void dispose() {
    disconnect();
    connected.dispose();
    _instance = null;
  }
}
