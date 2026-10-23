// ═══════════════════════════════════════════════════════════════════════════
// وحدةُ التاريخ: drift يخزّن **ثواني**، واستعلاماتٌ تعامله كأنه ملّي
// ═══════════════════════════════════════════════════════════════════════════
//
// `AppDatabase.dateVar` يصرّح صراحةً أن أعمدة DateTime تُخزَّن epoch **seconds**
// في SQLite وPostgreSQL معاً. موضعان يخالفان ذلك:
//
// B2 · تقادمُ الذمم (`getArAgingReport`) — تعليقٌ يزعم «milliseconds» ثم
//   `julianday(col / 1000, 'unixepoch')`. القسمةُ على ألفٍ تقع **مرّتين**
//   (مرّةً في drift ومرّةً في SQL) ⇒ كلُّ تاريخٍ ينهار إلى 1970 ⇒ العمر
//   ~٢٠٬٠٠٠ يوم ⇒ **كلُّ فاتورةٍ غير مسدَّدة تسقط في خانة ٩٠+**.
//   تُبنى على هذه الشاشة قراراتُ ائتمانٍ ومخصّصاتُ ديونٍ مشكوك فيها.
//
// B3 · تسويةُ القيمة المضافة (`getVatReconciliationData`) — `startMs`/`endMs`
//   بالملّي تُقارَن بأعمدةٍ بالثواني ⇒ لا صفَّ يقع في المدى إطلاقاً.
//   وحين يصير الطرفان صفراً يصير الفرقُ صفراً، فتُرسَم الشاشةُ **خضراء
//   «مطابق»** — شهادةُ براءةٍ كاذبةٍ على إقرارٍ ضريبيّ.
//
// الاختبارات دي بتقيس السلوك المرصود لا الاستعلام، فتفضل صالحة لو اتغيّرت
// صياغةُ SQL.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/domain/entities/accounting_entities.dart';

void main() {
  late AppDatabase db;
  late int warehouseId;

  // ٢٠٢٦-٠٨-٣١ هو اليوم ٢٤٣ من السنة، فـ٢٠٢٦-٠١-٠١ يبعد عنه ٢٤٢ يوماً بالضبط.
  final asOf = DateTime(2026, 8, 31);
  final sixDaysOld = DateTime(2026, 8, 25); // ٦ أيام  ⇒ خانة 0-30
  final oldInvoice = DateTime(2026, 1, 1); // ٢٤٢ يوماً ⇒ خانة 90+

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    warehouseId = await db.into(db.warehouses).insert(
        WarehousesCompanion.insert(
            name: 'مخزن التقادم', globalId: const Value('gid-wh-aging')));
  });

  tearDown(() async => db.close());

  // ═════════════════════════════════════════════════════════════════════════
  // B2 · تقادمُ الذمم المدينة والدائنة
  // ═════════════════════════════════════════════════════════════════════════

  test('B2 مدين: فاتورةُ ٦ أيام في 0-30 وفاتورةُ ٢٤٢ يوماً في 90+', () async {
    final customerId = await db.into(db.parties).insert(PartiesCompanion.insert(
          name: 'عميل التقادم',
          balance: const Value(1000),
          isCustomer: const Value(true),
          globalId: const Value('gid-cust-aging'),
        ));

    Future<void> unpaidInvoice(String no, DateTime date, double total) =>
        db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
              invoiceNumber: no,
              warehouseId: warehouseId,
              userId: 1,
              customerId: Value(customerId),
              subtotal: Value(total),
              total: Value(total),
              paid: const Value(0),
              paymentMethod: const Value('credit'),
              invoiceDate: date,
            ));

    await unpaidInvoice('AG-NEW', sixDaysOld, 400);
    await unpaidInvoice('AG-OLD', oldInvoice, 600);

    final rows = await db.getArAgingReport(asOfDate: asOf);
    final row = rows.firstWhere((r) => r.partyId == customerId);

    expect(row.bucket0_30, closeTo(400, 0.01),
        reason: 'فاتورةُ ٦ أيام لازم تقع في 0-30، لا في 90+');
    expect(row.bucket31_60, closeTo(0, 0.01));
    expect(row.bucket61_90, closeTo(0, 0.01));
    expect(row.bucket90Plus, closeTo(600, 0.01),
        reason: '٩٠+ لازم تحمل الفاتورةَ القديمة وحدها (٦٠٠) لا الاثنتين (١٠٠٠)');
  });

  test('B2 دائن: نفس القسمة على شقّ الموردين', () async {
    final supplierId = await db.into(db.parties).insert(PartiesCompanion.insert(
          name: 'مورد التقادم',
          balance: const Value(1000),
          isCustomer: const Value(false),
          isSupplier: const Value(true),
          globalId: const Value('gid-supp-aging'),
        ));

    Future<void> unpaidBill(String no, DateTime date, double total) =>
        db.into(db.purchaseInvoices).insert(PurchaseInvoicesCompanion.insert(
              invoiceNumber: no,
              supplierId: supplierId,
              warehouseId: warehouseId,
              subtotal: Value(total),
              total: Value(total),
              paid: const Value(0),
              invoiceDate: date,
            ));

    await unpaidBill('AP-NEW', sixDaysOld, 400);
    await unpaidBill('AP-OLD', oldInvoice, 600);

    final rows =
        await db.getArAgingReport(asOfDate: asOf, customersOnly: false);
    final row = rows.firstWhere((r) => r.partyId == supplierId);

    expect(row.bucket0_30, closeTo(400, 0.01));
    expect(row.bucket90Plus, closeTo(600, 0.01));
  });

  test('B2: خانةُ 31-60 مش ميتة — فاتورةُ ٤٥ يوماً تقع فيها', () async {
    final customerId = await db.into(db.parties).insert(PartiesCompanion.insert(
          name: 'عميل ٤٥ يوماً',
          balance: const Value(250),
          isCustomer: const Value(true),
          globalId: const Value('gid-cust-45d'),
        ));
    await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
          invoiceNumber: 'AG-45',
          warehouseId: warehouseId,
          userId: 1,
          customerId: Value(customerId),
          subtotal: const Value(250),
          total: const Value(250),
          paid: const Value(0),
          paymentMethod: const Value('credit'),
          invoiceDate: asOf.subtract(const Duration(days: 45)),
        ));

    final rows = await db.getArAgingReport(asOfDate: asOf);
    final row = rows.firstWhere((r) => r.partyId == customerId);

    expect(row.bucket31_60, closeTo(250, 0.01),
        reason: 'الخانةُ الوسطى لازم تستقبل صفوفاً، لا تفضل صفراً دايماً');
    expect(row.bucket90Plus, closeTo(0, 0.01));
  });

  test('B2: فاتورةٌ بعد تاريخ الأساس تُستبعَد', () async {
    final customerId = await db.into(db.parties).insert(PartiesCompanion.insert(
          name: 'عميل المستقبل',
          balance: const Value(700),
          isCustomer: const Value(true),
          globalId: const Value('gid-cust-future'),
        ));
    await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
          invoiceNumber: 'AG-FUT',
          warehouseId: warehouseId,
          userId: 1,
          customerId: Value(customerId),
          subtotal: const Value(700),
          total: const Value(700),
          paid: const Value(0),
          paymentMethod: const Value('credit'),
          invoiceDate: asOf.add(const Duration(days: 10)),
        ));

    final rows = await db.getArAgingReport(asOfDate: asOf);
    final row = rows.firstWhere((r) => r.partyId == customerId);

    expect(
        row.bucket0_30 + row.bucket31_60 + row.bucket61_90 + row.bucket90Plus,
        closeTo(0, 0.01),
        reason: '`si.invoice_date <= ?` لازم يقارن بنفس الوحدة كمان');
  });

  // ═════════════════════════════════════════════════════════════════════════
  // B3 · تسويةُ القيمة المضافة
  // ═════════════════════════════════════════════════════════════════════════

  test('B3: ضريبةُ فواتير الشهر تُقرأ — لا صفر يطبع «مطابق»', () async {
    final customerId = await db.into(db.parties).insert(PartiesCompanion.insert(
          name: 'عميل الضريبة',
          isCustomer: const Value(true),
          globalId: const Value('gid-cust-vat'),
        ));
    final saleDate = DateTime(2026, 7, 10);

    final invoiceId =
        await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
              invoiceNumber: 'VAT-1',
              warehouseId: warehouseId,
              userId: 1,
              customerId: Value(customerId),
              subtotal: const Value(1000),
              tax: const Value(150),
              total: const Value(1150),
              paid: const Value(1150),
              paymentMethod: const Value('cash'),
              invoiceDate: saleDate,
            ));

    final vatAcc = (await db.getAccountByCode('2121'))!;
    final cashAcc = (await db.getAccountByCode('1111'))!;
    final salesAcc = (await db.getAccountByCode('4121'))!;
    await db.createJournalEntry(
      description: 'قيد بيع للتسوية',
      date: saleDate,
      referenceType: 'sale',
      referenceId: invoiceId,
      isAutoPosted: true,
      lines: [
        JournalLine(accountId: cashAcc.id, debit: 1150, credit: 0),
        JournalLine(accountId: salesAcc.id, debit: 0, credit: 1000),
        JournalLine(accountId: vatAcc.id, debit: 0, credit: 150),
      ],
    );

    final result = await db.getVatReconciliationData(year: 2026, month: 7);

    expect(result.invoiceOutputVat, closeTo(150, 0.01),
        reason: 'ضريبةُ المخرجات من الفواتير كانت بتُقرأ صفراً');
    expect(result.glOutputVat, closeTo(150, 0.01),
        reason: 'وطرفُ الأستاذ كمان — فالفرقُ صفرٌ كاذبٌ لا حقيقيّ');
  });

  test('B3: ضريبةُ المشتريات (المدخلات) تُقرأ كذلك', () async {
    final supplierId = await db.into(db.parties).insert(PartiesCompanion.insert(
          name: 'مورد الضريبة',
          isCustomer: const Value(false),
          isSupplier: const Value(true),
          globalId: const Value('gid-supp-vat'),
        ));
    await db.into(db.purchaseInvoices).insert(PurchaseInvoicesCompanion.insert(
          invoiceNumber: 'VATP-1',
          supplierId: supplierId,
          warehouseId: warehouseId,
          subtotal: const Value(2000),
          tax: const Value(300),
          total: const Value(2300),
          invoiceDate: DateTime(2026, 7, 12),
        ));

    final result = await db.getVatReconciliationData(year: 2026, month: 7);
    expect(result.invoiceInputVat, closeTo(300, 0.01));
  });

  test('B3: فاتورةُ شهرٍ مجاور ما تدخلش المدى', () async {
    final customerId = await db.into(db.parties).insert(PartiesCompanion.insert(
          name: 'عميل أغسطس',
          isCustomer: const Value(true),
          globalId: const Value('gid-cust-vat-aug'),
        ));
    await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
          invoiceNumber: 'VAT-AUG',
          warehouseId: warehouseId,
          userId: 1,
          customerId: Value(customerId),
          subtotal: const Value(1000),
          tax: const Value(999),
          total: const Value(1999),
          paid: const Value(1999),
          paymentMethod: const Value('cash'),
          invoiceDate: DateTime(2026, 8, 3),
        ));

    final result = await db.getVatReconciliationData(year: 2026, month: 7);
    expect(result.invoiceOutputVat, closeTo(0, 0.01),
        reason: 'حدُّ الشهر لازم يفصل فعلاً — لا يبتلع الشهرَ التالي');
  });
}
