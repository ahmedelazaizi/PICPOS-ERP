// ═══════════════════════════════════════════════════════════════════════════
// مانعُ Go ٢‑٧ — تقييمُ المخزون يجب أن يطابق حسابَ المخزون في الأستاذ
// ═══════════════════════════════════════════════════════════════════════════
//
// ⚠️ **الخارطةُ وصفت العلاجَ خطأً.** قالت «`recalculateProductWAC` تُعيد
// التسعيرَ بلا قيدٍ موازن» — أي أضِف قيداً. والمقيس أنّ حسابَ المخزون
// **مدفوعٌ بالحركات**: كلُّ شراءٍ وبيعٍ وتعديلٍ وإبطالٍ يُرحَّل بتكلفته
// لحظتَها، ولا تقييمَ دوريَّ في المستودع كلِّه. فقيدُ إعادةِ تقييمٍ يُضاعف
// في كلِّ مواضع النداء — كلُّها ترحّل قيدَها أصلاً.
//
// 🔴 والعطبُ الحقيقيّ: الدالّةُ تقسم مجموعَ تكلفةِ **كلِّ وحدةٍ اشتُريت في
// التاريخ** على **عددِ كلِّ وحدةٍ اشتُريت في التاريخ** — أي «متوسّطَ الشراء
// مدى الحياة». وذلك يساوي المتوسّطَ المتحرّك **فقط** ما لم يقع بيعٌ بينهما.
// وأوّلُ بيعةٍ تكسر التطابق، ثمّ يتسرّب الرقمُ الخاطئ إلى تكلفة كلِّ بيعةٍ
// لاحقة (‏`sales_mutations_dao` تجمّد `costPrice` على السطر).
//
// والقياسُ هنا بدالّة المصالحة القائمة `getInventoryGlReconciliation()` —
// وهي المرجعُ الذي يستعمله التطبيقُ نفسُه — لا بحسابٍ يدويٍّ في الاختبار.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int warehouseId;
  late int branchId;
  late int supplierId;
  late int productId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();

    final wh = await db.getDefaultWarehouse();
    warehouseId = wh!.id;
    branchId = wh.branchId ?? 1;

    supplierId = await db.into(db.parties).insert(
          PartiesCompanion.insert(
            name: 'مورّد اختبار التسعير',
            isSupplier: const Value(true),
            isCustomer: const Value(false),
            globalId: const Value('gid-supplier-gowac'),
          ),
        );

    productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'GO-WAC',
        name: 'صنفُ اختبار التسعير',
        salePrice: const Value(40.0),
        costPrice: const Value(0.0),
        trackInventory: const Value(true),
        allowNegativeSale: const Value(true),
      ),
    );
  });

  tearDown(() => db.close());

  Future<void> buy(double qty, double unitCost) async {
    await db.createPurchaseInvoice(
      supplierId: supplierId,
      warehouseId: warehouseId,
      paid: 0.0,
      paymentMethod: 'credit',
      items: [
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: qty,
          unitCost: unitCost,
          total: qty * unitCost,
        ),
      ],
    );
  }

  Future<double> costPrice() async =>
      (await db.getProductById(productId))!.costPrice;

  Future<double> onHand() async =>
      (await db.getProductById(productId))!.currentStock;

  test('التجهيزة: شراءٌ واحدٌ يجعل التقييمَ يطابق الأستاذ', () async {
    await buy(10, 10);
    expect(await costPrice(), closeTo(10.0, 0.001));
    expect(await onHand(), closeTo(10.0, 0.001));

    final rec = await db.getInventoryGlReconciliation();
    expect(rec, isNotNull, reason: 'حسابُ المخزون مزروع');
    expect(rec!.delta, closeTo(0.0, 0.01),
        reason: 'مرساةٌ: بلا بيعٍ يتطابق الطرفان — لو فشلت هنا فالعطبُ '
            'ليس في الصيغة بل في التجهيزة');
  });

  test('شراءٌ ← بيعٌ ← شراءٌ ثمّ إعادةُ حساب: التقييمُ يبقى مطابقاً للأستاذ',
      () async {
    // ١٠ @ ١٠  ⇒ الأستاذ ١٠٠ · الموجود ١٠ · التكلفة ١٠
    await buy(10, 10);

    // بيعُ ٥ بتكلفةٍ ١٠  ⇒ الأستاذ ٥٠ · الموجود ٥ · التكلفة ١٠
    await db.createSalesInvoice(
      invoiceNumber: 'GO-SAL-1',
      warehouseId: warehouseId,
      userId: 1,
      subtotal: 200,
      discount: 0,
      tax: 0,
      total: 200,
      paid: 200,
      paymentMethod: 'نقدي',
      branchId: branchId,
      items: [
        SalesInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: 5,
          unitPrice: 40,
          total: 200,
          sortOrder: const Value(1),
        ),
      ],
    );
    expect(await onHand(), closeTo(5.0, 0.001), reason: 'شرطٌ مسبق');

    // ١٠ @ ٢٠  ⇒ الأستاذ ٢٥٠ · الموجود ١٥ · المتوسّطُ المتحرّك ١٦٫٦٦٧
    await buy(10, 20);
    expect(await onHand(), closeTo(15.0, 0.001));

    final before = await db.getInventoryGlReconciliation();
    expect(before!.delta, closeTo(0.0, 0.01),
        reason: 'مرساةٌ: المتوسّطُ المتحرّك يطابق قبل أن تُستدعى إعادةُ '
            'الحساب — فالعطبُ في إعادة الحساب لا في المسار العاديّ');

    // إعادةُ الحساب — وهي ما يُستدعى عند الإبطال والتعديل والمرتجع.
    await db.recalculateProductWAC(productId);

    // 🔴 المعطوب: (١٠×١٠ + ١٠×٢٠) ÷ ٢٠ = **١٥٫٠** — قسمةٌ على كلِّ ما
    //    اشتُري لا على الموجود ⇒ التقييم ١٥×١٥ = ٢٢٥ مقابل أستاذٍ ٢٥٠،
    //    انحرافٌ **٢٥** بلا قيدٍ ولا خطأ. والرقمُ ١٥ يصير بعدها تكلفةَ كلِّ
    //    بيعةٍ لاحقة.
    final after = await db.getInventoryGlReconciliation();
    expect(after!.delta, closeTo(0.0, 0.01),
        reason: 'إعادةُ الحساب لا يجوز أن تُحرّك التقييمَ عن الأستاذ');
    expect(await costPrice(), closeTo(250.0 / 15.0, 0.001),
        reason: 'التكلفةُ = قيمةُ الدفتر ÷ الموجود، لا متوسّطُ الشراء');
  });

  test('إبطالُ فاتورة شراءٍ يُبقي الطرفَين متطابقَين', () async {
    await buy(10, 10);
    final firstPurchase = (await db.select(db.purchaseInvoices).get()).first;
    await buy(10, 30);

    await db.voidPurchaseInvoice(firstPurchase.id, reason: 'اختبار');

    final rec = await db.getInventoryGlReconciliation();
    expect(rec!.delta, closeTo(0.0, 0.01),
        reason: 'الإبطالُ يعكس القيدَ ويستدعي إعادةَ الحساب — والطرفان '
            'يجب أن يبقيا متطابقَين بعده');
  });
}
