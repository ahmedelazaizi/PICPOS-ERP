// ═══════════════════════════════════════════════════════════════════════════
// ٣‑١ — الفاتورةُ المرتجعةُ كلّيّاً تخرج من **كلِّ** تجميعةِ مبيعات
// ═══════════════════════════════════════════════════════════════════════════
//
// العقدُ موثَّقٌ في `lib/domain/models/sales_returns_netting.dart`:
//   «الاستعلامُ يستثني مستنداتِ sale_type='return' كي لا تُطرح القيمةُ مرّتين،
//    ويستثني status IN ('returned','cancelled','voided') فيخرج المرتجعُ
//    الكاملُ من المجمل. يبقى المرتجعُ الجزئيُّ داخلَ المجمل بقيمة فاتورته
//    الكاملة — وهذا ما تطرحه الدوالُّ هناك.»
//
// وأربعُ تجميعاتٍ فقط كانت تحترمه (`getSalesAnalytics` ·
// `getCategoryProfitReport` · `getSalesBySaleType` · `getProductProfitReport`)،
// وثمانٍ لا. والأثرُ **مرئيٌّ على شاشةٍ واحدة**:
// `sales_by_classification_report.dart` يبني بطاقتَه من `getSalesBySaleType`
// (محروسة) وقائمتَه المنسدلةَ تحتها من `getSalesInvoicesBySaleType` (لم تكن) —
// فالبطاقةُ لا تطابق صفوفَها.
//
// ⚠️ وتوثيقُ `sales_analytics_dao.dart` كان يقول عكسَ ذلك: إنّ استبعادَ
// الأصلِ «خطأٌ يطرح القيمةَ مرّتين». وهو أقدمُ من الكود المخالف
// (‏`git blame`: التوثيقُ 2026‑07‑13 والحارسُ 2026‑07‑21) — أي وصفُ حالةٍ
// انتهت. صُحِّح مع هذا الإصلاح.
//
// المرساةُ في كلِّ توكيدٍ هنا: **`getSalesAnalytics`** — الدالّةُ التي كانت
// محروسةً منذ البداية. فالمقياسُ ليس رقماً اخترتُه بل اتّفاقُ الثمانيةِ مع
// المرجع.

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int userId;
  late int warehouseId;
  late int productId;
  late int keptCustomerId;
  late int returnedCustomerId;

  // فاتورةٌ سليمةٌ وأخرى مرتجعةٌ كلّيّاً — والفارقُ بينهما فاضحٌ عمداً.
  const keptTotal = 100.0;
  const returnedTotal = 500.0;

  late DateTime from;
  late DateTime to;

  setUp(() async {
    db = AppDatabase.forTesting();
    final now = DateTime.now();
    from = now.subtract(const Duration(days: 2));
    to = now.add(const Duration(days: 2));

    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(name: 'بائع', isSystemRole: const Value(false)),
        );
    userId = await db.createUser(
      username: 'ret_scope_user',
      password: 'test',
      displayName: 'Return Scope User',
      roleId: roleId,
    );
    warehouseId = (await db.getDefaultWarehouse())!.id;

    productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'RET-SCOPE-1',
        name: 'صنفُ الاختبار',
        salePrice: const Value(100.0),
        costPrice: const Value(40.0),
        currentStock: const Value(1000.0),
        trackInventory: const Value(true),
      ),
    );
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 1000.0,
      type: 'in',
      notes: 'seed',
    );

    keptCustomerId = await db.into(db.parties).insert(
          PartiesCompanion.insert(name: 'عميلٌ باقٍ'),
        );
    returnedCustomerId = await db.into(db.parties).insert(
          PartiesCompanion.insert(name: 'عميلٌ مرتجعٌ كلّيّاً'),
        );
  });

  tearDown(() async => db.close());

  Future<int> makeInvoice({
    required String number,
    required double total,
    required int customerId,
  }) =>
      db.createSalesInvoice(
        invoiceNumber: number,
        warehouseId: warehouseId,
        userId: userId,
        customerId: customerId,
        subtotal: total,
        discount: 0.0,
        tax: 0.0,
        total: total,
        paid: total,
        paymentMethod: 'cash',
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: total / 100.0,
            unitPrice: 100.0,
            total: total,
            costPrice: const Value(40.0),
          ),
        ],
      );

  /// يزرع الفاتورتَين ويختم الثانيةَ `'returned'` — وهو **الأثرُ الوحيد** الذي
  /// يتركه مرتجعٌ كامل على تنصيبةٍ مستقلّة: لا صفَّ فاتورةٍ جديدٌ يُكتَب.
  Future<void> seed() async {
    await makeInvoice(
      number: 'RET-KEEP-1',
      total: keptTotal,
      customerId: keptCustomerId,
    );
    final returnedId = await makeInvoice(
      number: 'RET-FULL-1',
      total: returnedTotal,
      customerId: returnedCustomerId,
    );
    await (db.update(db.salesInvoices)
          ..where((s) => s.id.equals(returnedId)))
        .write(const SalesInvoicesCompanion(status: Value('returned')));
  }

  test('المرجعُ `getSalesAnalytics` يستبعدها — وهو مقياسُ بقيّة التوكيدات',
      () async {
    await seed();
    final a = await db.getSalesAnalytics(from, to);
    expect(a.totalSales, keptTotal,
        reason: 'مرساة: الدالّةُ المحروسةُ منذ البداية تعطي ١٠٠ لا ٦٠٠');
    expect(a.invoiceCount, 1);
  });

  test('التجميعاتُ الثماني توافق المرجعَ على استبعاد المرتجع الكامل',
      () async {
    await seed();
    final reference = (await db.getSalesAnalytics(from, to)).totalSales;

    // ١ — الرسمُ اليوميّ
    final daily = await db.getDailySalesForRange(from: from, to: to);
    expect(daily.fold<double>(0, (s, r) => s + r.total), reference,
        reason: 'getDailySalesForRange');

    // ٢ — السلسلةُ الشهريّة
    final monthly = await db.getMonthlyPerformanceSeries(from: from, to: to);
    expect(
        monthly.fold<double>(
            0, (s, r) => s + (r['net_sales'] as num).toDouble()),
        reference,
        reason: 'getMonthlyPerformanceSeries');

    // ٣ — طرقُ الدفع
    final pay = await db.getPaymentMethodStats(from: from, to: to);
    expect(pay.fold<double>(0, (s, r) => s + r.total), reference,
        reason: 'getPaymentMethodStats');

    // ٤ — الأكثرُ مبيعاً (لوحةُ التحليلات)
    final topSelling = await db.getTopSellingProducts(from: from, to: to);
    expect(topSelling.fold<double>(0, (s, r) => s + r.totalSales), reference,
        reason: 'getTopSellingProducts');

    // ٥ — تقريرُ الأكثر مبيعاً
    final topReport = await db.getTopProductsReport(from: from, to: to);
    expect(topReport.fold<double>(0, (s, r) => s + r.totalValue), reference,
        reason: 'getTopProductsReport');

    // ٦ — المبيعاتُ بالتصنيف
    final byCat = await db.getSalesByCategory(from: from, to: to);
    expect(byCat.fold<double>(0, (s, r) => s + r.total), reference,
        reason: 'getSalesByCategory');

    // ٧ — تجميعاتُ العملاء
    final parties = await db.getCustomerPeriodAggregates(from: from, to: to);
    expect(parties.fold<double>(0, (s, r) => s + r.totalValue), reference,
        reason: 'getCustomerPeriodAggregates');

    // ٨ — عدُّ العملاء: المرتجعُ كلّيّاً لا يُعدُّ عميلاً نشطاً.
    expect(await db.getNewCustomersCount(from: from, to: to), 1,
        reason: 'getNewCustomersCount — كان يعدُّ الاثنين');
  });

  test('بطاقةُ تقرير التصنيف تطابق صفوفَها المنسدلة', () async {
    await seed();

    // الشاشةُ `sales_by_classification_report.dart` تبني الاثنين معاً:
    // البطاقةَ من `getSalesBySaleType` والقائمةَ من `getSalesInvoicesBySaleType`.
    final card = await db.getSalesBySaleType(from: from, to: to);
    final cardTotal = card.fold<double>(0, (s, r) => s + r.total);

    final rows = await db.getSalesInvoicesBySaleType(
      saleType: 'default',
      from: from,
      to: to,
    );
    final rowsTotal = rows.fold<double>(0, (s, r) => s + r.total);

    expect(rowsTotal, cardTotal,
        reason: 'البطاقةُ كانت محروسةً والقائمةُ لا — فتعرضان رقمَين مختلفَين '
            'على نفس الشاشة');
    expect(rows.length, 1,
        reason: 'الفاتورةُ المرتجعةُ كلّيّاً لا تظهر في صفوف المبيعات');
  });

  test('المرتجعُ **الجزئيُّ** يبقى بقيمته الكاملة — حارسٌ ضدّ تشديدٍ زائد',
      () async {
    await makeInvoice(
      number: 'RET-KEEP-2',
      total: keptTotal,
      customerId: keptCustomerId,
    );
    final partialId = await makeInvoice(
      number: 'RET-PARTIAL-1',
      total: returnedTotal,
      customerId: returnedCustomerId,
    );
    await (db.update(db.salesInvoices)..where((s) => s.id.equals(partialId)))
        .write(const SalesInvoicesCompanion(status: Value('partial_return')));

    // العقدُ صريحٌ: `partial_return` **ليست** في قائمة الاستبعاد؛ الطرحُ يقع
    // في طبقة التقرير (`clampedReturnedTotal`) لا في الاستعلام.
    const bothTotals = keptTotal + returnedTotal;
    expect((await db.getSalesAnalytics(from, to)).totalSales, bothTotals,
        reason: 'مرساة: المرجعُ يُبقي الجزئيَّ');

    final daily = await db.getDailySalesForRange(from: from, to: to);
    expect(daily.fold<double>(0, (s, r) => s + r.total), bothTotals,
        reason: 'ولو أُضيفت `partial_return` إلى الاستبعاد لطُرحت مرّتين');
  });
}
