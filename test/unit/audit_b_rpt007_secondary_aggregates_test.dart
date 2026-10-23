// Audit B RPT-007 — secondary aggregates: cancelled purchases carry no money,
// variance report honours its warehouseId, GL budget actuals (see rpt004 test).
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.into(db.warehouses).insert(WarehousesCompanion.insert(name: 'W1'));
    await db.into(db.warehouses).insert(WarehousesCompanion.insert(name: 'W2'));
    await db.into(db.parties).insert(PartiesCompanion.insert(name: 'Sup'));
  });
  tearDown(() => db.close());

  test('cancelled purchase is counted but carries no total/paid', () async {
    Future<void> p(String no, double total, double paid, String status) =>
        db.into(db.purchaseInvoices).insert(PurchaseInvoicesCompanion.insert(
              invoiceNumber: no,
              supplierId: 1,
              warehouseId: 1,
              invoiceDate: DateTime(2026, 8, 10),
              total: Value(total),
              paid: Value(paid),
              status: Value(status),
            ));
    await p('A', 100, 100, 'paid');
    await p('B', 500, 0, 'cancelled');
    final s = await db.getPurchaseInvoiceSummary(
        from: DateTime(2026, 8, 1), to: DateTime(2026, 8, 31));
    expect(s.invoiceCount, 2);
    expect(s.totalAmount, 100);
    expect(s.totalPaid, 100);
  });

  test('variance report honours warehouseId', () async {
    final prod = await db.into(db.products).insert(
        ProductsCompanion.insert(code: 'P1', name: 'P1'));
    Future<void> item(int warehouse) async {
      final plan = await db.into(db.cycleCountPlans).insert(
          CycleCountPlansCompanion.insert(name: 'plan$warehouse', warehouseId: warehouse));
      final task = await db.into(db.cycleCountTasks).insert(
          CycleCountTasksCompanion.insert(planId: plan, taskDate: DateTime(2026, 8, 1)));
      await db.into(db.cycleCountItems).insert(CycleCountItemsCompanion.insert(
            taskId: task,
            productId: prod,
            expectedQty: 10,
            countedQty: const Value(8),
            variance: const Value(-2),
            variancePercent: const Value(-20),
            countedAt: Value(DateTime(2026, 8, 2)),
          ));
    }

    await item(1);
    await item(2);
    expect((await db.getVarianceReport()).length, 2);
    expect((await db.getVarianceReport(warehouseId: 1)).length, 1);
  });
}
