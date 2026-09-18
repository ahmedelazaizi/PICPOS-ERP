// خصمٌ **لكلّ صنف** — قرارُ المالك 2026-09-18 على تصميم فاتورة المشتريات.
//
// ═══ ما كان ═══
//
// للفاتورة خصمٌ واحدٌ على **المستند**، يوزّعه المحرّكُ على السطور **نسبةً
// إلى قيمتها** (`discountFactor = (subtotal - discount) / subtotal`) قبل أن
// يصل السطرَ المخزَّنَ وحركةَ المخزون ومتوسّطَ التكلفة. وهذا ما يجعل متوسّطَ
// التكلفة تكلفةً حقيقيّةً ويمنع مرتجعاً من ردّ أكثرَ ممّا دُفع.
//
// و`PurchaseInvoiceItems.discount` عمودٌ قائمٌ **بلا كاتب** — وله **قارئ**:
// `getPurchaseReturnItemDetails` يقسّطه بنسبة المرتجَع ويطبعه على مستند
// المرتجع. فهو يطبع صفراً دائماً.
//
// ═══ والقرارُ يغيّر التوزيعَ لا المجموع ═══
//
// خصمان صريحان مجموعُهما = خصمُ المستند يعطيان **نفسَ الإجماليّ** وتوزيعاً
// مختلفاً: التوزيعُ النسبيُّ يعطي كلَّ سطرٍ حصّةً بقيمته، والصريحُ يعطيه ما
// كتبه المستخدمُ بالضبط. والفرقُ يقع في **متوسّط تكلفة كلّ صنف** — وهو ما
// يُقرأ في تقييم المخزون وفي المرتجع.
//
// ⚠️ **والقاعدةُ الحاكمةُ: الخصمُ يصل التكلفةَ مرّةً واحدةً بالضبط.** فلو
// حُمل السطرُ خصمَه الصريحَ **و** ضُرب في معامل التوزيع لطُبِّق مرّتَين —
// وتكلفةٌ أقلُّ من الحقيقة تُضخّم الربحَ في كلّ بيعةٍ تاليةٍ من هذا الصنف.

import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
  });

  tearDown(() => db.close());

  Future<int> seedSupplier() => db.into(db.parties).insert(
      PartiesCompanion.insert(name: 'مورد الخصم', isSupplier: const Value(true)));

  Future<int> seedProduct(String code) => db.insertProduct(
        ProductsCompanion.insert(
          code: code,
          name: 'صنف $code',
          salePrice: const Value(150.0),
          costPrice: const Value(0.0),
          trackInventory: const Value(true),
        ),
      );

  Future<List<PurchaseInvoiceItem>> linesOf(int invoiceId) =>
      (db.select(db.purchaseInvoiceItems)
            ..where((i) => i.invoiceId.equals(invoiceId))
            ..orderBy([(i) => OrderingTerm(expression: i.id)]))
          .get();

  test('خصمان صريحان يصلان السطرَ كما كُتبا — لا موزَّعَين بالقيمة', () async {
    final warehouseId = (await db.getDefaultWarehouse())!.id;
    final supplierId = await seedSupplier();
    final cheap = await seedProduct('DISC-CHEAP');
    final pricey = await seedProduct('DISC-PRICEY');

    // سطران: ١٠×١٠ = ١٠٠ و ١٠×٩٠ = ٩٠٠ ⇒ المجموع ١٠٠٠.
    // وخصمان صريحان: ٥٠ على الرخيص و٥٠ على الغالي ⇒ خصمُ المستند ١٠٠.
    //
    // ⚠️ **والتوزيعُ النسبيُّ كان سيعطي ١٠ و٩٠** — فالفرقُ في تكلفة الصنف
    // الرخيص أربعةُ أضعاف.
    final invoiceId = await db.createPurchaseInvoice(
      supplierId: supplierId,
      warehouseId: warehouseId,
      paid: 0.0,
      discount: 100.0,
      items: [
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: cheap,
          quantity: 10.0,
          unitCost: 10.0,
          discount: const Value(50.0),
          total: 100.0,
        ),
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: pricey,
          quantity: 10.0,
          unitCost: 90.0,
          discount: const Value(50.0),
          total: 900.0,
        ),
      ],
    );

    final lines = await linesOf(invoiceId);
    expect(lines, hasLength(2));

    // الرخيص: (١٠×١٠ − ٥٠) ÷ ١٠ = ٥.٠ للوحدة
    expect(lines[0].unitCost, closeTo(5.0, 0.001),
        reason: 'خصمُ السطر الصريحُ لم يصل تكلفتَه — التوزيعُ النسبيُّ '
            'كان سيعطي ٩.٠');
    // الغالي: (١٠×٩٠ − ٥٠) ÷ ١٠ = ٨٥.٠
    expect(lines[1].unitCost, closeTo(85.0, 0.001),
        reason: 'التوزيعُ النسبيُّ كان سيعطي ٨١.٠');

    // والعمودُ نفسُه مكتوبٌ — له قارئٌ في طباعة المرتجع.
    expect(lines[0].discount, closeTo(50.0, 0.001));
    expect(lines[1].discount, closeTo(50.0, 0.001));
  });

  test('ومتوسّطُ التكلفة يقرأ التكلفةَ الصافيةَ لا الإجماليّة', () async {
    // ⚠️ **وهذا هو الأثرُ الذي يبقى بعد إغلاق الشاشة.** تكلفةٌ أقلُّ من
    // الحقيقة تُضخّم الربحَ في كلّ بيعةٍ تاليةٍ من هذا الصنف.
    final warehouseId = (await db.getDefaultWarehouse())!.id;
    final supplierId = await seedSupplier();
    final pid = await seedProduct('DISC-WAC');

    await db.createPurchaseInvoice(
      supplierId: supplierId,
      warehouseId: warehouseId,
      paid: 0.0,
      discount: 50.0,
      items: [
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: pid,
          quantity: 10.0,
          unitCost: 10.0,
          discount: const Value(50.0),
          total: 100.0,
        ),
      ],
    );

    final product = await db.getProductById(pid);
    expect(product!.costPrice, closeTo(5.0, 0.001),
        reason: 'متوسّطُ التكلفة لم يقرأ الخصمَ — تقييمُ المخزون مضخَّم');
  });

  test('وبلا خصومٍ على السطور يبقى التوزيعُ النسبيُّ كما هو', () async {
    // ⚠️ **مرساةُ عدمِ الارتداد.** المنادون القدامى (الصندوقُ الصادر وإعاداتُ
    // الـAPI) يمرّرون خصمَ مستندٍ بلا خصومِ سطور، فسلوكُهم يجب أن يبقى
    // حرفيّاً كما هو — وإلّا غيّر هذا الإصلاحُ تكلفةَ كلّ فاتورةٍ قديمة.
    final warehouseId = (await db.getDefaultWarehouse())!.id;
    final supplierId = await seedSupplier();
    final cheap = await seedProduct('LEGACY-CHEAP');
    final pricey = await seedProduct('LEGACY-PRICEY');

    final invoiceId = await db.createPurchaseInvoice(
      supplierId: supplierId,
      warehouseId: warehouseId,
      paid: 0.0,
      discount: 100.0,
      items: [
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: cheap,
          quantity: 10.0,
          unitCost: 10.0,
          total: 100.0,
        ),
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: pricey,
          quantity: 10.0,
          unitCost: 90.0,
          total: 900.0,
        ),
      ],
    );

    final lines = await linesOf(invoiceId);
    // نسبيّاً: عاملٌ = (١٠٠٠ − ١٠٠) ÷ ١٠٠٠ = ٠٫٩
    expect(lines[0].unitCost, closeTo(9.0, 0.001));
    expect(lines[1].unitCost, closeTo(81.0, 0.001));
  });

  test('وخصمٌ صريحٌ أقلُّ من خصم المستند يوزّع الباقيَ نسبيّاً', () async {
    // حالةٌ مختلطة: المستخدمُ خصم ٥٠ على سطرٍ وأعطى المستندَ خصماً ١٠٠،
    // فالباقي ٥٠ يوزَّع على ما بقي من القيمة.
    final warehouseId = (await db.getDefaultWarehouse())!.id;
    final supplierId = await seedSupplier();
    final a = await seedProduct('MIX-A');
    final b = await seedProduct('MIX-B');

    final invoiceId = await db.createPurchaseInvoice(
      supplierId: supplierId,
      warehouseId: warehouseId,
      paid: 0.0,
      discount: 100.0,
      items: [
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: a,
          quantity: 10.0,
          unitCost: 10.0,
          discount: const Value(50.0),
          total: 100.0,
        ),
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: b,
          quantity: 10.0,
          unitCost: 90.0,
          total: 900.0,
        ),
      ],
    );

    final lines = await linesOf(invoiceId);
    // القاعدةُ واحدةٌ بلا فرعٍ خاصّ: الصريحُ أوّلاً ثمّ الباقي على
    // **ما بقي من قيمة السطور كلِّها** — لا على غير المخصومة وحدَها.
    // فالباقي ٥٠ على أساسٍ (١٠٠−٥٠) + ٩٠٠ = ٩٥٠ ⇒ معاملٌ = ٩٠٠/٩٥٠.
    //
    // ⚠️ وخصمُ المستند تنازلٌ على المستند، فمسُّه سطراً أخذ خصمَه
    // الخاصَّ **صوابٌ**: هو تنازلٌ ثانٍ فوق الأوّل.
    expect(lines[0].unitCost, closeTo(4.74, 0.01));
    expect(lines[1].unitCost, closeTo(85.26, 0.01));
  });
}
