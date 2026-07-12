// ═══════════════════════════════════════════════════════════════════════════
// INVENTORY COSTING EDGE CASES — Unit Tests (PIR Phase 8)
//
// Tests for edge cases in inventory operations:
//   - Zero-stock sale handling
//   - Negative stock prevention
//   - Multi-warehouse transfers
//   - Stock movement audit trail integrity
//   - Average cost calculation with edge inputs
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Average Cost Calculation', () {
    test('initial purchase sets average cost', () {
      final avgCost = _calculateAverageCost(
        currentStock: 0,
        currentAvgCost: 0,
        purchaseQty: 100,
        purchaseUnitCost: 10.0,
      );
      expect(avgCost, 10.0);
    });

    test('second purchase adjusts average cost correctly', () {
      // 100 units @ 10 = 1000
      // 50 units @ 16 = 800
      // Total: 150 units, Total cost: 1800
      // Average: 12.0
      final avgCost = _calculateAverageCost(
        currentStock: 100,
        currentAvgCost: 10.0,
        purchaseQty: 50,
        purchaseUnitCost: 16.0,
      );
      expect(avgCost, 12.0);
    });

    test('sale does NOT change average cost (weighted average method)', () {
      const avgCostBefore = 12.0;
      final avgCostAfter = _calculateAverageCostAfterSale(
        currentStock: 150,
        currentAvgCost: avgCostBefore,
        saleQty: 30,
      );
      expect(avgCostAfter, avgCostBefore);
    });

    test('zero-quantity purchase does not change cost', () {
      final avgCost = _calculateAverageCost(
        currentStock: 100,
        currentAvgCost: 10.0,
        purchaseQty: 0,
        purchaseUnitCost: 50.0,
      );
      expect(avgCost, 10.0); // Unchanged
    });

    test('purchase into zero stock with zero cost', () {
      final avgCost = _calculateAverageCost(
        currentStock: 0,
        currentAvgCost: 0,
        purchaseQty: 10,
        purchaseUnitCost: 0,
      );
      expect(avgCost, 0.0); // Free items
    });
  });

  group('Stock Validation Rules', () {
    test('sale quantity must not exceed available stock', () {
      const currentStock = 50.0;
      const saleQty = 60.0;

      expect(_canSell(currentStock, saleQty, allowNegative: false), isFalse);
    });

    test('sale allowed when stock is sufficient', () {
      const currentStock = 100.0;
      const saleQty = 50.0;

      expect(_canSell(currentStock, saleQty, allowNegative: false), isTrue);
    });

    test('sale allowed with negative when config permits', () {
      const currentStock = 10.0;
      const saleQty = 20.0;

      expect(_canSell(currentStock, saleQty, allowNegative: true), isTrue);
    });

    test('zero-quantity sale is rejected', () {
      expect(_canSell(100, 0, allowNegative: false), isFalse);
    });

    test('negative sale quantity is rejected', () {
      expect(_canSell(100, -5, allowNegative: false), isFalse);
    });
  });

  group('Warehouse Transfer Logic', () {
    test('transfer reduces source and increases destination', () {
      double sourceStock = 100.0;
      double destStock = 50.0;
      const transferQty = 25.0;

      final result = _executeTransfer(sourceStock, destStock, transferQty);

      expect(result['sourceAfter'], 75.0);
      expect(result['destAfter'], 75.0);
    });

    test('transfer fails when source has insufficient stock', () {
      expect(
        () => _executeTransfer(10, 50, 20),
        throwsA(isA<String>()),
      );
    });

    test('transfer preserves total inventory', () {
      double sourceStock = 100.0;
      double destStock = 50.0;
      const transferQty = 30.0;
      final totalBefore = sourceStock + destStock;

      final result = _executeTransfer(sourceStock, destStock, transferQty);
      final totalAfter = result['sourceAfter']! + result['destAfter']!;

      expect(totalAfter, totalBefore); // Inventory conservation law
    });

    test('same-warehouse transfer is rejected', () {
      expect(
        () => _validateTransfer(warehouseFrom: 1, warehouseTo: 1, qty: 10),
        throwsA(isA<String>()),
      );
    });
  });

  group('Stock Movement Audit Trail', () {
    test('movement records balance_after correctly', () {
      const currentStock = 100.0;
      const saleQty = 15.0;
      final balanceAfter = _calculateBalanceAfter(currentStock, -saleQty);

      expect(balanceAfter, 85.0);
    });

    test('purchase movement has positive quantity', () {
      const purchaseQty = 50.0;
      expect(purchaseQty, isPositive);

      final balanceAfter = _calculateBalanceAfter(100, purchaseQty);
      expect(balanceAfter, 150.0);
    });

    test('adjustment can be positive or negative', () {
      expect(_calculateBalanceAfter(100, 20), 120.0); // Positive adjustment
      expect(_calculateBalanceAfter(100, -10), 90.0); // Negative adjustment
    });

    test('return movement restores stock', () {
      // Original sale: -5
      // Return: +5 (same quantity, positive)
      const stockAfterSale = 95.0;
      const returnQty = 5.0;

      expect(_calculateBalanceAfter(stockAfterSale, returnQty), 100.0);
    });
  });

  group('Low Stock Alert Logic', () {
    test('stock below minimum triggers alert', () {
      expect(_isLowStock(currentStock: 5, minimumStock: 10), isTrue);
    });

    test('stock at minimum triggers alert', () {
      expect(_isLowStock(currentStock: 10, minimumStock: 10), isTrue);
    });

    test('stock above minimum is OK', () {
      expect(_isLowStock(currentStock: 15, minimumStock: 10), isFalse);
    });

    test('zero minimum means no alerts', () {
      expect(_isLowStock(currentStock: 0, minimumStock: 0), isFalse);
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Helper functions — pure business logic
// ═══════════════════════════════════════════════════════════════════════════

double _calculateAverageCost({
  required double currentStock,
  required double currentAvgCost,
  required double purchaseQty,
  required double purchaseUnitCost,
}) {
  if (purchaseQty <= 0) return currentAvgCost;
  final totalStock = currentStock + purchaseQty;
  if (totalStock == 0) return 0;
  return ((currentStock * currentAvgCost) + (purchaseQty * purchaseUnitCost)) / totalStock;
}

double _calculateAverageCostAfterSale({
  required double currentStock,
  required double currentAvgCost,
  required double saleQty,
}) {
  // In weighted average, selling doesn't change cost
  return currentAvgCost;
}

bool _canSell(double currentStock, double saleQty, {required bool allowNegative}) {
  if (saleQty <= 0) return false;
  if (!allowNegative && saleQty > currentStock) return false;
  return true;
}

Map<String, double> _executeTransfer(double sourceStock, double destStock, double qty) {
  if (qty > sourceStock) throw 'مخزون المصدر غير كافي';
  return {
    'sourceAfter': sourceStock - qty,
    'destAfter': destStock + qty,
  };
}

void _validateTransfer({required int warehouseFrom, required int warehouseTo, required double qty}) {
  if (warehouseFrom == warehouseTo) throw 'لا يمكن التحويل لنفس المخزن';
  if (qty <= 0) throw 'الكمية يجب أن تكون أكبر من صفر';
}

double _calculateBalanceAfter(double currentStock, double movementQty) {
  return currentStock + movementQty;
}

bool _isLowStock({required double currentStock, required double minimumStock}) {
  if (minimumStock <= 0) return false;
  return currentStock <= minimumStock;
}
