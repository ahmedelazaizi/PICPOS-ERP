// لوحةُ الحجوزات — استعلامُها الحيُّ ونطاقُ فرعِه.
//
// يُقاس هنا ما يُخفي موعداً قائماً أو يُظهر ما لا يجوز:
//  ‏١) **الوصلُ يساريٌّ للمورد** — حجزٌ بلا موظَّفٍ مسموحٌ، ووصلٌ داخليٌّ
//     كان سيُسقطه من اللوحة صامتاً.
//  ‏٢) **نطاقُ الفرع يفشل مغلقاً** — نطاقٌ فارغٌ لا يعني «الكلّ».
//  ‏٣) **حيٌّ لا لقطة** — حجزٌ جديدٌ يظهر بلا تحديثٍ يدويّ. وهذا بالضبط
//     الدرسُ المقيسُ في قائمة الفواتير (2026-08-23): إشارةٌ تُبثّ ولا توقظ
//     أحداً تُنتج شاشةً لا تتحدّث.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/domain/models/picpos_booking_view.dart';

void main() {
  late AppDatabase db;
  late int serviceId;
  late int resourceId;
  late DateTime day;

  setUp(() async {
    db = AppDatabase.forTesting();
    day = DateTime(2026, 9, 1);
    serviceId = await db.into(db.bookingServices).insert(
          BookingServicesCompanion.insert(
            name: 'قصّ شعر',
            durationMinutes: const Value(45),
            price: const Value(120),
            colorHex: const Value('#0250D3'),
          ),
        );
    // فرعٌ ثانٍ: البذرةُ تُنشئ الفرعَ الأوّلَ وحدَه، والمفتاحُ الأجنبيُّ
    // يرفض `branch_id = 2` بدونه.
    await db.into(db.branches).insert(
          BranchesCompanion.insert(
              name: 'فرع العقبة', code: const Value('BR2')),
        );
    resourceId = await db.into(db.bookingResources).insert(
          BookingResourcesCompanion.insert(
            name: 'محمد علي',
            role: const Value('حلاق أول'),
            colorHex: const Value('#0250D3'),
          ),
        );
  });

  tearDown(() => db.close());

  Future<int> insertBooking({
    int? resource,
    int? branch,
    String status = 'confirmed',
    int hour = 10,
  }) =>
      db.into(db.bookings).insert(
            BookingsCompanion.insert(
              customerName: 'عميل $hour',
              serviceId: serviceId,
              resourceId: Value(resource),
              startsAt: day.add(Duration(hours: hour)),
              endsAt: day.add(Duration(hours: hour, minutes: 45)),
              status: Value(status),
              branchId: Value(branch),
            ),
          );

  Future<List<BookingBoardRow>> board({List<int>? allowed}) => db
      .watchBookingsBoard(day, day.add(const Duration(days: 1)),
          allowedBranchIds: allowed)
      .first;

  group('الوصلُ لا يُسقط موعداً قائماً', () {
    test('حجزٌ بلا موردٍ يظهر — والوصلُ يساريّ', () async {
      await insertBooking(resource: null);
      final rows = await board();
      expect(rows, hasLength(1),
          reason: 'وصلٌ داخليٌّ كان سيُخفي موعداً لأنّ أحداً لم يُسنِده');
      expect(rows.single.resourceName, isNull);
      expect(rows.single.serviceName, 'قصّ شعر');
    });

    test('حجزٌ بموردٍ يحمل اسمَه ودورَه ولونَه', () async {
      await insertBooking(resource: resourceId);
      final r = (await board()).single;
      expect(r.resourceName, 'محمد علي');
      expect(r.resourceRole, 'حلاق أول');
      expect(r.resourceColorHex, '#0250D3');
      expect(r.servicePrice, 120);
    });
  });

  group('نطاقُ الفرع', () {
    test('معدومٌ ⇒ وصولٌ كامل', () async {
      await insertBooking(branch: 1);
      await insertBooking(branch: 2, hour: 11);
      expect(await board(), hasLength(2));
    });

    test('فارغٌ ⇒ يفشل مغلقاً ولا يُظهر حجوزَ الفرعِ المعدوم', () async {
      await insertBooking(branch: 1);
      await insertBooking(branch: null, hour: 11);
      expect(await board(allowed: const []), isEmpty,
          reason: 'الفرعُ المعدومُ في تنصيبةٍ بفرعٍ واحدٍ هو كلُّ الحجوزات — '
              'فإظهارُه لمن لا وصولَ له يقلب «لا وصول» إلى «الكلّ»');
    });

    test('محصورٌ ⇒ فروعُه والفرعُ المعدوم', () async {
      await insertBooking(branch: 1);
      await insertBooking(branch: 2, hour: 11);
      await insertBooking(branch: null, hour: 12);
      final rows = await board(allowed: const [1]);
      expect(rows, hasLength(2));
    });
  });

  group('حيٌّ لا لقطة', () {
    test('حجزٌ جديدٌ يصل المشتركَ بلا إعادةِ استعلام', () async {
      final stream = db
          .watchBookingsBoard(day, day.add(const Duration(days: 1)))
          .asBroadcastStream();
      final seen = <int>[];
      final sub = stream.listen((rows) => seen.add(rows.length));
      await pumpEventQueue();

      await insertBooking(hour: 10);
      await pumpEventQueue();
      await insertBooking(hour: 11);
      await pumpEventQueue();
      await sub.cancel();

      expect(seen.last, 2,
          reason: 'اللوحةُ تعرض «الآن» — ولو كانت لقطةً لبقيت على الصفر');
      expect(seen.length, greaterThanOrEqualTo(3),
          reason: 'كلُّ إدراجٍ يبثّ — لا الأوّلُ وحدَه');
    });
  });

  group('المدى يومٌ واحد', () {
    test('حجزُ الغدِ لا يظهر في لوحة اليوم', () async {
      await db.into(db.bookings).insert(
            BookingsCompanion.insert(
              customerName: 'غداً',
              serviceId: serviceId,
              startsAt: day.add(const Duration(days: 1, hours: 1)),
              endsAt: day.add(const Duration(days: 1, hours: 2)),
            ),
          );
      expect(await board(), isEmpty);
    });
  });
}
