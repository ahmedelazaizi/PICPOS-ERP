// Financial-intelligence SQL on real PostgreSQL: cash-flow statement, aged
// receivables/payables (unscoped, branch, cost-centre) and the analytics
// engine (unscoped + branch-restricted). The numbers mirror the SQLite tests
// (test/unit/cashflow_null_reference_type_test.dart and
// test/data/analytics/*) and are computed by hand below.
@Tags(['pg'])
library;

import 'package:drift/drift.dart' as d;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/providers/financial_analytics_provider.dart';

import '../data/analytics/analytics_harness.dart';
import '_support/pg_fixture.dart';

void main() {
  late PgTestFixture fx;
  late AppDatabase db;
  late Ledger gl;
  late int brA;
  late int brB;
  late int whA;
  late int whB;
  late int cc1;
  late int cc2;
  late int customerId;
  late int supplierId;
  final asOf = DateTime(2026, 8, 31);
  final old = asOf.subtract(const Duration(days: 120));

  setUpAll(() async {
    fx = await bootPgTestSchema();
    db = fx.db;
    await db.customSelect('SELECT 1').get(); // surface migration errors early
    await db.syncDefaultAccounts();
    gl = Ledger(db);

    brA = await gl.addBranch('A');
    brB = await gl.addBranch('B');
    whA = await db.into(db.warehouses).insert(
        WarehousesCompanion.insert(name: 'WA', branchId: d.Value(brA)));
    whB = await db.into(db.warehouses).insert(
        WarehousesCompanion.insert(name: 'WB', branchId: d.Value(brB)));
    cc1 = await gl.addCostCenter('CC1');
    cc2 = await gl.addCostCenter('CC2');

    // ── Ledger (August 2026) ────────────────────────────────────────────
    await gl.post(DateTime(2026, 7, 1), [('1111', 5000, 0), ('311', 0, 5000)]);
    await gl.post(DateTime(2026, 8, 5), [('1111', 1000, 0), ('4121', 0, 1000)],
        branchId: brA, refType: 'sale');
    await gl.post(DateTime(2026, 8, 10), [('623', 300, 0), ('1111', 0, 300)],
        branchId: brA, refType: 'expense');
    // Manual cash entry: reference_type IS NULL (operating, must not vanish).
    // (counter 4121, not equity: a manual entry vs equity is financing — ACC-006)
    await gl.post(DateTime(2026, 8, 12), [('1111', 700, 0), ('4121', 0, 700)],
        refType: null);
    await gl.post(DateTime(2026, 8, 15), [('1121', 800, 0), ('4121', 0, 800)],
        branchId: brB, refType: 'sale');

    // ── Sub-ledger: balance 1000 = A:400 (cc1) + B:600 (cc2), both 120 days
    // old; plus a future-dated 300 invoice that is NOT in the balance.
    customerId = await db.into(db.parties).insert(PartiesCompanion.insert(
        name: 'pg-cust',
        balance: const d.Value(1000),
        isCustomer: const d.Value(true),
        isSupplier: const d.Value(false)));
    supplierId = await db.into(db.parties).insert(PartiesCompanion.insert(
        name: 'pg-supp',
        balance: const d.Value(1000),
        isCustomer: const d.Value(false),
        isSupplier: const d.Value(true)));
    Future<void> sale(String no, int wh, DateTime date, double total, int? cc) =>
        db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
              invoiceNumber: no,
              warehouseId: wh,
              userId: 1,
              customerId: d.Value(customerId),
              subtotal: d.Value(total),
              total: d.Value(total),
              paymentMethod: const d.Value('credit'),
              invoiceDate: date,
              costCenterId: d.Value(cc),
            ));
    Future<void> purchase(String no, int wh, DateTime date, double total,
            int? cc, {bool deleted = false}) =>
        db.into(db.purchaseInvoices).insert(PurchaseInvoicesCompanion.insert(
              invoiceNumber: no,
              supplierId: supplierId,
              warehouseId: wh,
              invoiceDate: date,
              total: d.Value(total),
              costCenterId: d.Value(cc),
              isDeleted: d.Value(deleted),
            ));
    await sale('S-A', whA, old, 400, cc1);
    await sale('S-B', whB, old, 600, cc2);
    await sale('S-FUT', whA, asOf.add(const Duration(days: 10)), 300, cc1);
    await purchase('P-A', whA, old, 400, cc1);
    await purchase('P-B', whB, old, 600, cc2);
    await purchase('P-FUT', whA, asOf.add(const Duration(days: 10)), 300, cc1);
    await purchase('P-DEL', whA, old, 250, cc1, deleted: true);
  });

  tearDownAll(() async {
    await fx.tearDown();
  });

  List<Map<String, dynamic>> mine(List<Map<String, dynamic>> rows) => [
        for (final r in rows)
          if (r['name'] == 'pg-cust' || r['name'] == 'pg-supp') r,
      ];
  Map<String, dynamic> only(List<Map<String, dynamic>> rows) {
    expect(mine(rows), hasLength(1));
    return mine(rows).single;
  }

  void expectRow(Map<String, dynamic> r,
      {required double total, required double over90, double current = 0}) {
    expect((r['totalBalance'] as num).toDouble(), closeTo(total, 1e-6));
    expect((r['over90'] as num).toDouble(), closeTo(over90, 1e-6));
    expect((r['current'] as num).toDouble(), closeTo(current, 1e-6));
  }

  test('cash-flow statement: NULL reference_type counts as operating',
      () async {
    final cf = await db.getCashFlowStatement(
        DateTime(2026, 8, 1), DateTime(2026, 8, 31, 23, 59, 59));
    final op = cf['operating'] as Map<String, dynamic>;
    // opening 5000 (July capital); in 1000 sale + 700 NULL-ref; out 300.
    expect((cf['openingBalance'] as num).toDouble(), closeTo(5000, 1e-6));
    expect((op['totalInflow'] as num).toDouble(), closeTo(1700, 1e-6));
    expect((op['totalOutflow'] as num).toDouble(), closeTo(300, 1e-6));
    expect((cf['closingBalance'] as num).toDouble(), closeTo(6400, 1e-6));
  });

  group('aged receivables / payables', () {
    test('unscoped: total = parties.balance, future + deleted excluded',
        () async {
      expectRow(only(await db.getAgedReceivables(asOf)),
          total: 1000, over90: 1000);
      expectRow(only(await db.getAgedPayables(asOf)),
          total: 1000, over90: 1000);
    });

    test('branch-scoped: only that branch\'s invoices, nothing in current',
        () async {
      expectRow(only(await db.getAgedReceivables(asOf, branchId: brA)),
          total: 400, over90: 400);
      expectRow(only(await db.getAgedPayables(asOf, allowedBranchIds: {brA})),
          total: 400, over90: 400);
      expectRow(only(await db.getAgedReceivables(asOf, branchId: brB)),
          total: 600, over90: 600);
    });

    test('cost-centre-scoped: only that cost centre, nothing in current',
        () async {
      expectRow(only(await db.getAgedReceivables(asOf, costCenterId: cc1)),
          total: 400, over90: 400);
      expectRow(only(await db.getAgedPayables(asOf, costCenterId: cc2)),
          total: 600, over90: 600);
    });

    test('empty auth scope fails closed', () async {
      expect(mine(await db.getAgedReceivables(asOf, allowedBranchIds: <int>{})),
          isEmpty);
    });
  });

  group('computeFinancialAnalytics', () {
    final from = DateTime(2026, 8, 1);
    final to = DateTime(2026, 8, 31, 23, 59, 59, 999);

    test('unscoped', () async {
      final r = await computeFinancialAnalytics(db, (from: from, to: to));
      // revenue 1000 + 700 (manual, counter 4121) + 800; expense 300;
      // cash 5000+1000-300+700.
      expect(r.current.revenue, closeTo(2500, 1e-6));
      expect(r.current.netIncome, closeTo(2200, 1e-6));
      expect(r.current.cash, closeTo(6400, 1e-6));
      expect(r.current.receivables, closeTo(800, 1e-6));
      expect(r.prior.revenue, closeTo(0, 1e-6)); // July has no revenue
      expect(r.budgetAvailable, isTrue);
    });

    test('branch-restricted to A (own + NULL-branch entries)', () async {
      final r = await computeFinancialAnalytics(db, (from: from, to: to),
          allowedBranchIds: {brA});
      // B's 800 sale is invisible; A: revenue 1000 + 700 (NULL-branch manual), expense 300.
      expect(r.current.revenue, closeTo(1700, 1e-6));
      expect(r.current.netIncome, closeTo(1400, 1e-6));
      expect(r.current.cash, closeTo(6400, 1e-6));
      expect(r.budgetAvailable, isFalse);
    });
  });
}
