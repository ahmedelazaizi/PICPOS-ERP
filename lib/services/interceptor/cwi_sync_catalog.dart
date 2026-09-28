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

class _CwiSyncCatalog {
  _CwiSyncCatalog._();

  // ── Journal Entries ───────────────────────────────────────────────────────


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
      } catch (error, stack) {
        // Dynamic companion access is optional metadata enrichment.
        unawaited(DiagnosticLogger.logError(
          'SYNC-INTERCEPTOR',
          'party-group companion field read failed',
          error,
          stack,
        ));
      }
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
}
