import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/domain/models/table_status.dart';
import 'package:ural_erp/services/table_session_service.dart';

void main() {
  late AppDatabase db;
  late TableSessionService service;

  setUp(() {
    db = AppDatabase.forTesting();
    service = TableSessionService(db);
  });
  tearDown(() => db.close());

  Future<int> newTable(String name) => db.createTable(name: name);

  Future<RestaurantTable> readTable(int id) =>
      (db.select(db.restaurantTables)..where((t) => t.id.equals(id)))
          .getSingle();

  group('openTable', () {
    test('يفتح طاولةً متاحةً ويثبّت عددَ الأشخاص', () async {
      final t = await newTable('ط٧');
      final orderId = await service.openTable(
          tableId: t, guestCount: 4, userId: null, userName: 'أحمد');

      expect((await readTable(t)).status, TableStatus.occupied);
      final order = await db.getActiveOrderForTable(t);
      expect(order!.id, orderId);
      expect(order.guestCount, 4);
    });

    test('يكتب سطراً في السجل', () async {
      final t = await newTable('ط٨');
      await service.openTable(
          tableId: t, guestCount: 2, userId: null, userName: 'أحمد');

      final logs = await (db.select(db.activityLogs)
            ..where((l) => l.entityType.equals('table')))
          .get();
      expect(logs, hasLength(1));
      expect(logs.single.action, 'table_open');
      expect(logs.single.entityId, t);
    });

    test('يرفض طاولةً مشغولة', () async {
      final t = await newTable('ط٩');
      await service.openTable(
          tableId: t, guestCount: 2, userId: null, userName: 'أحمد');

      expect(
        () => service.openTable(
            tableId: t, guestCount: 2, userId: null, userName: 'أحمد'),
        throwsA(isA<TableTransitionException>()),
      );
    });

    test('يرفض عددَ أشخاصٍ أقلَّ من واحد', () async {
      final t = await newTable('ط١٠');
      expect(
        () => service.openTable(
            tableId: t, guestCount: 0, userId: null, userName: 'أحمد'),
        throwsA(isA<TableTransitionException>()),
      );
    });
  });

  group('closeTable', () {
    test('يرفض الإغلاقَ قبل اكتمال الدفع', () async {
      final t = await newTable('ط١١');
      final orderId = await service.openTable(
          tableId: t, guestCount: 2, userId: null, userName: 'أحمد');
      await (db.update(db.tableOrders)..where((o) => o.id.equals(orderId)))
          .write(const TableOrdersCompanion(
              total: Value(100), paidAmount: Value(60)));

      expect(
        () => service.closeTable(
            tableId: t, userId: null, userName: 'أحمد'),
        throwsA(isA<TableTransitionException>()),
      );
      expect((await readTable(t)).status, TableStatus.occupied);
    });

    test('يُغلق ويُحرّر الطاولة عند اكتمال الدفع', () async {
      final t = await newTable('ط١٢');
      final orderId = await service.openTable(
          tableId: t, guestCount: 2, userId: null, userName: 'أحمد');
      await (db.update(db.tableOrders)..where((o) => o.id.equals(orderId)))
          .write(const TableOrdersCompanion(
              total: Value(100), paidAmount: Value(100)));

      await service.closeTable(tableId: t, userId: null, userName: 'أحمد');

      expect((await readTable(t)).status, TableStatus.available);
      expect(await db.getActiveOrderForTable(t), isNull);
    });
  });

  group('cancelOrder', () {
    test('يرفض إلغاءَ طلبٍ دُفع منه شيء', () async {
      final t = await newTable('ط١٣');
      final orderId = await service.openTable(
          tableId: t, guestCount: 2, userId: null, userName: 'أحمد');
      await (db.update(db.tableOrders)..where((o) => o.id.equals(orderId)))
          .write(const TableOrdersCompanion(
              total: Value(100), paidAmount: Value(40)));

      expect(
        () => service.cancelOrder(
            tableId: t, userId: null, userName: 'أحمد'),
        throwsA(isA<TableTransitionException>()),
      );
    });

    test('يُلغي طلباً بكراً ويُحرّر الطاولة', () async {
      final t = await newTable('ط١٤');
      await service.openTable(
          tableId: t, guestCount: 2, userId: null, userName: 'أحمد');

      await service.cancelOrder(tableId: t, userId: null, userName: 'أحمد');

      expect((await readTable(t)).status, TableStatus.available);
    });
  });

  group('setTableStatus', () {
    test('يُخرج طاولةً متاحةً من الخدمة ويُعيدها', () async {
      final t = await newTable('ط١٥');
      await service.setTableStatus(
          tableId: t,
          status: TableStatus.outOfService,
          userId: null,
          userName: 'أحمد');
      expect((await readTable(t)).status, TableStatus.outOfService);

      await service.setTableStatus(
          tableId: t,
          status: TableStatus.available,
          userId: null,
          userName: 'أحمد');
      expect((await readTable(t)).status, TableStatus.available);
    });

    test('يرفض إخراجَ طاولةٍ عليها طلبٌ من الخدمة', () async {
      final t = await newTable('ط١٦');
      await service.openTable(
          tableId: t, guestCount: 2, userId: null, userName: 'أحمد');

      expect(
        () => service.setTableStatus(
            tableId: t,
            status: TableStatus.outOfService,
            userId: null,
            userName: 'أحمد'),
        throwsA(isA<TableTransitionException>()),
      );
    });
  });
}
