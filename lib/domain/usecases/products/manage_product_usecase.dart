import '../../repositories/products_repository.dart';

/// Use case: Create, update, or delete a product with validation.
///
/// Ensures product name, price, and code are valid before persisting.
class ManageProductUseCase {
  final ProductsRepository _repo;

  const ManageProductUseCase(this._repo);

  /// Creates a new product.
  Future<int> create(CreateProductParams params) async {
    _validateParams(params.name, params.salePrice);
    return _repo.createProduct(params);
  }

  /// Updates an existing product.
  Future<void> update(int id, UpdateProductParams params) async {
    if (id <= 0) {
      throw ArgumentError('معرّف المنتج غير صحيح');
    }
    if (params.name != null) {
      _validateName(params.name!);
    }
    return _repo.updateProduct(id, params);
  }

  /// Deletes a product after verifying it exists.
  Future<void> delete(int id) async {
    if (id <= 0) {
      throw ArgumentError('معرّف المنتج غير صحيح');
    }
    final product = await _repo.getProductById(id);
    if (product == null) {
      throw StateError('المنتج غير موجود');
    }
    return _repo.deleteProduct(id);
  }

  void _validateParams(String name, double price) {
    _validateName(name);
    if (price < 0) {
      throw ArgumentError('سعر المنتج لا يمكن أن يكون سالباً');
    }
  }

  void _validateName(String name) {
    if (name.trim().isEmpty) {
      throw ArgumentError('اسم المنتج مطلوب');
    }
    if (name.trim().length < 2) {
      throw ArgumentError('اسم المنتج يجب أن يكون حرفين على الأقل');
    }
  }
}
