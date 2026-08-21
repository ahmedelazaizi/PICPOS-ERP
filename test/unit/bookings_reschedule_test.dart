// test/unit/bookings_reschedule_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int serviceId;
  late int resourceA;
  late int resourceB;
  final now = DateTime(2026, 8, 20, 9);

  setUp(() async {
    db = AppDatabase.forTesting();
    serviceId = await db.into(db.bookingServices).insert(
          BookingServicesCompanion.insert(
            name: 'مساج',
            durationMinutes: const Value(60),
          ),
        );
    resourceA = await db.into(db.bookingResources).insert(
          BookingResourcesCompanion.insert(name: 'محمد'),
        );
    resourceB = await db.into(db.bookingResources).insert(
          BookingResourcesCompanion.insert(name: 'ريم'),
        );
  });

  test('إسنادُ حجزٍ من قائمة الانتظار يفحص التعارض', () async {
    // حجزٌ قائمٌ على «محمد» 10:00-11:00
    await db.createBooking(
      customerName: 'أحمد',
      serviceId: serviceId,
      resourceId: resourceA,
      startsAt: DateTime(2026, 8, 20, 10),
      now: now,
    );
    // حجزٌ بلا موظَّفٍ في نفس الوقت — وُلد بلا تعارضٍ لأنه بلا موظَّف
    final waiting = await db.createBooking(
      customerName: 'سارة',
      serviceId: serviceId,
      resourceId: null,
      startsAt: DateTime(2026, 8, 20, 10),
      now: now,
    );
    // إسنادُه إلى «محمد» يجب أن يُرفض — وهذا هو الموضعُ الذي يتسرّب منه
    // التعارضُ لو اكتُفي بالفحص عند الإنشاء.
    expect(
      () => db.updateBookingSlot(waiting, resourceId: resourceA, now: now),
      throwsA(isA<BookingConflictException>()),
    );
  });

  test('إسنادُه إلى موظَّفٍ فارغٍ ينجح', () async {
    final waiting = await db.createBooking(
      customerName: 'سارة',
      serviceId: serviceId,
      resourceId: null,
      startsAt: DateTime(2026, 8, 20, 10),
      now: now,
    );
    await db.updateBookingSlot(waiting, resourceId: resourceB, now: now);
    final row = await (db.select(db.bookings)..where((b) => b.id.equals(waiting)))
        .getSingle();
    expect(row.resourceId, resourceB);
  });

  test('التأجيلُ يفحص التعارضَ أيضاً — لا الإسنادُ وحدَه', () async {
    await db.createBooking(
      customerName: 'أحمد',
      serviceId: serviceId,
      resourceId: resourceA,
      startsAt: DateTime(2026, 8, 20, 12),
      now: now,
    );
    final mine = await db.createBooking(
      customerName: 'سارة',
      serviceId: serviceId,
      resourceId: resourceA,
      startsAt: DateTime(2026, 8, 20, 10),
      now: now,
    );
    // تأجيلٌ ساعتين يوقعه فوق حجز أحمد
    expect(
      () => db.updateBookingSlot(
        mine,
        startsAt: DateTime(2026, 8, 20, 12),
        now: now,
      ),
      throwsA(isA<BookingConflictException>()),
    );
  });

  test('الحجزُ لا يتعارض مع نفسِه عند التأجيل', () async {
    final mine = await db.createBooking(
      customerName: 'سارة',
      serviceId: serviceId,
      resourceId: resourceA,
      startsAt: DateTime(2026, 8, 20, 10),
      now: now,
    );
    await db.updateBookingSlot(
      mine,
      startsAt: DateTime(2026, 8, 20, 10, 30),
      now: now,
    );
    final row = await (db.select(db.bookings)..where((b) => b.id.equals(mine)))
        .getSingle();
    expect(row.startsAt, DateTime(2026, 8, 20, 10, 30));
    expect(row.endsAt, DateTime(2026, 8, 20, 11, 30));
  });

  test('تقصيرُ مدّةِ الخدمة لاحقاً لا يقصّر حجزاً قائماً عند إعادة الإسناد',
      () async {
    // `endsAt` **يُخزَّن ولا يُحسَب** (§٥). ولو أعادت `updateBookingSlot`
    // اشتقاقَه من مدّةِ الخدمة **الحاليّة** لعاد الأثرُ الرجعيُّ من أكثرِ
    // المسارات استعمالاً: قصُّ شعرٍ ٦٠ دقيقةً محجوزٌ ١٠:٠٠–١١:٠٠، ثم يقصّر
    // المالكُ الخدمةَ إلى ٣٠، ثم ينقل المضيفُ الحجزَ من محمدٍ إلى ريم بلا
    // تغييرِ وقتٍ — فيصير الصفُّ ١٠:٠٠–١٠:٣٠ ويُفتح ١٠:٣٠–١١:٠٠ للحجز
    // والموظَّفةُ ما تزال تعمل.
    final id = await db.createBooking(
      customerName: 'سارة',
      serviceId: serviceId,
      resourceId: resourceA,
      startsAt: DateTime(2026, 8, 20, 10),
      now: now,
    );

    // المالكُ يقصّر الخدمةَ تحت الحجز القائم.
    await (db.update(db.bookingServices)..where((s) => s.id.equals(serviceId)))
        .write(const BookingServicesCompanion(durationMinutes: Value(30)));

    // إعادةُ إسنادٍ خالصة — لا `startsAt` جديد.
    await db.updateBookingSlot(id, resourceId: resourceB, now: now);

    final row = await (db.select(db.bookings)..where((b) => b.id.equals(id)))
        .getSingle();
    expect(row.resourceId, resourceB);
    expect(row.startsAt, DateTime(2026, 8, 20, 10));
    expect(row.endsAt, DateTime(2026, 8, 20, 11),
        reason: 'الطولُ المخزَّنُ هو المرجع — لا مدّةُ الخدمة اليوم');
  });

  test('إطالةُ مدّةِ الخدمة لاحقاً لا تختلق تعارضاً عند إعادة الإسناد',
      () async {
    // الوجهُ الآخرُ لنفس الخلل: لو طالت الخدمةُ بدل أن تقصر، لرمت إعادةُ
    // الإسنادِ `BookingConflictException` بلا سببٍ ظاهرٍ للمضيف.
    final blocking = await db.createBooking(
      customerName: 'أحمد',
      serviceId: serviceId,
      resourceId: resourceB,
      startsAt: DateTime(2026, 8, 20, 11, 30),
      now: now,
    );
    expect(blocking, greaterThan(0));

    final mine = await db.createBooking(
      customerName: 'سارة',
      serviceId: serviceId,
      resourceId: resourceA,
      startsAt: DateTime(2026, 8, 20, 10),
      now: now,
    );

    // المالكُ يطيل الخدمةَ من ٦٠ إلى ١٢٠ — فلو أُعيد الاشتقاقُ لامتدّ حجزُ
    // سارة إلى ١٢:٠٠ ووقع فوق حجز أحمد على ريم.
    await (db.update(db.bookingServices)..where((s) => s.id.equals(serviceId)))
        .write(const BookingServicesCompanion(durationMinutes: Value(120)));

    await db.updateBookingSlot(mine, resourceId: resourceB, now: now);

    final row = await (db.select(db.bookings)..where((b) => b.id.equals(mine)))
        .getSingle();
    expect(row.resourceId, resourceB);
    expect(row.endsAt, DateTime(2026, 8, 20, 11));
  });

  test('التأجيلُ يحفظ الطولَ المخزَّنَ لا مدّةَ الخدمة الحاليّة', () async {
    final id = await db.createBooking(
      customerName: 'سارة',
      serviceId: serviceId,
      resourceId: resourceA,
      startsAt: DateTime(2026, 8, 20, 10),
      now: now,
    );
    await (db.update(db.bookingServices)..where((s) => s.id.equals(serviceId)))
        .write(const BookingServicesCompanion(durationMinutes: Value(15)));

    await db.updateBookingSlot(
      id,
      startsAt: DateTime(2026, 8, 20, 14),
      now: now,
    );

    final row = await (db.select(db.bookings)..where((b) => b.id.equals(id)))
        .getSingle();
    // ينتقل الصفُّ كتلةً واحدةً بطولِه المخزَّن (٦٠ دقيقة) لا بمدّةِ اليوم.
    expect(row.startsAt, DateTime(2026, 8, 20, 14));
    expect(row.endsAt, DateTime(2026, 8, 20, 15));
  });

  test('التأجيلُ إلى الماضي يُرفض', () async {
    final mine = await db.createBooking(
      customerName: 'سارة',
      serviceId: serviceId,
      resourceId: resourceA,
      startsAt: DateTime(2026, 8, 20, 10),
      now: now,
    );
    expect(
      () => db.updateBookingSlot(
        mine,
        startsAt: DateTime(2026, 8, 20, 8),
        now: now,
      ),
      throwsA(isA<BookingInPastException>()),
    );
  });

  test(
      'تغييرُ الموظَّف على حجزٍ مضى وقتُه مسموح — فحصُ الماضي مشروطٌ ببدايةٍ جديدة',
      () async {
    // حجزٌ أُنشئ في المستقبل بالنسبة لـ`now` وقتَ الإنشاء (الإنشاءُ يرفض
    // الماضي، فلا يمكن زرعُه في الماضي مباشرةً).
    final id = await db.createBooking(
      customerName: 'سارة',
      serviceId: serviceId,
      resourceId: resourceA,
      startsAt: DateTime(2026, 8, 20, 10),
      now: now,
    );
    // إعادةُ الإسناد فقط — بلا `startsAt` جديد — و`now` تالٍ يجعل بدايةَ
    // الحجزِ القديمةَ ماضياً. فحصُ الماضي مشروطٌ بوجود `startsAt` جديد،
    // فيجب أن تنجح رغم أنّ بدايةَ الحجز الحاليةَ صارت في الماضي.
    await db.updateBookingSlot(
      id,
      resourceId: resourceB,
      now: DateTime(2026, 8, 20, 12),
    );
    final row =
        await (db.select(db.bookings)..where((b) => b.id.equals(id)))
            .getSingle();
    expect(row.resourceId, resourceB);
  });
}
