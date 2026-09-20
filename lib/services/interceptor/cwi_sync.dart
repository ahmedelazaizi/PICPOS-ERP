// ignore_for_file: avoid_dynamic_calls
part of '../client_write_interceptor.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Sync module — SyncInterceptor interface implementations
//               Party Groups · Purchase Orders · Sales Orders
//               Quotations · Price Lists · Printers
//
// Part of the ClientWriteInterceptor library.
// All methods here back the @override stubs on ClientWriteInterceptor.
// ═══════════════════════════════════════════════════════════════════════════

class _CwiSync {
  _CwiSync._();

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

  // ── Units ─────────────────────────────────────────────────────────────────

  static Future<int?> createUnit(UnitsCompanion unit) async {
    if (!SyncInterceptor.isClientMode) return null;
    debugPrint('[ClientInterceptor] Routing unit create to server');
    final unitGlobalId = unit.globalId.present ? unit.globalId.value : null;
    final data = {
      'name': unit.name.value,
      'symbol': unit.symbol.value,
      'conversionFactor': unit.conversionFactor.value,
      if (unitGlobalId != null && unitGlobalId.isNotEmpty) 'globalId': unitGlobalId,
    };
    return ClientWriteInterceptor._tryOrQueue(
      tableName: 'units',
      operation: 'insert',
      payload: data,
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.submitUnit(data, idempotencyKey: reqIdemKey),
    );
  }

  static Future<bool> updateUnit(int id, Map<String, dynamic> data) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing unit update to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'units',
      operation: 'update',
      payload: {'id': id, ...data},
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.updateUnit(id, data, idempotencyKey: reqIdemKey),
    );
  }

  static Future<bool> deleteUnit(int id) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing unit delete to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'units',
      operation: 'delete',
      payload: {'id': id},
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.deleteUnit(id, idempotencyKey: reqIdemKey),
    );
  }

  // ── Product Units ─────────────────────────────────────────────────────────

  static Future<int?> createProductUnit(ProductUnitsCompanion productUnit) async {
    if (!SyncInterceptor.isClientMode) return null;
    debugPrint('[ClientInterceptor] Routing product unit mapping to server');
    T? readV<T>(Value<T> v, [T? fallback]) => v.present ? v.value : fallback;
    final data = {
      'productId': readV(productUnit.productId),
      'unitName': readV(productUnit.unitName),
      'barcode': readV(productUnit.barcode),
      'quantityInBase': readV(productUnit.quantityInBase),
      'salePrice': readV(productUnit.salePrice),
      'costPrice': readV(productUnit.costPrice),
      'isBaseUnit': readV<bool>(productUnit.isBaseUnit, false),
      'isDefaultSale': readV<bool>(productUnit.isDefaultSale, false),
      'isDefaultPurchase': readV<bool>(productUnit.isDefaultPurchase, false),
      'sortOrder': readV(productUnit.sortOrder),
    };
    return ClientWriteInterceptor._tryOrQueue(
      tableName: 'product_units',
      operation: 'insert',
      payload: data,
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy
          .submitProductUnitMapping(data, idempotencyKey: reqIdemKey),
    );
  }

  static Future<bool> updateProductUnit(int id, Map<String, dynamic> data) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing product unit mapping update to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'product_units',
      operation: 'update',
      payload: {'id': id, ...data},
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy
          .updateProductUnitMapping(id, data, idempotencyKey: reqIdemKey),
    );
  }

  static Future<bool> deleteProductUnit(int id) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing product unit mapping delete to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'product_units',
      operation: 'delete',
      payload: {'id': id},
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.deleteProductUnitMapping(id, idempotencyKey: reqIdemKey),
    );
  }

  // ── Product Barcodes ──────────────────────────────────────────────────────

  static Future<int?> createProductBarcode(ProductBarcodesCompanion barcode) async {
    if (!SyncInterceptor.isClientMode) return null;
    debugPrint('[ClientInterceptor] Routing product barcode create to server');
    T? readV<T>(Value<T> v, [T? fallback]) => v.present ? v.value : fallback;
    final data = {
      'productId': readV(barcode.productId),
      'barcode': readV(barcode.barcode),
      'isPrimary': readV<bool>(barcode.isPrimary, false),
    };
    return ClientWriteInterceptor._tryOrQueue(
      tableName: 'product_barcodes',
      operation: 'insert',
      payload: data,
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy
          .submitProductBarcode(data, idempotencyKey: reqIdemKey),
    );
  }

  static Future<bool> deleteProductBarcode(int id) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing product barcode delete to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'product_barcodes',
      operation: 'delete',
      payload: {'id': id},
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.deleteProductBarcode(id, idempotencyKey: reqIdemKey),
    );
  }

  // ── Users & Roles ─────────────────────────────────────────────────────────

  static Future<int?> createUser({
    required String username,
    required String password,
    required String displayName,
    int? roleId,
    List<int> branchIds = const [],
    String? globalId,
    String? cardCode,
  }) async {
    if (!SyncInterceptor.isClientMode) return null;
    debugPrint('[ClientInterceptor] Routing user create to server');
    final effectiveGlobalId =
        (globalId != null && globalId.isNotEmpty) ? globalId : const Uuid().v7();
    return ClientWriteInterceptor._tryOrQueue(
      tableName: 'users',
      operation: 'insert',
      payload: {
        'username': username,
        'password': password,
        'displayName': displayName,
        'roleId': roleId,
        'branchIds': branchIds,
        'globalId': effectiveGlobalId,
        if (cardCode != null && cardCode.isNotEmpty) 'cardCode': cardCode,
      },
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy.createUser(
        username: username,
        password: password,
        displayName: displayName,
        roleId: roleId,
        branchIds: branchIds,
        globalId: effectiveGlobalId,
        cardCode: cardCode,
      ),
    );
  }

  static Future<int?> createRole({
    required String name,
    String? description,
    bool isSystemRole = false,
  }) async {
    if (!SyncInterceptor.isClientMode) return null;
    debugPrint('[ClientInterceptor] Routing role create to server');
    return ClientWriteInterceptor._tryOrQueue(
      tableName: 'roles',
      operation: 'insert',
      payload: {
        'name': name,
        'description': description,
        'isSystemRole': isSystemRole,
      },
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy.createRole(
        name: name,
        description: description,
        isSystemRole: isSystemRole,
      ),
    );
  }

  static Future<bool> setRolePermissions(int roleId, List<String> permissionCodes,
      {String? roleGlobalId, String? roleName}) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing setRolePermissions to server '
        '(role $roleId, ${permissionCodes.length} perms)');
    // Offline-safe: when the server is unreachable, the request is queued in
    // sync_outbox with an idempotency key and replayed on reconnect. Without
    // this, a transient network blip during a permission save would silently
    // discard the change (the previous code swallowed the exception, and the
    // local DB write would later be overwritten by the server's stale state
    // on the next role_permissions broadcast).
    //
    // Spec 136 ISS-15: thread the role's globalId + name so the server can
    // resolve (or placeholder-create) the role before the FK-bound permission
    // write. Persisted in the queued payload so an offline replay carries it too.
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'role_permissions',
      operation: 'set',
      payload: {
        'roleId': roleId,
        'permissionCodes': permissionCodes,
        'roleGlobalId': ?roleGlobalId,
        'roleName': ?roleName,
      },
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.setRolePermissions(
            roleId,
            permissionCodes,
            idempotencyKey: reqIdemKey,
            roleGlobalId: roleGlobalId,
            roleName: roleName,
          ),
    );
  }

  // ── Regions ───────────────────────────────────────────────────────────────

  static Future<int?> createRegion({
    required String name,
    String? address,
    String? phone,
    int? costCenterId,
  }) async {
    if (!SyncInterceptor.isClientMode) return null;
    debugPrint('[ClientInterceptor] Routing region create to server');
    return ClientWriteInterceptor._tryOrQueue(
      tableName: 'regions',
      operation: 'insert',
      payload: {
        'name': name,
        'address': address,
        'phone': phone,
        'costCenterId': costCenterId,
      },
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy.createRegion(
        name: name,
        address: address,
        phone: phone,
        costCenterId: costCenterId,
      ),
    );
  }

  static Future<bool> updateRegion({
    required int id,
    required String name,
    String? address,
    String? phone,
    int? costCenterId,
  }) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing region update to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'regions',
      operation: 'update',
      payload: {
        'id': id,
        'name': name,
        'address': address,
        'phone': phone,
        'costCenterId': costCenterId,
      },
      serverCall: (reqIdemKey) async {
        await ClientWriteInterceptor._proxy.updateRegion(
          id: id,
          name: name,
          address: address,
          phone: phone,
          costCenterId: costCenterId,
        );
      },
    );
  }

  // ── Party Groups ──────────────────────────────────────────────────────────

  static Future<int?> createPartyGroup(dynamic companion) async {
    if (!SyncInterceptor.isClientMode) return null;
    debugPrint('[ClientInterceptor] Routing party group create to server');
    T? readV<T>(dynamic v, [T? fallback]) {
      try {
        if (v != null && v.present == true) return v.value as T?;
      } catch (_) {}
      return fallback;
    }
    final gid = readV<String>(companion.globalId) ?? '';
    final data = {
      'name': readV<String>(companion.name) ?? '',
      'type': readV<String>(companion.type) ?? 'both',
      'description': readV<String>(companion.description),
      'defaultDiscount': readV<double>(companion.defaultDiscount) ?? 0.0,
      'defaultPaymentTerms': readV<String>(companion.defaultPaymentTerms),
      'priceLevel': readV<String>(companion.priceLevel),
      'notes': readV<String>(companion.notes),
      'parentGroupId': readV<int>(companion.parentGroupId),
      if (gid.isNotEmpty) 'globalId': gid,
    };
    return ClientWriteInterceptor._tryOrQueue(
      tableName: 'party_groups',
      operation: 'insert',
      payload: data,
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.createPartyGroup(data, idempotencyKey: reqIdemKey),
    );
  }

  static Future<bool> updatePartyGroup(int id, Map<String, dynamic> data) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing party group update to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'party_groups',
      operation: 'update',
      payload: {'id': id, ...data},
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.updatePartyGroup(id, data, idempotencyKey: reqIdemKey),
    );
  }

  static Future<bool> deletePartyGroup(int id) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing party group delete to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'party_groups',
      operation: 'delete',
      payload: {'id': id},
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.deletePartyGroup(id, idempotencyKey: reqIdemKey),
    );
  }

  // ── Purchase Orders ───────────────────────────────────────────────────────

  static Future<int?> createPurchaseOrder(
    Map<String, dynamic> data,
    List<Map<String, dynamic>> items,
  ) async {
    if (!SyncInterceptor.isClientMode) return null;
    debugPrint('[ClientInterceptor] Routing purchase order create to server');
    final payload = {...data, 'items': items};
    await ClientWriteInterceptor._enrichItemsWithProductGlobalId(payload);
    return ClientWriteInterceptor._tryOrQueue(
      tableName: 'purchase_orders',
      operation: 'insert',
      payload: payload,
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.createPurchaseOrder(payload, idempotencyKey: reqIdemKey),
    );
  }

  static Future<bool> updatePurchaseOrderStatus(int id, String status) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing purchase order status update to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'purchase_orders',
      operation: 'update',
      payload: {'id': id, 'status': status},
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy
          .updatePurchaseOrderStatus(id, status, idempotencyKey: reqIdemKey),
    );
  }

  static Future<bool> deletePurchaseOrder(int id) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing purchase order delete to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'purchase_orders',
      operation: 'delete',
      payload: {'id': id},
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.deletePurchaseOrder(id, idempotencyKey: reqIdemKey),
    );
  }

  // ── Sales Orders ──────────────────────────────────────────────────────────

  static Future<int?> createSalesOrder(
    Map<String, dynamic> data,
    List<Map<String, dynamic>> items,
  ) async {
    if (!SyncInterceptor.isClientMode) return null;
    debugPrint('[ClientInterceptor] Routing sales order create to server');
    final payload = {...data, 'items': items};
    await ClientWriteInterceptor._enrichItemsWithProductGlobalId(payload);
    return ClientWriteInterceptor._tryOrQueue(
      tableName: 'sales_orders',
      operation: 'insert',
      payload: payload,
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.createSalesOrder(payload, idempotencyKey: reqIdemKey),
    );
  }

  static Future<bool> updateSalesOrderStatus(int id, String status) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing sales order status update to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'sales_orders',
      operation: 'update',
      payload: {'id': id, 'status': status},
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy
          .updateSalesOrderStatus(id, status, idempotencyKey: reqIdemKey),
    );
  }

  static Future<bool> deleteSalesOrder(int id) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing sales order delete to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'sales_orders',
      operation: 'delete',
      payload: {'id': id},
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.deleteSalesOrder(id, idempotencyKey: reqIdemKey),
    );
  }

  // ── Quotations ────────────────────────────────────────────────────────────

  static Future<int?> createQuotation(
    Map<String, dynamic> data,
    List<Map<String, dynamic>> items,
  ) async {
    if (!SyncInterceptor.isClientMode) return null;
    debugPrint('[ClientInterceptor] Routing quotation create to server');
    final payload = {...data, 'items': items};
    if (!payload.containsKey('customerGlobalId')) {
      final cid = payload['customerId'];
      final customerGlobalId = await ClientWriteInterceptor._lookupPartyGlobalId(
        cid is int ? cid : (cid is num ? cid.toInt() : null),
      );
      if (customerGlobalId != null) payload['customerGlobalId'] = customerGlobalId;
    }
    await ClientWriteInterceptor._enrichItemsWithProductGlobalId(payload);
    return ClientWriteInterceptor._tryOrQueue(
      tableName: 'quotations',
      operation: 'insert',
      payload: payload,
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.createQuotation(payload, idempotencyKey: reqIdemKey),
    );
  }

  static Future<bool> updateQuotationStatus(
    int id,
    String status, {
    int? convertedInvoiceId,
  }) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing quotation status update to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'quotations',
      operation: 'update',
      payload: {
        'id': id,
        'status': status,
        'convertedToInvoiceId': ?convertedInvoiceId,
      },
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy
          .updateQuotationStatus(id, status, convertedInvoiceId: convertedInvoiceId),
    );
  }

  static Future<bool> updateQuotation(
    int id,
    Map<String, dynamic> data,
    List<Map<String, dynamic>> items,
  ) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing quotation full update to server');
    final payload = {...data, 'id': id, 'items': items};
    if (!payload.containsKey('customerGlobalId')) {
      final cid = payload['customerId'];
      final customerGlobalId = await ClientWriteInterceptor._lookupPartyGlobalId(
        cid is int ? cid : (cid is num ? cid.toInt() : null),
      );
      if (customerGlobalId != null) payload['customerGlobalId'] = customerGlobalId;
    }
    await ClientWriteInterceptor._enrichItemsWithProductGlobalId(payload);
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'quotations',
      operation: 'update',
      payload: payload,
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.updateQuotation(id, payload, idempotencyKey: reqIdemKey),
    );
  }

  static Future<bool> deleteQuotation(int id) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing quotation delete to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'quotations',
      operation: 'delete',
      payload: {'id': id},
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.deleteQuotation(id, idempotencyKey: reqIdemKey),
    );
  }

  // ── Price Lists ───────────────────────────────────────────────────────────

  static Future<int?> createPriceList(Map<String, dynamic> data) async {
    if (!SyncInterceptor.isClientMode) return null;
    debugPrint('[ClientInterceptor] Routing price list create to server');
    return ClientWriteInterceptor._tryOrQueue(
      tableName: 'price_lists',
      operation: 'insert',
      payload: data,
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.createPriceList(data, idempotencyKey: reqIdemKey),
    );
  }

  static Future<bool> updatePriceList(int id, Map<String, dynamic> data) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing price list update to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'price_lists',
      operation: 'update',
      payload: {'id': id, ...data},
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.updatePriceList(id, data, idempotencyKey: reqIdemKey),
    );
  }

  static Future<bool> setPriceListItem(Map<String, dynamic> data) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing price list item upsert to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'price_list_items',
      operation: 'upsert',
      payload: data,
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.setPriceListItem(data, idempotencyKey: reqIdemKey),
    );
  }

  // ── Activity Logs ─────────────────────────────────────────────────────────

  /// Push a single activity log entry to the server.
  /// Non-blocking: queued in outbox when server is unreachable.
  static Future<bool> pushActivityLog(Map<String, dynamic> data) async {
    if (!SyncInterceptor.isClientMode) return false;
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'activity_logs',
      operation: 'insert',
      payload: data,
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.pushActivityLog(data, idempotencyKey: reqIdemKey),
    );
  }

  // ── Printers ──────────────────────────────────────────────────────────────

  static Future<int?> createPrinter(Map<String, dynamic> data) async {
    if (!SyncInterceptor.isClientMode) return null;
    debugPrint('[ClientInterceptor] Routing printer create to server');
    return ClientWriteInterceptor._tryOrQueue(
      tableName: 'printers',
      operation: 'insert',
      payload: data,
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.createPrinter(data, idempotencyKey: reqIdemKey),
    );
  }

  static Future<bool> updatePrinter(int id, Map<String, dynamic> data) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing printer update to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'printers',
      operation: 'update',
      payload: {'id': id, ...data},
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.updatePrinter(id, data, idempotencyKey: reqIdemKey),
    );
  }

  static Future<bool> deletePrinter(int id) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing printer delete to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'printers',
      operation: 'delete',
      payload: {'id': id},
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.deletePrinter(id, idempotencyKey: reqIdemKey),
    );
  }
}