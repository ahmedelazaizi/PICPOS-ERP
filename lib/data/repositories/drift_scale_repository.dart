import 'package:drift/drift.dart';
import '../../domain/repositories/scale_repository.dart';
import '../../services/label_scale_service.dart';
import '../database/database.dart';

class DriftScaleRepository implements IScaleRepository {
  final AppDatabase _db;
  final LabelScaleService _scaleService = LabelScaleService.instance;

  DriftScaleRepository(this._db);

  // --- Label Scale Registry ---
  @override
  Future<List<LabelScale>> getAllScales() => _db.getAllLabelScales();

  @override
  Stream<List<LabelScale>> watchAllScales() => _db.watchAllLabelScales();

  @override
  Future<LabelScale?> getScaleById(int id) => _db.getLabelScaleById(id);

  @override
  Future<int> saveScale(LabelScale scale) async {
    final companion = LabelScalesCompanion(
      id: Value(scale.id),
      name: Value(scale.name),
      brand: Value(scale.brand),
      connectionType: Value(scale.connectionType),
      ipAddress: Value(scale.ipAddress),
      port: Value(scale.port),
      comPort: Value(scale.comPort),
      baudRate: Value(scale.baudRate),
      dataBits: Value(scale.dataBits),
      parity: Value(scale.parity),
      stopBits: Value(scale.stopBits),
      handShake: Value(scale.handShake),
      maxPlu: Value(scale.maxPlu),
      ftpUsername: Value(scale.ftpUsername),
      ftpPassword: Value(scale.ftpPassword),
      isActive: Value(scale.isActive),
    );
    
    if (scale.id == 0) {
      // New scale - id 0 is auto-increment
      final newCompanion = companion.copyWith(id: const Value.absent());
      return _db.insertLabelScale(newCompanion);
    } else {
      await _db.updateLabelScale(scale);
      return scale.id;
    }
  }

  @override
  Future<void> deleteScale(int id) => _db.deleteLabelScale(id);

  @override
  Future<void> updateScaleStatus(int id, bool isActive) =>
      _db.updateLabelScaleStatus(id, isActive);

  // --- Support Methods for PLU Manager ---
  @override
  Future<List<Category>> getAllCategories() => _db.getAllCategories();

  @override
  Future<List<Product>> getAllActiveProducts() => _db.getAllProducts();

  // --- Product PLU Mapping ---
  @override
  Future<List<Product>> getProductsForScale() => _db.getScaleProducts();

  @override
  Future<Product?> getProductByPlu(int plu) => _db.getProductByScalePlu(plu);

  @override
  Future<void> updateProductPlu(int productId, {int? pluNumber, bool? isSoldByWeight}) =>
      _db.updateProductScalePlu(productId, pluNumber: pluNumber, isSoldByWeight: isSoldByWeight);

  @override
  Future<void> clearProductPlu(int productId) => _db.clearProductScalePlu(productId);

  @override
  Future<void> bulkUpdatePlu(Map<int, int?> pluMap) async {
    await _db.transaction(() async {
      for (var entry in pluMap.entries) {
        await _db.updateProductScalePlu(entry.key, pluNumber: entry.value);
      }
    });
  }

  // --- Synchronization & Testing ---
  @override
  Future<Map<String, dynamic>> testConnection(LabelScale scale) =>
      _scaleService.testScaleRecord(scale);

  @override
  Future<PLUUploadResult> syncToScale(LabelScale scale, List<ScalePLUItem> items) =>
      _scaleService.uploadToScaleRecord(scale: scale, items: items);

  @override
  Future<bool> clearScaleMemory(LabelScale scale) =>
      _scaleService.clearScaleRecord(scale);
}
