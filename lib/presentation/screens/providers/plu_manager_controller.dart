import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/repositories/scale_repository.dart';
import '../../../domain/repositories/i_products_repository.dart';
import '../../../data/database/database.dart';
import '../../../data/providers/repository_providers.dart';

class PluManagerController {
  final IScaleRepository _repo;
  final IProductRepository _productRepo;
  PluManagerController(this._repo, this._productRepo);

  Future<List<Product>> getAllProducts() => _repo.getAllActiveProducts();
  Future<List<Category>> getAllCategories() => _repo.getAllCategories();
  
  Future<Product?> getProductByScalePlu(int plu) => _repo.getProductByPlu(plu);
  
  Future<void> updateProductScalePlu(
    int id, {
    int? pluNumber,
    bool? isSoldByWeight,
  }) => _repo.updateProductPlu(id, pluNumber: pluNumber, isSoldByWeight: isSoldByWeight);
  
  Future<void> clearProductScalePlu(int id) => _repo.clearProductPlu(id);

  Future<Product?> getProductByCode(String code) async {
    final entity = await _productRepo.getProductByCode(code);
    if (entity == null) return null;
    // LOW-9: getAllProducts() is ACTIVE-only; an inactive match used to make
    // firstWhere throw and abort the whole CSV import on one row. Return null
    // gracefully (matches the Future<Product?> contract) so the row is skipped.
    return _firstActiveOrNull((p) => p.code == entity.code);
  }

  Future<Product?> getProductByBarcode(String barcode) async {
    final entity = await _productRepo.getProductByBarcode(barcode);
    if (entity == null) return null;
    // We need to return the Product object that matches this barcode.
    // Since the Product object in Drift doesn't have a barcode field (it's in
    // the product_barcodes table) we fetch by ID from the entity.
    // LOW-9: null-safe — an inactive product no longer aborts the import.
    return _firstActiveOrNull((p) => p.id == entity.id);
  }

  /// LOW-9: first ACTIVE product matching [test], or null (never throws).
  Future<Product?> _firstActiveOrNull(bool Function(Product) test) async {
    final matches = (await getAllProducts()).where(test);
    return matches.isEmpty ? null : matches.first;
  }

  Future<List<Product>> searchProducts(String query) async {
    final entities = await _productRepo.getProducts(query: query, limit: 100);
    final all = await getAllProducts();
    final ids = entities.map((e) => e.id).toSet();
    return all.where((p) => ids.contains(p.id)).toList();
  }

  Future<Product?> getProductById(int id) async {
    // LOW-9: null-safe — an id absent from the active set returns null, not throw.
    return _firstActiveOrNull((p) => p.id == id);
  }

  Future<List<Product>> getScaleProducts() => _repo.getProductsForScale();
}

final pluManagerControllerProvider = Provider(
  (ref) => PluManagerController(
    ref.watch(scaleRepositoryProvider),
    ref.watch(productRepositoryProvider),
  ),
);
