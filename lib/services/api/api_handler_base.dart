import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:drift/drift.dart' as drift;
import '../../core/logging/diagnostic_logger.dart';
import '../../core/utils/uuid_v7.dart';
import '../../data/database/database.dart';

/// Spec 129 F1 / FR-102 — structured subscriber record. Replaces the
/// previous `int? branchId` value with a record that also carries the
/// subscriber's `mode` (`'client'` or `'mirror'`) and, for mirrors, the
/// `device_id` from secure-storage pairing. Used by the WS upgrade
/// handler in [ApiSalesHandler.handleWebSocket] and by every broadcast
/// fan-out site. Mirrors are unconditionally included in fan-out (the
/// mirror's `branchId` is always null — no branch filter).
///
/// Backward-compat: pre-spec-129 clients that send only `branch_id` and
/// no `mode` are recorded with `mode='client'` so the existing
/// per-branch routing semantics stay identical.
class WsSubscriberInfo {
  final String mode;       // 'client' | 'mirror'
  final int? branchId;     // null = no branch filter (mirror always, or legacy client)
  final String? deviceId;  // present for mirror; clients may set in future

  const WsSubscriberInfo({
    required this.mode,
    this.branchId,
    this.deviceId,
  });

  bool get isMirror => mode == 'mirror';
}

/// Base class for API sub-handlers providing shared DB access and helpers.
abstract class ApiHandlerBase {
  final AppDatabase db;
  /// Maps each connected WebSocket channel to its [WsSubscriberInfo].
  /// Mirror subscribers always have `branchId == null` and receive every
  /// broadcast; client subscribers may scope to a single branch.
  final Map<WebSocketChannel, WsSubscriberInfo> wsClients;

  ApiHandlerBase(this.db, this.wsClients) {
    // Register self so notifyTableChangedFromAdmin can reach the
    // wsClients map without needing a direct ApiHandler reference.
    // Multiple sub-handlers share the same wsClients (set up in
    // ApiHandler), so the most-recent registration is fine.
    _registeredInstance = this;
  }

  /// Checks the persistent idempotency store for an existing response payload.
  /// Returns the JSON map if found, or null if the key is fresh.
  ///
  /// Feature 054 (v134) — stale-cache invalidation.
  ///
  /// `processed_messages` can outlive the rows it caches. Field repro
  /// (supermarket, 2026-05-14): yesterday's successful sales wrote 40
  /// entries to `processed_messages` AND to `sales_invoices`. Between
  /// then and today, `sales_invoices` was wiped (test reset / partial
  /// cleanup) but `processed_messages` survived. Today's fresh sales
  /// from the supermarket hit the orphaned cache and the server
  /// returned `duplicate: true, serverId=<old>` pointing at rows that
  /// no longer exist. 15 sales were lost silently.
  ///
  /// Fix: when a cached response is found, verify its `serverId` is
  /// still present in the target table. If not, delete the cache entry
  /// and return null (treat as a fresh request). All branches gain
  /// reliability — any rebuild of the transactional tables stops
  /// poisoning future writes from clients whose cache pre-dated the
  /// rebuild.
  ///
  /// `verifyExists` is the per-call ground-truth check supplied by the
  /// caller (e.g. for `postSale` we check `sales_invoices`). If null,
  /// the legacy unconditional-return behaviour is used — kept for
  /// handlers that have no target table (e.g. pure RPCs).
  Future<Map<String, dynamic>?> checkIdempotency(
    String idempotencyKey, {
    Future<bool> Function(int serverId)? verifyExists,
  }) async {
    // limit(1): `processed_messages` carries a PK on `idempotency_key` on any
    // schema drift created, but a server provisioned from the manual
    // `db/legacy_migrations/supabase_migration_v118.sql` (or one whose PK was never emitted) allows
    // duplicate keys. Without the limit this is `list.single` → StateError on
    // EVERY subsequent request bearing that key, which the caller converts to a
    // 500 — so the client's outbox retries forever and each retry is a fresh
    // sale attempt. The idempotency store would poison itself into duplicating
    // exactly what it exists to prevent.
    final query = db.select(db.processedMessages)
      ..where((p) => p.idempotencyKey.equals(idempotencyKey))
      ..limit(1);
    final record = await query.getSingleOrNull();
    if (record == null) return null;

    final payload = json.decode(record.responsePayload) as Map<String, dynamic>;

    if (verifyExists != null) {
      final serverId = payload['serverId'];
      if (serverId is int) {
        final stillExists = await verifyExists(serverId);
        if (!stillExists) {
          await DiagnosticLogger.log('IDEMPOTENCY',
              '⚠ orphaned-cache invalidated: key=$idempotencyKey '
              'cached_serverId=$serverId actionType=${record.actionType ?? '(null)'} '
              '— target row no longer exists, deleting cache entry and '
              'falling through to fresh handling. (Feature 054 fix.)');
          await (db.delete(db.processedMessages)
                ..where((p) => p.idempotencyKey.equals(idempotencyKey)))
              .go();
          return null;
        }
      }
    }
    return payload;
  }

  /// Stores a completed API response into the persistent idempotency store.
  Future<void> storeIdempotency(String idempotencyKey, Map<String, dynamic> responsePayload, {String? actionType}) async {
    await db.into(db.processedMessages).insert(
      ProcessedMessagesCompanion.insert(
        idempotencyKey: idempotencyKey,
        responsePayload: json.encode(responsePayload),
        actionType: drift.Value(actionType),
      ),
      // NOT `mode: insertOrIgnore` — drift silently downgrades that to a plain
      // INSERT on postgres (the mode is dropped unless an `onConflict` clause
      // is also supplied), so the PK on `idempotency_key` raises 23505 instead
      // of ignoring. Measured on a live PG in
      // test/integration_pg/pg_insert_or_ignore_pg_test.dart. That matters here
      // more than anywhere: this runs AFTER the sale has already committed, and
      // the caller's catch turns the throw into a 500 for a sale that actually
      // succeeded. `target: []` emits a bare `ON CONFLICT DO NOTHING`, which
      // matches any constraint — so it is also correct on a legacy server whose
      // `processed_messages` PK was never emitted.
      onConflict: drift.DoNothing(target: []),
    );
  }

  /// Feature 054 helper: ground-truth existence checks per action type,
  /// for stale-cache invalidation. Each entry maps an `action_type`
  /// (stored in `processed_messages.action_type`) to a function that
  /// asks the DB whether a given serverId is still present.
  ///
  /// Handlers pass `verifyExists: idempotencyVerifierFor('postSale')`
  /// to opt their cache lookup into the validation. New handlers should
  /// register their verifier here.
  Future<bool> Function(int serverId)? idempotencyVerifierFor(String actionType) {
    switch (actionType) {
      case 'postSale':
      case 'postSale_duplicate':
        return (id) async => (await (db.select(db.salesInvoices)
                  ..where((s) => s.id.equals(id))
                  ..limit(1))
                .getSingleOrNull()) !=
            null;
      case 'postPurchase':
      case 'postPurchase_duplicate':
        return (id) async => (await (db.select(db.purchaseInvoices)
                  ..where((p) => p.id.equals(id))
                  ..limit(1))
                .getSingleOrNull()) !=
            null;
      case 'postJournalEntry':
      case 'postJournalEntry_duplicate':
        return (id) async => (await (db.select(db.journalEntries)
                  ..where((e) => e.id.equals(id))
                  ..limit(1))
                .getSingleOrNull()) !=
            null;
      default:
        return null;
    }
  }

  /// Static stream that the server's own UI can listen to for data changes.
  /// Fires the table name whenever data is modified via the API.
  static final StreamController<String> _localChangeController =
      StreamController<String>.broadcast();

  /// Stream of table names that changed on the server via API.
  static Stream<String> get onDataChanged => _localChangeController.stream;

  /// Phase 6 follow-up — most-recent base instance, registered in the
  /// constructor below. Lets non-API code (the user-management dialogs
  /// in particular) trigger a real WebSocket broadcast after a direct
  /// DAO write that bypasses the HTTP layer. Without this, paired
  /// clients only learn about user_branch_access /
  /// user_warehouse_access changes at the next auto-sync interval
  /// (~5s) instead of within a few ms.
  static ApiHandlerBase? _registeredInstance;

  /// Broadcast a table-changed event from outside the API layer (e.g. a
  /// settings dialog that wrote to the DAO directly). Safe to call when
  /// no API server is running — the local stream still fires for the
  /// server's own UI, only the WebSocket leg is a no-op.
  ///
  /// In client mode this method is a no-op by design: a paired client
  /// has no wsClients to broadcast to, and pushing user-management
  /// events from a client violates the "only the server can manage
  /// users" architectural directive.
  static void notifyTableChangedFromAdmin(String table, {int? branchId}) {
    _localChangeController.add(table);
    _registeredInstance?._broadcastWsOnly(table, branchId: branchId);
  }

  /// Internal: WebSocket-only broadcast (no local stream emit), used by
  /// [notifyTableChangedFromAdmin] which already emitted on the local
  /// stream. Keeping the local emit out avoids double-firing for the
  /// server's own UI listeners.
  void _broadcastWsOnly(String table, {int? branchId}) {
    final msg = json.encode({
      'event': 'data_changed',
      'table': table,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'branch_id': ?branchId,
    });
    final stale = <WebSocketChannel>[];
    for (final entry in wsClients.entries) {
      final ws = entry.key;
      final info = entry.value;
      // Spec 129 F1: mirrors always receive (no branch filter); clients
      // are filtered by branchId scope as before.
      if (!info.isMirror && info.branchId != null && branchId != null && info.branchId != branchId) continue;
      try {
        ws.sink.add(msg);
      } catch (_) {
        stale.add(ws);
      }
    }
    for (final ws in stale) {
      wsClients.remove(ws);
      try {
        ws.sink.close();
      } catch (_) {}
    }
    if (wsClients.isNotEmpty) {
      debugPrint('[WS] Admin broadcast: $table → ${wsClients.length} clients');
    }
  }

  /// Spec 129 F2 / FR-201-204 — the ONLY sanctioned path for mutating
  /// endpoints to broadcast their changes. Wraps an endpoint's body, awaits
  /// it, then emits a `data_changed` event per declared table to every
  /// subscribed mirror + matching client.
  ///
  /// Contract (see specs/129-mirror-broadcast-discipline/contracts/broadcast-wrapper.md):
  ///   1. Broadcasts fire AFTER `body()` returns successfully. If the body
  ///      throws, NO broadcasts are emitted and the exception propagates.
  ///   2. `tables` is the declared union of every table the body mutates.
  ///      The `MutationRecordingInterceptor` test asserts this set equals
  ///      the actual recorded mutations (completeness AND minimality).
  ///   3. `branchId` scopes the event the same way as the underlying
  ///      [broadcast] primitive: mirrors always receive; clients filter.
  ///   4. Emits one [BROADCAST-WRAP] DiagnosticLogger line per endpoint
  ///      call (FR-OBS-2), not per table.
  ///
  /// Migration of legacy `broadcast(...)` callers is enforced by the
  /// structural test `test/structural/no_manual_broadcast_test.dart`.
  static Future<T> withBroadcast<T>({
    required String endpointLabel,
    required Set<String> tables,
    int? branchId,
    required Future<T> Function() body,
  }) async {
    final result = await body();
    // Sorted set for deterministic log output — helps grep + diff in tests.
    final sortedTables = tables.toList()..sort();
    DiagnosticLogger.log(
      DiagnosticLogger.broadcastWrap,
      'endpoint=$endpointLabel tables=$sortedTables branch=${branchId ?? "all"}',
    );
    final instance = _registeredInstance;
    if (instance != null) {
      for (final table in tables) {
        instance.broadcast(table, branchId: branchId);
      }
    }
    return result;
  }

  /// Broadcast data change event to all connected WebSocket clients
  /// AND to the server's own UI via the static stream.
  ///
  /// [branchId] scopes the event: clients subscribed to a different branch
  /// are skipped. Pass null to send to all clients regardless of branch.
  ///
  /// **Note (Spec 129 F2)**: new endpoint code MUST go through
  /// [withBroadcast] instead of calling this primitive directly. Direct
  /// callers outside the wrapper allow-list are flagged by
  /// `test/structural/no_manual_broadcast_test.dart`. Existing
  /// `notifyTableChangedFromAdmin` callers from the user-management dialogs
  /// remain a legitimate caller for now (different path — UI side, not API).
  void broadcast(String table, {int? branchId}) {
    // Notify local UI (server's own report screens)
    _localChangeController.add(table);

    // Notify remote WebSocket clients
    final msg = json.encode({
      'event': 'data_changed',
      'table': table,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'branch_id': ?branchId,
    });
    final stale = <WebSocketChannel>[];
    for (final entry in wsClients.entries) {
      final ws = entry.key;
      final info = entry.value;
      // Spec 129 F1: mirrors always receive (no branch filter); clients
      // are filtered by branchId scope as before.
      if (!info.isMirror && info.branchId != null && branchId != null && info.branchId != branchId) continue;
      try {
        ws.sink.add(msg);
      } catch (_) {
        stale.add(ws);
      }
    }
    for (final ws in stale) {
      wsClients.remove(ws);
      try {
        ws.sink.close();
      } catch (_) {}
    }
    if (wsClients.isNotEmpty) {
      debugPrint('[WS] Broadcast: $table → ${wsClients.length} clients');
    }
  }

  /// Broadcast a record_deleted event to all connected WebSocket clients.
  /// Called when a record is soft-deleted via the API so clients can update locally.
  ///
  /// [branchId] scopes the event to matching branch subscribers only.
  void broadcastRecordDeleted(String table, int recordId, {int? branchId}) {
    final msg = json.encode({
      'event': 'record_deleted',
      'table': table,
      'recordId': recordId,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'branch_id': ?branchId,
    });
    final stale = <WebSocketChannel>[];
    for (final entry in wsClients.entries) {
      final ws = entry.key;
      final info = entry.value;
      // Spec 129 F1: mirrors always receive (no branch filter); clients
      // are filtered by branchId scope as before.
      if (!info.isMirror && info.branchId != null && branchId != null && info.branchId != branchId) continue;
      try {
        ws.sink.add(msg);
      } catch (_) {
        stale.add(ws);
      }
    }
    for (final ws in stale) {
      wsClients.remove(ws);
      try {
        ws.sink.close();
      } catch (_) {}
    }
    if (wsClients.isNotEmpty) {
      debugPrint('[WS] Broadcast record_deleted: $table#$recordId → ${wsClients.length} clients');
    }
  }

  /// Return a JSON response.
  Response jsonResponse(Map<String, dynamic> data, {int statusCode = 200}) {
    return Response(
      statusCode,
      body: json.encode(data),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// Return an error response.
  Response errorResponse(String message, {int statusCode = 500}) {
    return Response(
      statusCode,
      body: json.encode({'error': message}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Defensive Parsing Helpers
  // ═══════════════════════════════════════════════════════════════

  int parseInt(dynamic value, [int defaultValue = 0]) {
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is bool) return value ? 1 : 0;
    if (value is String) {
      if (value.trim().isEmpty) return defaultValue;
      return int.tryParse(value) ?? double.tryParse(value)?.toInt() ?? defaultValue;
    }
    return defaultValue;
  }

  int? parseIntNullable(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is bool) return value ? 1 : 0;
    if (value is String) {
      if (value.trim().isEmpty) return null;
      return int.tryParse(value) ?? double.tryParse(value)?.toInt();
    }
    return null;
  }

  double parseDouble(dynamic value, [double defaultValue = 0.0]) {
    if (value == null) return defaultValue;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) {
      if (value.trim().isEmpty) return defaultValue;
      return double.tryParse(value) ?? defaultValue;
    }
    return defaultValue;
  }

  double? parseDoubleNullable(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) {
      if (value.trim().isEmpty) return null;
      return double.tryParse(value);
    }
    return null;
  }

  /// Resolve a client-provided role id to a server-side role id (Spec 136
  /// ISS-15). Roles created on a mirror/client are written to the LOCAL db only
  /// (the repo's `insertRole` never pushes), so the server may know the role by
  /// neither its drifted local id NOR its globalId. When permissions are then
  /// pushed for that role, `role_permissions.role_id` FK fails (Postgres 23503).
  ///
  /// Resolution order — mirrors [resolvePartyId]:
  ///   1. By `roleGlobalId` (UUID) — survives id drift.
  ///   2. By `clientRoleId` — same-namespace nodes.
  ///   3. globalId present but no match → auto-create a minimal placeholder role
  ///      preserving the UUID (and name when supplied) so the FK resolves and a
  ///      later DeltaPull fills in the rest.
  ///
  /// Returns the resolved/created server id, or null iff both `clientRoleId` and
  /// `roleGlobalId` are null/empty.
  Future<int?> resolveRoleId({
    int? clientRoleId,
    String? roleGlobalId,
    String? fallbackName,
  }) async {
    if (roleGlobalId != null && roleGlobalId.isNotEmpty) {
      final byUuid = await (db.select(db.roles)
            ..where((r) => r.globalId.equals(roleGlobalId))
            ..limit(1))
          .getSingleOrNull();
      if (byUuid != null) return byUuid.id;
    }
    if (clientRoleId != null && clientRoleId > 0) {
      final byId = await (db.select(db.roles)
            ..where((r) => r.id.equals(clientRoleId))
            ..limit(1))
          .getSingleOrNull();
      if (byId != null) return byId.id;
    }
    if (roleGlobalId != null && roleGlobalId.isNotEmpty) {
      final name = (fallbackName != null && fallbackName.trim().isNotEmpty)
          ? fallbackName.trim()
          : 'دور غير معرف';
      final newId = await db.into(db.roles).insert(
            RolesCompanion.insert(
              name: name,
              globalId: drift.Value(roleGlobalId),
            ),
          );
      debugPrint('[API] resolveRoleId: auto-created placeholder role '
          'name="$name" serverId=$newId globalId=$roleGlobalId '
          '(from clientRoleId=$clientRoleId)');
      return newId;
    }
    return null;
  }

  /// Resolve a client-provided party id to a server-side party id, falling
  /// back to UUID (`partyGlobalId`) when the integer id drifts between
  /// client and server. If the globalId is present but no matching row
  /// exists on the server, auto-create a minimal placeholder row preserving
  /// the UUID so the FK resolves and a later DeltaPull can fill in details.
  ///
  /// Returns the resolved server id, or null iff both `clientPartyId` and
  /// `partyGlobalId` are null/empty.
  Future<int?> resolvePartyId({
    int? clientPartyId,
    String? partyGlobalId,
    bool isCustomer = false,
    bool isSupplier = false,
    String? fallbackName,
  }) async {
    if (partyGlobalId != null && partyGlobalId.isNotEmpty) {
      final byUuid = await (db.select(db.parties)
            ..where((p) => p.globalId.equals(partyGlobalId))
            ..limit(1))
          .getSingleOrNull();
      if (byUuid != null) return byUuid.id;
    }
    if (clientPartyId != null && clientPartyId > 0) {
      final byId = await (db.select(db.parties)
            ..where((p) => p.id.equals(clientPartyId))
            ..limit(1))
          .getSingleOrNull();
      if (byId != null) return byId.id;
    }
    if (partyGlobalId != null && partyGlobalId.isNotEmpty) {
      final name = (fallbackName != null && fallbackName.trim().isNotEmpty)
          ? fallbackName.trim()
          : (isSupplier ? 'مورد غير معرف' : 'عميل غير معرف');
      // Spec 114 — route through db.insertParty so the matching COA
      // sub-account (2111-XXXXX / 1121-XXXXX) is created atomically with
      // the party row. Pre-114 the direct `db.into(...).insert(...)` call
      // left the placeholder with `accountId = null`, causing every JE
      // that referenced it to post against the parent control account
      // (2111 / 1121) and fail validation with "حساب رئيسي". The party
      // looked fine in the parties list and the statement, but the GL
      // had no record of any transaction with it.
      final newId = await db.insertParty(
        PartiesCompanion.insert(
          name: name,
          globalId: drift.Value(partyGlobalId),
          isCustomer: drift.Value(isCustomer),
          isSupplier: drift.Value(isSupplier),
        ),
      );
      debugPrint('[API] resolvePartyId: auto-created placeholder party '
          '(via insertParty, sub-account included) name="$name" '
          'serverId=$newId globalId=$partyGlobalId '
          '(from clientPartyId=$clientPartyId)');
      return newId;
    }
    // Step 3.5: globalId absent but fallbackName provided — look up by
    // name+role first (idempotent on retry), then create a placeholder.
    if (fallbackName != null && fallbackName.trim().isNotEmpty) {
      final byName = await (db.select(db.parties)
            ..where((p) =>
                p.name.equals(fallbackName.trim()) &
                p.isSupplier.equals(isSupplier))
            ..limit(1))
          .getSingleOrNull();
      if (byName != null) return byName.id;
      // Spec 114 — same as above: go through insertParty so the
      // sub-account is created together with the placeholder.
      final newId = await db.insertParty(
        PartiesCompanion.insert(
          name: fallbackName.trim(),
          globalId: drift.Value(UuidV7.generate()),
          isCustomer: drift.Value(isCustomer),
          isSupplier: drift.Value(isSupplier),
        ),
      );
      debugPrint('[API] resolvePartyId: created name-based placeholder '
          '(via insertParty, sub-account included) name="$fallbackName" '
          'serverId=$newId (clientPartyId=$clientPartyId, no globalId)');
      return newId;
    }
    return null;
  }

  /// Resolve a client-provided product id to a server-side product id,
  /// preferring `productGlobalId` (UUID) over the integer `clientProductId`
  /// so we survive client/server id drift. When the UUID is present but no
  /// matching row exists server-side, auto-create a minimal placeholder
  /// row so the FK resolves and a later DeltaPull can fill in details.
  ///
  /// Returns the resolved server id, or null iff both inputs are null/0.
  Future<int?> resolveProductId({
    int? clientProductId,
    String? productGlobalId,
    String? fallbackCode,
    String? fallbackName,
  }) async {
    if (productGlobalId != null && productGlobalId.isNotEmpty) {
      final byUuid = await (db.select(db.products)
            ..where((p) => p.globalId.equals(productGlobalId))
            ..limit(1))
          .getSingleOrNull();
      if (byUuid != null) return byUuid.id;
    }
    if (clientProductId != null && clientProductId > 0) {
      final byId = await (db.select(db.products)
            ..where((p) => p.id.equals(clientProductId))
            ..limit(1))
          .getSingleOrNull();
      if (byId != null) return byId.id;
    }
    // Natural-key fallback: a product with the same code may already exist
    // on the server (e.g. seeded separately) — adopt it before minting a
    // placeholder. Prevents the "duplicate product on server after sale"
    // class of bug.
    if (fallbackCode != null && fallbackCode.trim().isNotEmpty) {
      final byCode = await (db.select(db.products)
            ..where((p) => p.code.equals(fallbackCode.trim()))
            ..limit(1))
          .getSingleOrNull();
      if (byCode != null) {
        if ((byCode.globalId == null || byCode.globalId!.isEmpty) &&
            productGlobalId != null && productGlobalId.isNotEmpty) {
          await (db.update(db.products)..where((p) => p.id.equals(byCode.id)))
              .write(ProductsCompanion(globalId: drift.Value(productGlobalId)));
        }
        return byCode.id;
      }
    }
    if (productGlobalId != null && productGlobalId.isNotEmpty) {
      final name = (fallbackName != null && fallbackName.trim().isNotEmpty)
          ? fallbackName.trim()
          : 'صنف غير معرف';
      final code = (fallbackCode != null && fallbackCode.trim().isNotEmpty)
          ? fallbackCode.trim()
          : 'AUTO-${productGlobalId.substring(0, 8)}';
      final newId = await db.into(db.products).insert(
        ProductsCompanion.insert(
          code: code,
          name: name,
          globalId: drift.Value(productGlobalId),
          isActive: const drift.Value(true),
          trackInventory: const drift.Value(true),
        ),
      );
      debugPrint('[API] resolveProductId: auto-created placeholder product '
          'name="$name" code="$code" serverId=$newId globalId=$productGlobalId '
          '(from clientProductId=$clientProductId)');
      return newId;
    }
    return null;
  }

  bool parseBool(dynamic value, [bool defaultValue = false]) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is int) return value == 1;
    if (value is String) {
      final str = value.trim().toLowerCase();
      if (str == 'true' || str == '1' || str == 'yes' || str == 'on') return true;
      if (str == 'false' || str == '0' || str == 'no' || str == 'off') return false;
    }
    return defaultValue;
  }
}
