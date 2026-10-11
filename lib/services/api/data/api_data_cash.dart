// ApiDataHandler - receipts and cashier shift endpoints.
part of '../api_data_handler.dart';

/// Receipt and shift (open/close) endpoints of [ApiDataHandler].
extension ApiDataCashRoutes on ApiDataHandler {
  Future<Response> postReceipt(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.treasuryReceiptsCreate);
      if (perm != null) return perm;
      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'postReceipt',
        tables: const {
          'safe_transactions', 'accounting', 'journal_entries',
          'commercial_papers',
        },
        body: () async {
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;

      // Issue 12 — globalId-based idempotency. Mirrors the postExpense
      // pattern: a retry from the outbox with the same globalId returns
      // the existing serverId instead of inserting a phantom duplicate.
      final incomingGlobalId = data['globalId'] as String?;
      if (incomingGlobalId != null && incomingGlobalId.isNotEmpty) {
        final existing = await (db.select(db.safeTransactions)
              ..where((t) => t.globalId.equals(incomingGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          return jsonResponse({
            'success': true,
            'duplicate': true,
            'serverId': existing.id,
          });
        }
      }

      // Issue 12 — resolve `safeId` to a server-side id. Client and server
      // each seed the chart of safes independently, so the same logical
      // safe (e.g. "صندوق نقد المعان") commonly has different numeric ids
      // on each side. SafeSyncStrategy keeps the local id when matching
      // by name, so the client's `safeId` is its OWN id — useless on the
      // server. Prefer match by `safeGlobalId`, fall back to raw safeId.
      int? resolvedSafeId = parseIntNullable(data['safeId']);
      final clientSafeGlobalId = (data['safeGlobalId'] as String?)?.trim();
      if (clientSafeGlobalId != null && clientSafeGlobalId.isNotEmpty) {
        final byGlobal = await (db.select(db.safes)
              ..where((s) => s.globalId.equals(clientSafeGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (byGlobal != null) {
          if (byGlobal.id != resolvedSafeId) {
            debugPrint('[API] postReceipt: remapped safeId '
                '$resolvedSafeId → ${byGlobal.id} via globalId');
          }
          resolvedSafeId = byGlobal.id;
        }
      }

      // Resolve costCenterId — prefer explicit value, otherwise derive
      // from the branchId the client sent so the journal entry lands on
      // the right cost center even when the client didn't compute one.
      int? costCenterId = parseIntNullable(data['costCenterId']);
      final clientBranchId = parseIntNullable(data['branchId']);
      if (costCenterId == null && clientBranchId != null) {
        try {
          final branch = await (db.select(db.branches)
                ..where((b) => b.id.equals(clientBranchId))
                ..limit(1))
              .getSingleOrNull();
          costCenterId = branch?.costCenterId;
        } catch (_) {}
      }

      // Feature 044 — remap partyId via globalId, same as postExpense.
      // Without this the receipt's safe_transactions row hit the FK on
      // party_id when the mirror's local autoincrement diverged from
      // the server.
      final clientRcpPartyId = parseIntNullable(data['partyId']);
      final rcpPartyGid = (data['partyGlobalId'] as String?)?.trim();
      final rcpPartyName = (data['partyName'] as String?)?.trim();
      int? resolvedRcpPartyId;
      if (clientRcpPartyId != null && clientRcpPartyId > 0) {
        resolvedRcpPartyId = await resolvePartyId(
          clientPartyId: clientRcpPartyId,
          partyGlobalId: rcpPartyGid == null || rcpPartyGid.isEmpty ? null : rcpPartyGid,
          fallbackName: rcpPartyName == null || rcpPartyName.isEmpty ? null : rcpPartyName,
        );
      }

      // Spec 133 — when the client sends paperType='cheque', skip the
      // cash-leg JE and the safe transaction on the server side too,
      // so the server's pull doesn't re-introduce the duplicate JE that
      // mirror/client installs would otherwise inherit on next sync.
      // Symmetric with postExpense's Spec 081 fix (this file, postExpense
      // around line 118-119).
      final receiptPaperType = data['paperType'] as String?;
      final receiptIsCheque =
          receiptPaperType == 'cheque' || receiptPaperType == 'check';

      final id = await db.createReceiptVoucher(
        amount: parseDouble(data['amount']),
        category: data['category'] as String,
        discount: parseDouble(data['discount']),
        description: data['description'] as String?,
        partyId: resolvedRcpPartyId,
        safeId: resolvedSafeId,
        userId: await _resolveUserIdNullable(parseIntNullable(data['userId']),
            fallbackUsername: data['createdByUsername'] as String?),
        costCenterId: costCenterId,
        // Issue 3 (Feature 020): honor the operator's CoA account pick from
        // the client. Without this, the server's JE credit leg falls back to
        // the category-default account and diverges from what the local JE
        // posted on the client. Null means "no override" — the existing
        // category-derived behavior runs unchanged.
        linkedAccountId: parseIntNullable(data['linkedAccountId']),
        globalId: incomingGlobalId,
        skipJournalEntry: receiptIsCheque,
        skipSafeTransaction: receiptIsCheque,
        // Spec 135 BUG-C — attribute the JE to the operator's branch (the
        // client sent it) instead of the target safe's branch.
        operatingBranchId: clientBranchId,
      );

      // Spec 133 (FR-010) — discount-only JE for cheque receipts with a
      // settlement discount. Same helper the repo path uses (mirrors
      // treasury_repository_impl.dart::createReceiptVoucher). The
      // commercial-papers `pending` autopost handles the cheque amount;
      // this handles ONLY the discount portion so the customer's
      // outstanding balance lands at the correct net.
      if (receiptIsCheque) {
        final discountAmount = parseDouble(data['discount']);
        if (discountAmount > 0 && resolvedRcpPartyId != null) {
          await ChequeReceiptJEs.postDiscountAllowedJournalEntry(
            db: db,
            partyId: resolvedRcpPartyId,
            discountAmount: discountAmount,
            costCenterId: costCenterId,
            branchId: clientBranchId,
          );
        }
      }

      return jsonResponse({'success': true, 'serverId': id});
        },
      );
    } catch (e) {
      debugPrint('[API] postReceipt error: $e');
      return ApiErrors.fail(e, 'Failed to record receipt');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Shifts
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postOpenShift(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.posShiftOpen);
      if (perm != null) return perm;
      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'postOpenShift',
        // openShift writes a shifts row + an opening safe_transaction; an
        // opening-balance JE is not auto-posted by the current path, but
        // declaring the accounting tables is the safe maximum if a future
        // wiring lands.
        tables: const {
          'shifts', 'safe_transactions', 'accounting', 'journal_entries',
        },
        body: () async {
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      final resolvedUserId = await _resolveUserId(parseInt(data['userId']),
          fallbackUsername: data['createdByUsername'] as String?);
      // Spec 008 / FR-006: honour the client's branchId so the close-time
      // logic on this side (and on every paired client) can pull the right
      // branch's safes for shift-close zero-out.
      final branchId = parseIntNullable(data['branchId'] ?? data['branch_id']);
      // R9 idempotency: if the client sent a globalId and we already have a
      // shift for it, return that id instead of opening a duplicate. This
      // covers outbox replays + retries that previously created phantom
      // server shifts every time.
      final clientGlobalId = data['globalId'] as String?;
      if (clientGlobalId != null && clientGlobalId.isNotEmpty) {
        final existing = await (db.select(db.shifts)
              ..where((s) => s.globalId.equals(clientGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          debugPrint('[API] postOpenShift: dedup by globalId=$clientGlobalId '
              '→ existing shiftId=${existing.id}');
          return jsonResponse({'success': true, 'shiftId': existing.id});
        }
      }

      // Feature 048 (v130) — duplicate-open guard. Field log
      // (2026-05-13) showed admin user accumulated 4 simultaneously
      // open shifts on the server (ids 1, 2, 3, 5) because every mirror
      // open call created a NEW row without checking the user's state.
      // Symptoms cascaded: `getCurrentOpenShift(userId)` returned
      // different ids on different reads, shift-close calls disappeared
      // (they targeted a different open shift than the cashier saw),
      // and the closing report aggregated the wrong window.
      //
      // Fix: before INSERT, look up the user's existing open shift on
      // THIS server. If one exists, return its id (idempotent open).
      // The client still treats the response as "shift opened" because
      // the response shape is identical — but the server no longer
      // creates phantoms. Combined with v129's reverse carve-out
      // (Feature 036), the system now self-heals: stale opens stop
      // accumulating AND existing recently-closed shifts are protected
      // from flip-back.
      final existingOpen = await (db.select(db.shifts)
            ..where((s) =>
                s.userId.equals(resolvedUserId) &
                s.status.equals('open'))
            ..orderBy([(s) => OrderingTerm.desc(s.id)])
            ..limit(1))
          .getSingleOrNull();
      if (existingOpen != null) {
        debugPrint('[API] postOpenShift: user $resolvedUserId already has '
            'an open shift (id=${existingOpen.id}, globalId='
            '${existingOpen.globalId ?? "null"}) — returning that instead '
            'of creating a duplicate. Feature 048 v130 guard.');
        return jsonResponse({
          'success': true,
          'shiftId': existingOpen.id,
          'duplicate': true,
          'reason': 'user_has_open_shift',
        });
      }

      final shiftId = await db.openShift(
        resolvedUserId,
        parseDoubleNullable(data['openingBalance']) ?? 0,
        branchId: branchId,
        globalId: clientGlobalId,
      );
      return jsonResponse({'success': true, 'shiftId': shiftId});
        },
      );
    } catch (e) {
      debugPrint('[API] postOpenShift error: $e');
      return ApiErrors.fail(e, 'Failed to open shift');
    }
  }

  Future<Response> postCloseShift(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.posShiftClose);
      if (perm != null) return perm;
      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'postCloseShift',
        // Close path writes variance JE + ZRO safe_transactions per safe +
        // safes.balance updates.
        tables: const {
          'shifts', 'safes', 'safe_transactions',
          'accounting', 'journal_entries',
        },
        body: () async {
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;

      int shiftId = parseInt(data['shiftId']);

      // R9 (2026-05-12 fix): prefer globalId-based resolution. The client's
      // local SQLite shiftId rarely matches the server's auto-increment id
      // because the original /api/shifts/open response wasn't mapped back
      // (online opens bypass the outbox where mappedIds is populated). The
      // result was a recurring "Shift not found" 500 → DEAD-LETTER on every
      // shift close. Looking up by globalId fixes the root cause without
      // requiring a separate id-mapping table on the client.
      final shiftGlobalId = data['shiftGlobalId'] as String?;
      if (shiftGlobalId != null && shiftGlobalId.isNotEmpty) {
        final byGlobalId = await (db.select(db.shifts)
              ..where((s) => s.globalId.equals(shiftGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (byGlobalId != null) {
          // Idempotency: a retried close on an already-closed shift is a
          // no-op success — never throw.
          if (byGlobalId.status == 'closed') {
            debugPrint('[API] postCloseShift: globalId=$shiftGlobalId already '
                'closed (id=${byGlobalId.id}) — returning success');
            return jsonResponse(
                {'success': true, 'shiftId': byGlobalId.id, 'alreadyClosed': true});
          }
          shiftId = byGlobalId.id;
        }
      }

      // Defense in depth: if the client sent a shiftId that doesn't exist on
      // this server, reset to 0 so the userId-based fallback / reconstruction
      // path kicks in (instead of throwing "Shift not found"). Only triggers
      // when the globalId lookup above didn't already resolve a row.
      if (shiftId != 0) {
        final exists = await (db.select(db.shifts)
              ..where((s) => s.id.equals(shiftId))
              ..limit(1))
            .getSingleOrNull();
        if (exists == null) {
          debugPrint('[API] postCloseShift: shiftId=$shiftId not found on '
              'server — falling back to userId lookup / reconstruction');
          shiftId = 0;
        }
      }

      // Client mode sends shiftId=0 when the local DB doesn't have the shift yet.
      // Fall back to looking up the user's currently open shift by userId.
      // Supports two payload formats:
      //   • New (post-fix): payload contains explicit 'userId' field
      //   • Old (pre-fix):  userId is encoded in 'notes' as "userId=X,actualCard=Y"
      if (shiftId == 0) {
        // Try explicit userId field first (new format)
        int? userId = parseIntNullable(data['userId']);

        // Fall back to parsing from notes string (old format queued before fix)
        if (userId == null) {
          final notes = (data['notes'] as String?) ?? '';
          final match = RegExp(r'userId=(\d+)').firstMatch(notes);
          userId = match != null ? int.tryParse(match.group(1) ?? '') : null;
        }

        if (userId != null) {
          final openShift = await db.getCurrentOpenShift(userId);
          if (openShift != null) shiftId = openShift.id;
        }
      }

      // Phase 5A.7 (Issue 2) — when no server shift exists, RECONSTRUCT
      // it from the close payload's reconstruction hints (openingBalance,
      // openedAt, userId) before closing. Previously this branch returned
      // {clientAuthoritative: true} and never wrote anything, leaving the
      // server's reports forever inconsistent with the client's books
      // (the user's exact complaint: "إقفال الوردية لا يُرحَّل بشكل سليم").
      //
      // The client now ships these hints in the close payload (cwi_catalog
      // closeShift). Outbox rows queued before this change won't have
      // them; in that legacy case we fall back to opening with a zero
      // balance + a backfill flag so the server still has SOMETHING to
      // close — better than a silent acknowledge.
      if (shiftId == 0) {
        final reconstructUserId = parseIntNullable(data['userId']);
        if (reconstructUserId == null) {
          debugPrint('[API] postCloseShift: cannot reconstruct shift — '
              'no userId in payload. Rejecting.');
          return errorResponse('Cannot reconstruct shift: userId required');
        }
        final openingBalance =
            parseDoubleNullable(data['openingBalance']) ?? 0.0;
        final openedAtRaw = data['openedAt'] as String?;
        debugPrint('[API] postCloseShift: reconstructing missing shift for '
            'userId=$reconstructUserId, openingBalance=$openingBalance');
        final resolvedUserId = await _resolveUserId(reconstructUserId,
            fallbackUsername: data['createdByUsername'] as String?);
        // Spec 008 / FR-006: best-effort branchId for the reconstructed
        // shift. The close payload may carry it (when the open queued
        // offline + close arrives first); if not, we leave it null and the
        // close logic falls back to getUserBranchId — same as legacy rows.
        final reconstructBranchId =
            parseIntNullable(data['branchId'] ?? data['branch_id']);
        shiftId = await db.openShift(
          resolvedUserId,
          openingBalance,
          branchId: reconstructBranchId,
          // R9: thread the client's shiftGlobalId into the reconstructed
          // server row so future retries dedup by globalId (instead of
          // reconstructing a fresh phantom shift on every replay).
          globalId: shiftGlobalId,
        );
        // Backdate startTime if the client told us when the shift opened
        // — keeps shift duration analytics honest. Best-effort: ignore
        // failures so a malformed timestamp doesn't break the close.
        if (openedAtRaw != null) {
          final parsed = DateTime.tryParse(openedAtRaw);
          if (parsed != null) {
            try {
              await (db.update(db.shifts)
                    ..where((s) => s.id.equals(shiftId)))
                  .write(ShiftsCompanion(startTime: Value(parsed)));
            } catch (_) {}
          }
        }
      }

      await db.closeShiftWithAudit(
        shiftId,
        parseDouble(data['actualCash']),
        notes: data['notes'] as String?,
        closingMethod: (data['closingMethod'] as String?) ?? 'normal',
        // v151 — persist the client's closing figures on the server too;
        // otherwise a shift closed from a client terminal has no snapshot to
        // reprint from anywhere but that one machine.
        closingSnapshot: data['closingSnapshot'] as String?,
      );
      return jsonResponse({'success': true, 'shiftId': shiftId});
        },
      );
    } catch (e) {
      debugPrint('[API] postCloseShift error: $e');
      return ApiErrors.fail(e, 'Failed to close shift');
    }
  }
}
