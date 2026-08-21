// test/unit/bookings_status_test.dart
//
// `status` حقلٌ **ذو أثرٍ على التعارض** كالثلاثيّة
// `(resourceId, startsAt, endsAt)` تماماً — واستعلامُ التداخل يستثني
// `cancelled` و`no_show`، فالانتقالُ إليهما أو **منهما** يبدّل شَغلَ الوقت.
//
// التسريبُ الذي تحرسه هذه الملفّة: حجزُ «أ» على الموظَّف R في ١٠:٠٠ يُلغى،
// فيُنشأ حجزُ «ب» على R في ١٠:٠٠ بحقّ. ثم يتراجع أحدُهم عن الإلغاء — أو
// يقلب `no_show` إلى `confirmed` وهو ما تنصّ عليه §٦ صراحةً — فيحمل R
// حجزين حيَّين متداخلين ولم يجرِ فحصٌ قطّ.

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int serviceId;
  late int resourceId;

  final now = DateTime(2026, 8, 20, 9);

  setUp(() async {
    db = AppDatabase.forTesting();
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
    // الاختبار.
  });

  Future<Booking> row(int id) =>
      (db.select(db.bookings)..where((b) => b.id.equals(id))).getSingle();

  test('الإحياءُ إلى وقتٍ شُغل بعد الإلغاء يُرفَض', () async {
    final first = await db.createBooking(
      customerName: 'أحمد',
      serviceId: serviceId,
      resourceId: resourceId,
      startsAt: DateTime(2026, 8, 20, 10),
      now: now,
    );
    await db.setBookingStatus(first, 'cancelled', now: now);

    // الوقتُ فُرّغ فعلاً — فحجزُ سارة يُقبل بحقّ.
    final second = await db.createBooking(
      customerName: 'سارة',
      serviceId: serviceId,
      resourceId: resourceId,
      startsAt: DateTime(2026, 8, 20, 10),
      now: now,
    );
    expect(second, greaterThan(0));

    // ثم يتراجع أحدُهم عن الإلغاء — وهنا كان يمرّ حجزان حيّان على موظَّفٍ
    // واحدٍ بلا فحصٍ قطّ.
    expect(
      () => db.setBookingStatus(first, 'confirmed', now: now),
      throwsA(isA<BookingConflictException>()),
    );

    // ولم تتبدّل الحالةُ رغم المحاولة — المعاملةُ تُرجَع كاملةً.
    expect((await row(first)).status, 'cancelled');
  });

  test('قلبُ `no_show` إلى حالةٍ حيّةٍ يُفحَص كالإلغاء تماماً', () async {
    final first = await db.createBooking(
      customerName: 'أحمد',
      serviceId: serviceId,
      resourceId: resourceId,
      startsAt: DateTime(2026, 8, 20, 10),
      now: now,
    );
    await db.setBookingStatus(first, 'no_show', now: now);
    await db.createBooking(
      customerName: 'سارة',
      serviceId: serviceId,
      resourceId: resourceId,
      startsAt: DateTime(2026, 8, 20, 10),
      now: now,
    );
    expect(
      () => db.setBookingStatus(first, 'confirmed', now: now),
      throwsA(isA<BookingConflictException>()),
    );
  });

  test('الإحياءُ إلى وقتٍ ما يزال فارغاً ينجح', () async {
    final id = await db.createBooking(
      customerName: 'أحمد',
      serviceId: serviceId,
      resourceId: resourceId,
      startsAt: DateTime(2026, 8, 20, 10),
      now: now,
    );
    await db.setBookingStatus(id, 'cancelled', now: now);
    await db.setBookingStatus(id, 'confirmed', now: DateTime(2026, 8, 20, 9, 5));

    final revived = await row(id);
    expect(revived.status, 'confirmed');
    expect(revived.updatedAt, DateTime(2026, 8, 20, 9, 5));
  });

  test('الإلغاءُ لا يرمي أبداً — الاتّجاهُ المُفرِّغُ لا يحتاج فحصاً', () async {
    final first = await db.createBooking(
      customerName: 'أحمد',
      serviceId: serviceId,
      resourceId: resourceId,
      startsAt: DateTime(2026, 8, 20, 10),
      now: now,
    );
    await db.setBookingStatus(first, 'cancelled', now: now);
    final second = await db.createBooking(
      customerName: 'سارة',
      serviceId: serviceId,
      resourceId: resourceId,
      startsAt: DateTime(2026, 8, 20, 10),
      now: now,
    );

    // إلغاءُ الثاني بينما الأوّلُ ملغًى في نفس الوقت — لا فحصَ ولا رمي.
    await db.setBookingStatus(second, 'no_show', now: now);
    expect((await row(second)).status, 'no_show');

    // وإلغاءُ الملغى مرّةً أخرى كذلك.
    await db.setBookingStatus(first, 'cancelled', now: now);
    expect((await row(first)).status, 'cancelled');
  });

  test('الانتقالُ بين حالتين حيَّتين لا يرمي', () async {
    final id = await db.createBooking(
      customerName: 'أحمد',
      serviceId: serviceId,
      resourceId: resourceId,
      startsAt: DateTime(2026, 8, 20, 10),
      now: now,
    );
    await db.setBookingStatus(id, 'confirmed', now: now);
    await db.setBookingStatus(id, 'in_service', now: now);
    await db.setBookingStatus(id, 'completed', now: now);
    expect((await row(id)).status, 'completed');
  });

  test('حجزٌ بلا موظَّفٍ يُحيا بلا فحصٍ — لا أحدَ يتعارض عليه', () async {
    final id = await db.createBooking(
      customerName: 'أحمد',
      serviceId: serviceId,
      resourceId: null,
      startsAt: DateTime(2026, 8, 20, 10),
      now: now,
    );
    await db.setBookingStatus(id, 'cancelled', now: now);
    await db.createBooking(
      customerName: 'سارة',
      serviceId: serviceId,
      resourceId: null,
      startsAt: DateTime(2026, 8, 20, 10),
      now: now,
    );
    await db.setBookingStatus(id, 'pending', now: now);
    expect((await row(id)).status, 'pending');
  });
}
