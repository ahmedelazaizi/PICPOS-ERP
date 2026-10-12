// ServerProxy - expenses, receipts, shifts, safes, papers and accounting writes.
part of '../server_proxy.dart';

/// Expenses, receipts, shifts, treasury, safes, commercial papers, journal entries,
/// accounts, cost centers, fixed assets and safe-transaction writes of [ServerProxy].
extension ServerProxyCashWrites on ServerProxy {
  // ═══════════════════════════════════════════════════════════════
  // Expenses & Receipts
  // ═══════════════════════════════════════════════════════════════

  Future<int?> submitExpense({
    required double amount,
    required String category,
    String? description,
    int? partyId,
    // Feature 044 — let server remap to its own party id when the
    // mirror's local autoincrement diverges (`resolvePartyId` pattern).
    String? partyGlobalId,
     int? currencyId,
     double? exchangeRate,
     double? foreignAmount,
    String? partyName,
    int? safeId,
    int? userId,
    int? costCenterId,
    int? branchId,
    String? globalId, // NEW: UUID-First sync
    // Spec 081 — must reach the server so it can skip the cash JE and the
    // safe transaction for cheque payments (commercial papers owns both).
    // Pre-081 the field was always null on the wire, so the server posted
    // a phantom Dr AP / Cr Cash JE on top of the correct CP entry.
    String? paperType,
    String? idempotencyKey,
  }) async {
    final result = await post('/api/expenses', {
      'amount': amount,
      'category': category,
      'description': description,
      'partyId': partyId,
      if (partyGlobalId != null && partyGlobalId.isNotEmpty)
        'partyGlobalId': partyGlobalId,
      if (partyName != null && partyName.isNotEmpty) 'partyName': partyName,
      'safeId': safeId,
      'userId': userId,
      'costCenterId': costCenterId,
      'branchId': branchId,
      'globalId': globalId,
      if (paperType != null && paperType.isNotEmpty) 'paperType': paperType,
    }, idempotencyKey: idempotencyKey);
    return result['serverId'] as int?;
  }

  /// FIX 3.4: idempotencyKey added so outbox replay prevents double-deletes
  Future<void> deleteExpense(int id, {String? idempotencyKey}) async {
    await delete('/api/expenses/$id', idempotencyKey: idempotencyKey);
  }

  Future<int?> submitReceipt({
    required double amount,
    required String category,
    String? description,
    int? partyId,
    // Feature 044 — `resolvePartyId` on server side maps to its own id.
    String? partyGlobalId,
     int? currencyId,
     double? exchangeRate,
     double? foreignAmount,
    String? partyName,
    int? safeId,
    String? safeGlobalId, // Issue 12: lets server resolve to its own safe id
    int? userId,
    int? branchId,
    int? costCenterId,
    // Issue 3 (Feature 020): operator's CoA account pick — overrides the
    // category-default credit leg on the server's JE so the receipt's JE
    // matches the one the client posted locally.
    int? linkedAccountId,
    String? globalId, // UUID-First sync
    // Spec 133 — must reach the server so it can skip the cash JE and the
    // safe transaction for cheque receipts (commercial papers owns both).
    // Pre-133 the field was always null on the wire, so the server posted
    // a phantom Dr Safe / Cr Customer JE on top of the correct CP entry
    // → customer ledger showed two credits per cheque. Symmetric with
    // submitExpense's Spec 081 fix.
    String? paperType,
    String? idempotencyKey,
  }) async {
    final result = await post('/api/receipts', {
      'amount': amount,
      'category': category,
      'description': description,
      'partyId': partyId,
      if (partyGlobalId != null && partyGlobalId.isNotEmpty)
        'partyGlobalId': partyGlobalId,
      if (partyName != null && partyName.isNotEmpty) 'partyName': partyName,
      'safeId': safeId,
      'safeGlobalId': safeGlobalId,
      'userId': userId,
      'branchId': branchId,
      'costCenterId': costCenterId,
      'linkedAccountId': ?linkedAccountId,
      'globalId': globalId,
      if (paperType != null && paperType.isNotEmpty) 'paperType': paperType,
    }, idempotencyKey: idempotencyKey);
    return result['serverId'] as int?;
  }

  /// E-fix ١ — سندُ قبضٍ/صرفٍ كاملٌ من جهاز العميل (`/api/vouchers/<kind>`):
  /// تحويلٌ محاسبيّ، مستفيدٌ من الدليل، ورقةُ دفتر. رفضُ الورقة (`409`)
  /// يعود [VoucherBookException] بنصّه ليقرأه المستخدم لا «خطأ خادم».
  Future<int?> submitVoucher(Map<String, dynamic> data,
      {String? idempotencyKey}) async {
    final kind = data['kind'] == 'payment' ? 'payment' : 'receipt';
    try {
      final result = await post('/api/vouchers/$kind', data,
          idempotencyKey: idempotencyKey);
      return result['serverId'] as int?;
    } on Exception catch (e) {
      throw ServerProxy.voucherBookRejectionOf(e) ?? e;
    }
  }

  Future<void> submitSetDefaultSafe({required int safeId, String? idempotencyKey}) async {
    await post('/api/safes/set-default', {'safeId': safeId}, idempotencyKey: idempotencyKey);
  }

  // ═══════════════════════════════════════════════════════════════
  // Shifts
  // ═══════════════════════════════════════════════════════════════

  Future<int?> openShift(int userId, double openingBalance,
      {int? branchId, String? globalId, String? idempotencyKey}) async {
    final result = await post('/api/shifts/open', {
      'userId': userId,
      'openingBalance': openingBalance,
      // Spec 008 / FR-006: thread branchId so the server records which
      // branch the shift was opened on (multi-branch user support).
      'branchId': ?branchId,
      // Constitution R9: thread the local shift's globalId so the server
      // dedups by it and the matching close can be remapped without an
      // outbox-only id mapping.
      if (globalId != null && globalId.isNotEmpty) 'globalId': globalId,
    }, idempotencyKey: idempotencyKey);
    return result['shiftId'] as int?;
  }

  Future<void> closeShift(
    int shiftId,
    double actualCash, {
    String? notes,
    String? idempotencyKey,
    // Phase 5A.7 (Issue 2) — backfill fields. When the shift was opened
    // offline and the close arrives at the server before /api/shifts/open
    // has drained, these let the server reconstruct the shift in place
    // instead of pseudo-acknowledging the close.
    int? userId,
    double? openingBalance,
    DateTime? openedAt,
    // Constitution R9: shiftGlobalId lets the server resolve the local
    // shiftId (which may not exist on the server side because the open's
    // server-assigned id was never mapped back) → fixes the recurring
    // "Shift not found" 500 / DEAD-LETTER in production logs (2026-05-12).
    String? shiftGlobalId,
  }) async {
    await post('/api/shifts/close', {
      'shiftId': shiftId,
      'actualCash': actualCash,
      'notes': notes,
      'userId': ?userId,
      'openingBalance': ?openingBalance,
      if (openedAt != null) 'openedAt': openedAt.toIso8601String(),
      if (shiftGlobalId != null && shiftGlobalId.isNotEmpty)
        'shiftGlobalId': shiftGlobalId,
    }, idempotencyKey: idempotencyKey);
  }

  // ═══════════════════════════════════════════════════════════════
  // Treasury
  // ═══════════════════════════════════════════════════════════════

  Future<void> closeSafe(int safeId, {int? userId, double? cashAmount, double? bankAmount, String? notes, String? closeEventGid, String? idempotencyKey}) async {
    await post('/api/safes/close', {
      'safeId': safeId,
      'userId': userId,
      'cashAmount': ?cashAmount,
      'bankAmount': ?bankAmount,
      'notes': ?notes,
      if (closeEventGid != null && closeEventGid.isNotEmpty) 'closeEventGid': closeEventGid,
    }, idempotencyKey: idempotencyKey);
  }

  // ═══════════════════════════════════════════════════════════════
  // Cost Centers (Feature 006 / MM.C)
  // ═══════════════════════════════════════════════════════════════

  Future<int?> createCostCenter(
    Map<String, dynamic> data, {
    String? idempotencyKey,
  }) async {
    final result = await post('/api/cost_centers', data, idempotencyKey: idempotencyKey);
    return result['id'] as int?;
  }

  Future<void> updateCostCenter(int id, Map<String, dynamic> data, {String? idempotencyKey}) async {
    await put('/api/cost_centers/$id', data, idempotencyKey: idempotencyKey);
  }

  Future<void> deleteCostCenter(int id, {String? idempotencyKey}) async {
    await delete('/api/cost_centers/$id', idempotencyKey: idempotencyKey);
  }

  // ═══════════════════════════════════════════════════════════════
  // Accounts (CoA) + Account Mappings (Feature 006 / MM.C)
  // ═══════════════════════════════════════════════════════════════

  Future<int?> createAccount(
    Map<String, dynamic> data, {
    String? idempotencyKey,
  }) async {
    final result = await post('/api/accounts', data, idempotencyKey: idempotencyKey);
    return result['id'] as int?;
  }

  Future<void> updateAccount(int id, Map<String, dynamic> data, {String? idempotencyKey}) async {
    await put('/api/accounts/$id', data, idempotencyKey: idempotencyKey);
  }

  Future<void> deleteAccount(int id, {String? idempotencyKey}) async {
    await delete('/api/accounts/$id', idempotencyKey: idempotencyKey);
  }

  Future<void> setAccountMapping(
    Map<String, dynamic> data, {
    String? idempotencyKey,
  }) async {
    await post('/api/account-mappings', data, idempotencyKey: idempotencyKey);
  }

  Future<void> deleteAccountMapping({
    required String purpose,
    int? costCenterId,
    String? idempotencyKey,
  }) async {
    final cc = costCenterId != null ? '&cost_center_id=$costCenterId' : '';
    final url = Uri.parse(
        '$_baseUrl/api/account-mappings?purpose=${Uri.encodeComponent(purpose)}$cc');
    final headers = Map<String, String>.from(_authHeaders);
    if (idempotencyKey != null) {
      headers['X-Idempotency-Key'] = idempotencyKey;
    }
    final response = await TlsTrust.httpClient()
        .delete(url, headers: headers)
        .timeout(ServerProxy.requestTimeout);
    if (!_isSuccessStatusCode(response.statusCode)) {
      throw Exception(
          'Server error (${response.statusCode}): ${response.body}');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Safes (Feature 006 / MM.C — mirror-mode admin CRUD)
  //
  // Operational endpoints (close / transaction / transfer / set-default)
  // already exist above; these handle structural CRUD only.
  // ═══════════════════════════════════════════════════════════════

  Future<int?> createSafe(
    Map<String, dynamic> data, {
    String? idempotencyKey,
  }) async {
    final result = await post('/api/safes', data, idempotencyKey: idempotencyKey);
    return result['id'] as int?;
  }

  Future<void> updateSafe(int id, Map<String, dynamic> data, {String? idempotencyKey}) async {
    await put('/api/safes/$id', data, idempotencyKey: idempotencyKey);
  }

  Future<void> deleteSafe(int id, {String? idempotencyKey}) async {
    await delete('/api/safes/$id', idempotencyKey: idempotencyKey);
  }

  // ═══════════════════════════════════════════════════════════════
  // Commercial Papers
  // ═══════════════════════════════════════════════════════════════

  Future<int?> createCommercialPaper(Map<String, dynamic> data, {String? idempotencyKey}) async {
    final result = await post('/api/commercial-papers', data, idempotencyKey: idempotencyKey);
    return result['serverId'] as int?;
  }

  Future<void> updateCommercialPaperStatus(
    int id, {
    required String status,
    int? changedBy,
    String? changedByUsername,
    String? notes,
    int? endorsedToPartyId,
    String? globalId,
    // Feature 048 (v130) — caller-chosen contra leg for the auto-posted
    // JE. The server resolves the integer id via the globalId variant
    // when chart-of-accounts auto-increments diverge between client
    // and server (same remap pattern as partyGlobalId).
    int? counterAccountId,
    String? counterAccountGlobalId,
  }) async {
    // Feature 014 / Issue 3 — the path id is the LOCAL id and does
    // NOT match the server's. The server resolves by `globalId` when
    // present; the path `id` becomes a hint only.
    //
    // Feature 042 (Bug 5) — also forward `changedByUsername` so the
    // server can remap `changedBy` via `_resolveUserIdNullable`
    // (paper_status_history.changed_by NOT NULL FK to users(id) was
    // failing on every mirror status-change before this).
    await put('/api/commercial-papers/$id/status', {
      'status': status,
      'changedBy': changedBy,
      if (changedByUsername != null && changedByUsername.isNotEmpty)
        'changedByUsername': changedByUsername,
      'notes': notes,
      'endorsedToPartyId': endorsedToPartyId,
      if (globalId != null && globalId.isNotEmpty) 'globalId': globalId,
      'counterAccountId': ?counterAccountId,
      if (counterAccountGlobalId != null && counterAccountGlobalId.isNotEmpty)
        'counterAccountGlobalId': counterAccountGlobalId,
    });
  }

  Future<void> renewCommercialPaper(
    int id, {
    required String newDueDate,
    int? changedBy,
    String? notes,
  }) async {
    await post('/api/commercial-papers/$id/renew', {
      'newDueDate': newDueDate,
      'changedBy': changedBy,
      'notes': notes,
    });
  }

  Future<void> partialCollectPaper(
    int id, {
    required double amount,
    int? changedBy,
    String? notes,
  }) async {
    await post('/api/commercial-papers/$id/partial-collect', {
      'amount': amount,
      'changedBy': changedBy,
      'notes': notes,
    });
  }

  Future<void> depositPaperForCollection(
    int id, {
    required int bankSafeId,
    int? changedBy,
    String? notes,
  }) async {
    await post('/api/commercial-papers/$id/deposit', {
      'bankSafeId': bankSafeId,
      'changedBy': changedBy,
      'notes': notes,
    });
  }

  Future<void> reissuePaper(
    int id, {
    required int newPartyId,
    int? changedBy,
    String? notes,
  }) async {
    await post('/api/commercial-papers/$id/reissue', {
      'newPartyId': newPartyId,
      'changedBy': changedBy,
      'notes': notes,
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // Journal Entries (Client → Server)
  // ═══════════════════════════════════════════════════════════════

  Future<void> submitJournalEntry({
    required String description,
    required String date,
    required List<Map<String, dynamic>> lines,
    String? referenceType,
    int? referenceId,
    bool isAutoPosted = true,
    int? costCenterId,
    int? branchId,
    String? globalId, // NEW: UUID-First sync
    String? idempotencyKey,
  }) async {
    await post('/api/journals', {
      'description': description,
      'date': date,
      'lines': lines,
      'referenceType': referenceType,
      'referenceId': referenceId,
      'isAutoPosted': isAutoPosted,
      'costCenterId': costCenterId,
      'branchId': branchId,
      'globalId': globalId,
    }, idempotencyKey: idempotencyKey);
  }

  // ═══════════════════════════════════════════════════════════════
  // Fixed Assets — اقتناءٌ وإهلاك (Client → Server) · v166
  // ═══════════════════════════════════════════════════════════════

  Future<void> submitFixedAssetCreate(
    Map<String, dynamic> document, {
    String? idempotencyKey,
  }) async {
    await post('/api/fixed-assets', document, idempotencyKey: idempotencyKey);
  }

  /// طلبُ ترحيلِ إهلاكِ شهرٍ — التاريخُ وحدَه، لا قائمةُ الأصول.
  Future<void> submitAssetDepreciationRun(
    Map<String, dynamic> request, {
    String? idempotencyKey,
  }) async {
    await post('/api/fixed-assets/depreciation/run', request,
        idempotencyKey: idempotencyKey);
  }

  // ═══════════════════════════════════════════════════════════════
  // Operational Expenses (Client → Server) · v166
  // ═══════════════════════════════════════════════════════════════

  Future<void> submitOperationalExpense(
    Map<String, dynamic> document, {
    String? idempotencyKey,
  }) async {
    await post('/api/op-expenses', document, idempotencyKey: idempotencyKey);
  }

  // ═══════════════════════════════════════════════════════════════
  // Safe Transactions (Client → Server)
  // ═══════════════════════════════════════════════════════════════

  Future<void> submitSafeTransaction({
    required int safeId,
    required String transactionType,
    required double amount,
    String category = 'general',
    String? description,
    int? userId,
    String? referenceType,
    int? referenceId,
    String? globalId, // NEW: UUID-First sync
    String? idempotencyKey,
    // Phase 5B.4 (Issue 7) — server uses safeGlobalId to resolve to its
    // own safe.id (and therefore the right linked GL account) instead of
    // trusting the client's local safe.id. costCenterId likewise lets the
    // server stamp the JE with the dialog-selected cost center, not its
    // default. Mirrors the postReceipt flow shipped in commit 0d93217.
    String? safeGlobalId,
    int? costCenterId,
    // Spec 087 (F2) — thread the partyId end-to-end. The server's
    // postSafeTransaction handler resolves partyGlobalId → server's
    // partyId so the row lands with the correct party link and the
    // voucher appears in customer/supplier statements.
    int? partyId,
    String? partyGlobalId,
     int? currencyId,
     double? exchangeRate,
     double? foreignAmount,
  }) async {
    // PHASE-3 FIX: Treasury operations use retry logic for network resilience
    await _postWithRetry('/api/safes/transaction', {
      'safeId': safeId,
      'transactionType': transactionType,
      'amount': amount,
      'category': category,
      'description': description,
      'userId': userId,
      'referenceType': referenceType,
      'referenceId': referenceId,
      'globalId': globalId,
      if (safeGlobalId != null && safeGlobalId.isNotEmpty)
        'safeGlobalId': safeGlobalId,
      'costCenterId': ?costCenterId,
      'partyId': ?partyId,
       'currencyId': ?currencyId,
       'exchangeRate': ?exchangeRate,
       'foreignAmount': ?foreignAmount,
      if (partyGlobalId != null && partyGlobalId.isNotEmpty)
        'partyGlobalId': partyGlobalId,
    }, idempotencyKey: idempotencyKey);
  }

  Future<void> submitSafeTransfer({
    required int fromSafeId,
    required int toSafeId,
    required double amount,
    int? userId,
    String? description,
    String? globalId,
    String? idempotencyKey,
  }) async {
    await post('/api/safes/transfer', {
      'fromSafeId': fromSafeId,
      'toSafeId': toSafeId,
      'amount': amount,
      'userId': userId,
      'description': description,
      // `/api/safes/transfer` مش بيقرا هيدر الـidempotency، فالـglobalId هو
      // مسار الـdedup الوحيد — زي `postSafeTransaction` و`postExpense`.
      'globalId': globalId,
    }, idempotencyKey: idempotencyKey);
  }
}
