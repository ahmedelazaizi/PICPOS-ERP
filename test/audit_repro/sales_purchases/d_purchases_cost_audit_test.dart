// تدقيق المشتريات والتكلفة (WAC · تكلفة هبوط · مرتجع مشتريات · تعديل · إلغاء) — 2026-10-31.
// الاختبارات تؤكد **السلوك المحاسبي الصحيح**؛ فما يفشل منها استنساخ عيب.
//   flutter test test/audit_repro/sales_purchases --run-skipped
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/repositories/purchases_repository.dart';
import 'package:picpos_erp/services/stock_shortage_policy_service.dart';

import '../../scenarios/scenario_world.dart';

const kSkip = 'audit repro — pending owner approval';

void _log(String m) {
  // ignore: avoid_print
  print('[AUDIT-PUR] $m');
}

void main() {
  late ScenarioWorld w;
  late int sup;
  late int p;

  PurchasesRepository repo() => w.container.read(purchasesRepositoryProvider);

  Future<int> buy(double qty, double cost,
          {double paid = 0,
          double lineDiscount = 0,
          double invoiceDiscount = 0,
          double taxRate = 0,
          int? product,
          int? supplier,
          String? supplierInvoiceNumber}) =>
      repo().createInvoice(CreatePurchaseInvoiceParams(
        supplierId: supplier ?? sup,
        warehouseId: w.warehouseId,
        paid: paid,
        paymentMethod: paid > 0 ? 'cash' : 'credit',
        safeId: paid > 0 ? w.cashSafeId : null,
        userId: w.userId,
        discount: invoiceDiscount,
        supplierInvoiceNumber: supplierInvoiceNumber,
        items: [
          PurchaseItemParams(
              productId: product ?? p,
              quantity: qty,
              unitCost: cost,
              salePrice: 100,
              taxRate: taxRate,
              taxAmount: (qty * cost - lineDiscount) * taxRate / 100,
              discount: lineDiscount)
        ],
      ));

  Future<Object> pret(int invoiceId, double qty) async {
    try {
      final invoice = (await repo().getRawInvoiceById(invoiceId))!;
      final it = (await repo().getInvoiceItemsWithProduct(invoiceId)).single;
      return await repo().processPurchaseReturn(
        invoice: invoice,
        reason: 'تدقيق',
        returnItems: [
          PurchaseReturnItem(
              itemId: it.item.id,
              productId: it.item.productId,
              returnQuantity: qty,
              unitCost: it.item.unitCost,
              taxAmount: it.item.taxAmount * qty / it.item.quantity,
              originalQuantity: it.item.quantity,
              quantityInBase: it.item.quantityInBase)
        ],
      );
    } catch (e) {
      return 'EXC: $e';
    }
  }

  Future<String> state([int? product]) async {
    final pr = (await w.db.getProductById(product ?? p))!;
    final bal = await w.db.customSelect(
        'SELECT quantity q, average_cost c FROM inventory_balances WHERE product_id = ?',
        variables: [Variable<int>(product ?? p)]).get();
    return 'stock=${pr.currentStock} wac=${pr.costPrice} value=${pr.currentStock * pr.costPrice} '
        'whBal=${bal.map((e) => e.data).toList()} gl1136=${await w.accountNet('1136')} '
        'gl2111=${await w.accountNet('211')} gl5211=${await w.accountNet('5211')} '
        'supplier=${await w.partyBalance(sup)} safe=${await w.safeBalance()}';
  }

  setUp(() async {
    StockShortagePolicyService.resetCacheForTest();
    w = await ScenarioWorld.create();
    await w.grant(PermissionCodes.treasuryPaymentsCreate);
    sup = await w.addSupplier('مورد');
    p = await w.addProduct('P', price: 100, cost: 0);
  });
  tearDown(() async {
    StockShortagePolicyService.resetCacheForTest();
    await w.dispose();
  });

  test('PUR-01 شراء نقدي 10×50: 1136 مدين 500، المورد صفر، الخزنة −500', skip: kSkip, () async {
    await w.db.adjustSafeBalance(w.cashSafeId, 1000); // تمويل (خزنة فقط — لتجاوز حارس الرصيد)
    Object res = true;
    int? id;
    try {
      id = await buy(10, 50, paid: 500);
    } catch (e) {
      res = 'EXC: $e';
    }
    _log('PUR-01 res=$res JE=${id == null ? '-' : await w.linesOf('purchase_invoice', id)} ${await state()}');
    expect(res, isTrue);
    expect(await w.partyBalance(sup), closeTo(0, kEps));
    expect(await w.accountNet('1136'), closeTo(500, kEps));
  });

  test('PUR-02 آجل بخصم سطر 100 وضريبة 14% (10×100): مخزون 900، ضريبة مدخلات 126، مورد 1026',
      skip: kSkip, () async {
    final id = await buy(10, 100, lineDiscount: 100, taxRate: 14);
    final inv = (await repo().getRawInvoiceById(id))!;
    _log('PUR-02 hdr sub=${inv.subtotal} disc=${inv.discount} tax=${inv.tax} total=${inv.total} '
        'JE=${await w.linesOf('purchase_invoice', id)} ${await state()}');
    expect(await w.accountNet('1136'), closeTo(900, kEps));
    expect(await w.partyBalance(sup), closeTo(1026, kEps));
    expect((await w.db.getProductById(p))!.costPrice, closeTo(90, kEps));
  });

  test('PUR-03 خصم فاتورة 50 على 10×100: تكلفة الوحدة 95', skip: kSkip, () async {
    final id = await buy(10, 100, invoiceDiscount: 50);
    _log('PUR-03 JE=${await w.linesOf('purchase_invoice', id)} ${await state()}');
    expect((await w.db.getProductById(p))!.costPrice, closeTo(95, kEps));
    expect(await w.partyBalance(sup), closeTo(950, kEps));
  });

  test('PUR-04 بيع بالسالب ثم شراء: −5@10 ثم شراء 10@12 ⇒ WAC=12 و1136 = 5×12 = 60',
      skip: kSkip, () async {
    await buy(1, 10); // تكلفة مرجعية 10 (رصيد 1)
    await w.db.setSetting('enable_negative_sales', 'true');
    await w.sell([w.line(p, 6, 100)]); // رصيد −5 بتكلفة 10
    _log('PUR-04 before purchase: ${await state()}');
    final id = await buy(10, 12);
    final adj = await w.db.customSelect(
        "SELECT reference_type rt FROM journal_entries WHERE reference_type LIKE '%negative%'").get();
    _log('PUR-04 after: JE=${await w.linesOf('purchase_invoice', id)} adjRefs=${adj.map((e) => e.data['rt']).toList()} '
        '${await state()}');
    final pr = (await w.db.getProductById(p))!;
    expect(pr.currentStock, closeTo(5, kEps));
    expect(pr.costPrice, closeTo(12, kEps), reason: 'تصحيح مزدوج: WAC و قيد التسوية معاً');
    expect(await w.accountNet('1136'), closeTo(pr.currentStock * pr.costPrice, 0.05),
        reason: 'قيمة المخزون في الأستاذ = الكمية × WAC');
  });

  test('PUR-05 مرتجعا مشتريات جزئيان على فاتورة مدفوع نصفها: الذمة لا تصبح سالبة', skip: kSkip,
      () async {
    await w.db.adjustSafeBalance(w.cashSafeId, 1000);
    final id = await buy(10, 60, paid: 300); // إجمالي 600، مفتوح 300
    final a = await pret(id, 4); // 240 ⇒ من الذمة
    _log('PUR-05 after 1st: res=$a ${await state()}');
    final b = await pret(id, 4); // 240 ⇒ 60 من الذمة + 180 نقداً
    _log('PUR-05 after 2nd: res=$b ${await state()}');
    expect(await w.partyBalance(sup), greaterThanOrEqualTo(-kEps),
        reason: 'المرتجع الثاني يحسب الحصة على total−paid الأصلية');
    expect(await w.partyBalance(sup), closeTo(0, kEps));
    expect(await w.accountNet('211'), closeTo(0, kEps));
  });

  test('PUR-06 مرتجع مشتريات تراكمي يتجاوز الكمية (6 ثم 6 من 10) ⇒ رفض الثاني في المستودع',
      skip: kSkip, () async {
    final id = await buy(10, 60);
    final a = await pret(id, 6);
    final b = await pret(id, 6);
    _log('PUR-06 first=$a second=$b ${await state()}');
    expect(b is String, isTrue, reason: 'الحد التراكمي في الواجهة فقط');
  });

  test('PUR-07 تكلفة هبوط 100 من مورد شحن على 10×100: WAC 110 و ذمة مورد الشحن 100',
      skip: kSkip, () async {
    final freight = await w.addSupplier('شركة شحن');
    final id = await buy(10, 100);
    final sheet = await w.db.createLandedCostSheet(purchaseInvoiceId: id, sheetNumber: 'LC-1');
    await w.db.addLandedCostItem(
        sheetId: sheet, costType: 'freight', description: 'شحن', amount: 100, supplierPartyId: freight);
    Object res = true;
    try {
      final alloc = await w.db.calculateAllocations(sheet); // كما تفعل الشاشة قبل الاعتماد
      _log('PUR-07 allocations=${alloc.map((a) => a.toJson()).toList()}');
      await w.db.applyLandedCost(sheet);
    } catch (e) {
      res = 'EXC: $e';
    }
    final je = await w.db.customSelect(
        "SELECT a.code c, l.debit d, l.credit cr FROM journal_entry_lines l JOIN journal_entries e ON e.id = l.entry_id "
        "JOIN accounts a ON a.id = l.account_id WHERE e.reference_type LIKE 'landed%'").get();
    _log('PUR-07 apply=$res JE=${je.map((e) => e.data).toList()} freightParty=${await w.partyBalance(freight)} '
        '${await state()} mismatches=${(await w.db.getPartyBalanceMismatches()).length}');
    expect((await w.db.getProductById(p))!.costPrice, closeTo(110, kEps));
    expect(await w.partyBalance(freight), closeTo(100, kEps),
        reason: 'applyLandedCost لا يستدعي adjustPartyBalance');
  });

  test('PUR-08 تعديل فاتورة شراء 10→8: القيد يُعكس بقيد معاكس (أثر تدقيقي) لا يُحذف', skip: kSkip,
      () async {
    await w.grant(PermissionCodes.purchasesEdit);
    final id = await buy(10, 60);
    final before = await w.db.customSelect('SELECT COUNT(*) n FROM journal_entries').getSingle();
    Object res = true;
    try {
      await repo().updateInvoice(UpdatePurchaseInvoiceParams(
          invoiceId: id,
          userId: w.userId,
          supplierId: sup,
          warehouseId: w.warehouseId,
          paid: 0,
          paymentMethod: 'credit',
          items: [
            PurchaseItemParams(
                productId: p, quantity: 8, unitCost: 60, salePrice: 100, taxRate: 0, taxAmount: 0)
          ]));
    } catch (e) {
      res = 'EXC: $e';
    }
    final all = await w.db
        .customSelect('SELECT id, reference_type rt, is_deleted d FROM journal_entries ORDER BY id')
        .get();
    final activity = await w.db.customSelect(
      'SELECT id, action, entity_type, entity_id, description, old_value, new_value '
      'FROM activity_logs WHERE entity_type = ? AND entity_id = ? ORDER BY id',
      variables: [Variable<String>('purchase_invoice'), Variable<int>(id)],
    ).get();
    _log('PUR-08 res=$res jeBefore=${before.data['n']} '
        'after=${all.map((e) => e.data).toList()} activity=${activity.map((e) => e.data).toList()} '
        '${await state()}');
    expect(res, isTrue);
    expect(await w.partyBalance(sup), closeTo(480, kEps));
    expect(all.length, greaterThanOrEqualTo(3), reason: 'أصل + عكس + جديد');
  });

  test('PUR-09 إلغاء فاتورة شراء بعد مرتجع جزئي ⇒ يجب الرفض أو عكس الصافي فقط', skip: kSkip, () async {
    final id = await buy(10, 60);
    await pret(id, 4);
    Object res = true;
    try {
      await repo().voidInvoice(id, reason: 'تدقيق');
    } catch (e) {
      res = 'EXC: $e';
    }
    _log('PUR-09 void=$res ${await state()}');
    if (res == true) {
      expect(await w.stock(p), closeTo(0, kEps), reason: 'لا يُخرَج إلا الصافي 6');
      expect(await w.partyBalance(sup), closeTo(0, kEps));
    }
  });

  test('PUR-06b مرتجع تراكمي 6 ثم 6 من فاتورة 10 مع رصيد إضافي من فاتورة أخرى ⇒ رفض الثاني',
      skip: kSkip, () async {
    final id = await buy(10, 60);
    await buy(20, 60);
    final a = await pret(id, 6);
    final b = await pret(id, 6);
    _log('PUR-06b first=$a second=$b ${await state()}');
    expect(b is String, isTrue, reason: 'المستودع يقارن بالكمية الأصلية فقط لا بالمرتجع السابق');
  });

  test('PUR-09b إلغاء فاتورة شراء بعد مرتجع 4 مع رصيد إضافي ⇒ لا يُخرج إلا الصافي 6', skip: kSkip,
      () async {
    final id = await buy(10, 60);
    await buy(20, 60);
    await pret(id, 4);
    Object res = true;
    try {
      await repo().voidInvoice(id, reason: 'تدقيق');
    } catch (e) {
      res = 'EXC: $e';
    }
    _log('PUR-09b void=$res ${await state()}');
    expect(res, isNot(true), reason: 'أو يُعكس الصافي فقط: المتوقع رصيد 20 وذمة 1200');
    expect(await w.stock(p), closeTo(20, kEps));
    expect(await w.partyBalance(sup), closeTo(1200, kEps));
  });

  test('PUR-10 رقم فاتورة المورد مكرر بمسافة زائدة "A-1 " ⇒ يجب الرفض', skip: kSkip, () async {
    await buy(1, 10, supplierInvoiceNumber: 'A-1');
    Object res = true;
    try {
      await buy(1, 10, supplierInvoiceNumber: 'A-1 ');
    } catch (e) {
      res = 'EXC: $e';
    }
    _log('PUR-10 second=$res');
    expect(res, isNot(true));
  });

  test('PUR-11 مرتجع مشتريات بعد تغيّر WAC: يُخرج بتكلفة السطر و1136 = الكمية × WAC', skip: kSkip,
      () async {
    final id1 = await buy(10, 60);
    await buy(10, 90); // WAC 75
    final r = await pret(id1, 5); // 5 @60 تخرج ⇒ 15 @ (1500−300)/15 = 80
    _log('PUR-11 ret=$r ${await state()}');
    final pr = (await w.db.getProductById(p))!;
    expect(pr.costPrice, closeTo(80, kEps));
    expect(await w.accountNet('1136'), closeTo(pr.currentStock * pr.costPrice, 0.05));
  });
}
