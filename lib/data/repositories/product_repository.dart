import 'package:drift/drift.dart' show OrderingTerm;
import '../database/database.dart';
import 'base_repository.dart';

/// Repository for product-related operations
class ProductRepository extends BaseRepository<Product> {
  ProductRepository(super.db);

  @override
  Stream<List<Product>> watchAll() => db.watchAllProducts();

  /// Get all products as a list
  Future<List<Product>> getAll() => db.getAllProducts();

  @override
  Future<Product?> getById(int id) async {
    return (db.select(
      db.products,
    )..where((p) => p.id.equals(id))).getSingleOrNull();
  }

  /// Watch products (filter low stock in the UI layer)
  Stream<List<Product>> watchLowStock() => db.watchAllProducts();

  /// Get product by barcode
  Future<Product?> getByBarcode(String barcode) =>
      db.getProductByBarcode(barcode);

  /// Get product by unit barcode
  Future<Product?> getByUnitBarcode(String barcode) =>
      db.getProductByUnitBarcode(barcode);

  /// Insert new product
  Future<int> insert(ProductsCompanion product) => db.insertProduct(product);

  /// Update product
  Future<bool> update(Product product) => db.updateProduct(product);

  /// Delete product (soft delete)
  Future<void> delete(int id) => db.deleteProduct(id);

  /// Insert category
  Future<void> insertCategoryWithPrinter({
    required String name,
    required String color,
    int? printerId,
    String? iconName,
  }) => db.insertCategoryWithPrinter(
    name: name,
    color: color,
    printerId: printerId,
    iconName: iconName,
  );

  /// Update category
  Future<void> updateCategoryWithPrinter({
    required int id,
    required String name,
    required String color,
    int? printerId,
    String? iconName,
  }) => db.updateCategoryWithPrinter(
    id: id,
    name: name,
    color: color,
    printerId: printerId,
    iconName: iconName,
  );

  /// Count active products assigned to a category (Feature 045).
  Future<int> countActiveProductsInCategory(int id) =>
      db.countActiveProductsInCategory(id);

  /// Count category invoice items booked on a specific branch — used by
  /// the delete-category UI to warn before a global propagation.
  Future<int> countCategoryInvoicedItemsOnBranch(int id, int branchId) =>
      db.countCategoryInvoicedItemsOnBranch(id, branchId);

  /// Soft-delete a category, optionally bulk-moving active products to
  /// [moveToCategoryId] first (null = uncategorized). Feature 045.
  Future<void> deleteCategory(int id, {int? moveToCategoryId}) =>
      db.deleteCategory(id, moveToCategoryId: moveToCategoryId);

  /// Lock category
  Future<void> setCategoryLocked(int categoryId, bool isLocked) =>
      db.setCategoryLocked(categoryId, isLocked);

  /// Exclude category
  Future<void> excludeCategoryWithAllProducts(int categoryId) =>
      db.excludeCategoryWithAllProducts(categoryId);

  /// Unexclude category
  Future<void> unexcludeCategoryWithAllProducts(int categoryId) =>
      db.unexcludeCategoryWithAllProducts(categoryId);

  @override
  Future<void> setCategoryShowInPos(int categoryId, bool showInPos) =>
      db.setCategoryShowInPos(categoryId, showInPos);

  /// Reorder categories
  Future<void> updateCategorySortOrders(List<int> categoryIds) =>
      db.updateCategorySortOrders(categoryIds);

  /// Get all product units
  Future<List<ProductUnit>> getUnits(int productId) =>
      db.getProductUnits(productId);

  /// Watch product units
  Stream<List<ProductUnit>> watchUnits(int productId) =>
      db.watchProductUnits(productId);

  /// Insert product unit
  Future<int> insertUnit(ProductUnitsCompanion unit) =>
      db.insertProductUnit(unit);

  /// Update product stock
  Future<void> adjustStock({
    required int productId,
    required double quantity,
    int? warehouseId,
    String? notes,
  }) => db.adjustStock(
    productId: productId,
    warehouseId: warehouseId ?? 1,
    quantity: quantity,
    notes: notes,
  );

  /// Get next product code (8-digit format starting from 10000001 to avoid barcode conflicts)
  Future<String> getNextProductCode() async {
    const int baseCode = 10000000; // Start from 10 million

    // Get the product with the highest numeric code
    final products =
        await (db.select(db.products)
              ..orderBy([(p) => OrderingTerm.desc(p.id)])
              ..limit(100)) // Check last 100 products
            .get();

    int maxCode = baseCode;

    for (final p in products) {
      final codeInt = int.tryParse(p.code);
      if (codeInt != null && codeInt >= baseCode && codeInt > maxCode) {
        maxCode = codeInt;
      }
    }

    return (maxCode + 1).toString();
  }
}
