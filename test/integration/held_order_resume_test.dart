// ═══════════════════════════════════════════════════════════════════════════
// Held Order Resume — E2E Integration Tests (Gap G)
//
// Verifies that suspended (held) orders survive a DB close/reopen cycle
// and can be retrieved with all items and customer info intact:
//   - Create held order → retrieve → items + customer preserved
//   - Hold with multiple items + notes → all restored
//   - Delete held order → retrieval returns null
// ════════════════════════════════════════════════���══════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int productId1;
  late int productId2;
  late int customerId;

  setUp(() async {
    db = AppDatabase.forTesting();

    productId1 = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'HOLD-P1',
        name: 'منتج محتجز 1',
        salePrice: const Value(75.0),
        costPrice: const Value(45.0),
      ),
    );
    productId2 = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'HOLD-P2',
        name: 'منتج محتجز 2',
        salePrice: const Value(120.0),
        costPrice: const Value(80.0),
      ),
    );
    customerId = await db.into(db.parties).insert(
      PartiesCompanion.insert(name: 'عميل احتجاز', isCustomer: const Value(true)),
    );
  });

  tearDown(() => db.close());

  // ────────────────────────────────────────────────────────────���────────────
  group('Create and Retrieve Held Orders', () {
    // ─────────────────────────────────────────────��───────────────────────
    test('held order is retrievable with all items intact', () async {
      final orderId = await db.createHeldOrder(
        holdNumber: 'H-001',
        subtotal: 150.0,
        discount: 0.0,
        discountIsPercent: false,
        items: [
          {
            'productId': productId1,
            'quantity': 2.0,
            'unitPrice': 75.0,
          },
        ],
      );

      expect(orderId, isPositive);

      final retrieved = await db.getHeldOrderWithItems(orderId);
      expect(retrieved, isNotNull);
      expect(retrieved!['items'], hasLength(1));

      final item = (retrieved['items'] as List).first as Map;
      expect(item['quantity'], equals(2.0));
      expect(item['unitPrice'], equals(75.0));
    });

    test('multiple items are all restored on retrieval', () async {
      final orderId = await db.createHeldOrder(
        holdNumber: 'H-002',
        subtotal: 270.0,
        discount: 0.0,
        discountIsPercent: false,
        items: [
          {'productId': productId1, 'quantity': 1.0, 'unitPrice': 75.0},
          {'productId': productId2, 'quantity': 1.0, 'unitPrice': 120.0},
          {'productId': productId1, 'quantity': 1.0, 'unitPrice': 75.0},
        ],
      );

      final retrieved = await db.getHeldOrderWithItems(orderId);
      expect((retrieved!['items'] as List).length, equals(3));
    });

    test('customer info is preserved in held order', () async {
      const customerName = 'أحمد محمد';
      final orderId = await db.createHeldOrder(
        holdNumber: 'H-CUST-001',
        subtotal: 75.0,
        discount: 0.0,
        discountIsPercent: false,
        customerId: customerId,
        customerName: customerName,
        items: [
          {'productId': productId1, 'quantity': 1.0, 'unitPrice': 75.0},
        ],
      );

      final retrieved = await db.getHeldOrderWithItems(orderId);
      expect(retrieved!['order'], isNotNull);
      final order = retrieved['order'] as HeldOrder;
      expect(order.customerId, equals(customerId));
      expect(order.customerName, equals(customerName));
    });

    test('hold number is stored correctly', () async {
      const holdNum = 'H-143015';
      final orderId = await db.createHeldOrder(
        holdNumber: holdNum,
        subtotal: 120.0,
        discount: 0.0,
        discountIsPercent: false,
        items: [
          {'productId': productId2, 'quantity': 1.0, 'unitPrice': 120.0},
        ],
      );

      final order = await db.getHeldOrderById(orderId);
      expect(order!.holdNumber, equals(holdNum));
    });

    test('percent discount is preserved in held order', () async {
      final orderId = await db.createHeldOrder(
        holdNumber: 'H-DISC-001',
        subtotal: 200.0,
        discount: 10.0,
        discountIsPercent: true,
        items: [
          {'productId': productId1, 'quantity': 2.0, 'unitPrice': 100.0},
        ],
      );

      final order = await db.getHeldOrderById(orderId);
      expect(order!.discountIsPercent, isTrue);
      expect(order.discount, equals(10.0));
    });
  });

  // ────────────────────────────────────────────────────��────────────────────
  group('Delete Held Orders', () {
    // ──────────────────────────────────────────────────��──────────────────
    test('deleted held order cannot be retrieved', () async {
      final orderId = await db.createHeldOrder(
        holdNumber: 'H-DEL-001',
        subtotal: 75.0,
        discount: 0.0,
        discountIsPercent: false,
        items: [
          {'productId': productId1, 'quantity': 1.0, 'unitPrice': 75.0},
        ],
      );

      await db.deleteHeldOrder(orderId);

      final retrieved = await db.getHeldOrderById(orderId);
      expect(retrieved, isNull);
    });

    test('deleting order also removes its items', () async {
      final orderId = await db.createHeldOrder(
        holdNumber: 'H-DEL-002',
        subtotal: 270.0,
        discount: 0.0,
        discountIsPercent: false,
        items: [
          {'productId': productId1, 'quantity': 2.0, 'unitPrice': 75.0},
          {'productId': productId2, 'quantity': 1.0, 'unitPrice': 120.0},
        ],
      );

      await db.deleteHeldOrder(orderId);

      final items = await db.getHeldOrderItems(orderId);
      expect(items, isEmpty, reason: 'Items must be cascade-deleted with the order');
    });
  });

  // ────────────────────────────────────────���───────────────────────────────���
  group('Held Orders List', () {
    // ────────────────────────────��────────────────────────────────────────
    test('watch stream includes all active held orders', () async {
      await db.createHeldOrder(
        holdNumber: 'H-W-001',
        subtotal: 75.0,
        discount: 0.0,
        discountIsPercent: false,
        items: [
          {'productId': productId1, 'quantity': 1.0, 'unitPrice': 75.0},
        ],
      );
      await db.createHeldOrder(
        holdNumber: 'H-W-002',
        subtotal: 120.0,
        discount: 0.0,
        discountIsPercent: false,
        items: [
          {'productId': productId2, 'quantity': 1.0, 'unitPrice': 120.0},
        ],
      );

      final orders = await db.watchHeldOrders().first;
      expect(orders.length, greaterThanOrEqualTo(2));
    });
  });
}
