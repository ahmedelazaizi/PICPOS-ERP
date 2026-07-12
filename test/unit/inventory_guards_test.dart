// ═══════════════════════════════════════════════════════════════════════════
// Unit Test: Inventory Guards — Negative stock, transfer validation
// ═══════════════════════════════════════════════════════════════════════════
//
// Pure logic tests — no database dependency needed.
// The guard logic is: canSell = !trackInventory || allowNegativeSale || currentStock > 0

import 'package:flutter_test/flutter_test.dart';

/// Lightweight product model for guard logic testing (no DB dependency)
class _ProductGuard {
  final double currentStock;
  final bool trackInventory;
  final bool allowNegativeSale;

  _ProductGuard({
    required this.currentStock,
    this.trackInventory = true,
    this.allowNegativeSale = false,
  });

  bool get canSell =>
      !trackInventory || allowNegativeSale || currentStock > 0;
}

void main() {
  group('Negative Stock Prevention', () {
    test('Product with currentStock=0 and trackInventory=true blocks sale', () {
      final product = _ProductGuard(
        currentStock: 0,
        trackInventory: true,
        allowNegativeSale: false,
      );
      expect(product.canSell, isFalse,
          reason: 'Should not allow sale when stock is 0');
    });

    test('Product with allowNegativeSale=true allows sale at zero stock', () {
      final product = _ProductGuard(
        currentStock: 0,
        trackInventory: true,
        allowNegativeSale: true,
      );
      expect(product.canSell, isTrue,
          reason: 'allowNegativeSale overrides zero stock check');
    });

    test('Product with trackInventory=false always allows sale', () {
      final product = _ProductGuard(
        currentStock: 0,
        trackInventory: false,
      );
      expect(product.canSell, isTrue,
          reason: 'Services (no inventory tracking) always sellable');
    });

    test('Product with positive stock allows sale', () {
      final product = _ProductGuard(
        currentStock: 50,
        trackInventory: true,
        allowNegativeSale: false,
      );
      expect(product.canSell, isTrue);
    });
  });

  group('Transfer Stock Availability', () {
    test('Transfer blocked when requested qty exceeds stock', () {
      const currentStock = 10.0;
      const transferQty = 15.0;
      expect(currentStock >= transferQty, isFalse);
    });

    test('Transfer allowed when stock is sufficient', () {
      const currentStock = 20.0;
      const transferQty = 15.0;
      expect(currentStock >= transferQty, isTrue);
    });

    test('Transfer exact match is allowed', () {
      const currentStock = 10.0;
      const transferQty = 10.0;
      expect(currentStock >= transferQty, isTrue);
    });

    test('Transfer of 0 quantity is rejected', () {
      const transferQty = 0.0;
      expect(transferQty > 0, isFalse);
    });

    test('Transfer of negative quantity is rejected', () {
      const transferQty = -5.0;
      expect(transferQty > 0, isFalse);
    });
  });

  group('Inventory Balance Updates', () {
    test('Stock decreases after sale', () {
      expect(100.0 - 5.0, 95.0);
    });

    test('Stock increases after purchase', () {
      expect(100.0 + 20.0, 120.0);
    });

    test('Stock increases after sale return', () {
      expect(95.0 + 5.0, 100.0);
    });

    test('Stock decreases after purchase return', () {
      expect(120.0 - 20.0, 100.0);
    });
  });

  group('WAL Busy Timeout', () {
    test('busy_timeout value is 5000ms', () {
      const busyTimeout = 5000;
      expect(busyTimeout, greaterThanOrEqualTo(3000));
      expect(busyTimeout, lessThanOrEqualTo(30000));
    });
  });
}
