// ApiDataHandler - chart of accounts, account mappings and journal entries endpoints.
part of '../api_data_handler.dart';

/// Accounting endpoints of [ApiDataHandler].
extension ApiDataAccountingRoutes on ApiDataHandler {
  // ═══════════════════════════════════════════════════════════════
  // Accounts (CoA Admin CRUD) — Feature 006 / MM.C
  //
  // Lets a mirror admin add / rename / soft-delete chart-of-accounts
  // rows from a remote laptop. Uses the same DAO methods the server's
  // own UI uses (createAccount / updateAccount / deleteAccount), so
  // the system-account / non-zero-balance guards fire identically.
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postAccount(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.accountingManage);
      if (perm != null) return perm;
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;

      final incomingGlobalId = data['globalId'] as String?;
      if (incomingGlobalId != null && incomingGlobalId.isNotEmpty) {
        final existing = await (db.select(db.accounts)
              ..where((a) => a.globalId.equals(incomingGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          return jsonResponse(
              {'success': true, 'id': existing.id, 'duplicate': true});
        }
      }

      final id = await db.createAccount(
        code: data['code'] as String,
        name: data['name'] as String,
        accountType: data['accountType'] as String,
        parentId: parseIntNullable(data['parentId']),
      );
      // Stamp caller-provided globalId so the next DeltaPull on the
      // mirror device re-attaches its local cache to this exact row.
      if (incomingGlobalId != null && incomingGlobalId.isNotEmpty) {
        await (db.update(db.accounts)..where((a) => a.id.equals(id)))
            .write(AccountsCompanion(globalId: Value(incomingGlobalId)));
      }
      broadcast('accounts');
      return jsonResponse({'success': true, 'id': id});
    } catch (e) {
      debugPrint('[API] postAccount error: $e');
      return ApiErrors.fail(e, 'Failed to create account');
    }
  }

  Future<Response> putAccount(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.accountingManage);
      if (perm != null) return perm;
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      final accountId = int.parse(id);
      await db.updateAccount(
        accountId,
        name: data.containsKey('name') ? data['name'] as String? : null,
        code: data.containsKey('code') ? data['code'] as String? : null,
        isActive: data.containsKey('isActive')
            ? parseBool(data['isActive'], true)
            : null,
        isHiddenFromEntries: data.containsKey('isHiddenFromEntries')
            ? parseBool(data['isHiddenFromEntries'], false)
            : null,
      );
      broadcast('accounts');
      return jsonResponse({'success': true});
    } catch (e) {
      debugPrint('[API] putAccount error: $e');
      return ApiErrors.fail(e, 'Failed to update account');
    }
  }

  Future<Response> deleteAccount(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.accountingManage);
      if (perm != null) return perm;
      final accountId = int.parse(id);
      await db.deleteAccount(accountId);
      broadcast('accounts');
      broadcastRecordDeleted('accounts', accountId);
      return jsonResponse({'success': true});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to delete account');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Account Mappings (purpose → account) — Feature 006 / MM.C
  //
  // setAccountMapping is upsert semantics (the DAO does delete+insert
  // inside one transaction, keyed on purpose+costCenterId). DELETE
  // accepts an optional ?cost_center_id query param so the mirror admin
  // can clear a global default OR a per-cost-center override.
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postAccountMapping(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.accountingManage);
      if (perm != null) return perm;
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      final purpose = data['purpose'] as String?;
      final accountId = parseIntNullable(data['accountId']);
      if (purpose == null || purpose.isEmpty || accountId == null) {
        return errorResponse('purpose + accountId required', statusCode: 400);
      }
      await db.setAccountMapping(
        purpose,
        accountId,
        costCenterId: parseIntNullable(data['costCenterId']),
      );
      broadcast('account_mappings');
      return jsonResponse({'success': true});
    } catch (e) {
      debugPrint('[API] postAccountMapping error: $e');
      return ApiErrors.fail(e, 'Failed to set account mapping');
    }
  }

  Future<Response> deleteAccountMapping(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.accountingManage);
      if (perm != null) return perm;
      final purpose = request.url.queryParameters['purpose'];
      if (purpose == null || purpose.isEmpty) {
        return errorResponse('purpose query param required', statusCode: 400);
      }
      final ccRaw = request.url.queryParameters['cost_center_id'];
      final costCenterId = ccRaw != null && ccRaw.isNotEmpty
          ? int.tryParse(ccRaw)
          : null;
      if (costCenterId != null) {
        await (db.delete(db.accountMappings)
              ..where((m) =>
                  m.purpose.equals(purpose) &
                  m.costCenterId.equals(costCenterId)))
            .go();
      } else {
        await (db.delete(db.accountMappings)
              ..where(
                  (m) => m.purpose.equals(purpose) & m.costCenterId.isNull()))
            .go();
      }
      broadcast('account_mappings');
      return jsonResponse({'success': true});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to delete account mapping');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Journal Entries (Client → Server sync)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postJournalEntry(Request request) async {
    try {
      // 060 (D1-001): per-user permission gate. Manual journal entries
      // are the GL escape hatch — restricted to accounting-journal perm.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.accountingJournal);
      if (perm != null) return perm;

      // Feature 054 (v134): stale-cache invalidation. See
      // api_handler_base.dart::checkIdempotency.
      final idempotencyKey = request.headers['x-idempotency-key'] ?? request.headers['X-Idempotency-Key'];
      if (idempotencyKey != null) {
        final cached = await checkIdempotency(idempotencyKey,
            verifyExists: idempotencyVerifierFor('postJournalEntry'));
        if (cached != null) {
          await DiagnosticLogger.log('API-JE',
              '⚠ idempotency-hit: returning cached response key=$idempotencyKey '
              'cached_serverId=${cached['serverId']}');
          return jsonResponse(cached);
        }
      }

      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      final description = (data['description'] ?? data['notes']) as String? ?? '';
      final dateStr = (data['date'] ?? data['entryDate'] ?? data['entry_date']) as String?;
      final date = dateStr != null ? DateTime.tryParse(dateStr) ?? DateTime.now() : DateTime.now();
      final costCenterId = parseIntNullable(data['costCenterId'] ?? data['cost_center_id']);
      final branchId = parseIntNullable(data['branchId'] ?? data['branch_id']);
      final referenceType = (data['referenceType'] ?? data['reference_type']) as String?;
      final referenceId = parseIntNullable(data['referenceId'] ?? data['reference_id']);
  // ignore: dead_code
      final isAutoPosted = parseBool(data['isAutoPosted'] ?? data['is_auto_posted']) ?? true;
      // Spec 007 / FR-008: honour the client's locally-minted globalId so
      // both sides converge on the same UUID. Without this the server minted
      // a fresh UUID, DeltaPull then re-inserted the server's row as a
      // duplicate on the originating client/mirror. Empty/whitespace-only
      // strings are treated as absent (DAO will mint).
      final incomingGlobalId =
          (data['globalId'] as String?)?.trim().isEmpty ?? true
              ? null
              : (data['globalId'] as String).trim();
      // globalId-based idempotency: if a JE with this globalId already
      // exists (retry from a client outbox / mirror reconnect), return the
      // existing serverId instead of creating a duplicate. Mirrors the
      // postSafeTransaction pattern shipped in Phase 5B.4.
      if (incomingGlobalId != null) {
        final existing = await (db.select(db.journalEntries)
              ..where((j) => j.globalId.equals(incomingGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          final responseBody = {
            'success': true,
            'duplicate': true,
            'serverId': existing.id,
            'globalId': incomingGlobalId,
          };
          if (idempotencyKey != null) {
            await storeIdempotency(idempotencyKey, responseBody, actionType: 'postJournalEntry');
          }
          return jsonResponse(responseBody);
        }
      }

      final linesList = (data['lines'] as List? ?? []);
      final lines = linesList.map<JournalLine>((item) {
        final m = item as Map<String, dynamic>;
        return JournalLine(
          accountId: parseInt(m['accountId'] ?? m['account_id']),
          debit: parseDoubleNullable(m['debit']) ?? 0,
          credit: parseDoubleNullable(m['credit']) ?? 0,
          description: (m['description'] ?? m['notes']) as String?,
          costCenterId: parseIntNullable(m['costCenterId'] ?? m['cost_center_id']) ?? costCenterId,
        );
      }).toList();

      final entryId = await db.createJournalEntry(
        description: description,
        date: date,
        lines: lines,
        referenceType: referenceType,
        referenceId: referenceId,
        isAutoPosted: isAutoPosted,
        costCenterId: costCenterId,
        branchId: branchId,
        globalId: incomingGlobalId,
      );

      broadcast('journals');
      broadcast('accounting');
      db.markTablesUpdated({db.journalEntries, db.journalEntryLines});

      final responseBody = {
        'success': true,
        'serverId': entryId,
        'globalId': incomingGlobalId,
        'idempotencyKey': idempotencyKey,
      };
      if (idempotencyKey != null) {
        await storeIdempotency(idempotencyKey, responseBody, actionType: 'postJournalEntry');
      }
      return jsonResponse(responseBody);
    } catch (e) {
      debugPrint('[API] postJournalEntry error: $e');
      return ApiErrors.fail(e, 'Failed to create journal entry');
    }
  }
}
