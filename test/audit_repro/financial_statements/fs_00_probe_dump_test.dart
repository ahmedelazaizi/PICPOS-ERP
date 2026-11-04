// تدقيق القوائم المالية — تفريغ رقمي لدورة كاملة (دليل خام للتقرير).
// تشغيل: flutter test --run-skipped --concurrency=1 --dart-define=APP_BRAND=picpos <هذا الملف>
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '_fs_world.dart';

void main() {
  test('dump: full cycle numbers', skip: auditSkip, () async {
    final w = await ScenarioWorld.create();
    addTearDown(w.dispose);
    final cy = FsCycle(w);
    await cy.run();
    String j(Object? o) => const JsonEncoder.withIndent(' ').convert(o,);
    final inc = await cy.income();
    final bs = await cy.balanceSheet();
    final tb = await w.db.getTrialBalance(winFrom, winTo);
    final tax = await w.db.getTaxReport(winFrom, winTo);
    final cf = await w.db.getCashFlowStatement(winFrom, winTo);
    final sa = await w.db.getSalesAnalytics(winFrom, winTo);
    final safes = await w.db.select(w.db.safes).get();
    final invs = await w.db.customSelect(
        'select id, invoice_number, sale_type, status, subtotal, discount, tax, total, paid, payment_method, invoice_date from sales_invoices').get();
    final ret = await w.db.getReturnedAmountsForInvoices([cy.cashInvoice, cy.creditInvoice]);
    // ignore: avoid_print
    print('LOG ${cy.log}');
    // ignore: avoid_print
    print('INVOICES ${invs.map((r) => r.data).toList()}');
    // ignore: avoid_print
    print('RETURNED $ret');
    // ignore: avoid_print
    print('SALES_ANALYTICS totalSales=${sa.totalSales} disc=${sa.totalDiscount} tax=${sa.totalTax} cogs=${sa.totalCOGS} netRev=${sa.totalNetRevenue} profit=${sa.totalNetProfit} count=${sa.invoiceCount}');
    // ignore: avoid_print
    print('INCOME ${j(inc)}');
    // ignore: avoid_print
    print('BS ${j(bs)}');
    // ignore: avoid_print
    print('TB_TOTAL ${tb.lastWhere((r) => r['type'] == 'total')}');
    // ignore: avoid_print
    print('TAX ${j(tax)}');
    // ignore: avoid_print
    print('CASHFLOW ${j(cf)}');
    // ignore: avoid_print
    print('SAFES ${safes.map((s) => '${s.id}:${s.name}:${s.safeType}:${s.balance}').toList()} sum=${await cy.sumSafes()}');
    // ignore: avoid_print
    print('DRIFT ${await cy.cachedBalanceDrift()}');
    for (final m in await cy.accountMovements()) {
      // ignore: avoid_print
      print('ACC $m');
    }
    for (final e in await cy.entries()) {
      // ignore: avoid_print
      print('JE $e');
    }
  });
}
