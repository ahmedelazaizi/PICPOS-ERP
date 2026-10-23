// Audit B RPT-002 (b/c) on SQLite — same fixture as the PG test.
import 'package:drift/drift.dart' as d;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  final asOf = DateTime(2026, 8, 31);
  final old = asOf.subtract(const Duration(days: 120));

  setUp(() async {
    db = AppDatabase.forTesting();
    final wh = await db.into(db.warehouses).insert(WarehousesCompanion.insert(name: 'W'));
    final user = await db.into(db.users).insert(UsersCompanion.insert(
        username: 'user1', passwordHash: 'x', displayName: 'U'));
    final cust = await db.into(db.parties).insert(PartiesCompanion.insert(
        name: 'aging-cust',
        balance: const d.Value(500),
        isCustomer: const d.Value(true),
        isSupplier: const d.Value(false)));
    final supp = await db.into(db.parties).insert(PartiesCompanion.insert(
        name: 'aging-supp',
        balance: const d.Value(300),
        isCustomer: const d.Value(false),
        isSupplier: const d.Value(true)));
    Future<void> sale(String no, DateTime date, double total, {String status = 'pending'}) =>
        db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
              invoiceNumber: no, warehouseId: wh, userId: user,
              customerId: d.Value(cust), total: d.Value(total),
              invoiceDate: date, status: d.Value(status)));
    Future<void> purchase(String no, DateTime date, double total, {String status = 'pending'}) =>
        db.into(db.purchaseInvoices).insert(PurchaseInvoicesCompanion.insert(
              invoiceNumber: no, supplierId: supp, warehouseId: wh,
              invoiceDate: date, total: d.Value(total), status: d.Value(status)));
    await sale('S-OLD', old, 400);
    await sale('S-NEW', asOf.subtract(const Duration(days: 5)), 100);
    await sale('S-VOID', old, 700, status: 'voided');
    await purchase('P-OLD', old, 300);
    await purchase('P-RET', old, 900, status: 'returned');
    await purchase('P-CAN', old, 900, status: 'cancelled');
  });
  tearDown(() => db.close());

  test('AR buckets ignore voided invoices', () async {
    final r = (await db.getArAgingReport(asOfDate: asOf)).single;
    expect(r.bucket90Plus, 400);
    expect(r.bucket0_30, 100);
  });

  test('AP buckets ignore returned/cancelled purchases', () async {
    final r = (await db.getArAgingReport(asOfDate: asOf, customersOnly: false)).single;
    expect(r.bucket90Plus, 300);
    expect(r.bucket0_30 + r.bucket31_60 + r.bucket61_90, 0);
  });
}
