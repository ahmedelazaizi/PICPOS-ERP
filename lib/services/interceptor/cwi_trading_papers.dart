part of '../client_write_interceptor.dart';


// ═══════════════════════════════════════════════════════════════════════════
// Trading module — Sales · Inventory · Commercial Papers · Safe Operations
//                  Stock Transfers · Purchase Auto-Push
//
// Part of the ClientWriteInterceptor library.
// ═══════════════════════════════════════════════════════════════════════════

class _CwiTradingPapers {
  _CwiTradingPapers._();

  // ── Sales ─────────────────────────────────────────────────────────────────


  // ── Commercial Papers ─────────────────────────────────────────────────────

  static Future<int?> createCommercialPaper({
    required String paperNumber,
    required String type,
    required String direction,
    required int partyId,
    required double amount,
    required DateTime issueDate,
    required DateTime dueDate,
    String? bankName,
    int? safeId,
    String? accountNumber,
    String? notes,
    // Cluster 030 / Bug D — caller mints the globalId once and passes
    // it to BOTH this interceptor and the local DAO so mirror + server
    // converge on the same identity. Without this, the next status
    // update from the mirror failed with "Commercial paper not found"
    // because the server's auto-minted globalId didn't match the
    // mirror's local one.
    String? globalId,
  }) async {
    if (!SyncInterceptor.isClientMode) return null;
    debugPrint('[ClientInterceptor] Routing commercial paper create to server');

    // Feature 044 — thread `partyGlobalId` + `partyName` so the server
    // resolves the party via `resolvePartyId`. Field log:
    //   commercial_papers_party_id_fkey: Key (party_id)=(1000000006) is not
    //   present in table "parties"
    // The high autoincrement offset on the mirror's local `parties.id`
    // does not exist on the server. globalId is the cross-instance-stable
    // identifier; name is the fallback when the party row never reached
    // the server via DeltaPush yet.
    final partyGlobalId =
        await ClientWriteInterceptor._lookupPartyGlobalId(partyId);
    final partyName = await ClientWriteInterceptor._lookupPartyName(partyId);

    final payload = <String, dynamic>{
      'paperNumber': paperNumber,
      'type': type,
      'direction': direction,
      'partyId': partyId,
      'partyGlobalId': ?partyGlobalId,
      'partyName': ?partyName,
      'amount': amount,
      'issueDate': issueDate.toIso8601String(),
      'dueDate': dueDate.toIso8601String(),
      'bankName': bankName,
      'safeId': safeId,
      'accountNumber': accountNumber,
      'notes': notes,
      'globalId': globalId,
    };
    return ClientWriteInterceptor._tryOrQueue(
      tableName: 'commercial_papers',
      operation: 'insert',
      payload: payload,
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.createCommercialPaper(payload),
    );
  }

  static Future<bool> updateCommercialPaperStatus(
    int id,
    String status, {
    int? changedBy,
    String? notes,
    // Feature 048 (v130) — user-chosen contra leg for the JE. Resolved
    // to the server's account id via globalId remap inside the handler
    // (same pattern as partyGlobalId in Feature 044) so the JE posts
    // on the same account the cashier saw in the dropdown.
    int? counterAccountId,
  }) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing paper status update to server '
        '(counterAccountId=${counterAccountId ?? "null"})');
    // Feature 014 / Issue 3 — the client's `id` here is the LOCAL row id,
    // which does NOT generally match the server's auto-increment.
    // Previously we sent the local id and the server returned 404
    // ("Commercial paper not found: 2"). Fix: resolve the local row's
    // globalId and forward it; the server (api_data_handler.dart's
    // putCommercialPaperStatus) now accepts an optional `globalId` body
    // field that takes precedence over the path id when resolving the
    // target row.
    String? globalId;
    // Feature 042 (Bug 5) — also resolve the changing user's USERNAME on
    // the client so the server can remap the local user_id to its own
    // user table. Without this the server's `paper_status_history`
    // INSERT hit FK violation 23503 ("Key (changed_by)=(1) is not
    // present in table users") on every status change from the mirror,
    // because client and server hold independently-numbered `users.id`
    // sequences. Username is the cross-instance-stable identifier.
    String? changedByUsername;
    // Feature 048 — also resolve the counter account's globalId so the
    // server can remap to its own accounts.id even when client/server
    // chart-of-accounts auto-increments diverge (same divergence
    // pattern that party-id / user-id remap handles).
    String? counterAccountGlobalId;
    try {
      final db = ClientWriteInterceptor._db;
      if (db != null) {
        final row = await (db.select(db.commercialPapers)
              ..where((p) => p.id.equals(id))
              ..limit(1))
            .getSingleOrNull();
        globalId = row?.globalId;

        if (changedBy != null) {
          final u = await (db.select(db.users)
                ..where((x) => x.id.equals(changedBy))
                ..limit(1))
              .getSingleOrNull();
          changedByUsername = u?.username;
        }

        if (counterAccountId != null) {
          final acct = await (db.select(db.accounts)
                ..where((a) => a.id.equals(counterAccountId))
                ..limit(1))
              .getSingleOrNull();
          counterAccountGlobalId = acct?.globalId;
        }
      }
    } catch (e) {
      debugPrint('[ClientInterceptor] paper globalId/username/account '
          'lookup failed: $e');
    }
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'commercial_papers',
      operation: 'update_status',
      payload: {
        'id': id,
        'globalId': globalId,
        'status': status,
        'changedBy': changedBy,
        'changedByUsername': changedByUsername,
        'notes': notes,
        'counterAccountId': counterAccountId,
        if (counterAccountGlobalId != null && counterAccountGlobalId.isNotEmpty)
          'counterAccountGlobalId': counterAccountGlobalId,
      },
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy
          .updateCommercialPaperStatus(id,
              globalId: globalId,
              status: status,
              changedBy: changedBy,
              changedByUsername: changedByUsername,
              notes: notes,
              counterAccountId: counterAccountId,
              counterAccountGlobalId: counterAccountGlobalId),
    );
  }

  static Future<bool> renewCommercialPaper(
    int id,
    DateTime newDueDate, {
    int? changedBy,
    String? notes,
  }) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing paper renew to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'commercial_papers',
      operation: 'renew',
      payload: {
        'id': id,
        'newDueDate': newDueDate.toIso8601String(),
        'changedBy': changedBy,
        'notes': notes,
      },
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy.renewCommercialPaper(
        id,
        newDueDate: newDueDate.toIso8601String(),
        changedBy: changedBy,
        notes: notes,
      ),
    );
  }

  static Future<bool> partialCollectPaper(
    int id,
    double amount, {
    int? changedBy,
    String? notes,
  }) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing partial collection to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'commercial_papers',
      operation: 'partial_collect',
      payload: {'id': id, 'amount': amount, 'changedBy': changedBy, 'notes': notes},
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy.partialCollectPaper(
        id, amount: amount, changedBy: changedBy, notes: notes),
    );
  }

  static Future<bool> endorseCommercialPaper(
    int id,
    int toPartyId, {
    int? changedBy,
    String? notes,
  }) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing paper endorse to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'commercial_papers',
      operation: 'endorse',
      payload: {
        'id': id,
        'status': 'endorsed',
        'endorsedToPartyId': toPartyId,
        'changedBy': changedBy,
        'notes': notes,
      },
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy.updateCommercialPaperStatus(
        id,
        status: 'endorsed',
        changedBy: changedBy,
        notes: notes,
        endorsedToPartyId: toPartyId,
      ),
    );
  }

  static Future<bool> depositPaperForCollection(
    int id,
    int bankSafeId, {
    int? changedBy,
    String? notes,
  }) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing deposit for collection to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'commercial_papers',
      operation: 'deposit',
      payload: {'id': id, 'bankSafeId': bankSafeId, 'changedBy': changedBy, 'notes': notes},
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy.depositPaperForCollection(
        id, bankSafeId: bankSafeId, changedBy: changedBy, notes: notes),
    );
  }

  static Future<bool> reissueCommercialPaper(
    int id,
    int newPartyId, {
    int? changedBy,
    String? notes,
  }) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing paper reissue to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'commercial_papers',
      operation: 'reissue',
      payload: {
        'id': id,
        'newPartyId': newPartyId,
        'changedBy': changedBy,
        'notes': notes,
      },
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy.reissuePaper(
        id, newPartyId: newPartyId, changedBy: changedBy, notes: notes),
    );
  }
}
