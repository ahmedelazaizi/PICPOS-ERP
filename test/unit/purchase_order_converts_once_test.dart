// أمرُ شراءٍ واحدٌ ⇒ **فاتورةٌ واحدة**.
//
// ═══ لماذا يُقاس الآن ═══
//
// قرارُ المالك 2026-09-18 على تصميم فاتورة المشتريات: **الاتّجاهُ الجديد** —
// من داخل الفاتورة ← اختَر أمرَ شراءٍ لسحب بنوده. والقائمُ اليومَ عكسُه:
// زرٌّ على شاشة الأوامر يحوّل الأمرَ إلى فاتورة.
//
// فصار للأمر **مدخلان** إلى نفس الحدث. ولو لم يكن الاستهلاكُ محروساً
// لأنتجَا فاتورتَين بنفس البضاعة:
//
//   • المخزونُ يدخل **مرّتَين**
//   • ومتوسّطُ التكلفة يُحسَب على كمّيّةٍ ضِعفَ الحقيقة
//   • وذمّةُ المورّد تُقيَّد مرّتَين
//
// 🔴 **والحارسُ ناقصٌ أصلاً**: `convertPOToInvoice` يرفض الأمرَ الملغى وحدَه
// ولا يسأل `convertedToInvoiceId`. وشاشةُ الأوامر تخفي الزرَّ بعد التحويل
// (الحالةُ تصير `received`)، فالمنعُ **رسمٌ لا قاعدة** — وأيُّ منادٍ آخرَ
// يمرّ: حالةُ الاستعمال العامّة، ومدخلُ الفاتورة الجديد.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int supplierId;
  late int warehouseId;
  late int productId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    warehouseId = (await db.getDefaultWarehouse())!.id;
    supplierId = await db.into(db.parties).insert(
        PartiesCompanion.insert(name: 'مورد', isSupplier: const Value(true)));
    productId = await db.insertProduct(ProductsCompanion.insert(
      code: 'PO-ONCE',
      name: 'صنف الأمر',
      salePrice: const Value(150.0),
      costPrice: const Value(0.0),
      trackInventory: const Value(true),
    ));
  });

  tearDown(() => db.close());

  Future<int> seedOrder() => db.createPurchaseOrder(
        supplierId: supplierId,
        warehouseId: warehouseId,
        orderDate: DateTime(2026, 9, 1),
        items: [
          PurchaseOrderItemsCompanion.insert(
            orderId: 0,
            productId: productId,
            quantity: 10,
            unitCost: 40,
            total: 400,
          ),
        ],
      );

  Future<double> stockOf(int pid) async {
    final p = await db.getProductById(pid);
    return p?.currentStock ?? 0;
  }

  test('تحويلٌ واحدٌ يُدخل البضاعةَ مرّةً واحدة', () async {
    final orderId = await seedOrder();
    await db.convertPOToInvoice(orderId);
    expect(await stockOf(productId), closeTo(10, 0.001));
  });

  test('🔴 وتحويلٌ ثانٍ للأمر نفسِه يُرفَض — لا يُدخلها ثانيةً', () async {
    final orderId = await seedOrder();
    await db.convertPOToInvoice(orderId);

    await expectLater(
      db.convertPOToInvoice(orderId),
      throwsA(isA<Exception>()),
      reason: 'أمرٌ مستهلَكٌ يُحوَّل ثانيةً — بضاعةٌ تدخل مرّتَين وذمّةٌ '
          'تُقيَّد مرّتَين',
    );
    expect(await stockOf(productId), closeTo(10, 0.001),
        reason: 'المخزونُ تحرّك في المحاولة المرفوضة');
  });

  test('ولا تُنشأ فاتورةٌ ثانيةٌ عن الأمر نفسِه', () async {
    final orderId = await seedOrder();
    await db.convertPOToInvoice(orderId);
    try {
      await db.convertPOToInvoice(orderId);
    } catch (_) {/* مقيسٌ في الاختبار السابق */}

    final invoices = await db.select(db.purchaseInvoices).get();
    expect(invoices, hasLength(1),
        reason: 'فاتورتان عن أمرٍ واحدٍ — ومصالحةُ المخزون لن تفرّق بينهما');
  });

  test('والرابطُ يُكتَب على الأمر — وهو ما يُسأل عنه', () async {
    final orderId = await seedOrder();
    final invoiceId = await db.convertPOToInvoice(orderId);
    final order = await db.getPurchaseOrderById(orderId);
    expect(order!.convertedToInvoiceId, invoiceId);
    expect(order.status, 'received');
  });

  test('وأمرٌ ملغىً يبقى مرفوضاً كما كان', () async {
    final orderId = await seedOrder();
    await db.updatePurchaseOrderStatus(orderId, 'cancelled');
    await expectLater(
        db.convertPOToInvoice(orderId), throwsA(isA<Exception>()));
  });

  // ═══ المدخلُ الجديد: من داخل الفاتورة ═══════════════════════════════════

  Future<int> invoiceFromOrder(int? orderId) => db.createPurchaseInvoice(
        supplierId: supplierId,
        warehouseId: warehouseId,
        paid: 0,
        paymentMethod: 'credit',
        sourceOrderId: orderId,
        items: [
          PurchaseInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 10,
            unitCost: 40,
            total: 400,
          ),
        ],
      );

  test('فاتورةٌ تربط أمراً تستهلكه — فلا يبقى مفتوحاً بعد دخول بضاعته',
      () async {
    final orderId = await seedOrder();
    final invoiceId = await invoiceFromOrder(orderId);

    final order = await db.getPurchaseOrderById(orderId);
    expect(order!.convertedToInvoiceId, invoiceId,
        reason: 'الأمرُ بقي مفتوحاً وبضاعتُه دخلت — يحوّله أحدٌ ثانيةً '
            'فتدخل مرّتَين');
    expect(order.status, 'received');
    expect(order.receivedAt, isNotNull,
        reason: 'تاريخُ الاستلام هو ما تُقاس عليه «الالتزام بمواعيد التوريد»');
  });

  test('ثمّ يُرفَض تحويلُه من شاشة الأوامر — المدخلان يقرآن نفسَ القاعدة',
      () async {
    final orderId = await seedOrder();
    await invoiceFromOrder(orderId);

    await expectLater(db.convertPOToInvoice(orderId), throwsA(isA<Exception>()),
        reason: 'المدخلُ الآخرُ لا يرى ما استهلكه الأوّل');
    expect(await stockOf(productId), closeTo(10, 0.001));
  });

  test('وأمرٌ مستهلَكٌ لا يُربَط بفاتورةٍ ثانية', () async {
    final orderId = await seedOrder();
    await invoiceFromOrder(orderId);

    await expectLater(invoiceFromOrder(orderId), throwsA(isA<Exception>()));
    // ⚠️ **والرفضُ قبل أن يتحرّك شيء**: لو وقع بعد إدخال البضاعة لاعتمد
    // على تراجع المعاملة وحدَه.
    expect(await stockOf(productId), closeTo(10, 0.001));
    expect(await db.select(db.purchaseInvoices).get(), hasLength(1));
  });

  test('وفاتورةٌ بلا أمرٍ لا تلمس أمراً — السلوكُ القديم كما هو', () async {
    final orderId = await seedOrder();
    await invoiceFromOrder(null);

    final order = await db.getPurchaseOrderById(orderId);
    expect(order!.convertedToInvoiceId, isNull,
        reason: 'فاتورةٌ عاديّةٌ ختمت أمراً لا علاقةَ لها به');
    expect(order.status, 'draft');
  });
}
