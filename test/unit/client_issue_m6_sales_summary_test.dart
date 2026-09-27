// ═══════════════════════════════════════════════════════════════════════════
// متطلبات العميل 2026-07-25 · م6 · ح-2 + البند 2 — إجماليات شاشة فواتير
// المبيعات.
// ═══════════════════════════════════════════════════════════════════════════
//
// ح-2 (حاجب): كل بطاقات الشاشة كانت تُجمَّع في الذاكرة فوق نتيجة
// `getInvoicesPaged()` المحدودة بـ**500 صف**. فرع فيه 4000 فاتورة يختار
// مارس ⇒ «إجمالي المبيعات» يعرض رقماً مبتوراً أو صفراً، و«عدد الفواتير»
// يعدّ الصفوف المحمَّلة لا المطابقة — **بلا أي مؤشر بتر**.
//
// البند 2: بطاقة «إجمالي المرتجعات» موجودة أصلاً؛ الناقص «صافي المبيعات».
// لكن إضافتها فوق أساس مبتور = رقم خاطئ بمظهر أفضل — لذلك التجميع في SQL
// **شرط مسبق**.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int warehouseId;
  late int otherWarehouseId;
  late int userId;
  // ignore: unused_local_variable
  late int productId;

  setUp(() async {
    db = AppDatabase.forTesting();
    warehouseId = await db.into(db.warehouses).insert(
        WarehousesCompanion.insert(
            name: 'مخزن م6', globalId: const Value('gid-wh-m6')));
    otherWarehouseId = await db.into(db.warehouses).insert(
        WarehousesCompanion.insert(
            name: 'مخزن آخر م6', globalId: const Value('gid-wh-m6b')));
    userId = await db.into(db.users).insert(UsersCompanion.insert(
          username: 'm6_user',
          passwordHash: 'x',
          displayName: 'M6',
          roleId: const Value(1),
        ));
    productId = await db.insertProduct(ProductsCompanion.insert(
      code: 'M6-1',
      name: 'صنف م6',
      trackInventory: const Value(true),
    ));
  });

  tearDown(() async => db.close());

  Future<int> makeInvoice({
    required double total,
    required double paid,
    required DateTime date,
    int? whId,
    String saleType = 'default',
    String? notes,
  }) =>
      db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
            invoiceNumber: 'M6-${DateTime.now().microsecondsSinceEpoch}',
            warehouseId: whId ?? warehouseId,
            userId: userId,
            invoiceDate: date,
            total: Value(total),
            paid: Value(paid),
            saleType: Value(saleType),
            notes: Value(notes),
          ));

  test('ح-2: الإجماليات تُحسب على كل الفواتير المطابقة لا على أحدث 500',
      () async {
    // 600 فاتورة بـ100 لكل منها ⇒ الإجمالي الصحيح 60,000.
    for (var i = 0; i < 600; i++) {
      await makeInvoice(
          total: 100, paid: 100, date: DateTime(2026, 7, 10, 0, 0, i % 60));
    }

    final s = await db.getSalesInvoiceSummary(
      from: DateTime(2026, 7, 1),
      to: DateTime(2026, 7, 31),
    );

    expect(s.invoiceCount, 600,
        reason: 'العدد يعكس الصفوف المطابقة لا المحمَّلة');
    expect(s.totalAmount, closeTo(60000, 0.001),
        reason: 'التجميع في SQL لا يبتره ترقيم الصفحات');
    expect(s.totalPaid, closeTo(60000, 0.001));
  });

  test('البند 2: صافي المبيعات = الإجمالي − المرتجعات', () async {
    final original = await makeInvoice(
        total: 1000, paid: 400, date: DateTime(2026, 7, 10));
    // مرتجع مرتبط بالفاتورة عبر نفس الصيغة التي يقرأها التقرير.
    await makeInvoice(
      total: 300,
      paid: 0,
      date: DateTime(2026, 7, 11),
      saleType: 'return',
      notes: 'Return for invoice #$original',
    );

    final s = await db.getSalesInvoiceSummary(
      from: DateTime(2026, 7, 1),
      to: DateTime(2026, 7, 31),
    );

    expect(s.invoiceCount, 1, reason: 'صفوف المرتجعات ليست فواتير بيع');
    expect(s.totalAmount, closeTo(1000, 0.001));
    expect(s.totalReturns, closeTo(300, 0.001));
    expect(s.netSales, closeTo(700, 0.001),
        reason: 'صافي المبيعات = 1000 − 300');
    expect(s.totalRemaining, closeTo(300, 0.001),
        reason: 'المتبقي = 1000 − 400 مدفوع − 300 مرتجع');
  });

  test('نافذة التاريخ لا تسرّب اليوم السابق ولا التالي', () async {
    await makeInvoice(total: 50, paid: 50, date: DateTime(2026, 6, 30, 23, 59));
    await makeInvoice(total: 100, paid: 100, date: DateTime(2026, 7, 1));
    await makeInvoice(total: 100, paid: 100, date: DateTime(2026, 7, 31, 23, 59));
    await makeInvoice(total: 50, paid: 50, date: DateTime(2026, 8, 1));

    final s = await db.getSalesInvoiceSummary(
      from: DateTime(2026, 7, 1),
      to: DateTime(2026, 7, 31),
    );
    expect(s.invoiceCount, 2);
    expect(s.totalAmount, closeTo(200, 0.001),
        reason: 'نفس نافذة `dayWindowFor`: [بداية البداية، بداية اليوم التالي)');
  });

  test('فلتر المخزن يُطبَّق في SQL', () async {
    await makeInvoice(total: 100, paid: 100, date: DateTime(2026, 7, 10));
    await makeInvoice(
        total: 999,
        paid: 999,
        date: DateTime(2026, 7, 10),
        whId: otherWarehouseId);

    final s = await db.getSalesInvoiceSummary(
      from: DateTime(2026, 7, 1),
      to: DateTime(2026, 7, 31),
      warehouseIds: [warehouseId],
    );
    expect(s.totalAmount, closeTo(100, 0.001));
  });

  test('الفواتير المحذوفة مستبعدة', () async {
    final id = await makeInvoice(
        total: 500, paid: 500, date: DateTime(2026, 7, 10));
    await (db.update(db.salesInvoices)..where((s) => s.id.equals(id)))
        .write(const SalesInvoicesCompanion(isDeleted: Value(true)));

    final s = await db.getSalesInvoiceSummary(
      from: DateTime(2026, 7, 1),
      to: DateTime(2026, 7, 31),
    );
    expect(s.invoiceCount, 0);
    expect(s.totalAmount, closeTo(0, 0.001));
  });

  test('مدى بلا فواتير يرجع أصفاراً لا يرمي', () async {
    final s = await db.getSalesInvoiceSummary(
      from: DateTime(2026, 1, 1),
      to: DateTime(2026, 1, 31),
    );
    expect(s.invoiceCount, 0);
    expect(s.totalAmount, 0);
    expect(s.netSales, 0);
  });
}
