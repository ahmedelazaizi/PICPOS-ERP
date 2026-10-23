// ═══════════════════════════════════════════════════════════════════════════
// إلغاءُ مرتجع المبيعات يعكس القيدَ ولا يعكس المخزون
// ═══════════════════════════════════════════════════════════════════════════
//
// `cancelSalesReturn` (‏`journal_entry_factory.dart`) يعكس ثلاثةَ أشياء:
// المخزون · حركاتِ الخزنة · رصيدَ العميل. الاثنان الأخيران يستعلمان بمرجع
// `'sales_return'`، والأولُ وحدَه يستعلم بـ`'sales_invoice'`.
//
// والمسارُ الرئيسيُّ للمرتجعات (`ReturnsRepositoryImpl.processSalesReturn` —
// وهو ما تناديه شاشةُ «مرتجع المبيعات» ووضعُ المرتجع في نقطة البيع) يكتب
// حركةَ المخزون بمرجع `'sales_return'`.
//
// ⚠️ (2026-09-02) كانت التجهيزةُ هنا تنادي `ProcessSalesReturnUseCase` وتصفها
// «ما تناديه الشاشة» — وهي كانت كوداً ميّتاً بلا مُنادٍ في `lib`. الاختبارُ
// كان أخضرَ لسببٍ صحيحٍ بالصدفة (المرجعُ المكتوبُ واحد)، والآن ينادي المسارَ
// الحيَّ نفسَه — فيلزمه ورديّةٌ مفتوحة (ح‑١: لا صرفَ نقديٍّ بلا ورديّة).
// فالحلقةُ **لا تدور إطلاقاً**: القيدُ ينعكس والنقديةُ ترجع ورصيدُ العميل
// يُعدَّل، والبضاعةُ تفضل في المخزون. ربحٌ وهميّ وجردٌ لا يطابق الرفّ.
//
// (‏المرتجعُ السريع من البيع السريع — `sales_mutations_dao.dart` — يكتب
//  `'sales_invoice'` فعلاً، فهو المسارُ الوحيد الذي كان يعمل. الإصلاحُ يجب
//  أن يغطّي الاثنين معاً.)
//
// وحتى في المسار الذي كان يعمل، الإلغاءُ كان يعدّل `products.current_stock`
// يدوياً ويحذف صفَّ الحركة — فلا يلمس `inventory_balances` إطلاقاً. فرصيدُ
// المخزن يفضل منتفخاً، ويضيع أثرُ العملية من كشف الحركة.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/entities/product_entity.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late int userId;
  late int warehouseId;
  late int productId;
  late int invoiceId;
  late int invoiceItemId;

  /// رصيدُ المخزن للصنف — غيرُ `products.current_stock` تماماً.
  Future<double> warehouseBalance() async {
    final row = await (db.select(db.inventoryBalances)
          ..where((t) =>
              t.productId.equals(productId) &
              t.warehouseId.equals(warehouseId)))
        .getSingleOrNull();
    return row?.quantity ?? 0;
  }

  Future<double> productStock() async =>
      (await db.getProductById(productId))!.currentStock;

  /// رصيدُ الخزنة النقدية — نفسُ الخزنة التي يسحب منها المرتجعُ النقديّ.
  Future<double> cashSafeBalance() async =>
      (await db.getDefaultSafeByType('cash'))!.balance;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );

    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(name: 'كاشير', isSystemRole: const Value(false)),
        );
    userId = await db.createUser(
      username: 'cancel_ret',
      password: 'test123',
      displayName: 'Cancel Tester',
      roleId: roleId,
    );
    warehouseId = (await db.getDefaultWarehouse())!.id;
    // ح‑١: المسارُ الحيُّ يرفض الردَّ النقديَّ كلَّه بلا ورديّةٍ مفتوحة.
    await db.openShift(userId, 0);

    productId = await db.insertProduct(ProductsCompanion.insert(
      code: 'CR-P1',
      name: 'صنف الإلغاء',
      salePrice: const Value(100.0),
      costPrice: const Value(60.0),
      trackInventory: const Value(true),
    ));
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 50.0,
      type: 'in',
      unitCost: 60.0,
      notes: 'رصيدٌ افتتاحيّ',
    );

    invoiceId = await db.createSalesInvoice(
      invoiceNumber: 'INV-CR-001',
      warehouseId: warehouseId,
      userId: userId,
      subtotal: 500.0,
      discount: 0.0,
      tax: 0.0,
      total: 500.0,
      paid: 500.0,
      paymentMethod: 'cash',
      items: [
        SalesInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: 5.0,
          unitPrice: 100.0,
          total: 500.0,
          costPrice: const Value(60.0),
        ),
      ],
    );
    invoiceItemId = (await db.getSalesInvoiceItems(invoiceId)).first.id;
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  /// يرجّع ٥ وحداتٍ بالمسار الرئيسيّ — **عينُ** ما تناديه شاشةُ المردودات
  /// (`sales_return_provider.processReturn`) ووضعُ المرتجع في نقطة البيع.
  Future<void> processReturn() async {
    final p = (await db.getProductById(productId))!;
    final ok = await container.read(returnsRepositoryProvider).processSalesReturn(
      invoice: (await db.getSalesInvoiceById(invoiceId))!,
      returnQuantities: {invoiceItemId: 5},
      productCache: {
        productId: ProductEntity(
          id: p.id,
          name: p.name,
          code: p.code,
          salePrice: p.salePrice,
          costPrice: p.costPrice,
          currentStock: p.currentStock,
          minStock: p.minStock,
          trackInventory: p.trackInventory,
        ),
      },
      reason: 'اختبار الإلغاء',
      userId: userId,
      userName: 'Cancel Tester',
      isFullReturn: true,
    );
    expect(ok, isTrue, reason: 'تجهيزة: المرتجع لازم ينجح');
  }

  Future<void> cancelReturn() async {
    final invoice = (await db.getSalesInvoiceById(invoiceId))!;
    await container.read(returnsRepositoryProvider).cancelSalesReturn(
          invoice: invoice,
          userId: userId,
          userName: 'Cancel Tester',
        );
  }

  test('ضابط: المرتجع نفسه بيرجّع البضاعة للمخزون وللمخزن', () async {
    final stockAfterSale = await productStock();
    final whAfterSale = await warehouseBalance();

    await processReturn();

    expect(await productStock(), closeTo(stockAfterSale + 5, 0.001));
    expect(await warehouseBalance(), closeTo(whAfterSale + 5, 0.001));
  });

  test('إلغاءُ المرتجع بيرجّع المخزون لما كان عليه بعد البيع', () async {
    final stockAfterSale = await productStock();
    await processReturn();
    await cancelReturn();

    expect(
      await productStock(),
      closeTo(stockAfterSale, 0.001),
      reason: 'الحلقةُ تستعلم بـ«sales_invoice» بينما المسارَ الرئيسيَّ يكتب '
          '«sales_return»، فلا تدور أصلاً: البضاعةُ ترجع للعميل والمخزونُ '
          'يفضل منتفخاً بـ٥ وحدات — وقيمتُها ٣٠٠ بتكلفة ٦٠.',
    );
  });

  test('وكذلك رصيدُ المخزن — لا `current_stock` وحدَه', () async {
    final whAfterSale = await warehouseBalance();
    await processReturn();
    await cancelReturn();

    expect(
      await warehouseBalance(),
      closeTo(whAfterSale, 0.001),
      reason: 'الإلغاء كان يعدّل products.current_stock يدوياً ويحذف صفَّ '
          'الحركة، فلا يلمس inventory_balances — فينفصل رصيدُ المخزن عن '
          'رصيد الصنف حتى في المسار الذي كان يعمل.',
    );
  });

  test('الإلغاء يترك أثراً في كشف الحركة — لا يمحو التاريخ', () async {
    await processReturn();
    await cancelReturn();

    final moves = await (db.select(db.stockMovements)
          ..where((t) => t.productId.equals(productId)))
        .get();

    expect(
      moves.where((m) => m.movementType == 'return'), isNotEmpty,
      reason: 'حذفُ صفِّ حركة المرتجع يمحو الدليلَ على أن المرتجع حصل أصلاً؛ '
          'المراجعُ يرى بضاعةً رجعت للرفّ بلا سببٍ مسجَّل.',
    );
    expect(
      moves.where((m) => m.referenceType == 'return_cancel'), isNotEmpty,
      reason: 'وللإلغاء نفسِه لازم صفٌّ مضادّ — نفسُ ما تفعله الخزنةُ '
          'بـ«return_cancel».',
    );
  });

  // ═════════════════════════════════════════════════════════════════════════
  // الخزنة — الخصمُ والردُّ كلٌّ مرّةً واحدة
  // ═════════════════════════════════════════════════════════════════════════
  //
  // `createSafeTransaction` **يعدّل الرصيدَ بنفسه**: `receipt/deposit` تزيد
  // و`payment/withdrawal` تنقص (‏`treasury_dao.dart:1464-1475`). فأيُّ نداءٍ
  // يكتب الرصيدَ **ثم** ينادي `createSafeTransaction` يطبّق الحركةَ مرّتين.
  //
  // وهذا ما يفعله مسارُ المرتجع: `adjustSafeBalance(-refund)` ثم
  // `createSafeTransaction(type: 'payment', amount: refund)`.

  test('ضابط: المرتجعُ النقديّ يخصم من الخزنة مرّةً واحدة لا مرّتين', () async {
    final before = await cashSafeBalance();

    await processReturn(); // مرتجعٌ نقديّ ٥٠٠

    expect(
      await cashSafeBalance(),
      closeTo(before - 500, 0.001),
      reason: 'المرتجعُ ٥٠٠ فالدرجُ ينقص ٥٠٠. لو نقص ١٠٠٠ فالخصمُ وقع '
          'مرّتين: مرّةً من `adjustSafeBalance(-refund)` ومرّةً من '
          '`createSafeTransaction(payment)` الذي ينقص الرصيدَ بنفسه.',
    );
  });

  test('إلغاءُ المرتجع يرجّع رصيدَ الخزنة لما كان — لا يزيده', () async {
    final before = await cashSafeBalance();

    await processReturn();
    await cancelReturn();

    expect(
      await cashSafeBalance(),
      closeTo(before, 0.001),
      reason: 'الإلغاءُ يعكس المرتجعَ فالدرجُ يرجع لرقمه. و`cancelSalesReturn` '
          'يكتب الرصيدَ المطلق ثم ينادي `createSafeTransaction(receipt)` '
          'فيُضيف المبلغَ مرّةً ثانية ⇒ نقديةٌ تُخلق من العدم.',
    );
  });
}
