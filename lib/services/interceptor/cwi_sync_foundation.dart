part of '../client_write_interceptor.dart';

// ignore_for_file: avoid_dynamic_calls

// ═══════════════════════════════════════════════════════════════════════════
// Sync module — SyncInterceptor interface implementations
//               Party Groups · Purchase Orders · Sales Orders
//               Quotations · Price Lists · Printers
//
// Part of the ClientWriteInterceptor library.
// All methods here back the @override stubs on ClientWriteInterceptor.
// ═══════════════════════════════════════════════════════════════════════════

class _CwiSyncFoundation {
  _CwiSyncFoundation._();

  // ── Journal Entries ───────────────────────────────────────────────────────

  static Future<void> submitJournalEntry({
    required String description,
    required DateTime date,
    required List<dynamic> lines,
    String? referenceType,
    int? referenceId,
    bool isAutoPosted = false,
    int? costCenterId,
    int? branchId,
    String? globalId,
  }) async {
    if (!SyncInterceptor.isClientMode) return;
    debugPrint('[ClientInterceptor] Routing journal entry to server');
    await ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'journal_entries',
      operation: 'insert',
      payload: {
        'description': description,
        'date': date.toIso8601String(),
        'lines': lines,
        'referenceType': referenceType,
        'referenceId': referenceId,
        'isAutoPosted': isAutoPosted,
        'costCenterId': costCenterId,
        'branchId': branchId,
        'globalId': globalId,
      },
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy.submitJournalEntry(
        description: description,
        date: date.toIso8601String(),
        lines: lines.cast<Map<String, dynamic>>(),
        referenceType: referenceType,
        referenceId: referenceId,
        isAutoPosted: isAutoPosted,
        costCenterId: costCenterId,
        branchId: branchId,
        globalId: globalId,
        idempotencyKey: reqIdemKey,
      ),
    );
  }

  // ── Landed Cost (v166) ────────────────────────────────────────────────────

  static Future<void> submitLandedCostApply(
      Map<String, dynamic> document) async {
    if (!SyncInterceptor.isClientMode) return;
    debugPrint('[ClientInterceptor] Routing landed-cost apply to server');
    await ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'landed_cost_sheets',
      operation: 'apply',
      payload: Map<String, dynamic>.from(document),
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.submitLandedCostApply(
        document,
        idempotencyKey: reqIdemKey,
      ),
    );
  }

  // ── Floor Plan (v174 / قسمُ ٧) ───────────────────────────────

  /// مخطَّطُ قاعةٍ كاملاً — **مستندٌ واحد لا سحبةٌ سحبة**.
  ///
  /// 🔴 ولو أُرسِلَت كلُّ سحبةٍ وحدَها لصار صندوقُ الصادر مئاتِ
  ///    الرسائل لجلسةِ ترتيبٍ واحدة، **وإعادةُ تشغيلِها بترتيبٍ
  ///    مختلفٍ تُنتج مخطَّطاً لم يرسمه أحد**. والمستندُ الواحدُ
  ///    صورةٌ نهائيّةٌ: إعادةُ إرسالِه تُعيد نفسَ النتيجة.
  static Future<void> submitFloorPlan(Map<String, dynamic> document) async {
    if (!SyncInterceptor.isClientMode) return;
    debugPrint('[ClientInterceptor] Routing floor-plan save to server');
    await ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'floor_plan_items',
      operation: 'save',
      payload: Map<String, dynamic>.from(document),
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.submitFloorPlan(
        document,
        idempotencyKey: reqIdemKey,
      ),
    );
  }
  // ── Attachments (v176 / §٨) ──────────────────────────────────

  /// مرفقٌ واحدٌ ببايتاتِه — **والحمولةُ تدخل صندوقَ الصادر كما هي إن
  /// انقطعت الشبكة**: فالورقةُ لا تُفقَد بانقطاع، وهذا ثمنُه المقيسُ
  /// والمقصود: صفٌّ في الطابور بحجم الملفّ مضروباً في أربعةٍ على
  /// ثلاثة (base64)، وسقفُ الخمسة ميغا هو الذي يضبطُه.
  static Future<void> submitAttachment(Map<String, dynamic> document) async {
    if (!SyncInterceptor.isClientMode) return;
    debugPrint('[ClientInterceptor] Routing attachment to server');
    await ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'attachments',
      operation: 'insert',
      payload: Map<String, dynamic>.from(document),
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.submitAttachment(
        document,
        idempotencyKey: reqIdemKey,
      ),
    );
  }

  static Future<void> submitAttachmentDelete(
      Map<String, dynamic> document) async {
    if (!SyncInterceptor.isClientMode) return;
    debugPrint('[ClientInterceptor] Routing attachment delete to server');
    await ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'attachments',
      operation: 'delete',
      payload: Map<String, dynamic>.from(document),
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.submitAttachmentDelete(
        document,
        idempotencyKey: reqIdemKey,
      ),
    );
  }
  // ── Fixed Assets (v166) ───────────────────────────────────────────────────

  static Future<void> submitFixedAssetCreate(
      Map<String, dynamic> document) async {
    if (!SyncInterceptor.isClientMode) return;
    debugPrint('[ClientInterceptor] Routing fixed-asset create to server');
    await ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'fixed_assets',
      operation: 'insert',
      payload: Map<String, dynamic>.from(document),
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.submitFixedAssetCreate(
        document,
        idempotencyKey: reqIdemKey,
      ),
    );
  }

  static Future<void> submitAssetDepreciationRun(
      Map<String, dynamic> request) async {
    if (!SyncInterceptor.isClientMode) return;
    debugPrint('[ClientInterceptor] Routing depreciation run to server');
    await ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'asset_depreciations',
      operation: 'run',
      payload: Map<String, dynamic>.from(request),
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.submitAssetDepreciationRun(
        request,
        idempotencyKey: reqIdemKey,
      ),
    );
  }

  // ── Operational Expenses (v166) ───────────────────────────────────────────

  static Future<void> submitOperationalExpense(
      Map<String, dynamic> document) async {
    if (!SyncInterceptor.isClientMode) return;
    debugPrint('[ClientInterceptor] Routing operational expense to server');
    await ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'op_expenses',
      operation: 'insert',
      payload: Map<String, dynamic>.from(document),
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.submitOperationalExpense(
        document,
        idempotencyKey: reqIdemKey,
      ),
    );
  }

  // ── Manufacturing (v166) ──────────────────────────────────────────────────

  static Future<void> submitManufacturingAction(
      Map<String, dynamic> request) async {
    if (!SyncInterceptor.isClientMode) return;
    debugPrint('[ClientInterceptor] Routing manufacturing action to server');
    await ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'manufacturing_orders',
      operation: 'action',
      payload: Map<String, dynamic>.from(request),
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.submitManufacturingAction(
        request,
        idempotencyKey: reqIdemKey,
      ),
    );
  }

  // ── Bookings (v167) ───────────────────────────────────────────────────────

  static Future<void> submitBookingDepositApplication(
      Map<String, dynamic> request) async {
    if (!SyncInterceptor.isClientMode) return;
    debugPrint('[ClientInterceptor] Routing booking deposit to server');
    await ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'bookings',
      operation: 'apply_deposit',
      payload: Map<String, dynamic>.from(request),
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.submitBookingDepositApplication(
        request,
        idempotencyKey: reqIdemKey,
      ),
    );
  }

  // ── Safe Transactions ─────────────────────────────────────────────────────

  static Future<void> submitSafeTransaction({
    required int safeId,
    required String transactionType,
    required double amount,
    required String category,
    String? description,
    int? userId,
    String? referenceType,
    int? referenceId,
    String? globalId,
    // Phase 5B.4 (Issue 7) — surface the safe + cost center identity to
    // the server so its postSafeTransaction can resolve to the correct
    // safe.linkedAccountId even when the server's safe.id has drifted
    // from the client's. Both optional for backward compatibility.
    String? safeGlobalId,
    int? costCenterId,
    // Spec 087 (F2) — preserve partyId end-to-end. The generic
    // /api/safes/transaction endpoint previously dropped it, so any
    // voucher created via this path landed on the server with
    // partyId=null and was missing from the party's statement.
    int? partyId,
    String? partyGlobalId,
  }) async {
    if (!SyncInterceptor.isClientMode) return;
    debugPrint('[ClientInterceptor] Routing safe transaction to server');
    await ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'safe_transactions',
      operation: 'insert',
      payload: {
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
        if (partyGlobalId != null && partyGlobalId.isNotEmpty)
          'partyGlobalId': partyGlobalId,
      },
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy.submitSafeTransaction(
        safeId: safeId,
        transactionType: transactionType,
        amount: amount,
        category: category,
        description: description,
        userId: userId,
        referenceType: referenceType,
        referenceId: referenceId,
        globalId: globalId,
        safeGlobalId: safeGlobalId,
        costCenterId: costCenterId,
        partyId: partyId,
        partyGlobalId: partyGlobalId,
        idempotencyKey: reqIdemKey,
      ),
    );
  }
}
