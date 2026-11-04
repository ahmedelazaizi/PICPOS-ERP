// تدقيق إغلاق الوردية — مصفوفة سيناريوهات استنساخ (2026-10-31).
//
// السياق: شكوى المالك «إقفال الوردية يكرر قيمة المرتجع على أنها خصم».
// كل اختبار هنا يقارن أربعة مصادر لنفس الوردية:
//   ملخص الإغلاق (getShiftClosingAggregates — ما ترسمه الشاشة)
//   ⟷ safe_transactions (صافي حركة الأدراج النقدية)
//   ⟷ قيود اليومية (صافي حساب النقدية 111x + توازن كل قيد)
//   ⟷ رصيد الخزنة / المتوقع المخزَّن في shifts.expected_cash عند الإقفال.
//
// الاختبارات تؤكد **السلوك المحاسبي الصحيح**؛ فما يفشل منها هو استنساخ عيب.
// كلها موسومة skip حتى يوافق المالك، وتُشغَّل بـ:
//   flutter test test/audit_repro/shift_close --run-skipped
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/data/repositories/exchange_repository_impl.dart';
import 'package:picpos_erp/data/repositories/returns_repository_impl.dart';
import 'package:picpos_erp/domain/entities/cart_item_entity.dart';
import 'package:picpos_erp/domain/entities/product_entity.dart';
import 'package:picpos_erp/domain/repositories/sales_repository.dart'
    show SaleSuccess;

import '../../scenarios/scenario_world.dart';

const kSkip = 'audit repro — pending owner approval';

/// لقطة واحدة لوردية مفتوحة من المصادر الأربعة.
class _Snap {
  _Snap(this.agg, this.drawerNet, this.cashSafes, this.glCash);
  final ShiftClosingAggregates agg;
  final double drawerNet; // Σ(receipt) − Σ(payment|withdrawal) على الأدراج النقدية منذ بدء الوردية
  final double cashSafes; // Σ safes.balance للخزائن النقدية
  final double glCash; // صافي 111x في الأستاذ

  int get invoiceBadge => agg.salesCount + agg.returnsCount; // «إجمالي فواتير»

  @override
  String toString() => 'sales(${agg.salesCount}) cash=${agg.salesCash} '
      'bank=${agg.salesBank} click=${agg.salesClick} credit=${agg.salesCredit} | '
      'returns(${agg.returnsCount}) cash=${agg.returnsCash} bank=${agg.returnsBank} '
      'click=${agg.returnsClick} credit=${agg.returnsCredit} | '
      'receipts(${agg.receiptCount}) cash=${agg.receiptCash} | '
      'expenses(${agg.expensesCount}) cash=${agg.expensesCash} | '
      'payments(${agg.paymentCount}) cash=${agg.paymentCash} | '
      'income=${agg.openingBalance + agg.totalIncomeCash} '
      'outflow=${agg.totalOutflowCash} expected=${agg.systemCash} '
      'bankExp=${agg.systemBank} clickExp=${agg.systemClick} | '
      'badge=$invoiceBadge | drawerNet=$drawerNet safes=$cashSafes gl111=$glCash';
}

Future<_Snap> _snap(ScenarioWorld w, {int? userId, String? tag}) async {
  final uid = userId ?? w.userId;
  final shift = (await w.db.getCurrentOpenShift(uid))!;
  final agg = await w.db.getShiftClosingAggregates(
    userId: uid,
    includeAllUsers: false,
    shiftStart: shift.startTime,
    openingBalance: shift.openingBalance,
    branchId: shift.branchId,
  );
  final r = await w.db.customSelect(
    "SELECT COALESCE(SUM(CASE WHEN t.transaction_type = 'receipt' THEN t.amount "
    "WHEN t.transaction_type IN ('payment','withdrawal') THEN -t.amount ELSE 0 END),0) n "
    'FROM safe_transactions t JOIN safes s ON s.id = t.safe_id '
    "WHERE s.safe_type = 'cash' AND t.created_at >= ? "
    "AND t.category <> 'shift_variance' AND COALESCE(t.reference_type,'') <> 'shift_closing'",
    variables: [Variable<DateTime>(shift.startTime)],
  ).getSingle();
  final safesRow = await w.db
      .customSelect("SELECT COALESCE(SUM(balance),0) s FROM safes WHERE safe_type = 'cash'")
      .getSingle();
  final s = _Snap(
    agg,
    (r.data['n'] as num).toDouble(),
    (safesRow.data['s'] as num).toDouble(),
    await w.accountNet('111'),
  );
  // ignore: avoid_print
  print('[AUDIT ${tag ?? ''}] $s');
  return s;
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

Future<SaleSuccess> _sale(ScenarioWorld w, SaleRequest r) async {
  final res = await w.sales.completeSalesTransaction(r);
  expect(res.isSuccess, isTrue, reason: res.errorMessage);
  return res as SaleSuccess;
}

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
        int? clickSafeId}) =>
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
    );

/// مرتجع بلا فاتورة بنفس مسار «المرتجع السريع» (createSalesInvoice saleType=return).
Future<int> _noInvoiceReturn(ScenarioWorld w, int productId, double qty, double price,
    {String method = 'cash'}) {
  final total = qty * price;
  return w.sales.createSalesInvoice(
    customerId: null,
    warehouseId: w.warehouseId,
    userId: w.userId,
    subtotal: total,
    discount: 0,
    tax: 0,
    total: total,
    paid: total,
    paymentMethod: method,
    saleType: 'return',
    cashSafeId: w.cashSafeId,
    items: [
      CartItemEntity(
          productId: productId,
          productName: 'p$productId',
          productCode: 'c$productId',
          quantity: qty,
          unitPrice: price),
    ],
  );
}

Future<Shift> _shiftRow(ScenarioWorld w, int id) =>
    (w.db.select(w.db.shifts)..where((s) => s.id.equals(id))).getSingle();

Future<ProductEntity> _entity(ScenarioWorld w, int id) async {
  final p = (await w.db.getProductById(id))!;
  return ProductEntity(
      id: p.id,
      name: p.name,
      code: p.code,
      salePrice: p.salePrice,
      costPrice: p.costPrice,
      currentStock: p.currentStock,
      minStock: p.minStock,
      trackInventory: p.trackInventory);
}

/// ينتظر حتى يتغيّر الثانية — التواريخ تُخزَّن في SQLite بدقة الثانية.
Future<void> _nextSecond() => Future<void>.delayed(const Duration(milliseconds: 1100));

void main() {
  late ScenarioWorld w;
  late int p; // 6.99
  late int q; // 100
  late int r; // 150

  setUp(() async {
    w = await ScenarioWorld.create();
    p = await w.addProduct('P699', price: 6.99, cost: 4, stock: 500);
    q = await w.addProduct('Q100', price: 100, cost: 60, stock: 500);
    r = await w.addProduct('R150', price: 150, cost: 90, stock: 500);
  });
  tearDown(() => w.dispose());

  group('AUD-S01 بيانات المالك الحرفية', () {
    test('SINV-1 34.95 + SRET-1 بلا فاتورة 48.93 + SINV-2 90.87 ⇒ المرتجع يُطرح مرة واحدة',
        skip: kSkip, () async {
      final s1 = await w.sell([w.line(p, 5, 6.99)]);
      final ret = await _noInvoiceReturn(w, p, 7, 6.99);
      await w.sell([w.line(p, 13, 6.99)]);
      final s = await _snap(w, tag: 'S01');
      // ignore: avoid_print
      final refs = await w.db
          .customSelect('SELECT reference_type rt, reference_id rid, description d FROM journal_entries')
          .get();
      // ignore: avoid_print
      print('[AUDIT S01] JE refs=${refs.map((e) => e.data).toList()}');
      final retItem = (await w.db.getSalesInvoiceItems(ret)).single;
      // ignore: avoid_print
      print('[AUDIT S01] SRET item costPrice=${retItem.costPrice} qty=${retItem.quantity}');
      // ignore: avoid_print
      print('[AUDIT S01] JE sale SINV-1=${await w.linesOf('sales_invoice', s1.invoiceId!)}');
      // ignore: avoid_print
      print('[AUDIT S01] JE return SRET-1=${await w.linesOf('sales_return', ret)}');

      expect(s.agg.salesCount, 2, reason: '«مبيعات (2)»');
      expect(s.agg.returnsCount, 1, reason: '«مرتجعات مبيعات (1)»');
      expect(s.agg.salesCash, closeTo(125.82, kEps));
      expect(s.agg.returnsCash, closeTo(48.93, kEps));
      expect(s.agg.totalOutflowCash, closeTo(48.93, kEps),
          reason: '«إجمالي الخصم» = مرتجعات + مصروفات + سندات صرف — لا يضيف المرتجع مرتين');
      expect(s.agg.systemCash, closeTo(76.89, kEps));
      expect(s.invoiceBadge, 3, reason: 'الشارة تعدّ المرتجع فاتورةً');
      expect(s.drawerNet, closeTo(76.89, kEps));
      expect(s.cashSafes, closeTo(76.89, kEps));
      expect(s.glCash, closeTo(76.89, kEps));
      expect(await w.unbalancedEntries(), isEmpty);
    });

    test('إقفال بالفعلي المطابق 76.89 ⇒ فرق صفر ولا قيد فرق', skip: kSkip, () async {
      final shiftId = (await w.db.getCurrentOpenShift(w.userId))!.id;
      await w.sell([w.line(p, 5, 6.99)]);
      await _noInvoiceReturn(w, p, 7, 6.99);
      await w.sell([w.line(p, 13, 6.99)]);
      await w.db.closeShiftWithAudit(shiftId, 76.89);
      final sh = await _shiftRow(w, shiftId);
      expect(sh.expectedCash, closeTo(76.89, kEps));
      expect(sh.variance, closeTo(0, kEps));
      expect(await w.linesOf('shift_close', shiftId), isEmpty);
    });

    test('AUD-F03: رصيد حساب الدرج في الأستاذ = رصيد خزنة الدرج (قبل الإقفال وبعده)',
        skip: kSkip, () async {
      final shiftId = (await w.db.getCurrentOpenShift(w.userId))!.id;
      await w.sell([w.line(p, 5, 6.99)]);
      await _noInvoiceReturn(w, p, 7, 6.99);
      await w.sell([w.line(p, 13, 6.99)]);
      final drawer = (await w.db.getSafeById(w.cashSafeId))!;
      final drawerAcc = (await w.db.resolveSafeGlAccount(drawer))!;
      final central = (await w.db.getCentralSafe())!;
      final centralAcc = await w.db.resolveSafeGlAccount(central);
      Future<double> net(int accountId) async {
        final r = await w.db.customSelect(
            'SELECT COALESCE(SUM(l.debit - l.credit),0) n FROM journal_entry_lines l '
            'JOIN journal_entries e ON e.id = l.entry_id '
            'WHERE e.is_deleted = 0 AND l.account_id = ?',
            variables: [Variable<int>(accountId)]).getSingle();
        return (r.data['n'] as num).toDouble();
      }

      Future<String> perAccount() async {
        final rows = await w.db.customSelect(
            "SELECT a.code c, ROUND(SUM(l.debit - l.credit),3) n FROM journal_entry_lines l "
            'JOIN journal_entries e ON e.id = l.entry_id JOIN accounts a ON a.id = l.account_id '
            "WHERE e.is_deleted = 0 AND a.code LIKE '111%' GROUP BY a.code").get();
        return rows.map((e) => '${e.data['c']}=${e.data['n']}').join(' ');
      }

      // ignore: avoid_print
      print('[AUDIT F03] before close: drawerAcc=${drawerAcc.code} '
          'drawerSafe=${(await w.db.getSafeById(drawer.id))!.balance} | ${await perAccount()}');
      final before = await net(drawerAcc.id);
      await w.db.closeShiftWithAudit(shiftId, 76.89);
      // ignore: avoid_print
      print('[AUDIT F03] after close: drawerSafe=${(await w.db.getSafeById(drawer.id))!.balance} '
          'central=${(await w.db.getCentralSafe())!.balance} centralAcc=${centralAcc?.code} | '
          '${await perAccount()}');
      expect(before, closeTo(76.89, kEps),
          reason: 'قيد البيع يمدين حساب الدرج وقيد المرتجع السريع يدائن حساب النقدية العام');
      expect(await net(drawerAcc.id),
          closeTo((await w.db.getSafeById(drawer.id))!.balance, kEps));
    });

    test('AUD-F02: إقفال والحقل فارغ (0) ⇒ عجز 76.89 مرحَّل على 6217 — حقيقي لا وهمي',
        skip: kSkip, () async {
      final shiftId = (await w.db.getCurrentOpenShift(w.userId))!.id;
      await w.sell([w.line(p, 5, 6.99)]);
      await _noInvoiceReturn(w, p, 7, 6.99);
      await w.sell([w.line(p, 13, 6.99)]);
      final v = w.container
          .read(accountingServiceProvider)
          .validateShiftClose(expectedCash: 76.89, actualCash: 0);
      // ignore: avoid_print
      print('[AUDIT F02] validateShiftClose severity=${v.severity} variance=${v.variance}');
      expect(v.severity, 'CRITICAL',
          reason: 'المتحكّم يعيد false هنا والحوار لا يقرأ القيمة (انظر التقرير AUD-F01)');
      await w.db.closeShiftWithAudit(shiftId, 0);
      final sh = await _shiftRow(w, shiftId);
      expect(sh.variance, closeTo(-76.89, kEps));
      final je = await w.linesOf('shift_close', shiftId);
      // ignore: avoid_print
      print('[AUDIT F02] variance JE lines=$je glCash=${await w.accountNet('111')}');
      expect(je.where((l) => (l['debit'] as num) > 0).single['code'], '6217');
      expect(await w.accountNet('111'), closeTo(0, kEps));
    });
  });

  group('AUD-S02 قنوات الدفع', () {
    test('نقد/بطاقة/كليك/آجل/جزئي/مختلط: كل قناة في عمودها والمتوقع = حركة الخزائن',
        skip: kSkip, () async {
      final bankId = await _ensureSafe(w, 'bank');
      final clickId = await _ensureSafe(w, 'click');
      final c = await w.addCustomer('عميل آجل');
      await _sale(w, _req(w, [w.line(q, 1, 100)], paid: 100)); // نقد 100
      await _sale(w, _req(w, [w.line(q, 1, 100)], method: 'card', paid: 100, bankSafeId: bankId));
      await _sale(w, _req(w, [w.line(q, 1, 100)], method: 'click', paid: 100, clickSafeId: clickId));
      await _sale(w, _req(w, [w.line(q, 1, 100)], method: 'credit', paid: 0, customerId: c));
      await _sale(w, _req(w, [w.line(q, 1, 100)], method: 'credit', paid: 30, customerId: c));
      await _sale(w, _req(w, [w.line(q, 1, 100)],
          method: 'mixed', paid: 100, cash: 60, bank: 40, bankSafeId: bankId));
      final s = await _snap(w, tag: 'S02');
      final bankBal = (await w.db.getSafeById(bankId))!.balance;
      final clickBal = (await w.db.getSafeById(clickId))!.balance;
      // ignore: avoid_print
      print('[AUDIT S02] bankSafe=$bankBal clickSafe=$clickBal');
      expect(s.agg.salesCount, 6);
      expect(s.agg.salesCash, closeTo(100 + 30 + 60, kEps));
      expect(s.agg.salesBank, closeTo(100 + 40, kEps));
      expect(s.agg.salesClick, closeTo(100, kEps));
      expect(s.agg.salesCredit, closeTo(100 + 70, kEps));
      expect(s.agg.systemCash, closeTo(s.drawerNet, kEps));
      expect(s.agg.systemBank, closeTo(bankBal, kEps));
      expect(s.agg.systemClick, closeTo(clickBal, kEps));
      expect(await w.unbalancedEntries(), isEmpty);
    });

    test('AUD-F05: بيع آجل ثم تحصيله في نفس الوردية ⇒ النقد يُحتسب مرة واحدة',
        skip: kSkip, () async {
      final c = await w.addCustomer('عميل');
      final sale = await _sale(
          w, _req(w, [w.line(q, 1, 100)], method: 'credit', paid: 0, customerId: c));
      await w.db.addSalesPayment(
          invoiceId: sale.invoiceId, amount: 100, safeId: w.cashSafeId, userId: w.userId);
      final s = await _snap(w, tag: 'F05');
      expect(s.drawerNet, closeTo(100, kEps));
      expect(s.agg.systemCash, closeTo(100, kEps),
          reason: 'salesCash يقرأ paid المحدَّث + سند القبض نفسه ⇒ ازدواج إن ظهر 200');
    });
  });

  group('AUD-S03 الخصومات والضريبة', () {
    test('خصم سطر/خصم فاتورة نسبة/قيمة وضريبة شاملة/غير شاملة: الملخص يقرأ paid الصافي',
        skip: kSkip, () async {
      final cases = <String, SaleRequest>{
        'خصم سطر 10%': _req(w, [
          CartItemEntity(
              productId: q,
              productName: 'q',
              productCode: 'q',
              quantity: 1,
              unitPrice: 100,
              discountPercent: 10)
        ], paid: 90),
        'خصم فاتورة 10%': _req(w, [w.line(q, 1, 100)], paid: 90, discountPercent: 10),
        'خصم فاتورة 5 قيمة': _req(w, [w.line(q, 1, 100)], paid: 95, invoiceDiscountAmount: 5),
        'ضريبة 14% غير شاملة': _req(w, [w.line(q, 1, 100)], paid: 114, tax: true),
        'ضريبة 14% شاملة': _req(w, [w.line(q, 1, 114)], paid: 114, tax: true, inclusive: true),
      };
      var expected = 0.0;
      for (final e in cases.entries) {
        final res = await _sale(w, e.value);
        final inv = (await w.db.getSalesInvoiceById(res.invoiceId))!;
        final lines = await w.linesOf('sale', inv.id);
        // ignore: avoid_print
        print('[AUDIT S03] ${e.key}: subtotal=${inv.subtotal} discount=${inv.discount} '
            'tax=${inv.tax} total=${inv.total} paid=${inv.paid} je=$lines');
        expected += inv.paid;
      }
      final s = await _snap(w, tag: 'S03');
      expect(s.agg.salesCash, closeTo(expected, kEps));
      expect(s.agg.totalOutflowCash, closeTo(0, kEps),
          reason: 'خصم البيع لا يظهر في «إجمالي الخصم» — هذا الصف ليس خصماً تجارياً');
      expect(s.agg.systemCash, closeTo(s.drawerNet, kEps));
      expect(await w.unbalancedEntries(), isEmpty);
    });
  });

  group('AUD-S04 المرتجعات', () {
    test('مرتجع جزئي ثم كامل من فاتورة نفس الوردية (شاشة المرتجعات)', skip: kSkip, () async {
      final sale = await w.sell([w.line(q, 3, 100)]);
      expect(await w.returnItems(sale.invoiceId!, q, 1), isTrue);
      expect(await w.returnItems(sale.invoiceId!, q, 2), isTrue);
      final s = await _snap(w, tag: 'S04a');
      expect(s.agg.salesCash, closeTo(300, kEps));
      expect(s.agg.returnsCash, closeTo(300, kEps));
      expect(s.agg.returnsCount, 2);
      expect(s.agg.systemCash, closeTo(0, kEps));
      expect(s.drawerNet, closeTo(0, kEps));
      expect(s.glCash, closeTo(0, kEps));
    });

    test('مرتجع لفاتورة وردية سابقة يُطرح من الوردية الحالية فقط', skip: kSkip, () async {
      final sh1 = (await w.db.getCurrentOpenShift(w.userId))!.id;
      final sale = await w.sell([w.line(q, 2, 100)]);
      await w.db.closeShiftWithAudit(sh1, 200);
      await _nextSecond();
      await w.db.openShift(w.userId, 0);
      expect(await w.returnItems(sale.invoiceId!, q, 1), isTrue);
      final s = await _snap(w, tag: 'S04b');
      expect(s.agg.salesCount, 0);
      expect(s.agg.returnsCash, closeTo(100, kEps));
      expect(s.agg.systemCash, closeTo(-100, kEps));
      expect(s.drawerNet, closeTo(-100, kEps));
    });

    test('مرتجع فاتورة بطاقة ⇒ عمود البنك لا النقد (لا خيار ردٍّ نقدي لفاتورة بطاقة)',
        skip: kSkip, () async {
      final bankId = await _ensureSafe(w, 'bank');
      final sale =
          await _sale(w, _req(w, [w.line(q, 1, 100)], method: 'card', paid: 100, bankSafeId: bankId));
      expect(await w.returnItems(sale.invoiceId, q, 1), isTrue);
      final s = await _snap(w, tag: 'S04c');
      expect(s.agg.returnsBank, closeTo(100, kEps));
      expect(s.agg.returnsCash, closeTo(0, kEps));
      expect(s.agg.systemBank, closeTo(0, kEps));
    });

    test('مرتجع فاتورة آجلة ⇒ يقاصّ الذمة في عمود الآجل ولا يمس النقد', skip: kSkip, () async {
      final c = await w.addCustomer('عميل');
      final sale = await _sale(
          w, _req(w, [w.line(q, 1, 100)], method: 'credit', paid: 0, customerId: c));
      expect(await w.returnItems(sale.invoiceId, q, 1), isTrue);
      final s = await _snap(w, tag: 'S04d');
      expect(s.agg.returnsCredit, closeTo(100, kEps));
      expect(s.agg.returnsCash, closeTo(0, kEps));
      expect(s.agg.systemCreditNet, closeTo(0, kEps));
      expect(s.agg.systemCash, closeTo(0, kEps));
    });

    test('AUD-F09: مرتجع واحد لفاتورة مختلطة ⇒ «مرتجعات (1)» لا (2)', skip: kSkip, () async {
      final bankId = await _ensureSafe(w, 'bank');
      final sale = await _sale(w, _req(w, [w.line(q, 1, 100)],
          method: 'mixed', paid: 100, cash: 60, bank: 40, bankSafeId: bankId));
      expect(await w.returnItems(sale.invoiceId, q, 1), isTrue);
      final s = await _snap(w, tag: 'F09');
      expect(s.agg.returnsCash + s.agg.returnsBank, closeTo(100, kEps));
      expect(s.agg.returnsCount, 1, reason: 'مستند مرتجع واحد يُعدّ بعدد صفوف الخزنة');
    });

    test('استبدال: المرتجع يُطرح مرة والبديل يُضاف مرة والصافي = حركة الدرج', skip: kSkip,
        () async {
      final sale = await w.sell([w.line(q, 1, 100)]);
      final inv = (await w.db.getSalesInvoiceById(sale.invoiceId!))!;
      final item = (await w.db.getSalesInvoiceItems(inv.id)).single;
      final repo = ExchangeRepositoryImpl(
        w.db,
        w.container.read(returnsRepositoryProvider) as ReturnsRepositoryImpl,
        w.sales,
      );
      final res = await repo.processExchange(
        originalInvoice: inv,
        returnQuantities: {item.id: 1},
        returnProductCache: {q: await _entity(w, q)},
        replacementItems: [w.line(r, 1, 150)],
        warehouseId: w.warehouseId,
        userId: w.userId,
        userName: 'مستخدم السيناريو',
        taxEnabled: false,
      );
      // ignore: avoid_print
      print('[AUDIT S04e] exchange refunded=${res.cashRefunded} collected=${res.cashCollected}');
      final s = await _snap(w, tag: 'S04e');
      expect(s.agg.salesCash, closeTo(250, kEps));
      expect(s.agg.returnsCash, closeTo(100, kEps));
      expect(s.agg.systemCash, closeTo(150, kEps));
      expect(s.drawerNet, closeTo(150, kEps));
    });
  });

  group('AUD-S05 سندات ومصروفات ورصيد افتتاحي', () {
    test('مصروف + سند قبض + سند صرف + رصيد افتتاحي 50', skip: kSkip, () async {
      final sh = (await w.db.getCurrentOpenShift(w.userId))!;
      await w.db.closeShiftWithAudit(sh.id, 0);
      await _nextSecond();
      await w.db.openShift(w.userId, 50);
      final c = await w.addCustomer('عميل');
      final sup = await w.addSupplier('مورد');
      await w.sell([w.line(q, 2, 100)]);
      await w.db.createPaymentVoucher(
          amount: 20, category: 'expense', description: 'ضيافة', safeId: w.cashSafeId, userId: w.userId);
      await w.db.createReceiptVoucher(
          amount: 30, category: 'customer_payment', partyId: c, safeId: w.cashSafeId, userId: w.userId);
      await w.db.createPaymentVoucher(
          amount: 40, category: 'supplier_payment', partyId: sup, safeId: w.cashSafeId, userId: w.userId);
      final s = await _snap(w, tag: 'S05');
      expect(s.agg.expensesCash, closeTo(20, kEps));
      expect(s.agg.receiptCash, closeTo(30, kEps));
      expect(s.agg.paymentCash, closeTo(40, kEps));
      expect(s.agg.totalOutflowCash, closeTo(60, kEps));
      expect(s.agg.systemCash, closeTo(50 + 200 + 30 - 20 - 40, kEps));
      expect(s.agg.systemCash - 50, closeTo(s.drawerNet, kEps),
          reason: 'الرصيد الافتتاحي رقمٌ مُعلَن بلا حركة خزنة');
      // ignore: avoid_print
      print('[AUDIT S05] opening 50 in safe? safes=${s.cashSafes} gl=${s.glCash}');
    });

    test('AUD-F08: صرف رواتب من HR بفئة salaries يُصنَّف «مصروفات» لا «سندات صرف»',
        skip: kSkip, () async {
      await w.db.createPaymentVoucher(
          amount: 25, category: 'salaries', safeId: w.cashSafeId, userId: w.userId);
      final s = await _snap(w, tag: 'F08');
      expect(s.agg.expensesCash, closeTo(25, kEps));
    });
  });

  group('AUD-S06 تعدد المستخدمين والورديات', () {
    test('AUD-F06: بيعة مستخدم آخر على درج الكاشير ⇒ الشاشة والمتوقع المخزَّن يتفقان',
        skip: kSkip, () async {
      final sh = (await w.db.getCurrentOpenShift(w.userId))!;
      await w.sell([w.line(q, 1, 100)]);
      // المدير (المستخدم 1) يبيع بلا وردية على نفس الدرج (مسار DAO مباشر).
      await w.db.createSalesInvoice(
        warehouseId: w.warehouseId,
        userId: 1,
        subtotal: 50,
        discount: 0,
        tax: 0,
        total: 50,
        paid: 50,
        paymentMethod: 'cash',
        cashSafeId: w.cashSafeId,
        items: [
          SalesInvoiceItemsCompanion.insert(
              invoiceId: 0, productId: r, quantity: 1, unitPrice: 50, total: 50)
        ],
      );
      final s = await _snap(w, tag: 'F06');
      await w.db.closeShiftWithAudit(sh.id, 150); // الكاشير يعدّ الدرج كله
      final row = await _shiftRow(w, sh.id);
      // ignore: avoid_print
      print('[AUDIT F06] screen expected=${s.agg.systemCash} stored expected=${row.expectedCash} '
          'stored variance=${row.variance} screenVariance=${150 - s.agg.systemCash}');
      expect(s.agg.systemCash, closeTo(row.expectedCash!, kEps),
          reason: 'الشاشة تقول زيادة +50 والمخزَّن/المرحَّل صفر');
    });

    test('ورديتان متعاقبتان بفاصل ثانية: لا تسرّب', skip: kSkip, () async {
      final sh1 = (await w.db.getCurrentOpenShift(w.userId))!.id;
      await w.sell([w.line(q, 1, 100)]);
      await w.db.closeShiftWithAudit(sh1, 100);
      await _nextSecond();
      await w.db.openShift(w.userId, 0);
      await w.sell([w.line(r, 1, 150)]);
      final s = await _snap(w, tag: 'S06b');
      expect(s.agg.salesCash, closeTo(150, kEps));
      expect(s.agg.receiptCash, closeTo(0, kEps));
      expect(s.agg.systemCash, closeTo(150, kEps));
    });

    test('AUD-F07: إقفال ثم فتح في نفس الثانية (تحويل مستخدم) ⇒ لا تسرّب من الوردية السابقة',
        skip: kSkip, () async {
      final sh1 = (await w.db.getCurrentOpenShift(w.userId))!.id;
      await w.sell([w.line(q, 1, 100)]);
      await w.db.closeShiftWithAudit(sh1, 100);
      final sh2 = await w.db.openShift(w.userId, 0); // بلا انتظار
      final s = await _snap(w, tag: 'F07');
      final row1 = await _shiftRow(w, sh1);
      final row2 = await _shiftRow(w, sh2);
      // ignore: avoid_print
      print('[AUDIT F07] sh1.end=${row1.endTime} sh2.start=${row2.startTime}');
      expect(s.agg.salesCash, closeTo(0, kEps));
      expect(s.agg.receiptCash, closeTo(0, kEps));
      expect(s.agg.systemCash, closeTo(0, kEps));
    });
  });

  group('AUD-S07 إلغاء الفاتورة', () {
    test('إلغاء في نفس الوردية ⇒ الشاشة 0 والمخزَّن 0 والدرج 0', skip: kSkip, () async {
      final sh = (await w.db.getCurrentOpenShift(w.userId))!;
      final sale = await w.sell([w.line(q, 1, 100)]);
      await w.db.voidSalesInvoice(sale.invoiceId!, reason: 'تدقيق', deletedBy: w.userId);
      final s = await _snap(w, tag: 'S07a');
      expect(s.agg.systemCash, closeTo(0, kEps));
      expect(s.drawerNet, closeTo(0, kEps));
      await w.db.closeShiftWithAudit(sh.id, 0);
      final row = await _shiftRow(w, sh.id);
      final central = (await w.db.getCentralSafe())!.balance;
      // ignore: avoid_print
      print('[AUDIT S07a] stored expected=${row.expectedCash} variance=${row.variance} '
          'drawer=${await w.safeBalance()} central=$central gl111=${await w.accountNet('111')}');
      expect(row.variance, closeTo(0, kEps));
      expect(await w.safeBalance() + central, closeTo(0, kEps));
    });

    test('AUD-F04: إلغاء فاتورة وردية مقفلة أثناء الوردية التالية ⇒ الشاشة = المتوقع المخزَّن',
        skip: kSkip, () async {
      final sh1 = (await w.db.getCurrentOpenShift(w.userId))!.id;
      final sale = await w.sell([w.line(q, 1, 100)]);
      await w.db.closeShiftWithAudit(sh1, 100);
      await _nextSecond();
      final sh2 = await w.db.openShift(w.userId, 0);
      await w.db.voidSalesInvoice(sale.invoiceId!, reason: 'تدقيق', deletedBy: w.userId);
      final s = await _snap(w, tag: 'F04');
      final voidRow = await (w.db.select(w.db.safeTransactions)
            ..where((t) => t.referenceType.equals('sales_invoice_void')))
          .getSingle();
      // الدرج أُفرغ إلى المركزي عند إقفال الوردية السابقة، فالكاشير يعدّ 0.
      await w.db.closeShiftWithAudit(sh2, 0);
      final row = await _shiftRow(w, sh2);
      // ignore: avoid_print
      print('[AUDIT F04] void row userId=${voidRow.userId} type=${voidRow.transactionType} '
          'screen expected=${s.agg.systemCash} stored expected=${row.expectedCash} '
          'stored variance=${row.variance} drawer=${await w.safeBalance()}');
      expect(s.agg.systemCash, closeTo(row.expectedCash!, kEps));
    });
  });
}
