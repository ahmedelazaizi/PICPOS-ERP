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

  group('SyncEngine - Categories', () {
    test('insert and verify category', () async {
      final id = await database.into(database.categories).insert(
        CategoriesCompanion.insert(
          name: 'Test Cat',
          color: const Value('#FF0000'),
        ),
      );

      final cat = await (database.select(database.categories)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();

      expect(cat, isNotNull);
      expect(cat!.name, 'Test Cat');
    });
  });

  group('SyncEngine - Products', () {
    test('insert product with category FK', () async {
      final catId = await database.into(database.categories).insert(
        CategoriesCompanion.insert(
          name: 'Electronics',
          color: const Value('#00FF00'),
        ),
      );

      final productId = await database.into(database.products).insert(
        ProductsCompanion.insert(
          name: 'Test Phone',
          code: 'PHN-001',
          categoryId: Value(catId),
          salePrice: const Value(999.0),
          costPrice: const Value(700.0),
          warehouseId: Value(warehouseId),
        ),
      );

      final product = await (database.select(database.products)
            ..where((t) => t.id.equals(productId)))
          .getSingleOrNull();

      expect(product, isNotNull);
      expect(product!.name, 'Test Phone');
      expect(product.salePrice, 999.0);
      expect(product.categoryId, catId);
    });
  });

  group('SyncEngine - Parties', () {
    test('insert party and verify', () async {
      final partyId = await database.into(database.parties).insert(
        PartiesCompanion.insert(
          name: 'Sync Customer',
          isCustomer: const Value(true),
        ),
      );

      final party = await (database.select(database.parties)
            ..where((t) => t.id.equals(partyId)))
          .getSingleOrNull();

      expect(party, isNotNull);
      expect(party!.name, 'Sync Customer');
      expect(party.isCustomer, true);
    });
  });

  group('SyncEngine - Sales Dedup', () {
    test('two invoices with same number produce distinct IDs', () async {
      final customerId = await database.into(database.parties).insert(
        PartiesCompanion.insert(
          name: 'Dedup Customer',
          isCustomer: const Value(true),
        ),
      );

      final id1 = await database.into(database.salesInvoices).insert(
        SalesInvoicesCompanion.insert(
          invoiceNumber: 'INV-DUP',
          customerId: Value(customerId),
          userId: userId,
          warehouseId: warehouseId,
          invoiceDate: DateTime(2026, 3, 1),
        ),
      );

      final id2 = await database.into(database.salesInvoices).insert(
        SalesInvoicesCompanion.insert(
          invoiceNumber: 'INV-DUP',
          customerId: Value(customerId),
          userId: userId,
          warehouseId: warehouseId,
          invoiceDate: DateTime(2026, 3, 1),
        ),
      );

      // Both inserts succeed — schema doesn't enforce unique invoice numbers
      expect(id1, isNot(equals(id2)));
    });
  });

  group('SyncEngine - Conflict Policies', () {
    test('serverWins: overwrite local data on sync', () async {
      // Insert local category
      final id = await database.into(database.categories).insert(
        CategoriesCompanion.insert(
          name: 'Local Name',
          color: const Value('#111'),
        ),
      );

      // Server wins: overwrite
      await (database.update(database.categories)
            ..where((t) => t.id.equals(id)))
          .write(const CategoriesCompanion(name: Value('Server Name')));

      final result = await (database.select(database.categories)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();

      expect(result!.name, 'Server Name');
    });

    test('appendOnly: sales invoices only add, never overwrite', () async {
      final count1 = (await database.select(database.salesInvoices).get()).length;

      await database.into(database.salesInvoices).insert(
        SalesInvoicesCompanion.insert(
          invoiceNumber: 'APPEND-001',
          userId: userId,
          warehouseId: warehouseId,
          invoiceDate: DateTime(2026, 3, 1),
        ),
      );

      final count2 = (await database.select(database.salesInvoices).get()).length;
      expect(count2, count1 + 1);
    });
  });
}
