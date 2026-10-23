// test/unit/bookings_dao_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int serviceId;
  late int resourceId;

  // «الآن» ثابتٌ يُمرَّر صراحةً: قاعدةُ «لا حجزَ في الماضي» تقارن به،
  // ولو قرأ الكودُ ساعةَ النظام لصار الاختبارُ رهينةَ وقتِ التشغيل.
  final now = DateTime(2026, 8, 20, 9);

  setUp(() async {
    db = AppDatabase.forTesting();
    // المفاتيحُ الأجنبيّة مُنفَذة في `forTesting` — يُزرع الأبُ قبل الابن.
    serviceId = await db.into(db.bookingServices).insert(
          BookingServicesCompanion.insert(
            name: 'قص شعر',
            durationMinutes: const Value(45),
            bufferMinutes: const Value(15),
          ),
        );
    resourceId = await db.into(db.bookingResources).insert(
          BookingResourcesCompanion.insert(name: 'محمد علي'),
        );
  });

  tearDown(() async {
    // لا `db.close()`: يعلّق مؤقّتَ drift في المنطقة الوهميّة فيتجمّد
    // الاختبار. الحياةُ تنتهي بانتهاء العمليّة.
  });

  test('الإنشاءُ يحسب النهايةَ من المدّة وفترةِ التنظيف', () async {
    final id = await db.createBooking(
      customerName: 'أحمد',
      serviceId: serviceId,
      resourceId: resourceId,
      startsAt: DateTime(2026, 8, 20, 10),
      now: now,
    );
    final row = await (db.select(db.bookings)..where((b) => b.id.equals(id)))
        .getSingle();
    expect(row.endsAt, DateTime(2026, 8, 20, 11)); // 45 + 15
    expect(row.status, 'pending');
    expect(row.depositStatus, 'held');
  });

  test('حجزٌ متداخلٌ على نفس الموظَّف يُرفَض', () async {
    await db.createBooking(
      customerName: 'أحمد',
      serviceId: serviceId,
      resourceId: resourceId,
      startsAt: DateTime(2026, 8, 20, 10),
      now: now,
    );
    expect(
      () => db.createBooking(
        customerName: 'سارة',
        serviceId: serviceId,
        resourceId: resourceId,
        startsAt: DateTime(2026, 8, 20, 10, 30),
        now: now,
      ),
      throwsA(isA<BookingConflictException>()),
    );
  });

  test('التلاصقُ مسموح — النهايةُ تساوي البداية', () async {
    await db.createBooking(
      customerName: 'أحمد',
      serviceId: serviceId,
      resourceId: resourceId,
      startsAt: DateTime(2026, 8, 20, 10),
      now: now,
    );
    final id = await db.createBooking(
      customerName: 'سارة',
      serviceId: serviceId,
      resourceId: resourceId,
      startsAt: DateTime(2026, 8, 20, 11), // بعد 45+15 تماماً
      now: now,
    );
    expect(id, greaterThan(0));
  });

  test('حجزٌ بلا موظَّفٍ لا يشارك في فحص التعارض', () async {
    await db.createBooking(
      customerName: 'أحمد',
      serviceId: serviceId,
      resourceId: null,
      startsAt: DateTime(2026, 8, 20, 10),
      now: now,
    );
    final id = await db.createBooking(
      customerName: 'سارة',
      serviceId: serviceId,
      resourceId: null,
      startsAt: DateTime(2026, 8, 20, 10),
      now: now,
    );
    expect(id, greaterThan(0));
  });

  test('الملغى ومَن لم يحضر يُفرّغان الوقت', () async {
    final first = await db.createBooking(
      customerName: 'أحمد',
      serviceId: serviceId,
      resourceId: resourceId,
      startsAt: DateTime(2026, 8, 20, 10),
      now: now,
    );
    await (db.update(db.bookings)..where((b) => b.id.equals(first)))
        .write(const BookingsCompanion(status: Value('cancelled')));
    final second = await db.createBooking(
      customerName: 'سارة',
      serviceId: serviceId,
      resourceId: resourceId,
      startsAt: DateTime(2026, 8, 20, 10),
      now: now,
    );
    expect(second, greaterThan(0));

    // `no_show` يُفرّغ الوقتَ أيضاً — لا الإلغاءُ وحدَه.
    await (db.update(db.bookings)..where((b) => b.id.equals(second)))
        .write(const BookingsCompanion(status: Value('no_show')));
    final third = await db.createBooking(
      customerName: 'منى',
      serviceId: serviceId,
      resourceId: resourceId,
      startsAt: DateTime(2026, 8, 20, 10),
      now: now,
    );
    expect(third, greaterThan(0));
  });

  test('حجزٌ يعبر منتصفَ الليل يُكتَشف رغم أنّ الجديدَ يبدأ بعد منتصف الليل',
      () async {
    // مدّةٌ ٦٠ دقيقةً بلا فترة تنظيف: يبدأ ٢٣:٥٠ فينتهي ٠٠:٥٠ اليومَ التالي —
    // يعبر منتصفَ الليل فعلاً.
    final midnightServiceId = await db.into(db.bookingServices).insert(
          BookingServicesCompanion.insert(
            name: 'خدمةٌ تعبر منتصفَ الليل',
            durationMinutes: const Value(60),
          ),
        );
    await db.createBooking(
      customerName: 'أحمد',
      serviceId: midnightServiceId,
      resourceId: resourceId,
      startsAt: DateTime(2026, 8, 20, 23, 50),
      now: now,
    );
    expect(
      () => db.createBooking(
        customerName: 'سارة',
        serviceId: midnightServiceId,
        resourceId: resourceId,
        startsAt: DateTime(2026, 8, 21, 0, 10), // داخل [23:50, 00:50)
        now: now,
      ),
      throwsA(isA<BookingConflictException>()),
    );
  });

  test('لا حجزَ في الماضي', () async {
    expect(
      () => db.createBooking(
        customerName: 'أحمد',
        serviceId: serviceId,
        resourceId: resourceId,
        startsAt: DateTime(2026, 8, 20, 8), // قبل `now`
        now: now,
      ),
      throwsA(isA<BookingInPastException>()),
    );
  });
}
