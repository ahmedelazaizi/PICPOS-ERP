// DAO لمنتقي العميل وحجوزات العميل (P3): البحث بنطاق الفرع، التطبيع، الهاتف
// المكرَّر، الطرف المحذوف، وحجوزاتُ الخدمات والطاولات معاً، وتبعيّةُ الحجوزات
// للطرف الباقي بعد إزالة التكرار، وحفظُ partyId مع اللقطة.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/daos/customer_picker_dao.dart';
import 'package:picpos_erp/data/database/database.dart';

import '../helpers/v195_reservations_db.dart';

void main() {
  late AppDatabase db;
  late int table;
  late int svc;

  setUp(() async {
    db = AppDatabase.forTesting();
    table = await insertTestTable(db, 'T1');
    svc = await insertTestServiceId(db);
  });

  group('searchCustomersForPicker', () {
    test('بالاسم وبالهاتف المطبَّع (0101… = +20 101…)', () async {
      final a = await insertTestParty(db, 'سارة أحمد', phone: '+20 101 234 5678');
      await insertTestParty(db, 'خالد', phone: '01199998888');

      expect((await db.searchCustomersForPicker('سارة')).map((p) => p.id), [a]);
      expect((await db.searchCustomersForPicker('01012345678')).map((p) => p.id), [a]);
      expect((await db.searchCustomersForPicker('0101 234 5678')).map((p) => p.id), [a]);
      expect((await db.searchCustomersForPicker('5678')).map((p) => p.id), [a]);
      expect(await db.searchCustomersForPicker('لا أحد'), isEmpty);
    });

    test('لا يُرجع الموردين ولا غير النشطين ولا العميل النقدي النظامي', () async {
      await insertTestParty(db, 'مورد فقط', customer: false, supplier: true);
      await insertTestParty(db, 'معطّل', active: false);
      final ok = await insertTestParty(db, 'معطّل لكن حيّ');
      final found = await db.searchCustomersForPicker('معطّل');
      expect(found.map((p) => p.id), [ok]);
      final cash = await db.searchCustomersForPicker('نقدي');
      expect(cash.where((p) => p.name.contains('نقدي')), isEmpty,
          reason: 'العميل النقدي النظامي ليس عميلَ حجز');
    });

    test('🔒 نطاق الفرع: المقيَّد بفرعٍ لا يرى عملاء فروعٍ أخرى', () async {
      final global = await insertTestParty(db, 'عام زيد');
      final b1 = await insertTestParty(db, 'فرع١ زيد', branchIds: '1');
      final b2 = await insertTestParty(db, 'فرع٢ زيد', branchIds: '2');
      Future<Set<int>> ids(Set<int>? scope) async => (await db
              .searchCustomersForPicker('زيد', allowedBranchIds: scope))
          .map((p) => p.id)
          .toSet();

      expect(await ids(null), {global, b1, b2}, reason: 'وصول كامل');
      expect(await ids({1}), {global, b1});
      expect(await ids({2}), {global, b2});
      expect(await ids({1, 2}), {global, b1, b2});
      expect(await ids(<int>{}), isEmpty, reason: 'نطاقٌ فارغ = لا شيء');
    });

    test('🔒 findCustomersByPhone يحترم النطاق ولا يكشف رقماً من فرعٍ آخر', () async {
      final other = await insertTestParty(db, 'فرع٢', phone: '01211112222', branchIds: '2');
      expect((await db.findCustomersByPhone('0121 111 2222')).map((p) => p.id), [other]);
      expect(await db.findCustomersByPhone('0121 111 2222', allowedBranchIds: {1}), isEmpty);
    });

    test('هاتفٌ مكرَّر عند عدّة عملاء ⇒ تُرجع كلَّهم', () async {
      final a = await insertTestParty(db, 'أ', phone: '01311112222');
      final b = await insertTestParty(db, 'ب', phone: '+20 131 111 2222');
      await insertTestParty(db, 'ج', phone: '01311113333');
      final dups = await db.findCustomersByPhone('01311112222');
      expect(dups.map((p) => p.id).toSet(), {a, b});
    });
  });

  group('partyReservations', () {
    test('تجمع الخدمات والطاولات (الأحدثُ أولاً) وتعدّها', () async {
      final p = await insertTestParty(db, 'ملف العميل', phone: '01411112222');
      final other = await insertTestParty(db, 'آخر');
      await insertTestReservation(db, table, 'ملف', '01411112222', partyId: p);
      await insertTestBooking(db, svc, 'ملف', '01411112222', partyId: p);
      await insertTestReservation(db, table, 'غيره', null, partyId: other);

      final rows = await db.partyReservations(p);
      expect(rows.length, 2);
      expect(rows.map((r) => r.kind).toSet(), {'table', 'booking'});
      expect(rows.first.at.isAfter(rows.last.at) || rows.first.at == rows.last.at, isTrue);
      expect(rows.firstWhere((r) => r.isTable).place, 'T1');
      expect(await db.partyReservationCount(p), 2);
      expect(await db.partyReservationCount(other), 1);
    });

    test('طرفٌ محذوف: partyByIdAny يرجعه والبحث لا يعرضه', () async {
      final p = await insertTestParty(db, 'سيُحذف', phone: '01511112222');
      await db.customStatement(
          'UPDATE parties SET is_active = 0, deleted_at = 1 WHERE id = ?', [p]);
      expect((await db.partyByIdAny(p))?.deletedAt, isNotNull);
      expect(await db.searchCustomersForPicker('سيُحذف'), isEmpty);
    });
  });

  group('createReservation + الدمج', () {
    test('createReservation يحفظ partyId مع اللقطة', () async {
      final p = await insertTestParty(db, 'عميل مسجّل', phone: '01611112222');
      final id = await db.createReservation(
        tableId: table,
        customerName: 'عميل مسجّل',
        customerPhone: '01611112222',
        partyId: p,
        reservationTime: DateTime(2030, 1, 1, 20),
        partySize: 3,
      );
      final row = await rowOf(db, 'table_reservations', id);
      expect(row['party_id'], p);
      expect(row['customer_name'], 'عميل مسجّل');
      expect(row['customer_phone'], '01611112222');
    });

    test('ضيفٌ: partyId يبقى null', () async {
      final id = await db.createReservation(
        tableId: table,
        customerName: 'ضيف',
        reservationTime: DateTime(2030, 1, 1, 20),
      );
      expect((await rowOf(db, 'table_reservations', id))['party_id'], isNull);
    });

    test('🔴 إزالة التكرار: حجوزات الطرف المدموج تتبع الطرف الباقي', () async {
      final keep = await insertTestParty(db, 'مكرّر');
      final dup = await insertTestParty(db, 'مكرّر');
      final res = await insertTestReservation(db, table, 'مكرّر', null, partyId: dup);
      final bk = await insertTestBooking(db, svc, 'مكرّر', null, partyId: dup);
      // الباقي = الأعلى مراجع؛ نُعطي keep فاتورة وهميّة غير ضروريّة: الأقل id يفوز عند التعادل.
      final result = await db.repairDuplicateParties();
      expect(result.mergedCount, greaterThanOrEqualTo(1));
      expect((await rowOf(db, 'parties', dup))['is_active'], 0);
      expect((await rowOf(db, 'table_reservations', res))['party_id'], keep);
      expect((await rowOf(db, 'bookings', bk))['party_id'], keep);
      // اللقطة لم تُمَس.
      expect((await rowOf(db, 'table_reservations', res))['customer_name'], 'مكرّر');
    });

    test('repointReservationParties مباشرةً + عدم الفعل لنفس المعرّف', () async {
      final a = await insertTestParty(db, 'أ');
      final b = await insertTestParty(db, 'ب');
      final res = await insertTestReservation(db, table, 'أ', null, partyId: a);
      expect(await db.repointReservationParties(a, a), 0);
      expect(await db.repointReservationParties(a, b), 1);
      expect((await rowOf(db, 'table_reservations', res))['party_id'], b);
    });
  });
}
