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
  
  // ── طلبُ الاستبعاد (v175 / المرحلة ٧) ────────────────────────────────
  //
  // ⚠️ **مستندٌ له دورةُ حياةٍ بخلاف [disposeAsset]**: تلك تنفّذ فوراً بلا
  //    مسوّدةٍ ولا مراجعة، وهذه تحفظ طلباً ثمّ يُعتمَد — والأثرُ المحاسبيُّ
  //    عند الاعتماد وحدَه.

  Stream<List<AssetDisposalData>> watchAssetDisposals();
  Future<List<AssetDisposalListRow>> getAssetDisposalRows();
  Future<AssetDisposalData?> getOpenDisposalForAsset(int assetId);

  Future<int> createAssetDisposalRequest({
    required int assetId,
    required DateTime disposalDate,
    required String method,
    required double disposalValue,
    required String collectionMethod,
    required String reason,
    int? buyerPartyId,
    int? safeId,
    int? costCenterId,
    int? createdBy,
  });

  Future<void> updateAssetDisposalRequest({
    required int id,
    required DateTime disposalDate,
    required String method,
    required double disposalValue,
    required String collectionMethod,
    required String reason,
    int? buyerPartyId,
    int? safeId,
    int? costCenterId,
  });

  Future<void> cancelAssetDisposalRequest(int id);

  /// 🔴 الأثرُ المحاسبيُّ كلُّه هنا. [safeId] لازمٌ للبيع النقديِّ وحدَه.
  Future<void> approveAssetDisposal(
    int id, {
    int? safeId,
    int? approvedBy,
    String? approvedByName,
  });

  Future<List<AssetDepreciationData>> getAssetDepreciationSchedule(int assetId);
  Future<List<FixedAssetData>> getFixedAssetsList();
  Future<Map<String, double>> getAssetsSummary();
}
