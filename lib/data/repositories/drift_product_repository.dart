import 'package:flutter/foundation.dart';
import '../../domain/entities/product_entity.dart';
import '../../domain/repositories/i_products_repository.dart';
import '../database/database_barrel.dart' as db;
import 'package:drift/drift.dart';

class DriftProductRepository implements IProductRepository {
  final db.AppDatabase _db;

  DriftProductRepository(this._db);

  /// B3 — maps rows and stamps `taxExempt` from the raw `products.tax_exempt`
  /// column (one query per batch; not part of the Drift row).
  Future<List<ProductEntity>> _mapAll(List<db.Product> rows) async {
    if (rows.isEmpty) return const [];
    final exempt = await _db.getTaxExemptProductIds(rows.map((p) => p.id));
    return [
      for (final p in rows)
        _mapToEntity(p, taxExempt: exempt.contains(p.id)),
    ];
  }

  Future<ProductEntity?> _mapOne(db.Product? p) async =>
      p == null ? null : (await _mapAll([p])).single;

  ProductEntity _mapToEntity(db.Product p, {bool taxExempt = false}) {
    return ProductEntity(
      taxExempt: taxExempt,
      id: p.id,
      code: p.code,
      name: p.name,
      categoryId: p.categoryId,
      categoryName: null, // Populated by UI if needed
      salePrice: p.salePrice,
      costPrice: p.costPrice,
      pricePerUnit: p.pricePerUnit,
      currentStock: p.currentStock,
      minStock: p.minStock,
      trackInventory: p.trackInventory,
      trackExpiry: p.trackExpiry,
      isSoldByWeight: p.isSoldByWeight,
      isActive: p.isActive,
      description: p.description,
      barcode: p.barcode,
      scalePluNumber: p.scalePluNumber,
      scaleType: p.scaleType,
      taxRate: p.taxRate,
      isLocked: p.isLocked,
      allowNegativeSale: p.allowNegativeSale,
      defaultShelfDays: p.defaultShelfDays,
      alertDaysBefore: p.alertDaysBefore,
      priceTalabat: p.priceTalabat,
      priceCareem: p.priceCareem,
      priceAshyae: p.priceAshyae,
      wholesalePrice: p.wholesalePrice,
      supplierId: p.supplierId,
      imageData: p.imageData,
      productType: p.productType,
      warehouseId: p.warehouseId,
    );
  }

  @override
  Stream<List<ProductEntity>> watchAllProducts() {
    return _db.watchAllProducts().asyncMap(_mapAll);
  }

  @override
  Stream<List<ProductEntity>> watchInventoryProducts({
    int limit = 1500,
    String? search,
    int? categoryId,
    bool lowStockOnly = false,
    Iterable<int>? restrictToIds,
  }) {
    return _db
        .watchInventoryProducts(
          limit: limit,
          search: search,
          categoryId: categoryId,
          lowStockOnly: lowStockOnly,
          restrictToIds: restrictToIds,
        )
        .asyncMap(_mapAll);
  }

  @override
  Stream<({int activeCount, int lowStockCount, double totalValue})>
      watchInventorySummary() {
    return _db.watchInventorySummary();
  }

  @override
  Stream<List<ProductEntity>> watchPosProducts({
    Iterable<int>? categoryIds,
    String? search,
    int limit = 600,
    bool includeUncategorized = false,
  }) {
    return _db
        .watchPosProducts(
          categoryIds: categoryIds,
          search: search,
          limit: limit,
          includeUncategorized: includeUncategorized,
        )
        .asyncMap(_mapAll);
  }

  @override
  Future<T> runInWriteTransaction<T>(Future<T> Function() action) {
    return _db.transaction(action);
  }

  @override
  Future<List<ProductEntity>> getInventoryProductsPage({
    required int limit,
    required int offset,
    String? search,
    int? categoryId,
    bool lowStockOnly = false,
    Iterable<int>? restrictToIds,
  }) async {
    final rows = await _db.getInventoryProductsPage(
      limit: limit,
      offset: offset,
      search: search,
      categoryId: categoryId,
      lowStockOnly: lowStockOnly,
      restrictToIds: restrictToIds,
    );
    return _mapAll(rows);
  }

  @override
  Future<List<ProductEntity>> getProducts({
    int limit = 20,
    int offset = 0,
    String? query,
    int? categoryId,
  }) async {
    final queryBuilder = _db.select(_db.products);

    // ── المحذوفُ يختفي · والمعطَّلُ يبقى ──────────────────────────────────
    //
    // هذا قارئُ شاشة الأصناف، وكان **الوحيد** بين قرّاء المنتجات بلا فلترةٍ
    // إطلاقاً — نظائرُه في الـDAO (`watchAllProducts` · `getAllProducts` ·
    // `watchProductsByCategory`) تفلتر `isActive == true`. فالمحذوفُ كان
    // مستبعَداً من البيع السريع والمنتقيات تلقائياً وباقياً هنا وحدَه:
    // «تظهر رسالة تم الحذف ولكن لا يزال الصنف موجوداً» (بلاغٌ ميدانيّ).
    //
    // 🔴 والفلترةُ على `deletedAt` **وحدَه** — لا `isActive`. الشاشةُ تعرض
    // المعطَّلَ **عمداً** كي يستطيع المشغّلُ إعادةَ تفعيله، وفلترةٌ على
    // `isActive` كانت ستُخفيه هي الأخرى فتكسر خاصيةً قائمة. وهي الطريقُ
    // الأقصرُ الخاطئ الذي يقع فيه من يصلح هذا العطل — ولذلك اختبارٌ حارسٌ
    // صريحٌ عليها في `test/unit/product_delete_hides_from_list_test.dart`.
    queryBuilder.where((p) => p.deletedAt.isNull());

    // Apply filters
    if (query != null && query.isNotEmpty) {
      // Issue 1 (Feature 019): primary `barcode` column.
      // Cluster 023 / Issue 10 — also match against the `product_barcodes`
      // table (multi-barcode UPCs / packaging-unit barcodes) so a scanned
      // barcode that's stored on a unit row instead of the product row
      // still finds the product. Subquery returns the productIds whose
      // additional barcodes match; OR with the primary-column predicates.
      final barcodeMatchIds = await (_db.select(_db.productBarcodes)
            ..where((b) => b.barcode.contains(query)))
          .get();
      final extraIds = barcodeMatchIds.map((b) => b.productId).toSet().toList();
      queryBuilder.where(
        (p) =>
            p.name.contains(query) |
            p.code.contains(query) |
            p.barcode.contains(query) |
            (extraIds.isNotEmpty ? p.id.isIn(extraIds) : const Constant(false)),
      );
    }
    if (categoryId != null) {
      queryBuilder.where((p) => p.categoryId.equals(categoryId));
    }

    // Apply pagination
    queryBuilder.orderBy([
      (p) => OrderingTerm(expression: p.sortOrder, mode: OrderingMode.asc),
      (p) => OrderingTerm(expression: p.name, mode: OrderingMode.asc),
    ]);
    queryBuilder.limit(limit, offset: offset);

    final dbProducts = await queryBuilder.get();
    // Day-18: Diagnostic count log gated — release builds must not emit
    // internal query parameters to the console or crash-log collectors.
    if (kDebugMode) {
      debugPrint('[PRODUCTS_REPO] getProducts returned ${dbProducts.length} items '
          '(limit=$limit, offset=$offset, query=$query, categoryId=$categoryId)');
    }
    return _mapAll(dbProducts);
  }

  @override
  Stream<List<ProductEntity>> searchProducts(String query) {
    return _db
        .searchProducts(query)
        .asyncMap(_mapAll);
  }

  @override
  Future<ProductEntity?> getProductById(int id) async {
    return _mapOne(await _db.getProductById(id));
  }

  @override
  Future<List<ProductEntity>> getProductsByIds(List<int> ids) async {
    if (ids.isEmpty) return const [];
    // Deduplicate to minimise query work
    final unique = ids.toSet().toList();
    final rows = await (_db.select(_db.products)
          ..where((p) => p.id.isIn(unique)))
        .get();
    return _mapAll(rows);
  }

  @override
  Future<ProductEntity?> getProductByCode(String code) async {
    return _mapOne(await _db.getProductByCode(code));
  }

  @override
  Future<ProductEntity?> getProductByBarcode(String barcode) async {
    return _mapOne(await _db.getProductByBarcode(barcode));
  }

  @override
  Future<ProductEntity?> getProductAnyStatusByBarcode(String barcode) async {
    return _mapOne(await _db.getProductAnyStatusByBarcode(barcode));
  }

  @override
  Future<ProductEntity?> getProductByScalePlu(int pluNumber) async {
    return _mapOne(await _db.getProductByScalePlu(pluNumber));
  }

  @override
  Future<List<db.ProductBarcode>> getAllProductBarcodes() {
    return _db.select(_db.productBarcodes).get();
  }

  @override
  Future<List<db.ProductBarcode>> getProductBarcodes(int productId) {
    return _db.getProductBarcodes(productId);
  }

  @override
  Stream<List<ProductEntity>> watchLowStockProducts() {
    return _db.watchLowStockProducts().asyncMap(_mapAll);
  }

  @override
  Future<List<ProductEntity>> getLowStockProducts() async {
    return _mapAll(await _db.getLowStockProducts());
  }

  @override
  Future<void> updateProductStock(int productId, double newStock) {
    return _db.updateProductStock(productId, newStock);
  }

  @override
  Future<int> createStockMovement(db.StockMovementsCompanion movement) {
    return _db.createStockMovement(movement);
  }

  @override
  Future<List<db.ProductBatch>> getExpiredBatches() {
    return _db.getExpiredBatches();
  }

  @override
  Future<List<db.ProductBatch>> getExpiringBatches(int days) {
    return _db.getExpiringBatches(days);
  }

  @override
  Stream<List<db.Category>> watchAllCategories() {
    return _db.watchAllCategories();
  }

  @override
  Stream<List<db.Category>> watchCategoriesForBranch(int branchId) {
    return _db.watchCategoriesForBranch(branchId);
  }

  @override
  Future<List<db.Category>> getCategories() async {
    return _db.select(_db.categories).get();
  }

  @override
  Future<List<int>> getCategoryBranchIds(int categoryId) {
    return _db.getCategoryBranchIds(categoryId);
  }

  @override
  Future<int> getOrCreateCategory(String name) async {
    return _db.getOrCreateCategory(name);
  }

  @override
  Future<List<db.Product>> getAllProducts() async {
    return _db.select(_db.products).get();
  }

  @override
  Future<db.Category?> getCategoryById(int id) async {
    return (_db.select(_db.categories)..where((c) => c.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<List<db.Party>> getSuppliers() async {
    return _db.getSuppliers();
  }

  @override
  Future<bool> productCodeExists(String code, {int? excludeProductId}) async {
    return _db.productCodeExists(code, excludeProductId: excludeProductId);
  }

  @override
  Future<bool> barcodeExists(String barcode, {int? excludeProductId}) async {
    return _db.barcodeExists(barcode, excludeProductId: excludeProductId);
  }

  @override
  Future<void> logActivity({
    required int? userId,
    required String userName,
    required String action,
    required int entityId,
    required String description,
    String? oldValue,
    String? newValue,
  }) async {
    await _db.logActivity(
      userId: userId,
      userName: userName,
      action: action,
      entityType: 'product',
      entityId: entityId,
      description: description,
      oldValue: oldValue,
      newValue: newValue,
    );
  }

  @override
  Future<int> insertProduct(db.ProductsCompanion product) async {
    return _db.insertProduct(product);
  }

  @override
  Future<bool> updateProduct(db.Product product) async {
    return _db.updateProduct(product);
  }

  @override
  Future<bool> updateProductFromEntity(ProductEntity entity) async {
    return _db.updateProductFromEntity(entity);
  }

  @override
  Future<void> updateProductPrices(int productId, {required double costPrice, required double salePrice}) async {
    await (_db.update(_db.products)..where((p) => p.id.equals(productId))).write(
      db.ProductsCompanion(
        costPrice: Value(costPrice),
        salePrice: Value(salePrice),
      ),
    );
  }

  @override
  Future<void> deleteProduct(int id) async {
    await _db.deleteProduct(id);
  }

  @override
  Future<void> insertCategoryWithPrinter({
    required String name,
    required String color,
    int? printerId,
    String? iconName,
    bool isGlobal = true,
    List<int> branchIds = const [],
  }) async {
    await _db.transaction(() async {
      final categoryId = await _db.insertCategoryWithPrinter(
        name: name,
        color: color,
        printerId: printerId,
        iconName: iconName,
      );

      // Update isGlobal
      await (_db.update(_db.categories)..where((c) => c.id.equals(categoryId)))
          .write(db.CategoriesCompanion(isGlobal: Value(isGlobal)));

      // Link branches
      await _db.setCategoryBranches(categoryId, branchIds);
    });
  }

  @override
  Future<void> updateCategoryWithPrinter({
    required int id,
    required String name,
    required String color,
    int? printerId,
    String? iconName,
    bool isGlobal = true,
    List<int> branchIds = const [],
  }) async {
    await _db.transaction(() async {
      await _db.updateCategoryWithPrinter(
        id: id,
        name: name,
        color: color,
        printerId: printerId,
        iconName: iconName,
      );

      // Update isGlobal
      await (_db.update(_db.categories)..where((c) => c.id.equals(id)))
          .write(db.CategoriesCompanion(isGlobal: Value(isGlobal)));

      // Link branches
      await _db.setCategoryBranches(id, branchIds);
    });
  }

  @override
  Future<int> countActiveProductsInCategory(int categoryId) {
    return _db.countActiveProductsInCategory(categoryId);
  }

  @override
  Future<int> countCategoryInvoicedItemsOnBranch(
    int categoryId,
    int branchId,
  ) {
    return _db.countCategoryInvoicedItemsOnBranch(categoryId, branchId);
  }

  @override
  Future<void> deleteCategory(int id, {int? moveToCategoryId}) async {
    await _db.deleteCategory(id, moveToCategoryId: moveToCategoryId);
  }

  @override
  Future<void> setCategoryLocked(int categoryId, bool isLocked) async {
    await _db.setCategoryLocked(categoryId, isLocked);
  }

  @override
  Future<void> excludeCategoryWithAllProducts(int categoryId) async {
    await _db.excludeCategoryWithAllProducts(categoryId);
  }

  @override
  Future<void> unexcludeCategoryWithAllProducts(int categoryId) async {
    await _db.unexcludeCategoryWithAllProducts(categoryId);
  }

  @override
  Future<void> setCategoryShowInPos(int categoryId, bool showInPos) async {
    await _db.setCategoryShowInPos(categoryId, showInPos);
  }

  @override
  Future<void> updateCategorySortOrders(List<int> categoryIds) async {
    await _db.updateCategorySortOrders(categoryIds);
  }

  @override
  Future<String> getNextProductCode() {
    return _db.getNextProductCode();
  }

  @override
  Future<int> quickAddProduct({
    required String name,
    required double salePrice,
    String? barcode,
    int? categoryId,
    bool allowNegativeSale = false,
  }) async {
    // Day 6C: presentation calls this instead of building a Drift Companion.
    final code = await _db.getNextProductCode();
    return _db.insertProduct(db.ProductsCompanion.insert(
      code: code,
      name: name,
      salePrice: Value(salePrice),
      barcode: Value(barcode),
      categoryId: Value(categoryId),
      costPrice: const Value(0),
      // Cluster 024 / Issue 8 — persist the negative-sales flag on the new
      // row so the operator can immediately sell it without trip to the
      // products screen. Caller supplies `true` when the install-wide
      // `enable_negative_sales` setting is on.
      allowNegativeSale: Value(allowNegativeSale),
    ));
  }

  @override
  Future<int> insertProductBarcode(int productId, String barcode, {bool isPrimary = false}) {
    return _db.insertProductBarcode(productId, barcode, isPrimary: isPrimary);
  }

  @override
  Future<void> createDefaultProductUnits(int productId, {double piecePrice = 0, double pieceCost = 0, String? pieceBarcode}) {
    return _db.createDefaultProductUnits(productId, piecePrice: piecePrice, pieceCost: pieceCost, pieceBarcode: pieceBarcode);
  }

  @override
  Future<List<db.Product>> getInventoryProducts() {
    return (_db.select(_db.products)..where((p) => p.trackInventory.equals(true))).get();
  }

  @override
  Future<double> getCalculatedStock(int productId) async {
    final result = await _db.customSelect(
      'SELECT COALESCE(SUM(quantity), 0) as calculated_stock '
      'FROM stock_movements WHERE product_id = ?',
      variables: [Variable(productId)],
      readsFrom: {_db.stockMovements},
    ).getSingle();

    return (result.data['calculated_stock'] as num?)?.toDouble() ?? 0.0;
  }

  @override
  Future<void> updateProductSortOrders(List<int> productIds) =>
      _db.updateProductSortOrders(productIds);

  @override
  Future<List<db.Product>> getScaleProducts() => _db.getScaleProducts();

  @override
  Future<List<db.WarehousePrice>> getWarehousePricesForProduct(int productId) =>
      _db.getWarehousePricesForProduct(productId);

  @override
  Future<db.WarehousePrice?> getWarehousePrice(int productId, int warehouseId) =>
      _db.getWarehousePrice(productId, warehouseId);

  @override
  Future<void> upsertWarehousePrice({
    required int productId,
    required int warehouseId,
    required double salePrice,
    required double costPrice,
    required double wholesalePrice,
    String? notes,
  }) =>
      _db.upsertWarehousePrice(
        productId: productId,
        warehouseId: warehouseId,
        salePrice: salePrice,
        costPrice: costPrice,
        wholesalePrice: wholesalePrice,
        notes: notes,
      );

  @override
  Future<void> deleteWarehousePrice(int id) => _db.deleteWarehousePrice(id);

  @override
  Future<List<db.ModifierGroupWithItems>> getProductModifiers(int productId) =>
      _db.getProductModifiers(productId);

  @override
  Future<bool> productHasModifiers(int productId) =>
      _db.productHasModifiers(productId);

  @override
  Future<List<db.Unit>> getAllUnits() => _db.select(_db.units).get();

  @override
  Future<List<db.ProductUnit>> getProductUnits(int productId) =>
      (_db.select(_db.productUnits)..where((u) => u.productId.equals(productId))).get();

  @override
  Future<int> insertProductUnit(db.ProductUnitsCompanion productUnit) =>
      _db.into(_db.productUnits).insert(productUnit);

  @override
  Future<bool> updateProductUnit(db.ProductUnit productUnit) =>
      _db.update(_db.productUnits).replace(productUnit);

  @override
  Future<bool> deleteProductUnit(int id) =>
      (_db.delete(_db.productUnits)..where((u) => u.id.equals(id))).go().then((count) => count > 0);

  @override
  Future<int> deleteProductUnits(int productId) =>
      (_db.delete(_db.productUnits)..where((u) => u.productId.equals(productId))).go();

  @override
  Future<int> insertUnit(db.UnitsCompanion unit) => _db.into(_db.units).insert(unit);

  @override
  Future<bool> updateUnit(db.Unit unit) => _db.update(_db.units).replace(unit);

  @override
  Future<bool> deleteUnit(int id) =>
      (_db.delete(_db.units)..where((u) => u.id.equals(id))).go().then((count) => count > 0);

  @override
  Future<Map<int, String>> getBaseUnitNameMap() => _db.getBaseUnitNameMap();
}
