// ═══════════════════════════════════════════════════════════════════════════
// SALES HELD ORDERS DAO
// Extracted from sales_dao.dart — Sprint 12 God File Splitting
// ═══════════════════════════════════════════════════════════════════════════

part of '../database.dart';

/// Extension for Held Orders (Suspended Sales) operations
extension SalesHeldOrdersDao on AppDatabase {
  // ═══════════════════════════════════════════════════════════════════════
  // HELD ORDERS (Suspended Sales)
  // ═══════════════════════════════════════════════════════════════════════

  /// Watch all held orders
  Stream<List<HeldOrder>> watchHeldOrders() {
    return (select(
      heldOrders,
    )..orderBy([(o) => OrderingTerm.desc(o.createdAt)])).watch();
  }

  /// Get a single held order by ID
  Future<HeldOrder?> getHeldOrderById(int id) {
    return (select(
      heldOrders,
    )..where((o) => o.id.equals(id))).getSingleOrNull();
  }

  /// Get items for a held order (Data Class)
  Future<List<HeldOrderItem>> getHeldOrderItems(int heldOrderId) {
    return (select(
      heldOrderItems,
    )..where((i) => i.heldOrderId.equals(heldOrderId))).get();
  }

  /// Delete a held order and its items
  Future<void> deleteHeldOrder(int id) async {
    await transaction(() async {
      await (delete(
        heldOrderItems,
      )..where((i) => i.heldOrderId.equals(id))).go();
      await (delete(heldOrders)..where((o) => o.id.equals(id))).go();
    });
  }

  /// Create a held order with items
  Future<int> createHeldOrder({
    required String holdNumber,
    required double subtotal,
    required double discount,
    required bool discountIsPercent,
    int? customerId,
    String? customerName,
    required List<Map<String, dynamic>> items,
  }) async {
    return transaction(() async {
      final orderId = await into(heldOrders).insert(
        HeldOrdersCompanion.insert(
          holdNumber: holdNumber,
          subtotal: Value(subtotal),
          discount: Value(discount),
          discountIsPercent: Value(discountIsPercent),
          customerId: Value(customerId),
          customerName: Value(customerName),
          createdAt: Value(DateTime.now()),
          // UUID-First Phase 1 Slice 3: stable identity across installs.
          globalId: Value(UuidV7.generate()),
        ),
      );

      for (final item in items) {
        await into(heldOrderItems).insert(
          HeldOrderItemsCompanion.insert(
            heldOrderId: orderId,
            productId: item['productId'] as int,
            quantity: (item['quantity'] as num).toDouble(),
            unitPrice: (item['unitPrice'] as num).toDouble(),
            customPrice: Value((item['customPrice'] as num?)?.toDouble()),
            note: Value(item['note'] as String?),
            globalId: Value(UuidV7.generate()),
          ),
        );
      }

      return orderId;
    });
  }

  /// Get held order with its items (for retrieval)
  Future<Map<String, dynamic>?> getHeldOrderWithItems(int orderId) async {
    final order = await (select(
      heldOrders,
    )..where((o) => o.id.equals(orderId))).getSingleOrNull();
    if (order == null) return null;

    final items = await (select(
      heldOrderItems,
    )..where((i) => i.heldOrderId.equals(orderId))).get();

    // Get products + their categories for items.
    // Issue 2 (Feature 019): the printed held-order receipt groups items by
    // category — fetch the category name alongside the product so the
    // presentation layer doesn't need a second round-trip per row.
    final itemsWithProducts = <Map<String, dynamic>>[];
    for (final item in items) {
      final product = await (select(
        products,
      )..where((p) => p.id.equals(item.productId))).getSingleOrNull();
      if (product != null) {
        String? categoryName;
        if (product.categoryId != null) {
          final cat = await (select(categories)
                ..where((c) => c.id.equals(product.categoryId!))
                ..limit(1))
              .getSingleOrNull();
          categoryName = cat?.name;
        }
        itemsWithProducts.add({
          'product': product,
          'categoryId': product.categoryId,
          'categoryName': categoryName,
          'quantity': item.quantity,
          'unitPrice': item.unitPrice,
          'customPrice': item.customPrice,
          'note': item.note,
        });
      }
    }

    return {'order': order, 'items': itemsWithProducts};
  }
}
