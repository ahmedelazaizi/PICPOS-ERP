// تدقيق القوائم المالية (2026-10-31) — مطابقة دورة كاملة بين التقارير.
//
// الدورة (انظر _fs_world.dart): مخزون افتتاحي 10×60، شراء آجل 10×60+14%،
// بيع نقدي 3×100 خصم 20 +14%، بيع آجل 2×100 خصم 10 +14%، مرتجع 1 من النقدي،
// مصروف 50، قبض 100 + خصم تسوية 5، صرف 200 + خصم مكتسب 10، شيك 40 محصَّل،
// أصل 1200 + إهلاك 100، رواتب 1000 مرحَّلة ومصروفة.
//
// مجموعتان:
//  • «ضوابط سليمة»   — يُتوقَّع نجاحها (دليل أن المطابقة قائمة).
//  • «مخالفات»       — تُثبت السلوك الصحيح المتوقَّع؛ فشلُها اليوم = المخالفة.
//
// تشغيل: flutter test --run-skipped --concurrency=1 --dart-define=APP_BRAND=picpos <الملف>
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/models/sales_returns_netting.dart';

import '_fs_world.dart';

void main() {
  late ScenarioWorld w;
  late FsCycle cy;
  late Map<String, dynamic> inc;

  setUpAll(() async {
    w = await ScenarioWorld.create();
    cy = FsCycle(w);
    await cy.run();
    inc = await cy.income();
  });
  tearDownAll(() => w.dispose());

  double n(Object? v) => (v as num).toDouble();

  group('ضوابط سليمة', () {
    test('P1 ميزان المراجعة متوازن ويطابق مجموع أسطر القيود', skip: auditSkip,
        () async {
      expect(await w.unbalancedEntries(), isEmpty);
      final tb = await w.trialBalanceTotals();
      final j = await w.journalTotals();
      expect(tb.debit, closeTo(tb.credit, kEps));
      expect(tb.debit, closeTo(j.debit, kEps));
    });

    test('P2 المركز المالي: الأصول = الخصوم + حقوق الملكية', skip: auditSkip,
        () async {
      final bs = await cy.balanceSheet();
      expect(bs['isBalanced'], isTrue);
      expect(n(bs['totalAssets']),
          closeTo(n(bs['totalLiabilities']) + n(bs['totalEquity']), 0.01));
      // صافي الربح المضاف لحقوق الملكية = صافي ربح قائمة الدخل لنفس السنة
      final pl = (bs['equityDetails'] as List).cast<Map>()
          .firstWhere((e) => e['name'] == 'صافي الأرباح (دوري)');
      expect(n(pl['balance']), closeTo(n(inc['netProfit']), kEps));
    });

    test('P3 لا انحراف بين accounts.balance المخزَّن ومجموع القيود', skip: auditSkip,
        () async {
      expect(await cy.cachedBalanceDrift(), isEmpty);
    });

    test('P4 المخزون: الكمية 16 وقيمة الأستاذ 1136 = 16×60 = 960', skip: auditSkip,
        () async {
      expect(await w.stock(cy.product), closeTo(16, kEps));
      expect(await w.accountNet('1136'), closeTo(960, kEps));
    });

    test('P5 الذمم: بطاقة العميل/المورد = حسابه في الأستاذ', skip: auditSkip,
        () async {
      // عميل: 216.6 − (100+5) − 40 = 71.6
      expect(await w.partyBalance(cy.customer), closeTo(71.6, kEps));
      expect(await w.accountNet('1121'), closeTo(71.6, kEps));
      // مورد: 684 − (200+10) = 474
      expect(await w.partyBalance(cy.supplier), closeTo(474, kEps));
      expect(await w.accountNet('2111'), closeTo(-474, kEps));
    });

    test('P6 VAT: المحصَّلة صافية من المرتجع، والمدفوعة 84', skip: auditSkip,
        () async {
      final t = await w.db.getTaxReport(winFrom, winTo);
      expect(n(t['salesTax']), closeTo(39.2 + 26.6 - 13.067, 0.01));
      expect(n(t['purchaseTax']), closeTo(84, kEps));
      expect(n(t['netTax']), closeTo(52.733 - 84, 0.01));
      expect(n(inc['outputVatNet']), closeTo(n(t['salesTax']), kEps));
    });

    test('P7 مردودات المبيعات تخفيضٌ للإيراد لا مصروف', skip: auditSkip, () async {
      expect(n(inc['salesReturns']), closeTo(93.333, 0.01));
      final exp = (inc['expenseDetails'] as List).cast<Map>().map((e) => e['name']);
      expect(exp, isNot(contains('مردودات المبيعات')));
      final rev = (inc['revenueDetails'] as List).cast<Map>()
          .firstWhere((e) => e['name'] == 'مردودات المبيعات');
      expect(n(rev['amount']), closeTo(-93.333, 0.01));
    });

    test('P8 صافي المبيعات (تقرير المبيعات بعد المرتجعات، بلا ضريبة) = 4121−4212−4211',
        skip: auditSkip, () async {
      final gross = await w.db.getSalesAnalytics(winFrom, winTo);
      final returned = await w.db
          .getReturnedAmountsForInvoices([cy.cashInvoice, cy.creditInvoice]);
      final invs = await (w.db.select(w.db.salesInvoices)).get();
      final net = netOfReturns(
          gross,
          clampedReturnedTotal(
              returnedByInvoice: returned,
              displayedInvoiceTotals: {for (final i in invs) i.id: i.total}));
      final glNetSales = -(await w.accountNet('4121')) -
          (await w.accountNet('4212')) - (await w.accountNet('4211'));
      expect(glNetSales, closeTo(376.667, 0.01));
      expect(net.totalNetRevenue, closeTo(glNetSales, 0.01));
      // المبيعات الصافية = إجمالي (500) − خصم (30) − مرتجع (93.333)
      expect(500 - gross.totalDiscount - n(inc['salesReturns']),
          closeTo(glNetSales, 0.01));
    });

    test('P9 تكلفة البضاعة المباعة = (5 مباعة − 1 مرتجعة) × 60 = حركة المخزون',
        skip: auditSkip, () async {
      expect(n(inc['totalCOGS']), closeTo(240, kEps));
      final mv = await w.db.customSelect(
          'select movement_type t, sum(quantity) q, sum(quantity * coalesce(unit_cost,0)) v '
          'from stock_movements where product_id = ? group by movement_type',
          variables: [Variable<int>(cy.product)]).get();
      // ignore: avoid_print
      print('P9 stock_movements ${mv.map((r) => r.data).toList()}');
    });
  });

  group('مخالفات (فشلُ الاختبار = المخالفة)', () {
    test('V1 «صافي الإيراد» لا يشمل خصم التسوية المكتسب من المورد (4202)',
        skip: auditSkip, () async {
      // المتوقع: 470 − 93.333 = 376.667 ؛ الفعلي يضيف 10 من 4202
      expect(n(inc['totalRevenue']), closeTo(376.667, 0.01));
    });

    test('V2 خصم التسوية في السندات يُرحَّل إلى الحسابات المربوطة (6215/4316) لا 5205/4202',
        skip: auditSkip, () async {
      final r5205 = await w.db.getAccountByCode('5205');
      final r4202 = await w.db.getAccountByCode('4202');
      // ignore: avoid_print
      print('V2 5205 parent=${r5205?.parentId} type=${r5205?.accountType}; '
          '4202 parent=${r4202?.parentId} type=${r4202?.accountType}');
      expect(await w.accountNet('6215'), closeTo(5, kEps));
      expect(await w.accountNet('4316'), closeTo(-10, kEps));
    });

    test('V3 الإهلاك يظهر في بند الإهلاك المستقل (totalDepreciation = 100)',
        skip: auditSkip, () async {
      expect(n(inc['totalDepreciation']), closeTo(100, kEps));
    });

    test('V4 أرصدة الصناديق (لوحة القيادة/الخزينة) = حسابات النقدية في الأستاذ',
        skip: auditSkip, () async {
      final safes = await w.db.select(w.db.safes).get();
      final perSafe = <String>[];
      for (final s in safes) {
        if (s.linkedAccountId == null) continue;
        final acc = await (w.db.select(w.db.accounts)
              ..where((a) => a.id.equals(s.linkedAccountId!)))
            .getSingle();
        final gl = await w.accountNet(acc.code);
        perSafe.add('${s.name}: safe=${s.balance} gl(${acc.code})=$gl');
      }
      // ignore: avoid_print
      print('V4 $perSafe');
      final glCash = await w.accountNet('111');
      expect(await cy.sumSafes(), closeTo(glCash, kEps),
          reason: 'Σ safes.balance يجب أن يساوي حساب النقدية 111*');
    });

    test('V5 تقرير VAT: «إجمالي المبيعات بدون ضريبة» = وعاء الضريبة المحصَّلة',
        skip: auditSkip, () async {
      final t = await w.db.getTaxReport(winFrom, winTo);
      expect(n(t['salesTotalExclTax']), closeTo(n(t['salesTax']) / 0.14, 0.02));
    });

    test('V6 قائمة التدفقات: تصنيف المقبوض من العملاء/المدفوع للموردين/الرواتب/الشيكات',
        skip: auditSkip, () async {
      final cf = await w.db.getCashFlowStatement(winFrom, winTo);
      final op = cf['operating'] as Map;
      final fin = cf['financing'] as Map;
      expect(n(op['receiptsFromCustomers']), closeTo(140, kEps),
          reason: 'قبض 100 + شيك عميل محصَّل 40');
      expect(n(op['paymentsToSuppliers']), closeTo(200, kEps));
      expect(n(op['salaries']), closeTo(1000, kEps));
      expect(n(fin['checksCollected']), closeTo(0, kEps),
          reason: 'تحصيل شيك عميل نشاط تشغيلي (IAS 7.14) لا تمويلي');
    });

    test('V7 الخصم المسموح به في فاتورة البيع يُفصَح عنه في الأستاذ (4212 = 30)',
        skip: auditSkip, () async {
      final sa = await w.db.getSalesAnalytics(winFrom, winTo);
      expect(sa.totalDiscount, closeTo(30, kEps));
      expect(await w.accountNet('4212'), closeTo(30, kEps));
    });

    test('V8 لوحة القيادة «شامل الضريبة» = تقرير المبيعات بعد المرتجعات', skip: auditSkip,
        () async {
      final gross = await w.db.getSalesAnalytics(winFrom, winTo);
      final returned = await w.db
          .getReturnedAmountsForInvoices([cy.cashInvoice, cy.creditInvoice]);
      final invs = await (w.db.select(w.db.salesInvoices)).get();
      final net = netOfReturns(
          gross,
          clampedReturnedTotal(
              returnedByInvoice: returned,
              displayedInvoiceTotals: {for (final i in invs) i.id: i.total}));
      // ignore: avoid_print
      print('V8 report.totalSales=${net.totalSales} dashboard.netRevenueInclVat=${inc['netRevenueInclVat']}');
      expect(n(inc['netRevenueInclVat']), closeTo(net.totalSales, 0.01));
    });

    // FS-16 (2026-11-03): كان V9 يستدعي `netOfReturns` بلا قيود المرتجع، أي
    // المسارَ التناسبيَّ القديم، فيعطي 136.241 (تكلفةُ المرتجع 300×106.4/535.8
    // = 59.574 بدل 60 المقيّدة). شاشةُ التقرير صارت تمرّر `actual` من قيد
    // المرتجع، فالاختبارُ يستدعي **المسارَ نفسَه** الذي تستدعيه الشاشة
    // (`_netOfDisplayedReturns`). التأكيدُ نفسُه لم يُرخَ: الربحُ = مجملُ ربح
    // الأستاذ بهامش 0.01، وأُضيف إليه تطابقُ الإيراد والتكلفة كلٌّ على حدة.
    test('V9 ربح تقرير المبيعات = مجمل ربح الأستاذ', skip: auditSkip, () async {
      final gross = await w.db.getSalesAnalytics(winFrom, winTo);
      final ids = [cy.cashInvoice, cy.creditInvoice];
      final returned = await w.db.getReturnedAmountsForInvoices(ids);
      final invs = await (w.db.select(w.db.salesInvoices)).get();
      final actual = returnsProfitBasis(
          gross: gross,
          returnedByInvoice: returned,
          displayedInvoices: invs,
          ledgerByInvoice: await w.db.getReturnLedgerAmountsForInvoices(ids));
      final net = netOfReturns(
          gross,
          clampedReturnedTotal(
              returnedByInvoice: returned,
              displayedInvoiceTotals: {for (final i in invs) i.id: i.total}),
          actual: actual);
      final glNetSales = -(await w.accountNet('4121')) -
          (await w.accountNet('4212')) -
          (await w.accountNet('4211'));
      final glCogs = await w.accountNet('5211');
      final glGross = glNetSales - glCogs;
      // ignore: avoid_print
      print('V9 report.profit=${net.totalProfit} gl.grossProfit(sales only)=$glGross '
          'report.cogs=${net.totalCOGS} gl.5211=$glCogs');
      expect(actual.isEstimated, isFalse,
          reason: 'المرتجعُ له قيدٌ محلّيّ — لا مبرّرَ للتقدير');
      expect(net.totalNetRevenue, closeTo(glNetSales, 0.01));
      expect(net.totalCOGS, closeTo(glCogs, 0.01));
      expect(net.totalProfit, closeTo(glGross, 0.01));
    });
  });
}
