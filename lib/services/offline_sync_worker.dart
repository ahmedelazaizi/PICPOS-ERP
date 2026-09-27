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

  /// Drain all pending outbox items by replaying them via ServerProxy.
  /// Called when WebSocket reconnects, HTTP polling succeeds, or manually.
  /// Set [force] to true to skip the WebSocket connectivity check
  /// (used by the periodic HTTP sync timer).
  Future<void> drainOutbox({bool force = false}) async {
    if (_isDraining || _db == null) return;
    if (!force && !WebSocketSyncClient.instance.connected.value) return;

    _isDraining = true;

    try {
      // Load persistent ID mappings for reconciliation
      final Map<String, Map<String, int>> mappedIds = await _loadIdMappings();

      // CRITICAL: Ensure we have a valid API token before sending any requests.
      // Without this, all POST calls will fail with 401 Unauthorized.
      final hasToken = await _ensureApiToken();
      if (!hasToken) {
        debugPrint('[OfflineSyncWorker] ❌ Cannot drain: no API token (server unreachable)');
        _scheduleRetry();
        return;
      }
      _retryAttempts = 0; // server reachable — reset backoff

      // Server IS reachable (token fetch succeeded) — reset any permanently
      // failed items so they get a fresh chance to sync.
      final resetCount = await _db!.resetFailedSyncItems();
      if (resetCount > 0) {
        debugPrint('[OfflineSyncWorker] ♻️ Reset $resetCount permanently failed items back to pending');
      }

      // Check if there are pending items
      final pendingCheck = await _db!.getPendingSyncItems(limit: 1);
      if (pendingCheck.isEmpty) {
        debugPrint('[OfflineSyncWorker] ✅ No pending items in outbox');
        return;
      }

      debugPrint('[OfflineSyncWorker] Starting outbox drain...');
      int synced = 0;
      int failed = 0;
      bool mappingsUpdated = false;

      while (true) {
        // Issue 7 — bumped batch from 50 → 200 so a backed-up outbox
        // (e.g. 1000 pending operations after a long offline window)
        // drains in 5 iterations instead of 20. Each item is still
        // sent serially within an iteration to preserve ordering.
        final items = await _db!.getPendingSyncItems(limit: 200);
        if (items.isEmpty) break;

        for (final item in items) {
          try {
            final originalPayload =
                jsonDecode(item.payload) as Map<String, dynamic>;

            // Reconcile IDs locally before sending to server
            final mappedPayload = _applyIdMappings(item.targetTable, originalPayload, mappedIds);

            // CRITICAL PRE-FLIGHT: for sales/returns/held-orders, ensure
            // every product referenced in the items list has a server-
            // side mapping. If not, push the product FIRST (out of
            // order) so the sale doesn't fail with FK 23503 on
            // sales_invoice_items.products_id.
            //
            // Root cause of the regression this guards against: a
            // client-mode detection race at product-create time. If
            // `SyncInterceptor.isClientMode` briefly returned false
            // during startup, `ClientWriteInterceptor.createProduct`
            // early-returned without queueing anything, so the product
            // only existed locally. Sales created later referenced
            // those local product ids that the server never heard of
            // → every drain attempt hit 23503 forever and the 4 failed
            // rows the user showed in the sync dialog piled up until
            // they dead-lettered.
            if (['sales', 'sales_returns', 'held_orders'].contains(item.targetTable)) {
              await _ensureProductsMappedOrPushed(
                mappedPayload['items'] as List?,
                mappedIds,
                proxy: ServerProxy.instance,
                outboxId: item.id,
              );
            }

            // Re-apply mappings AFTER the pre-flight resolved any new
            // ids (the list was mutated in place; items field may now
            // carry server ids).
            final reMappedPayload = _applyIdMappings(item.targetTable, mappedPayload, mappedIds);

            // Enrich payload: add createdByUsername so server can resolve
            // user IDs by username when client/server IDs diverge.
            final enrichedPayload = await _enrichWithUsername(reMappedPayload);

            final dynamic result = await _replayOperation(
              item.targetTable,
              item.operation,
              enrichedPayload,
              item.id,
            );

            // Capture new Server IDs to map dependent entities
            final int? serverId = result is int
                ? result
                : result is Map
                    ? ((result['serverId'] as int?) ?? (result['id'] as int?))
                    : null;
            if (serverId != null) {
                // Resolve the local ID either from `item.recordId` or by querying name/code
                int? localId;
                    if (item.targetTable == 'parties') {
                        final p = await _db!.getPartyByName(originalPayload['name']?.toString() ?? '', false);
                        localId = p?.id;
                    } else if (item.targetTable == 'products') {
                        final pItem = await _db!.getProductByCode(originalPayload['code']?.toString() ?? '');
                        localId = pItem?.id;
                    } else if (item.targetTable == 'units') {
                        // Resolve unit localId by name and symbol
                        final u = await _db!.customSelect(
                            'SELECT id FROM units WHERE name = ? AND symbol = ? LIMIT 1',
                            variables: [
                                Variable<String>(originalPayload['name']?.toString() ?? ''),
                                Variable<String>(originalPayload['symbol']?.toString() ?? ''),
                            ],
                        ).getSingleOrNull();
                        localId = u?.read<int>('id');
                    } else if (item.recordId != '0') {
                        localId = int.tryParse(item.recordId);
                    }

                    if (localId != null) {
                        mappedIds[item.targetTable] ??= {};
                        mappedIds[item.targetTable]![localId.toString()] = serverId;
                        mappingsUpdated = true;
                        debugPrint('[OfflineSyncWorker] 🔗 Mapped ${item.targetTable} Local ID $localId -> Server ID $serverId');
                        // Persist immediately to the relational FK remap table (P2.2)
                        final gid = originalPayload['globalId'] as String?;
                        unawaited(_db!.storeFkMapping(
                          tableName: item.targetTable,
                          localId: localId,
                          remoteId: serverId,
                          globalId: gid,
                        ));
                    }
                }

            await _db!.markAsSyncSuccess(item.id);
            synced++;
            // Spec 136 — breadcrumb the offline→online recovery of the
            // user-visible transactional rows. Success was previously
            // print-only, so a sale made offline showed only its
            // "⏳ queued offline" line and never a confirmation that it
            // reached the server — it looked like the invoice vanished. This
            // closes the loop in the login log (queued → drained → serverId).
            // Spec 136 item 6 — widened to every user-visible money/stock
            // outbox type so safes (safe_transactions/safe_transfers),
            // receipt + payment vouchers (receipts/expenses), inventory
            // adjustments and stock transfers also confirm in the login log
            // (item.operation already distinguishes e.g. safes/close vs
            // inventory/adjust).
            if (const {
              'sales', 'sales_returns', 'held_orders', 'purchases',
              'expenses', 'receipts',
              'safe_transactions', 'safe_transfers',
              'inventory', 'stock_transfers',
            }.contains(item.targetTable)) {
              unawaited(DiagnosticLogger.log(
                'OUTBOX-DRAIN',
                '✓ ${item.targetTable}/${item.operation} outboxId=${item.id} '
                '→ serverId=${serverId ?? '-'}',
              ));
            }
            debugPrint(
              '[OfflineSyncWorker] ✅ Synced ${item.targetTable}/${item.operation} #${item.id}',
            );
          } catch (e) {
            final errorStr = e.toString();
            // Distinguish between network errors and real server errors
            final isNetworkError =
                errorStr.contains('SocketException') ||
                errorStr.contains('Connection refused') ||
                errorStr.contains('Connection reset') ||
                errorStr.contains('TimeoutException') ||
                errorStr.contains('HandshakeException');

            if (isNetworkError) {
              // Network error — DON'T burn retry attempts, just pause and retry later
              debugPrint('[OfflineSyncWorker] ⚠️ Network error on item #${item.id} — pausing drain');
              _scheduleRetry();
              return;
            }

            // 429 Rate limited — DON'T burn retry attempts, wait for the rate-limit window.
            final isRateLimited =
                errorStr.contains('429') ||
                errorStr.contains('Too many requests') ||
                errorStr.contains('rate limit');

            if (isRateLimited) {
              // Extract retryAfterSeconds from the server response if present.
              int waitSecs = 65; // default: slightly more than the 60s window
              final match = RegExp(r'retryAfterSeconds[":]+\s*(\d+)').firstMatch(errorStr);
              if (match != null) waitSecs = (int.tryParse(match.group(1) ?? '') ?? 60) + 5;
              debugPrint('[OfflineSyncWorker] ⏳ Rate limited (429) on item #${item.id} — pausing ${waitSecs}s');
              _retryTimer?.cancel();
              _retryTimer = Timer(Duration(seconds: waitSecs), () => drainOutbox(force: true));
              return;
            }

            // 401 Unauthorized — token expired or invalidated since drain started.
            // Force re-verify on next cycle so a fresh token is obtained before retry.
            final isUnauthorized =
                errorStr.contains('401') ||
                errorStr.toLowerCase().contains('unauthorized') ||
                errorStr.contains('Invalid token') ||
                errorStr.contains('Expired token');

            if (isUnauthorized) {
              _tokenVerifiedAt = null; // Force re-verify next cycle
              // Spec 151 (P1-8) — a 401 may mean the signed session token
              // expired/was rejected. Evict it (keeping the in-memory proof)
              // so the next _ensureApiToken → ensureSession re-mints a fresh
              // one before the retry.
              ServerProxy.instance.invalidateSessionToken();
              debugPrint('[OfflineSyncWorker] 🔑 401 on item #${item.id} — token may be expired, scheduling re-verify');
              _scheduleRetry();
              return;
            }

            // البند 5: a BUSINESS conflict (different data under the same
            // business key) must NOT be folded into success — that would drop
            // the operator's invoice silently. Dead-letter it so it appears in
            // the sync-failures UI with the server's Arabic reason.
            if (isTerminalBusinessConflict(errorStr)) {
              failed++;
              await _db!.markAsSyncDeadLetter(item.id, errorStr);
              lastDeadLetterEvent.value = DeadLetterEvent(
                table: item.targetTable,
                operation: item.operation,
                reason: errorStr,
                timestamp: DateTime.now(),
              );
              debugPrint('[OfflineSyncWorker] ⛔ Business conflict on item #${item.id} '
                  '— dead-lettered, operator action required: $errorStr');
              unawaited(DiagnosticLogger.log('SYNC-WARN',
                  '⛔ BUSINESS-CONFLICT table=${item.targetTable} '
                  'op=${item.operation} id=${item.id} reason=$errorStr'));
              continue;
            }

            // 409 Conflict or duplicate — data already exists on server.
            // Mark as synced (not failed) to prevent infinite retries.
            final isConflict =
                errorStr.contains('409') ||
                errorStr.contains('Conflict') ||
                errorStr.contains('UNIQUE constraint') ||
                errorStr.contains('duplicate') ||
                errorStr.contains('already exists');

            if (isConflict) {
              final serverPayload = _serverPayloadFromConflict(errorStr);
              if (kFinancialSyncTables.contains(item.targetTable)) {
                try {
                  await _db!.into(_db!.syncConflictLog).insert(
                    SyncConflictLogCompanion.insert(
                      conflictTable: item.targetTable,
                      recordId: item.recordId,
                      resolution: 'pending_review',
                      clientPayload: item.payload,
                      serverPayload: Value(
                        serverPayload == null ? null : jsonEncode(serverPayload),
                      ),
                      reason: Value(
                        'بيانات مالية متعارضة؛ بقيت العملية معلقة للمراجعة: '
                        '${errorStr.substring(0, errorStr.length.clamp(0, 200))}',
                      ),
                      clientId: const Value(null),
                    ),
                  );
                } catch (error, stack) {
                  await DiagnosticLogger.logError(
                    'SYNC-CONFLICT',
                    'financial outbox conflict log failed for ${item.targetTable}/${item.recordId}',
                    error,
                    stack,
                  );
                }
                await DiagnosticLogger.log(
                  'SYNC-CONFLICT',
                  'financial outbox conflict pending review table=${item.targetTable} '
                  'record=${item.recordId}',
                );
                continue;
              }

              synced++;
              await _db!.markAsSyncSuccess(item.id);
              // Pull the server's authoritative version so the local row converges
              unawaited(
                DeltaPullService.instance.pullTable(item.targetTable).catchError((Object e) {
                  debugPrint('[OfflineSyncWorker] Delta pull after conflict failed (${item.targetTable}): $e');
                }),
              );
              // Log the conflict for audit
              try {
                await _db!.into(_db!.syncConflictLog).insert(
                  SyncConflictLogCompanion.insert(
                    conflictTable: item.targetTable,
                    recordId: item.recordId,
                    resolution: 'server_wins_pull_triggered',
                    clientPayload: item.payload,
                    serverPayload: Value(
                      serverPayload == null ? null : jsonEncode(serverPayload),
                    ),
                    reason: Value('بيانات موجودة بالفعل على السيرفر: ${errorStr.substring(0, errorStr.length.clamp(0, 200))}'),
                    clientId: const Value(null),
                  ),
                );
              } catch (error, stack) {
                await DiagnosticLogger.logError(
                  'SYNC-CONFLICT',
                  'conflict log insert failed for ${item.targetTable}/${item.recordId}',
                  error,
                  stack,
                );
              }
              debugPrint(
                '[OfflineSyncWorker] ⚠️ Conflict on item #${item.id} (${item.targetTable}) — marked as synced, pulling server state',
              );
              continue;
            }

            // Permanent validation errors — retrying will NEVER help.
            // Immediately dead-letter instead of burning 10 retry attempts.
            // The admin can manually retry from the sync management dialog
            // after fixing the underlying data issue (e.g. re-sync users).
            final isPermanentError =
                errorStr.contains('Strict Mapping Violation') ||
                errorStr.contains('not found on server') ||
                errorStr.contains('Validation Error: Valid userId') ||
                errorStr.contains('Validation Error: Valid warehouseId') ||
                errorStr.contains('Shift not found') ||
                // FIX 2026-04-28: stock validation + invalid items are permanent.
                // Without this, a sale referencing a product the server doesn't
                // have (e.g. local-only product from old build with id 1000000001+)
                // loops forever — the server log filled with 50+ identical
                // "غير متوفر نهائياً" failures for the same POS-2.
                errorStr.contains('غير متوفر نهائياً') ||
                errorStr.contains('item missing productId') ||
                errorStr.contains('Validation Error: item missing') ||
                errorStr.contains('Purchase invoice not found') ||
                // L4 (2026-04-28): cross-branch authorization failures are
                // permanent — retrying with the same branch/warehouse pair
                // will never succeed. Admin must fix the device pairing or
                // warehouse assignment before retrying.
                errorStr.contains('Authorization Error') ||
                errorStr.contains('Cross-branch operation denied') ||
                // A permission denial is permanent FOR THIS ACTOR — the same
                // payload replayed by the same user always fails. Without
                // this it burned all 10 attempts against the server before
                // dead-lettering. Covers both denial shapes:
                //   • ApiUserCtx.requirePermission → 403 "User #N lacks
                //     permission: <code>"
                //   • PermissionEnforcer.requireCriticalOp → 403 with an
                //     Arabic reason; every one of those messages contains
                //     "لا تملك صلاحية" or "يلزم صلاحية".
                // Recovery once an admin grants the permission is the
                // existing "إعادة محاولة الكل" button, which resets
                // dead-letter rows to pending (retryAllDeadLetterItems).
                errorStr.contains('lacks permission') ||
                errorStr.contains('لا تملك صلاحية') ||
                errorStr.contains('يلزم صلاحية') ||
                // Spec 136 (field 2026-06-04): an unbalanced journal entry
                // (debit ≠ credit beyond the balance tolerance — 0.01 since
                // Spec 139) is a
                // data/logic defect in the invoice itself — replaying the
                // identical payload will ALWAYS fail. Without this, invoice
                // AQ-POS-1 retried up to _maxSyncAttempts (10) and EACH
                // attempt inserted+rolled back a sale on the server, churning
                // the invoice sequence and flooding the log with ~40 identical
                // failures. Dead-letter immediately; the GL fix
                // (autoPostCashSale/CreditSale discount derivation) prevents
                // the imbalance for new sales, this caps any residual poison.
                errorStr.contains('خطأ في قيد اليومية') ||
                errorStr.contains('لا يساوي الدائن') ||
                // Spec 136 (field 2026-06-14): selling a product from the wrong
                // warehouse (it lives only in another warehouse) is permanent —
                // the payload's warehouseId never changes on replay, so it
                // looped ~40× in the server log (QRS-POS-6). Dead-letter it; the
                // operator must re-issue from the correct warehouse.
                errorStr.contains('خاص بمستودع آخر') ||
                errorStr.contains('اختر المستودع الصحيح') ||
                // BLOCKER C-01 (Spec 151): an unknown sync table (thrown by the
                // switch `default:` in _replayOperation) is a permanent dispatch
                // defect — no code path exists to replay it, so retrying is
                // pointless. Dead-letter immediately so the drop is surfaced in
                // the SYNC-WARN log instead of being silently marked synced.
                errorStr.contains('Unknown sync table');

            if (isPermanentError) {
              failed++;
              await _db!.markAsSyncDeadLetter(item.id, errorStr);
              lastDeadLetterEvent.value = DeadLetterEvent(
                table: item.targetTable,
                operation: item.operation,
                reason: errorStr,
                timestamp: DateTime.now(),
              );
              debugPrint(
                '[OfflineSyncWorker] 🚫 Permanent validation error on item #${item.id} — immediately dead-lettered (manual retry needed): $e',
              );
              // Surface in persistent diagnostic log so the operator can
              // identify exactly which invoices/operations were dropped.
              unawaited(DiagnosticLogger.log('SYNC-WARN',
                  '🚫 DEAD-LETTER table=${item.targetTable} op=${item.operation} '
                  'id=${item.id} reason=$errorStr'));
              continue;
            }

            // Server/logic error — increment attempts
            failed++;
            debugPrint(
              '[OfflineSyncWorker] ❌ Server error item #${item.id} (attempt ${item.attempts + 1}): $e',
            );
            if (item.attempts >= _maxSyncAttempts) {
              await _db!.markAsSyncDeadLetter(item.id, errorStr);
              lastDeadLetterEvent.value = DeadLetterEvent(
                table: item.targetTable,
                operation: item.operation,
                reason: errorStr,
                timestamp: DateTime.now(),
              );
              debugPrint('[OfflineSyncWorker] 🚫 Item #${item.id} moved to dead_letter after ${item.attempts + 1} attempts');
              unawaited(DiagnosticLogger.log('SYNC-WARN',
                  '🚫 DEAD-LETTER table=${item.targetTable} op=${item.operation} '
                  'id=${item.id} attempts=${item.attempts + 1} reason=$errorStr'));
            } else {
              await _db!.markAsSyncFailed(item.id, errorStr);
            }
          }
        }
      }

      // Save ID mappings to SQLite settings for safety if we stopped early
      if (mappingsUpdated) {
        await _saveIdMappings(mappedIds);
      }

      if (failed == 0) _retryAttempts = 0;
      debugPrint('[OfflineSyncWorker] Outbox drain complete: $synced synced, $failed failed');
      // Spec 136 — one summary line per productive drain so the operator can
      // see, in the login log, that the offline queue was flushed (and how many
      // remain) instead of inferring it from silence.
      if (synced > 0 || failed > 0) {
        final remaining = await _db!.getPendingSyncItems(limit: 1);
        unawaited(DiagnosticLogger.log(
          'OUTBOX-DRAIN',
          'cycle complete synced=$synced failed=$failed '
          'remaining=${remaining.isEmpty ? 0 : '1+'}',
        ));
      }
      // Pull server changes back — but ONLY when this drain actually pushed
      // something. `pullAll()` is 41 sequential HTTP round-trips; firing it
      // unconditionally meant every drain cycle, including the ones that
      // pushed nothing because the batch was all failures, cost the server
      // another 41 requests. Combined with the watch-stream retry loop above,
      // a single stuck outbox row generated hundreds of pulls per minute from
      // one client. A drain that synced nothing has, by definition, no new
      // server-side result to fetch.
      if (synced > 0) {
        unawaited(DeltaPullService.instance.pullAll());
      }
    } catch (e) {
      debugPrint('[OfflineSyncWorker] Drain error: $e');
      _scheduleRetry();
    } finally {
      _isDraining = false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RECONCILIATION MAPPING LOGIC
  // ═══════════════════════════════════════════════════════════════════════════

  /// Pre-flight: for every `productId` referenced in a sale/return payload,
  /// make sure we either have a server mapping OR can push the product now.
  ///
  /// This plugs a race that produces FK 23503 errors on the server:
  ///   - User creates product on client with local id X.
  ///   - Client-mode detection briefly off → no outbox row queued.
  ///   - User creates a sale referencing product X.
  ///   - Sale goes into the outbox.
  ///   - Drain replays the sale → server sees productId X which never
  ///     arrived → foreign-key violation → dead-letter loop.
  ///
  /// Recovery: when we see an unmapped productId, look up the local
  /// product row, POST it via `createProduct` immediately (out of
  /// queue order), capture the server id, and inject the mapping so
  /// the re-applied payload sends the correct id to the server.
  Future<void> _ensureProductsMappedOrPushed(
    List? items,
    Map<String, Map<String, int>> mappedIds, {
    required ServerProxy proxy,
    required int outboxId,
  }) async {
    if (items == null || items.isEmpty) return;
    if (_db == null) return;

    final productMap = mappedIds.putIfAbsent('products', () => {});

    for (final raw in items) {
      final item = raw is Map ? raw : null;
      if (item == null) continue;
      final rawPid = item['productId'] ?? item['product_id'];
      if (rawPid == null) continue;
      final localIdStr = rawPid.toString();

      // Already mapped OR the value is itself already a server id we've
      // captured from a previous drain → nothing to do.
      if (productMap.containsKey(localIdStr)) continue;
      if (productMap.values.contains(rawPid is int ? rawPid : int.tryParse(localIdStr))) continue;

      // Not mapped — look up the local product and push it now.
      try {
        final localId = int.tryParse(localIdStr);
        if (localId == null) continue;
        final product = await _db!.getProductById(localId);
        if (product == null) {
          debugPrint('[OfflineSyncWorker] ⚠️ pre-flight: local product $localId missing — sale will '
              'fail server FK check. Skipping product push.');
          continue;
        }

        debugPrint('[OfflineSyncWorker] 🔄 pre-flight: product local=$localId '
            '(code=${product.code}) has no server mapping — pushing now to resolve sale $outboxId');

        // Ensure the local product has a globalId so the server's UUID-based
        // idempotency check in postProduct short-circuits on retries instead
        // of inserting a fresh row each time. Missing globalId was the root
        // cause of duplicate server rows (appearing as productType='product'
        // — displayed as "عام" — because the other metadata was also omitted).
        String? effectiveGlobalId = product.globalId;
        if (effectiveGlobalId == null || effectiveGlobalId.isEmpty) {
          effectiveGlobalId = const Uuid().v7();
          try {
            await (_db!.update(_db!.products)
                  ..where((p) => p.id.equals(localId)))
                .write(ProductsCompanion(globalId: Value(effectiveGlobalId)));
          } catch (e) {
            debugPrint('[OfflineSyncWorker] pre-flight: failed to persist globalId on local product $localId: $e');
          }
        }

        // Mirror the full ClientWriteInterceptor.createProduct payload so the
        // server reconstructs the product exactly — productType, globalId,
        // warehouseId, extended price tiers, and scale metadata must all be
        // present. A partial payload here creates a server row that differs
        // from the client's and appears as a duplicate after the next pull.
        String? categoryGlobalId;
        String? categoryName;
        String? categoryColor;
        if (product.categoryId != null) {
          try {
            final cat = await (_db!.select(_db!.categories)
                  ..where((c) => c.id.equals(product.categoryId!))
                  ..limit(1))
                .getSingleOrNull();
            if (cat != null) {
              categoryGlobalId = cat.globalId;
              categoryName = cat.name;
              categoryColor = cat.color;
              if (categoryGlobalId == null || categoryGlobalId.isEmpty) {
                categoryGlobalId = const Uuid().v7();
                try {
                  await (_db!.update(_db!.categories)
                        ..where((c) => c.id.equals(product.categoryId!)))
                      .write(CategoriesCompanion(globalId: Value(categoryGlobalId)));
                } catch (error, stack) {
      // Mapping failures are recoverable, but must remain diagnosable because
      // stale FK mappings can make a financial replay target the wrong row.
      unawaited(DiagnosticLogger.logError(
        'SYNC-MAPPING',
        'best-effort mapping operation failed',
        error,
        stack,
      ));
    }
              }
            }
          } catch (e) {
            debugPrint('[OfflineSyncWorker] pre-flight: category lookup failed (non-fatal): $e');
          }
        }

        final payload = <String, dynamic>{
          'globalId': effectiveGlobalId,
          'code': product.code,
          'name': product.name,
          'salePrice': product.salePrice,
          'costPrice': product.costPrice,
          'categoryId': product.categoryId,
          'categoryGlobalId': categoryGlobalId,
          'categoryName': categoryName,
          'categoryColor': categoryColor,
          'supplierId': product.supplierId,
          'unitId': product.unitId,
          'currentStock': product.currentStock,
          'barcode': product.barcode,
          'minStock': product.minStock,
          'taxRate': product.taxRate,
          'isSoldByWeight': product.isSoldByWeight,
          'allowNegativeSale': product.allowNegativeSale,
          'trackExpiry': product.trackExpiry,
          'defaultShelfDays': product.defaultShelfDays,
          'alertDaysBefore': product.alertDaysBefore,
          'pricePerUnit': product.pricePerUnit,
          'wholesalePrice': product.wholesalePrice,
          'priceTalabat': product.priceTalabat,
          'priceCareem': product.priceCareem,
          'priceAshyae': product.priceAshyae,
          'scaleType': product.scaleType,
          'scalePluNumber': product.scalePluNumber,
          'productType': product.productType,
          'warehouseId': product.warehouseId,
        };

        final serverId = await proxy.createProduct(
          payload,
          idempotencyKey: 'preflight_prod_${product.code}_$localId',
        );
        if (serverId != null && serverId != 0) {
          productMap[localIdStr] = serverId;
          debugPrint('[OfflineSyncWorker] ✅ pre-flight: product local=$localId → server=$serverId');
        } else {
          debugPrint('[OfflineSyncWorker] ⚠️ pre-flight: createProduct returned null/0 for '
              'local=$localId — sale $outboxId may still 23503');
        }
      } catch (e) {
        final err = e.toString();
        // Conflict = product already exists on server with matching code
        // (e.g. by prior sync). Fetch server id by code so the mapping
        // is captured even though the POST itself "failed".
        if (err.contains('409') ||
            err.contains('Conflict') ||
            err.contains('UNIQUE constraint') ||
            err.contains('already exists') ||
            err.contains('duplicate')) {
          debugPrint('[OfflineSyncWorker] pre-flight: product $localIdStr already on server — '
              'mapping will be resolved server-side on retry');
          continue;
        }
        debugPrint('[OfflineSyncWorker] ⚠️ pre-flight push failed for product $localIdStr: $e');
        // Continue — the sale replay will fail its own FK check and move
        // through the normal error handling (attempt counter / retry).
      }
    }
  }

  Future<Map<String, Map<String, int>>> _loadIdMappings() async {
    if (_db == null) return {};
    // Load from the persistent FK remap table (P2.2)
    try {
      final dbMappings = await _db!.loadAllFkMappings();
      if (dbMappings.isNotEmpty) return dbMappings;
    } catch (error, stack) {
      // Mapping failures are recoverable, but must remain diagnosable because
      // stale FK mappings can make a financial replay target the wrong row.
      unawaited(DiagnosticLogger.logError(
        'SYNC-MAPPING',
        'best-effort mapping operation failed',
        error,
        stack,
      ));
    }
    // Fallback: migrate one-time from the legacy JSON blob in settings
    try {
      final jsonStr = await _db!.getSettingValue('_sync_id_mappings');
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final legacy = await compute(_decodeMappingsBackground, jsonStr);
        if (legacy.isNotEmpty) {
          await _db!.bulkStoreFkMappings(legacy);
          debugPrint('[OfflineSyncWorker] Migrated ${legacy.length} tables from JSON blob → remote_id_mappings');
        }
        return legacy;
      }
    } catch (error, stack) {
      // Mapping failures are recoverable, but must remain diagnosable because
      // stale FK mappings can make a financial replay target the wrong row.
      unawaited(DiagnosticLogger.logError(
        'SYNC-MAPPING',
        'best-effort mapping operation failed',
        error,
        stack,
      ));
    }
    return {};
  }

  Future<void> _saveIdMappings(Map<String, Map<String, int>> mappings) async {
    if (_db == null || mappings.isEmpty) return;
    try {
      await _db!.bulkStoreFkMappings(mappings);
    } catch (error, stack) {
      // Mapping failures are recoverable, but must remain diagnosable because
      // stale FK mappings can make a financial replay target the wrong row.
      unawaited(DiagnosticLogger.logError(
        'SYNC-MAPPING',
        'best-effort mapping operation failed',
        error,
        stack,
      ));
    }
  }

  /// Enrich a payload with `createdByUsername` so the server can resolve user
  /// IDs by username when client/server auto-increment IDs diverge.
  /// Only adds the field if `userId` is present and `createdByUsername` is absent.
  Future<Map<String, dynamic>> _enrichWithUsername(Map<String, dynamic> payload) async {
    if (_db == null) return payload;
    final userId = payload['userId'];
    if (userId == null || payload.containsKey('createdByUsername')) return payload;
    try {
      final uid = userId is int ? userId : int.tryParse(userId.toString());
      if (uid == null || uid == 0) return payload;
      final user = await _db!.getUserById(uid);
      if (user != null) {
        final enriched = Map<String, dynamic>.from(payload);
        enriched['createdByUsername'] = user.user.username;
        return enriched;
      }
    } catch (error, stack) {
      // Mapping failures are recoverable, but must remain diagnosable because
      // stale FK mappings can make a financial replay target the wrong row.
      unawaited(DiagnosticLogger.logError(
        'SYNC-MAPPING',
        'best-effort mapping operation failed',
        error,
        stack,
      ));
    }
    return payload;
  }

  Map<String, dynamic> _applyIdMappings(String table, Map<String, dynamic> payload, Map<String, Map<String, int>> mappings) {
    if (mappings.isEmpty) return payload;
    final p = Map<String, dynamic>.from(payload);

    // Sales and Returns mapping
    if (['sales', 'sales_returns', 'held_orders'].contains(table)) {
      if (p['customerId'] != null && mappings['parties']?.containsKey(p['customerId'].toString()) == true) {
        p['customerId'] = mappings['parties']![p['customerId'].toString()];
      }
    }
    // Purchases mapping
    if (['purchases', 'purchase_invoices'].contains(table)) {
      if (p['supplierId'] != null && mappings['parties']?.containsKey(p['supplierId'].toString()) == true) {
        p['supplierId'] = mappings['parties']![p['supplierId'].toString()];
      }
      if (p['supplier_id'] != null && mappings['parties']?.containsKey(p['supplier_id'].toString()) == true) {
        p['supplier_id'] = mappings['parties']![p['supplier_id'].toString()];
      }
    }
    // Items Mapping
    if (p['items'] is List) {
      final items = (p['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      for (var item in items) {
        if (item['productId'] != null && mappings['products']?.containsKey(item['productId'].toString()) == true) {
          item['productId'] = mappings['products']![item['productId'].toString()];
        }
        if (item['product_id'] != null && mappings['products']?.containsKey(item['product_id'].toString()) == true) {
          item['product_id'] = mappings['products']![item['product_id'].toString()];
        }
      }
      p['items'] = items;
    }
      if (p['partyId'] != null && mappings['parties']?.containsKey(p['partyId'].toString()) == true) {
        p['partyId'] = mappings['parties']![p['partyId'].toString()];
      }
    // Product Unit & Barcode mapping (needs productId)
    if (['product_units', 'product_barcodes', 'warehouse_prices'].contains(table)) {
      if (p['productId'] != null && mappings['products']?.containsKey(p['productId'].toString()) == true) {
        p['productId'] = mappings['products']![p['productId'].toString()];
      }
      if (p['product_id'] != null && mappings['products']?.containsKey(p['product_id'].toString()) == true) {
        p['product_id'] = mappings['products']![p['product_id'].toString()];
      }
    }

    // ── Self-id remap (update/delete ops on client-originated records) ──
    // If an earlier outbox entry inserted this record and received a server id,
    // subsequent update/delete ops must target the server id, not the local one.
    if (p['id'] != null && mappings[table]?.containsKey(p['id'].toString()) == true) {
      p['id'] = mappings[table]![p['id'].toString()];
    }

    // ── Shift close: shiftId references a previously-opened local shift ──
    if (table == 'shifts' && p['shiftId'] != null &&
        mappings['shifts']?.containsKey(p['shiftId'].toString()) == true) {
      p['shiftId'] = mappings['shifts']![p['shiftId'].toString()];
    }

    // ── referenceType/referenceId — journals + safe_transactions ──
    // Translate referenceType → the outbox case-name that owned the mapping.
    // C-01: producers queue JEs under 'journal_entries' (not the dead
    // 'journals'), so include it here or an offline JE's referenceId never
    // gets remapped to the server id.
    if (['journals', 'journal_entries', 'safe_transactions'].contains(table)) {
      final refType = (p['referenceType'] ?? p['reference_type']) as String?;
      final refIdRaw = p['referenceId'] ?? p['reference_id'];
      const refTypeToCaseName = <String, String>{
        'sales_invoice': 'sales',
        'purchase_invoice': 'purchases',
        'sales_return': 'sales_returns',
        'purchase_return': 'purchase_returns',
        'shift_closing': 'shifts',
      };
      if (refType != null && refIdRaw != null) {
        final caseName = refTypeToCaseName[refType];
        if (caseName != null &&
            mappings[caseName]?.containsKey(refIdRaw.toString()) == true) {
          final remoteId = mappings[caseName]![refIdRaw.toString()];
          if (p.containsKey('referenceId')) p['referenceId'] = remoteId;
          if (p.containsKey('reference_id')) p['reference_id'] = remoteId;
        }
      }
    }

    return p;
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

  /// Replay a single queued operation via ServerProxy
  Future<dynamic> _replayOperation(
    String table,
    String operation,
    Map<String, dynamic> payload,
    int outboxId,
  ) async {
    final proxy = ServerProxy.instance;
    // Spec 136 ISS-21 — use the globally-unique idempotency key that
    // ClientWriteInterceptor._tryOrQueue already minted (a UUIDv7 stored in
    // payload['idempotency_key']) instead of regenerating 'SyncOutbox_<localId>'.
    //
    // The local outbox autoincrement id is NOT globally unique: it restarts at
    // 1 after a wipe/reinstall (this device gets MIRROR-WIPE) and repeats across
    // devices, while the server's `processed_messages` cache is persistent and
    // global. So 'SyncOutbox_3' from a fresh outbox collided with a DIFFERENT
    // invoice's cached entry from an earlier session — the server returned that
    // stale cached response and SILENTLY DROPPED the new offline invoice
    // (field repro: SINV-32 hit cached AQ-POS-18 serverId=84 → never persisted →
    // shift variance). The UUIDv7 key never collides; a genuine retry of the
    // SAME item reuses the same stored key (correct idempotency), and the
    // server's globalId dedup remains the authoritative guard.
    final idempotencyKey = idempotencyKeyFor(payload, outboxId);

    switch (table) {
      case 'sales':
        if (operation == 'insert') {
          return proxy.submitSale(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'delete') {
          // FIX 3.4: Pass idempotencyKey to DELETE — prevents double-delete on reconnect
          await proxy.deleteSalesInvoice(payload['id'] as int, idempotencyKey: idempotencyKey);
        } else if (operation == 'void') {
          // C-02 (Spec 151): sales-invoice void submit queued while the server
          // was unreachable. Without this branch the payload would silently
          // fall through the switch on drain — the client thinks the void is
          // "queued" forever but it is actually dropped. Server resolves by the
          // threaded globalId (payload['globalId']) and is idempotent.
          return proxy.submitVoidSale(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'payment') {
          // Spec 151 C-05: customer collection queued while the server was
          // unreachable. Same drop-on-drain hazard as void — replay via the
          // dedicated endpoint (server dedups on the payload globalId).
          return proxy.submitSalesPayment(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'update') {
          // Pre-deploy BLOCKER (sync audit): an invoice edit queued offline must
          // reach HQ (was silently dropped via break→null→markAsSyncSuccess).
          await proxy.updateSalesInvoice(payload['id'] as int, payload, idempotencyKey: idempotencyKey);
        } else {
          throw StateError('Unhandled op $operation for table $table');
        }
        break;

      case 'sales_returns':
        if (operation == 'insert') {
          return proxy.submitSalesReturn(payload, idempotencyKey: idempotencyKey);
        }
        break;

      case 'sales_exchanges':
        if (operation == 'insert') {
          // بلا هذا الفرع تُصَفُّ حمولةُ الاستبدال ثم تسقط صامتةً عند
          // التصريف (‏`break` → null → `markAsSyncSuccess`) — نفسُ ما وقع
          // لـ`void` و`payment` قبلَها. والعميلُ يظنّها «مُصفَّفة» وهي مفقودة.
          return proxy.submitExchange(payload, idempotencyKey: idempotencyKey);
        }
        break;

      case 'held_orders':
        if (operation == 'insert') {
          return proxy.submitHeldOrder(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'delete') {
          // FIX 3.4: Pass idempotencyKey to DELETE
          await proxy.deleteHeldOrder(payload['id'] as int, idempotencyKey: idempotencyKey);
        }
        break;

      case 'expenses':
        if (operation == 'insert') {
          return proxy.submitExpense(
            amount: (payload['amount'] as num).toDouble(),
            category: payload['category'] as String,
            description: payload['description'] as String?,
            partyId: payload['partyId'] as int?,
            // Feature 044 — forward cached party identifiers so a
            // deferred replay still resolves via `resolvePartyId` on the
            // server. Older queue entries without these fields fall back
            // to the integer partyId path.
            partyGlobalId: payload['partyGlobalId'] as String?,
            partyName: payload['partyName'] as String?,
            safeId: payload['safeId'] as int?,
            userId: payload['userId'] as int?,
            costCenterId: payload['costCenterId'] as int?,
            branchId: payload['branchId'] as int?,
            globalId: payload['globalId'] as String?,
            idempotencyKey: idempotencyKey,
          );
        } else if (operation == 'delete') {
          // FIX 3.4: Pass idempotencyKey to DELETE
          await proxy.deleteExpense(payload['id'] as int, idempotencyKey: idempotencyKey);
        }
        break;

      case 'receipts':
        if (operation == 'insert') {
          return proxy.submitReceipt(
            amount: (payload['amount'] as num).toDouble(),
            category: payload['category'] as String,
            description: payload['description'] as String?,
            partyId: payload['partyId'] as int?,
            // Feature 044 — same party-resolution threading.
            partyGlobalId: payload['partyGlobalId'] as String?,
            partyName: payload['partyName'] as String?,
            safeId: payload['safeId'] as int?,
            safeGlobalId: payload['safeGlobalId'] as String?,
            userId: payload['userId'] as int?,
            branchId: payload['branchId'] as int?,
            costCenterId: payload['costCenterId'] as int?,
            linkedAccountId: payload['linkedAccountId'] as int?,
            globalId: payload['globalId'] as String?,
            idempotencyKey: idempotencyKey,
          );
        }
        break;

      case 'parties':
        if (operation == 'insert') {
          return proxy.createParty(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'update') {
          // Pre-deploy BLOCKER (sync audit): a customer edit (credit-limit,
          // balance, phone, discount) queued offline via cwi_commerce.dart must
          // reach HQ. Without this branch the op hit break→null→markAsSyncSuccess
          // and was silently dropped, then reverted on the next serverWins pull.
          await proxy.updateParty(payload['id'] as int, payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'delete') {
          await proxy.deleteParty(payload['id'] as int, idempotencyKey: idempotencyKey);
        } else {
          throw StateError('Unhandled op $operation for table $table');
        }
        break;

      case 'units':
        if (operation == 'insert') {
          return proxy.submitUnit(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'update') {
          await proxy.updateUnit(payload['id'] as int, payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'delete') {
          await proxy.deleteUnit(payload['id'] as int, idempotencyKey: idempotencyKey);
        }
        break;

      case 'product_units':
        if (operation == 'insert') {
          return proxy.submitProductUnitMapping(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'update') {
          // ⚠️ كان هذا الفرعُ **غائباً**، فيسقط `update` على `break` ويعود
          // `null` ⇒ يُعلَّم في الطابور **ناجحاً** بلا إرسال. تعديلُ سعرِ
          // وحدةٍ أو معامِلِ تحويلٍ أثناء انقطاعٍ كان يُمحى من الطابور ثم
          // يُرجَع بأوّل سحبٍ تالٍ (`serverWins`) — فيبيع الكرتونةَ بسعرٍ
          // خاطئ. نفسُ فئةِ العطب التي أُغلقت لـ`parties/update` و
          // `sales/update`.
          await proxy.updateProductUnitMapping(
              payload['id'] as int, payload,
              idempotencyKey: idempotencyKey);
        } else if (operation == 'delete') {
          await proxy.deleteProductUnitMapping(payload['id'] as int, idempotencyKey: idempotencyKey);
        } else {
          // فخُّ الفئة: عمليةٌ غيرُ معروفةٍ تُرمى ولا تُبتلع. الصمتُ هنا هو
          // العطبُ نفسُه.
          throw StateError('Unhandled op $operation for table $table');
        }
        break;

      case 'product_barcodes':
        if (operation == 'insert') {
          return proxy.submitProductBarcode(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'delete') {
          await proxy.deleteProductBarcode(payload['id'] as int, idempotencyKey: idempotencyKey);
        }
        break;

      case 'products':
        if (operation == 'insert') {
          return proxy.createProduct(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'update') {
          await proxy.updateProduct(payload['id'] as int, payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'delete') {
          await proxy.deleteProduct(payload['id'] as int, idempotencyKey: idempotencyKey);
        }
        break;

      case 'purchase_returns':
        if (operation == 'insert') {
          return proxy.submitPurchaseReturn(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'edit') {
          // Feature 015 — purchase return edit (atomic reverse + recreate).
          return proxy.submitPurchaseReturnEdit(payload, idempotencyKey: idempotencyKey);
        }
        break;

      case 'purchases':
      case 'purchase_invoices':
        if (operation == 'insert') {
          // Replay the ORIGINAL payload, only normalising snake_case keys that
          // the PurchaseDao outbox writes. The previous hand-built map listed
          // 7 fields and silently dropped everything else — `discount`,
          // `globalId`, `costCenterId`, `branchId`, `userId`, and per-line
          // `taxRate`/`taxAmount`/`batchNumber`/`expiryDate`/`unitName`/
          // `quantityInBase`/`globalId`. So any purchase queued while offline
          // reached the server GROSS, with zero VAT, no idempotency key and no
          // line identities (which then duplicated on the next pull).
          final replay = <String, dynamic>{...payload};
          void alias(String camel, String snake) {
            if (replay[camel] == null && replay[snake] != null) {
              replay[camel] = replay[snake];
            }
          }
          alias('supplierId', 'supplier_id');
          alias('warehouseId', 'warehouse_id');
          alias('invoiceDate', 'invoice_date');
          alias('paymentMethod', 'payment_method');
          alias('supplierInvoiceNumber', 'invoice_number');
          alias('costCenterId', 'cost_center_id');
          alias('branchId', 'branch_id');
          alias('globalId', 'global_id');
          alias('userId', 'user_id');
          replay['paid'] ??= 0;
          replay['items'] = (payload['items'] as List?)?.map((item) {
            final m = Map<String, dynamic>.from(item as Map);
            m['productId'] ??= m['product_id'];
            m['unitCost'] ??= m['unit_cost'];
            m['taxRate'] ??= m['tax_rate'];
            m['taxAmount'] ??= m['tax_amount'];
            m['quantityInBase'] ??= m['quantity_in_base'];
            m['globalId'] ??= m['global_id'];
            m['total'] ??= ((m['quantity'] as num?)?.toDouble() ?? 0) *
                ((m['unitCost'] as num?)?.toDouble() ?? 0);
            return m;
          }).toList() ?? [];
          return proxy.createPurchase(replay, idempotencyKey: idempotencyKey);
        } else if (operation == 'update') {
          await proxy.updatePurchase(payload['id'] as int, payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'delete') {
          await proxy.deletePurchase(payload['id'] as int);
        } else if (operation == 'void') {
          // PR-2 (pre-deploy batch B6): void submit queued while the server
          // was unreachable. Without this branch the payload would silently
          // fall through the switch on drain — the client thinks the void
          // is "queued" forever but it's actually dropped.
          return proxy.submitVoidPurchase(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'payment') {
          // Spec 151 C-03: purchase payment queued while the server was
          // unreachable. Same drop-on-drain hazard as void — replay via the
          // dedicated endpoint (server dedups on the payload globalId).
          return proxy.submitPurchasePayment(payload, idempotencyKey: idempotencyKey);
        }
        break;

      case 'quotations':
        // Offline-queued quotation operations. Without this case, entries
        // created or edited while the server was unreachable used to fall
        // through to the `default:` branch below and get silently dropped —
        // the user saw the save succeed locally, but the server never heard
        // about it, which is why editing an "already-saved" quotation hung
        // on a loading state that waited for a server round-trip that was
        // never going to happen.
        if (operation == 'insert') {
          return proxy.createQuotation(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'update') {
          // Two shapes land here:
          //   (a) status-only update — payload carries `status` (+ optional
          //       `convertedToInvoiceId`) and no `items` array.
          //   (b) full-row edit      — payload carries an `items` list (and
          //       typically subtotal/total/discount/...); routed to the
          //       full PUT /api/quotations/<id> endpoint.
          final hasItems = payload['items'] is List;
          if (hasItems) {
            await proxy.updateQuotation(
              payload['id'] as int,
              payload,
              idempotencyKey: idempotencyKey,
            );
          } else {
            await proxy.updateQuotationStatus(
              payload['id'] as int,
              payload['status'] as String? ?? 'draft',
              convertedInvoiceId: payload['convertedToInvoiceId'] as int?,
              idempotencyKey: idempotencyKey,
            );
          }
        } else if (operation == 'delete') {
          await proxy.deleteQuotation(payload['id'] as int, idempotencyKey: idempotencyKey);
        }
        break;

      case 'shifts':
        if (operation == 'open') {
          // Return the server's shiftId so the calling drain loop captures it
          // into mappedIds['shifts'] → ensures any subsequent close operation
          // gets remapped from local id to server id (otherwise the close
          // fails with "Shift not found").
          return proxy.openShift(
            payload['userId'] as int,
            (payload['openingBalance'] as num).toDouble(),
            // Spec 008 / FR-006: forward branchId from the outbox payload
            // so a delayed-drain shift open lands on the server with the
            // correct branch attribution.
            branchId: payload['branchId'] is int
                ? payload['branchId'] as int
                : (payload['branchId'] is num
                    ? (payload['branchId'] as num).toInt()
                    : null),
            // R9: forward globalId so the server dedups by it on retries
            // (idempotent open) instead of inserting a fresh phantom shift.
            globalId: payload['globalId'] as String?,
            idempotencyKey: idempotencyKey,
          );
        } else if (operation == 'close') {
          // Phase 5A.7 (Issue 2) — forward the optional reconstruction
          // hints (userId/openingBalance/openedAt) so the server can
          // recreate the shift if /api/shifts/open never drained before
          // the close arrived. Older outbox rows queued before this
          // change won't have these keys; the proxy treats them as null.
          final openedAtRaw = payload['openedAt'] as String?;
          await proxy.closeShift(
            payload['shiftId'] as int,
            (payload['actualCash'] as num).toDouble(),
            notes: payload['notes'] as String?,
            userId: payload['userId'] as int?,
            openingBalance: (payload['openingBalance'] as num?)?.toDouble(),
            openedAt: openedAtRaw != null ? DateTime.tryParse(openedAtRaw) : null,
            // R9: forward shiftGlobalId so the server resolves the right
            // shift even when the local→server id mapping is missing
            // (the recurring "Shift not found" DEAD-LETTER root cause).
            shiftGlobalId: payload['shiftGlobalId'] as String?,
            idempotencyKey: idempotencyKey,
          );
        }
        break;

      case 'categories':
        if (operation == 'insert') {
          return proxy.createCategory(
            name: payload['name'] as String,
            color: payload['color'] as String,
            printerId: payload['printerId'] as int?,
            iconName: payload['iconName'] as String?,
            idempotencyKey: idempotencyKey,
          );
        } else if (operation == 'update') {
          await proxy.updateCategory(
            id: payload['id'] as int,
            name: payload['name'] as String,
            color: payload['color'] as String,
            printerId: payload['printerId'] as int?,
            iconName: payload['iconName'] as String?,
            idempotencyKey: idempotencyKey,
          );
        } else if (operation == 'delete') {
          // FIX 3.4: Pass idempotencyKey to DELETE
          // Feature 045: forward the cached `moveToCategoryId` so a
          // deferred replay still runs the same bulk-move + soft-delete
          // server-side. Older queue entries without this key replay as
          // `moveToCategoryId=null` (uncategorized) — matches the
          // legacy "products survive" expectation.
          await proxy.deleteCategory(
            payload['id'] as int,
            moveToCategoryId: payload['moveToCategoryId'] as int?,
            idempotencyKey: idempotencyKey,
          );
        }
        break;

      case 'inventory':
        if (operation == 'adjust') {
          // Spec 135 BUG-A: forward the cached productGlobalId + per-event
          // adjustmentEventGid from the outbox payload so a deferred replay
          // re-sends the SAME deterministic JE globalId. Without this, the
          // server falls back to a fresh UuidV7 on replay → a divergent JE
          // globalId that the UNIQUE constraint can't dedup → phantom
          // duplicate JE (or 23505) if the first attempt partially landed.
          // Older queue entries lacking these keys replay as null (pre-135
          // behaviour — still event-unique, just not cross-instance-deduped).
          await proxy.adjustStock(
            productId: payload['productId'] as int,
            warehouseId: payload['warehouseId'] as int,
            quantity: (payload['quantity'] as num).toDouble(),
            type: payload['type'] as String?,
            notes: payload['notes'] as String?,
            productGlobalId: payload['productGlobalId'] as String?,
            // Spec 136 ISS-26 #2 — forward the cached warehouseGlobalId so a
            // deferred replay still resolves the correct server warehouse.
            warehouseGlobalId: payload['warehouseGlobalId'] as String?,
            adjustmentEventGid: payload['adjustmentEventGid'] as String?,
            idempotencyKey: idempotencyKey,
          );
        }
        break;

      case 'settings':
        if (operation == 'update') {
          final settings = (payload['settings'] as Map?)?.cast<String, String>();
          if (settings != null) {
            await proxy.saveSettings(settings, idempotencyKey: idempotencyKey);
          }
        }
        break;

      case 'commercial_papers':
        if (operation == 'insert') {
          // `return` مش `await`: الـdrain بيلتقط الـserverId من القيمة
          // المرجَّعة ويسجّل mapping في `remote_id_mappings`. `await` بيرجّع
          // `null` فمفيش mapping — والعمليات اللاحقة (تجديد · تحصيل جزئي ·
          // إيداع · إعادة إصدار) بتبعت الـid **المحلي** في مسار الـURL،
          // فبتضرب ورقة تانية خالص على السيرفر ليها نفس الرقم.
          return proxy.createCommercialPaper(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'update_status') {
          await proxy.updateCommercialPaperStatus(
            payload['id'] as int,
            status: payload['status'] as String,
            changedBy: payload['changedBy'] as int?,
            // Feature 042 (Bug 5) — forward the cached username from the
            // queued payload so a deferred replay still resolves the
            // server-side user_id via _resolveUserIdNullable. Older
            // queue entries without this field still work via the
            // integer changedBy fallback.
            changedByUsername: payload['changedByUsername'] as String?,
            notes: payload['notes'] as String?,
            endorsedToPartyId: payload['endorsedToPartyId'] as int?,
            globalId: payload['globalId'] as String?,
            // Feature 048 (v130) — forward the user-chosen contra leg so a
            // deferred replay still posts the JE to the right account.
            counterAccountId: payload['counterAccountId'] as int?,
            counterAccountGlobalId:
                payload['counterAccountGlobalId'] as String?,
          );
        } else if (operation == 'renew') {
          await proxy.renewCommercialPaper(
            payload['id'] as int,
            newDueDate: payload['newDueDate'] as String,
            changedBy: payload['changedBy'] as int?,
            notes: payload['notes'] as String?,
          );
        } else if (operation == 'partial_collect') {
          await proxy.partialCollectPaper(
            payload['id'] as int,
            amount: (payload['amount'] as num).toDouble(),
            changedBy: payload['changedBy'] as int?,
            notes: payload['notes'] as String?,
          );
        } else if (operation == 'endorse') {
          await proxy.updateCommercialPaperStatus(
            payload['id'] as int,
            status: 'endorsed',
            changedBy: payload['changedBy'] as int?,
            notes: payload['notes'] as String?,
            endorsedToPartyId: payload['endorsedToPartyId'] as int?,
          );
        } else if (operation == 'deposit') {
          await proxy.depositPaperForCollection(
            payload['id'] as int,
            bankSafeId: payload['bankSafeId'] as int,
            changedBy: payload['changedBy'] as int?,
            notes: payload['notes'] as String?,
          );
        } else if (operation == 'reissue') {
          await proxy.reissuePaper(
            payload['id'] as int,
            newPartyId: payload['newPartyId'] as int,
            changedBy: payload['changedBy'] as int?,
            notes: payload['notes'] as String?,
          );
        }
        break;

      // BLOCKER C-01 (Spec 151) — offline journal-entry replay.
      // The outbox producer (cwi_sync.submitJournalEntry) queues manual/auto
      // journal entries under tableName:'journal_entries'. Before this fix the
      // switch had ONLY a (dead) 'journals' case and NO 'journal_entries'
      // case, so every offline JE fell through to `default:`, which
      // debugPrint'd and returned null. The drain loop then called
      // markAsSyncSuccess unconditionally → the GL write was cleared from the
      // outbox and NEVER reached the server: a silent GL loss with no
      // dead-letter. Both names now share one body so a JE queued under either
      // key replays correctly. ('journals' is retained because the pull-side /
      // websocket subscription map still references that name.)
      case 'journals':
      case 'journal_entries':
        if (operation == 'insert') {
          return proxy.submitJournalEntry(
            description: (payload['description'] ?? payload['notes']) as String? ?? '',
            date: (payload['date'] ?? payload['entry_date'] ?? payload['created_at']) as String? ?? DateTime.now().toIso8601String(),
            lines: (payload['lines'] as List?)
                    ?.cast<Map<String, dynamic>>() ??
                [],
            referenceType: (payload['referenceType'] ?? payload['reference_type']) as String?,
            referenceId: (payload['referenceId'] ?? payload['reference_id']) as int?,
            isAutoPosted: (payload['isAutoPosted'] ?? payload['is_auto_posted']) as bool? ?? true,
            costCenterId: (payload['costCenterId'] ?? payload['cost_center_id']) as int?,
            branchId: (payload['branchId'] ?? payload['branch_id']) as int?,
            // R9: thread the caller-minted globalId (UUIDv7) end-to-end so the
            // server dedups by it on retries instead of inserting a phantom
            // duplicate JE. The legacy 'journals' body omitted it — a real R9
            // gap that this fix closes for both keys.
            globalId: (payload['globalId'] ?? payload['global_id']) as String?,
            idempotencyKey: idempotencyKey,
          );
        }
        break;

      // v166 — ورقةُ تحميلٍ مطبَّقة. الحمولةُ هي المستندُ نفسُه، فتُعاد
      // كما هي: الخادمُ يزيل التكرارَ بمعرّف الورقة العالميّ، فإعادةُ
      // الإرسال بعد انقطاعٍ لا تُنتج تطبيقاً ثانياً ولا قيداً ثانياً.
      // v174 / قسمُ ٧ — مخطَّطُ قاعةٍ كاملاً. الحمولةُ **صورةٌ نهائيّةٌ**
      // لا فرقٌ، فإعادةُ إرسالِها بعد انقطاعٍ تُعيد نفسَ المخطَّط لا
      // معالمَ مضاعَفةً: المعالمُ تُطابَق بمعرّفاتِها العالميّة،
      // والغائبُ عنها يُحذَف حذفاً ناعماً.
      case 'floor_plan_items':
        if (operation == 'save') {
          return proxy.submitFloorPlan(
            payload,
            idempotencyKey: idempotencyKey,
          );
        }
        throw StateError('Unhandled op $operation for table $table');

      case 'attachments':
        // v176 / §٨ — ورقةٌ رُفعت والشبكةُ مقطوعة. والحمولةُ
        // **تحمل البايتاتِ نفسَها** (base64) لا مسارَ ملفٍّ على
        // القرص: مسارٌ يصير مُعلَّقاً إن نُقِل الملفُّ أو مُسِح،
        // فيُعاد إرسالُ مرفقٍ لا وجودَ له إلى الأبد.
        if (operation == 'insert') {
          return proxy.submitAttachment(
            payload,
            idempotencyKey: idempotencyKey,
          );
        }
        if (operation == 'delete') {
          return proxy.submitAttachmentDelete(
            payload,
            idempotencyKey: idempotencyKey,
          );
        }
        throw StateError('Unhandled op $operation for table $table');

      case 'landed_cost_sheets':
        if (operation == 'apply') {
          return proxy.submitLandedCostApply(
            payload,
            idempotencyKey: idempotencyKey,
          );
        }
        throw StateError('Unhandled op $operation for table $table');

      // v166 — اقتناءُ أصلٍ وترحيلُ إهلاك. الحمولةُ هي الطلبُ نفسُه:
      // الخادمُ يزيل تكرارَ الأصل بمعرّفه، ويزيل تكرارَ الإهلاك بمفتاحه
      // الطبيعيّ `(asset_id, period_date)`.
      case 'fixed_assets':
        if (operation == 'insert') {
          return proxy.submitFixedAssetCreate(payload,
              idempotencyKey: idempotencyKey);
        }
        throw StateError('Unhandled op $operation for table $table');

      case 'asset_depreciations':
        if (operation == 'run') {
          return proxy.submitAssetDepreciationRun(payload,
              idempotencyKey: idempotencyKey);
        }
        throw StateError('Unhandled op $operation for table $table');

      // v166 — مصروفٌ تشغيليّ. الخادمُ يزيل التكرارَ بمعرّفه.
      case 'op_expenses':
        if (operation == 'insert') {
          return proxy.submitOperationalExpense(payload,
              idempotencyKey: idempotencyKey);
        }
        throw StateError('Unhandled op $operation for table $table');

      // v166 — حدثٌ على أمرِ إنتاج. الخادمُ يفحص حالةَ الأمر قبل التنفيذ
      // (‏`draft` للبدء و`in_progress` للإنجاز)، فإعادةُ الإرسال بعد
      // انقطاعٍ تُردّ بدل أن تستهلك الخاماتِ ثانية.
      case 'manufacturing_orders':
        if (operation == 'action') {
          return proxy.submitManufacturingAction(payload,
              idempotencyKey: idempotencyKey);
        }
        throw StateError('Unhandled op $operation for table $table');

      // v167 — خصمُ عربون. الخادمُ يفحص `bookings.invoice_id` قبل التنفيذ،
      // فإعادةُ الإرسال بعد انقطاعٍ تُردّ بدل أن تُطفئ الالتزامَ مرّتين
      // وتنقص رصيدَ العميل ضِعفَ ما دفع.
      case 'bookings':
        if (operation == 'apply_deposit') {
          return proxy.submitBookingDepositApplication(payload,
              idempotencyKey: idempotencyKey);
        }
        throw StateError('Unhandled op $operation for table $table');

      case 'safe_transactions':
        if (operation == 'insert') {
          return proxy.submitSafeTransaction(
            safeId: (payload['safeId'] ?? payload['safe_id']) as int? ?? 1,
            transactionType: (payload['transactionType'] ?? payload['transaction_type']) as String? ?? 'receipt',
            amount: (payload['amount'] as num?)?.toDouble() ?? 0,
            category: payload['category'] as String? ?? 'general',
            description: (payload['description'] ?? payload['notes']) as String?,
            userId: (payload['userId'] ?? payload['user_id']) as int?,
            referenceType: (payload['referenceType'] ?? payload['reference_type']) as String?,
            referenceId: (payload['referenceId'] ?? payload['reference_id']) as int?,
            // Phase 5B.4 (Issue 7) — ferry the optional safeGlobalId +
            // costCenterId hints when the queued payload carried them.
            // Older outbox rows queued before this change won't have these
            // keys; the proxy treats absent values as null and the server
            // falls back to its existing safeId-based lookup.
            globalId: payload['globalId'] as String?,
            safeGlobalId: payload['safeGlobalId'] as String?,
            costCenterId: payload['costCenterId'] as int?,
            idempotencyKey: idempotencyKey,
          );
        }
        break;

      case 'safe_transfers':
        if (operation == 'insert') {
          await proxy.submitSafeTransfer(
            fromSafeId: (payload['fromSafeId'] ?? payload['from_safe_id']) as int,
            toSafeId: (payload['toSafeId'] ?? payload['to_safe_id']) as int,
            amount: (payload['amount'] as num).toDouble(),
            userId: (payload['userId'] ?? payload['user_id']) as int?,
            description: (payload['description'] ?? payload['notes']) as String?,
            // نفس سبب stock_transfers تحت: /api/safes/transfer بيعمل dedup
            // بالـglobalId ومش بيقرا هيدر الـidempotency.
            globalId: replayGlobalIdFrom(payload),
            idempotencyKey: idempotencyKey,
          );
        }
        break;

      case 'stock_transfers':
        if (operation == 'insert') {
          await proxy.submitStockTransfer(
            fromWarehouseId: (payload['fromWarehouseId'] ?? payload['from_warehouse_id']) as int,
            toWarehouseId: (payload['toWarehouseId'] ?? payload['to_warehouse_id']) as int,
            items: (payload['items'] as List?)
                    ?.cast<Map<String, dynamic>>() ??
                [],
            userId: (payload['userId'] ?? payload['user_id']) as int?,
            notes: (payload['notes'] ?? payload['description']) as String?,
            // بلا ده كانت إعادة الإرسال بعد timeout بتخصم المخزون تاني:
            // السيرفر بيعمل dedup بالـglobalId حصرياً، و/api/inventory/transfer
            // مش بيقرا هيدر الـidempotency فالمفتاح تحت بلا أثر هنا.
            globalId: replayGlobalIdFrom(payload),
            idempotencyKey: idempotencyKey,
          );
        }
        break;

      case 'roles':
        if (operation == 'insert') {
          return proxy.createRole(
            name: payload['name'] as String,
            description: payload['description'] as String?,
            isSystemRole: payload['isSystemRole'] as bool? ?? false,
          );
        }
        break;

      case 'role_permissions':
        // Replay a queued role-permission save. The payload was stored by
        // cwi_sync.setRolePermissions when the server was unreachable; we
        // forward it as-is. The same idempotency key is reused so the
        // server can dedupe a request that succeeded but whose response
        // never reached us.
        if (operation == 'set') {
          await proxy.setRolePermissions(
            payload['roleId'] as int,
            (payload['permissionCodes'] as List).cast<String>(),
            idempotencyKey: idempotencyKey,
            // Spec 136 ISS-15: replay the role identity so an offline-queued
            // save still lets the server resolve/create the role.
            roleGlobalId: payload['roleGlobalId'] as String?,
            roleName: payload['roleName'] as String?,
          );
        }
        break;

      case 'users':
        if (operation == 'insert') {
          return proxy.createUser(
            username: payload['username'] as String,
            password: payload['password'] as String,
            displayName: payload['displayName'] as String,
            roleId: payload['roleId'] as int?,
            branchIds: (payload['branchIds'] as List?)?.cast<int>(),
            globalId: payload['globalId'] as String?,
          );
        } else if (operation == 'update') {
          final id = payload['id'] as int;
          // Three possible shapes from ClientWriteInterceptor: full field update,
          // password-only update, or pin-only update. Dispatch by which key is
          // the sole payload field after stripping 'id'.
          final fields = Map<String, dynamic>.from(payload)..remove('id');
          if (fields.length == 1 && fields.containsKey('password')) {
            await proxy.updateUserPassword(id, fields['password'] as String,
                idempotencyKey: idempotencyKey);
          } else if (fields.length == 1 && fields.containsKey('pin')) {
            await proxy.updateUserPin(id, fields['pin'] as String?,
                idempotencyKey: idempotencyKey);
          } else {
            await proxy.updateUser(id, fields, idempotencyKey: idempotencyKey);
          }
        }
        break;

      case 'regions':
        if (operation == 'insert') {
          return proxy.createRegion(
            name: payload['name'] as String,
            address: payload['address'] as String?,
            phone: payload['phone'] as String?,
            costCenterId: payload['costCenterId'] as int?,
          );
        } else if (operation == 'update') {
          await proxy.updateRegion(
            id: payload['id'] as int,
            name: payload['name'] as String,
            address: payload['address'] as String?,
            phone: payload['phone'] as String?,
            costCenterId: payload['costCenterId'] as int?,
          );
        }
        break;

      case 'party_groups':
        if (operation == 'insert') {
          return proxy.createPartyGroup(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'update') {
          final id = payload['id'] as int;
          final data = Map<String, dynamic>.from(payload)..remove('id');
          await proxy.updatePartyGroup(id, data, idempotencyKey: idempotencyKey);
        } else if (operation == 'delete') {
          await proxy.deletePartyGroup(payload['id'] as int, idempotencyKey: idempotencyKey);
        }
        break;

      case 'purchase_orders':
        if (operation == 'insert') {
          return proxy.createPurchaseOrder(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'update') {
          await proxy.updatePurchaseOrderStatus(
            payload['id'] as int,
            payload['status'] as String,
            idempotencyKey: idempotencyKey,
          );
        } else if (operation == 'delete') {
          await proxy.deletePurchaseOrder(payload['id'] as int, idempotencyKey: idempotencyKey);
        }
        break;

      case 'sales_orders':
        if (operation == 'insert') {
          return proxy.createSalesOrder(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'update') {
          await proxy.updateSalesOrderStatus(
            payload['id'] as int,
            payload['status'] as String,
            idempotencyKey: idempotencyKey,
          );
        } else if (operation == 'delete') {
          await proxy.deleteSalesOrder(payload['id'] as int, idempotencyKey: idempotencyKey);
        }
        break;

      case 'price_lists':
        if (operation == 'insert') {
          return proxy.createPriceList(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'update') {
          final id = payload['id'] as int;
          final data = Map<String, dynamic>.from(payload)..remove('id');
          await proxy.updatePriceList(id, data, idempotencyKey: idempotencyKey);
        }
        break;

      case 'price_list_items':
        if (operation == 'upsert') {
          await proxy.setPriceListItem(payload, idempotencyKey: idempotencyKey);
        }
        break;

      case 'printers':
        if (operation == 'insert') {
          return proxy.createPrinter(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'update') {
          final id = payload['id'] as int;
          final data = Map<String, dynamic>.from(payload)..remove('id');
          await proxy.updatePrinter(id, data, idempotencyKey: idempotencyKey);
        } else if (operation == 'delete') {
          await proxy.deletePrinter(payload['id'] as int, idempotencyKey: idempotencyKey);
        }
        break;

      case 'inventory_bonds':
        if (operation == 'insert') {
          return proxy.submitInventoryBond(payload, idempotencyKey: idempotencyKey);
        }
        break;

      // ── Admin / structural tables ────────────────────────────────────────
      // These seven had NO case at all, so every queued operation fell to the
      // `default:` StateError → isPermanentError → markAsSyncDeadLetter. The
      // "retry all" button flips dead-letter rows back to pending with
      // attempts=0, they hit the same StateError, and dead-letter again —
      // an endless loop the admin can never clear. Eighteen enqueue sites
      // across cwi_admin/cwi_catalog/cwi_sync fed it.
      //
      // Every operation below already has a tested method on ServerProxy (the
      // same one the online path calls) and every payload already carries what
      // that method needs, so this is dispatch-table plumbing, not new
      // behaviour. NOTE: mirror mode never reaches here — it throws
      // MirrorOfflineException instead of queueing — so this is a client-mode
      // fix exclusively.

      case 'branches':
        if (operation == 'insert') {
          await proxy.createBranch(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'update') {
          await proxy.updateBranch(
            payload['id'] as int,
            _withoutId(payload),
            idempotencyKey: idempotencyKey,
          );
        } else if (operation == 'delete') {
          await proxy.deleteBranch(
            payload['id'] as int,
            reassignUsersToBranchId: payload['reassignUsersToBranchId'] as int?,
            idempotencyKey: idempotencyKey,
          );
        } else {
          throw StateError('Unhandled op $operation for table $table');
        }
        break;

      case 'accounts':
        if (operation == 'insert') {
          await proxy.createAccount(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'update') {
          await proxy.updateAccount(
            payload['id'] as int,
            _withoutId(payload),
            idempotencyKey: idempotencyKey,
          );
        } else if (operation == 'delete') {
          await proxy.deleteAccount(payload['id'] as int,
              idempotencyKey: idempotencyKey);
        } else {
          throw StateError('Unhandled op $operation for table $table');
        }
        break;

      case 'account_mappings':
        if (operation == 'upsert') {
          await proxy.setAccountMapping(payload,
              idempotencyKey: idempotencyKey);
        } else if (operation == 'delete') {
          await proxy.deleteAccountMapping(
            purpose: payload['purpose'] as String,
            costCenterId: payload['costCenterId'] as int?,
            idempotencyKey: idempotencyKey,
          );
        } else {
          throw StateError('Unhandled op $operation for table $table');
        }
        break;

      case 'cost_centers':
        if (operation == 'insert') {
          await proxy.createCostCenter(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'update') {
          await proxy.updateCostCenter(
            payload['id'] as int,
            _withoutId(payload),
            idempotencyKey: idempotencyKey,
          );
        } else if (operation == 'delete') {
          await proxy.deleteCostCenter(payload['id'] as int,
              idempotencyKey: idempotencyKey);
        } else {
          throw StateError('Unhandled op $operation for table $table');
        }
        break;

      case 'user_region_access':
        if (operation == 'upsert') {
          await proxy.setUserRegionAccess(
            payload['userId'] as int,
            (payload['regionIds'] as List).map((e) => e as int).toList(),
            idempotencyKey: idempotencyKey,
          );
        } else {
          throw StateError('Unhandled op $operation for table $table');
        }
        break;

      case 'warehouses':
        if (operation == 'insert') {
          return proxy.createWarehouse(
            name: payload['name'] as String,
            branchId: payload['branchId'] as int?,
            globalId: payload['globalId'] as String?,
          );
        } else if (operation == 'update') {
          // Three distinct enqueue sites share operation='update' and are
          // told apart by these flags (cwi_catalog setDefault/unsetDefault).
          // Replaying the wrong one silently re-points the POS's default
          // warehouse, so the discrimination has to match the producer.
          if (payload['setDefault'] == true) {
            await proxy.setDefaultWarehouse(payload['id'] as int,
                idempotencyKey: idempotencyKey);
          } else if (payload['unsetDefault'] == true) {
            await proxy.unsetDefaultWarehouse(payload['id'] as int,
                idempotencyKey: idempotencyKey);
          } else {
            await proxy.updateWarehouse(
              payload['id'] as int,
              _withoutId(payload),
              idempotencyKey: idempotencyKey,
            );
          }
        } else if (operation == 'delete') {
          await proxy.deleteWarehouse(payload['id'] as int,
              idempotencyKey: idempotencyKey);
        } else {
          throw StateError('Unhandled op $operation for table $table');
        }
        break;

      case 'activity_logs':
        if (operation == 'insert') {
          await proxy.pushActivityLog(payload,
              idempotencyKey: idempotencyKey);
        } else {
          throw StateError('Unhandled op $operation for table $table');
        }
        break;

      case 'safes':
        if (operation == 'close') {
          // Spec 135: forward the cached amounts + closeEventGid so a deferred
          // replay re-sends the SAME deterministic closing-JE id and the same
          // split (older entries without these keys replay as null — pre-135
          // behaviour). The DAO's gid guard + balance<=0 check keep replay
          // idempotent.
          await proxy.closeSafe(
            payload['safeId'] as int,
            userId: payload['userId'] as int?,
            cashAmount: (payload['cashAmount'] as num?)?.toDouble(),
            bankAmount: (payload['bankAmount'] as num?)?.toDouble(),
            notes: payload['notes'] as String?,
            closeEventGid: payload['closeEventGid'] as String?,
            idempotencyKey: idempotencyKey,
          );
        } else if (operation == 'insert') {
          await proxy.createSafe(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'delete') {
          await proxy.deleteSafe(payload['id'] as int,
              idempotencyKey: idempotencyKey);
        } else if (operation == 'update') {
          // ClientWriteInterceptor.submitSetDefaultSafe queues this shape.
          if (payload['isDefault'] == true) {
            await proxy.submitSetDefaultSafe(
              safeId: payload['id'] as int,
              idempotencyKey: idempotencyKey,
            );
          } else {
            // A generic safe edit (rename / bank details / isActive). Falling
            // through to `break` here returned null, which drainOutbox reads
            // as SUCCESS and clears the row — the edit vanished with no
            // dead-letter, no log, no trace. That is strictly worse than the
            // dead-letter loop the seven tables above suffered: at least a
            // dead-letter is visible.
            await proxy.updateSafe(
              payload['id'] as int,
              _withoutId(payload),
              idempotencyKey: idempotencyKey,
            );
          }
        } else {
          throw StateError('Unhandled op $operation for table $table');
        }
        break;

      default:
        // BLOCKER C-01 (Spec 151) — FAIL-LOUD. Previously this debugPrint'd and
        // returned null, so the drain loop marked the item as a sync SUCCESS
        // and cleared it from the outbox — silently DROPPING the write (an
        // offline journal_entries GL row was the field repro). Throwing routes
        // the item through the permanent-error classifier in drainOutbox →
        // markAsSyncDeadLetter + SYNC-WARN, turning a silent drop into a
        // visible dead-letter the admin can see (and manually retry once a code
        // fix adds the missing case). NEVER return null here.
        throw StateError('Unknown sync table: $table (op=$operation)');
    }
  }

  void dispose() {
    _retryTimer?.cancel();
    _heartbeatTimer?.cancel();
    pendingCount.dispose();
  }
}
