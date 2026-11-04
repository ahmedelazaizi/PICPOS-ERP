// تدقيق المبيعات — (ب) مصفوفة الترحيل والكسر (2026-10-31).
//
// لكل سيناريو تُطبع الأرقام الفعلية من: قيد اليومية (كود/مدين/دائن) ·
// safe_transactions · stock_movements · accounts.balance · رصيد العميل · المخزون.
// الاختبارات تؤكد **السلوك المحاسبي الصحيح**؛ فما يفشل منها استنساخ عيب.
//   flutter test test/audit_repro/sales_purchases --run-skipped
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/entities/cart_item_entity.dart';
import 'package:picpos_erp/services/stock_shortage_policy_service.dart';

import '../../scenarios/scenario_world.dart';

const kSkip = 'audit repro — pending owner approval';

void _log(String m) {
  // ignore: avoid_print
  print('[AUDIT-SALE] $m');
}

Future<int> _ensureSafe(ScenarioWorld w, String type) async {
  final existing = await w.db.getDefaultSafeByType(type);
  if (existing != null) return existing.id;
  return w.db.into(w.db.safes).insert(SafesCompanion.insert(
        name: 'audit-$type',
        safeType: Value(type),
        isDefault: const Value(true),
      ));
}

CartItemEntity _l(int p, double qty, double price,
        {double disc = 0, double rate = 14, bool exempt = false}) =>
    CartItemEntity(
        productId: p,
        productName: 'p$p',
        productCode: 'c$p',
        quantity: qty,
        unitPrice: price,
        discountPercent: disc,
        taxRate: rate,
        taxExempt: exempt);

SaleRequest _req(ScenarioWorld w, List<CartItemEntity> items,
        {String method = 'cash',
        required double paid,
        double? cash,
        double? bank,
        double? click,
        int? customerId,
        double discountPercent = 0,
        double? invoiceDiscountAmount,
        bool tax = false,
        bool inclusive = false,
        int? bankSafeId,
        int? clickSafeId,
        String? globalId,
        DateTime? date}) =>
    SaleRequest(
      items: items,
      customerId: customerId,
      warehouseId: w.warehouseId,
      userId: w.userId,
      paymentMethod: method,
      paidAmount: paid,
      cashAmount: cash,
      bankAmount: bank,
      clickAmount: click,
      cashSafeId: w.cashSafeId,
      bankSafeId: bankSafeId,
      clickSafeId: clickSafeId,
      discountPercent: discountPercent,
      invoiceDiscountAmount: invoiceDiscountAmount,
      taxEnabled: tax,
      taxPercent: 14,
      pricesIncludeTax: inclusive,
      globalId: globalId,
      invoiceDate: date,
    );

/// خريطة كود ← (مدين − دائن) لقيد الفاتورة.
Future<Map<String, double>> _je(ScenarioWorld w, int invoiceId,
    [String ref = 'sales_invoice']) async {
  final lines = await w.linesOf(ref, invoiceId);
  final m = <String, double>{};
  for (final l in lines) {
    final code = l['code'] as String;
    m[code] = (m[code] ?? 0) + (l['debit'] as num).toDouble() - (l['credit'] as num).toDouble();
  }
  return m;
}

double _byPrefix(Map<String, double> m, String prefix) =>
    m.entries.where((e) => e.key.startsWith(prefix)).fold(0.0, (s, e) => s + e.value);

Future<String> _dump(ScenarioWorld w, int invoiceId, {int? customer}) async {
  final inv = (await w.db.getSalesInvoiceById(invoiceId))!;
  final items = await w.db.getSalesInvoiceItems(invoiceId);
  final st = await w.db.customSelect(
      'SELECT s.safe_type ty, t.transaction_type tt, t.amount a FROM safe_transactions t '
      'JOIN safes s ON s.id = t.safe_id WHERE t.reference_id = ? '
      "AND t.reference_type = 'sales_invoice'",
      variables: [Variable<int>(invoiceId)]).get();
  final mv = await w.db.customSelect(
      'SELECT product_id p, movement_type t, quantity q, unit_cost c FROM stock_movements '
      "WHERE reference_id = ? AND reference_type = 'sales_invoice'",
      variables: [Variable<int>(invoiceId)]).get();
  return 'hdr sub=${inv.subtotal} disc=${inv.discount} tax=${inv.tax} total=${inv.total} '
      'paid=${inv.paid} pm=${inv.paymentMethod} status=${inv.status} | '
      'items=${items.map((i) => 'q${i.quantity}×${i.unitPrice} tax${i.taxAmount} tot${i.total} cost${i.costPrice}').toList()} | '
      'JE=${await w.linesOf('sales_invoice', invoiceId)} | safe_tx=${st.map((e) => e.data).toList()} | '
      'moves=${mv.map((e) => e.data).toList()}'
      '${customer != null ? ' | party=${await w.partyBalance(customer)}' : ''}';
}

/// accounts.balance المخزَّن يجب أن يساوي Σ(مدين − دائن) المرحَّل لكل حساب.
Future<List<String>> _accountBalanceDrift(ScenarioWorld w) async {
  final rows = await w.db.customSelect(
      'SELECT a.code c, a.balance b, COALESCE((SELECT SUM(l.debit - l.credit) '
      'FROM journal_entry_lines l JOIN journal_entries e ON e.id = l.entry_id '
      'WHERE l.account_id = a.id AND e.is_deleted = 0),0) n FROM accounts a').get();
  return rows
      .where((r) => ((r.data['b'] as num) - (r.data['n'] as num)).abs() > 0.005)
      .map((r) => '${r.data['c']}: balance=${r.data['b']} gl=${r.data['n']}')
      .toList();
}

void main() {
  late ScenarioWorld w;
  late int q; // 100 / تكلفة 60

  setUp(() async {
    StockShortagePolicyService.resetCacheForTest();
    w = await ScenarioWorld.create();
    q = await w.addProduct('Q100', price: 100, cost: 60, stock: 500);
  });
  tearDown(() async {
    StockShortagePolicyService.resetCacheForTest();
    await w.dispose();
  });

  group('SAL-PAY قنوات الدفع', () {
    test('PAY-01 نقدي 2×100: مدين نقدية 200 / دائن 4121 200 · 5211/1136 = 120',
        skip: kSkip, () async {
      final r = await w.sell([w.line(q, 2, 100)]);
      _log('PAY-01 ${await _dump(w, r.invoiceId!)}');
      final je = await _je(w, r.invoiceId!);
      expect(_byPrefix(je, '111'), closeTo(200, kEps));
      expect(je['4121'], closeTo(-200, kEps));
      expect(je['5211'], closeTo(120, kEps));
      expect(je['1136'], closeTo(-120, kEps));
      expect(await w.unbalancedEntries(), isEmpty);
      expect(await _accountBalanceDrift(w), isEmpty);
    });

    test('PAY-02 بطاقة (card) بلا bankAmount: المدين بنك 1113 وخزنة البنك +200',
        skip: kSkip, () async {
      final bank = await _ensureSafe(w, 'bank');
      final r = await w.sales.completeSalesTransaction(
          _req(w, [w.line(q, 2, 100)], method: 'card', paid: 200, bankSafeId: bank));
      expect(r.isSuccess, isTrue, reason: r.errorMessage);
      _log('PAY-02 ${await _dump(w, r.invoiceId!)} bankSafe=${await w.safeBalance(bank)} '
          'cashSafe=${await w.safeBalance()}');
      final je = await _je(w, r.invoiceId!);
      expect(await w.safeBalance(bank), closeTo(200, kEps));
      expect(await w.safeBalance(), closeTo(0, kEps));
      expect(_byPrefix(je, '1111'), closeTo(0, kEps), reason: 'لا شيء على الصندوق');
    });

    test('PAY-03 كليك: خزنة الكليك +200 والقيد على حساب الكليك', skip: kSkip, () async {
      final click = await _ensureSafe(w, 'click');
      final r = await w.sales.completeSalesTransaction(
          _req(w, [w.line(q, 2, 100)], method: 'click', paid: 200, clickSafeId: click));
      expect(r.isSuccess, isTrue, reason: r.errorMessage);
      _log('PAY-03 ${await _dump(w, r.invoiceId!)} clickSafe=${await w.safeBalance(click)}');
      expect(await w.safeBalance(click), closeTo(200, kEps));
      expect(await w.safeBalance(), closeTo(0, kEps));
    });

    test('PAY-04 آجل بالكامل: ذمم 200 ورصيد العميل +200 ولا حركة خزنة', skip: kSkip, () async {
      final c = await w.addCustomer('عميل آجل');
      final r = await w.sell([w.line(q, 2, 100)], customerId: c, method: 'credit', paid: 0);
      _log('PAY-04 ${await _dump(w, r.invoiceId!, customer: c)}');
      final je = await _je(w, r.invoiceId!);
      expect(_byPrefix(je, '112'), closeTo(200, kEps));
      expect(await w.partyBalance(c), closeTo(200, kEps));
      expect(await w.safeBalance(), closeTo(0, kEps));
    });

    test('PAY-05 آجل بدفعة مقدمة 50 بالبنك: البنك 50 في الخزنة وفي القيد (لا على الصندوق)',
        skip: kSkip, () async {
      final bank = await _ensureSafe(w, 'bank');
      final c = await w.addCustomer('عميل جزئي');
      final r = await w.sales.completeSalesTransaction(_req(w, [w.line(q, 2, 100)],
          method: 'credit', paid: 50, cash: 0, bank: 50, bankSafeId: bank, customerId: c));
      expect(r.isSuccess, isTrue, reason: r.errorMessage);
      final bankAcc = (await w.db.resolveSafeGlAccount((await w.db.getSafeById(bank))!))!.code;
      _log('PAY-05 ${await _dump(w, r.invoiceId!, customer: c)} bankSafe=${await w.safeBalance(bank)} '
          'cashSafe=${await w.safeBalance()} bankAcc=$bankAcc');
      final je = await _je(w, r.invoiceId!);
      expect(await w.safeBalance(bank), closeTo(50, kEps));
      expect(je[bankAcc] ?? 0, closeTo(50, kEps),
          reason: 'autoPostCreditSale يرحّل الدفعة المقدمة على ساق النقدية فقط');
      expect(_byPrefix(je, '112'), closeTo(150, kEps));
      expect(await w.partyBalance(c), closeTo(150, kEps));
    });

    test('PAY-06 مختلط نقد 60 + بنك 40', skip: kSkip, () async {
      final bank = await _ensureSafe(w, 'bank');
      final r = await w.sales.completeSalesTransaction(_req(w, [w.line(q, 1, 100)],
          method: 'mixed', paid: 100, cash: 60, bank: 40, bankSafeId: bank));
      expect(r.isSuccess, isTrue, reason: r.errorMessage);
      _log('PAY-06 ${await _dump(w, r.invoiceId!)}');
      expect(await w.safeBalance(), closeTo(60, kEps));
      expect(await w.safeBalance(bank), closeTo(40, kEps));
      expect(await w.unbalancedEntries(), isEmpty);
    });
  });

  group('SAL-DSC الخصومات', () {
    test('DSC-01 خصم سطر 10% على 2×100: 4121 دائن 200 و4212 مدين 20 (خصم مسموح به)',
        skip: kSkip, () async {
      final r = await w.sales.completeSalesTransaction(
          _req(w, [_l(q, 2, 100, disc: 10)], paid: 180));
      expect(r.isSuccess, isTrue, reason: r.errorMessage);
      _log('DSC-01 ${await _dump(w, r.invoiceId!)}');
      final je = await _je(w, r.invoiceId!);
      expect(je['4121'], closeTo(-200, kEps));
      expect(je['4212'], closeTo(20, kEps));
      expect(_byPrefix(je, '111'), closeTo(180, kEps));
    });

    test('DSC-02 خصم فاتورة 10% و DSC-03 مبلغ ثابت 15', skip: kSkip, () async {
      final r1 = await w.sales.completeSalesTransaction(
          _req(w, [w.line(q, 2, 100)], paid: 180, discountPercent: 10));
      final r2 = await w.sales.completeSalesTransaction(
          _req(w, [w.line(q, 2, 100)], paid: 185, invoiceDiscountAmount: 15));
      expect(r1.isSuccess && r2.isSuccess, isTrue);
      _log('DSC-02 ${await _dump(w, r1.invoiceId!)}');
      _log('DSC-03 ${await _dump(w, r2.invoiceId!)}');
      expect((await _je(w, r1.invoiceId!))['4212'], closeTo(20, kEps));
      expect((await _je(w, r2.invoiceId!))['4212'], closeTo(15, kEps));
    });

    test('DSC-04 خصم نسبة 150% ⇒ يجب الرفض (لا إجمالي سالب)', skip: kSkip, () async {
      final r = await w.sales.completeSalesTransaction(
          _req(w, [w.line(q, 1, 100)], paid: 0, discountPercent: 150));
      if (r.isSuccess) _log('DSC-04 ${await _dump(w, r.invoiceId!)}');
      _log('DSC-04 success=${r.isSuccess} err=${r.errorMessage}');
      expect(r.isSuccess, isFalse);
    });

    test('DSC-05 خصم سطر 150% ⇒ يجب الرفض', skip: kSkip, () async {
      final r = await w.sales.completeSalesTransaction(
          _req(w, [_l(q, 1, 100, disc: 150)], paid: 0));
      if (r.isSuccess) _log('DSC-05 ${await _dump(w, r.invoiceId!)} safe=${await w.safeBalance()}');
      _log('DSC-05 success=${r.isSuccess} err=${r.errorMessage}');
      expect(r.isSuccess, isFalse);
    });

    test('DSC-06 خصم ثابت 500 على 100 ⇒ يُقصّ عند 100 والإجمالي صفر', skip: kSkip, () async {
      final r = await w.sales.completeSalesTransaction(
          _req(w, [w.line(q, 1, 100)], paid: 0, invoiceDiscountAmount: 500));
      _log('DSC-06 success=${r.isSuccess} err=${r.errorMessage} '
          '${r.isSuccess ? await _dump(w, r.invoiceId!) : ''}');
      expect(r.isSuccess, isTrue);
      final inv = (await w.db.getSalesInvoiceById(r.invoiceId!))!;
      expect(inv.total, closeTo(0, kEps));
      expect(await w.unbalancedEntries(), isEmpty);
    });
  });

  group('SAL-TAX الضريبة والتقريب', () {
    test('TAX-01 غير شاملة 14% على 2×100: ضريبة 28 على 2121 والإجمالي 228', skip: kSkip,
        () async {
      final r = await w.sales.completeSalesTransaction(
          _req(w, [_l(q, 2, 100)], paid: 228, tax: true));
      expect(r.isSuccess, isTrue, reason: r.errorMessage);
      _log('TAX-01 ${await _dump(w, r.invoiceId!)}');
      final je = await _je(w, r.invoiceId!);
      expect(je['2121'], closeTo(-28, kEps));
      expect(je['4121'], closeTo(-200, kEps));
      expect(_byPrefix(je, '111'), closeTo(228, kEps));
    });

    test('TAX-02 شاملة 14%: 2×114 ⇒ صافي 200 وضريبة 28', skip: kSkip, () async {
      final r = await w.sales.completeSalesTransaction(
          _req(w, [_l(q, 2, 114)], paid: 228, tax: true, inclusive: true));
      expect(r.isSuccess, isTrue, reason: r.errorMessage);
      _log('TAX-02 ${await _dump(w, r.invoiceId!)}');
      final je = await _je(w, r.invoiceId!);
      expect(je['2121'], closeTo(-28, kEps));
      expect(je['4121'], closeTo(-200, kEps));
    });

    test('TAX-03 شاملة + خصم فاتورة 10%: 4121 − 4212 = الصافي قبل الضريبة (180)', skip: kSkip,
        () async {
      final r = await w.sales.completeSalesTransaction(_req(w, [_l(q, 2, 114)],
          paid: 205.2, tax: true, inclusive: true, discountPercent: 10));
      expect(r.isSuccess, isTrue, reason: r.errorMessage);
      _log('TAX-03 ${await _dump(w, r.invoiceId!)}');
      final inv = (await w.db.getSalesInvoiceById(r.invoiceId!))!;
      final je = await _je(w, r.invoiceId!);
      expect(inv.subtotal - inv.discount + inv.tax, closeTo(inv.total, kEps),
          reason: 'معادلة الرأس subtotal − discount + tax = total');
      expect(-(je['4121'] ?? 0) - (je['4212'] ?? 0), closeTo(180, kEps));
      expect(je['2121'], closeTo(-25.2, kEps));
    });

    test('TAX-04 سطر معفى + سطر خاضع', skip: kSkip, () async {
      final r = await w.sales.completeSalesTransaction(
          _req(w, [_l(q, 1, 100), _l(q, 1, 100, exempt: true)], paid: 214, tax: true));
      expect(r.isSuccess, isTrue, reason: r.errorMessage);
      _log('TAX-04 ${await _dump(w, r.invoiceId!)}');
      expect((await _je(w, r.invoiceId!))['2121'], closeTo(-14, kEps));
    });

    test('TAX-05 تقريب: 3×6.99 شاملة 14% + 7×0.333 ⇒ توازن القيد وتطابق الرأس والأسطر',
        skip: kSkip, () async {
      final p = await w.addProduct('R', price: 6.99, cost: 4.123456, stock: 100);
      final r = await w.sales.completeSalesTransaction(_req(
          w, [_l(p, 3, 6.99), _l(p, 7, 0.333)],
          paid: 23.301, tax: true, inclusive: true));
      expect(r.isSuccess, isTrue, reason: r.errorMessage);
      _log('TAX-05 ${await _dump(w, r.invoiceId!)}');
      final inv = (await w.db.getSalesInvoiceById(r.invoiceId!))!;
      final items = await w.db.getSalesInvoiceItems(r.invoiceId!);
      expect(items.fold<double>(0, (s, i) => s + i.taxAmount), closeTo(inv.tax, kEps));
      expect(await w.unbalancedEntries(), isEmpty);
    });
  });

  group('SAL-BRK اختبارات الكسر', () {
    test('BRK-01 كمية صفرية ⇒ رفض', skip: kSkip, () async {
      final r = await w.sales.completeSalesTransaction(_req(w, [w.line(q, 0, 100)], paid: 0));
      _log('BRK-01 success=${r.isSuccess} err=${r.errorMessage} '
          '${r.isSuccess ? await _dump(w, r.invoiceId!) : ''}');
      expect(r.isSuccess, isFalse);
    });

    test('BRK-02 كمية سالبة −3 في فاتورة بيع ⇒ رفض (وإلا يزيد المخزون ويُخرج نقداً)',
        skip: kSkip, () async {
      final before = await w.stock(q);
      final r = await w.sales.completeSalesTransaction(_req(w, [w.line(q, -3, 100)], paid: -300));
      _log('BRK-02 success=${r.isSuccess} err=${r.errorMessage} stock $before→${await w.stock(q)} '
          'safe=${await w.safeBalance()} ${r.isSuccess ? await _dump(w, r.invoiceId!) : ''}');
      expect(r.isSuccess, isFalse);
    });

    test('BRK-03 سعر سالب −100 ⇒ رفض', skip: kSkip, () async {
      final r = await w.sales.completeSalesTransaction(_req(w, [w.line(q, 1, -100)], paid: -100));
      _log('BRK-03 success=${r.isSuccess} err=${r.errorMessage} safe=${await w.safeBalance()} '
          '${r.isSuccess ? await _dump(w, r.invoiceId!) : ''}');
      expect(r.isSuccess, isFalse);
    });

    test('BRK-04 مدفوع > الإجمالي في بيع نقدي (paid 500 لإجمالي 100)', skip: kSkip, () async {
      final r = await w.sales.completeSalesTransaction(_req(w, [w.line(q, 1, 100)], paid: 500));
      _log('BRK-04 success=${r.isSuccess} err=${r.errorMessage} safe=${await w.safeBalance()} '
          '${r.isSuccess ? await _dump(w, r.invoiceId!) : ''}');
      if (r.isSuccess) {
        expect(await w.safeBalance(), closeTo(100, kEps), reason: 'الباقي يُردّ للعميل');
        expect(await w.unbalancedEntries(), isEmpty);
      }
    });

    test('BRK-05 كسور كبيرة qty 0.3333333 × 3.3333333', skip: kSkip, () async {
      final r = await w.sales.completeSalesTransaction(
          _req(w, [w.line(q, 0.3333333, 3.3333333)], paid: 1.11));
      _log('BRK-05 success=${r.isSuccess} ${r.isSuccess ? await _dump(w, r.invoiceId!) : r.errorMessage}');
      expect(await w.unbalancedEntries(), isEmpty);
      expect(await _accountBalanceDrift(w), isEmpty);
    });

    test('BRK-06 إعادة إرسال نفس الطلب (نفس globalId) ⇒ فاتورة واحدة ومخزون يُخصم مرة',
        skip: kSkip, () async {
      const gid = '01900000-0000-7000-8000-00000000a001';
      final r1 = await w.sales.completeSalesTransaction(
          _req(w, [w.line(q, 2, 100)], paid: 200, globalId: gid));
      final r2 = await w.sales.completeSalesTransaction(
          _req(w, [w.line(q, 2, 100)], paid: 200, globalId: gid));
      final n = await w.db.customSelect('SELECT COUNT(*) n FROM sales_invoices').getSingle();
      _log('BRK-06 r1=${r1.isSuccess}/${r1.invoiceId} r2=${r2.isSuccess}/${r2.invoiceId} '
          'err2=${r2.errorMessage} invoices=${n.data['n']} stock=${await w.stock(q)} '
          'safe=${await w.safeBalance()}');
      expect(n.data['n'], 1);
      expect(await w.stock(q), closeTo(498, kEps));
      expect(r2.isSuccess, isTrue, reason: 'إعادة المحاولة يجب أن تعيد الفاتورة الأصلية لا خطأ');
      expect(r2.invoiceId, r1.invoiceId);
    });

    test('BRK-07 سباق طلبين على آخر وحدة (رصيد 1) ⇒ ينجح واحد فقط', skip: kSkip, () async {
      await w.db.setSetting('enable_negative_sales', 'false');
      final p = await w.addProduct('LAST', price: 10, cost: 5, stock: 1);
      final rs = await Future.wait([
        w.sales.completeSalesTransaction(_req(w, [w.line(p, 1, 10)], paid: 10)),
        w.sales.completeSalesTransaction(_req(w, [w.line(p, 1, 10)], paid: 10)),
      ]);
      _log('BRK-07 results=${rs.map((r) => r.isSuccess).toList()} stock=${await w.stock(p)} '
          'safe=${await w.safeBalance()}');
      expect(rs.where((r) => r.isSuccess).length, 1);
      expect(await w.stock(p), closeTo(0, kEps));
    });

    test('BRK-08 أرقام تسلسلية: 5 فواتير متزامنة ⇒ أرقام فريدة', skip: kSkip, () async {
      final rs = await Future.wait(List.generate(
          5, (_) => w.sales.completeSalesTransaction(_req(w, [w.line(q, 1, 100)], paid: 100))));
      final nums = <String>[];
      for (final r in rs) {
        nums.add((await w.db.getSalesInvoiceById(r.invoiceId!))!.invoiceNumber);
      }
      _log('BRK-08 numbers=$nums');
      expect(nums.toSet().length, 5);
    });

    test('BRK-09 مستخدم بلا أي صلاحية يبيع عبر الأوركستريتر (طبقة البيانات)', skip: kSkip,
        () async {
      final roleId = await w.db.into(w.db.roles).insert(
          RolesCompanion.insert(name: 'بلا صلاحيات', isSystemRole: const Value(false)));
      final u = await w.db.createUser(
          username: 'noperm', password: 'noperm-pw-1', displayName: 'بلا', roleId: roleId);
      await w.db.openShift(u, 0);
      final r = await w.sales.completeSalesTransaction(SaleRequest(
          items: [w.line(q, 1, 100)],
          warehouseId: w.warehouseId,
          userId: u,
          paymentMethod: 'cash',
          paidAmount: 100,
          taxEnabled: false,
          cashSafeId: w.cashSafeId));
      _log('BRK-09 success=${r.isSuccess} err=${r.errorMessage}');
      expect(r.isSuccess, isFalse, reason: 'لا فحص salesCreate في طبقة البيانات (يُفحص في UI/API فقط)');
    });

    test('BRK-10 فاتورة بتاريخ شهر سابق مقفل ⇒ رفض بلا أثر', skip: kSkip, () async {
      final now = DateTime.now();
      final prev = DateTime(now.year, now.month - 1, 15);
      final n = await (w.db.update(w.db.accountingPeriods)
            ..where((p) => p.month.equals(prev.month) & p.year.equals(prev.year)))
          .write(const AccountingPeriodsCompanion(isClosed: Value(true)));
      final r = await w.sales.completeSalesTransaction(
          _req(w, [w.line(q, 1, 100)], paid: 100, date: prev));
      _log('BRK-10 closedRows=$n success=${r.isSuccess} err=${r.errorMessage} stock=${await w.stock(q)}');
      expect(r.isSuccess, isFalse);
      expect(await w.stock(q), closeTo(500, kEps));
    });

    test('BRK-11 الشهر الحالي مقفل وفاتورة بتاريخ شهر سابق مفتوح ⇒ يجب أن تنجح', skip: kSkip,
        () async {
      final now = DateTime.now();
      final prev = DateTime(now.year, now.month - 1, 15);
      final open = await (w.db.select(w.db.accountingPeriods)
            ..where((p) => p.month.equals(prev.month) & p.year.equals(prev.year)))
          .get();
      await (w.db.update(w.db.accountingPeriods)
            ..where((p) => p.month.equals(now.month) & p.year.equals(now.year)))
          .write(const AccountingPeriodsCompanion(isClosed: Value(true)));
      final r = await w.sales.completeSalesTransaction(
          _req(w, [w.line(q, 1, 100)], paid: 100, date: prev));
      _log('BRK-11 prevPeriodRows=${open.length} success=${r.isSuccess} err=${r.errorMessage}');
      expect(r.isSuccess, isTrue,
          reason: 'adjustStock يفحص فترة DateTime.now() لا تاريخ الفاتورة');
    });
  });

  group('SAL-COST التكلفة', () {
    test('COST-01 صنف بتكلفة صفر وسياسة warn: COGS صفر (تحذير) — توثيق الأثر', skip: kSkip,
        () async {
      final z = await w.addProduct('Z0', price: 50, cost: 0, stock: 0);
      await w.db.setSetting('enable_negative_sales', 'true');
      final r = await w.sales.completeSalesTransaction(_req(w, [w.line(z, 4, 50)], paid: 200));
      _log('COST-01 success=${r.isSuccess} ${r.isSuccess ? await _dump(w, r.invoiceId!) : r.errorMessage}');
      final logs = await w.db.customSelect(
          "SELECT COUNT(*) n FROM sqlite_master WHERE name LIKE '%zero_cost%'").getSingle();
      _log('COST-01 zero_cost tables=${logs.data['n']}');
      expect(r.isSuccess, isTrue);
    });

    test('COST-02 سياسة block وصنف بتكلفة صفر ⇒ رفض قبل أي أثر (لا فاتورة يتيمة بلا قيد)',
        skip: kSkip, () async {
      final z = await w.addProduct('Z1', price: 50, cost: 0, stock: 0);
      await w.db.setSetting('enable_negative_sales', 'true');
      await w.db.setSetting('zero_cost_policy', 'block');
      final r = await w.sales.completeSalesTransaction(_req(w, [w.line(z, 4, 50)], paid: 200));
      final inv = await w.db.customSelect('SELECT COUNT(*) n FROM sales_invoices').getSingle();
      _log('COST-02 success=${r.isSuccess} err=${r.errorMessage} invoices=${inv.data['n']} '
          'stock=${await w.stock(z)} safe=${await w.safeBalance()}');
      expect(r.isSuccess, isFalse);
      expect(inv.data['n'], 0);
    });

    test('COST-03 بيع بالسالب ثم شراء بتكلفة مختلفة: COGS البيع = تكلفة الصنف لحظة البيع',
        skip: kSkip, () async {
      await w.db.setSetting('enable_negative_sales', 'true');
      final p = await w.addProduct('NEGC', price: 20, cost: 10, stock: 0);
      final r = await w.sales.completeSalesTransaction(_req(w, [w.line(p, 5, 20)], paid: 100));
      expect(r.isSuccess, isTrue, reason: r.errorMessage);
      _log('COST-03 ${await _dump(w, r.invoiceId!)}');
      expect((await _je(w, r.invoiceId!))['5211'], closeTo(50, kEps));
    });
  });

  test('SAL-ACC-01 accounts.balance = Σ قيود لكل الحسابات بعد مزيج عمليات', skip: kSkip,
      () async {
    final c = await w.addCustomer('ع');
    await w.sell([w.line(q, 2, 100)]);
    await w.sell([w.line(q, 1, 100)], customerId: c, method: 'credit', paid: 0);
    final r = await w.sell([w.line(q, 3, 100)]);
    await w.returnItems(r.invoiceId!, q, 1);
    final drift = await _accountBalanceDrift(w);
    _log('ACC-01 drift=$drift');
    expect(drift, isEmpty);
  });
}
