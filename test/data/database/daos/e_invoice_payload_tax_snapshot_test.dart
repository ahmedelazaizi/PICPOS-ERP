// ═══════════════════════════════════════════════════════════════════════════
// حمولةُ المستند الضريبيّ تُبنى من **لقطة البند**، لا من المنتج اليوم.
// ═══════════════════════════════════════════════════════════════════════════
//
// ═══ فئةُ العطب ═══
//
// `sales_invoice_items` يحمل عموداً خاصّاً به: `tax_rate` و`tax_amount` —
// لقطةً وقتَ البيع، بنفس مبدأ `cost_price` و`due_date` و`rounding_adjustment`
// المكتوبِ في المخطَّط: **لقطةٌ وقتَ الإصدار لا حسابٌ حيّ**.
//
// لكنّ `buildInvoicePayload` كان يقرأ `product.tax_rate` **الحيّة** ويحسب
// `taxAmount = item.total * product.taxRate / 100`. فتعديلُ ضريبةِ صنفٍ اليومَ
// — أو تغييرُ الدولة لنسبة ض.ق.م — يُعيد إقرارَ **كلِّ فاتورةٍ قديمة** لذلك
// الصنف بنسبةٍ لم يدفعها العميلُ قطّ.
//
// والأثرُ ضريبيٌّ لا تجميليّ: ما يصل المصلحةَ يخالف ما على الإيصال الذي بيد
// العميل، وما قُيِّد في الأستاذ.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int saleId;
  late int productId;

  setUp(() async {
    db = AppDatabase.forTesting();

    await db.saveEInvoiceConfig(
      platform: 'eta',
      clientId: 'id',
      clientSecret: 'secret',
      registrationNumber: '100-200-300',
      isEnabled: true,
    );

    final branchId = await db.into(db.branches).insert(
        BranchesCompanion.insert(name: 'فرع', globalId: const Value('br-tax')));
    final whId = await db.into(db.warehouses).insert(WarehousesCompanion.insert(
        name: 'مخزن',
        branchId: Value(branchId),
        globalId: const Value('wh-tax')));

    productId = await db.into(db.products).insert(ProductsCompanion.insert(
          code: 'P-TAX',
          name: 'صنفٌ ضريبيّ',
          // الضريبةُ الحيّةُ على المنتج **وقتَ البيع**.
          taxRate: const Value(5),
        ));

    saleId = await db.into(db.salesInvoices).insert(
        SalesInvoicesCompanion.insert(
      invoiceNumber: 'INV-TAX-1',
      warehouseId: whId,
      userId: 1,
      invoiceDate: DateTime(2026, 6, 1),
      total: const Value(105),
      subtotal: const Value(100),
      tax: const Value(5),
    ));

    // بندٌ بلقطةِ ضريبتِه: ٥٪ على مئة ⇒ خمسة.
    await db.into(db.salesInvoiceItems).insert(
        SalesInvoiceItemsCompanion.insert(
      invoiceId: saleId,
      productId: productId,
      quantity: 1,
      unitPrice: 100,
      total: 100,
      taxRate: const Value(5),
      taxAmount: const Value(5),
    ));
  });

  tearDown(() => db.close());

  // 🔴 مرساةٌ غيرُ دائريّة: قبل أيّ تعديلٍ تُقرأ اللقطةُ صحيحةً — فسقوطُ
  //    التوكيد بعد التعديل أثرُ التعديل لا عطبٌ في البذر.
  test('مرساة: قبل تعديل المنتج تُقرأ النسبةُ ٥٪', () async {
    final payload = await db.buildInvoicePayload(saleId, 'eta');
    final items = payload['items'] as List;

    expect(items, hasLength(1));
    expect((items.first as Map)['taxRate'], 5.0);
  });

  test('🔴 تعديلُ ضريبة المنتج لا يُعيد إقرارَ فاتورةٍ قديمة', () async {
    // الدولةُ رفعت ض.ق.م، أو صُحِّح تصنيفُ الصنف — بعد البيع بشهور.
    await (db.update(db.products)..where((p) => p.id.equals(productId)))
        .write(const ProductsCompanion(taxRate: Value(25)));

    final payload = await db.buildInvoicePayload(saleId, 'eta');
    final item = (payload['items'] as List).first as Map;

    expect(item['taxRate'], 5.0,
        reason: 'الفاتورةُ حُرِّرت بـ٥٪ ودفع العميلُ ٥٪ — فتُقدَّم بـ٥٪');
    expect(item['taxAmount'], 5.0,
        reason: 'مبلغُ الضريبة لقطةُ البند لا حاصلُ ضربٍ بنسبةِ اليوم');
  });

  test('🔴 والمقدَّمُ يطابق ما قُيِّد على الفاتورة نفسِها', () async {
    await (db.update(db.products)..where((p) => p.id.equals(productId)))
        .write(const ProductsCompanion(taxRate: Value(25)));

    final payload = await db.buildInvoicePayload(saleId, 'eta');
    final items = (payload['items'] as List).cast<Map>();
    final lineTax = items.fold<double>(
        0, (sum, m) => sum + ((m['taxAmount'] as num?)?.toDouble() ?? 0));

    expect(lineTax, closeTo(payload['tax'] as double, 0.001),
        reason: 'مجموعُ ضرائب البنود يجب أن يساوي ضريبةَ الفاتورة المقدَّمة — '
            'وإلّا فالمستندُ يناقض نفسَه');
  });
}
