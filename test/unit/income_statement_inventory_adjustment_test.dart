// Field issue #2 (2026-07-14) — adding stock via a تسوية (adjustment) inflated
// the dashboard "صافي الإيراد" (net revenue) and "صافي الربح" (net profit).
//
// Root cause: an upward adjustment posts Dr Inventory / Cr Inventory-Surplus
// (4317). 4317 is account_type 'revenue', and getIncomeStatement summed ALL
// revenue accounts into totalRevenue → a stock top-up looked like sales.
//
// Fix: surplus (4317) → otherIncome, shrinkage (6216) → otherExpense; both are
// excluded from the operating totalRevenue/totalExpenses but folded back into
// netProfit (so netProfit is numerically unchanged — a genuine surplus is still
// a gain). This proves net revenue is now sales-only.
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int warehouseId;
  late int productId;

  setUp(() async {
    db = AppDatabase.forTesting();
    final wh = await db.getDefaultWarehouse();
    warehouseId = wh!.id;
    productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'SURP-1',
        name: 'صنف فائض',
        costPrice: const Value(0.39),
        currentStock: const Value(0),
        trackInventory: const Value(true),
      ),
    );
  });

  tearDown(() async => db.close());

  test('inventory surplus adjustment is otherIncome, NOT sales revenue', () async {
    // Upward 'adjustment' of 1000 @ cost 0.39 → surplus gain 390 credited to 4317.
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 1000,
      type: 'adjustment',
      notes: 'load stock',
    );

    final pl = await db.getIncomeStatement(DateTime(2000), DateTime(2100));

    expect(pl['totalRevenue'] as double, closeTo(0, 0.001),
        reason: 'a stock adjustment is NOT sales — net revenue must stay 0');
    expect(pl['otherIncome'] as double, closeTo(390, 0.001),
        reason: 'the surplus is a non-operating gain');
    expect(pl['netProfit'] as double, closeTo(390, 0.001),
        reason: 'net profit still reflects the genuine surplus (unchanged)');
  });
}
