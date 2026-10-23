// ═══════════════════════════════════════════════════════════════════════════
// متطلبات العميل 2026-07-25 · الموجة م2 — تقرير ضريبة المبيعات
// ═══════════════════════════════════════════════════════════════════════════
//
// ح-7 — فلتر الفرع/المخزن **يضخّم الالتزام الضريبي**:
//   شرط `EXISTS` في getTaxReport يقيّد نوع المرجع بـ
//   ('sale', 'sales_invoice', 'cash_sale') فقط، بينما قيود المردودات نوعها
//   'sales_return' وقيود الضريبة اليدوية ليس لها فاتورة تُربط بها إطلاقاً.
//   النتيجة: **تسقط عكوسات ضريبة المردودات كلها** عند أي فلتر مخزن ⇒
//   «كل الفروع» يعطي الرقم الصحيح، واختيار الفرع يعطي رقماً **أكبر**.
//   لو قُدِّم إقرار ضريبي على الرقم المفلتر فهو خاطئ لصالح الجهة.
//
// البند 8 — تفصيل نسبة الضريبة لكل صنف:
//   `taxRate`/`taxAmount` محفوظان لكل سطر فاتورة فعلاً، لكن التقرير لا يقرأ
//   جدول الأصناف إطلاقاً — يعرض رؤوس الفواتير فقط.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/domain/entities/accounting_entities.dart';

void main() {
  late AppDatabase db;
  late int warehouseId;
  late int otherWarehouseId;
  late int customerId;
  late int productId;

  /// الفترة المغطاة بالتقرير.
  final from = DateTime(2026, 7, 1);
  final to = DateTime(2026, 7, 31, 23, 59, 59);
  final saleDate = DateTime(2026, 7, 10);

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();

    warehouseId = await db.into(db.warehouses).insert(
        WarehousesCompanion.insert(
            name: 'مخزن م2', globalId: const Value('gid-wh-m2')));
    otherWarehouseId = await db.into(db.warehouses).insert(
        WarehousesCompanion.insert(
            name: 'مخزن آخر', globalId: const Value('gid-wh-m2b')));
    customerId = await db.into(db.parties).insert(PartiesCompanion.insert(
          name: 'عميل م2',
          isCustomer: const Value(true),
          globalId: const Value('gid-cust-m2'),
        ));
    productId = await db.insertProduct(ProductsCompanion.insert(
      code: 'M2-1',
      name: 'صنف م2',
      trackInventory: const Value(true),
    ));
  });

  tearDown(() async => db.close());

  /// تنشئ فاتورة (بيع أو مرتجع) + قيدها على حساب ضريبة المخرجات.
  Future<int> postInvoiceWithVat({
    required String saleType,
    required String referenceType,
    required double net,
    required double vat,
    required int whId,
    List<({double rate, double amount, double lineTotal})> lines = const [],
  }) async {
    final invoiceId = await db.into(db.salesInvoices).insert(
          SalesInvoicesCompanion.insert(
            invoiceNumber: 'M2-$saleType-${DateTime.now().microsecondsSinceEpoch}',
            warehouseId: whId,
            userId: 1,
            customerId: Value(customerId),
            subtotal: Value(net),
            tax: Value(vat),
            total: Value(net + vat),
            paid: Value(net + vat),
            paymentMethod: const Value('cash'),
            saleType: Value(saleType),
            invoiceDate: saleDate,
          ),
        );

    for (final l in lines) {
      await db.into(db.salesInvoiceItems).insert(SalesInvoiceItemsCompanion(
            invoiceId: Value(invoiceId),
            productId: Value(productId),
            quantity: const Value(1),
            unitPrice: Value(l.lineTotal),
            total: Value(l.lineTotal),
            taxRate: Value(l.rate),
            taxAmount: Value(l.amount),
          ));
    }

    final vatAcc = (await db.getAccountByCode('2121'))!;
    final cashAcc = (await db.getAccountByCode('1111'))!;
    final salesAcc = (await db.getAccountByCode('4121'))!;

    // البيع: من النقدية / إلى المبيعات + ض. المخرجات.
    // المرتجع: العكس تماماً — يدين ض. المخرجات (يخفض الالتزام).
    final isReturn = saleType == 'return';
    await db.createJournalEntry(
      description: isReturn ? 'قيد مرتجع مبيعات' : 'قيد بيع',
      date: saleDate,
      referenceType: referenceType,
      referenceId: invoiceId,
      isAutoPosted: true,
      lines: [
        JournalLine(
          accountId: cashAcc.id,
          debit: isReturn ? 0 : net + vat,
          credit: isReturn ? net + vat : 0,
        ),
        JournalLine(
          accountId: salesAcc.id,
          debit: isReturn ? net : 0,
          credit: isReturn ? 0 : net,
        ),
        JournalLine(
          accountId: vatAcc.id,
          debit: isReturn ? vat : 0,
          credit: isReturn ? 0 : vat,
        ),
      ],
    );
    return invoiceId;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // ح-7
  // ═════════════════════════════════════════════════════════════════════════

  test('ح-7: فلتر المخزن لا يُسقط عكس ضريبة المردودات', () async {
    // بيع 1000 + ضريبة 160، ثم مرتجع كامل — صافي الالتزام الضريبي = 0.
    await postInvoiceWithVat(
      saleType: 'default',
      referenceType: 'sale',
      net: 1000,
      vat: 160,
      whId: warehouseId,
    );
    await postInvoiceWithVat(
      saleType: 'return',
      referenceType: 'sales_return',
      net: 1000,
      vat: 160,
      whId: warehouseId,
    );

    final unfiltered = await db.getTaxReport(from, to);
    expect(unfiltered['salesTax'], closeTo(0, 0.001),
        reason: 'بلا فلتر: البيع والمرتجع يتعادلان');

    final filtered = await db.getTaxReport(from, to, warehouseIds: [warehouseId]);
    expect(filtered['salesTax'], closeTo(0, 0.001),
        reason: 'فلتر المخزن يجب ألا يغيّر الرقم — إسقاط عكس المردودات '
            'يضخّم الالتزام الضريبي');
    expect(filtered['salesTax'], closeTo(unfiltered['salesTax'] as double, 0.001),
        reason: 'الفلتر الأضيق لا يجوز أن يعطي رقماً أكبر');
  });

  test('إجمالي المشتريات في التقرير يشمل الفواتير المُنشأة حديثاً', () async {
    // مسار الإنشاء يرحّل بنوع مرجع 'purchase_invoice'، ومسار التعديل بـ
    // 'purchase'. لو قرأ التقرير النوع الثاني فقط لظهرت المشتريات صفراً حتى
    // يُعدَّل كل فاتورة — وهو ما يجعل «إجمالي المشتريات بدون الضريبة» كاذباً.
    final supplierId = await db.into(db.parties).insert(PartiesCompanion.insert(
          name: 'مورد م2',
          isSupplier: const Value(true),
          globalId: const Value('gid-sup-m2'),
        ));
    final purchaseId = await db.into(db.purchaseInvoices).insert(
          PurchaseInvoicesCompanion.insert(
            invoiceNumber: 'PUR-M2',
            supplierId: supplierId,
            warehouseId: warehouseId,
            invoiceDate: saleDate,
            subtotal: const Value(500),
            tax: const Value(80),
            total: const Value(580),
          ),
        );

    final invAcc = (await db.getAccountByCode('1136'))!;
    final inputVatAcc = (await db.getAccountByCode('1141'))!;
    final apAcc = (await db.getAccountByCode('2111'))!;
    await db.createJournalEntry(
      description: 'قيد مشتريات',
      date: saleDate,
      referenceType: 'purchase_invoice',
      referenceId: purchaseId,
      isAutoPosted: true,
      lines: [
        JournalLine(accountId: invAcc.id, debit: 500),
        JournalLine(accountId: inputVatAcc.id, debit: 80),
        JournalLine(accountId: apAcc.id, credit: 580),
      ],
    );

    final report = await db.getTaxReport(from, to);
    expect(report['purchaseTax'], closeTo(80, 0.001));
    expect(report['purchaseTotalExclTax'], closeTo(500, 0.001),
        reason: 'فاتورة مُنشأة (purchase_invoice) يجب أن تُحتسب دون '
            'انتظار تعديلها');
  });

  test('ح-7: فلتر المخزن ما زال يستبعد مخزناً آخر', () async {
    await postInvoiceWithVat(
      saleType: 'default',
      referenceType: 'sale',
      net: 1000,
      vat: 160,
      whId: warehouseId,
    );
    await postInvoiceWithVat(
      saleType: 'default',
      referenceType: 'sale',
      net: 500,
      vat: 80,
      whId: otherWarehouseId,
    );

    final filtered = await db.getTaxReport(from, to, warehouseIds: [warehouseId]);
    expect(filtered['salesTax'], closeTo(160, 0.001),
        reason: 'الفلتر يجب أن يظل يستبعد فواتير المخازن الأخرى');
  });
}
