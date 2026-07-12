import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/usecases/fixed_assets/manage_asset_usecase.dart';
import 'package:ural_erp/domain/usecases/fixed_assets/run_depreciation_usecase.dart';

void main() {
  group('ManageAssetUseCase — AssetInput Validation', () {
    test('AssetInput holds all fields correctly', () {
      final input = AssetInput(
        code: 'FA-001',
        name: 'مكيف مركزي',
        categoryId: 2,
        location: 'الطابق الثاني',
        purchasePrice: 5000,
        purchaseDate: DateTime(2026, 1, 15),
        usefulLifeYears: 10,
        salvageValue: 500,
        depreciationMethod: 'straight_line',
        notes: 'جديد',
        costCenterId: 3,
      );
      expect(input.code, 'FA-001');
      expect(input.purchasePrice, 5000);
      expect(input.usefulLifeYears, 10);
      expect(input.salvageValue, 500);
      expect(input.depreciationMethod, 'straight_line');
      expect(input.costCenterId, 3);
    });

    test('AssetInput defaults are correct', () {
      final input = AssetInput(
        code: 'FA-002',
        name: 'طابعة',
        categoryId: 1,
        purchasePrice: 1500,
        purchaseDate: DateTime.now(),
        usefulLifeYears: 5,
      );
      expect(input.salvageValue, 0);
      expect(input.depreciationMethod, 'straight_line');
      expect(input.notes, isNull);
      expect(input.costCenterId, isNull);
    });
  });

  group('DisposeAssetInput', () {
    test('holds disposal values', () {
      final input = DisposeAssetInput(
        assetId: 5,
        disposalValue: 2000,
        disposalDate: DateTime(2026, 6, 30),
        costCenterId: 1,
      );
      expect(input.assetId, 5);
      expect(input.disposalValue, 2000);
    });
  });

  group('AssetResult', () {
    test('success with ID', () {
      final r = AssetResult.success(7);
      expect(r.isSuccess, true);
      expect(r.assetId, 7);
      expect(r.error, isNull);
    });

    test('failure with Arabic message', () {
      final r = AssetResult.failure('يجب إدخال كود الأصل');
      expect(r.isSuccess, false);
      expect(r.assetId, isNull);
      expect(r.error, contains('كود'));
    });
  });

  group('DepreciationResult', () {
    test('success carries count', () {
      final r = DepreciationResult.success(assetsProcessed: 15);
      expect(r.isSuccess, true);
      expect(r.assetsProcessed, 15);
    });

    test('failure resets count to 0', () {
      final r = DepreciationResult.failure('خطأ');
      expect(r.isSuccess, false);
      expect(r.assetsProcessed, 0);
    });
  });
}
