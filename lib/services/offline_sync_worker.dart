// ignore_for_file: avoid_dynamic_calls
import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../core/logging/diagnostic_logger.dart';
import '../data/database/database.dart';
import 'delta_pull_service.dart';
import 'network_service.dart';
import 'pos_terminal_registration_service.dart';
import 'server_proxy.dart';
import 'websocket_sync_client.dart';

part 'offline_sync_worker/offline_sync_worker_drain.dart';
part 'offline_sync_worker/offline_sync_worker_reconciliation.dart';
part 'offline_sync_worker/offline_sync_worker_replay_admin.dart';
part 'offline_sync_worker/offline_sync_worker_replay_finance.dart';
part 'offline_sync_worker/offline_sync_worker_replay.dart';

/// البند 5 (متطلبات العميل 2026-07-25) — رمز التعارض الذي يرسله الخادم حين
/// يرفض فاتورة مشتريات لأن رقم فاتورة المورد مستخدم بالفعل لهذا المورد.
///
/// Kept as a stable machine-readable token so the worker classifies the
/// conflict by contract, not by guessing at Arabic error prose.
const kDuplicateSupplierInvoiceNoCode = 'DUPLICATE_SUPPLIER_INVOICE_NO';

/// True when a server error is a BUSINESS conflict the operator must resolve —
/// as opposed to the benign "this exact row already exists" 409 that the worker
/// folds into success.
///
/// The distinction matters: the benign case means the server already holds the
/// operator's data, so marking the outbox item synced is correct. A business
/// conflict means the server holds *different* data under the same business
/// key — folding that into success silently DISCARDS the operator's invoice and
/// they are never told. Those must dead-letter so they surface in the
/// sync-failures UI.
bool isTerminalBusinessConflict(String error) =>
    error.contains(kDuplicateSupplierInvoiceNoCode);

Map<String, dynamic>? _serverPayloadFromConflict(String error) {
  final separator = error.indexOf('): ');
  if (separator < 0) return null;
  final body = error.substring(separator + 3);
  try {
    final decoded = jsonDecode(body);
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
  }
}

/// Event payload emitted by [OfflineSyncWorker.lastDeadLetterEvent] each time
/// an outbox item is moved to the dead-letter state. The shell listens for
/// this and surfaces a snackbar so the admin notices immediately rather than
/// waiting for them to open the sync management dialog.
class DeadLetterEvent {
  final String table;
  final String operation;
  final String reason;
  final DateTime timestamp;

  const DeadLetterEvent({
    required this.table,
    required this.operation,
    required this.reason,
    required this.timestamp,
  });
}

/// Top-level function for background JSON decode (Isolates)
Map<String, Map<String, int>> _decodeMappingsBackground(String jsonStr) {
  try {
    final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
    final Map<String, Map<String, int>> result = {};
    for (final table in decoded.keys) {
      final tableMap = decoded[table] as Map<String, dynamic>;
      result[table] = tableMap.map((k, v) => MapEntry(k, v as int));
    }
    return result;
  } catch (_) {
    // Corrupt cached id mappings are recoverable; the next successful drain
    // rebuilds them from server responses.
    return {};
  }
}

/// Top-level function for background JSON encode (Isolates)
  // ignore: unused_element
String _encodeMappingsBackground(Map<String, Map<String, int>> mappings) {
  return jsonEncode(mappings);
}

/// Background worker that drains the SyncOutbox when the server
/// connection is restored. Works in tandem with the
/// [ClientWriteInterceptor] which queues failed writes into the
/// outbox, and [ConnectionHealthWrapper] which triggers drain on
/// reconnect.
/// يقرا الـ`globalId` من payload مخزّن في طابور الأوفلاين.
///
/// ── ليه دالة مش قراءة مباشرة ────────────────────────────────────────────────
/// الـ`globalId` هو **مسار الـdedup الوحيد** على السيرفر لعمليات زي التحويل
/// المخزني: `postStockTransfer` بيفحصه قبل الحركات ويرجّع `dedup: true` لو
/// شافه قبل كده، و`/api/inventory/transfer` مش ضمن الـendpoints اللي بتقرا
/// هيدر `x-idempotency-key` — فالمفتاح لوحده بلا أثر هناك.
///
/// إعادة الإرسال من الطابور كانت بتسقط الحقل ده رغم إنه **مخزّن فعلاً** في
/// الـpayload (`cwi_trading.dart:673`)، فالسيرفر كان بيشوف الطلب المعاد
/// كطلب جديد ويخصم المخزون تاني. سبع cases تانية في نفس الـswitch بتمرّره
/// صح — دي كانت الشاذة.
///
/// الطابور فيه الشكلين (`globalId` من المعترض، `global_id` من مسارات أقدم)،
/// وصفوف قديمة بلا الحقل خالص لازم تعدّي بـ`null` مش بنص فاضي — السيرفر
/// بيتعامل مع `''` كقيمة موجودة.
@visibleForTesting
String? replayGlobalIdFrom(Map<String, dynamic> payload) {
  final raw = payload['globalId'] ?? payload['global_id'];
  if (raw is! String || raw.isEmpty) return null;
  return raw;
}

class OfflineSyncWorker {
  OfflineSyncWorker._();
  static final OfflineSyncWorker instance = OfflineSyncWorker._();

  AppDatabase? _db;
  bool _isDraining = false;
  Timer? _retryTimer;
  Timer? _heartbeatTimer;
  int _retryAttempts = 0;

  static const int _maxSyncAttempts = 10;
  // Tightened from 15s/300s → 3s/60s. The previous backoff parked failed
  // pushes on a 5-minute cap, which felt like "invoices vanished" to the
  // operator: the local UI marked them complete, the outbox waited silently
  // for minutes, and only the next manual sync surfaced them. With a 60-second
  // cap the worst-case wait after a transient failure stays inside an
  // operator's attention span.
  static const int _minRetrySeconds = 3;
  static const int _maxRetrySeconds = 60;
  static const int _heartbeatSeconds = 30;

  /// Floor between two drains triggered by the outbox WATCH stream.
  ///
  /// `watchSyncPendingCount()` re-emits on every write to `sync_outbox`, and
  /// `markAsSyncFailed` writes to that table while KEEPING the row `pending`.
  /// So a row the server keeps rejecting produced: drain → mark failed (write)
  /// → stream re-emits → drain again, immediately, with no delay — up to
  /// `_maxSyncAttempts` back-to-back cycles, each one replaying the batch AND
  /// (before this change) firing a full 41-table `pullAll()`. That is the
  /// retry storm behind "one or two clients load while the rest are fine".
  /// A single poison row — e.g. the purchase edit that always 500'd on the
  /// missing `warehouseId` — was enough to trigger it.
  static const Duration _watchDrainCooldown = Duration(seconds: 5);

  DateTime? _tokenVerifiedAt;
  DateTime _lastWatchDrain = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _watchDrainTimer;

  void _scheduleRetry() {
    _retryTimer?.cancel();
    final delay = (_minRetrySeconds * (1 << _retryAttempts.clamp(0, 5)))
        .clamp(_minRetrySeconds, _maxRetrySeconds);
    _retryAttempts++;
    debugPrint('[OfflineSyncWorker] ⏳ Retry in ${delay}s (backoff attempt $_retryAttempts)');
    _retryTimer = Timer(Duration(seconds: delay), () => drainOutbox(force: true));
  }

  /// Rate-limited entry point for drains triggered by the outbox watch stream.
  ///
  /// A fresh write (a new sale queued) still drains within
  /// [_watchDrainCooldown]; a row that keeps failing can no longer spin the
  /// loop. The heartbeat timer and the WebSocket-reconnect listener are
  /// unaffected — they remain immediate.
  void _requestWatchDrain() {
    final now = DateTime.now();
    final elapsed = now.difference(_lastWatchDrain);
    if (elapsed >= _watchDrainCooldown) {
      _lastWatchDrain = now;
      drainOutbox(force: true);
      return;
    }
    // Inside the cooldown: coalesce into ONE trailing drain so a write that
    // lands mid-cooldown is not left sitting until the 30 s heartbeat.
    if (_watchDrainTimer?.isActive == true) return;
    _watchDrainTimer = Timer(_watchDrainCooldown - elapsed, () {
      if (!NetworkService.instance.isClient) return;
      if (_isDraining) return;
      if (pendingCount.value <= 0) return;
      _lastWatchDrain = DateTime.now();
      drainOutbox(force: true);
    });
  }

  /// Pending items count for UI badges (yellow — waiting to sync)
  final ValueNotifier<int> pendingCount = ValueNotifier<int>(0);

  /// Dead-letter items count for UI badges (red — permanently failed, needs admin attention)
  final ValueNotifier<int> deadLetterCount = ValueNotifier<int>(0);

  /// Fires when an item moves from pending → dead_letter so the shell can
  /// surface a snackbar/toast for admin attention. Holds the most-recent
  /// event so listeners attached after the firing still see it (and can
  /// dedupe by timestamp). Set to null on app start.
  final ValueNotifier<DeadLetterEvent?> lastDeadLetterEvent =
      ValueNotifier<DeadLetterEvent?>(null);

  /// Initialize with the app database
  void initialize(AppDatabase db) {
    _db = db;
    DeltaPullService.instance.initialize(db);
    // Watch pending count
    db.watchSyncPendingCount().listen((count) {
      pendingCount.value = count;
      // Only auto-drain in CLIENT mode — standalone/server should never
      // attempt to sync to a remote server.
      if (count > 0 && !_isDraining && NetworkService.instance.isClient) {
        _requestWatchDrain();
      }
    });
    // Watch dead-letter count for the red alert badge
    db.watchSyncDeadLetterCount().listen((count) {
      deadLetterCount.value = count;
    });
    // Trigger drain immediately on WebSocket reconnect and reset backoff
    WebSocketSyncClient.instance.connected.addListener(() {
      if (WebSocketSyncClient.instance.connected.value && !_isDraining) {
        _retryAttempts = 0;
        drainOutbox(force: true);
        // Feature 009 / T012g — also retry POS terminal registration on
        // every reconnect so a freshly-online device that boot-failed
        // its first attempt gets registered without app restart.
        // Fire-and-forget: registerIfNeeded is itself idempotent.
        // ignore: discarded_futures
        PosTerminalRegistrationService.instance.registerIfNeeded();
      }
    });

    // Kick an initial drain on startup in case the outbox is non-empty at
    // launch. Drift's .watch() does emit an initial value, but the listener
    // races with server/websocket init — if the server is briefly unreachable
    // during the first tick, the retry lands on long backoff and the user
    // sees "stuck" outbox entries that only flush on manual "push invoices".
    // This explicit kick guarantees one fresh attempt once the app is up.
    // 1s is enough for HTTP/WebSocket init in practice; the previous 3s
    // delay made the "stuck invoice on app open" symptom drag on visibly.
    Future.delayed(const Duration(seconds: 1), () async {
      // 068 (D2-003): if not in client mode but the outbox has rows, that
      // means a paired client was flipped back to standalone (or
      // server/mirror) AFTER local writes had already queued. Those rows
      // will never drain and never raise an alert under the legacy
      // strict-isClient gate. Emit a SYNC-WARN now so the diagnostic log
      // captures the dead-letter situation; the existing
      // watchSyncDeadLetterCount + sync-pending banner already surface it
      // visually once the user opens the sync screen.
      if (!NetworkService.instance.isClient) {
        final stranded = await db.getPendingSyncItems(limit: 1);
        if (stranded.isNotEmpty) {
          unawaited(DiagnosticLogger.log(
            'SYNC-WARN',
            'stranded outbox: ${pendingCount.value} pending row(s) on '
                '${NetworkService.instance.mode.name} mode '
                '(non-client) — these will never drain. Likely a '
                'paired-client → standalone/server flip after offline '
                'writes. Investigate via sync screen.',
          ));
        }
        return;
      }
      final pending = await db.getPendingSyncItems(limit: 1);
      if (pending.isNotEmpty && !_isDraining) {
        debugPrint('[OfflineSyncWorker] 🚀 Startup drain — ${pendingCount.value} pending');
        drainOutbox(force: true);
      }
    });

    // Heartbeat: every 30s, if the outbox has pending rows and we are in
    // client mode, force a drain attempt. Covers the case where the
    // websocket stays disconnected (or reconnected silently without firing
    // the listener) and the exponential backoff has parked on its 5-minute
    // cap — the user shouldn't have to click "force push" to unstick it.
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: _heartbeatSeconds), (_) {
      if (!NetworkService.instance.isClient) return;
      if (_isDraining) return;
      if (pendingCount.value <= 0) return;
      drainOutbox(force: true);
    });
  }

  /// Ensure the API token is available and fresh before draining.
  /// Re-verifies with the server every 5 minutes — catches expired/rotated tokens
  /// that remain non-null in memory but are rejected with 401 by the server.
  Future<bool> _ensureApiToken() async {
    final proxy = ServerProxy.instance;
    final tokenMissing = proxy.apiToken == null || proxy.apiToken!.isEmpty;
    final tokenStale = _tokenVerifiedAt == null ||
        DateTime.now().difference(_tokenVerifiedAt!) > const Duration(minutes: 5);

    if (!tokenMissing && !tokenStale) return true;

    final ns = NetworkService.instance;
    final addr = ns.serverAddress ?? '';
    if (addr.isEmpty) return false;

    debugPrint('[OfflineSyncWorker] ${tokenMissing ? "Token missing" : "Token stale"} — re-verifying with server...');
    final result = await ns.testServerConnection(addr, ns.serverPort);
    if (result['success'] == true) {
      _tokenVerifiedAt = DateTime.now();
      debugPrint('[OfflineSyncWorker] ✅ Token verified');
      // Spec 151 (P1-8) — now that the server is reachable, mint the signed
      // per-user session token for anyone who logged in while offline (or
      // whose token was evicted by a prior 401). No-op when a token is already
      // cached / no proof / not client mode. Never throws.
      await proxy.ensureSession();
      return true;
    }
    debugPrint('[OfflineSyncWorker] ⚠️ Token verification failed: ${result['error']}');
    return false;
  }

  /// Spec 136 ISS-21 — resolve the idempotency key for replaying a queued
  /// outbox item. Prefer the globally-unique UUIDv7 that
  /// ClientWriteInterceptor._tryOrQueue stored in `payload['idempotency_key']`;
  /// fall back to the legacy `SyncOutbox_<localId>` only for old rows that
  /// predate that key. The legacy form is NOT globally unique (the local outbox
  /// id restarts after a wipe/reinstall and repeats across devices) and collided
  /// with the server's persistent `processed_messages`, silently dropping new
  /// offline invoices.
  @visibleForTesting
  static String idempotencyKeyFor(Map<String, dynamic> payload, int outboxId) {
    final storedKey = payload['idempotency_key'] as String?;
    return (storedKey != null && storedKey.isNotEmpty)
        ? storedKey
        : 'SyncOutbox_$outboxId';
  }

  /// The update-shaped payloads are queued as `{'id': id, ...data}`, but the
  /// proxy's update methods take the id separately and expect only the changed
  /// fields. Sending `id` back inside the body would let the server overwrite
  /// its own primary key with the CLIENT's autoincrement — the ids diverge
  /// between instances, so that is a row-corrupting edit, not a no-op.
  /// The routing-only flags are stripped for the same reason: they are how the
  /// producer tags which endpoint to call, not columns on the table.
  static Map<String, dynamic> _withoutId(Map<String, dynamic> payload) {
    final copy = Map<String, dynamic>.from(payload)..remove('id');
    copy.remove('idempotency_key');
    copy.remove('setDefault');
    copy.remove('unsetDefault');
    return copy;
  }

  void dispose() {
    _retryTimer?.cancel();
    _heartbeatTimer?.cancel();
    pendingCount.dispose();
  }
}
