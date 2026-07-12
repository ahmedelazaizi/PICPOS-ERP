import '../../services/label_scale_service.dart';
import '../../data/database/database.dart';

abstract class IScaleRepository {
  // --- Label Scale Registry ---
  Future<List<LabelScale>> getAllScales();
  Stream<List<LabelScale>> watchAllScales();
  Future<LabelScale?> getScaleById(int id);
  Future<int> saveScale(LabelScale scale);
  Future<void> deleteScale(int id);
  Future<void> updateScaleStatus(int id, bool isActive);

  // --- Support Methods for PLU Manager ---
  Future<List<Category>> getAllCategories();
  Future<List<Product>> getAllActiveProducts();

  // --- Product PLU Mapping ---
  Future<List<Product>> getProductsForScale();
  Future<Product?> getProductByPlu(int plu);
  Future<void> updateProductPlu(int productId, {int? pluNumber, bool? isSoldByWeight});
  Future<void> clearProductPlu(int productId);
  Future<void> bulkUpdatePlu(Map<int, int?> pluMap);

  // --- Synchronization & Testing ---
  Future<Map<String, dynamic>> testConnection(LabelScale scale);
  Future<PLUUploadResult> syncToScale(LabelScale scale, List<ScalePLUItem> items);
  Future<bool> clearScaleMemory(LabelScale scale);
}
