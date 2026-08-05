// ═══════════════════════════════════════════════════════════════════════════
// تقرير المبيعات — الكارت والجدول كانوا بيقيسوا مجموعتين مختلفتين.
// ═══════════════════════════════════════════════════════════════════════════
//
// الشاشة بتنده مسارين لنفس الفترة:
//   • البطاقة  → getSalesAnalytics (sales_analytics_dao)
//   • الجدول   → getSalesByDateRange (sales_dao)
//
// والاتنين بيستثنوا مجموعتين مختلفتين:
//   الكارت:  is_deleted = 0
//            AND (sale_type IS NULL OR sale_type != 'return')
//            AND status NOT IN ('returned', 'cancelled', 'voided')
//   الجدول:  is_deleted = 0        ← وبس
//
// فالكارت بيقول ١٠٠٬٠٠٠ والمستخدم بيصدّر Excel ويجمع عمود الإجمالي فيطلّع
// ١٠٨٬٠٠٠. مفيش رقم فيهم غلط لوحده — الغلط إن الاتنين بيجاوبوا سؤالين
// مختلفين تحت عنوان واحد.
//
// ── ليه معامل اختياري لا تغيير دلالة ─────────────────────────────────────
// getSalesByDateRange **مشتركة**: returns_repository_impl بينديها عشان يلاقي
// الفواتير المتاحة للمرتجع (ومحتاج يشوف المكتملة)، و tax_report_screen بينديها
// لقائمة الضريبة التفصيلية. تغيير دلالتها عامةً كان هيكسر مسار المرتجعات.
// فالاستثناء اختياري (`revenueOnly`) وتقرير المبيعات وحده بيطلبه.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int warehouseId;

  final from = DateTime(2026, 8, 1);
  final to = DateTime(2026, 8, 31);

  Future<void> invoice({
    required String number,
    required double total,
    String saleType = 'default',
    String status = 'completed',
    bool isDeleted = false,
  }) =>
      db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
            invoiceNumber: number,
            warehouseId: warehouseId,
            userId: 1,
            invoiceDate: DateTime(2026, 8, 10),
            total: Value(total),
            paid: Value(total),
            saleType: Value(saleType),
            status: Value(status),
            isDeleted: Value(isDeleted),
          ));

  setUp(() async {
    db = AppDatabase.forTesting();
    warehouseId = await db
        .into(db.warehouses)
        .insert(WarehousesCompanion.insert(name: 'مخزن'));

    // بيعة عادية — دي وحدها اللي المفروض تتحسب إيراداً.
    await invoice(number: 'OK', total: 100000);
    // ملغية: الكارت بيستثنيها والجدول كان بيعرضها.
    await invoice(number: 'CANCELLED', total: 5000, status: 'cancelled');
    // أصل اترجّع: الكارت بيستثنيه (المرتجع بيتطرح لوحده).
    await invoice(number: 'RETURNED', total: 3000, status: 'returned');
    // فاتورة مرتجع (شكل جديد: إجمالي موجب + saleType='return').
    await invoice(number: 'RET-DOC', total: 2000, saleType: 'return');
    // محذوفة ناعماً: الاتنين بيستثنوها أصلاً.
    await invoice(number: 'DELETED', total: 9000, isDeleted: true);
  });

  tearDown(() => db.close());

  test('الضابط: الكارت بيقيس البيعة العادية وحدها', () async {
    final card = await db.getSalesAnalytics(from, to);
    expect(card.totalSales, 100000);
  });

  test('جمع عمود الجدول == رقم الكارت', () async {
    final card = await db.getSalesAnalytics(from, to);
    final rows = await db.getSalesByDateRange(from, to, revenueOnly: true);
    final tableTotal = rows.fold<double>(0, (s, r) => s + r.total);
    expect(tableTotal, card.totalSales,
        reason: 'الكارت ١٠٠٬٠٠٠ وجمع Excel كان ١٠٨٬٠٠٠');
    expect(rows.map((r) => r.invoiceNumber), ['OK']);
  });

  test('كل صنف مستبعَد بيتشال بسببه', () async {
    final rows = await db.getSalesByDateRange(from, to, revenueOnly: true);
    final numbers = rows.map((r) => r.invoiceNumber).toSet();
    expect(numbers.contains('CANCELLED'), isFalse, reason: 'ملغية');
    expect(numbers.contains('RETURNED'), isFalse, reason: 'أصل اترجّع');
    expect(numbers.contains('RET-DOC'), isFalse, reason: 'مستند مرتجع');
    expect(numbers.contains('DELETED'), isFalse, reason: 'محذوفة ناعماً');
  });

  test('السلوك الافتراضي غير متغيّر — مسار المرتجعات لسه بيشوف المكتملة',
      () async {
    // returns_repository_impl بيعتمد على ده عشان يلاقي فاتورة يرجّعها.
    final rows = await db.getSalesByDateRange(from, to);
    final numbers = rows.map((r) => r.invoiceNumber).toSet();
    expect(numbers.contains('OK'), isTrue);
    expect(numbers.contains('CANCELLED'), isTrue,
        reason: 'من غير revenueOnly مفيش استثناء جديد — ولا كسر لمُنادٍ قائم');
    expect(numbers.contains('RETURNED'), isTrue);
    expect(numbers.contains('DELETED'), isFalse,
        reason: 'المحذوف ناعماً كان مستبعَداً قبل التغيير وبعده');
  });
}
