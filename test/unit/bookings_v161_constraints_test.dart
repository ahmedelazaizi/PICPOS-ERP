// test/unit/bookings_v161_constraints_test.dart
//
// حدودُ v161 — حالةُ الحضور وأعمدةُ المورد وجدولُ التذكير.
//
// ═══ لماذا تُقاس القيودُ لا تُفترَض ═══
//
// «الطفرةُ دخلت والاختبارُ مرَّ لأن الخاصّيّةَ المدَّعاةَ غيرُ موجودة» عطبٌ
// وقع في هذا المستودع. فكلُّ قيدٍ هنا يُقاس **بطرفَيه**: قيمةٌ مشروعةٌ تُكتب
// ولا ترمي، وقيمةٌ مخترَعةٌ **ترمي**. ولو اكتُفي بالطرف الأوّل لمرَّ الاختبارُ
// أخضرَ على جدولٍ بلا قيدٍ أصلاً.
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting();
  });

  tearDown(() async {
    // لا `db.close()` — يعلّق مؤقّتَ drift في المنطقة الوهميّة.
  });

  Matcher throwsCheckViolation() => throwsA(predicate(
        (e) => e.toString().toLowerCase().contains('check constraint failed'),
        'throws a CHECK constraint violation',
      ));

  Future<int> newService() => db.into(db.bookingServices).insert(
        BookingServicesCompanion.insert(name: 'قص شعر'),
      );

  Future<int> newResource({String? kind, int? start, int? end}) =>
      db.into(db.bookingResources).insert(
            BookingResourcesCompanion.insert(
              name: 'محمد علي',
              kind: kind == null ? const Value.absent() : Value(kind),
              shiftStartMinutes:
                  start == null ? const Value.absent() : Value(start),
              shiftEndMinutes: end == null ? const Value.absent() : Value(end),
            ),
          );

  Future<int> newBooking(String status, int serviceId) =>
      db.into(db.bookings).insert(
            BookingsCompanion.insert(
              customerName: 'أحمد محمد',
              serviceId: serviceId,
              startsAt: DateTime(2026, 8, 22, 10),
              endsAt: DateTime(2026, 8, 22, 10, 45),
              status: Value(status),
            ),
          );

  // ═════════════════════════════════════════════════════════════════════
  // ١) حالةُ «تم الحضور» — سببُ الترقية
  // ═════════════════════════════════════════════════════════════════════
  //
  // ⚠️ التصميمُ يرسم «تم الحضور» (`seated`)، والقيدُ الأوّلُ كان **يرميها**.
  // فهذا الاختبارُ هو الذي يُثبت أن الترقيةَ فعلت شيئاً.
  group('حالاتُ الحجز', () {
    test('`seated` تُكتب ولا ترمي — وهي سببُ v161', () async {
      final s = await newService();
      await expectLater(newBooking('seated', s), completes);
    });

    // `completed` **بقيت** ولم تُستبدَل: يحتاجها تحويلُ الحجز إلى فاتورة.
    test('`completed` باقيةٌ مقبولة', () async {
      final s = await newService();
      await expectLater(newBooking('completed', s), completes);
    });

    test('الحالاتُ الخمسُ الأخرى مقبولةٌ كما كانت', () async {
      final s = await newService();
      for (final st in [
        'pending',
        'confirmed',
        'in_service',
        'cancelled',
        'no_show',
      ]) {
        await expectLater(newBooking(st, s), completes, reason: st);
      }
    });

    // ⚠️ **الطرفُ الذي يُثبت أن القيدَ حيّ.** بدونه يمرّ الاختبارُ أخضرَ على
    // جدولٍ نُزع قيدُه — وحالةٌ بخطأٍ إملائيّ (`canceled`) تجعل الحجزَ حيّاً
    // في نظر محرِّك التعارض أو ميتاً على غير وجهٍ، بلا صوت.
    test('حالةٌ مخترَعةٌ ترمي — فالقيدُ يعمل', () async {
      final s = await newService();
      await expectLater(newBooking('canceled', s), throwsCheckViolation());
      await expectLater(newBooking('arrived', s), throwsCheckViolation());
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  // ٢) نوعُ المورد
  // ═════════════════════════════════════════════════════════════════════
  group('نوعُ المورد', () {
    test('`staff` و`device` مقبولان', () async {
      await expectLater(newResource(kind: 'staff'), completes);
      await expectLater(newResource(kind: 'device'), completes);
    });

    test('الافتراضُ `staff` حين لا يُمرَّر', () async {
      final id = await newResource();
      final row = await (db.select(db.bookingResources)
            ..where((r) => r.id.equals(id)))
          .getSingle();
      expect(row.kind, 'staff');
    });

    test('نوعٌ مخترَعٌ يرمي', () async {
      await expectLater(newResource(kind: 'robot'), throwsCheckViolation());
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  // ٣) الورديّة — دقائقُ من منتصف الليل
  // ═════════════════════════════════════════════════════════════════════
  group('ورديّةُ المورد', () {
    test('مدًى عاديٌّ مقبول', () async {
      // ١٠:٠٠ ص → ٠٨:٠٠ م
      await expectLater(newResource(start: 600, end: 1200), completes);
    });

    // 🔴 **الحارسُ الذي يمنع قيداً خاطئاً من أن يُضاف لاحقاً.**
    //
    // ورديّةٌ تعبر منتصفَ الليل (‏٢٠:٠٠ → ٠٢:٠٠) قائمةٌ فعلاً في المطاعم.
    // فقيدُ `end > start` كان سيمنع استعمالاً صحيحاً — ولذلك **لم يُكتَب**،
    // والمدى يُفسَّر دائريّاً في الحساب. وهذا الاختبارُ يثبّت الغياب عمداً.
    test('ورديّةٌ تعبر منتصفَ الليل مقبولة — لا قيدَ `end > start`', () async {
      await expectLater(newResource(start: 1200, end: 120), completes);
    });

    test('الورديّةُ اختياريّةٌ — معدومةٌ مقبولة', () async {
      await expectLater(newResource(), completes);
    });

    test('دقيقةٌ خارجَ اليوم ترمي', () async {
      await expectLater(newResource(start: 1440), throwsCheckViolation());
      await expectLater(newResource(end: -1), throwsCheckViolation());
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  // ٤) التذكيرات — «فُتحت» لا «أُرسلت»
  // ═════════════════════════════════════════════════════════════════════
  group('التذكيرات', () {
    Future<int> newReminder({
      required int bookingId,
      String? state,
      String? channel,
      int? offset,
    }) =>
        db.into(db.bookingReminders).insert(
              BookingRemindersCompanion.insert(
                bookingId: bookingId,
                scheduledAt: DateTime(2026, 8, 22, 9),
                state: state == null ? const Value.absent() : Value(state),
                channel:
                    channel == null ? const Value.absent() : Value(channel),
                offsetMinutes:
                    offset == null ? const Value.absent() : Value(offset),
              ),
            );

    Future<int> bookingId() async => newBooking('pending', await newService());

    test('الحالاتُ الثلاثُ مقبولة', () async {
      final b = await bookingId();
      for (final st in ['scheduled', 'opened', 'dismissed']) {
        await expectLater(newReminder(bookingId: b, state: st), completes,
            reason: st);
      }
    });

    // 🔴 **حارسُ الصدق.** الإرسالُ عبر رابط `wa.me` يفتح واتساب والموظَّفُ
    // يضغط «إرسال» — فالتطبيقُ **لا يعلم** أن الرسالةَ أُرسلت أو وصلت. ولو
    // قُبلت `sent` في القاعدة لَظهرت شارةُ «أُرسلت» فوق فعلٍ لم يُتحقَّق منه.
    //
    // فالقيدُ يمنع الكذبةَ **عند الكتابة** لا بالاتّفاق على تسميةٍ في الواجهة.
    test('`sent` مرفوضةٌ — لا نَدَّعي تسليماً لا نعرفه', () async {
      final b = await bookingId();
      await expectLater(
        newReminder(bookingId: b, state: 'sent'),
        throwsCheckViolation(),
      );
      await expectLater(
        newReminder(bookingId: b, state: 'delivered'),
        throwsCheckViolation(),
      );
    });

    test('القناتان مقبولتان وغيرُهما يرمي', () async {
      final b = await bookingId();
      await expectLater(
          newReminder(bookingId: b, channel: 'whatsapp'), completes);
      await expectLater(newReminder(bookingId: b, channel: 'sms'), completes);
      await expectLater(
        newReminder(bookingId: b, channel: 'telegram'),
        throwsCheckViolation(),
      );
    });

    // تذكيرٌ **بعد** الموعد لا معنى له.
    test('إزاحةٌ سالبةٌ ترمي، وصفرٌ مقبول', () async {
      final b = await bookingId();
      await expectLater(newReminder(bookingId: b, offset: 0), completes);
      await expectLater(
        newReminder(bookingId: b, offset: -30),
        throwsCheckViolation(),
      );
    });
  });
}
