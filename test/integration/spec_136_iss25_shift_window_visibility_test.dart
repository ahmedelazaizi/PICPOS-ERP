import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:ural_erp/data/database/database.dart';

/// Spec 136 ISS-25 — shift-window visibility across the midnight boundary.
///
/// Field bug: the POS "previous invoices/expenses" views were scoped to the
/// CALENDAR DAY (local midnight). A shift that crosses midnight lost every
/// invoice/expense created before 00:00 — and a shift opened the previous
/// evening showed nothing. The fix adds `watchSalesSince(from)` so callers can
/// pass the open shift's `startTime` instead of midnight.
void main() {
  late AppDatabase db;
  late int userId;
  late int warehouseId;

  setUp(() async {
    db = AppDatabase.forTesting();
    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(
            name: 'كاشير ISS25',
            isSystemRole: const Value(false),
          ),
        );
    userId = await db.createUser(
      username: 'iss25_cashier',
      password: 'pw',
      displayName: 'ISS25',
      roleId: roleId,
    );
    final wh = await db.getDefaultWarehouse();
    warehouseId = wh!.id;
  });

  tearDown(() async => db.close());

  Future<int> insertSale(
    String number,
    DateTime date, {
    int? forUser,
    String? saleType,
  }) {
    return db.into(db.salesInvoices).insert(
          SalesInvoicesCompanion.insert(
            invoiceNumber: number,
            warehouseId: warehouseId,
            userId: forUser ?? userId,
            invoiceDate: date,
            total: const Value(10),
            saleType: saleType == null ? const Value.absent() : Value(saleType),
          ),
        );
  }

  test(
      'shift crossing midnight: watchSalesSince(shiftStart) keeps pre-midnight '
      'sales that the calendar-day stream drops', () async {
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final shiftStart = todayMidnight.subtract(const Duration(hours: 2)); // ~22:00 prev day
    final preMidnight =
        todayMidnight.subtract(const Duration(minutes: 30)); // ~23:30 prev day
    final postMidnight =
        todayMidnight.add(const Duration(minutes: 30)); // ~00:30 today

    await insertSale('PRE', preMidnight);
    await insertSale('POST', postMidnight);

    // BUG repro: the calendar-day stream only sees the post-midnight invoice.
    final todayOnly = await db.watchTodaySalesForUser(userId).first;
    expect(todayOnly.map((i) => i.invoiceNumber).toList(), ['POST'],
        reason: 'calendar-day filter drops the pre-midnight invoice (the bug)');

    // FIX: the shift-window stream sees BOTH pre- and post-midnight invoices.
    final shiftWindow =
        await db.watchSalesSince(shiftStart, userId: userId).first;
    expect(shiftWindow.map((i) => i.invoiceNumber).toSet(), {'PRE', 'POST'},
        reason: 'shift window must keep the whole open shift across midnight');
  });

  test('watchSalesSince scoping: excludes returns and (when userId set) other users',
      () async {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(hours: 3));

    await insertSale('S1', now);
    await insertSale('RET1', now, saleType: 'return');

    final otherRole = await db.into(db.roles).insert(
          RolesCompanion.insert(
            name: 'other25',
            isSystemRole: const Value(false),
          ),
        );
    final otherUser = await db.createUser(
      username: 'other25',
      // مغايرةٌ عن `iss25_cashier` — `createUser` يرفض التكرار (§١).
      password: 'pw-other',
      displayName: 'o',
      roleId: otherRole,
    );
    await insertSale('S2', now, forUser: otherUser);

    // userId set → only this user's non-return sales.
    final mine = await db.watchSalesSince(from, userId: userId).first;
    expect(mine.map((i) => i.invoiceNumber).toSet(), {'S1'},
        reason: 'returns excluded + other-user sales excluded when userId set');

    // no userId → all users, returns still excluded.
    final all = await db.watchSalesSince(from).first;
    expect(all.map((i) => i.invoiceNumber).toSet(), {'S1', 'S2'},
        reason: 'no userId → all users in window, returns still excluded');
  });
}
