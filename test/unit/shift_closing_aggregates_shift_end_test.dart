// ═══════════════════════════════════════════════════════════════════════════
// نافذة احتساب إغلاق الوردية — `shiftEnd`
// ═══════════════════════════════════════════════════════════════════════════
//
// `getShiftClosingAggregates` كانت نافذتها `[shiftStart, now]` بلا نهاية.
// ده صح تماماً وإنت بتقفل وردية شغّالة، لكنه غلط خطير لو استخدمناه في
// **إعادة احتساب وردية مقفولة**: الوردية اللي اتقفلت الصبح هتبلع كل مبيعات
// اليوم اللي بعدها، فالورقة المعاد طباعتها تطلع بأرقام أكبر من الأصل.
//
// الاختبار ده بيثبّت إن `shiftEnd` بيقصّ النافذة فعلاً، وإن غيابه بيحافظ
// على السلوك القديم بالظبط (الافتراضي = دلوقتي) عشان مسار الإغلاق الحيّ
// ما يتغيّرش.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int userId;
  late int warehouseId;

  /// فاتورة نقدي بتاريخ محدد.
  Future<void> insertCashSale({
    required String number,
    required double total,
    required DateTime at,
  }) async {
    await db.into(db.salesInvoices).insert(
          SalesInvoicesCompanion.insert(
            invoiceNumber: number,
            warehouseId: warehouseId,
            userId: userId,
            invoiceDate: at,
            subtotal: Value(total),
            total: Value(total),
            paid: Value(total),
            cashPaid: Value(total),
            paymentMethod: const Value('cash'),
            status: const Value('completed'),
          ),
        );
  }

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();

    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(
            name: 'cashier-shiftend',
            isSystemRole: const Value(false),
          ),
        );
    userId = await db.createUser(
      username: 'cashier_shiftend',
      password: 'pw',
      displayName: 'ShiftEnd',
      roleId: roleId,
    );
    warehouseId = await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(name: 'wh-shiftend'),
        );
  });

  tearDown(() => db.close());

  test('shiftEnd يقص النافذة فما تبلعش مبيعات بعد الإغلاق', () async {
    final start = DateTime.now().subtract(const Duration(hours: 6));
    final end = DateTime.now().subtract(const Duration(hours: 3));

    // جوه الوردية
    await insertCashSale(number: 'IN-1', total: 100, at: start.add(
      const Duration(minutes: 30),
    ));
    // بعد ما الوردية اتقفلت — المفروض ما تدخلش
    await insertCashSale(number: 'OUT-1', total: 999, at: end.add(
      const Duration(minutes: 30),
    ));

    final scoped = await db.getShiftClosingAggregates(
      userId: userId,
      includeAllUsers: false,
      shiftStart: start,
      shiftEnd: end,
    );

    expect(scoped.salesCash, closeTo(100, 0.001),
        reason: 'المبيعة اللي بعد نهاية الوردية لازم تفضل برّه.');
    expect(scoped.salesCount, 1);
  });

  test('من غير shiftEnd السلوك زي ما هو — النافذة لحد دلوقتي', () async {
    final start = DateTime.now().subtract(const Duration(hours: 6));
    final end = DateTime.now().subtract(const Duration(hours: 3));

    await insertCashSale(
        number: 'IN-2', total: 100, at: start.add(const Duration(minutes: 30)));
    await insertCashSale(
        number: 'AFTER-2', total: 999, at: end.add(const Duration(minutes: 30)));

    final open = await db.getShiftClosingAggregates(
      userId: userId,
      includeAllUsers: false,
      shiftStart: start,
      // مفيش shiftEnd — ده مسار الإغلاق الحيّ
    );

    // ده بالظبط السبب اللي عشانه `shiftEnd` لازم يتبعت لما نعيد احتساب
    // وردية مقفولة: من غيره الاتنين بيتحسبوا.
    expect(open.salesCash, closeTo(1099, 0.001));
    expect(open.salesCount, 2);
  });
}
