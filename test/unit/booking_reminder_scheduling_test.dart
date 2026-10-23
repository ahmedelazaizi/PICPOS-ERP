// test/unit/booking_reminder_scheduling_test.dart
//
// حارسُ مولِّد تذكيرات الحجوزات.
//
// ⚠️ جدولُ `BookingReminders` شُحن بقيوده، والوجهةُ تعرض، والحساباتُ الخالصةُ
// جاهزة — و**لا موضعَ واحدٌ كان يُنشئ صفَّ تذكير**. فالوجهةُ كانت فارغةً
// أبداً مهما حُجز. هذا الحارسُ يقيس أنّ الصفَّ يُولد فعلاً، وبالمهلة
// المحفوظة لا بثابتٍ مدفون.
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/domain/models/picpos_booking_view.dart';

void main() {
  late AppDatabase db;
  late int serviceId;
  late int resourceId;
  // ⚠️ `openedBy` مفتاحٌ أجنبيٌّ على `Users` — رقمٌ مخترَعٌ يُسقط التحديثَ
  // بـFOREIGN KEY constraint failed لا بفشلٍ في المنطق.
  late int userId;
  final now = DateTime(2026, 8, 20, 9);

  setUp(() async {
    db = AppDatabase.forTesting();
    userId = (await db.select(db.users).get()).first.id;
    serviceId = await db.into(db.bookingServices).insert(
          BookingServicesCompanion.insert(
            name: 'مساج',
            durationMinutes: const Value(60),
          ),
        );
    resourceId = await db.into(db.bookingResources).insert(
          BookingResourcesCompanion.insert(name: 'محمد'),
        );
  });

  Future<List<BookingReminder>> reminders() =>
      db.select(db.bookingReminders).get();

  test('إنشاءُ حجزٍ بهاتفٍ يُولّد صفَّ تذكيرٍ واحداً — لا صفراً ولا اثنين',
      () async {
    await db.createBooking(
      customerName: 'أحمد',
      customerPhone: '0791234567',
      serviceId: serviceId,
      resourceId: resourceId,
      startsAt: DateTime(2026, 8, 20, 14),
      now: now,
    );

    final rows = await reminders();
    expect(rows, hasLength(1));
  });

  test('المهلةُ تُقرأ من الإعداد المحفوظ لا من ثابتٍ مدفون', () async {
    // الافتراضُ ٦٠. لو كان الكودُ يُثبّت ٦٠ لَمرّ الاختبارُ بـ٦٠ وسقط بـ٣٠.
    await db.setSetting(bookingReminderOffsetKey, '30');

    final startsAt = DateTime(2026, 8, 20, 14);
    await db.createBooking(
      customerName: 'أحمد',
      customerPhone: '0791234567',
      serviceId: serviceId,
      startsAt: startsAt,
      now: now,
    );

    final row = (await reminders()).single;
    expect(row.offsetMinutes, 30);
    expect(row.scheduledAt, DateTime(2026, 8, 20, 13, 30));
  });

  test('الحالةُ والقناةُ يقبلهما القيدُ — `scheduled` و`whatsapp`', () async {
    await db.createBooking(
      customerName: 'أحمد',
      customerPhone: '0791234567',
      serviceId: serviceId,
      startsAt: DateTime(2026, 8, 20, 14),
      now: now,
    );

    final row = (await reminders()).single;
    // ⚠️ لا `sent`: رابطُ `wa.me` لا يُثبت تسليماً، والقيدُ يرفضها أصلاً.
    expect(row.state, 'scheduled');
    expect(row.channel, 'whatsapp');
    expect(row.openedAt, isNull);
  });

  test('حجزٌ بلا هاتفٍ لا يُولّد تذكيراً — والحجزُ نفسُه يبقى قائماً',
      () async {
    // قرارُ المالك 2026-08-23: صفٌّ لا يملك رابطاً ممكناً زينةٌ في القائمة.
    // وهو في الوقت نفسِه يقيس أنّ غيابَ التذكير **لا يُسقط الحجز** — بخلاف
    // العربون الذي يُسقطه عمداً (مالٌ مقبوضٌ بلا أثرٍ أسوأُ من رفض الحجز).
    final bookingId = await db.createBooking(
      customerName: 'أحمد بلا هاتف',
      serviceId: serviceId,
      startsAt: DateTime(2026, 8, 20, 14),
      now: now,
    );

    expect(await reminders(), isEmpty);
    final booking = await (db.select(db.bookings)
          ..where((b) => b.id.equals(bookingId)))
        .getSingleOrNull();
    expect(booking, isNotNull);
  });

  test('حجزٌ أقربُ من المهلة يُنشئ تذكيراً مستحقّاً فوراً لا يُتخطّى',
      () async {
    // قرارُ المالك 2026-08-23: الموعدُ بعد ١٠ دقائقَ والمهلةُ ٦٠ ⇒ لحظةُ
    // الاستحقاق مضت. العميلُ ما زال يستحقّ تذكيراً، فيُنشَأ مستحقّاً.
    final startsAt = now.add(const Duration(minutes: 10));
    await db.createBooking(
      customerName: 'أحمد',
      customerPhone: '0791234567',
      serviceId: serviceId,
      startsAt: startsAt,
      now: now,
    );

    final row = (await reminders()).single;
    expect(row.scheduledAt, startsAt.subtract(const Duration(minutes: 60)));
    expect(row.scheduledAt.isBefore(now), isTrue);
  });

  test('نقلُ الحجز يُعيد جدولةَ التذكير بنفس المهلة ولا يترك صفّاً يتيماً',
      () async {
    await db.setSetting(bookingReminderOffsetKey, '30');
    final bookingId = await db.createBooking(
      customerName: 'أحمد',
      customerPhone: '0791234567',
      serviceId: serviceId,
      resourceId: resourceId,
      startsAt: DateTime(2026, 8, 20, 14),
      now: now,
    );
    // الإعدادُ يتبدّل بعد الحجز — والنقلُ يجب أن يستعمل المهلةَ **المخزَّنةَ
    // في الصفّ** (٣٠) لا الإعدادَ الجديد، وإلّا غيّر تبديلُ الإعداد تذكيراتٍ
    // قديمةً بأثرٍ رجعيّ.
    await db.setSetting(bookingReminderOffsetKey, '120');

    await db.updateBookingSlot(
      bookingId,
      startsAt: DateTime(2026, 8, 20, 17),
      now: now,
    );

    final rows = await reminders();
    expect(rows, hasLength(1));
    expect(rows.single.offsetMinutes, 30);
    expect(rows.single.scheduledAt, DateTime(2026, 8, 20, 16, 30));
  });

  test('فتحُ رابط التذكير يختمه `opened` بمن فتحه ومتى', () async {
    // ⚠️ بلا هذا يبقى كلُّ تذكيرٍ `scheduled` أبداً، فـ`isReminderDue` تعرضه
    // مستحقّاً إلى الأبد وتتراكم القائمةُ بما عُولج فعلاً — والمضيفُ لا يميّز
    // ما أرسله ممّا لم يُرسله.
    await db.createBooking(
      customerName: 'أحمد',
      customerPhone: '0791234567',
      serviceId: serviceId,
      startsAt: DateTime(2026, 8, 20, 14),
      now: now,
    );
    final reminderId = (await reminders()).single.id;
    final openedAt = DateTime(2026, 8, 20, 13, 5);

    await db.markBookingReminderOpened(reminderId, userId: userId, now: openedAt);

    final row = (await reminders()).single;
    // ⚠️ `opened` لا `sent`: الرابطُ فُتح — والتسليمُ لا يملك التطبيقُ إثباتَه.
    expect(row.state, 'opened');
    expect(row.openedAt, openedAt);
    expect(row.openedBy, userId);
  });

  test('التذكيرُ المفتوحُ لا يعود مستحقّاً ولا تُحرّكه إعادةُ الجدولة',
      () async {
    final bookingId = await db.createBooking(
      customerName: 'أحمد',
      customerPhone: '0791234567',
      serviceId: serviceId,
      startsAt: DateTime(2026, 8, 20, 14),
      now: now,
    );
    final scheduledBefore = (await reminders()).single.scheduledAt;
    await db.markBookingReminderOpened((await reminders()).single.id,
        userId: userId, now: DateTime(2026, 8, 20, 13, 5));

    await db.updateBookingSlot(
      bookingId,
      startsAt: DateTime(2026, 8, 20, 18),
      now: now,
    );

    final row = (await reminders()).single;
    // تحريكُ موعدِ تذكيرٍ فُتح فعلاً يكذب على سجلٍّ تمّ.
    expect(row.state, 'opened');
    expect(row.scheduledAt, scheduledBefore);
    expect(
      isReminderDue(
        state: row.state,
        scheduledAt: row.scheduledAt,
        now: DateTime(2026, 8, 20, 17),
      ),
      isFalse,
    );
  });

  test('إعدادٌ فاسدٌ أو سالبٌ يسقط على الافتراض ٦٠ ولا يكسر القيد', () async {
    // `offset_minutes >= 0` قيدٌ في الجدول: قيمةٌ سالبةٌ تُدرَج تُسقط الإدراج.
    await db.setSetting(bookingReminderOffsetKey, '-15');

    await db.createBooking(
      customerName: 'أحمد',
      customerPhone: '0791234567',
      serviceId: serviceId,
      startsAt: DateTime(2026, 8, 20, 14),
      now: now,
    );

    final row = (await reminders()).single;
    expect(row.offsetMinutes, 60);
    expect(row.scheduledAt, DateTime(2026, 8, 20, 13));
  });
}
