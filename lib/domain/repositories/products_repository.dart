import '../entities/product_entity.dart';

/// Products repository interface
///
/// Defines contract for product operations. Implementations in data layer.
abstract class ProductsRepository {
  /// Get all active products
  Future<List<ProductEntity>> getAllProducts();

  /// Watch all active products
  Stream<List<ProductEntity>> watchProducts();

  /// Get product by ID
  Future<ProductEntity?> getProductById(int id);

  /// Get product by barcode
  Future<ProductEntity?> getProductByBarcode(String barcode);

  /// Get product by code
  Future<ProductEntity?> getProductByCode(String code);

  /// Search products by name or code
  Future<List<ProductEntity>> searchProducts(String query);

  /// Get products by category
  Future<List<ProductEntity>> getProductsByCategory(int categoryId);

  /// Get low stock products
  Future<List<ProductEntity>> getLowStockProducts();

  /// Create new product
  Future<int> createProduct(CreateProductParams params);

  /// Update product
  Future<void> updateProduct(int id, UpdateProductParams params);

  /// Delete (deactivate) product
  Future<void> deleteProduct(int id);

  /// Adjust stock
  Future<void> adjustStock(int productId, double quantity, {String? notes});

  /// Update stock after sale
  Future<void> decreaseStock(int productId, double quantity);

  /// Update stock after purchase
  Future<void> increaseStock(int productId, double quantity);
}

/// Parameters for creating a product
class CreateProductParams {
  final String code;
  final String name;
  final int? categoryId;
  final double salePrice;
  final double costPrice;
  final double? pricePerUnit;
  final double initialStock;
  final double minStock;
  final bool trackInventory;
  final bool trackExpiry;
  final bool isSoldByWeight;
  final String? description;
  final String? barcode;

  const CreateProductParams({
    required this.code,
    required this.name,
    this.categoryId,
    required this.salePrice,
    required this.costPrice,
    this.pricePerUnit,
    this.initialStock = 0,
    this.minStock = 0,
    this.trackInventory = true,
    this.trackExpiry = false,
    this.isSoldByWeight = false,
    this.description,
    this.barcode,
  });
}

/// Parameters for updating a product
class UpdateProductParams {
  final String? code;
  final String? name;
  final int? categoryId;
  final double? salePrice;
  final double? costPrice;
  final double? pricePerUnit;
  final double? minStock;
  final bool? trackInventory;
  final bool? trackExpiry;
  final bool? isSoldByWeight;
  final String? description;
  final String? barcode;
  final bool? isActive;

  const UpdateProductParams({
    this.code,
    this.name,
    this.categoryId,
    this.salePrice,
    this.costPrice,
    this.pricePerUnit,
    this.minStock,
    this.trackInventory,
    this.trackExpiry,
    this.isSoldByWeight,
    this.description,
    this.barcode,
    this.isActive,
  });
}
