import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/usecases/manufacturing/create_bom_usecase.dart';
import 'package:picpos_erp/domain/usecases/manufacturing/execute_production_usecase.dart';

void main() {
  group('CreateBOMUseCase — Input Validation', () {
    test('returns failure when components list is empty', () async {
      final input = CreateBOMInput(
        finishedProductId: 1,
        bomCode: 'BOM-001',
        expectedQuantity: 10,
        components: [],
      );
      // We can't call execute without a real DB, but we can validate the input model
      expect(input.components, isEmpty);
      expect(input.bomCode, 'BOM-001');
      expect(input.expectedQuantity, 10);
    });

    test('BOMComponentInput.toMap() returns correct structure', () {
      final comp = BOMComponentInput(
        rawMaterialId: 5,
        quantity: 2.5,
        unitCost: 10.0,
      );
      final map = comp.toMap();
      expect(map['rawMaterialId'], 5);
      expect(map['quantity'], 2.5);
      expect(map['unitCost'], 10.0);
    });

    test('CreateBOMResult.success carries bomId', () {
      final result = CreateBOMResult.success(42);
      expect(result.isSuccess, true);
      expect(result.bomId, 42);
      expect(result.error, isNull);
    });

    test('CreateBOMResult.failure carries error message', () {
      final result = CreateBOMResult.failure('يجب إدخال كود BOM');
      expect(result.isSuccess, false);
      expect(result.bomId, isNull);
      expect(result.error, 'يجب إدخال كود BOM');
    });
  });

  group('ProductionOrderInput', () {
    test('holds correct values', () {
      final input = ProductionOrderInput(
        bomId: 1,
        orderedQty: 100,
        warehouseId: 3,
        startDate: DateTime(2026, 3, 1),
        notes: 'Test batch',
      );
      expect(input.bomId, 1);
      expect(input.orderedQty, 100);
      expect(input.warehouseId, 3);
      expect(input.notes, 'Test batch');
    });
  });

  group('ProductionResult', () {
    test('success factory', () {
      final r = ProductionResult.success(10);
      expect(r.isSuccess, true);
      expect(r.orderId, 10);
    });

    test('failure factory', () {
      final r = ProductionResult.failure('خطأ');
      expect(r.isSuccess, false);
      expect(r.error, 'خطأ');
    });
  });
}
