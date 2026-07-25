part of '../client_write_interceptor.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Catalog module — Products · Purchases · Shifts · Settings · Categories
//                  Users · Warehouses
//
// Part of the ClientWriteInterceptor library.
// ═══════════════════════════════════════════════════════════════════════════

class _CwiCatalog {
  _CwiCatalog._();

  // ── Products ──────────────────────────────────────────────────────────────

  static Future<int?> createProduct({
    required String code,
    required String name,
    required double salePrice,
    required double costPrice,
    int? categoryId,
    int? supplierId,
    double currentStock = 0,
    String? barcode,
    double minStock = 0,
    double taxRate = 0,
    bool isSoldByWeight = false,
    bool allowNegativeSale = false,
    bool trackExpiry = false,
    int defaultShelfDays = 90,
    int alertDaysBefore = 30,
    double? pricePerUnit,
    double wholesalePrice = 0,
    double priceTalabat = 0,
    double priceCareem = 0,
    double priceAshyae = 0,
    String? scaleType,
    int? scalePluNumber,
    String productType = 'product',
    int? warehouseId,
    String? globalId,
    // P5: ship child rows in the same payload so the server creates them
    // atomically — there is no /api/product-units endpoint and creating them
    // separately produced "naked" products on the server.
    List<Map<String, dynamic>>? units,
    List<Map<String, dynamic>>? barcodes,
  }) async {
    if (!SyncInterceptor.isClientMode) return null;
    debugPrint('[ClientInterceptor] Routing product create to server');

    final db = ClientWriteInterceptor._db;

    // ── Local dedup guard ──────────────────────────────────────────────────
    if (db != null) {
      try {
        final trimmedCode = code.trim();
        if (trimmedCode.isNotEmpty) {
          final existing = await (db.select(db.products)
                ..where((p) => p.code.equals(trimmedCode))
                ..limit(1))
              .getSingleOrNull();
          if (existing != null) {
            debugPrint('[ClientInterceptor] createProduct dedup: '
                'code="$trimmedCode" already exists as id=${existing.id} '
                '(globalId=${existing.globalId}). Returning existing id.');
            return existing.id;
          }
        }
        final trimmedBarcode = barcode?.trim();
        if (trimmedBarcode != null && trimmedBarcode.isNotEmpty) {
          final existing = await (db.select(db.products)
                ..where((p) => p.barcode.equals(trimmedBarcode))
                ..limit(1))
              .getSingleOrNull();
          if (existing != null) {
            debugPrint('[ClientInterceptor] createProduct dedup: '
                'barcode="$trimmedBarcode" already exists as id=${existing.id}. '
                'Returning existing id.');
            return existing.id;
          }
        }
      } catch (e) {
        debugPrint('[ClientInterceptor] createProduct local dedup failed (non-fatal): $e');
      }
    }

    final effectiveGlobalId =
        (globalId != null && globalId.isNotEmpty) ? globalId : const Uuid().v7();

    // Look up the category's globalId locally so the server can reconcile
    // by UUID even when client/server integer ids diverge.
    String? categoryGlobalId;
    String? categoryName;
    String? categoryColor;
    if (categoryId != null && db != null) {
      try {
        final cat = await (db.select(db.categories)
              ..where((c) => c.id.equals(categoryId))
              ..limit(1))
            .getSingleOrNull();
        if (cat != null) {
          categoryGlobalId = cat.globalId;
          categoryName = cat.name;
          categoryColor = cat.color;
          if (categoryGlobalId == null || categoryGlobalId.isEmpty) {
            categoryGlobalId = const Uuid().v7();
            try {
              await (db.update(db.categories)
                    ..where((c) => c.id.equals(categoryId)))
                  .write(CategoriesCompanion(globalId: Value(categoryGlobalId)));
            } catch (_) {}
          }
        }
      } catch (e) {
        debugPrint('[ClientInterceptor] category lookup failed (non-fatal): $e');
      }
    }

    final data = {
      'globalId': effectiveGlobalId,
      'code': code,
      'name': name,
      'salePrice': salePrice,
      'costPrice': costPrice,
      'categoryId': categoryId,
      'categoryGlobalId': categoryGlobalId,
      'categoryName': categoryName,
      'categoryColor': categoryColor,
      'supplierId': supplierId,
      'currentStock': currentStock,
      'barcode': barcode,
      'minStock': minStock,
      'taxRate': taxRate,
      'isSoldByWeight': isSoldByWeight,
      'allowNegativeSale': allowNegativeSale,
      'trackExpiry': trackExpiry,
      'defaultShelfDays': defaultShelfDays,
      'alertDaysBefore': alertDaysBefore,
      'pricePerUnit': pricePerUnit,
      'wholesalePrice': wholesalePrice,
      'priceTalabat': priceTalabat,
      'priceCareem': priceCareem,
      'priceAshyae': priceAshyae,
      'scaleType': scaleType,
      'scalePluNumber': scalePluNumber,
      'productType': productType,
      'warehouseId': warehouseId,
      if (units != null && units.isNotEmpty) 'units': units,
      if (barcodes != null && barcodes.isNotEmpty) 'barcodes': barcodes,
    };
    final result = await ClientWriteInterceptor._tryOrQueue(
      tableName: 'products',
      operation: 'insert',
      payload: data,
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.createProduct(data, idempotencyKey: reqIdemKey),
    );
    // Issue 3 — pull the products table immediately so the freshly-created
    // server row (with its authoritative id, server stamps, FK-resolved
    // category id) shows up on this device without waiting for the next
    // 5 s tick or a `data_changed` push. Fire-and-forget so the create
    // call still returns synchronously to the UI.
    _scheduleProductsPull('createProduct');
    return result;
  }

  static Future<bool> updateProduct(int id, Map<String, dynamic> data) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing product update to server');
    final result = await ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'products',
      operation: 'update',
      payload: {'id': id, ...data},
      serverCall: (reqIdemKey) async {
        await ClientWriteInterceptor._proxy
            .updateProduct(id, data, idempotencyKey: reqIdemKey);
      },
    );
    _scheduleProductsPull('updateProduct');
    return result;
  }

  static Future<bool> deleteProduct(int id, {String? idempotencyKey}) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing product delete to server');
    final result = await ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'products',
      operation: 'delete',
      payload: {'id': id},
      serverCall: (reqIdemKey) async {
        await ClientWriteInterceptor._proxy
            .deleteProduct(id, idempotencyKey: idempotencyKey ?? reqIdemKey);
      },
    );
    _scheduleProductsPull('deleteProduct');
    return result;
  }

  /// Fire-and-forget pull of the products table. Used after each
  /// client-mode product write so the originating device sees the
  /// authoritative server state immediately. Other clients still see it
  /// via the WebSocket `data_changed` broadcast — this catches the
  /// originator who otherwise would have to wait for the next tick.
  static void _scheduleProductsPull(String trigger) =>
      _schedulePullTable('products', trigger);

  /// Same pattern as [_scheduleProductsPull] for the categories table —
  /// Phase 5A.6 (Issue 3). Without this, a newly-created category from
  /// the originating client only appears via the WebSocket broadcast,
  /// which under load can race with the local insert and produce a
  /// transient duplicate on screen until the next periodic sync. Pulling
  /// immediately reconciles to the server's authoritative row.
  static void _scheduleCategoriesPull(String trigger) =>
      _schedulePullTable('categories', trigger);

  static void _schedulePullTable(String table, String trigger) {
    Future<void>(() async {
      try {
        await DeltaPullService.instance.pullTable(table);
      } catch (e) {
        debugPrint('[ClientInterceptor] post-$trigger pullTable($table) '
            'failed (non-fatal): $e');
      }
    });
  }

  // ── Purchases ─────────────────────────────────────────────────────────────

  static Future<int?> createPurchase({
    required int supplierId,
    required List<Map<String, dynamic>> items,
    double paid = 0,
    String? notes,
    String? globalId,
    int? userId,
  }) async {
    if (!SyncInterceptor.isClientMode) return null;
    debugPrint('[ClientInterceptor] Routing purchase create to server');
    final effectiveGlobalId =
        (globalId != null && globalId.isNotEmpty) ? globalId : const Uuid().v7();
    final supplierGlobalId =
        await ClientWriteInterceptor._lookupPartyGlobalId(supplierId);
    final supplierName =
        await ClientWriteInterceptor._lookupPartyName(supplierId);
    final data = {
      'globalId': effectiveGlobalId,
      'supplierId': supplierId,
      'supplierGlobalId': ?supplierGlobalId,
      'supplierName': ?supplierName,
      'items': items,
      'paid': paid,
      'notes': notes,
      'userId': ?userId,
    };
    await ClientWriteInterceptor._enrichItemsWithProductGlobalId(data);
    return ClientWriteInterceptor._tryOrQueue(
      tableName: 'purchases',
      operation: 'insert',
      payload: data,
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy.createPurchase(data),
    );
  }

  /// Route a purchase-invoice EDIT to the server.
  ///
  /// The payload MUST carry everything `putPurchase` needs to rebuild the
  /// invoice. Before this it sent only id/supplier/items/paid/notes, which
  /// broke client-mode editing two ways:
  ///   1. no `warehouseId` → the server's `parseInt(null) == 0` tripped
  ///      "Validation Error: warehouseId is required" on EVERY edit, and the
  ///      failed row then sat in the outbox driving the drain retry storm;
  ///   2. the per-line map omitted tax / batch / expiry / unit fields, so any
  ///      edit that DID land silently zeroed the VAT and dropped batch,
  ///      expiry and UOM data.
  /// `warehouseId` is still allowed to be null — the server now falls back to
  /// the invoice's own warehouse — but sending it keeps the edit explicit.
  static Future<bool> updatePurchase({
    required int invoiceId,
    required int supplierId,
    required List<Map<String, dynamic>> items,
    double paid = 0,
    String? notes,
    int? warehouseId,
    int? branchId,
    int? costCenterId,
    String? paymentMethod,
    String? supplierInvoiceNumber,
    int? userId,
  }) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing purchase update to server');
    final supplierGlobalId =
        await ClientWriteInterceptor._lookupPartyGlobalId(supplierId);
    final supplierName =
        await ClientWriteInterceptor._lookupPartyName(supplierId);
    final data = {
      'id': invoiceId,
      'supplierId': supplierId,
      'supplierGlobalId': ?supplierGlobalId,
      'supplierName': ?supplierName,
      'items': items,
      'paid': paid,
      'notes': notes,
      'warehouseId': ?warehouseId,
      'branchId': ?branchId,
      'costCenterId': ?costCenterId,
      'paymentMethod': ?paymentMethod,
      'supplierInvoiceNumber': ?supplierInvoiceNumber,
      'userId': ?userId,
    };
    await ClientWriteInterceptor._enrichItemsWithProductGlobalId(data);
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'purchases',
      operation: 'update',
      payload: data,
      serverCall: (reqIdemKey) =>
          ClientWriteInterceptor._proxy.updatePurchase(invoiceId, data),
    );
  }

  static Future<bool> deletePurchase(int id) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing purchase delete to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'purchases',
      operation: 'delete',
      payload: {'id': id},
      serverCall: (reqIdemKey) async {
        await ClientWriteInterceptor._proxy.deletePurchase(id);
      },
    );
  }

  // ── Shifts ────────────────────────────────────────────────────────────────

  static Future<int?> openShift(int userId, double openingBalance,
      {int? localShiftId, int? branchId, String? globalId}) async {
    if (!SyncInterceptor.isClientMode) {
      // Visibility v122: previously this branch was silent. Standalone
      // mode is fine (no server) but if a CLIENT install hits this path
      // it means the open never reached the server — an entire class
      // of "Shift not found" follow-on bugs hide here.
      unawaited(DiagnosticLogger.log('SHIFT-MIRROR',
          'openShift: skipped (isClientMode=false) '
          'userId=$userId localShiftId=$localShiftId globalId=$globalId'));
      return null;
    }
    unawaited(DiagnosticLogger.log('SHIFT-MIRROR',
        'openShift: routing to server '
        'userId=$userId localShiftId=$localShiftId '
        'branchId=$branchId globalId=$globalId'));
    debugPrint('[ClientInterceptor] Routing shift open to server '
        '(localShiftId=$localShiftId, branchId=$branchId, globalId=$globalId)');
    final result = await ClientWriteInterceptor._tryOrQueue(
      tableName: 'shifts',
      operation: 'open',
      // Include the local shift id as `id` so it lands in the outbox row's
      // recordId. When the drain replays openShift and the server returns
      // a serverId, OfflineSyncWorker captures the local→server mapping
      // → close-shift later remaps correctly instead of "Shift not found".
      payload: {
        'id': ?localShiftId,
        'userId': userId,
        'openingBalance': openingBalance,
        // Spec 008 / FR-006: thread branchId so the server records which
        // branch this shift was opened on. Required for multi-branch users
        // — see specs/008-shift-branchid/spec.md.
        'branchId': ?branchId,
        // R9: forward the local shift's globalId so the server can dedup
        // and so close-shift can later resolve by globalId instead of by
        // the local id (which the server doesn't have a mapping for).
        if (globalId != null && globalId.isNotEmpty) 'globalId': globalId,
      },
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy.openShift(
        userId,
        openingBalance,
        branchId: branchId,
        globalId: globalId,
        idempotencyKey: reqIdemKey,
      ),
    );
    unawaited(DiagnosticLogger.log('SHIFT-MIRROR',
        'openShift: result=${result == null ? "queued/null" : "serverId=$result"} '
        'localShiftId=$localShiftId globalId=$globalId'));
    return result;
  }

  static Future<bool> closeShift({
    required int userId,
    required double actualCash,
    double actualCard = 0,
  }) async {
    if (!SyncInterceptor.isClientMode) {
      // Visibility v122: standalone mode never mirrors. Logged so a
      // CLIENT-mode close that hits this branch (because of an
      // isClientMode race during shutdown) is no longer invisible.
      unawaited(DiagnosticLogger.log('SHIFT-MIRROR',
          'closeShift: skipped (isClientMode=false) '
          'userId=$userId actualCash=$actualCash'));
      return false;
    }
    debugPrint('[ClientInterceptor] Routing shift close to server');

    int shiftId = 0;
    // Phase 5A.7 (Issue 2) — capture the local shift's openingBalance and
    // openedAt so the server can RECONSTRUCT the shift if its own /api/
    // shifts/open never landed (open queued offline + close arrives first
    // when the network comes back). Previously the server early-returned
    // `clientAuthoritative:true` and never actually wrote the close,
    // leaving the user's reports out of sync between client and server.
    double? openingBalance;
    DateTime? openedAt;
    String? shiftGlobalId;
    try {
      final db = ClientWriteInterceptor._db;
      if (db != null) {
        final openShift = await db.getCurrentOpenShift(userId);
        if (openShift != null) {
          shiftId = openShift.id;
          openingBalance = openShift.openingBalance;
          openedAt = openShift.startTime;
          shiftGlobalId = openShift.globalId;
          // R9 backfill: legacy local shifts opened pre-globalId support
          // have a null globalId. Mint and persist one now so the server
          // can resolve / dedup this close (and any future operations).
          if (shiftGlobalId == null || shiftGlobalId.isEmpty) {
            shiftGlobalId = const Uuid().v7();
            try {
              await (db.update(db.shifts)..where((s) => s.id.equals(shiftId)))
                  .write(ShiftsCompanion(globalId: Value(shiftGlobalId)));
            } catch (e) {
              debugPrint('[ClientInterceptor] closeShift: failed to backfill '
                  'globalId on local shift $shiftId: $e');
            }
          }
        }
      }
    } catch (_) {}

    unawaited(DiagnosticLogger.log('SHIFT-MIRROR',
        'closeShift: routing to server '
        'userId=$userId localShiftId=$shiftId '
        'shiftGlobalId=$shiftGlobalId actualCash=$actualCash '
        'openingBalance=$openingBalance openedAt=$openedAt'));
    final ok = await ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'shifts',
      operation: 'close',
      payload: {
        'shiftId': shiftId,
        'userId': userId,
        'actualCash': actualCash,
        'actualCard': actualCard,
        'openingBalance': ?openingBalance,
        if (openedAt != null) 'openedAt': openedAt.toIso8601String(),
        if (shiftGlobalId != null && shiftGlobalId.isNotEmpty)
          'shiftGlobalId': shiftGlobalId,
        'notes': 'userId=$userId,actualCard=$actualCard',
      },
      serverCall: (reqIdemKey) async {
        await ClientWriteInterceptor._proxy.closeShift(
          shiftId,
          actualCash,
          notes: 'userId=$userId,actualCard=$actualCard',
          openingBalance: openingBalance,
          openedAt: openedAt,
          userId: userId,
          shiftGlobalId: shiftGlobalId,
          idempotencyKey: reqIdemKey,
        );
      },
    );
    unawaited(DiagnosticLogger.log('SHIFT-MIRROR',
        'closeShift: result=${ok ? "ok/queued" : "failed"} '
        'localShiftId=$shiftId shiftGlobalId=$shiftGlobalId'));
    return ok;
  }

  // ── Settings ──────────────────────────────────────────────────────────────

  static Future<bool> saveSettings(Map<String, String> settings) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing settings save to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'settings',
      operation: 'update',
      payload: {'settings': settings},
      serverCall: (reqIdemKey) async {
        await ClientWriteInterceptor._proxy.saveSettings(settings);
      },
    );
  }

  // ── Categories ────────────────────────────────────────────────────────────

  static Future<int?> createCategory({
    required String name,
    required String color,
    int? printerId,
    String? iconName,
    bool isGlobal = true,
    List<int> branchIds = const [],
    String? globalId,
  }) async {
    if (!SyncInterceptor.isClientMode) return null;
    debugPrint('[ClientInterceptor] Routing category create to server');
    // Issue 1 — always send a deterministic globalId so the server (and the
    // CategorySyncStrategy on the next pull) can dedup by UUID even if the
    // outbox replays the create after a timeout produced a second create
    // attempt.
    final effectiveGlobalId =
        (globalId != null && globalId.isNotEmpty) ? globalId : const Uuid().v7();
    final result = await ClientWriteInterceptor._tryOrQueue(
      tableName: 'categories',
      operation: 'insert',
      payload: {
        'globalId': effectiveGlobalId,
        'name': name,
        'color': color,
        'printerId': printerId,
        'iconName': iconName,
        'isGlobal': isGlobal,
        'branchIds': branchIds,
      },
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy.createCategory(
        name: name,
        color: color,
        printerId: printerId,
        iconName: iconName,
        isGlobal: isGlobal,
        branchIds: branchIds,
        globalId: effectiveGlobalId,
        idempotencyKey: reqIdemKey,
      ),
    );
    // Phase 5A.6 (Issue 3) — pull authoritative server state immediately
    // so the originating device reconciles to the server's id/timestamps
    // without waiting for the WebSocket broadcast (which under load can
    // arrive before the local strategy has finished its dedup pass).
    _scheduleCategoriesPull('createCategory');
    return result;
  }

  static Future<bool> updateCategory({
    required int id,
    required String name,
    required String color,
    int? printerId,
    String? iconName,
    bool isGlobal = true,
    List<int> branchIds = const [],
  }) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing category update to server');
    final result = await ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'categories',
      operation: 'update',
      payload: {
        'id': id,
        'name': name,
        'color': color,
        'printerId': printerId,
        'iconName': iconName,
        'isGlobal': isGlobal,
        'branchIds': branchIds,
      },
      serverCall: (reqIdemKey) async {
        await ClientWriteInterceptor._proxy.updateCategory(
          id: id,
          name: name,
          color: color,
          printerId: printerId,
          iconName: iconName,
          isGlobal: isGlobal,
          branchIds: branchIds,
          idempotencyKey: reqIdemKey,
        );
      },
    );
    _scheduleCategoriesPull('updateCategory');
    return result;
  }

  static Future<bool> deleteCategory(int id, {int? moveToCategoryId}) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing category delete to server '
        '(moveTo=${moveToCategoryId ?? "NULL"})');
    final result = await ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'categories',
      operation: 'delete',
      payload: {
        'id': id,
        // Feature 045 — caller-chosen destination for bulk-move. Cached on
        // the outbox payload so a deferred replay (offline_sync_worker)
        // applies the same migration server-side. NULL is encoded as a
        // present key with literal null so the server can distinguish
        // "uncategorized" from "field missing — legacy client".
        'moveToCategoryId': moveToCategoryId,
      },
      serverCall: (reqIdemKey) async {
        // Issue 1 — pass the outbox-row idempotency key so a replay after a
        // timeout doesn't try to delete twice. updateCategory already does
        // this; deleteCategory was the odd one out and produced spurious
        // 404s in the field.
        await ClientWriteInterceptor._proxy.deleteCategory(
          id,
          moveToCategoryId: moveToCategoryId,
          idempotencyKey: reqIdemKey,
        );
      },
    );
    _scheduleCategoriesPull('deleteCategory');
    return result;
  }

  // ── Users (Admin) ─────────────────────────────────────────────────────────

  static Future<bool> updateUser(int userId, Map<String, dynamic> fields) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing user update to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'users',
      operation: 'update',
      payload: {'id': userId, ...fields},
      serverCall: (reqIdemKey) async {
        await ClientWriteInterceptor._proxy
            .updateUser(userId, fields, idempotencyKey: reqIdemKey);
      },
    );
  }

  static Future<bool> updateUserPassword(int userId, String password) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing user password update to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'users',
      operation: 'update',
      payload: {'id': userId, 'password': password},
      serverCall: (reqIdemKey) async {
        await ClientWriteInterceptor._proxy
            .updateUserPassword(userId, password, idempotencyKey: reqIdemKey);
      },
    );
  }

  static Future<bool> updateUserPin(int userId, String? pin) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing user PIN update to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'users',
      operation: 'update',
      payload: {'id': userId, 'pin': pin},
      serverCall: (reqIdemKey) async {
        await ClientWriteInterceptor._proxy
            .updateUserPin(userId, pin, idempotencyKey: reqIdemKey);
      },
    );
  }

  // ── Warehouses ────────────────────────────────────────────────────────────

  static Future<int?> createWarehouse({
    required String name,
    int? branchId,
    String? globalId,
  }) async {
    if (!SyncInterceptor.isClientMode) return null;
    debugPrint('[ClientInterceptor] Routing warehouse create to server');
    final effectiveGlobalId =
        (globalId != null && globalId.isNotEmpty) ? globalId : const Uuid().v7();
    return ClientWriteInterceptor._tryOrQueue(
      tableName: 'warehouses',
      operation: 'insert',
      payload: {
        'name': name,
        'branchId': branchId,
        'globalId': effectiveGlobalId,
      },
      serverCall: (reqIdemKey) => ClientWriteInterceptor._proxy.createWarehouse(
        name: name,
        branchId: branchId,
        globalId: effectiveGlobalId,
      ),
    );
  }

  static Future<bool> updateWarehouse(int id, Map<String, dynamic> fields) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing warehouse update to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'warehouses',
      operation: 'update',
      payload: {'id': id, ...fields},
      serverCall: (reqIdemKey) async {
        await ClientWriteInterceptor._proxy
            .updateWarehouse(id, fields, idempotencyKey: reqIdemKey);
      },
    );
  }

  static Future<bool> setDefaultWarehouse(int id) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing set default warehouse to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'warehouses',
      operation: 'update',
      payload: {'id': id, 'setDefault': true},
      serverCall: (reqIdemKey) async {
        await ClientWriteInterceptor._proxy
            .setDefaultWarehouse(id, idempotencyKey: reqIdemKey);
      },
    );
  }

  static Future<bool> unsetDefaultWarehouse(int id) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing unset default warehouse to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'warehouses',
      operation: 'update',
      payload: {'id': id, 'unsetDefault': true},
      serverCall: (reqIdemKey) async {
        await ClientWriteInterceptor._proxy
            .unsetDefaultWarehouse(id, idempotencyKey: reqIdemKey);
      },
    );
  }

  static Future<bool> deleteWarehouse(int id) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing warehouse delete to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'warehouses',
      operation: 'delete',
      payload: {'id': id},
      serverCall: (reqIdemKey) async {
        await ClientWriteInterceptor._proxy
            .deleteWarehouse(id, idempotencyKey: reqIdemKey);
      },
    );
  }
}
