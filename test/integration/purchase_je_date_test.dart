// قيد فاتورة المشتريات كان بتاريخ **النهاردة** مش تاريخ الفاتورة، وقفل الفترة
// كان بيتفحص على النهاردة كمان.
//
// ── العطلان ─────────────────────────────────────────────────────────────────
// `purchase_dao.dart:469` → `validateFinancialPeriod(DateTime.now())`
// `purchase_dao.dart:878` → `date: DateTime.now()`
// بينما الهيدر بيتخزن بـ`invoiceDate ?? DateTime.now()` (‏:598).
//
// **١. قفل الفترة متجاوَز على مستوى المستند:** فاتورة بتاريخ مارس بتتقبل حتى
//    لو مارس مقفول، لأن الفحص على أغسطس.
//
// **٢. الضريبة بتتحسب في إقرار الشهر الغلط:** تقرير المشتريات بيفلتر بـ
//    `i.invoiceDate` وتقرير الضريبة بيفلتر بـ`e.entry_date`. فاتورة مؤرَّخة
//    مارس وقيدها أغسطس بتظهر في مشتريات مارس وفي ضريبة مدخلات أغسطس.
//
// ── المقارنة اللي بتحسم ─────────────────────────────────────────────────────
// مسار المبيعات **صح** (`sales_mutations_dao.dart:55` → `effectiveInvoiceDate`)،
// و`autoPostPurchase:968` نفسه بيستعمل `purchase.invoiceDate` — يعني مسارين
// في نفس النظام لنفس المستند بتاريخين مختلفين.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int supplierId;
  late int productId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    supplierId = await db.insertParty(PartiesCompanion.insert(
      name: 'مورد اختبار',
      isSupplier: const Value(true),
    ));
    productId = await db.into(db.products).insert(ProductsCompanion.insert(
          name: 'صنف',
          code: 'P-JE-DATE',
          salePrice: const Value(20.0),
          costPrice: const Value(10.0),
        ));
    await db.into(db.fiscalYears).insert(FiscalYearsCompanion(
          name: const Value('السنة'),
          startDate: Value(DateTime(2026, 1, 1)),
          endDate: Value(DateTime(2026, 12, 31)),
          isCurrent: const Value(true),
        ));
  });
  tearDown(() => db.close());

  Future<int> makePurchase(DateTime invoiceDate) => db.createPurchaseInvoice(
        supplierId: supplierId,
        warehouseId: 1,
        userId: 1,
        paid: 0,
        paymentMethod: 'credit',
        invoiceDate: invoiceDate,
        items: [
          PurchaseInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 10,
            unitCost: 10,
            total: 100,
          ),
        ],
      );

  test('قيد الفاتورة بياخد تاريخ الفاتورة مش تاريخ النهاردة', () async {
    final backdated = DateTime(2026, 3, 10);
    final invoiceId = await makePurchase(backdated);

    final je = await (db.select(db.journalEntries)
          ..where((e) =>
              e.referenceType.equals('purchase_invoice') &
              e.referenceId.equals(invoiceId)))
        .getSingle();

    expect(je.entryDate.year, 2026);
    expect(je.entryDate.month, 3,
        reason: 'القيد في أغسطس والفاتورة في مارس — الضريبة هتتحسب في '
            'إقرار الشهر الغلط');
    expect(je.entryDate.day, 10);
  });

  test('فاتورة بتاريخ فترة مقفولة بتترفض — القفل مش متجاوَز', () async {
    // الفترات بتتولّد مع السنة المالية، فالإقفال تحديث مش إدخال.
    await db.generatePeriodsForYear(1, DateTime(2026, 1, 1), DateTime(2026, 12, 31));
    await db.customStatement(
        'UPDATE accounting_periods SET is_closed = 1 WHERE month = 3 AND year = 2026');

    await expectLater(
      makePurchase(DateTime(2026, 3, 10)),
      throwsA(predicate((e) => e.toString().contains('مغلقة'))),
      reason: 'الفحص كان على النهاردة فالفاتورة المؤرَّخة مارس بتعدّي',
    );
  });

  test('فاتورة بتاريخ فترة مفتوحة بتعدّي عادي', () async {
    final open = DateTime(2026, 6, 15);
    final invoiceId = await makePurchase(open);
    expect(invoiceId, greaterThan(0));

    final je = await (db.select(db.journalEntries)
          ..where((e) => e.referenceId.equals(invoiceId) &
              e.referenceType.equals('purchase_invoice')))
        .getSingle();
    expect(je.entryDate.month, 6);
  });

  test('فاتورة بلا تاريخ صريح بتاخد النهاردة زي الأول', () async {
    final invoiceId = await makePurchase(DateTime.now());
    final je = await (db.select(db.journalEntries)
          ..where((e) => e.referenceId.equals(invoiceId) &
              e.referenceType.equals('purchase_invoice')))
        .getSingle();
    expect(je.entryDate.day, DateTime.now().day);
  });
}
