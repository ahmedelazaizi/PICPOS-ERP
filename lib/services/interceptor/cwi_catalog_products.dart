part of '../client_write_interceptor.dart';


// ═══════════════════════════════════════════════════════════════════════════
// Catalog module — Products · Purchases · Shifts · Settings · Categories
//                  Users · Warehouses
//
// Part of the ClientWriteInterceptor library.
// ═══════════════════════════════════════════════════════════════════════════

class _CwiCatalogProducts {
  _CwiCatalogProducts._();

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
    // B3: «معفى» (raw `products.tax_exempt`) — taxed at 0 %, so it must
    // reach the server with the product.
    bool taxExempt = false,
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
            } catch (error, stack) {
              unawaited(DiagnosticLogger.logError(
                'SYNC-INTERCEPTOR',
                'close-shift local metadata lookup failed',
                error,
                stack,
              ));
            }
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
      'taxExempt': taxExempt,
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
}
