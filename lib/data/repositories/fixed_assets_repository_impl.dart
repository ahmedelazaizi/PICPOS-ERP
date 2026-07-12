import '../database/database.dart';
import '../../domain/repositories/fixed_assets_repository.dart';

class FixedAssetsRepositoryImpl implements IFixedAssetsRepository {
  final AppDatabase _db;

  FixedAssetsRepositoryImpl(this._db);

  @override
  Stream<List<FixedAssetData>> watchFixedAssets() => _db.watchFixedAssets();

  @override
  Stream<List<AssetCategory>> watchAssetCategories() => _db.watchAssetCategories();

  @override
  Stream<List<AssetDepreciationData>> watchAllDepreciations() => _db.watchAllDepreciations();

  @override
  Stream<List<AssetDepreciationData>> watchDepreciationHistory(int assetId) =>
      _db.watchDepreciationHistory(assetId);

  @override
  Future<List<AssetCategory>> getAssetCategoriesList() => _db.getAssetCategoriesList();

  @override
  Future<void> createAssetCategory({
    required String name,
    double? defaultUsefulLife,
    String? defaultDepreciationMethod,
    int? accountId,
    int? depreciationAccountId,
  }) => _db.createAssetCategory(
        name: name,
        defaultUsefulLife: defaultUsefulLife ?? 0.0,
        defaultDepreciationMethod: defaultDepreciationMethod ?? 'straight_line',
        accountId: accountId,
        depreciationAccountId: depreciationAccountId,
      );

  @override
  Future<void> updateAssetCategoryById(int id, {
    required String name,
    int? accountId,
    int? depreciationAccountId,
    double? defaultUsefulLife,
    String? defaultDepreciationMethod,
  }) => _db.updateAssetCategoryById(id,
        name: name,
        accountId: accountId,
        depreciationAccountId: depreciationAccountId,
        defaultUsefulLife: defaultUsefulLife,
        defaultDepreciationMethod: defaultDepreciationMethod,
      );

  @override
  Future<int> createFixedAsset({
    required String code,
    required String name,
    required int categoryId,
    String? location,
    required double purchasePrice,
    required DateTime purchaseDate,
    required double usefulLifeYears,
    double salvageValue = 0,
    String depreciationMethod = 'straight_line',
    String? notes,
    int? costCenterId,
    int? contraAccountId,
  }) => _db.createFixedAsset(
        code: code,
        name: name,
        categoryId: categoryId,
        location: location,
        purchasePrice: purchasePrice,
        purchaseDate: purchaseDate,
        usefulLifeYears: usefulLifeYears,
        salvageValue: salvageValue,
        depreciationMethod: depreciationMethod,
        notes: notes,
        costCenterId: costCenterId,
        contraAccountId: contraAccountId,
      );

  @override
  Future<void> updateFixedAsset(
    int assetId, {
    String? name,
    String? location,
    double? salvageValue,
    String? notes,
    int? costCenterId,
    bool clearCostCenter = false,
  }) => _db.updateFixedAsset(
        assetId,
        name: name,
        location: location,
        salvageValue: salvageValue,
        notes: notes,
        costCenterId: costCenterId,
        clearCostCenter: clearCostCenter,
      );

  @override
  Future<void> deleteFixedAsset(int id) => _db.deleteFixedAsset(id);

  @override
  Future<int> runMonthlyDepreciation(DateTime periodDate, {int? costCenterId}) =>
      _db.runMonthlyDepreciation(periodDate, costCenterId: costCenterId);

  @override
  Future<void> revalueAsset(int assetId, {required double newFairValue, int? costCenterId}) =>
      _db.revalueAsset(assetId, newFairValue: newFairValue, costCenterId: costCenterId);

  @override
  Future<void> disposeAsset(int assetId, {required double disposalValue, required DateTime disposalDate, int? costCenterId}) =>
      _db.disposeAsset(assetId, disposalValue: disposalValue, disposalDate: disposalDate, costCenterId: costCenterId);

  @override
  Future<List<AssetDepreciationData>> getAssetDepreciationSchedule(int assetId) =>
      _db.getAssetDepreciationSchedule(assetId);

  @override
  Future<List<FixedAssetData>> getFixedAssetsList() => _db.getFixedAssetsList();

  @override
  Future<Map<String, double>> getAssetsSummary() => _db.getAssetsSummary();
}
