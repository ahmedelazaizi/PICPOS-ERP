import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

// Task 11 (سجلُّ الطاولة) — يغذّي `logsForEntity` شاشةَ سجل الطاولة، وهو
// استعلامٌ خالصٌ على `ActivityLogs` المسلسَل بالهاش (ICR-03) لا جدولٌ جديد.
// الاختبارُ هنا يثبت ما تعتمد عليه الشاشة: التصفيةَ على entityType وentityId
// معاً (لا أحدَهما)، والترتيبَ من الأحدث، والحدَّ الأقصى.
void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting();
  });

  tearDown(() async {
    await database.close();
  });

  // زرعٌ مباشرٌ بـ`createdAt` صريحٍ — لا عبر `logActivity` التي تُثبّت
  // `DateTime.now()` وقد تتساوى طوابعُ استدعاءاتٍ متتابعةٍ على ساعةٍ خشِنة،
  // فيصير اختبارُ الترتيب هشّاً.
  Future<void> seed({
    required String entityType,
    required int entityId,
    required String action,
    required DateTime createdAt,
  }) => database.into(database.activityLogs).insert(
        ActivityLogsCompanion.insert(
          userName: 'اختبار',
          action: action,
          entityType: entityType,
          entityId: Value(entityId),
          description: action,
          createdAt: Value(createdAt),
        ),
      );

  group('ActivityLogsDao.logsForEntity', () {
    test('يُصفّي على entityType وentityId معاً ويرتّب من الأحدث', () async {
      final t0 = DateTime(2026, 8, 16, 19, 30);
      await seed(
        entityType: 'table',
        entityId: 1,
        action: 'table_open',
        createdAt: t0,
      );
      await seed(
        // طاولةٌ أخرى — لا يجب أن تظهر رغم نفس entityType.
        entityType: 'table',
        entityId: 2,
        action: 'table_open',
        createdAt: t0.add(const Duration(minutes: 5)),
      );
      await seed(
        entityType: 'table',
        entityId: 1,
        action: 'table_close',
        createdAt: t0.add(const Duration(hours: 1, minutes: 18)),
      );
      await seed(
        // كيانٌ آخر بنفس المعرّف (١) — لا يجب أن يظهر رغم تطابق entityId.
        entityType: 'table_order',
        entityId: 1,
        action: 'checkout_table',
        createdAt: t0.add(const Duration(minutes: 30)),
      );

      final logs = await database.logsForEntity(
        entityType: 'table',
        entityId: 1,
      );

      expect(
        logs.map((l) => l.action).toList(),
        ['table_close', 'table_open'],
        reason: 'سطرا الطاولة (١) فقط، والأحدثُ (الإغلاق) أوّلاً',
      );
      expect(logs.every((l) => l.entityId == 1 && l.entityType == 'table'),
          isTrue);
    });

    test('يحترم الحدَّ الأقصى limit', () async {
      for (var i = 0; i < 5; i++) {
        await seed(
          entityType: 'table',
          entityId: 9,
          action: 'table_status_change',
          createdAt: DateTime(2026, 8, 16, 10, i),
        );
      }

      final logs = await database.logsForEntity(
        entityType: 'table',
        entityId: 9,
        limit: 3,
      );

      expect(logs, hasLength(3));
      // الحدُّ يُبقي الأحدثَ — الدقائق ٤ و٣ و٢، لا الأقدم.
      expect(logs.first.createdAt, DateTime(2026, 8, 16, 10, 4));
    });

    test('طاولةٌ بلا سجلٍّ تُرجع قائمةً فارغة', () async {
      final logs = await database.logsForEntity(
        entityType: 'table',
        entityId: 999,
      );
      expect(logs, isEmpty);
    });
  });
}
