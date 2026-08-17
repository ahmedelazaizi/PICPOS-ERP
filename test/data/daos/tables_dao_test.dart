import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase.forTesting();
  });

  tearDown(() async {
    await database.close();
  });

  group('TablesDao - Table & Section Management', () {
    test('createSection - should create a new section', () async {
      final sectionId = await database.createSection('VIP Section');
      expect(sectionId, isPositive);
    });

    test('createTable - should create a new table in a section', () async {
      final sectionId = await database.createSection('Main Hall');
      final tableId = await database.createTable(
        name: 'Table 1',
        sectionId: sectionId,
        capacity: 4,
      );
      expect(tableId, isPositive);
    });

    test('updateTableStatus - should change table status', () async {
      final sectionId = await database.createSection('Main Hall');
      final tableId = await database.createTable(
        name: 'T1',
        sectionId: sectionId,
        capacity: 2,
      );

      await database.updateTableStatus(tableId, 'occupied');
      
      final table = await (database.select(database.restaurantTables)
            ..where((t) => t.id.equals(tableId)))
          .getSingle();
          
      expect(table.status, 'occupied');
    });
  });

  group('TablesDao - Order Management', () {
    test('createTableOrder - should create order and mark table as occupied', () async {
      final sectionId = await database.createSection('Dining');
      final tableId = await database.createTable(
        name: 'Table A1',
        sectionId: sectionId,
        capacity: 4,
      );

      final orderId = await database.createTableOrder(tableId);
      expect(orderId, isPositive);

      final table = await (database.select(database.restaurantTables)
            ..where((t) => t.id.equals(tableId)))
          .getSingle();
      expect(table.status, 'occupied');
    });

    test('createTableOrder - يرفض طلباً ثانياً على طاولةٍ لها طلبٌ حيّ', () async {
      final sectionId = await database.createSection('Dining');
      final tableId = await database.createTable(
        name: 'Table A2',
        sectionId: sectionId,
        capacity: 4,
      );

      final firstId = await database.createTableOrder(tableId);

      // صفّان يطابقان getActiveOrderForTable يجعلان getSingleOrNull() ترمي
      // StateError على كلّ قراءةٍ لاحقة — الطاولةُ تصير غيرَ قابلةٍ للإغلاق
      // ولا للإلغاء ولا حتى للعرض.
      await expectLater(
        database.createTableOrder(tableId),
        throwsA(isA<StateError>()),
      );

      final orders = await (database.select(database.tableOrders)
            ..where((o) => o.tableId.equals(tableId)))
          .get();
      expect(orders, hasLength(1));
      expect(orders.single.id, firstId);
      expect(await database.getActiveOrderForTable(tableId), isNotNull);
    });

    test('transferTableOrder - should move active order and update statuses', () async {
      final sectionId = await database.createSection('Dining');
      final fromTableId = await database.createTable(
        name: 'Table 1',
        sectionId: sectionId,
        capacity: 4,
      );
      final toTableId = await database.createTable(
        name: 'Table 2',
        sectionId: sectionId,
        capacity: 4,
      );

      // Create order on Table 1
      final orderId = await database.createTableOrder(fromTableId);
      
      // Transfer to Table 2
      await database.transferTableOrder(fromTableId, toTableId);

      // Verify Table 1 is now available
      final fromTable = await (database.select(database.restaurantTables)
            ..where((t) => t.id.equals(fromTableId)))
          .getSingle();
      expect(fromTable.status, 'available');

      // Verify Table 2 is now occupied
      final toTable = await (database.select(database.restaurantTables)
            ..where((t) => t.id.equals(toTableId)))
          .getSingle();
      expect(toTable.status, 'occupied');

      // Verify order now points to Table 2
      final order = await (database.select(database.tableOrders)
            ..where((o) => o.id.equals(orderId)))
          .getSingle();
      expect(order.tableId, toTableId);
    });

    test('transferTableOrder - should throw if target table not available', () async {
      final sectionId = await database.createSection('Dining');
      final fromTableId = await database.createTable(name: 'T1', sectionId: sectionId);
      final toTableId = await database.createTable(name: 'T2', sectionId: sectionId);

      // Mark T2 as occupied manually
      await database.updateTableStatus(toTableId, 'occupied');

      // Create order on T1
      await database.createTableOrder(fromTableId);
      
      expect(
        () => database.transferTableOrder(fromTableId, toTableId),
        throwsException,
      );
    });
  });
}
