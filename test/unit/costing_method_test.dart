import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/costing_method_service.dart';

void main() {
  // حالة `lastPurchase` اتشالت مع الصيغة نفسها — مش صيغة تحميل تكلفة مسموحة
  // في IAS 2.25 (المسموح: متوسط مرجّح · FIFO · تمييز محدد). التغطية البديلة
  // في `costing_method_ias2_test.dart`، وفيها إن التركيبات القايمة المخزَّن
  // فيها القيمة القديمة بتتقرا كمتوسط مرجّح.
  group('CostingMethodService — calculateCost', () {
    test('calculates weighted average cost correctly', () {
      // WAC = (50 * 10 + 20 * 15) / (50 + 20) = 800 / 70 ≈ 11.43
      final result = CostingMethodService.calculateCost(
        method: CostingMethod.weightedAverage,
        purchaseUnitCost: 15.0,
        currentCost: 10.0,
        currentStock: 50,
        purchaseQty: 20,
      );
      expect(result, closeTo(11.43, 0.01));
    });

    test('WAC with zero current stock returns new cost', () {
      final result = CostingMethodService.calculateCost(
        method: CostingMethod.weightedAverage,
        purchaseUnitCost: 25.0,
        currentCost: 0,
        currentStock: 0,
        purchaseQty: 10,
      );
      expect(result, 25.0);
    });

    test('WAC with equal prices returns same price', () {
      final result = CostingMethodService.calculateCost(
        method: CostingMethod.weightedAverage,
        purchaseUnitCost: 10.0,
        currentCost: 10.0,
        currentStock: 100,
        purchaseQty: 50,
      );
      expect(result, 10.0);
    });
  });

  group('CostingMethodService — label', () {
    test('returns Arabic label for weightedAverage', () {
      final label = CostingMethodService.label(CostingMethod.weightedAverage);
      expect(label, contains('متوسط'));
    });
  });
}
