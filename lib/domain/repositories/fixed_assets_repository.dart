import '../../data/database/database.dart';

abstract class IFixedAssetsRepository {
  Stream<List<FixedAssetData>> watchFixedAssets();
  Stream<List<AssetCategory>> watchAssetCategories();
  Stream<List<AssetDepreciationData>> watchAllDepreciations();
  Stream<List<AssetDepreciationData>> watchDepreciationHistory(int assetId);
  
  Future<List<AssetCategory>> getAssetCategoriesList();
  Future<void> createAssetCategory({
    required String name,
    double? defaultUsefulLife,
    String? defaultDepreciationMethod,
    int? accountId,
    int? depreciationAccountId,
  });
  Future<void> updateAssetCategoryById(int id, {
    required String name,
    int? accountId,
    int? depreciationAccountId,
    double? defaultUsefulLife,
    String? defaultDepreciationMethod,
  });

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
  });
  Future<void> updateFixedAsset(
    int assetId, {
    String? name,
    String? location,
    double? salvageValue,
    String? notes,
    int? costCenterId,
    bool clearCostCenter = false,
    int? custodianUserId,
    bool clearCustodian = false,
  });
  Future<void> deleteFixedAsset(int id);

  /// حالةُ الأصول **كما في تاريخ** — مفتاحُها رقمُ الأصل، وأصلٌ بلا صفِّ
  /// إهلاكٍ حتى التاريخ يغيب عنها.
  Future<Map<int, ({double accumulated, double bookValue, double cost})>>
      getAssetSnapshotsAsOf(DateTime asOf);

  /// قيودُ الأصل — بالأنواع المعلَنة في `kAssetJeReferenceTypes`.
  Future<List<JournalEntryData>> getAssetMovements(int assetId);
  
  Future<int> runMonthlyDepreciation(DateTime periodDate, {int? costCenterId});
  Future<void> revalueAsset(int assetId, {required double newFairValue, int? costCenterId});
  Future<void> disposeAsset(int assetId, {required double disposalValue, required DateTime disposalDate, int? costCenterId});
  
  Future<List<AssetDepreciationData>> getAssetDepreciationSchedule(int assetId);
  Future<List<FixedAssetData>> getFixedAssetsList();
  Future<Map<String, double>> getAssetsSummary();
}
