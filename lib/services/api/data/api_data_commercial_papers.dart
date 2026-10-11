// ApiDataHandler - commercial papers (cheques / notes) endpoints.
part of '../api_data_handler.dart';

/// Commercial-paper endpoints of [ApiDataHandler].
extension ApiDataCommercialPapersRoutes on ApiDataHandler {
  // ═══════════════════════════════════════════════════════════════
  // Commercial Papers
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postCommercialPaper(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.commercialPapersManage);
      if (perm != null) return perm;
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      // Cluster 030 / Bug D: honour the client's locally-minted globalId
      // so mirror + server share identity. If absent, fall back to the
      // DAO's auto-mint (legacy clients pre-Cluster 030). On a globalId
      // collision (retry from a queued mirror outbox), short-circuit and
      // return the existing serverId so the operator's downstream
      // status updates resolve correctly.
      final incomingGlobalId =
          (data['globalId'] as String?)?.trim().isEmpty ?? true
              ? null
              : (data['globalId'] as String).trim();
      if (incomingGlobalId != null) {
        final existing = await (db.select(db.commercialPapers)
              ..where((p) => p.globalId.equals(incomingGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          debugPrint('[API] postCommercialPaper: globalId '
              '"$incomingGlobalId" already exists → idempotent return '
              '(serverId=${existing.id})');
          return jsonResponse({
            'success': true,
            'serverId': existing.id,
            'duplicate': true,
          });
        }
      }
      // Feature 044 — remap the client's local `partyId` via globalId.
      // Field log:
      //   commercial_papers_party_id_fkey: Key (party_id)=(1000000006) is
      //   not present in table "parties"
      // `resolvePartyId` covers: existing-globalId match → use that id,
      // existing-local-id match → use it, globalId+name supplied →
      // auto-create placeholder party so the FK lands cleanly. The
      // commercial-paper insert requires a non-null party so we throw
      // on a fully unresolvable input instead of letting the DAO crash
      // with a less informative FK error.
      final cpClientPartyId = parseIntNullable(data['partyId']);
      final cpPartyGid = (data['partyGlobalId'] as String?)?.trim();
      final cpPartyName = (data['partyName'] as String?)?.trim();
      final resolvedCpPartyId = await resolvePartyId(
        clientPartyId: cpClientPartyId,
        partyGlobalId: cpPartyGid == null || cpPartyGid.isEmpty ? null : cpPartyGid,
        fallbackName: cpPartyName == null || cpPartyName.isEmpty ? null : cpPartyName,
      );
      if (resolvedCpPartyId == null) {
        throw Exception('Validation Error: commercial_paper.partyId could '
            'not be resolved (clientPartyId=$cpClientPartyId, '
            'partyGlobalId="$cpPartyGid", partyName="$cpPartyName").');
      }

      final id = await db.createCommercialPaper(
        paperNumber: data['paperNumber'] as String,
        type: data['type'] as String,
        direction: data['direction'] as String,
        partyId: resolvedCpPartyId,
        amount: parseDouble(data['amount']),
        issueDate: DateTime.parse(data['issueDate'] as String),
        dueDate: DateTime.parse(data['dueDate'] as String),
        bankName: data['bankName'] as String?,
        safeId: parseIntNullable(data['safeId']),
        accountNumber: data['accountNumber'] as String?,
        notes: data['notes'] as String?,
        globalId: incomingGlobalId,
      );
      // E-fix ٢ (v186) — ساحبُ الشيك/مستفيدُه من الدليل (معرّفُ العميل يُحَلّ).
      await db.setCommercialPaperDrawer(id,
          accountId: await resolveClientAccountId(db, data['drawerAccount']),
          name: data['drawerName'] as String?);
      broadcast('commercial_papers');
      return jsonResponse({'success': true, 'serverId': id});
    } catch (e) {
      debugPrint('[API] postCommercialPaper error: $e');
      return ApiErrors.fail(e, 'Failed to create commercial paper');
    }
  }

  Future<Response> putCommercialPaperStatus(
      Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.commercialPapersManage);
      if (perm != null) return perm;
      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'putCommercialPaperStatus',
        tables: const {
          'commercial_papers',
          'journal_entries', 'accounting',
          'safe_transactions',
        },
        body: () async {
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      // Feature 014 / Issue 3 — accept an optional `globalId` from the
      // body. Mirror/client devices send it because their LOCAL paper id
      // does NOT match the server's auto-increment; the server resolves
      // globalId → its own paperId here. The path `id` is treated as a
      // hint and is only used when no globalId is provided (single-tier
      // / standalone deployments unchanged).
      final incomingGlobalId = data['globalId'] as String?;
      var resolvedPaperId = int.parse(id);
      if (incomingGlobalId != null && incomingGlobalId.isNotEmpty) {
        final paper = await (db.select(db.commercialPapers)
              ..where((p) => p.globalId.equals(incomingGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (paper != null) {
          resolvedPaperId = paper.id;
        } else {
          debugPrint('[API] putCommercialPaperStatus: globalId '
              '"$incomingGlobalId" not found on server; falling back to '
              'path id $id (likely 404).');
        }
      }
      // Feature 042 (Bug 5) — remap the client's local user_id to the
      // server's. The client mirror previously sent its LOCAL `changedBy`
      // straight through (commonly id=1 for the cashier on the mirror's
      // SQLite), but the server's `users` table autoincrements
      // independently and admin can land on a different id (id=2 was the
      // field repro). `paper_status_history.changed_by` is FK to
      // `users(id)` with a NOT NULL constraint, so the insert raised
      // 23503 and every status change on the mirror failed with HTTP 500.
      // Mirrors the same `_resolveUserIdNullable(... fallbackUsername:
      // data['createdByUsername'])` pattern used at postExpense (l.185),
      // postSafeTransaction (l.1833), and postReceipt — username is the
      // cross-instance-stable identifier (admin == admin), local id
      // isn't.
      final resolvedChangedBy = await _resolveUserIdNullable(
        parseIntNullable(data['changedBy']),
        fallbackUsername: data['changedByUsername'] as String?,
      );

      // Feature 048 (v130) — resolve the user-chosen contra-leg account
      // by globalId first (cross-instance stable), falling back to the
      // raw integer id (works when client + server happen to share the
      // same accounts.id, e.g. a freshly-seeded standalone install).
      // Null = no override; DAO falls back to purposes-map defaults.
      //
      // Spec 082b — surface the remap (or the failure to remap) via
      // DiagnosticLogger. Without this, if the client's globalId
      // doesn't exist on the server (sync gap, account deleted on
      // server before client refreshed), the resolver silently keeps
      // the client's raw id, the DAO's `select where id=X` either
      // finds the WRONG account or null, and the JE lands on a
      // default — invisible to support. CP-AUTOPOST-GLOBALID-MISS
      // shows the failure trail.
      int? resolvedCounterAccountId = parseIntNullable(data['counterAccountId']);
      final counterAccountGlobalId =
          (data['counterAccountGlobalId'] as String?)?.trim();
      if (counterAccountGlobalId != null && counterAccountGlobalId.isNotEmpty) {
        final byGid = await (db.select(db.accounts)
              ..where((a) => a.globalId.equals(counterAccountGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (byGid != null) {
          if (resolvedCounterAccountId != null &&
              byGid.id != resolvedCounterAccountId) {
            await DiagnosticLogger.log(
              'CP-AUTOPOST-GLOBALID-REMAP',
              'counterAccountId remapped client=$resolvedCounterAccountId → '
                  'server=${byGid.id} via globalId=$counterAccountGlobalId',
            );
          }
          resolvedCounterAccountId = byGid.id;
        } else {
          await DiagnosticLogger.log(
            'CP-AUTOPOST-GLOBALID-MISS',
            'counterAccountGlobalId=$counterAccountGlobalId NOT FOUND on '
                'server (client sent rawId=$resolvedCounterAccountId). '
                'Falling back to rawId — if it does not exist on server '
                'either, JE will land on purposes-map default or be '
                'skipped (see subsequent CP-AUTOPOST-OVERRIDE-FALLBACK / '
                'CP-AUTOPOST-WARN lines).',
          );
        }
      }

      await db.changePaperStatus(
        paperId: resolvedPaperId,
        newStatus: data['status'] as String,
        changedBy: resolvedChangedBy ?? 0,
        notes: data['notes'] as String?,
        endorsedToPartyId: parseIntNullable(data['endorsedToPartyId']),
        counterAccountId: resolvedCounterAccountId,
      );
      return jsonResponse({'success': true});
        },
      );
    } catch (e) {
      debugPrint('[API] putCommercialPaperStatus error: $e');
      return ApiErrors.fail(e, 'Failed to update paper status');
    }
  }

  Future<Response> postRenewPaper(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.commercialPapersManage);
      if (perm != null) return perm;
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      await db.renewPaper(
        paperId: int.parse(id),
        newDueDate: DateTime.parse(data['newDueDate'] as String),
        changedBy: parseIntNullable(data['changedBy']) ?? 0,
        notes: data['notes'] as String?,
      );
      broadcast('commercial_papers');
      return jsonResponse({'success': true});
    } catch (e) {
      debugPrint('[API] postRenewPaper error: $e');
      return ApiErrors.fail(e, 'Failed to renew paper');
    }
  }

  Future<Response> postPartialCollection(
      Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.commercialPapersManage);
      if (perm != null) return perm;
      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'postPartialCollection',
        tables: const {
          'commercial_papers', 'safe_transactions',
          'accounting', 'journal_entries',
        },
        body: () async {
          final data = json.decode(await request.readAsString())
              as Map<String, dynamic>;
          await db.partialCollection(
            paperId: int.parse(id),
            collectedAmount: parseDouble(data['amount']),
            changedBy: parseIntNullable(data['changedBy']) ?? 0,
            notes: data['notes'] as String?,
          );
          return jsonResponse({'success': true});
        },
      );
    } catch (e) {
      debugPrint('[API] postPartialCollection error: $e');
      return ApiErrors.fail(e, 'Failed to partially collect paper');
    }
  }

  Future<Response> postDepositForCollection(
      Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.commercialPapersManage);
      if (perm != null) return perm;
      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'postDepositForCollection',
        tables: const {'commercial_papers', 'safe_transactions'},
        body: () async {
          final data = json.decode(await request.readAsString())
              as Map<String, dynamic>;
          await db.depositForCollection(
            paperId: int.parse(id),
            bankSafeId: parseInt(data['bankSafeId']),
            changedBy: parseIntNullable(data['changedBy']) ?? 0,
            notes: data['notes'] as String?,
          );
          return jsonResponse({'success': true});
        },
      );
    } catch (e) {
      debugPrint('[API] postDepositForCollection error: $e');
      return ApiErrors.fail(e, 'Failed to deposit paper for collection');
    }
  }

  Future<Response> postReissuePaper(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.commercialPapersManage);
      if (perm != null) return perm;
      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'postReissuePaper',
        tables: const {
          'commercial_papers', 'journal_entries', 'accounting',
        },
        body: () async {
          final data = json.decode(await request.readAsString())
              as Map<String, dynamic>;
          await db.reissueToParty(
            paperId: int.parse(id),
            newPartyId: parseInt(data['newPartyId']),
            changedBy: parseIntNullable(data['changedBy']) ?? 0,
            notes: data['notes'] as String?,
          );
          return jsonResponse({'success': true});
        },
      );
    } catch (e) {
      debugPrint('[API] postReissuePaper error: $e');
      return ApiErrors.fail(e, 'Failed to reissue paper');
    }
  }
}
