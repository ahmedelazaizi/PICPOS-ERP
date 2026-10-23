// getAgedReceivables / getAgedPayables: invoice_date <= asOf, and the party
// total follows the active branch/region/auth scope instead of the
// company-wide parties.balance.
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int brA;
  late int brB;
  late int whA;
  late int whB;
  late int customerId;
  late int supplierId;
  final asOf = DateTime(2026, 8, 31);

  setUp(() async {
    db = AppDatabase.forTesting();
    brA = await db.into(db.branches).insert(BranchesCompanion.insert(name: 'A'));
    brB = await db.into(db.branches).insert(BranchesCompanion.insert(name: 'B'));
    whA = await db.into(db.warehouses).insert(WarehousesCompanion.insert(
        name: 'WA', branchId: Value(brA)));
    whB = await db.into(db.warehouses).insert(WarehousesCompanion.insert(
        name: 'WB', branchId: Value(brB)));
    // Company-wide balance 1000 = A:400 (old) + B:600 (old, 120 days).
    customerId = await db.into(db.parties).insert(PartiesCompanion.insert(
        name: 'cust', balance: const Value(1000), isCustomer: const Value(true), isSupplier: const Value(false)));
    supplierId = await db.into(db.parties).insert(PartiesCompanion.insert(
        name: 'supp', balance: const Value(1000), isCustomer: const Value(false), isSupplier: const Value(true)));
  });

  tearDown(() => db.close());

  Future<void> sale(String no, int wh, DateTime date, double total) => db
      .into(db.salesInvoices)
      .insert(SalesInvoicesCompanion.insert(
        invoiceNumber: no,
        warehouseId: wh,
        userId: 1,
        customerId: Value(customerId),
        subtotal: Value(total),
        total: Value(total),
        paymentMethod: const Value('credit'),
        invoiceDate: date,
      ));

  Future<void> purchase(String no, int wh, DateTime date, double total) => db
      .into(db.purchaseInvoices)
      .insert(PurchaseInvoicesCompanion.insert(
        invoiceNumber: no,
        supplierId: supplierId,
        warehouseId: wh,
        invoiceDate: date,
        total: Value(total),
      ));

  Future<void> seedBoth() async {
    final old = asOf.subtract(const Duration(days: 120));
    await sale('S-A', whA, old, 400);
    await sale('S-B', whB, old, 600);
    await purchase('P-A', whA, old, 400);
    await purchase('P-B', whB, old, 600);
  }

  // The test DB seeds default parties; look only at this test's two.
  List<Map<String, dynamic>> mine(List<Map<String, dynamic>> rows) => [
        for (final r in rows)
          if (r['name'] == 'cust' || r['name'] == 'supp') r,
      ];

  Map<String, dynamic> only(List<Map<String, dynamic>> rows) {
    expect(mine(rows), hasLength(1));
    return mine(rows).single;
  }

  Future<void> setBalance(double v) => (db.update(db.parties)
        ..where((p) => p.name.isIn(['cust', 'supp'])))
      .write(PartiesCompanion(balance: Value(v)));

  // Party balance = ONLY the in-date invoices (600); the future-dated 400 is
  // not part of it. The old code counted the future invoice (current == 400).
  Future<void> seedFuture() async {
    await setBalance(600);
    await sale('S-OLD', whA, asOf.subtract(const Duration(days: 120)), 600);
    await sale('S-FUT', whA, asOf.add(const Duration(days: 10)), 400);
    await purchase('P-OLD', whA, asOf.subtract(const Duration(days: 120)), 600);
    await purchase('P-FUT', whA, asOf.add(const Duration(days: 10)), 400);
  }

  test('future-dated invoice (after asOf) is excluded from the buckets',
      () async {
    await seedFuture();
    for (final row in [
      only(await db.getAgedReceivables(asOf)),
      only(await db.getAgedPayables(asOf)),
    ]) {
      expect(row['totalBalance'], 600);
      expect(row['over90'], 600);
      expect(row['current'], 0);
    }
  });

  test('future-dated invoice is absent from the branch-scoped total',
      () async {
    await seedFuture();
    for (final row in [
      only(await db.getAgedReceivables(asOf, branchId: brA)),
      only(await db.getAgedPayables(asOf, allowedBranchIds: {brA})),
    ]) {
      expect(row['totalBalance'], 600);
      expect(row['over90'], 600);
      expect(row['current'], 0);
    }
  });

  test('cost-centre filter is scoped: other cost centres are not current',
      () async {
    final cc1 = await db
        .into(db.costCenters)
        .insert(CostCentersCompanion.insert(code: 'CC1', name: 'one'));
    final cc2 = await db
        .into(db.costCenters)
        .insert(CostCentersCompanion.insert(code: 'CC2', name: 'two'));
    final old = asOf.subtract(const Duration(days: 120));
    await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
        invoiceNumber: 'C1', warehouseId: whA, userId: 1,
        customerId: Value(customerId), total: const Value(400),
        paymentMethod: const Value('credit'), invoiceDate: old,
        costCenterId: Value(cc1)));
    await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
        invoiceNumber: 'C2', warehouseId: whA, userId: 1,
        customerId: Value(customerId), total: const Value(600),
        paymentMethod: const Value('credit'), invoiceDate: old,
        costCenterId: Value(cc2)));
    await db.into(db.purchaseInvoices).insert(PurchaseInvoicesCompanion.insert(
        invoiceNumber: 'PC1', supplierId: supplierId, warehouseId: whA,
        invoiceDate: old, total: const Value(400), costCenterId: Value(cc1)));
    await db.into(db.purchaseInvoices).insert(PurchaseInvoicesCompanion.insert(
        invoiceNumber: 'PC2', supplierId: supplierId, warehouseId: whA,
        invoiceDate: old, total: const Value(600), costCenterId: Value(cc2)));
    for (final row in [
      only(await db.getAgedReceivables(asOf, costCenterId: cc1)),
      only(await db.getAgedPayables(asOf, costCenterId: cc1)),
    ]) {
      expect(row['totalBalance'], 400);
      expect(row['over90'], 400);
      expect(row['current'], 0);
    }
  });

  test('soft-deleted purchase invoice is not payable', () async {
    await setBalance(600);
    final old = asOf.subtract(const Duration(days: 120));
    await purchase('P-LIVE', whA, old, 600);
    await db.into(db.purchaseInvoices).insert(PurchaseInvoicesCompanion.insert(
        invoiceNumber: 'P-DEL', supplierId: supplierId, warehouseId: whA,
        invoiceDate: old, total: const Value(400), isDeleted: const Value(true)));
    final ap = only(await db.getAgedPayables(asOf, branchId: brA));
    expect(ap['totalBalance'], 600);
  });

  test('scoped: party with zero company-wide balance but open in-scope invoice stays',
      () async {
    await setBalance(0);
    await sale('S-A', whA, asOf.subtract(const Duration(days: 120)), 400);
    expect(only(await db.getAgedReceivables(asOf, branchId: brA))['totalBalance'], 400);
    expect(mine(await db.getAgedReceivables(asOf)), isEmpty);
  });
  test('branch-filtered view does not push other-branch debt into current',
      () async {
    await seedBoth();
    for (final scoped in [
      () => db.getAgedReceivables(asOf, branchId: brA),
      () => db.getAgedReceivables(asOf, allowedBranchIds: {brA}),
      () => db.getAgedPayables(asOf, branchId: brA),
      () => db.getAgedPayables(asOf, allowedBranchIds: {brA}),
    ]) {
      final row = only(await scoped());
      expect(row['totalBalance'], 400);
      expect(row['over90'], 400);
      expect(row['current'], 0, reason: 'B\'s 600 must not appear as current');
    }
  });

  test('NULL-branch warehouse invoices stay visible in every restricted view',
      () async {
    final whN = await db
        .into(db.warehouses)
        .insert(WarehousesCompanion.insert(name: 'WN'));
    await setBalance(1000);
    final old = asOf.subtract(const Duration(days: 120));
    await sale('S-A', whA, old, 400);
    await sale('S-B', whB, old, 300);
    await sale('S-N', whN, old, 200);
    await purchase('P-A', whA, old, 400);
    await purchase('P-B', whB, old, 300);
    await purchase('P-N', whN, old, 200);
    final regionId = await db
        .into(db.regions)
        .insert(RegionsCompanion.insert(name: 'R'));
    await (db.update(db.branches)..where((b) => b.id.equals(brA)))
        .write(BranchesCompanion(regionId: Value(regionId)));
    for (final scoped in [
      () => db.getAgedReceivables(asOf, branchId: brA),
      () => db.getAgedReceivables(asOf, allowedBranchIds: {brA}),
      () => db.getAgedReceivables(asOf, regionId: regionId),
      () => db.getAgedPayables(asOf, branchId: brA),
      () => db.getAgedPayables(asOf, allowedBranchIds: {brA}),
      () => db.getAgedPayables(asOf, regionId: regionId),
    ]) {
      final row = only(await scoped());
      expect(row['totalBalance'], 600, reason: 'A 400 + NULL-branch 200, no B');
      expect(row['over90'], 600);
      expect(row['current'], 0);
    }
  });

  test('scope with no invoices lists nothing; empty auth scope fails closed',
      () async {
    await sale('S-A', whA, asOf.subtract(const Duration(days: 5)), 400);
    expect(mine(await db.getAgedReceivables(asOf, branchId: brB)), isEmpty);
    expect(mine(await db.getAgedReceivables(asOf, allowedBranchIds: <int>{})),
        isEmpty);
    expect(mine(await db.getAgedPayables(asOf, allowedBranchIds: <int>{})),
        isEmpty);
  });

  test('unrestricted view is unchanged: total = parties.balance', () async {
    await seedBoth();
    final ar = only(await db.getAgedReceivables(asOf));
    expect(ar['totalBalance'], 1000);
    expect(ar['over90'], 1000);
    expect(ar['current'], 0);
    final ap = only(await db.getAgedPayables(asOf));
    expect(ap['totalBalance'], 1000);
    expect(ap['over90'], 1000);
  });

  test('unrestricted: non-invoice remainder still lands in current', () async {
    await sale('S-A', whA, asOf.subtract(const Duration(days: 120)), 400);
    final ar = only(await db.getAgedReceivables(asOf));
    expect(ar['totalBalance'], 1000);
    expect(ar['over90'], 400);
    expect(ar['current'], 600);
  });
}
