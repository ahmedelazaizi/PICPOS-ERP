// test/unit/bookings_range_scope_test.dart
//
// نطاقُ الفرع في `getBookingsInRange` — عقدٌ ثلاثيُّ الحالات يطبّقه
// المستودعُ كلُّه (`sales_dao.getSalesInvoices` · `purchase_dao`):
//
//   `null`  = وصولٌ كامل
//   `{}`    = **يفشل مغلقاً** — لا صفَّ واحد
//   `{ids}` = تلك الفروعُ **أو** صفوفُ الفرعِ المعدوم
//
// والحالةُ الوسطى هي التي تتسرّب: تركُ `| branchId.isNull()` في الفرع
// الفارغ يجعل «لا وصول» تُعرَض «كلَّ الحجوزات» — وفي تنصيبٍ بفرعٍ واحدٍ
// كلُّ حجزٍ فرعُه معدوم، فالتسريبُ كاملٌ لا جزئيّ.

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int serviceId;
  late int branchA;
  late int branchB;

  final now = DateTime(2026, 8, 20, 9);
  final from = DateTime(2026, 8, 20);
  final to = DateTime(2026, 8, 21);

  setUp(() async {
    db = AppDatabase.forTesting();
    branchA = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'فرع أ',
            globalId: const Value('gid-br-bk-a'),
          ),
        );
    branchB = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'فرع ب',
            globalId: const Value('gid-br-bk-b'),
          ),
        );
    serviceId = await db.into(db.bookingServices).insert(
          BookingServicesCompanion.insert(
            name: 'قص شعر',
            durationMinutes: const Value(60),
          ),
        );

    // بلا موظَّفٍ مُسنَدٍ عمداً: الغرضُ نطاقُ الفرع لا فحصُ التعارض، وحجزٌ
    // بلا موظَّفٍ لا يشارك في الفحص فتتعايش الثلاثةُ في نفس الساعة.
    await db.createBooking(
      customerName: 'زبونُ فرع أ',
      serviceId: serviceId,
      startsAt: DateTime(2026, 8, 20, 10),
      branchId: branchA,
      now: now,
    );
    await db.createBooking(
      customerName: 'زبونُ فرع ب',
      serviceId: serviceId,
      startsAt: DateTime(2026, 8, 20, 11),
      branchId: branchB,
      now: now,
    );
    await db.createBooking(
      customerName: 'زبونٌ بلا فرع',
      serviceId: serviceId,
      startsAt: DateTime(2026, 8, 20, 12),
      branchId: null,
      now: now,
    );
  });

  tearDown(() async {
    // لا `db.close()`: يعلّق مؤقّتَ drift في المنطقة الوهميّة فيتجمّد
    // الاختبار.
  });

  Set<String> namesOf(List<Booking> rows) =>
      rows.map((b) => b.customerName).toSet();

  test('نطاقٌ معدومٌ = وصولٌ كامل — كلُّ الصفوف', () async {
    final rows = await db.getBookingsInRange(from, to);
    expect(namesOf(rows), {'زبونُ فرع أ', 'زبونُ فرع ب', 'زبونٌ بلا فرع'});
  });

  test('نطاقٌ فارغٌ يفشل **مغلقاً** — لا صفَّ واحد', () async {
    final rows = await db.getBookingsInRange(from, to, allowedBranchIds: const []);
    expect(rows, isEmpty,
        reason: 'صلاحيّةٌ بلا فروعٍ يجب ألّا ترى شيئاً — ولا حتى صفوفَ '
            'الفرعِ المعدوم؛ وإلّا صارت «لا وصول» = «كلُّ الحجوزات»');
  });

  test('نطاقٌ بفرعٍ = ذلك الفرعُ **مع** صفوفِ الفرعِ المعدوم', () async {
    final rows = await db.getBookingsInRange(from, to, allowedBranchIds: [branchA]);
    expect(namesOf(rows), {'زبونُ فرع أ', 'زبونٌ بلا فرع'});
  });

  test('نطاقٌ بالفرعين معاً يرى الثلاثة', () async {
    final rows =
        await db.getBookingsInRange(from, to, allowedBranchIds: [branchA, branchB]);
    expect(namesOf(rows), {'زبونُ فرع أ', 'زبونُ فرع ب', 'زبونٌ بلا فرع'});
  });

  test('الترتيبُ ببدايةِ الموعد تصاعديّاً', () async {
    final rows = await db.getBookingsInRange(from, to);
    expect(rows.map((b) => b.startsAt).toList(), [
      DateTime(2026, 8, 20, 10),
      DateTime(2026, 8, 20, 11),
      DateTime(2026, 8, 20, 12),
    ]);
  });

  test('الترشيحُ على `startsAt` وحدَها — العابرُ لمنتصف الليل لا يظهر في الغد',
      () async {
    // دلالةٌ مقصودةٌ تُثبَّت هنا كي لا تُكتشَف مفاجأةً: حجزٌ يبدأ ٢٣:٥٠
    // وينتهي ٠٠:٥٠ **لا** يظهر في مدى اليوم التالي، لأنّ الاستعلامَ يرشّح
    // على البداية لا على التداخل. تقويمٌ يوميٌّ يريد «ما يشغل هذا اليوم»
    // يحتاج دلالةَ تداخلٍ (`startsAt < to && endsAt > from`) — وهي تغييرٌ
    // واعٍ لا تصحيحُ خطأ.
    await db.createBooking(
      customerName: 'عابرُ منتصف الليل',
      serviceId: serviceId,
      startsAt: DateTime(2026, 8, 20, 23, 50),
      now: now,
    );

    final today = await db.getBookingsInRange(from, to);
    expect(namesOf(today), contains('عابرُ منتصف الليل'));

    final tomorrow = await db.getBookingsInRange(
      DateTime(2026, 8, 21),
      DateTime(2026, 8, 22),
    );
    expect(namesOf(tomorrow), isNot(contains('عابرُ منتصف الليل')),
        reason: 'الترشيحُ على البداية لا على التداخل — دلالةٌ مقصودة');
  });
}
