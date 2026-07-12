import '../../domain/entities/product_entity.dart';
import '../../data/database/database_barrel.dart' as db;

/// Interface for Product Repository
/// Decouples the application from the concrete database implementation (Drift vs Web/Supabase)
abstract class IProductRepository {
  /// Stream of all products for real-time updates
  Stream<List<ProductEntity>> watchAllProducts();

  /// Spec 136 ISS-9 — bounded, DB-filtered stream for the inventory screen
  /// (avoids loading the whole catalog into memory). Filters applied in SQL.
  Stream<List<ProductEntity>> watchInventoryProducts({
    int limit,
    String? search,
    int? categoryId,
    bool lowStockOnly,
    Iterable<int>? restrictToIds,
  });

  /// Spec 136 ISS-9 — cheap SQL aggregate for the inventory summary cards.
  Stream<({int activeCount, int lowStockCount, double totalValue})>
      watchInventorySummary();

  /// Spec 136 ISS-9b — one page (offset-based) of inventory products for
  /// infinite scroll over the full catalog.
  Future<List<ProductEntity>> getInventoryProductsPage({
    required int limit,
    required int offset,
    String? search,
    int? categoryId,
    bool lowStockOnly,
    Iterable<int>? restrictToIds,
  });

  /// Spec 136 ISS-12 — bounded product stream for the POS grid (scoped to the
  /// selected category + descendants or the search term), so POS load and the
  /// post-sale rebuild don't depend on catalog size.
  Stream<List<ProductEntity>> watchPosProducts({
    Iterable<int>? categoryIds,
    String? search,
    int limit,
    bool includeUncategorized,
  });

  /// Spec 136 ISS-11 — run [action] inside a single DB write transaction so
  /// many row writes (e.g. an Excel bulk import) commit atomically AND emit a
  /// single Drift stream notification on commit instead of one per row. Without
  /// this, importing N products fired N `watchAllProducts` emits, each re-
  /// mapping the growing list → O(N²) and a frozen UI.
  Future<T> runInWriteTransaction<T>(Future<T> Function() action);

  /// Get paginated products
  Future<List<ProductEntity>> getProducts({
    int limit = 20,
    int offset = 0,
    String? query,
    int? categoryId,
  });

  /// Search products by query (name or code)
  Stream<List<ProductEntity>> searchProducts(String query);

  /// Get single product by ID
  Future<ProductEntity?> getProductById(int id);

  /// Get multiple products by their IDs in a SINGLE query — avoids N+1
  /// loops when processing a list of invoice items.
  Future<List<ProductEntity>> getProductsByIds(List<int> ids);

  /// Get single product by Code
  Future<ProductEntity?> getProductByCode(String code);

  /// Get single product by Barcode
  Future<ProductEntity?> getProductByBarcode(String barcode);

  /// Get single product by Barcode regardless of status (Diagnostic)
  Future<ProductEntity?> getProductAnyStatusByBarcode(String barcode);

  /// Get single product by Scale PLU Number
  Future<ProductEntity?> getProductByScalePlu(int pluNumber);

  /// Get product barcodes
  Future<List<db.ProductBarcode>> getProductBarcodes(int productId);

  /// Cluster 023 / Issue 9 — fetch every (productId, barcode) pair from
  /// `product_barcodes`. The POS grid loads this once at start so the
  /// in-memory search can match a scanned barcode that lives on a
  /// packaging-unit row (alternate UPC) instead of the primary `barcode`
  /// column on the product itself.
  Future<List<db.ProductBarcode>> getAllProductBarcodes();

  /// Get Low Stock Products
  Stream<List<ProductEntity>> watchLowStockProducts();

  /// Get Low Stock Products Snapshot
  Future<List<ProductEntity>> getLowStockProducts();

  /// Update product stock quantity
  Future<void> updateProductStock(int productId, double newStock);

  /// Create a stock movement record
  Future<int> createStockMovement(db.StockMovementsCompanion movement);

  /// Get Expired Batches
  Future<List<db.ProductBatch>> getExpiredBatches();

  /// Get Expiring Batches within days
  Future<List<db.ProductBatch>> getExpiringBatches(int days);

  /// Watch all categories
  Stream<List<db.Category>> watchAllCategories();

  /// PIR R-10: Watch branch-specific categories
  Stream<List<db.Category>> watchCategoriesForBranch(int branchId);

  /// Get all categories
  Future<List<db.Category>> getCategories();

  /// PIR R-10: Get branches linked to a category
  Future<List<int>> getCategoryBranchIds(int categoryId);

  /// Get or create category by name
  Future<int> getOrCreateCategory(String name);

  /// Get all products (unpaginated, for reports)
  Future<List<db.Product>> getAllProducts();

  /// Get single category by ID
  Future<db.Category?> getCategoryById(int id);

  /// Insert category
  Future<void> insertCategoryWithPrinter({
    required String name,
    required String color,
    int? printerId,
    String? iconName,
    bool isGlobal = true,
    List<int> branchIds = const [],
  });

  /// Update category
  Future<void> updateCategoryWithPrinter({
    required int id,
    required String name,
    required String color,
    int? printerId,
    String? iconName,
    bool isGlobal = true,
    List<int> branchIds = const [],
  });

  /// Count active products currently assigned to a category. Feature 045 —
  /// used by the delete-category UI to choose between an empty-confirm
  /// flow and the bulk-move-then-delete flow.
  Future<int> countActiveProductsInCategory(int categoryId);

  /// Count invoice items (sales + purchases) referencing products in the
  /// given category that were booked on the given branch. Used to warn
  /// operators before propagating a global category delete that would
  /// strip a category actively used on their branch.
  Future<int> countCategoryInvoicedItemsOnBranch(int categoryId, int branchId);

  /// Soft-delete a category. Optionally migrates active products to
  /// [moveToCategoryId] inside the same transaction (null = leave them
  /// uncategorized — `products.categoryId` is nullable). Feature 045.
  Future<void> deleteCategory(int id, {int? moveToCategoryId});

  /// Lock category
  Future<void> setCategoryLocked(int categoryId, bool isLocked);

  /// Exclude category
  Future<void> excludeCategoryWithAllProducts(int categoryId);

  /// Unexclude category
  Future<void> unexcludeCategoryWithAllProducts(int categoryId);

  /// Set category POS visibility (v100)
  Future<void> setCategoryShowInPos(int categoryId, bool showInPos);

  /// Reorder categories
  Future<void> updateCategorySortOrders(List<int> categoryIds);

  /// Get all suppliers
  Future<List<db.Party>> getSuppliers();

  /// Check if code exists
  Future<bool> productCodeExists(String code, {int? excludeProductId});

  /// Check if barcode exists
  Future<bool> barcodeExists(String barcode, {int? excludeProductId});

  /// Log product activity
  Future<void> logActivity({
    required int? userId,
    required String userName,
    required String action,
    required int entityId,
    required String description,
    String? oldValue,
    String? newValue,
  });

  /// CRUD Operations
  Future<int> insertProduct(db.ProductsCompanion product);
  Future<bool> updateProduct(db.Product product);
  Future<bool> updateProductFromEntity(ProductEntity entity);
  Future<void> updateProductPrices(int productId, {required double costPrice, required double salePrice});
  Future<void> deleteProduct(int id);

  /// Get next sequential product code
  Future<String> getNextProductCode();

  /// Quick-add a new product with minimal info (name + price + optional barcode).
  /// Auto-generates the product code. Removes the need for Drift `Companion`
  /// types in the presentation layer (Day 6C refactor).
  ///
  /// Cluster 024 / Issue 8 — `allowNegativeSale` defaults to false but the
  /// POS quick-add dialog passes `true` whenever the install-wide
  /// `enable_negative_sales` setting is ON, so an operator can immediately
  /// sell the just-created product without bouncing to the products screen
  /// to flip the per-product flag.
  Future<int> quickAddProduct({
    required String name,
    required double salePrice,
    String? barcode,
    int? categoryId,
    bool allowNegativeSale = false,
  });

  /// Insert a product barcode
  Future<int> insertProductBarcode(int productId, String barcode, {bool isPrimary});

  /// Create default product units (e.g. "piece")
  Future<void> createDefaultProductUnits(int productId, {double piecePrice, double pieceCost, String? pieceBarcode});

  /// Get products that track inventory
  Future<List<db.Product>> getInventoryProducts();

  /// Get calculated stock quantity from movements (PIR Integrity)
  Future<double> getCalculatedStock(int productId);

  /// Batch update product sort orders
  Future<void> updateProductSortOrders(List<int> productIds);

  /// Get products with scale PLU
  Future<List<db.Product>> getScaleProducts();

  // --- Warehouse Pricing ---
  Future<List<db.WarehousePrice>> getWarehousePricesForProduct(int productId);
  Future<db.WarehousePrice?> getWarehousePrice(int productId, int warehouseId);
  Future<void> upsertWarehousePrice({
    required int productId,
    required int warehouseId,
    required double salePrice,
    required double costPrice,
    required double wholesalePrice,
    String? notes,
  });
  Future<void> deleteWarehousePrice(int id);
  
  /// Get product modifiers
  Future<List<db.ModifierGroupWithItems>> getProductModifiers(int productId);

  /// Check if a product has modifiers
  Future<bool> productHasModifiers(int productId);

  /// Unit CRUD Operations
  Future<List<db.Unit>> getAllUnits();
  Future<List<db.ProductUnit>> getProductUnits(int productId);
  Future<int> insertProductUnit(db.ProductUnitsCompanion productUnit);
  Future<bool> updateProductUnit(db.ProductUnit productUnit);
  Future<bool> deleteProductUnit(int id);
  Future<int> deleteProductUnits(int productId);
  Future<int> insertUnit(db.UnitsCompanion unit);
  Future<bool> updateUnit(db.Unit unit);
  Future<bool> deleteUnit(int id);

  /// Get a map of productId -> base unit name for all products
  Future<Map<int, String>> getBaseUnitNameMap();
}
