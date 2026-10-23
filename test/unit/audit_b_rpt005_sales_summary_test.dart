// Audit B RPT-005 — sales summary range is half-open and `paid` is filtered.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/repositories/sales_summary_queries.dart';

void main() {
  late AppDatabase db;
  late int wh;
  late int user;

  setUp(() async {
    db = AppDatabase.forTesting();
    wh = await db.into(db.warehouses).insert(WarehousesCompanion.insert(name: 'W'));
    user = await db.into(db.users).insert(UsersCompanion.insert(
        username: 'user1', passwordHash: 'x', displayName: 'U'));
  });
  tearDown(() => db.close());

  Future<void> inv(String no, DateTime d,
      {double total = 100, double paid = 100, bool deleted = false}) async {
    await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
          invoiceNumber: no,
          warehouseId: wh,
          userId: user,
          invoiceDate: d,
          total: Value(total),
          paid: Value(paid),
          isDeleted: Value(deleted),
        ));
  }

  test('invoice at next midnight is not counted in the previous day', () async {
    await inv('A', DateTime(2026, 5, 10, 12));
    await inv('B', DateTime(2026, 5, 11)); // exactly next midnight
    final s = await querySalesSummary(db,
        fromDate: DateTime(2026, 5, 10), toDate: DateTime(2026, 5, 10));
    expect(s.invoiceCount, 1);
    expect(s.totalSales, 100);
    expect(s.totalPaid, 100);
  });

  test('voided paid invoice is excluded from totalPaid', () async {
    await inv('A', DateTime(2026, 5, 10, 12), total: 100, paid: 40);
    await inv('V', DateTime(2026, 5, 10, 13), total: 100, paid: 100, deleted: true);
    final s = await querySalesSummary(db,
        fromDate: DateTime(2026, 5, 10), toDate: DateTime(2026, 5, 10));
    expect(s.totalSales, 100);
    expect(s.totalPaid, 40);
  });
}
