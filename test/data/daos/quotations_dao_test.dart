import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase database;
  late int warehouseId;
  late int userId;

  setUp(() async {
    database = AppDatabase.forTesting();
    final roleId = await database.into(database.roles).insert(
      RolesCompanion.insert(name: 'Admin', isSystemRole: const Value(true)),
    );
    userId = await database.createUser(
      username: 'testuser',
      password: 'test123',
      displayName: 'Test User',
      roleId: roleId,
    );
    warehouseId = await database.into(database.warehouses).insert(
      WarehousesCompanion.insert(name: 'Main Warehouse'),
    );
  });

  tearDown(() async {
    await database.close();
  });

  group('QuotationsDao - CRUD', () {
    test('insert and retrieve quotation', () async {
      final id = await database.into(database.quotations).insert(
        QuotationsCompanion.insert(
          quotationNumber: 'Q-001',
          warehouseId: warehouseId,
          userId: userId,
          quotationDate: DateTime(2026, 3, 1),
          subtotal: const Value(100.0),
          total: const Value(100.0),
        ),
      );

      expect(id, isPositive);

      final q = await (database.select(database.quotations)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      expect(q, isNotNull);
      expect(q!.quotationNumber, 'Q-001');
      expect(q.total, 100.0);
    });

    test('update quotation total', () async {
      final id = await database.into(database.quotations).insert(
        QuotationsCompanion.insert(
          quotationNumber: 'Q-002',
          warehouseId: warehouseId,
          userId: userId,
          quotationDate: DateTime(2026, 3, 1),
          total: const Value(50.0),
        ),
      );

      await (database.update(database.quotations)
            ..where((t) => t.id.equals(id)))
          .write(const QuotationsCompanion(total: Value(75.0)));

      final updated = await (database.select(database.quotations)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      expect(updated!.total, 75.0);
    });

    test('delete quotation', () async {
      final id = await database.into(database.quotations).insert(
        QuotationsCompanion.insert(
          quotationNumber: 'Q-DEL',
          warehouseId: warehouseId,
          userId: userId,
          quotationDate: DateTime(2026, 3, 1),
        ),
      );

      await (database.delete(database.quotations)
            ..where((t) => t.id.equals(id)))
          .go();

      final result = await (database.select(database.quotations)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      expect(result, isNull);
    });

    test('status defaults to draft', () async {
      final id = await database.into(database.quotations).insert(
        QuotationsCompanion.insert(
          quotationNumber: 'Q-STATUS',
          warehouseId: warehouseId,
          userId: userId,
          quotationDate: DateTime(2026, 3, 1),
        ),
      );

      final q = await (database.select(database.quotations)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      expect(q!.status, 'draft');
    });
  });

  group('QuotationsDao - Items', () {
    test('insert quotation items linked to quotation', () async {
      // Need a product first
      final catId = await database.into(database.categories).insert(
        CategoriesCompanion.insert(name: 'Test Cat', color: const Value('#000')),
      );
      final productId = await database.into(database.products).insert(
        ProductsCompanion.insert(
          name: 'Test Product',
          code: 'TST-001',
          categoryId: Value(catId),
          salePrice: const Value(50.0),
          costPrice: const Value(30.0),
          warehouseId: Value(warehouseId),
        ),
      );

      final quotationId = await database.into(database.quotations).insert(
        QuotationsCompanion.insert(
          quotationNumber: 'Q-ITEMS',
          warehouseId: warehouseId,
          userId: userId,
          quotationDate: DateTime(2026, 3, 1),
          total: const Value(100.0),
        ),
      );

      await database.into(database.quotationItems).insert(
        QuotationItemsCompanion.insert(
          quotationId: quotationId,
          productId: productId,
          quantity: 2.0,
          unitPrice: 50.0,
          total: 100.0,
        ),
      );

      final items = await (database.select(database.quotationItems)
            ..where((t) => t.quotationId.equals(quotationId)))
          .get();
      expect(items, hasLength(1));
      expect(items.first.quantity, 2.0);
      expect(items.first.unitPrice, 50.0);
    });
  });

  group('QuotationsDao - Search', () {
    test('list quotations ordered by date', () async {
      await database.into(database.quotations).insert(
        QuotationsCompanion.insert(
          quotationNumber: 'Q-OLD',
          warehouseId: warehouseId,
          userId: userId,
          quotationDate: DateTime(2026, 1, 1),
        ),
      );
      await database.into(database.quotations).insert(
        QuotationsCompanion.insert(
          quotationNumber: 'Q-NEW',
          warehouseId: warehouseId,
          userId: userId,
          quotationDate: DateTime(2026, 3, 1),
        ),
      );

      final all = await (database.select(database.quotations)
            ..orderBy([(t) => OrderingTerm.desc(t.quotationDate)]))
          .get();
      expect(all, hasLength(2));
      expect(all.first.quotationNumber, 'Q-NEW');
    });
  });
}
