// test/unit/bookings_check_constraints_test.dart
//
// حدودُ الجدول التي يقوم عليها **محرِّكُ التعارض** — لا نظافةُ بياناتٍ فحسب.
//
// عطلان صامتان كلاهما غيرُ آمن:
//
// ١) `durationMinutes <= 0` يُنتج `endsAt <= startsAt`، وعندها ترجع
//    `bookingSlotsOverlap` كاذبةً في وجه كلِّ شيء — فالحجزُ قائمٌ ويشغل
//    موظَّفاً و**لا يراه المحرِّكُ أبداً**.
//
// ٢) `duration + buffer > 1440` يُخرج الصفوفَ من نافذةِ ترشيح المرشَّحين
//    (`startsAt - يوم`)، فلا تصل إلى الدالّة الخالصة ويمرّ التعارضُ صامتاً.
//
// والقيدُ في الجدول نفسِه لا في الـDAO عمداً — على سُنّة
// `table_tax_check_constraint_test.dart`: يسري على `INSERT` و`UPDATE` وعلى
// كلِّ مسارِ كتابةٍ قادمٍ لم يُكتَب بعد.

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting();
  });

  tearDown(() async {
    // لا `db.close()`: يعلّق مؤقّتَ drift في المنطقة الوهميّة فيتجمّد
    // الاختبار.
  });

  Matcher throwsCheckViolation() => throwsA(predicate(
        (e) => e.toString().toLowerCase().contains('check constraint failed'),
        'throws a CHECK constraint violation',
      ));

  Future<int> insertService({
    required String name,
    int? duration,
    int? buffer,
  }) =>
      db.into(db.bookingServices).insert(
            BookingServicesCompanion.insert(
              name: name,
              durationMinutes:
                  duration == null ? const Value.absent() : Value(duration),
              bufferMinutes:
                  buffer == null ? const Value.absent() : Value(buffer),
            ),
          );

  // ═══════════════════════════════════════════════════════════════════════
  group('مدّةُ الخدمة — الحدُّ السفليّ', () {
    test('مدّةُ صفرٍ تُرفض في الجدول', () async {
      await expectLater(
        insertService(name: 'خدمةٌ بلا مدّة', duration: 0),
        throwsCheckViolation(),
      );
    });

    test('مدّةٌ سالبةٌ تُرفض كذلك — لا ثغرةَ تحت الصفر', () async {
      await expectLater(
        insertService(name: 'خدمةٌ سالبة', duration: -30),
        throwsCheckViolation(),
      );
    });

    test('فترةُ تنظيفٍ سالبةٌ تُرفض', () async {
      await expectLater(
        insertService(name: 'تنظيفٌ سالب', duration: 30, buffer: -10),
        throwsCheckViolation(),
      );
    });

    test('دقيقةٌ واحدةٌ تُقبل — الحدُّ يمنع الصفرَ لا الخدمةَ القصيرة',
        () async {
      final id = await insertService(name: 'خدمةٌ خاطفة', duration: 1);
      expect(id, greaterThan(0));
    });

    test('التعديلُ إلى صفرٍ يُرفض أيضاً — القيدُ يسري على `UPDATE`', () async {
      final id = await insertService(name: 'قص شعر', duration: 45, buffer: 15);
      await expectLater(
        (db.update(db.bookingServices)..where((s) => s.id.equals(id)))
            .write(const BookingServicesCompanion(durationMinutes: Value(0))),
        throwsCheckViolation(),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  group('سقفُ اليوم — ١٤٤٠ دقيقة هي عرضُ نافذةِ الترشيح', () {
    test('مجموعٌ يتجاوز اليومَ يُرفض', () async {
      await expectLater(
        insertService(name: 'خدمةٌ تتجاوز اليوم', duration: 1441),
        throwsCheckViolation(),
      );
    });

    test('التجاوزُ عبر فترةِ التنظيف يُرفض كذلك — المجموعُ هو المقيس',
        () async {
      await expectLater(
        insertService(name: 'مجموعٌ متجاوز', duration: 1400, buffer: 41),
        throwsCheckViolation(),
      );
    });

    test('اليومُ كاملاً بالضبط يُقبل — لا يُرفض بفارقِ دقيقة', () async {
      final id =
          await insertService(name: 'يومٌ كامل', duration: 1400, buffer: 40);
      expect(id, greaterThan(0));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  group('قيمُ الحالة والعربون مُنفَذةٌ لا موصوفةٌ فحسب', () {
    late int serviceId;
    setUp(() async {
      serviceId = await insertService(name: 'قص شعر', duration: 45, buffer: 15);
    });

    Future<int> insertBooking({String? status, String? deposit}) =>
        db.into(db.bookings).insert(
              BookingsCompanion.insert(
                customerName: 'أحمد',
                serviceId: serviceId,
                startsAt: DateTime(2026, 8, 20, 10),
                endsAt: DateTime(2026, 8, 20, 11),
                status: status == null ? const Value.absent() : Value(status),
                depositStatus:
                    deposit == null ? const Value.absent() : Value(deposit),
              ),
            );

    test('حالةٌ خارج المجموعة تُرفض', () async {
      // `canceled` بلامٍ واحدة: خطأٌ إملائيٌّ يجعل الحجزَ **حيّاً** في نظر
      // استعلام التعارض (لأنه ليس `cancelled`) فيحجب وقتاً ظنّ صاحبُه أنه
      // أفرغه — بلا صوت.
      await expectLater(
        insertBooking(status: 'canceled'),
        throwsCheckViolation(),
      );
    });

    test('كلُّ حالةٍ موثَّقةٍ مقبولة', () async {
      for (final status in const [
        'pending',
        'confirmed',
        'in_service',
        'completed',
        'cancelled',
        'no_show',
      ]) {
        final id = await insertBooking(status: status);
        expect(id, greaterThan(0), reason: 'الحالةُ $status يجب أن تُقبل');
      }
    });

    test('حالةُ عربونٍ خارج المجموعة تُرفض', () async {
      await expectLater(
        insertBooking(deposit: 'transferred'),
        throwsCheckViolation(),
      );
    });

    test('حالاتُ العربون الثلاثُ مقبولة — ثلاثٌ لا أربع', () async {
      for (final deposit in const ['held', 'refunded', 'forfeited']) {
        final id = await insertBooking(deposit: deposit);
        expect(id, greaterThan(0), reason: 'حالةُ العربون $deposit تُقبل');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  test('فهرسُ المسار الساخن `(resource_id, starts_at)` قائمٌ على قاعدةٍ جديدة',
      () async {
    // فهرسٌ خامٌّ لا كيانُ drift، فـ`createAll()` ما بتصدّروش — لازم
    // `onCreate` يركّبه صراحةً وإلّا بقيت القاعدةُ الجديدةُ بلا فهرسٍ بينما
    // المُرقّاةُ تأخذه من الهجرة.
    final rows = await db
        .customSelect(
          "SELECT sql FROM sqlite_master WHERE type = 'index' AND name = ?",
          variables: [Variable.withString(kBookingResourceSlotIndexName)],
        )
        .get();
    expect(rows, hasLength(1),
        reason: 'الفهرسُ $kBookingResourceSlotIndexName غائبٌ عن قاعدةٍ '
            'أُنشئت من `createAll` — راجع مسارَ `onCreate`');
    expect(rows.single.read<String>('sql').toLowerCase(),
        contains('resource_id'));
  });

  // ═══════════════════════════════════════════════════════════════════════
  test('القيدان ظاهران في نصِّ الجدولين — لا في الـDAO', () async {
    Future<String> tableSql(String name) async {
      final rows = await db
          .customSelect('SELECT sql FROM sqlite_master WHERE name = ?',
              variables: [Variable.withString(name)])
          .get();
      return rows.single.read<String>('sql').toLowerCase();
    }

    final servicesSql = await tableSql('booking_services');
    expect(servicesSql, contains('duration_minutes > 0'));
    expect(servicesSql, contains('1440'));

    final bookingsSql = await tableSql('bookings');
    expect(bookingsSql, contains('no_show'));
    expect(bookingsSql, contains('forfeited'));
  });
}
