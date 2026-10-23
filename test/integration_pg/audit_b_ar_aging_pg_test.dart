// Audit B RPT-003 / RPT-002 on real PostgreSQL: `getArAgingReport` used
// julianday()/scalar MAX() and failed on PG; fully returned purchases were
// aged as payables.
@Tags(['pg'])
library;

import 'package:drift/drift.dart' as d;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

import '_support/pg_fixture.dart';

void main() {
  late PgTestFixture fx;
  late AppDatabase db;
  final asOf = DateTime(2026, 8, 31);
  final old = asOf.subtract(const Duration(days: 120));

  setUpAll(() async {
    fx = await bootPgTestSchema();
    db = fx.db;
    await db.customSelect('SELECT 1').get();
    final wh = await db
        .into(db.warehouses)
        .insert(WarehousesCompanion.insert(name: 'W'));
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
    Future<void> sale(String no, DateTime date, double total) =>
        db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
              invoiceNumber: no,
              warehouseId: wh,
              userId: 1,
              customerId: d.Value(cust),
              total: d.Value(total),
              invoiceDate: date,
            ));
    Future<void> purchase(String no, DateTime date, double total,
            {String status = 'pending'}) =>
        db.into(db.purchaseInvoices).insert(PurchaseInvoicesCompanion.insert(
              invoiceNumber: no,
              supplierId: supp,
              warehouseId: wh,
              invoiceDate: date,
              total: d.Value(total),
              status: d.Value(status),
            ));
    await sale('S-OLD', old, 400);
    await sale('S-NEW', asOf.subtract(const Duration(days: 5)), 100);
    await purchase('P-OLD', old, 300);
    await purchase('P-RET', old, 900, status: 'returned');
  });

  tearDownAll(() async {
    await fx.tearDown();
  });

  test('AR aging runs on PostgreSQL and buckets by age', () async {
    final rows = await db.getArAgingReport(asOfDate: asOf);
    final r = rows.singleWhere((x) => x.partyName == 'aging-cust');
    expect(r.totalBalance, 500);
    expect(r.bucket90Plus, 400);
    expect(r.bucket0_30, 100);
    expect(r.bucket31_60, 0);
  });

  test('AP aging runs on PostgreSQL and skips fully returned purchases',
      () async {
    final rows =
        await db.getArAgingReport(asOfDate: asOf, customersOnly: false);
    final r = rows.singleWhere((x) => x.partyName == 'aging-supp');
    expect(r.bucket90Plus, 300);
    expect(r.bucket0_30 + r.bucket31_60 + r.bucket61_90, 0);
  });
}
