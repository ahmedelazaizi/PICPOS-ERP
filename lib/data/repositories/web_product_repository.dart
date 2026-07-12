import '../../domain/entities/product_entity.dart';
import '../../domain/repositories/i_products_repository.dart';
import '../database/database_barrel.dart' as db;

// Provides Web implementation ensuring the interface is respected.
// Currently wraps the stub behavior but sets the stage for real Supabase calls.
class WebProductRepository implements IProductRepository {
  final db.AppDatabase _db;

  WebProductRepository(this._db);

  @override
  Stream<List<ProductEntity>> watchAllProducts() {
    return const Stream.empty(); // Web stub
  }

  @override
  Stream<List<ProductEntity>> watchInventoryProducts({
    int limit = 1500,
    String? search,
    int? categoryId,
    bool lowStockOnly = false,
    Iterable<int>? restrictToIds,
  }) {
    return const Stream.empty(); // Web stub (Spec 136 ISS-9)
  }

  @override
  Stream<({int activeCount, int lowStockCount, double totalValue})>
      watchInventorySummary() {
    return Stream.value((activeCount: 0, lowStockCount: 0, totalValue: 0.0));
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
    return const []; // Web stub (Spec 136 ISS-9b)
  }

  @override
  Stream<List<ProductEntity>> watchPosProducts({
    Iterable<int>? categoryIds,
    String? search,
    int limit = 600,
    bool includeUncategorized = false,
  }) {
    return const Stream.empty(); // Web stub (Spec 136 ISS-12)
  }

  @override
  Future<T> runInWriteTransaction<T>(Future<T> Function() action) => action();

  @override
  Future<List<ProductEntity>> getProducts({
    int limit = 20,
    int offset = 0,
    String? query,
    int? categoryId,
  }) async {
    return []; // Stub
  }

  @override
  Stream<List<ProductEntity>> searchProducts(String query) {
    return const Stream.empty(); // Web stub
  }

  @override
  Future<ProductEntity?> getProductById(int id) async {
    return null; // Web stub
  }

  @override
  Future<List<ProductEntity>> getProductsByIds(List<int> ids) async {
    return const []; // Web stub
  }

  @override
  Future<ProductEntity?> getProductByCode(String code) async {
    return null; // Web stub
  }

  @override
  Future<List<db.ProductBarcode>> getProductBarcodes(int productId) {
    return _db.getProductBarcodes(productId);
  }

  @override
  Future<List<db.ProductBarcode>> getAllProductBarcodes() async => const [];

  @override
  Stream<List<ProductEntity>> watchLowStockProducts() {
    return const Stream.empty(); // Web stub
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
  Future<int> insertProduct(db.ProductsCompanion product) async {
    // Web stub - direct return to avoid native DB signature mismatch during analysis
    return 0;
  }

  @override
  Future<bool> updateProduct(db.Product product) async {
    // Web stub - direct return
    return true;
  }

  @override
  Future<void> deleteProduct(int id) async {
    // Web stub - direct return
  }

  @override
  Future<List<db.Category>> getCategories() async => [];

  @override
  Future<List<db.Party>> getSuppliers() async => [];

  @override
  Future<bool> productCodeExists(String code, {int? excludeProductId}) async =>
      false;

  @override
  Future<bool> barcodeExists(String barcode, {int? excludeProductId}) async =>
      false;

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
  Future<void> insertCategoryWithPrinter({
    required String name,
    required String color,
    int? printerId,
    String? iconName,
    bool isGlobal = true,
    List<int> branchIds = const [],
  }) async {}

  @override
  Future<void> updateCategoryWithPrinter({
    required int id,
    required String name,
    required String color,
    int? printerId,
    String? iconName,
    bool isGlobal = true,
    List<int> branchIds = const [],
  }) async {}

  @override
  Future<int> countActiveProductsInCategory(int categoryId) async => 0;

  @override
  Future<int> countCategoryInvoicedItemsOnBranch(
    int categoryId,
    int branchId,
  ) async => 0;

  @override
  Future<void> deleteCategory(int id, {int? moveToCategoryId}) async {}

  @override
  Future<void> setCategoryLocked(int categoryId, bool isLocked) async {}

  @override
  Future<void> excludeCategoryWithAllProducts(int categoryId) async {}

  @override
  Future<void> unexcludeCategoryWithAllProducts(int categoryId) async {}

  @override
  Future<void> setCategoryShowInPos(int categoryId, bool showInPos) async {}

  @override
  Future<List<db.Product>> getAllProducts() async => [];

  @override
  Future<List<ProductEntity>> getLowStockProducts() async => [];

  @override
  Stream<List<db.Category>> watchAllCategories() => const Stream.empty();

  @override
  Future<void> updateCategorySortOrders(List<int> categoryIds) async {}

  @override
  Future<bool> updateProductFromEntity(ProductEntity entity) async => false;

  @override
  Future<void> updateProductPrices(int productId, {required double costPrice, required double salePrice}) async {}

  @override
  Future<String> getNextProductCode() async => '10000001';

  @override
  Future<int> insertProductBarcode(int productId, String barcode, {bool isPrimary = false}) async => 0;

  @override
  Future<void> createDefaultProductUnits(int productId, {double piecePrice = 0, double pieceCost = 0, String? pieceBarcode}) async {}

  // ═══════════════════════════════════════════════════════════════════════════
  // Missing interface stubs
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Future<ProductEntity?> getProductAnyStatusByBarcode(String barcode) async => null;

  @override
  Future<ProductEntity?> getProductByScalePlu(int pluNumber) async => null;

  @override
  Future<ProductEntity?> getProductByBarcode(String barcode) async => null;

  @override
  Future<int> getOrCreateCategory(String name) async => 0;

  @override
  Future<db.Category?> getCategoryById(int id) async => null;

  @override
  Future<List<db.Product>> getInventoryProducts() async => [];

  @override
  Future<double> getCalculatedStock(int productId) async => 0;

  @override
  Future<void> updateProductSortOrders(List<int> productIds) async {}

  @override
  Future<List<db.Product>> getScaleProducts() async => [];

  @override
  Future<List<db.WarehousePrice>> getWarehousePricesForProduct(int productId) async => [];

  @override
  Future<db.WarehousePrice?> getWarehousePrice(int productId, int warehouseId) async => null;

  @override
  Future<void> upsertWarehousePrice({
    required int productId,
    required int warehouseId,
    required double salePrice,
    required double costPrice,
    required double wholesalePrice,
    String? notes,
  }) async {}

  @override
  Future<void> deleteWarehousePrice(int id) async {}

  @override
  Future<List<db.ModifierGroupWithItems>> getProductModifiers(int productId) async => [];

  @override
  Future<bool> productHasModifiers(int productId) async => false;

  @override
  Future<List<db.Unit>> getAllUnits() async => [];

  @override
  Future<List<db.ProductUnit>> getProductUnits(int productId) async => [];

  @override
  Future<int> insertProductUnit(db.ProductUnitsCompanion productUnit) async => 0;

  @override
  Future<bool> updateProductUnit(db.ProductUnit productUnit) async => true;

  @override
  Future<bool> deleteProductUnit(int id) async => true;

  @override
  Future<int> deleteProductUnits(int productId) async => 0;

  @override
  Future<int> insertUnit(db.UnitsCompanion unit) async => 0;

  @override
  Future<bool> updateUnit(db.Unit unit) async => true;

  @override
  Future<bool> deleteUnit(int id) async => true;

  @override
  Future<Map<int, String>> getBaseUnitNameMap() async => {};

  @override
  Future<List<int>> getCategoryBranchIds(int categoryId) async => [];

  @override
  Stream<List<db.Category>> watchCategoriesForBranch(int branchId) => const Stream.empty();

  @override
  Future<int> quickAddProduct({
    required String name,
    required double salePrice,
    String? barcode,
    int? categoryId,
    bool allowNegativeSale = false,
  }) async => 0; // Web stub
}
