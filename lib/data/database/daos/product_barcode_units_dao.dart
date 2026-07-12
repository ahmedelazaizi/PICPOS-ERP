part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PRODUCT BARCODE, UNITS & PRICING DAO — الباركود والوحدات والتسعير
// ═══════════════════════════════════════════════════════════════════════════

extension ProductBarcodeUnitsDao on AppDatabase {
  // ═══════════════════════════════════════════════════════════════════════
  // BARCODE OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════

  /// Get product by barcode
  Future<Product?> getProductByBarcode(String barcode) async {
    // 1. Try fetching from main products table (Primary barcode)
    final product = await (select(products)
          ..where(
            (p) => p.barcode.equals(barcode) & p.isActive.equals(true),
          )
          ..limit(1))
        .getSingleOrNull();

    if (product != null) return product;

    // 2. Try fetching from secondary barcodes table
    final secondary = await (select(productBarcodes)
          ..where((b) => b.barcode.equals(barcode))
          ..limit(1))
        .getSingleOrNull();

    if (secondary != null) {
      return (select(products)
            ..where(
              (p) =>
                  p.id.equals(secondary.productId) & p.isActive.equals(true),
            )
            ..limit(1))
          .getSingleOrNull();
    }

    return null;
  }

  /// Diagnostic method: Get product by barcode regardless of isActive status
  Future<Product?> getProductAnyStatusByBarcode(String barcode) async {
    // 1. Try fetching from main products table
    final product = await (select(products)
          ..where((p) => p.barcode.equals(barcode))
          ..limit(1))
        .getSingleOrNull();

    if (product != null) return product;

    // 2. Try fetching from secondary barcodes
    final secondary = await (select(productBarcodes)
          ..where((b) => b.barcode.equals(barcode))
          ..limit(1))
        .getSingleOrNull();

    if (secondary != null) {
      return (select(products)
            ..where((p) => p.id.equals(secondary.productId))
            ..limit(1))
          .getSingleOrNull();
    }

    return null;
  }

  /// Insert a product barcode
  Future<int> insertProductBarcode(
    int productId,
    String barcode, {
    bool isPrimary = false,
  }) async {
    // UUID-First Phase 1 Slice 3: mint ONE globalId upfront so the server
    // and local row share identity whether the interceptor path wins or
    // we fall back to a pure-local insert.
    final gid = UuidV7.generate();
    final companion = ProductBarcodesCompanion.insert(
      productId: productId,
      barcode: barcode,
      isPrimary: Value(isPrimary),
      globalId: Value(gid),
    );
    if (SyncInterceptor.isClientMode) {
      final serverId = await SyncInterceptor.instance?.createProductBarcode(companion);
      if (serverId != null) return serverId;
    }

    return into(productBarcodes).insert(companion);
  }

  /// Delete a barcode by ID
  Future<void> deleteProductBarcode(int barcodeId) async {
    if (SyncInterceptor.isClientMode) {
      await SyncInterceptor.instance?.deleteProductBarcode(barcodeId);
    }
    await (delete(productBarcodes)..where((b) => b.id.equals(barcodeId))).go();
  }

  /// Get all barcodes for a product
  Future<List<ProductBarcode>> getProductBarcodes(int productId) {
    return (select(
      productBarcodes,
    )..where((b) => b.productId.equals(productId))).get();
  }

  /// Delete product barcodes
  Future<void> deleteProductBarcodes(int productId) async {
    await (delete(
      productBarcodes,
    )..where((b) => b.productId.equals(productId))).go();
  }

  /// Check if barcode exists (optionally exclude a product ID for edit scenarios)
  Future<bool> barcodeExists(String barcode, {int? excludeProductId}) async {
    // Check in products table
    final query = select(products)..where((p) => p.barcode.equals(barcode));
    if (excludeProductId != null) {
      query.where((p) => p.id.equals(excludeProductId).not());
    }
    final inProducts = await (query..limit(1)).getSingleOrNull();
    if (inProducts != null) return true;

    // Check in barcodes table
    final bQuery = select(productBarcodes)
      ..where((b) => b.barcode.equals(barcode));
    if (excludeProductId != null) {
      bQuery.where((b) => b.productId.equals(excludeProductId).not());
    }
    final inBarcodes = await (bQuery..limit(1)).getSingleOrNull();
    return inBarcodes != null;
  }

  /// Check if product code exists (optionally exclude a product ID for edit scenarios)
  Future<bool> productCodeExists(String code, {int? excludeProductId}) async {
    final query = select(products)
      ..where((p) => p.code.equals(code) & p.isActive.equals(true));
    if (excludeProductId != null) {
      query.where((p) => p.id.equals(excludeProductId).not());
    }
    final existing = await (query..limit(1)).getSingleOrNull();
    return existing != null;
  }

  /// Get product by internal code (for weighted barcodes)
  Future<Product?> getProductByCode(String code) async {
    return (select(products)..where((p) => p.code.equals(code))).get().then(
      (list) => list.isEmpty ? null : list.first,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SCALE PLU (أرقام الميزان)
  // ═══════════════════════════════════════════════════════════════════════

  /// Get product by scale PLU number (for scale barcode parsing)
  Future<Product?> getProductByScalePlu(int pluNumber) async {
    return (select(products)..where((p) => p.scalePluNumber.equals(pluNumber)))
        .get()
        .then((list) => list.isEmpty ? null : list.first);
  }

  /// Update product scale PLU number (lightweight — only updates PLU fields)
  Future<void> updateProductScalePlu(
    int productId, {
    int? pluNumber,
    bool? isSoldByWeight,
  }) async {
    await (update(products)..where((p) => p.id.equals(productId))).write(
      ProductsCompanion(
        scalePluNumber: pluNumber != null
            ? Value(pluNumber)
            : const Value.absent(),
        isSoldByWeight: isSoldByWeight != null
            ? Value(isSoldByWeight)
            : const Value.absent(),
      ),
    );
    _productSearchCache.clear();
  }

  /// Clear product scale PLU number (set to null)
  Future<void> clearProductScalePlu(int productId) async {
    await customStatement(
      'UPDATE products SET scale_plu_number = NULL WHERE id = ?',
      [productId],
    );
    _productSearchCache.clear();
  }

  /// Get all products with scale PLU assigned
  Future<List<Product>> getScaleProducts() async {
    return (select(products)
          ..where((p) => p.scalePluNumber.isNotNull())
          ..where((p) => p.isActive.equals(true))
          ..orderBy([(p) => OrderingTerm.asc(p.scalePluNumber)]))
        .get();
  }

  /// Get the next available PLU number
  Future<int> getNextAvailableScalePlu() async {
    final result = await customSelect(
      'SELECT MAX(scale_plu_number) as max_plu FROM products WHERE scale_plu_number IS NOT NULL',
    ).getSingleOrNull();
    final maxPlu = result?.read<int?>('max_plu') ?? 0;
    return maxPlu + 1;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // UNIT OPERATIONS (الوحدات الأساسية)
  // ═══════════════════════════════════════════════════════════════════════

  /// Get all units
  Future<List<Unit>> getAllUnits() {
    return select(units).get();
  }

  /// Watch all units
  Stream<List<Unit>> watchAllUnits() {
    return select(units).watch();
  }

  /// Insert a new unit.
  ///
  /// UUID-First (Phase 1): auto-mint a UUID v7 globalId if the caller did
  /// not supply one, so server and local row share a stable identity.
  Future<int> insertUnit(UnitsCompanion unit) async {
    final hasGid = unit.globalId.present &&
        (unit.globalId.value?.isNotEmpty ?? false);
    final unitWithGid =
        hasGid ? unit : unit.copyWith(globalId: Value(UuidV7.generate()));
    if (SyncInterceptor.isClientMode) {
      final serverId =
          await SyncInterceptor.instance?.createUnit(unitWithGid);
      if (serverId != null) return serverId;
    }
    return into(units).insert(unitWithGid);
  }

  /// Update an existing unit
  Future<bool> updateUnit(Unit unit) async {
    if (SyncInterceptor.isClientMode) {
      await SyncInterceptor.instance?.updateUnit(unit.id, {
        'name': unit.name,
      });
    }
    return update(units).replace(unit);
  }

  /// Delete a unit by ID
  Future<void> deleteUnit(int unitId) async {
    if (SyncInterceptor.isClientMode) {
      await SyncInterceptor.instance?.deleteUnit(unitId);
    }
    await (delete(units)..where((u) => u.id.equals(unitId))).go();
  }

  /// Get product by unit barcode (any unit) - checks units then falls back to barcodes
  Future<Product?> getProductByUnitBarcode(String barcode) async {
    final unit =
        await (select(productUnits)..where((u) => u.barcode.equals(barcode)))
            .get()
            .then((list) => list.isEmpty ? null : list.first);
    if (unit != null) {
      return (select(
        products,
      )..where((p) => p.id.equals(unit.productId))).getSingleOrNull();
    }
    // Fallback to product barcodes
    return getProductByBarcode(barcode);
  }

  /// Get unit by barcode
  Future<ProductUnit?> getUnitByBarcode(String barcode) async {
    return (select(
      productUnits,
    )..where((u) => u.barcode.equals(barcode))..limit(1)).getSingleOrNull();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PRODUCT UNITS (Multi-unit support — وحدات المنتج)
  // ═══════════════════════════════════════════════════════════════════════

  /// Get all units for a product
  Future<List<ProductUnit>> getProductUnits(int productId) {
    return (select(productUnits)
          ..where((u) => u.productId.equals(productId))
          ..orderBy([(u) => OrderingTerm.asc(u.sortOrder)]))
        .get();
  }

  /// Watch product units
  Stream<List<ProductUnit>> watchProductUnits(int productId) {
    return (select(productUnits)
          ..where((u) => u.productId.equals(productId))
          ..orderBy([(u) => OrderingTerm.asc(u.sortOrder)]))
        .watch();
  }

  /// Insert a product unit
  Future<int> insertProductUnit(ProductUnitsCompanion unit) async {
    // UUID-First Phase 1 Slice 3: auto-mint if caller didn't supply a
    // globalId so both client and server rows share the same identity.
    final hasGid = unit.globalId.present &&
        (unit.globalId.value?.isNotEmpty ?? false);
    final unitWithGid = hasGid
        ? unit
        : unit.copyWith(globalId: Value(UuidV7.generate()));
    if (SyncInterceptor.isClientMode) {
      final serverId = await SyncInterceptor.instance?.createProductUnit(unitWithGid);
      if (serverId != null) return serverId;
    }
    return into(productUnits).insert(unitWithGid);
  }

  /// Update a product unit
  Future<bool> updateProductUnit(ProductUnit unit) async {
    if (SyncInterceptor.isClientMode) {
      await SyncInterceptor.instance?.updateProductUnit(unit.id, {
        'unitName': unit.unitName,
        'barcode': unit.barcode,
        'quantityInBase': unit.quantityInBase,
        'salePrice': unit.salePrice,
        'costPrice': unit.costPrice,
        'isBaseUnit': unit.isBaseUnit,
        'isDefaultSale': unit.isDefaultSale,
        'sortOrder': unit.sortOrder,
      });
    }
    return update(productUnits).replace(unit);
  }

  /// Delete a product unit by ID
  Future<void> deleteProductUnit(int unitId) async {
    if (SyncInterceptor.isClientMode) {
      await SyncInterceptor.instance?.deleteProductUnit(unitId);
    }
    await (delete(productUnits)..where((u) => u.id.equals(unitId))).go();
  }

  /// Delete all units for a product
  Future<void> deleteProductUnits(int productId) async {
    await (delete(
      productUnits,
    )..where((u) => u.productId.equals(productId))).go();
  }

  /// Create default units for a product
  Future<void> createDefaultProductUnits(
    int productId, {
    double piecePrice = 0,
    double pieceCost = 0,
    String? pieceBarcode,
  }) async {
    await insertProductUnit(
      ProductUnitsCompanion.insert(
        productId: productId,
        unitName: 'قطعة',
        barcode: Value(pieceBarcode),
        quantityInBase: const Value(1),
        salePrice: Value(piecePrice),
        costPrice: Value(pieceCost),
        isBaseUnit: const Value(true),
        isDefaultSale: const Value(true),
        sortOrder: const Value(0),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // WAREHOUSE PRICING (Per-warehouse product prices — تسعير حسب المستودع)
  // ═══════════════════════════════════════════════════════════════════════

  /// Get all warehouse-specific prices for a product
  Future<List<WarehousePrice>> getWarehousePricesForProduct(int productId) {
    return (select(warehousePrices)
          ..where((w) => w.productId.equals(productId)))
        .get();
  }

  /// Get price for a specific product+warehouse pair
  Future<WarehousePrice?> getWarehousePrice(int productId, int warehouseId) {
    return (select(warehousePrices)
          ..where(
            (w) =>
                w.productId.equals(productId) &
                w.warehouseId.equals(warehouseId),
          ))
        .getSingleOrNull();
  }

  /// Insert or update a warehouse price entry
  Future<void> upsertWarehousePrice({
    required int productId,
    required int warehouseId,
    required double salePrice,
    required double costPrice,
    required double wholesalePrice,
    String? notes,
  }) async {
    final existing = await getWarehousePrice(productId, warehouseId);
    if (existing != null) {
      await (update(warehousePrices)..where((w) => w.id.equals(existing.id)))
          .write(
        WarehousePricesCompanion(
          salePrice: Value(salePrice),
          costPrice: Value(costPrice),
          wholesalePrice: Value(wholesalePrice),
          notes: Value(notes),
        ),
      );
    } else {
      await into(warehousePrices).insert(
        WarehousePricesCompanion.insert(
          productId: productId,
          warehouseId: warehouseId,
          salePrice: Value(salePrice),
          costPrice: Value(costPrice),
          wholesalePrice: Value(wholesalePrice),
          notes: Value(notes),
        ),
      );
    }
  }

  /// Delete a warehouse price entry by ID
  Future<void> deleteWarehousePrice(int id) async {
    await (delete(warehousePrices)..where((w) => w.id.equals(id))).go();
  }

  /// Delete all warehouse prices for a product
  Future<void> deleteAllWarehousePrices(int productId) async {
    await (delete(warehousePrices)
          ..where((w) => w.productId.equals(productId)))
        .go();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // UOM DISPLAY HELPERS
  // ═══════════════════════════════════════════════════════════════════════

  /// Get a map of productId → base unit name for all products that have units.
  Future<Map<int, String>> getBaseUnitNameMap() async {
    final results = await customSelect(
      '''SELECT pu.product_id, pu.unit_name
         FROM product_units pu
         WHERE pu.id = (
           SELECT pu2.id FROM product_units pu2
           WHERE pu2.product_id = pu.product_id
           ORDER BY pu2.is_base_unit DESC, pu2.sort_order ASC
           LIMIT 1
         )''',
      readsFrom: {productUnits},
    ).get();

    final map = <int, String>{};
    for (final row in results) {
      map[row.data['product_id'] as int] = row.data['unit_name'] as String;
    }
    return map;
  }
}
