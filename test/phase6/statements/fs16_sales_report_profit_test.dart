// FS-16 — ربحُ تقرير المبيعات يُحسم بقيد المرتجع لا بالتناسب.
//
// المسارُ الحقيقيّ: بيعٌ عبر الـorchestrator ومرتجعٌ عبر
// `ReturnsRepositoryImpl.processSalesReturn` (ما تناديه شاشةُ المرتجعات)،
// ثمّ نفسُ نداءات `sales_report_screen._netOfDisplayedReturns`.
//
// الدورة: افتتاحيٌّ 10×60، بيعٌ X بضريبة 14% 3×100 بخصم 20، شراءٌ 10×90 (يغيّر
// المتوسّطَ المرجّح)، بيعٌ Y بلا ضريبة 2×100، ثمّ مرتجعُ وحدةٍ من X (تكلفتُها
// المجمَّدةُ 60 لا المتوسّطُ الجديد).
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/models/sales_returns_netting.dart';
import 'package:picpos_erp/domain/repositories/purchases_repository.dart';

import '../../scenarios/scenario_world.dart';

void main() {
  late ScenarioWorld w;
  late int x;
  late int y;

  setUpAll(() async {
    w = await ScenarioWorld.create();
    final p = await w.addProduct('FS16', price: 100, cost: 60, stock: 10);
    final rx = await w.sales.completeSalesTransaction(SaleRequest(
      items: [w.line(p, 3, 100)],
      warehouseId: w.warehouseId,
      userId: w.userId,
      paymentMethod: 'cash',
      paidAmount: 280 * 1.14,
      taxEnabled: true,
      taxPercent: 14,
      invoiceDiscountAmount: 20,
      cashSafeId: w.cashSafeId,
    ));
    expect(rx.isSuccess, isTrue, reason: rx.errorMessage);
    x = rx.invoiceId!;
    await w.container.read(purchasesRepositoryProvider).createInvoice(
        CreatePurchaseInvoiceParams(
            supplierId: await w.addSupplier('مورد FS16'),
            warehouseId: w.warehouseId,
            paid: 0,
            paymentMethod: 'credit',
            userId: w.userId,
            items: [
          PurchaseItemParams(
              productId: p,
              quantity: 10,
              unitCost: 90,
              salePrice: 100,
              taxRate: 0,
              taxAmount: 0)
        ]));
    y = (await w.sell([w.line(p, 2, 100)])).invoiceId!;
    expect(await w.returnItems(x, p, 1), isTrue);
  });
  tearDownAll(() => w.dispose());

  Future<({SalesAnalytics gross, Map<int, double> returned,
      List<SalesInvoiceData> invs})> load() async {
    final gross = await w.db.getSalesAnalytics(
        DateTime.now().subtract(const Duration(days: 1)), DateTime.now());
    final invs = await (w.db.select(w.db.salesInvoices)
          ..where((i) => i.id.isIn([x, y])))
        .get();
    return (
      gross: gross,
      returned: await w.db.getReturnedAmountsForInvoices([x, y]),
      invs: invs,
    );
  }

  test('الربحُ والتكلفةُ والإيراد = الأستاذ؛ والتقديرُ القديمُ لا يساويه',
      () async {
    final d = await load();
    final clamped = clampedReturnedTotal(
        returnedByInvoice: d.returned,
        displayedInvoiceTotals: {for (final i in d.invs) i.id: i.total});
    final actual = returnsProfitBasis(
        gross: d.gross,
        returnedByInvoice: d.returned,
        displayedInvoices: d.invs,
        ledgerByInvoice: await w.db.getReturnLedgerAmountsForInvoices([x, y]));
    final exact = netOfReturns(d.gross, clamped, actual: actual);
    final legacy = netOfReturns(d.gross, clamped);

    final glNet = -(await w.accountNet('4121')) -
        (await w.accountNet('4212')) -
        (await w.accountNet('4211'));
    final glCogs = await w.accountNet('5211');
    // ignore: avoid_print
    print('FS16 gross: rev=${d.gross.totalNetRevenue} cogs=${d.gross.totalCOGS} '
        'profit=${d.gross.totalProfit} refund=${d.returned}\n'
        'FS16 legacy: rev=${legacy.totalNetRevenue} cogs=${legacy.totalCOGS} '
        'profit=${legacy.totalProfit}\n'
        'FS16 exact:  rev=${exact.totalNetRevenue} cogs=${exact.totalCOGS} '
        'profit=${exact.totalProfit}\n'
        'FS16 gl:     rev=$glNet cogs=$glCogs profit=${glNet - glCogs}');

    expect(actual.isEstimated, isFalse);
    expect(exact.totalNetRevenue, closeTo(glNet, 0.01));
    expect(exact.totalCOGS, closeTo(glCogs, 0.01));
    expect(exact.totalProfit, closeTo(glNet - glCogs, 0.01));
    // الدليلُ على العطب: المسارُ التناسبيُّ يخطئ هنا بأكثرَ من قرش.
    expect((legacy.totalProfit - (glNet - glCogs)).abs(), greaterThan(0.01));
    // وبطاقةُ «إجمالي المبيعات» لم تتغيّر: نفسُ القصّ في المسارين.
    expect(exact.totalSales, closeTo(legacy.totalSales, 1e-9));
  });

  // التوصيلُ يُرحَّل للبيع على 414 لا 4121، وقيدُ المرتجع يضمّ حصّةَ التوصيل
  // من المردود إلى 4211 (‏`salesReturnNet = refund − vat`). التقريرُ يستثني
  // التوصيلَ من الإيراد في الاتّجاهين، فالفرقُ عن `4121 − 4211` هو حصّةُ
  // التوصيل بالضبط (5) — فرقُ تبويبٍ في الأستاذ موثَّقٌ لا تقدير.
  test('فاتورةٌ بتوصيل: المطروحُ = 4211 − حصّةِ التوصيل، والتكلفةُ = قيد المرتجع',
      () async {
    final v = await ScenarioWorld.create();
    addTearDown(v.dispose);
    final p = await v.addProduct('FS16D', price: 100, cost: 60, stock: 10);
    final r = await v.sales.completeSalesTransaction(SaleRequest(
      items: [v.line(p, 2, 100)],
      warehouseId: v.warehouseId,
      userId: v.userId,
      paymentMethod: 'cash',
      paidAmount: 238,
      taxEnabled: true,
      taxPercent: 14,
      deliveryFee: 10,
      cashSafeId: v.cashSafeId,
    ));
    expect(r.isSuccess, isTrue, reason: r.errorMessage);
    final id = r.invoiceId!;
    final inv = (await v.db.getSalesInvoiceById(id))!;
    final before4211 = await v.accountNet('4211');
    expect(await v.returnItems(id, p, 1), isTrue);
    final refund = await v.db.getReturnedAmountsForInvoices([id]);
    final ledger = await v.db.getReturnLedgerAmountsForInvoices([id]);
    final gross = await v.db.getSalesAnalytics(
        DateTime.now().subtract(const Duration(days: 1)), DateTime.now());
    final basis = returnsProfitBasis(
        gross: gross,
        returnedByInvoice: refund,
        displayedInvoices: [inv],
        ledgerByInvoice: ledger);
    final gl4211 = await v.accountNet('4211') - before4211;
    final deliveryShare = refund[id]! * inv.deliveryFee / inv.total;
    // ignore: avoid_print
    print('FS16D total=${inv.total} tax=${inv.tax} delivery=${inv.deliveryFee} '
        'refund=$refund ledger=$ledger basis.rev=${basis.netRevenue} '
        'basis.cogs=${basis.cogs} gl4211=$gl4211 gl414=${await v.accountNet('414')}');

    expect(refund[id], closeTo(119, kEps)); // (200 + 28 + 10) / 2
    expect(gl4211, closeTo(105, kEps)); // 119 − 14 ضريبة
    expect(deliveryShare, closeTo(5, kEps));
    expect(basis.netRevenue, closeTo(gl4211 - deliveryShare, kEps));
    expect(basis.netRevenue, closeTo(100, kEps)); // وحدةٌ بسعر 100 بلا ضريبة
    expect(basis.cogs, closeTo(60, kEps));
    expect(basis.isEstimated, isFalse);
  });

  test('مرتجعٌ بلا قيدٍ محلّيّ يُعلَّم تقديرياً ولا يُختلَق', () async {
    final d = await load();
    final actual = returnsProfitBasis(
        gross: d.gross,
        returnedByInvoice: d.returned,
        displayedInvoices: d.invs,
        ledgerByInvoice: const {});
    expect(actual.estimatedInvoiceCount, 1);
    expect(actual.isEstimated, isTrue);
  });
}
