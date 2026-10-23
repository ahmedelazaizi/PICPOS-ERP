// ═══════════════════════════════════════════════════════════════════════════
// م-3 (Spec 153 totals-reconciliation) — every sales aggregate must exclude
// returns AND void/cancelled invoices with the SAME predicate.
//
// The actual divergence: getSalesAnalytics (and the sibling KPIs) already
// excluded new-shape POSITIVE-total returns via `sale_type != 'return'`, but
// getCategoryProfitReport did NOT — so a positive-total return inflated
// category profit only. The fix shares one RETURN predicate so both agree.
//
// Void/cancelled invoices are NOT folded into that shared predicate: a committed
// void sets `is_deleted = true`, which every query already drops. (A status
// guard on getSalesAnalytics was tried and reverted — it also excludes
// `status='returned'` ORIGINALS, which are real gross sales the returns figure
// nets out separately, and it desynced the card from the invoice list +
// return-rate + sibling aggregates.)
//
// This test pins that neither aggregate counts a positive-total return, and
// that both drop a committed void (via is_deleted).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int wId;
  late int uId;
  late int pId;
  final from = DateTime(2026, 1, 1);
  final to = DateTime(2026, 12, 31);
  final saleDate = DateTime(2026, 6, 1);

  setUp(() async {
    db = AppDatabase.forTesting();
    wId = await db
        .into(db.warehouses)
        .insert(WarehousesCompanion.insert(name: 'W1'));
    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(name: 'مدير', isSystemRole: const Value(true)),
        );
    uId = await db.createUser(
      username: 'user1',
      password: 'pass123',
      displayName: 'U1',
      roleId: roleId,
    );
    pId = await db.into(db.products).insert(
          ProductsCompanion.insert(
            name: 'صنف',
            code: 'P1',
            costPrice: const Value(4),
            salePrice: const Value(10),
          ),
        );
  });

  tearDown(() => db.close());

  // Direct row insert — full control over total / status / sale_type, and no
  // side effects (no JE posting, stock, period validation) so the test isolates
  // the WHERE predicate under review.
  Future<void> seedInvoice({
    required String number,
    required double total,
    required double itemTotal,
    String saleType = 'default',
    String status = 'completed',
    bool isDeleted = false,
  }) async {
    final invId = await db.into(db.salesInvoices).insert(
          SalesInvoicesCompanion.insert(
            invoiceNumber: number,
            warehouseId: wId,
            userId: uId,
            invoiceDate: saleDate,
            subtotal: Value(itemTotal),
            total: Value(total),
            saleType: Value(saleType),
            status: Value(status),
            isDeleted: Value(isDeleted),
          ),
        );
    await db.into(db.salesInvoiceItems).insert(
          SalesInvoiceItemsCompanion.insert(
            invoiceId: invId,
            productId: pId,
            quantity: 1,
            unitPrice: itemTotal,
            total: itemTotal,
            costPrice: const Value(4),
            quantityInBase: const Value(1),
          ),
        );
  }

  Future<double> categorySalesBase() async {
    final rows = await db.getCategoryProfitReport(from: from, to: to);
    return rows.fold<double>(0, (s, r) => s + r.totalSales);
  }

  test(
      'category-profit and sales-report both exclude a positive-total return AND a voided invoice',
      () async {
    // Baseline: one ordinary completed sale (item total 100, invoice total 115).
    await seedInvoice(number: 'S1', total: 115, itemTotal: 100);
    final catBase = await categorySalesBase();
    final repBase = await db.getSalesAnalytics(from, to);
    expect(catBase, closeTo(100, 0.001),
        reason: 'sanity: the ordinary sale IS counted by category-profit');
    expect(repBase.totalSales, closeTo(115, 0.001),
        reason: 'sanity: the ordinary sale IS counted by the sales report');
    expect(repBase.salesCount, 1, reason: 'sanity: exactly one countable sale');
    expect(repBase.totalCOGS, closeTo(4, 0.001),
        reason: 'sanity: baseline COGS = qty 1 × base 1 × cost 4');

    // A new-shape POSITIVE-total return (sale_type='return', not a void status).
    await seedInvoice(
        number: 'R1', total: 50, itemTotal: 50, saleType: 'return');
    // A committed void — as production writes it: status='voided' AND
    // is_deleted=true. Both aggregates drop it via their is_deleted = 0 guard.
    await seedInvoice(
        number: 'V1',
        total: 70,
        itemTotal: 70,
        status: 'voided',
        isDeleted: true);

    final catAfter = await categorySalesBase();
    final repAfter = await db.getSalesAnalytics(from, to);

    expect(catAfter, closeTo(catBase, 0.001),
        reason:
            'category-profit must exclude BOTH the return and the voided invoice');
    expect(repAfter.totalSales, closeTo(repBase.totalSales, 0.001),
        reason:
            'sales-report sales base must exclude BOTH the return and the voided invoice');
    expect(repAfter.salesCount, repBase.salesCount,
        reason: 'invoice count must not include the return/void');
    // Revenue AND COGS must drop the same rows — otherwise gross profit distorts
    // silently (both R1 and V1 carry cost 4; a leak into COGS would raise it).
    expect(repAfter.totalCOGS, closeTo(repBase.totalCOGS, 0.001),
        reason:
            'COGS exclusion must stay symmetric with revenue (no gross-profit distortion)');
  });
}
