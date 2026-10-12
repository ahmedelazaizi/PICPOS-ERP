// سيناريو (ي): فترة/سنة مالية مقفلة ترفض الترحيل بتاريخ فيها — وبلا أي أثر جانبي
// (لا مخزون ولا خزينة ولا قيد) لأن العملية تتراجع كاملة.
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/domain/repositories/purchases_repository.dart';

import 'scenario_world.dart';

void main() {
  late ScenarioWorld w;
  late int product;
  late int supplier;

  setUp(() async {
    w = await ScenarioWorld.create();
    product = await w.addProduct('J1', price: 100, cost: 60, stock: 50);
    supplier = await w.addSupplier('مورد الفترة');
  });
  tearDown(() => w.dispose());

  Future<void> closeCurrentMonth() async {
    final now = DateTime.now();
    final n = await (w.db.update(w.db.accountingPeriods)
          ..where((p) => p.month.equals(now.month) & p.year.equals(now.year)))
        .write(const AccountingPeriodsCompanion(isClosed: Value(true)));
    expect(n, 1, reason: 'تجهيزة: فترة الشهر الحالي موجودة وأُقفلت');
  }

  Future<void> expectNoSideEffects(
      {required double stock, required double safe, required int entries}) async {
    expect(await w.stock(product), closeTo(stock, kEps));
    expect(await w.safeBalance(), closeTo(safe, kEps));
    final c = await w.db
        .customSelect('select count(*) n from journal_entries')
        .getSingle();
    expect(c.data['n'], entries);
  }

  test('فترة الشهر الحالي مقفلة: بيع نقدي اليوم يُرفض بلا أثر', () async {
    final ok = await w.sell([w.line(product, 2, 100)]);
    expect(ok.invoiceId, isNotNull);
    final entries = (await w.db
            .customSelect('select count(*) n from journal_entries')
            .getSingle())
        .data['n'] as int;

    await closeCurrentMonth();

    await w.expectSaleRejected(w.sellRaw([w.line(product, 1, 100)]), 'مغلقة');
    await expectNoSideEffects(stock: 48, safe: 200, entries: entries);
  });

  test('فترة مقفلة: إلغاء فاتورة سابقة في الفترة نفسها يُرفض', () async {
    final r = await w.sell([w.line(product, 2, 100)]);
    await closeCurrentMonth();
    await expectLater(
        w.db.voidSalesInvoice(r.invoiceId!, deletedBy: w.userId),
        throwsA(isA<Exception>()));
    final inv = await (w.db.select(w.db.salesInvoices)
          ..where((i) => i.id.equals(r.invoiceId!)))
        .getSingle();
    expect(inv.status, isNot('voided'));
    expect(await w.stock(product), closeTo(48, kEps));
    expect(await w.safeBalance(), closeTo(200, kEps));
  });

  test('فترة مقفلة: فاتورة شراء بتاريخ فيها تُرفض بلا أثر على المخزون', () async {
    await closeCurrentMonth();
    await expectLater(
        w.container.read(purchasesRepositoryProvider).createInvoice(
            CreatePurchaseInvoiceParams(
                supplierId: supplier,
                warehouseId: w.warehouseId,
                paid: 0,
                paymentMethod: 'credit',
                userId: w.userId,
                items: [
                  PurchaseItemParams(
                      productId: product,
                      quantity: 5,
                      unitCost: 60,
                      salePrice: 100,
                      taxRate: 0,
                      taxAmount: 0)
                ])),
        throwsA(isA<Exception>()));
    expect(await w.stock(product), closeTo(50, kEps));
    expect(await w.partyBalance(supplier), closeTo(0, kEps));
  });

  test('سنة مالية مقفلة (2024): بيع بتاريخ 2024-06-15 يُرفض ولا يُنشأ مستند',
      () async {
    final yearId = await w.db.into(w.db.fiscalYears).insert(
        FiscalYearsCompanion.insert(
            name: 'السنة المالية 2024',
            startDate: DateTime(2024, 1, 1),
            endDate: DateTime(2024, 12, 31)));
    await w.db.closeFiscalYear(yearId, w.userId);
    final entries = (await w.db
            .customSelect('select count(*) n from journal_entries')
            .getSingle())
        .data['n'] as int;
    final invoices = (await w.db
            .customSelect('select count(*) n from sales_invoices')
            .getSingle())
        .data['n'] as int;

    await w.expectSaleRejected(
        w.sellRaw([w.line(product, 1, 100)], date: DateTime(2024, 6, 15)), 'سنة مالية مغلقة');

    await expectNoSideEffects(stock: 50, safe: 0, entries: entries);
    final after = await w.db
        .customSelect('select count(*) n from sales_invoices')
        .getSingle();
    expect(after.data['n'], invoices);
  });

  test('الفترة المفتوحة تقبل الترحيل بعد رفض الفترة المقفلة (لا أثر دائم للرفض)',
      () async {
    final yearId = await w.db.into(w.db.fiscalYears).insert(
        FiscalYearsCompanion.insert(
            name: 'السنة المالية 2023',
            startDate: DateTime(2023, 1, 1),
            endDate: DateTime(2023, 12, 31)));
    await w.db.closeFiscalYear(yearId, w.userId);
    await w.expectSaleRejected(
        w.sellRaw([w.line(product, 1, 100)], date: DateTime(2023, 3, 1)),
        'مغلقة');
    final r = await w.sell([w.line(product, 1, 100)]);
    expect(r.invoiceId, isNotNull);
    expect(await w.stock(product), closeTo(49, kEps));
    expect(await w.safeBalance(), closeTo(100, kEps));
  });
}
