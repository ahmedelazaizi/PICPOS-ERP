part of '../client_write_interceptor.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Vouchers (E-fix ١) — سندا القبض والصرف من جهاز العميل
//
// حمولةٌ واحدةٌ إلى `/api/vouchers/<receipt|payment>` (‏`ApiVoucherHandler`)
// تحمل ما يكتبه الجهازُ الرئيسيُّ كلَّه: التحويلَ المحاسبيّ وحسابَ الخزينة،
// والمستفيدَ من الدليل، وورقةَ دفتر السندات، وحقولَ العملة. ختمُ المندوب
// والخط يحلّه الخادمُ من خط العميل (نفسُ نهج المبيعات).
//
// ⚠️ **ملفٌّ مستقلّ** لأنّ `cwi_sync_foundation.dart` و`cwi_commerce.dart`
//    على حدّ بوّابة الحجم.
//
// عقدُ الفشل يختلف عن `_tryOrQueue` عمداً: **رفضُ الخادم يُرمى** (ورقةٌ خارج
// المدى أو مكرّرة يجب أن يقرأها المستخدم) ولا يُصفّ؛ وانقطاعُ الشبكة وحدَه
// يُصفّ في صندوق الصادر (عميل) أو يُرمى `MirrorOfflineException` (مرآة).
// إعادةُ الإرسال آمنة: الخادمُ يعيد الصفَّ القائم لنفس `globalId`.
// ═══════════════════════════════════════════════════════════════════════════

/// Outbox table name for a queued voucher (see `OfflineSyncWorker`).
const kVoucherOutboxTable = 'vouchers';

class ClientVoucherInterceptor {
  ClientVoucherInterceptor._();

  /// `null` when writes are not intercepted (server / standalone): the caller
  /// writes locally. Otherwise the server's id, or `queued` when offline.
  static Future<({int? serverId, bool queued})?> submit({
    required bool isReceipt,
    required bool transfer,
    required String globalId,
    required double amount,
    required String category,
    double discount = 0,
    String? description,
    int? partyId,
    int? safeId,
    int? treasuryAccountId,
    int? beneficiaryAccountId,
    int? costCenterId,
    int? branchId,
    int? userId,
    String? paperType,
    int? bookId,
    int? bookNumber,
    int? currencyId,
    double? exchangeRate,
    double? foreignAmount,
  }) async {
    if (!SyncInterceptor.isClientMode) return null;
    final db = _CwiCoreSupport.database;
    if (db == null) throw StateError('ClientWriteInterceptor not initialized');
    final payload = await buildPayload(
      db,
      isReceipt: isReceipt,
      transfer: transfer,
      globalId: globalId,
      amount: amount,
      category: category,
      discount: discount,
      description: description,
      partyId: partyId,
      safeId: safeId,
      treasuryAccountId: treasuryAccountId,
      beneficiaryAccountId: beneficiaryAccountId,
      costCenterId: costCenterId,
      branchId: branchId,
      userId: userId,
      paperType: paperType,
      bookId: bookId,
      bookNumber: bookNumber,
      currencyId: currencyId,
      exchangeRate: exchangeRate,
      foreignAmount: foreignAmount,
    );
    await _CwiCoreSupport.enrichPayloadWithUsername(payload);
    final mirror = WriteRouter.isMirrorActive;
    if (mirror) WriteRouter.stampAdminAttribution(payload);
    final key = const Uuid().v7();
    payload['idempotency_key'] = key;
    try {
      final id = await ClientWriteInterceptor._proxy
          .submitVoucher(payload, idempotencyKey: key);
      _CwiCoreSupport._refreshAfterWrite();
      await _cacheCashReceipt(db, payload, partyId: partyId, safeId: safeId);
      return (serverId: id, queued: false);
    } catch (error) {
      if (!_CwiCoreSupport._isNetworkException(error)) rethrow;
      if (mirror) throw MirrorOfflineException.network(error.toString());
      await db.addToSyncOutbox(
        tableName: kVoucherOutboxTable,
        recordId: globalId,
        operation: 'insert',
        payload: payload,
        idempotencyKey: key,
      );
      await _cacheCashReceipt(db, payload, partyId: partyId, safeId: safeId);
      return (serverId: null, queued: true);
    }
  }

  /// The wire payload, built from the CLIENT's [db]: every local id travels
  /// with the identity the server resolves it by (globalId / chart code).
  static Future<Map<String, dynamic>> buildPayload(
    AppDatabase db, {
    required bool isReceipt,
    required bool transfer,
    required String globalId,
    required double amount,
    required String category,
    double discount = 0,
    String? description,
    int? partyId,
    int? safeId,
    int? treasuryAccountId,
    int? beneficiaryAccountId,
    int? costCenterId,
    int? branchId,
    int? userId,
    String? paperType,
    int? bookId,
    int? bookNumber,
    int? currencyId,
    double? exchangeRate,
    double? foreignAmount,
  }) async {
    Party? party;
    if (partyId != null && partyId > 0) {
      party = await (db.select(db.parties)
            ..where((p) => p.id.equals(partyId))
            ..limit(1))
          .getSingleOrNull();
    }
    Safe? safe;
    if (safeId != null) {
      safe = await (db.select(db.safes)
            ..where((s) => s.id.equals(safeId))
            ..limit(1))
          .getSingleOrNull();
    }
    String? bookGlobalId;
    if (bookId != null) {
      final row = await db.customSelect(
        'SELECT global_id FROM voucher_books WHERE id = ?',
        variables: [Variable<int>(bookId)],
      ).getSingleOrNull();
      bookGlobalId = row?.data['global_id'] as String?;
    }
    return {
      'kind': isReceipt ? 'receipt' : 'payment',
      'mode': transfer ? 'transfer' : 'standard',
      'globalId': globalId,
      'amount': amount,
      'discount': discount,
      'category': category,
      'description': description,
      'partyId': partyId,
      'partyGlobalId': ?party?.globalId,
      'partyName': ?party?.name,
      'safeId': safeId,
      'safeGlobalId': ?safe?.globalId,
      'treasuryAccount': await _account(db, treasuryAccountId),
      'beneficiaryAccount': await _account(db, beneficiaryAccountId),
      'costCenterId': costCenterId,
      'branchId': branchId,
      'userId': userId,
      'paperType': paperType,
      'bookId': bookId,
      'bookGlobalId': bookGlobalId,
      'bookNumber': bookNumber,
      'currencyId': currencyId,
      'exchangeRate': exchangeRate,
      'foreignAmount': foreignAmount,
    };
  }

  static Future<Map<String, dynamic>?> _account(AppDatabase db, int? id) async {
    if (id == null) return null;
    final a = await (db.select(db.accounts)
          ..where((x) => x.id.equals(id))
          ..limit(1))
        .getSingleOrNull();
    return {'id': id, 'code': a?.code, 'globalId': a?.globalId};
  }

  /// Spec 136 ISS-26 (#4) — نفسُ صفِّ الذاكرة الذي يكتبه `createReceipt`:
  /// سندُ قبضٍ نقديٌّ بطرفٍ يظهر في كشف العميل فوراً، والصفُّ العائدُ من
  /// الخادم يُدمَج عليه بنفس `globalId`. لا رصيدَ ولا قيدَ هنا.
  static Future<void> _cacheCashReceipt(
    AppDatabase db,
    Map<String, dynamic> payload, {
    required int? partyId,
    required int? safeId,
  }) async {
    final gid = payload['globalId'] as String;
    // الويب: قاعدة القراءة بعيدة وللقراءة فقط — لا صفَّ كاش محلياً.
    if (WriteRouter.isWebClient) return;
    if (payload['kind'] != 'receipt' ||
        payload['mode'] != 'standard' ||
        payload['paperType'] != null ||
        partyId == null ||
        safeId == null) {
      return;
    }
    try {
      final dup = await (db.select(db.safeTransactions)
            ..where((t) => t.globalId.equals(gid))
            ..limit(1))
          .getSingleOrNull();
      if (dup != null) return;
      final safe = await (db.select(db.safes)
            ..where((s) => s.id.equals(safeId))
            ..limit(1))
          .getSingleOrNull();
      final amount = (payload['amount'] as num).toDouble();
      await db.into(db.safeTransactions).insert(
            SafeTransactionsCompanion.insert(
              voucherNumber:
                  'CACHE-${gid.length >= 12 ? gid.substring(0, 12) : gid}',
              safeId: safeId,
              transactionType: 'receipt',
              category: payload['category'] as String,
              amount: amount,
              balanceAfter: (safe?.balance ?? 0) + amount,
              partyId: Value(partyId),
              description: Value(payload['description'] as String?),
              costCenterId: Value(payload['costCenterId'] as int?),
              globalId: Value(gid),
            ),
          );
    } catch (e) {
      debugPrint('[ClientInterceptor] voucher cache row failed: $e');
    }
  }
}
