// ApiDataHandler - safes, safe close, safe transactions and transfers endpoints.
part of '../api_data_handler.dart';

/// Treasury endpoints of [ApiDataHandler].
extension ApiDataTreasuryRoutes on ApiDataHandler {
  // ═══════════════════════════════════════════════════════════════
  // Safes (Admin CRUD) — Feature 006 / MM.C
  //
  // Creation goes through createSafeWithLinkedAccount so the safe is
  // atomically paired with a CoA sub-account (Feature 004 / FR-006).
  // The dedicated postCloseSafe / postSafeTransaction / postSafeTransfer
  // / postSetDefaultSafe endpoints are unchanged — those handle
  // operational moves; this group handles structural CRUD.
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postSafe(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.treasuryManage);
      if (perm != null) return perm;
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;

      final incomingGlobalId = data['globalId'] as String?;
      if (incomingGlobalId != null && incomingGlobalId.isNotEmpty) {
        final existing = await (db.select(db.safes)
              ..where((s) => s.globalId.equals(incomingGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          return jsonResponse(
              {'success': true, 'id': existing.id, 'duplicate': true});
        }
      }

      final id = await db.createSafeWithLinkedAccount(
        name: data['name'] as String,
        safeType: (data['safeType'] as String?) ?? 'cash',
        bankName: data['bankName'] as String?,
        accountNumber: data['accountNumber'] as String?,
        costCenterId: parseIntNullable(data['costCenterId']),
        branchId: parseIntNullable(data['branchId']),
      );

      // Stamp the caller-provided globalId so the next DeltaPull on the
      // mirror device re-attaches its local cache to this exact row.
      if (incomingGlobalId != null && incomingGlobalId.isNotEmpty) {
        await (db.update(db.safes)..where((s) => s.id.equals(id)))
            .write(SafesCompanion(globalId: Value(incomingGlobalId)));
      }
      broadcast('safes');
      broadcast('accounts'); // linked CoA sub-account also created
      return jsonResponse({'success': true, 'id': id});
    } catch (e) {
      debugPrint('[API] postSafe error: $e');
      return ApiErrors.fail(e, 'Failed to create safe');
    }
  }

  Future<Response> putSafe(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.treasuryManage);
      if (perm != null) return perm;
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      final safeId = int.parse(id);
      // Mirror the rename to the linked CoA account in a single
      // transaction so a reader never sees a half-renamed pair.
      await db.transaction(() async {
        final existing = await (db.select(db.safes)
              ..where((s) => s.id.equals(safeId))
              ..limit(1))
            .getSingleOrNull();
        await (db.update(db.safes)..where((s) => s.id.equals(safeId)))
            .write(
          SafesCompanion(
            name: data.containsKey('name')
                ? Value(data['name'] as String)
                : const Value.absent(),
            bankName: data.containsKey('bankName')
                ? Value(data['bankName'] as String?)
                : const Value.absent(),
            accountNumber: data.containsKey('accountNumber')
                ? Value(data['accountNumber'] as String?)
                : const Value.absent(),
            costCenterId: data.containsKey('costCenterId')
                ? Value(parseIntNullable(data['costCenterId']))
                : const Value.absent(),
            branchId: data.containsKey('branchId')
                ? Value(parseIntNullable(data['branchId']))
                : const Value.absent(),
            isActive: data.containsKey('isActive')
                ? Value(parseBool(data['isActive'], true))
                : const Value.absent(),
          ),
        );
        if (existing != null &&
            existing.linkedAccountId != null &&
            data.containsKey('name') &&
            (data['name'] as String) != existing.name) {
          await (db.update(db.accounts)
                ..where((a) => a.id.equals(existing.linkedAccountId!)))
              .write(AccountsCompanion(name: Value(data['name'] as String)));
        }
      });
      broadcast('safes');
      broadcast('accounts');
      return jsonResponse({'success': true});
    } catch (e) {
      debugPrint('[API] putSafe error: $e');
      return ApiErrors.fail(e, 'Failed to update safe');
    }
  }

  Future<Response> deleteSafe(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.treasuryManage);
      if (perm != null) return perm;
      final safeId = int.parse(id);
      await db.deleteSafeById(safeId);
      broadcast('safes');
      broadcastRecordDeleted('safes', safeId);
      return jsonResponse({'success': true});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to delete safe');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Treasury — Safe Close
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postCloseSafe(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.treasuryManage);
      if (perm != null) return perm;
      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'postCloseSafe',
        // closeSafe writes a closing safe_transaction, updates safes.balance,
        // and may post a closing JE.
        tables: const {
          'safes', 'safe_transactions',
          'accounting', 'journal_entries',
        },
        body: () async {
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      // Spec 135: honour the client's amounts + closeEventGid so the server
      // posts the IDENTICAL closing JE with the SAME deterministic globalId
      // (dedup against the client's local row on DeltaPull).
      await db.closeSafe(
        parseInt(data['safeId']),
        userId: parseIntNullable(data['userId']),
        cashAmount: (data['cashAmount'] as num?)?.toDouble(),
        bankAmount: (data['bankAmount'] as num?)?.toDouble(),
        notes: data['notes'] as String?,
        closeEventGid: data['closeEventGid'] as String?,
      );
      return jsonResponse({'success': true});
        },
      );
    } catch (e) {
      debugPrint('[API] postCloseSafe error: $e');
      return ApiErrors.fail(e, 'Failed to close safe');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Safe Transactions (Client → Server sync)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postSafeTransaction(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.treasuryManage);
      if (perm != null) return perm;
      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'postSafeTransaction',
        // No JE is posted by this endpoint today; accounting/journal_entries
        // are declared as the safe maximum in case a future wiring lands.
        tables: const {
          'safe_transactions', 'safes',
          'accounting', 'journal_entries',
        },
        body: () async {
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;

      // Phase 5B.4 (Issue 7) — globalId-based idempotency. Mirrors the
      // postReceipt pattern: a retry from the outbox with the same
      // globalId returns the existing serverId instead of inserting a
      // phantom duplicate. Also lets the JE on this side dedup against
      // the client's local JE via deterministic globalId derivation
      // when 5B.1 is wired through (currently this endpoint doesn't
      // post a JE, but its globalId still anchors the safe_transactions
      // identity for SafeTransactionSyncStrategy).
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

      // Phase 5B.4 (Issue 7) — resolve `safeId` via `safeGlobalId` when
      // the client supplied one. Same divergence problem as postReceipt:
      // each side seeds the chart of safes independently and keeps its
      // own autoincrement, so trusting the client's `safeId` blindly
      // posts the transaction (and any downstream JE) to the wrong
      // safe's linked GL account on the server. globalId is the only
      // stable identifier across both sides.
      int resolvedSafeId = parseInt(data['safeId'] ?? data['safe_id']);
      final clientSafeGlobalId = (data['safeGlobalId'] as String?)?.trim();
      if (clientSafeGlobalId != null && clientSafeGlobalId.isNotEmpty) {
        final byGlobal = await (db.select(db.safes)
              ..where((s) => s.globalId.equals(clientSafeGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (byGlobal != null) {
          if (byGlobal.id != resolvedSafeId) {
            debugPrint('[API] postSafeTransaction: remapped safeId '
                '$resolvedSafeId → ${byGlobal.id} via globalId');
          }
          resolvedSafeId = byGlobal.id;
        }
      }
      final transactionType = (data['transactionType'] ?? data['transaction_type']) as String; // receipt, payment
      final category = data['category'] as String? ?? 'general';
      final amount = parseDouble(data['amount']);
      final description = (data['description'] ?? data['notes']) as String?;
      final userId = await _resolveUserIdNullable(parseIntNullable(data['userId'] ?? data['user_id']),
          fallbackUsername: data['createdByUsername'] as String?);
      final referenceType = (data['referenceType'] ?? data['reference_type']) as String?;
      final referenceId = parseIntNullable(data['referenceId'] ?? data['reference_id']);
      final costCenterId = parseIntNullable(data['costCenterId'] ?? data['cost_center_id']);

      // Spec 087 (F2) — resolve partyId on the server side so the
      // safe-transaction row carries the right party link. Previously
      // this endpoint silently dropped partyId; vouchers replayed
      // through here (outbox retries, non-receipt-dialog code paths)
      // landed with partyId=null on the server and the voucher was
      // missing from the customer/supplier statement on every client
      // that later pulled the row. Mirrors the resolution pattern
      // already used in postReceipt (cl.338-348).
      final clientStPartyId = parseIntNullable(data['partyId'] ?? data['party_id']);
      final stPartyGid = (data['partyGlobalId'] as String?)?.trim();
      final stPartyName = (data['partyName'] as String?)?.trim();
      int? resolvedStPartyId;
      if (clientStPartyId != null && clientStPartyId > 0) {
        resolvedStPartyId = await resolvePartyId(
          clientPartyId: clientStPartyId,
          partyGlobalId: stPartyGid == null || stPartyGid.isEmpty ? null : stPartyGid,
          fallbackName: stPartyName == null || stPartyName.isEmpty ? null : stPartyName,
        );
      }

      // Get current safe balance
      final safe = await (db.select(db.safes)
            ..where((s) => s.id.equals(resolvedSafeId)))
          .getSingleOrNull();
      if (safe == null) {
        return errorResponse('Safe not found: $resolvedSafeId');
      }

      final balanceChange = transactionType == 'receipt' ? amount : -amount;

      // Feature 005 Phase 8 — atomic safe-balance update to prevent the
      // Lost-Update race when two clients post safe transactions to the
      // same safe concurrently. Pre-005 this read `safe.balance` outside
      // a transaction, computed `newBalance = safe.balance + change`, then
      // wrote the absolute value via `updateSafeBalance` — under PostgreSQL's
      // default Read-Committed isolation two concurrent requests both saw
      // the same starting balance and the second write silently clobbered
      // the first. Now both the insert and the increment run inside a
      // single transaction with SQL-level arithmetic (`balance = balance + ?`)
      // and the recorded `balanceAfter` is read AFTER the increment so it
      // reflects the actual post-state.
      // 066 (D5-001): generateInvoiceNumber moved inside the txn so the
      // RV/PV counter rolls back if the safe-update or insert fails.
  // ignore: unused_local_variable
      final newBalance = await db.transaction(() async {
        final voucherNumber = await db.generateInvoiceNumber(
          transactionType == 'receipt' ? 'RV' : 'PV',
        );
        await db.customStatement(
          'UPDATE safes SET balance = balance + ? WHERE id = ?',
          [balanceChange, resolvedSafeId],
        );
        final updated = await (db.select(db.safes)
              ..where((s) => s.id.equals(resolvedSafeId))
              ..limit(1))
            .getSingle();
        final stId = await db.into(db.safeTransactions).insert(
          SafeTransactionsCompanion.insert(
            voucherNumber: voucherNumber,
            safeId: resolvedSafeId,
            transactionType: transactionType,
            category: category,
            amount: amount,
            balanceAfter: updated.balance,
            description: Value(description),
            referenceType: Value(referenceType),
            referenceId: Value(referenceId),
            userId: Value(userId),
            // Phase 5B.4 — persist the cost center the dialog selected.
            costCenterId: Value(costCenterId),
             currencyId: Value(parseIntNullable(data['currencyId'] ?? data['currency_id'])),
             exchangeRate: Value(parseDoubleNullable(data['exchangeRate'] ?? data['exchange_rate'])),
             foreignAmount: Value(parseDoubleNullable(data['foreignAmount'] ?? data['foreign_amount'])),
            // Spec 087 (F2) — persist the resolved partyId so the
            // voucher appears in the right customer/supplier statement.
            partyId: Value(resolvedStPartyId),
            // Phase 5B.4 — share identity with the client row so
            // SafeTransactionSyncStrategy dedupes on the next pull.
            globalId: incomingGlobalId != null && incomingGlobalId.isNotEmpty
                ? Value(incomingGlobalId)
                : const Value.absent(),
          ),
        );
        // v185 — a receipt from a customer carries its rep + route.
        if (transactionType == 'receipt') {
          await db.stampDocumentRep('safe_transactions', stId, resolvedStPartyId);
        }
        return updated.balance;
      });

      return jsonResponse({'success': true});
        },
      );
    } catch (e) {
      debugPrint('[API] postSafeTransaction error: $e');
      return ApiErrors.fail(e, 'Failed to record safe transaction');
    }
  }

  Future<Response> postSafeTransfer(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.treasuryTransfer);
      if (perm != null) return perm;
      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'postSafeTransfer',
        tables: const {
          'safe_transactions', 'safes',
          'accounting', 'journal_entries',
        },
        body: () async {
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      final fromSafeId = parseInt(data['fromSafeId']);
      final toSafeId = parseInt(data['toSafeId']);
      final amount = parseDouble(data['amount']);
      final userId = await _resolveUserIdNullable(parseIntNullable(data['userId']),
          fallbackUsername: data['createdByUsername'] as String?);
      final description = data['description'] as String? ?? 'تحويل بين صناديق';

      // ── dedup بالـglobalId قبل أي حركة ────────────────────────────────────
      // ده كان الـendpoint الوحيد في مجموعة الخزينة بلا أي فحص تكرار — على
      // عكس postSafeTransaction وpostExpense. فطلب اتنفّذ وضاع رده كان
      // بيتعاد من طابور العميل ويتنفّذ تاني: تحويل ١٠,٠٠٠ يبقى ٢٠,٠٠٠ و٤
      // سندات بدل ٢. والهيدر x-idempotency-key مش مقروء هنا فما كانش بيحمي.
      //
      // التحويل مالوش جدول رأس، بيتسجّل كسطرين في safe_transactions، فالختم
      // على سطر الصرف (الخزنة المصدر) وهو هدف الفحص.
      final incomingGlobalId = (data['globalId'] as String?)?.trim();
      if (incomingGlobalId != null && incomingGlobalId.isNotEmpty) {
        final existing = await (db.select(db.safeTransactions)
              ..where((t) => t.globalId.equals(incomingGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          debugPrint('[API] postSafeTransfer: duplicate globalId='
              '$incomingGlobalId — skipping (voucher=${existing.voucherNumber})');
          return jsonResponse({'success': true, 'dedup': true});
        }
      }

      // Validate both safes exist before opening the transaction.
      final fromSafe = await (db.select(db.safes)
            ..where((s) => s.id.equals(fromSafeId)))
          .getSingleOrNull();
      final toSafe = await (db.select(db.safes)
            ..where((s) => s.id.equals(toSafeId)))
          .getSingleOrNull();
      if (fromSafe == null || toSafe == null) {
        return errorResponse('One or both safes not found');
      }

      // Feature 005 Phase 8 — atomic transfer: both balance updates and
      // both safe_transactions inserts run inside a single transaction
      // using SQL-level arithmetic, preventing the Lost-Update race when
      // concurrent transfers touch the same source or destination safe.
      // balanceAfter on each row is read AFTER the corresponding UPDATE
      // so it reflects the actual post-state.
      // 066 (D5-001): generateInvoiceNumber moved inside the txn so PV/RV
      // counters roll back if either UPDATE or insert fails.
      await db.transaction(() async {
        final pvNumber = await db.generateInvoiceNumber('PV');
        final rvNumber = await db.generateInvoiceNumber('RV');
        await db.customStatement(
          'UPDATE safes SET balance = balance - ? WHERE id = ?',
          [amount, fromSafeId],
        );
        final fromUpdated = await (db.select(db.safes)
              ..where((s) => s.id.equals(fromSafeId))
              ..limit(1))
            .getSingle();
        await db.into(db.safeTransactions).insert(
          SafeTransactionsCompanion.insert(
            voucherNumber: pvNumber,
            safeId: fromSafeId,
            transactionType: 'payment',
            category: 'transfer',
            amount: amount,
            balanceAfter: fromUpdated.balance,
            description: Value('$description → ${toSafe.name}'),
            userId: Value(userId),
            // هدف الـdedup فوق — سطر الصرف هو هوية التحويل.
            globalId: Value(incomingGlobalId),
          ),
        );

        await db.customStatement(
          'UPDATE safes SET balance = balance + ? WHERE id = ?',
          [amount, toSafeId],
        );
        final toUpdated = await (db.select(db.safes)
              ..where((s) => s.id.equals(toSafeId))
              ..limit(1))
            .getSingle();
        await db.into(db.safeTransactions).insert(
          SafeTransactionsCompanion.insert(
            voucherNumber: rvNumber,
            safeId: toSafeId,
            transactionType: 'receipt',
            category: 'transfer',
            amount: amount,
            balanceAfter: toUpdated.balance,
            description: Value('$description ← ${fromSafe.name}'),
            userId: Value(userId),
          ),
        );
      });

      return jsonResponse({'success': true});
        },
      );
    } catch (e) {
      debugPrint('[API] postSafeTransfer error: $e');
      return ApiErrors.fail(e, 'Failed to transfer between safes');
    }
  }

  Future<Response> postSetDefaultSafe(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.treasuryManage);
      if (perm != null) return perm;
      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'postSetDefaultSafe',
        tables: const {'safes'},
        body: () async {
          final data = json.decode(await request.readAsString())
              as Map<String, dynamic>;
          final safeId = parseInt(data['safeId']);
          // When setting a safe as default from branch, we only set it for
          // that branch. The db method handles per-branch scoping itself.
          await db.setDefaultSafe(safeId);
          return jsonResponse({'success': true});
        },
      );
    } catch (e) {
      debugPrint('[API] postSetDefaultSafe error: $e');
      return ApiErrors.fail(e, 'Failed to set default safe');
    }
  }
}
