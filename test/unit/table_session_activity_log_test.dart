// سدُّ ثغرةِ سجلِّ الحجز — كان الحجزُ يُنشَأ بلا أثرٍ في `ActivityLogs`
// (مسارُه القديم: الودجتُ ينادي `restaurantRepo.createReservation` مباشرةً
// بلا سطرِ سجلٍّ واحد). هذا الاختبارُ يقيس السلوكَ من الخدمة — لا من
// الودجت، فلا يفتح شاشةً ولا يُركِّب `ProviderScope`.
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/table_session_service.dart';

void main() {
  late AppDatabase db;
  late TableSessionService service;
  late int tableId;

  setUp(() async {
    db = AppDatabase.forTesting();
    // `forTesting` يُنفِذ المفاتيحَ الأجنبيّة — ازرع القسمَ قبل الطاولة.
    final sectionId = await db.into(db.tableSections).insert(
          TableSectionsCompanion.insert(name: 'الصالة'),
        );
    tableId = await db.into(db.restaurantTables).insert(
          RestaurantTablesCompanion.insert(
            name: 'ط١',
            sectionId: Value(sectionId),
          ),
        );
    service = TableSessionService(db);
  });

  tearDown(() async => db.close());

  Future<List<ActivityLog>> logsOfType(String action) =>
      (db.select(db.activityLogs)..where((l) => l.action.equals(action))).get();

  test('حجزُ الطاولة يترك سطرَ سجلّ يسمّي العميل', () async {
    await service.reserveTable(
      tableId: tableId,
      customerName: 'أحمد محمد',
      customerPhone: '0791234567',
      reservationTime: DateTime(2026, 9, 1, 20),
      partySize: 4,
      userId: null,
      userName: 'كاشير',
    );

    final logs = await logsOfType('table_reserve');
    expect(logs, hasLength(1),
        reason: 'الحجزُ كان يُنشَأ بلا أثر — فمن حجز الطاولةَ ومتى؟');
    expect(logs.single.description, contains('أحمد محمد'));
  });

  test('سطرُ الحجز يحمل نوعَ الكيان والمعرّف الصحيحَين', () async {
    // `userId: null` عن قصد — `ActivityLogs.userId` مفتاحٌ أجنبيٌّ إلى
    // `Users`، ولا مستخدمَ مزروعاً بهذا الاختبار الوحدويّ الصغير.
    await service.reserveTable(
      tableId: tableId,
      customerName: 'سارة علي',
      reservationTime: DateTime(2026, 9, 2, 19),
      partySize: 2,
      userId: null,
      userName: 'مدير',
    );

    final logs = await logsOfType('table_reserve');
    expect(logs, hasLength(1));
    expect(logs.single.entityType, 'table');
    expect(logs.single.entityId, tableId);
    expect(logs.single.userName, 'مدير');
  });

  test('الحجزُ يقلب حالةَ الطاولة إلى محجوزة كسابق عهده', () async {
    await service.reserveTable(
      tableId: tableId,
      customerName: 'محمد خالد',
      reservationTime: DateTime(2026, 9, 3, 21),
      partySize: 3,
      userId: null,
      userName: 'كاشير',
    );

    final table = await (db.select(db.restaurantTables)
          ..where((t) => t.id.equals(tableId)))
        .getSingle();
    expect(table.status, 'reserved');
  });
}
