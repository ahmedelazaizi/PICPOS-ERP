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
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/domain/entities/accounting_entities.dart';

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
  // البند 8
  // ═════════════════════════════════════════════════════════════════════════

  test('البند 8: تفصيل الضريبة لكل صنف بنسبته الخاصة', () async {
    // فاتورة واحدة بسطرين بنسبتين مختلفتين: 16% و 5%.
    await postInvoiceWithVat(
      saleType: 'default',
      referenceType: 'sale',
      net: 1100,
      vat: 185,
      whId: warehouseId,
      lines: [
        (rate: 16, amount: 160, lineTotal: 1160),
        (rate: 5, amount: 25, lineTotal: 525),
      ],
    );

    final rows = await db.getSalesTaxDetailByItem(from, to);

    expect(rows, hasLength(2), reason: 'سطر لكل صنف لا سطر لكل فاتورة');

    final byRate = {for (final r in rows) r['taxRate'] as double: r};
    expect(byRate.keys.toSet(), {16.0, 5.0},
        reason: 'كل سطر يحمل نسبته الخاصة');

    expect(byRate[16]!['taxAmount'], closeTo(160, 0.001));
    expect(byRate[5]!['taxAmount'], closeTo(25, 0.001));

    // الوعاء الضريبي = إجمالي السطر − ضريبته.
    expect(byRate[16]!['taxableBase'], closeTo(1000, 0.001));
    expect(byRate[5]!['taxableBase'], closeTo(500, 0.001));

    // مجموع ضرائب الأسطر == ضريبة رأس الفاتورة (ثابت Spec 151).
    final lineSum = rows.fold<double>(
        0, (s, r) => s + (r['taxAmount'] as num).toDouble());
    expect(lineSum, closeTo(185, 0.001));

    expect(rows.first['invoiceNumber'], isNotNull);
    expect(rows.first['customerName'], 'عميل م2');
    expect(rows.first['productName'], 'صنف م2');
  });

  test('البند 8: مجاميع فرعية لكل نسبة ضريبة تطابق التفصيل', () async {
    // فاتورتان: الأولى 16% و5%، الثانية 16% فقط ⇒ شريحتان.
    await postInvoiceWithVat(
      saleType: 'default',
      referenceType: 'sale',
      net: 1100,
      vat: 185,
      whId: warehouseId,
      lines: [
        (rate: 16, amount: 160, lineTotal: 1160),
        (rate: 5, amount: 25, lineTotal: 525),
      ],
    );
    await postInvoiceWithVat(
      saleType: 'default',
      referenceType: 'sale',
      net: 200,
      vat: 32,
      whId: warehouseId,
      lines: [(rate: 16, amount: 32, lineTotal: 232)],
    );

    final buckets = await db.getSalesTaxByRate(from, to);
    expect(buckets, hasLength(2), reason: 'شريحة لكل نسبة مميزة');
    expect(buckets.first['taxRate'], 16.0,
        reason: 'الشرائح مرتّبة تنازلياً بالنسبة');

    final byRate = {for (final b in buckets) b['taxRate'] as double: b};
    expect(byRate[16]!['taxableBase'], closeTo(1000 + 200, 0.001));
    expect(byRate[16]!['taxAmount'], closeTo(160 + 32, 0.001));
    expect(byRate[5]!['taxableBase'], closeTo(500, 0.001));
    expect(byRate[5]!['taxAmount'], closeTo(25, 0.001));

    // الثابت الحاكم: مجموع الشرائح == مجموع أسطر التفصيل.
    final detail = await db.getSalesTaxDetailByItem(from, to);
    final detailTax = detail.fold<double>(
        0, (s, r) => s + (r['taxAmount'] as num).toDouble());
    final bucketTax = buckets.fold<double>(
        0, (s, b) => s + (b['taxAmount'] as num).toDouble());
    expect(bucketTax, closeTo(detailTax, 0.001));
  });

  test('البند 8: المرتجعات والفواتير الملغاة لا تدخل التفصيل', () async {
    await postInvoiceWithVat(
      saleType: 'return',
      referenceType: 'sales_return',
      net: 100,
      vat: 16,
      whId: warehouseId,
      lines: [(rate: 16, amount: 16, lineTotal: 116)],
    );

    final rows = await db.getSalesTaxDetailByItem(from, to);
    expect(rows, isEmpty,
        reason: 'صفوف المرتجعات تُستبعد من تفصيل ضريبة المبيعات');
  });
}
