import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/services/costing_method_service.dart';

void main() {
  group('CostingMethodService — calculateCost', () {
    test('returns new cost as-is for lastPurchase method', () {
      final result = CostingMethodService.calculateCost(
        method: CostingMethod.lastPurchase,
        purchaseUnitCost: 15.0,
        currentCost: 10.0,
        currentStock: 50,
        purchaseQty: 20,
      );
      expect(result, 15.0);
    });

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
    test('returns Arabic label for lastPurchase', () {
      final label = CostingMethodService.label(CostingMethod.lastPurchase);
      expect(label, contains('آخر'));
    });

    test('returns Arabic label for weightedAverage', () {
      final label = CostingMethodService.label(CostingMethod.weightedAverage);
      expect(label, contains('متوسط'));
    });
  });
}
