import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase database;
  late int warehouseId;
  late int supplierId;
  late int customerId;

  setUp(() async {
    database = AppDatabase.forTesting();
    final roleId = await database.into(database.roles).insert(
      RolesCompanion.insert(name: 'Admin', isSystemRole: const Value(true)),
    );
    await database.createUser(
      username: 'testuser',
      password: 'test123',
      displayName: 'Test User',
      roleId: roleId,
    );
    warehouseId = await database.into(database.warehouses).insert(
      WarehousesCompanion.insert(name: 'Main Warehouse'),
    );
    supplierId = await database.into(database.parties).insert(
      PartiesCompanion.insert(name: 'Test Supplier', isSupplier: const Value(true)),
    );
    customerId = await database.into(database.parties).insert(
      PartiesCompanion.insert(name: 'Test Customer', isCustomer: const Value(true)),
    );
  });

  tearDown(() async {
    await database.close();
  });

  group('PurchaseOrders - CRUD', () {
    test('insert and retrieve purchase order', () async {
      final id = await database.into(database.purchaseOrders).insert(
        PurchaseOrdersCompanion.insert(
          orderNumber: 'PO-001',
          supplierId: supplierId,
          warehouseId: warehouseId,
          orderDate: DateTime(2026, 3, 1),
          total: const Value(500.0),
        ),
      );

      expect(id, isPositive);

      final po = await (database.select(database.purchaseOrders)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      expect(po, isNotNull);
      expect(po!.orderNumber, 'PO-001');
      expect(po.total, 500.0);
    });

    test('default status is draft', () async {
      final id = await database.into(database.purchaseOrders).insert(
        PurchaseOrdersCompanion.insert(
          orderNumber: 'PO-STATUS',
          supplierId: supplierId,
          warehouseId: warehouseId,
          orderDate: DateTime(2026, 3, 1),
        ),
      );

      final po = await (database.select(database.purchaseOrders)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      expect(po!.status, 'draft');
    });

    test('update PO status to approved', () async {
      final id = await database.into(database.purchaseOrders).insert(
        PurchaseOrdersCompanion.insert(
          orderNumber: 'PO-UP',
          supplierId: supplierId,
          warehouseId: warehouseId,
          orderDate: DateTime(2026, 3, 1),
        ),
      );

      await (database.update(database.purchaseOrders)
            ..where((t) => t.id.equals(id)))
          .write(const PurchaseOrdersCompanion(status: Value('approved')));

      final updated = await (database.select(database.purchaseOrders)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      expect(updated!.status, 'approved');
    });

    test('delete purchase order', () async {
      final id = await database.into(database.purchaseOrders).insert(
        PurchaseOrdersCompanion.insert(
          orderNumber: 'PO-DEL',
          supplierId: supplierId,
          warehouseId: warehouseId,
          orderDate: DateTime(2026, 3, 1),
        ),
      );

      await (database.delete(database.purchaseOrders)
            ..where((t) => t.id.equals(id)))
          .go();

      final result = await (database.select(database.purchaseOrders)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      expect(result, isNull);
    });
  });

  group('SalesOrders - CRUD', () {
    test('insert and retrieve sales order', () async {
      final id = await database.into(database.salesOrders).insert(
        SalesOrdersCompanion.insert(
          orderNumber: 'SO-001',
          warehouseId: warehouseId,
          orderDate: DateTime(2026, 3, 1),
          customerId: Value(customerId),
          total: const Value(300.0),
        ),
      );

      expect(id, isPositive);

      final so = await (database.select(database.salesOrders)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      expect(so, isNotNull);
      expect(so!.orderNumber, 'SO-001');
      expect(so.total, 300.0);
    });

    test('update SO status to confirmed', () async {
      final id = await database.into(database.salesOrders).insert(
        SalesOrdersCompanion.insert(
          orderNumber: 'SO-UP',
          warehouseId: warehouseId,
          orderDate: DateTime(2026, 3, 1),
        ),
      );

      await (database.update(database.salesOrders)
            ..where((t) => t.id.equals(id)))
          .write(const SalesOrdersCompanion(status: Value('confirmed')));

      final updated = await (database.select(database.salesOrders)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      expect(updated!.status, 'confirmed');
    });
  });
}
