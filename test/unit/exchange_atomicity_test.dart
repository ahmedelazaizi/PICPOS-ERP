// ═══════════════════════════════════════════════════════════════════════════
// المهمّةُ ٣ (2026-08-16) — مستودعُ الاستبدال: الذرّيةُ والربط
// ═══════════════════════════════════════════════════════════════════════════
//
// الاستبدالُ مستندان — مردودُ مبيعاتٍ **و** فاتورةُ بيع — في **معاملةِ قاعدةٍ
// واحدة**. والخطرُ الذي تحرسه هذه المجموعةُ ليس «فشلَ العملية» بل **نجاحَها
// نصفاً**: أن يُلغى مستندٌ ويبقى أثرُه في الخزنة. لذلك التأكيدُ ثلاثيٌّ دوماً
// ولا يكفي واحدٌ منه:
//
//   • لا مستندَ مردودٍ جديد (‏الشكلُ «أ» = حالةُ الفاتورة الأصلية لم تُقلب)
//     ولا صفَّ فاتورةٍ جديد.
//   • لا حركةَ مخزونٍ من نوع `'return'`.
//   • رصيدُ درج الوردية لم يتغيّر، ولا صفَّ خزنةٍ جديد.
//
// وضبطُ الضدّ (‏الاختبارُ الثالث) يُثبت أن الثلاثةَ **تتحرّك فعلاً** عند نجاح
// الاستبدال، وإلا كانت التأكيداتُ الثلاثةُ خضراءَ لأنها لا تقيس شيئاً.
//
// ملحوظةٌ على أسماء الأعمدة: كلُّها مثبتةٌ من `lib/data/database/tables/`
// (`sales_purchase_tables.dart` · `inventory_tables.dart` ·
// `treasury_settings_tables.dart`) لا منقولةٌ من اختبارٍ آخر.
//
// المسارُ المقيس (standalone): `SyncInterceptor.instance == null` في
// الاختبارات ⇒ `isClientMode == false`.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/logging/diagnostic_logger.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/repositories/drift_accounting_repository.dart';
import 'package:ural_erp/data/repositories/exchange_repository_impl.dart';
import 'package:ural_erp/data/repositories/returns_repository_impl.dart';
import 'package:ural_erp/data/repositories/sales_transaction_orchestrator.dart';
import 'package:ural_erp/domain/entities/cart_item_entity.dart';
import 'package:ural_erp/domain/entities/product_entity.dart';
import 'package:ural_erp/domain/models/exchange_settlement.dart';
import 'package:ural_erp/domain/repositories/audit_repository_interface.dart';
import 'package:ural_erp/domain/repositories/i_products_repository.dart';
import 'package:ural_erp/domain/repositories/inventory_repository.dart';
import 'package:ural_erp/domain/repositories/kitchen_repository.dart';
import 'package:ural_erp/domain/repositories/parties_repository.dart';
import 'package:ural_erp/domain/repositories/printers_repository.dart';
import 'package:ural_erp/domain/repositories/settings_repository.dart';
import 'package:ural_erp/domain/repositories/treasury_repository.dart';
import 'package:ural_erp/services/accounting_service.dart';
import 'package:ural_erp/services/kitchen_service.dart';

void main() {
  late AppDatabase db;
  late ExchangeRepositoryImpl exchange;
  late int warehouseId;
  late int branchId;
  late int drawerSafeId;
  late int cashierId;
  late int soldProductId; // الصنفُ المباعُ أصلاً ثم المرتجَع
  late int spareProductId; // البديلُ المتوفّر

  /// لقطةُ الحالة قبل الاستبدال — تُقارَن بها بعد الرفض.
  Future<({int invoices, int returnMoves, int safeTxns, double drawer})>
      snapshot() async {
    final invoices = await db.select(db.salesInvoices).get();
    final returnMoves = await (db.select(db.stockMovements)
          ..where((m) => m.movementType.equals('return')))
        .get();
    final safeTxns = await db.select(db.safeTransactions).get();
    final drawer = await (db.select(db.safes)
          ..where((s) => s.id.equals(drawerSafeId)))
        .getSingle();
    return (
      invoices: invoices.length,
      returnMoves: returnMoves.length,
      safeTxns: safeTxns.length,
      drawer: drawer.balance,
    );
  }

  Future<double> drawerBalance() async {
    final safe = await (db.select(db.safes)
          ..where((s) => s.id.equals(drawerSafeId)))
        .getSingle();
    return safe.balance;
  }

  Future<Map<int, ProductEntity>> productCacheFor(int productId) async {
    final p = await db.getProductById(productId);
    return {
      productId: ProductEntity(
        id: p!.id,
        name: p.name,
        code: p.code,
        salePrice: p.salePrice,
        costPrice: p.costPrice,
        currentStock: p.currentStock,
        minStock: p.minStock,
        trackInventory: p.trackInventory,
      ),
    };
  }

  /// فاتورةُ بيعٍ نقديةٌ أصليةٌ بمستخدمٍ آخر (admin id=1) كي لا تتلوّث حركاتُ
  /// «مَن-لمَس-الدرج» التي يفحصها `resolveRefundSafe`.
  Future<SalesInvoiceData> makeOriginalSale({
    double unitPrice = 100,
    double lineTotal = 100,
    double tax = 0,
    double taxRate = 0,
  }) async {
    final id = await db.createSalesInvoice(
      invoiceNumber: 'INV-EXCH-${DateTime.now().microsecondsSinceEpoch}',
      warehouseId: warehouseId,
      userId: 1,
      subtotal: unitPrice,
      discount: 0,
      tax: tax,
      total: lineTotal,
      paid: lineTotal,
      paymentMethod: 'cash',
      items: [
        SalesInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: soldProductId,
          quantity: 1,
          unitPrice: unitPrice,
          total: lineTotal,
          costPrice: const Value(60),
          taxRate: Value(taxRate),
          taxAmount: Value(tax),
        ),
      ],
    );
    return (db.select(db.salesInvoices)..where((s) => s.id.equals(id)))
        .getSingle();
  }

  CartItemEntity spareLine({
    double quantity = 1,
    double unitPrice = 130,
    double taxRate = 0,
    int? productId,
  }) =>
      CartItemEntity(
        productId: productId ?? spareProductId,
        productName: 'بديل',
        productCode: 'SPARE',
        quantity: quantity,
        unitPrice: unitPrice,
        taxRate: taxRate,
      );

  setUp(() async {
    db = AppDatabase.forTesting();
    DiagnosticLogger.enableTestMode();
    // `autoPostSalesReturn` / `generateSalesAccountingEntry` يحتاجان دليلَ
    // حساباتٍ ممتلئاً — مطابقةٌ لإعداد `sales_return_wac_gl_drift_test.dart`.
    await db.syncDefaultAccounts();

    final accounting = AccountingService(
      DriftAccountingRepository(db),
      _StubPartiesRepo(),
      _StubTreasuryRepo(),
      _StubProductRepo(),
      _StubInventoryRepo(),
      _StubSettingsRepo(),
      _StubAuditRepo(),
    );
    // أمرُ المطبخ غيرُ قاتلٍ (‏ملفوفٌ بـtry/catch في المنسّق) فالمقاطعُ
    // الرامية كافية.
    final kitchen = KitchenService(
      _StubKitchenRepo(),
      _StubProductRepo(),
      _StubPrintersRepo(),
      db,
    );
    exchange = ExchangeRepositoryImpl(
      db,
      ReturnsRepositoryImpl(db, accounting),
      SalesTransactionOrchestrator(db, accounting, kitchen),
    );

    warehouseId = (await db.getDefaultWarehouse())!.id;

    branchId = await db.into(db.branches).insert(
          BranchesCompanion.insert(name: 'فرعُ الاستبدال'),
        );
    drawerSafeId = await db.into(db.safes).insert(
          SafesCompanion.insert(
            name: 'درجُ وردية الاستبدال',
            safeType: const Value('cash'),
            branchId: Value(branchId),
            balance: const Value(1000),
          ),
        );
    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(name: 'كاشير', isSystemRole: const Value(false)),
        );
    cashierId = await db.createUser(
      username: 'exchange_cashier',
      password: 'x',
      displayName: 'كاشير الاستبدال',
      roleId: roleId,
    );
    await db.into(db.shifts).insert(
          ShiftsCompanion.insert(
            startTime: DateTime.now(),
            userId: cashierId,
            status: 'open',
            branchId: Value(branchId),
          ),
        );

    // الصنفُ المرتجَع **متعقَّبُ المخزون** عمداً: بدونه لا تُكتب حركةُ
    // `'return'` أصلاً فيصير تأكيدُ «لا حركةَ مرتجع» أخضرَ بلا معنى.
    soldProductId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'EXCH-SOLD',
        name: 'الصنفُ المباع',
        salePrice: const Value(100),
        costPrice: const Value(60),
        currentStock: const Value(0),
        trackInventory: const Value(true),
      ),
    );
    spareProductId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'EXCH-SPARE',
        name: 'الصنفُ البديل',
        salePrice: const Value(130),
        costPrice: const Value(70),
        currentStock: const Value(0),
        trackInventory: const Value(true),
      ),
    );
    // رصيدٌ افتتاحيٌّ للصنف المباع كي تنجح فاتورةُ البيع الأصلية (الخصمُ من
    // مخزنٍ بلا رصيدٍ يُرفض في `_updateWarehouseBalance`). البديلُ يبقى بلا
    // رصيدٍ عمداً — كلُّ اختبارٍ يزرع له ما يحتاجه.
    await db.adjustStock(
      productId: soldProductId,
      warehouseId: warehouseId,
      quantity: 50,
      type: 'adjustment',
      unitCost: 60,
    );
  });

  tearDown(() async => db.close());

  Future<void> stockSpare(double qty, {double unitCost = 70}) => db.adjustStock(
        productId: spareProductId,
        warehouseId: warehouseId,
        quantity: qty,
        type: 'adjustment',
        unitCost: unitCost,
      );

  // ───────────────────────────────────────────────────────────────────────
  // ١ — الرفضُ المبكّر (قرارُ المالك: يمنع لا يحذّر)
  // ───────────────────────────────────────────────────────────────────────

  test('بديلٌ نافدُ المخزون ⇒ رفضٌ **قبل أيّ كتابة**', () async {
    final invoice = await makeOriginalSale();
    final items = await db.getSalesInvoiceItems(invoice.id);
    final before = await snapshot();
    // لا رصيدَ للبديل إطلاقاً في هذا المستودع.

    await expectLater(
      exchange.processExchange(
        originalInvoice: invoice,
        returnQuantities: {items.first.id: 1},
        returnProductCache: await productCacheFor(soldProductId),
        replacementItems: [spareLine()],
        warehouseId: warehouseId,
        userId: cashierId,
        userName: 'كاشير الاستبدال',
        taxEnabled: false,
      ),
      throwsA(isA<Exception>()),
    );

    final after = await snapshot();
    expect(after.invoices, before.invoices, reason: 'لا صفَّ فاتورةٍ جديد');
    expect(after.returnMoves, before.returnMoves,
        reason: "لا حركةَ مخزونٍ من نوع 'return'");
    expect(after.safeTxns, before.safeTxns, reason: 'لا صفَّ خزنةٍ جديد');
    expect(after.drawer, before.drawer, reason: 'رصيدُ الدرج لم يتغيّر');
    final reread = await (db.select(db.salesInvoices)
          ..where((s) => s.id.equals(invoice.id)))
        .getSingle();
    expect(reread.status, 'completed',
        reason: 'حالةُ الفاتورة الأصلية لم تُقلب ⇒ لا مستندَ مردودٍ جديد');
  });

  // ───────────────────────────────────────────────────────────────────────
  // ٢ — الذرّيةُ الحقيقية: البديلُ **متوفّرٌ** فيعبر الرفضَ المبكّر، ثم
  //     ينفجر شقُّ البيع بعد أن كتب شقُّ الارتجاع كلَّ آثاره.
  // ───────────────────────────────────────────────────────────────────────

  test('فشلُ شقّ البيع يُلغي شقَّ الارتجاع بالكامل', () async {
    final invoice = await makeOriginalSale();
    final items = await db.getSalesInvoiceItems(invoice.id);

    // البديلُ متوفّرٌ فعلاً — الرفضُ المبكّرُ لا يلتقطه، فيلزم أن تُنقذنا
    // المعاملةُ وحدَها.
    await stockSpare(5, unitCost: 0);
    // ثم يُفجَّر شقُّ البيع **داخل** المعاملة: صنفٌ متعقَّبُ المخزون بتكلفةٍ
    // صفرٍ وسياسةُ `zero_cost_policy = 'block'` ⇒ `createSalesInvoice` ترمي
    // بعد أن تكون قد أدرجت ترويسةَ الفاتورة.
    await (db.update(db.products)..where((p) => p.id.equals(spareProductId)))
        .write(const ProductsCompanion(costPrice: Value(0)));
    await db.setSetting('zero_cost_policy', 'block');

    final before = await snapshot();

    await expectLater(
      exchange.processExchange(
        originalInvoice: invoice,
        returnQuantities: {items.first.id: 1},
        returnProductCache: await productCacheFor(soldProductId),
        replacementItems: [spareLine()],
        warehouseId: warehouseId,
        userId: cashierId,
        userName: 'كاشير الاستبدال',
        taxEnabled: false,
      ),
      throwsA(isA<Exception>()),
    );

    final after = await snapshot();
    // ثلاثةٌ معاً — ولا يكفي واحد. وأثرُ الخزنة أوّلاً عمداً: مستندٌ يُلغى
    // ويبقى أثرُه في الدرج أسوأُ من الفشل نفسِه.
    expect(after.drawer, before.drawer,
        reason: 'رصيدُ درج الوردية لم يتغيّر بمقدارٍ ولا كسر');
    expect(after.safeTxns, before.safeTxns,
        reason: 'صفُّ خزنة المرتجع أُلغي — لا أثرَ خزنةٍ لمستندٍ لم يُولد');
    expect(after.returnMoves, before.returnMoves,
        reason: "حركةُ المخزون 'return' التي كتبها شقُّ الارتجاع أُلغيت");
    expect(after.invoices, before.invoices,
        reason: 'لا صفَّ فاتورةٍ جديد — لا مستندَ بيعٍ يتيم');
    final reread = await (db.select(db.salesInvoices)
          ..where((s) => s.id.equals(invoice.id)))
        .getSingle();
    expect(reread.status, 'completed',
        reason: 'حالةُ الفاتورة الأصلية عادت كما كانت ⇒ لا مستندَ مردود');
  });

  // ───────────────────────────────────────────────────────────────────────
  // ٣ — ضبطُ الضدّ + مستندان + مفتاحُ الربط
  // ───────────────────────────────────────────────────────────────────────

  test('استبدالٌ ناجح ⇒ مستندان لكلٍّ رقمُه ومفتاحُ استبدالٍ يربطهما', () async {
    final invoice = await makeOriginalSale();
    final items = await db.getSalesInvoiceItems(invoice.id);
    await stockSpare(5);
    final before = await snapshot();

    final result = await exchange.processExchange(
      originalInvoice: invoice,
      returnQuantities: {items.first.id: 1},
      returnProductCache: await productCacheFor(soldProductId),
      replacementItems: [spareLine()],
      warehouseId: warehouseId,
      userId: cashierId,
      userName: 'كاشير الاستبدال',
      taxEnabled: false,
    );

    // ضبطُ الضدّ: الثلاثةُ تتحرّك فعلاً عند النجاح، فتأكيداتُ ٢ ليست فارغة.
    final after = await snapshot();
    expect(after.invoices, before.invoices + 1,
        reason: 'فاتورةُ البيع مستندٌ جديدٌ مستقلّ');
    expect(after.returnMoves, before.returnMoves + 1,
        reason: "شقُّ الارتجاع يكتب حركةَ مخزونٍ 'return'");
    expect(after.safeTxns, greaterThan(before.safeTxns),
        reason: 'الشقّان يتركان أثراً في الخزنة');

    // مستندان لا مستندٌ واحد.
    final sale = await (db.select(db.salesInvoices)
          ..where((s) => s.id.equals(result.saleInvoiceId)))
        .getSingle();
    expect(sale.id, isNot(invoice.id));
    expect(sale.invoiceNumber, result.saleInvoiceNumber);
    expect(sale.invoiceNumber, isNot(invoice.invoiceNumber),
        reason: 'لكلّ مستندٍ رقمُه');
    expect(result.returnVoucherNumber, isNotNull,
        reason: 'مستندُ المردود له رقمُه (SRET-N) المقروءُ من صفّ الخزنة');
    expect(result.returnVoucherNumber, startsWith('SRET-'));

    final flippedOriginal = await (db.select(db.salesInvoices)
          ..where((s) => s.id.equals(invoice.id)))
        .getSingle();
    expect(['returned', 'partial_return'], contains(flippedOriginal.status),
        reason: 'مستندُ المردود يظهر في شاشة مرتجع المبيعات');

    // مفتاحُ استبدالٍ مشتركٌ يجعل كلَّ مستندٍ يشير إلى الآخر.
    expect(result.exchangeKey, isNotEmpty);
    expect(sale.notes, contains(result.exchangeKey),
        reason: 'فاتورةُ البيع تحمل المفتاح');
    expect(flippedOriginal.notes, contains(result.exchangeKey),
        reason: 'مستندُ المردود يحمل نفسَ المفتاح');
    expect(sale.notes, contains('${invoice.id}'),
        reason: 'فاتورةُ البيع تشير إلى مستند المردود');
    expect(flippedOriginal.notes, contains('${sale.id}'),
        reason: 'مستندُ المردود يشير إلى فاتورة البيع');

    // ولا خصمَ يبتلع قيمةَ المرتجع.
    expect(sale.discount, 0,
        reason: 'الفرقُ لا يمرّ خصماً — خصمٌ بقيمة المرتجع يكذب على تقرير '
            'المبيعات');
    expect(sale.total, closeTo(130, 0.001),
        reason: 'فاتورةُ البيع تحمل قيمتَها الكاملة لا الفرقَ فقط');
  });

  // ───────────────────────────────────────────────────────────────────────
  // ٤ — الفرقُ في درج الوردية بحسب settleExchange، والتساوي بلا صفٍّ بصفر
  // ───────────────────────────────────────────────────────────────────────

  test('البديلُ أغلى ⇒ صافي الدرج = +الفرق (قبض)', () async {
    final invoice = await makeOriginalSale();
    final items = await db.getSalesInvoiceItems(invoice.id);
    await stockSpare(5);
    final before = await drawerBalance();

    final r = await exchange.processExchange(
      originalInvoice: invoice,
      returnQuantities: {items.first.id: 1},
      returnProductCache: await productCacheFor(soldProductId),
      replacementItems: [spareLine(unitPrice: 130)],
      warehouseId: warehouseId,
      userId: cashierId,
      userName: 'كاشير الاستبدال',
      taxEnabled: false,
    );

    expect(r.direction, ExchangeCashDirection.collect);
    expect(r.difference, closeTo(30, 0.001));
    expect(await drawerBalance(), closeTo(before + 30, 0.001),
        reason: 'قبضُ الفرق في خزنة الوردية');
  });

  test('البديلُ أرخص ⇒ صافي الدرج = −الفرق (صرف)', () async {
    final invoice = await makeOriginalSale();
    final items = await db.getSalesInvoiceItems(invoice.id);
    await stockSpare(5);
    final before = await drawerBalance();

    final r = await exchange.processExchange(
      originalInvoice: invoice,
      returnQuantities: {items.first.id: 1},
      returnProductCache: await productCacheFor(soldProductId),
      replacementItems: [spareLine(unitPrice: 70)],
      warehouseId: warehouseId,
      userId: cashierId,
      userName: 'كاشير الاستبدال',
      taxEnabled: false,
    );

    expect(r.direction, ExchangeCashDirection.refund);
    expect(r.difference, closeTo(30, 0.001));
    expect(await drawerBalance(), closeTo(before - 30, 0.001),
        reason: 'صرفُ الفرق من خزنة الوردية');
  });

  test('متساويان ⇒ الدرجُ لا يتغيّر ولا صفَّ خزنةٍ بصفر', () async {
    final invoice = await makeOriginalSale();
    final items = await db.getSalesInvoiceItems(invoice.id);
    await stockSpare(5);
    final before = await drawerBalance();

    final r = await exchange.processExchange(
      originalInvoice: invoice,
      returnQuantities: {items.first.id: 1},
      returnProductCache: await productCacheFor(soldProductId),
      replacementItems: [spareLine(unitPrice: 100)],
      warehouseId: warehouseId,
      userId: cashierId,
      userName: 'كاشير الاستبدال',
      taxEnabled: false,
    );

    expect(r.direction, ExchangeCashDirection.none);
    expect(r.difference, 0);
    expect(await drawerBalance(), closeTo(before, 0.001),
        reason: 'استبدالٌ متساوي القيمة لا يحرّك الدرج');
    final zeroRows = await (db.select(db.safeTransactions)
          ..where((t) => t.amount.equals(0)))
        .get();
    expect(zeroRows, isEmpty,
        reason: 'ولا صفَّ خزنةٍ بصفرٍ يلوّث الكشف');
  });

  // ───────────────────────────────────────────────────────────────────────
  // ٥ — الضريبة: الفاتورةُ الأصليةُ نسبتُها، والبيعُ نسبةَ اليوم
  // ───────────────────────────────────────────────────────────────────────

  test('اختلافُ نسبة الضريبة بين التاريخَين فرقٌ يظهر ولا يُبتلع', () async {
    // الفاتورةُ الأصليةُ بلا ضريبةٍ إطلاقاً (‏١٠٠ صافياً)، والبيعُ اليومَ
    // بنسبة ١٤٪ على نفس السعر ⇒ الفرقُ ١٤ ضريبةً خالصة، لا صفراً.
    final invoice = await makeOriginalSale(
      unitPrice: 100,
      lineTotal: 100,
      tax: 0,
      taxRate: 0,
    );
    final items = await db.getSalesInvoiceItems(invoice.id);
    await stockSpare(5);
    final before = await drawerBalance();

    final r = await exchange.processExchange(
      originalInvoice: invoice,
      returnQuantities: {items.first.id: 1},
      returnProductCache: await productCacheFor(soldProductId),
      replacementItems: [spareLine(unitPrice: 100, taxRate: 14)],
      warehouseId: warehouseId,
      userId: cashierId,
      userName: 'كاشير الاستبدال',
      taxPercent: 14,
      taxEnabled: true,
    );

    expect(r.returnTotal, closeTo(100, 0.001),
        reason: 'المرتجعُ يُعكَس بقيم الفاتورة الأصلية (بلا ضريبة)');
    expect(r.saleTotal, closeTo(114, 0.001),
        reason: 'البيعُ يحمل نسبةَ اليوم ١٤٪');
    expect(r.direction, ExchangeCashDirection.collect);
    expect(r.difference, closeTo(14, 0.001),
        reason: 'فرقُ النسبتَين حقيقيٌّ يظهر ولا يُبتلع');
    expect(await drawerBalance(), closeTo(before + 14, 0.001));

    final sale = await (db.select(db.salesInvoices)
          ..where((s) => s.id.equals(r.saleInvoiceId)))
        .getSingle();
    expect(sale.tax, closeTo(14, 0.001));
  });
}

// ── مقاطعُ التعاون — نفسُ نمط `sales_return_wac_gl_drift_test.dart`:
// أيُّ نداءٍ غيرِ متوقَّعٍ يرمي بدل أن يمرّ صامتاً ─────────────────────────

class _StubPartiesRepo implements IPartiesRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('Stub: ${inv.memberName}');
}

class _StubTreasuryRepo implements ITreasuryRepository {
  @override
  Future<List<Map<String, dynamic>>> getSafeAccountsForReference(
          String referenceType, int referenceId) async =>
      [];
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('Stub: ${inv.memberName}');
}

class _StubProductRepo implements IProductRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('Stub: ${inv.memberName}');
}

class _StubInventoryRepo implements InventoryRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('Stub: ${inv.memberName}');
}

class _StubSettingsRepo implements ISettingsRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('Stub: ${inv.memberName}');
}

class _StubAuditRepo implements IAuditRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('Stub: ${inv.memberName}');
}

class _StubKitchenRepo implements KitchenRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('Stub: ${inv.memberName}');
}

class _StubPrintersRepo implements IPrintersRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('Stub: ${inv.memberName}');
}
