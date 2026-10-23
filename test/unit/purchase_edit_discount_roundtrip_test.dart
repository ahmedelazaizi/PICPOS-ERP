// تحريرُ فاتورةٍ مخصومةٍ **لا يخفّض تكلفتَها** — ذهاباً وإياباً.
//
// ═══ 🔴 العطبُ المقيس ═══
//
// المحرّكُ يخزّن تكلفةَ السطر **صافيةً** بعد توزيع الخصم (ح‑1، IAS 2.11)،
// ويستقبل من النموذج تكلفةً **إجماليّةً** وخصمَ مستندٍ يوزّعه بنفسه.
//
// ونموذجُ التحرير القائم يملأ الحقلَين من المخزَّن حرفاً:
//
//     `_discountController.text = invoice.discount`     ← الخصمُ كاملاً
//     `'unitCost': iwv.item.unitCost`                   ← والتكلفةُ **صافية**
//
// فيُعاد توزيعُ الخصم على تكلفةٍ وُزِّع عليها أصلاً. **وكلُّ حفظٍ يخفّضها
// ثانيةً** — ولو لم يُغيَّر حرف.
//
// وأثرُه لا يظهر على الشاشة: الفاتورةُ تبدو سليمة، والرقمُ الذي ينزل هو
// **متوسّطُ تكلفة الصنف** — فيُضخَّم الربحُ في كلّ بيعةٍ تالية، ويردّ
// المرتجعُ أقلَّ ممّا دُفع.
//
// ═══ والعلاجُ عكسٌ دقيق ═══
//
// ‏[resolvePurchaseLineGross] تعيد بناءَ الإجماليّ من الصافي المخزَّن —
// وهي عكسُ [resolvePurchaseLineNets] بالضبط، فالدورةُ تُعيد نفسَ الأرقام.

import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/domain/models/purchase_line_discount.dart';

void main() {
  late AppDatabase db;
  late int supplierId;
  late int warehouseId;
  late int adminId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    warehouseId = (await db.getDefaultWarehouse())!.id;
    supplierId = await db.into(db.parties).insert(
        PartiesCompanion.insert(name: 'مورد', isSupplier: const Value(true)));
    adminId = (await db
            .customSelect("SELECT id FROM users WHERE username = 'admin' LIMIT 1")
            .getSingle())
        .read<int>('id');
  });

  tearDown(() => db.close());

  Future<int> seedProduct(String code) => db.insertProduct(
        ProductsCompanion.insert(
          code: code,
          name: 'صنف $code',
          salePrice: const Value(200.0),
          costPrice: const Value(0.0),
          trackInventory: const Value(true),
        ),
      );

  Future<List<PurchaseInvoiceItem>> linesOf(int invoiceId) =>
      (db.select(db.purchaseInvoiceItems)
            ..where((i) => i.invoiceId.equals(invoiceId))
            ..orderBy([(i) => OrderingTerm(expression: i.id)]))
          .get();

  test('🔴 إعادةُ حفظِ المخزَّن كما هو تخفّض التكلفة — وهذا ما يفعله القديم',
      () async {
    // ⚠️ **هذا الاختبارُ يوثّق ما يقع اليوم**، وهو مقياسُ العلاج: الدورةُ
    // التالية (بالعكس) يجب أن تُعيد ٩٠٫٠ لا ٨٠٫٠.
    final pid = await seedProduct('RT-NAIVE');
    final invoiceId = await db.createPurchaseInvoice(
      supplierId: supplierId,
      warehouseId: warehouseId,
      paid: 0,
      paymentMethod: 'credit',
      discount: 100,
      items: [
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: pid,
          quantity: 10,
          unitCost: 100,
          total: 1000,
        ),
      ],
    );

    final stored = (await linesOf(invoiceId)).single;
    expect(stored.unitCost, closeTo(90, 0.001),
        reason: 'التوزيعُ الأصليُّ: (١٠٠٠ − ١٠٠) ÷ ١٠');

    // وهذا **حرفيّاً** ما يمرّره نموذجُ التحرير القائم: التكلفةُ المخزَّنة
    // (صافية) مع الخصم كاملاً.
    await db.updatePurchaseInvoice(
      invoiceId: invoiceId,
      supplierId: supplierId,
      warehouseId: warehouseId,
      paid: 0,
      paymentMethod: 'credit',
      discount: 100,
      userId: adminId,
      items: [
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: invoiceId,
          productId: pid,
          quantity: 10,
          unitCost: stored.unitCost,
          total: 10 * stored.unitCost,
        ),
      ],
    );

    final after = (await linesOf(invoiceId)).single;
    expect(after.unitCost, closeTo(80, 0.001),
        reason: 'لو صار هذا ٩٠ فقد عولج المحرّكُ — وهذا الاختبارُ يوثّق '
            'السلوكَ القائمَ لا يحرسه');
  });

  test('والعكسُ يُعيد الإجماليَّ فتُغلَق الدورةُ على نفس الأرقام', () async {
    final pid = await seedProduct('RT-FIXED');
    final invoiceId = await db.createPurchaseInvoice(
      supplierId: supplierId,
      warehouseId: warehouseId,
      paid: 0,
      paymentMethod: 'credit',
      discount: 100,
      items: [
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: pid,
          quantity: 10,
          unitCost: 100,
          total: 1000,
        ),
      ],
    );

    final header = await (db.select(db.purchaseInvoices)
          ..where((i) => i.id.equals(invoiceId)))
        .getSingle();
    final stored = await linesOf(invoiceId);

    // ما يجب أن يملأه نموذجُ التحرير: الإجماليُّ المُعاد بناؤه.
    final gross = resolvePurchaseLineGross(
      netPerLine: [for (final l in stored) l.quantity * l.unitCost],
      explicitDiscountPerLine: [for (final l in stored) l.discount],
      documentDiscount: header.discount,
    );

    await db.updatePurchaseInvoice(
      invoiceId: invoiceId,
      supplierId: supplierId,
      warehouseId: warehouseId,
      paid: 0,
      paymentMethod: 'credit',
      discount: header.discount,
      userId: adminId,
      items: [
        for (var i = 0; i < stored.length; i++)
          PurchaseInvoiceItemsCompanion.insert(
            invoiceId: invoiceId,
            productId: stored[i].productId,
            quantity: stored[i].quantity,
            unitCost: gross[i] / stored[i].quantity,
            discount: Value(stored[i].discount),
            total: gross[i],
          ),
      ],
    );

    final after = (await linesOf(invoiceId)).single;
    expect(after.unitCost, closeTo(90, 0.001),
        reason: 'الدورةُ لم تُغلَق — التكلفةُ انزاحت بحفظٍ بلا تغييرِ حرف');

    final headerAfter = await (db.select(db.purchaseInvoices)
          ..where((i) => i.id.equals(invoiceId)))
        .getSingle();
    expect(headerAfter.total, closeTo(header.total, 0.001));
    expect(headerAfter.subtotal, closeTo(header.subtotal, 0.001));
    expect(headerAfter.discount, closeTo(header.discount, 0.001));

    final product = await db.getProductById(pid);
    expect(product!.costPrice, closeTo(90, 0.001),
        reason: 'متوسّطُ التكلفة انزاح — وهو الرقمُ الذي يبقى بعد إغلاق '
            'الشاشة');
  });

  test('وبخصومِ أصنافٍ مختلطةٍ تُغلَق الدورةُ أيضاً', () async {
    final a = await seedProduct('RT-MIX-A');
    final b = await seedProduct('RT-MIX-B');
    final invoiceId = await db.createPurchaseInvoice(
      supplierId: supplierId,
      warehouseId: warehouseId,
      paid: 0,
      paymentMethod: 'credit',
      discount: 100,
      items: [
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: a,
          quantity: 10,
          unitCost: 10,
          discount: const Value(50),
          total: 100,
        ),
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: b,
          quantity: 10,
          unitCost: 90,
          total: 900,
        ),
      ],
    );

    final header = await (db.select(db.purchaseInvoices)
          ..where((i) => i.id.equals(invoiceId)))
        .getSingle();
    final before = await linesOf(invoiceId);

    final gross = resolvePurchaseLineGross(
      netPerLine: [for (final l in before) l.quantity * l.unitCost],
      explicitDiscountPerLine: [for (final l in before) l.discount],
      documentDiscount: header.discount,
    );
    // العكسُ يُعيد الإجماليَّ الأصليَّ: ١٠٠ و٩٠٠.
    expect(gross[0], closeTo(100, 0.01));
    expect(gross[1], closeTo(900, 0.01));

    await db.updatePurchaseInvoice(
      invoiceId: invoiceId,
      supplierId: supplierId,
      warehouseId: warehouseId,
      paid: 0,
      paymentMethod: 'credit',
      discount: header.discount,
      userId: adminId,
      items: [
        for (var i = 0; i < before.length; i++)
          PurchaseInvoiceItemsCompanion.insert(
            invoiceId: invoiceId,
            productId: before[i].productId,
            quantity: before[i].quantity,
            unitCost: gross[i] / before[i].quantity,
            discount: Value(before[i].discount),
            total: gross[i],
          ),
      ],
    );

    final after = await linesOf(invoiceId);
    expect(after[0].unitCost, closeTo(before[0].unitCost, 0.01));
    expect(after[1].unitCost, closeTo(before[1].unitCost, 0.01));
  });
}
