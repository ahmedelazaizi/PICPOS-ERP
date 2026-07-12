// ═══════════════════════════════════════════════════════════════════════════
// ManageAssetUseCase — Unit Tests (coverage: manage_asset_usecase.dart)
// ═══════════════════════════════════════════════════════════════════════════
//
// Validation paths in createAsset() all return early before any DB access,
// so AppDatabase.forTesting() is sufficient.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/domain/usecases/fixed_assets/manage_asset_usecase.dart';

void main() {
  late AppDatabase db;
  late ManageAssetUseCase useCase;

  setUp(() {
    db = AppDatabase.forTesting();
    useCase = ManageAssetUseCase(db);
  });

  tearDown(() => db.close());

  // ── createAsset validation ──────────────────────────────────────────────────
  group('createAsset — validation', () {
    test('fails when code is empty', () async {
      final input = AssetInput(
        code: '',
        name: 'Test',
        categoryId: 1,
        purchasePrice: 1000,
        purchaseDate: DateTime(2026, 1, 1),
        usefulLifeYears: 3,
      );
      final result = await useCase.createAsset(input);
      expect(result.isSuccess, isFalse);
      expect(result.error, 'يجب إدخال كود الأصل');
    });

    test('fails when code is blank whitespace', () async {
      final input = AssetInput(
        code: '  ',
        name: 'Test',
        categoryId: 1,
        purchasePrice: 1000,
        purchaseDate: DateTime(2026, 1, 1),
        usefulLifeYears: 3,
      );
      final result = await useCase.createAsset(input);
      expect(result.isSuccess, isFalse);
    });

    test('fails when name is empty', () async {
      final input = AssetInput(
        code: 'FA-001',
        name: '',
        categoryId: 1,
        purchasePrice: 1000,
        purchaseDate: DateTime(2026, 1, 1),
        usefulLifeYears: 3,
      );
      final result = await useCase.createAsset(input);
      expect(result.isSuccess, isFalse);
      expect(result.error, 'يجب إدخال اسم الأصل');
    });

    test('fails when purchasePrice is zero', () async {
      final input = AssetInput(
        code: 'FA-001',
        name: 'Asset',
        categoryId: 1,
        purchasePrice: 0,
        purchaseDate: DateTime(2026, 1, 1),
        usefulLifeYears: 3,
      );
      final result = await useCase.createAsset(input);
      expect(result.isSuccess, isFalse);
      expect(result.error, 'سعر الشراء يجب أن يكون أكبر من صفر');
    });

    test('fails when purchasePrice is negative', () async {
      final input = AssetInput(
        code: 'FA-001',
        name: 'Asset',
        categoryId: 1,
        purchasePrice: -100,
        purchaseDate: DateTime(2026, 1, 1),
        usefulLifeYears: 3,
      );
      final result = await useCase.createAsset(input);
      expect(result.isSuccess, isFalse);
    });

    test('fails when usefulLifeYears is zero', () async {
      final input = AssetInput(
        code: 'FA-001',
        name: 'Asset',
        categoryId: 1,
        purchasePrice: 1000,
        purchaseDate: DateTime(2026, 1, 1),
        usefulLifeYears: 0,
      );
      final result = await useCase.createAsset(input);
      expect(result.isSuccess, isFalse);
      expect(result.error, 'العمر الإنتاجي يجب أن يكون أكبر من صفر');
    });

    test('fails when salvageValue >= purchasePrice', () async {
      final input = AssetInput(
        code: 'FA-001',
        name: 'Asset',
        categoryId: 1,
        purchasePrice: 1000,
        purchaseDate: DateTime(2026, 1, 1),
        usefulLifeYears: 5,
        salvageValue: 1000, // equal to purchasePrice
      );
      final result = await useCase.createAsset(input);
      expect(result.isSuccess, isFalse);
      expect(result.error, 'قيمة الخردة يجب أن تكون أقل من سعر الشراء');
    });

    test('fails when salvageValue > purchasePrice', () async {
      final input = AssetInput(
        code: 'FA-001',
        name: 'Asset',
        categoryId: 1,
        purchasePrice: 1000,
        purchaseDate: DateTime(2026, 1, 1),
        usefulLifeYears: 5,
        salvageValue: 1500, // greater than purchasePrice
      );
      final result = await useCase.createAsset(input);
      expect(result.isSuccess, isFalse);
    });
  });

  // ── revalueAsset validation ─────────────────────────────────────────────────
  group('revalueAsset — validation', () {
    test('fails when newFairValue is zero', () async {
      final result = await useCase.revalueAsset(1, 0);
      expect(result.isSuccess, isFalse);
      expect(result.error, 'القيمة العادلة يجب أن تكون أكبر من صفر');
    });

    test('fails when newFairValue is negative', () async {
      final result = await useCase.revalueAsset(1, -500);
      expect(result.isSuccess, isFalse);
    });
  });

  // ── Data classes ─────────────────────────────────────────────────────────────
  group('AssetResult', () {
    test('success sets isSuccess=true and assetId', () {
      final r = AssetResult.success(99);
      expect(r.isSuccess, isTrue);
      expect(r.assetId, 99);
      expect(r.error, isNull);
    });

    test('failure sets isSuccess=false and error', () {
      final r = AssetResult.failure('broke');
      expect(r.isSuccess, isFalse);
      expect(r.error, 'broke');
      expect(r.assetId, isNull);
    });

    test('success without id has null assetId', () {
      final r = AssetResult.success();
      expect(r.isSuccess, isTrue);
      expect(r.assetId, isNull);
    });
  });

  group('AssetInput defaults', () {
    test('salvageValue defaults to 0', () {
      final input = AssetInput(
        code: 'FA-001',
        name: 'Test',
        categoryId: 1,
        purchasePrice: 1000,
        purchaseDate: DateTime(2026, 1, 1),
        usefulLifeYears: 5,
      );
      expect(input.salvageValue, 0);
    });

    test('depreciationMethod defaults to straight_line', () {
      final input = AssetInput(
        code: 'FA-001',
        name: 'Test',
        categoryId: 1,
        purchasePrice: 1000,
        purchaseDate: DateTime(2026, 1, 1),
        usefulLifeYears: 5,
      );
      expect(input.depreciationMethod, 'straight_line');
    });
  });

  group('DisposeAssetInput', () {
    test('stores fields correctly', () {
      final date = DateTime(2026, 6, 1);
      final input = DisposeAssetInput(
        assetId: 5,
        disposalValue: 2500,
        disposalDate: date,
        costCenterId: 1,
      );
      expect(input.assetId, 5);
      expect(input.disposalValue, 2500);
      expect(input.disposalDate, date);
      expect(input.costCenterId, 1);
    });
  });
}
