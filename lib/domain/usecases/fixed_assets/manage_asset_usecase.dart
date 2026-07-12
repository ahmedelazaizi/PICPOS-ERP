import '../../../data/database/database.dart';

/// Input for creating or updating a fixed asset
class AssetInput {
  final String code;
  final String name;
  final int categoryId;
  final String? location;
  final double purchasePrice;
  final DateTime purchaseDate;
  final double usefulLifeYears;
  final double salvageValue;
  final String depreciationMethod;
  final String? notes;
  final int? costCenterId;

  AssetInput({
    required this.code,
    required this.name,
    required this.categoryId,
    this.location,
    required this.purchasePrice,
    required this.purchaseDate,
    required this.usefulLifeYears,
    this.salvageValue = 0,
    this.depreciationMethod = 'straight_line',
    this.notes,
    this.costCenterId,
  });
}

/// Input for disposing of an asset
class DisposeAssetInput {
  final int assetId;
  final double disposalValue;
  final DateTime disposalDate;
  final int? costCenterId;

  DisposeAssetInput({
    required this.assetId,
    required this.disposalValue,
    required this.disposalDate,
    this.costCenterId,
  });
}

/// Result of asset operations
class AssetResult {
  final bool isSuccess;
  final int? assetId;
  final String? error;

  AssetResult.success([this.assetId]) : isSuccess = true, error = null;
  AssetResult.failure(this.error) : isSuccess = false, assetId = null;
}

/// Use case: Create, dispose, and revalue fixed assets (IAS 16)
class ManageAssetUseCase {
  final AppDatabase _db;

  ManageAssetUseCase(this._db);

  /// Create a fixed asset with acquisition journal entry
  Future<AssetResult> createAsset(AssetInput input) async {
    if (input.code.trim().isEmpty) return AssetResult.failure('يجب إدخال كود الأصل');
    if (input.name.trim().isEmpty) return AssetResult.failure('يجب إدخال اسم الأصل');
    if (input.purchasePrice <= 0) return AssetResult.failure('سعر الشراء يجب أن يكون أكبر من صفر');
    if (input.usefulLifeYears <= 0) return AssetResult.failure('العمر الإنتاجي يجب أن يكون أكبر من صفر');
    if (input.salvageValue >= input.purchasePrice) {
      return AssetResult.failure('قيمة الخردة يجب أن تكون أقل من سعر الشراء');
    }

    try {
      final id = await _db.createFixedAsset(
        code: input.code,
        name: input.name,
        categoryId: input.categoryId,
        location: input.location,
        purchasePrice: input.purchasePrice,
        purchaseDate: input.purchaseDate,
        usefulLifeYears: input.usefulLifeYears,
        salvageValue: input.salvageValue,
        depreciationMethod: input.depreciationMethod,
        notes: input.notes,
        costCenterId: input.costCenterId,
      );
      return AssetResult.success(id);
    } catch (e) {
      return AssetResult.failure(e.toString());
    }
  }

  /// Dispose of an asset (sell or write-off) with journal entry
  Future<AssetResult> disposeAsset(DisposeAssetInput input) async {
    try {
      await _db.disposeAsset(
        input.assetId,
        disposalValue: input.disposalValue,
        disposalDate: input.disposalDate,
        costCenterId: input.costCenterId,
      );
      return AssetResult.success(input.assetId);
    } catch (e) {
      return AssetResult.failure(e.toString());
    }
  }

  /// Revalue an asset (IAS 16.31 — Revaluation Model)
  Future<AssetResult> revalueAsset(int assetId, double newFairValue, {int? costCenterId}) async {
    if (newFairValue <= 0) return AssetResult.failure('القيمة العادلة يجب أن تكون أكبر من صفر');

    try {
      await _db.revalueAsset(
        assetId,
        newFairValue: newFairValue,
        costCenterId: costCenterId,
      );
      return AssetResult.success(assetId);
    } catch (e) {
      return AssetResult.failure(e.toString());
    }
  }
}
