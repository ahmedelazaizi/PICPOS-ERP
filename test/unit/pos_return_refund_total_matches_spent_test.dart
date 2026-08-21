// مراجعةٌ نهائيةٌ قبل الدمج (2026-08-16) — العطبُ Critical: «مبلغُ
// الاسترداد» المعروضُ للكاشير (`PosReturnMode.refundTotal`، خلفَ
// `_refundTotal` في `picpos_pos_operations.dart`) كان يُبنى على
// `ReturnableLine.unitPrice` — سعرُ البيع قبل الضريبة وقبل خصم السطر —
// بينما المصروفُ فعلياً من الدرج (`ReturnsRepositoryImpl._calculateReturnTotal`،
// عبر `processSalesReturn`) مبنيٌّ على `item.total` (شاملَ الضريبة، صافياً
// من الخصم) × عاملِ توزيعٍ على مستوى الفاتورة.
//
// هذا الملفُّ يقيس الفجوةَ عبر السلك الحقيقيّ: يبني فاتورةً فعليةً، يستدعي
// `processSalesReturn` (نفسُ الدالّة التي تصرف من الدرج إنتاجياً)، يقرأ
// المبلغَ الفعليَّ المصروف من صفّ `safe_transactions`، ثم يبني
// `PosReturnMode` بنفس بيانات الفاتورة (كما يبنيها `_showQuickReturn`
// حرفياً — راجع `picpos_pos_operations.dart`) ويقارن `mode.refundTotal`
// بما صُرف فعلاً — يجب أن يتطابقا تماماً.
//
// قبل الإصلاح: هذا الملفُّ يفشل تحويلاً (compile) لأن `ReturnableLine`
// لا تملك `lineTotal`، ولا `PosReturnMode.fromLines` تملك
// `invoiceTotal`/`invoiceDeliveryFee`، ولا `PosReturnMode` تملك
// `refundTotal` — ثبَّتُّ الحمرةَ بتشغيلٍ فعليٍّ عبر `git stash` مؤقّتاً
// لتغييرات `lib/` (راجعُ تقريرَ الإصلاح النهائيّ).

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:ural_erp/core/logging/diagnostic_logger.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/repositories/drift_accounting_repository.dart';
import 'package:ural_erp/data/repositories/returns_repository_impl.dart';
import 'package:ural_erp/domain/entities/product_entity.dart';
import 'package:ural_erp/domain/models/returnable_line.dart';
import 'package:ural_erp/domain/repositories/audit_repository_interface.dart';
import 'package:ural_erp/domain/repositories/i_products_repository.dart';
import 'package:ural_erp/domain/repositories/inventory_repository.dart';
import 'package:ural_erp/domain/repositories/parties_repository.dart';
import 'package:ural_erp/domain/repositories/settings_repository.dart';
import 'package:ural_erp/domain/repositories/treasury_repository.dart';
import 'package:ural_erp/presentation/pos_picpos/state/pos_return_mode.dart';
import 'package:ural_erp/services/accounting_service.dart';

void main() {
  late AppDatabase db;
  late ReturnsRepositoryImpl repo;
  late int warehouseId;
  late int productId;
  late int roleId;
  late int cashierId;

  setUp(() async {
    db = AppDatabase.forTesting();
    DiagnosticLogger.enableTestMode();
    // مطلوبةٌ لتنجح autoPostSalesReturn (تحتاج دليلَ حساباتٍ ممتلئاً) —
    // مطابقةٌ لإعداد return_refund_hits_shift_drawer_test.dart.
    await db.syncDefaultAccounts();
    repo = ReturnsRepositoryImpl(
      db,
      AccountingService(
        DriftAccountingRepository(db),
        _StubPartiesRepo(),
        _StubTreasuryRepo(),
        _StubProductRepo(),
        _StubInventoryRepo(),
        _StubSettingsRepo(),
        _StubAuditRepo(),
      ),
    );
    roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(
              name: 'كاشير', isSystemRole: const Value(false)),
        );
    warehouseId = (await db.getDefaultWarehouse())!.id;
    productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'RTN-DISPLAY-01',
        name: 'منتج اختبار العرض',
        salePrice: const Value(100.0),
        costPrice: const Value(0),
        currentStock: const Value(0),
        // تبسيطٌ متعمَّد: الاختبارُ يفحص مطابقةَ المبلغ المعروض بالمصروف لا
        // المخزون.
        trackInventory: const Value(false),
      ),
    );
    cashierId = await db.createUser(
      username: 'display_match_cashier',
      password: 'x',
      displayName: 'كاشيرُ مطابقة العرض',
      roleId: roleId,
    );
  });

  tearDown(() async => db.close());

  Future<Map<int, ProductEntity>> productCacheFor() async {
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

  /// حركةُ الخزنة الوحيدة التي يتركها مرتجعٌ نقديٌّ كامل — مطابقةٌ لِـ
  /// `refundTxnFor` في return_refund_hits_shift_drawer_test.dart.
  Future<double> actualCashSpentFor(int invoiceId) async {
    final rows = await (db.select(db.safeTransactions)
          ..where((t) =>
              t.referenceType.equals('sales_return') &
              t.referenceId.equals(invoiceId) &
              t.category.equals('sales_return')))
        .get();
    expect(rows, hasLength(1),
        reason: 'مرتجعٌ نقديٌّ كاملٌ بلا عميلٍ يجب أن يترك حركةَ خزنةٍ '
            'واحدةً بفئة sales_return');
    return rows.single.amount;
  }

  Future<void> openShiftFor(int userId, String branchName) async {
    final branchId = await db.into(db.branches).insert(
          BranchesCompanion.insert(name: branchName),
        );
    await db.into(db.safes).insert(
          SafesCompanion.insert(
            name: '$branchName — الدرج',
            safeType: const Value('cash'),
            branchId: Value(branchId),
          ),
        );
    await db.into(db.shifts).insert(
          ShiftsCompanion.insert(
            startTime: DateTime.now(),
            userId: userId,
            status: 'open',
            branchId: Value(branchId),
          ),
        );
  }

  test(
      'فاتورةٌ بضريبة ١٤٪ بلا خصم — مبلغُ الاسترداد المعروض يساوي المصروفَ '
      'فعلياً من الدرج بالضبط', () async {
    // مئةٌ قبل الضريبة، ١١٤ شاملَ ١٤٪ — item.total تخزينٌ شاملُ الضريبة
    // (sales_transaction_orchestrator.dart:81: total = netBeforeTax + netTax)،
    // و unitPrice يبقى ١٠٠ (سعرُ البيع قبل الضريبة — صحيحٌ لعرض سعر
    // السطر، خاطئٌ أساساً لمبلغ الاسترداد).
    const subtotal = 100.0;
    const taxAmount = 14.0;
    const invoiceTotalAmount = 114.0;

    final invoiceId = await db.createSalesInvoice(
      invoiceNumber: 'INV-DISPLAY-${DateTime.now().microsecondsSinceEpoch}',
      warehouseId: warehouseId,
      userId: 1,
      subtotal: subtotal,
      discount: 0,
      tax: taxAmount,
      total: invoiceTotalAmount,
      paid: invoiceTotalAmount,
      paymentMethod: 'cash',
      items: [
        SalesInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: 1,
          unitPrice: subtotal,
          total: invoiceTotalAmount,
          costPrice: const Value(0),
        ),
      ],
    );
    final invoice = await (db.select(db.salesInvoices)
          ..where((s) => s.id.equals(invoiceId)))
        .getSingle();

    await openShiftFor(cashierId, 'فرع مطابقة العرض — ضريبة');

    final items = await db.getSalesInvoiceItems(invoiceId);
    final ok = await repo.processSalesReturn(
      invoice: invoice,
      returnQuantities: {items.first.id: 1},
      productCache: await productCacheFor(),
      userId: cashierId,
      userName: 'كاشيرُ مطابقة العرض',
    );
    expect(ok, isTrue);

    final actuallySpent = await actualCashSpentFor(invoiceId);
    expect(actuallySpent, invoiceTotalAmount);

    // مطابقةٌ لِمَا يبنيه `_showQuickReturn` حرفياً في
    // `picpos_pos_operations.dart`: `lineTotal: item.total` (لا
    // `unitPrice`)، و`invoiceTotal`/`invoiceDeliveryFee` من ترويسة
    // الفاتورة.
    final line = ReturnableLine(
      invoiceItemId: items.first.id,
      productId: items.first.productId,
      productName: 'منتج اختبار العرض',
      soldQty: items.first.quantity,
      alreadyReturnedQty: 0,
      unitPrice: items.first.unitPrice,
      lineTotal: items.first.total,
    );
    final mode = PosReturnMode.fromLines(
      invoiceId: invoiceId,
      lines: [line],
      invoiceTotal: invoice.total,
      invoiceDeliveryFee: invoice.deliveryFee,
    );
    final setOk = mode.setQty(line.invoiceItemId, 1);
    expect(setOk, isTrue);

    expect(mode.refundTotal, actuallySpent,
        reason: 'قبل الإصلاح: المعروضُ كان Σqty×unitPrice=100.00 بينما '
            'المصروفُ الفعليُّ من الدرج 114.00 (فرقٌ بمقدار الضريبة كاملةً) '
            '— فائضٌ صامتٌ في الدرج يُقيَّد لاحقاً «فائضَ نقدية» (إيرادٌ '
            'وهميّ).');
  });

  test(
      'فاتورةٌ بخصمِ سطرٍ (بلا ضريبة) — مبلغُ الاسترداد المعروض يساوي '
      'المصروفَ فعلياً لا سعرَ القائمة قبل الخصم', () async {
    // سعرُ القائمة ١٠٠، خصمُ سطرٍ ٢٠ ⇒ total=80 صافياً (unitPrice يبقى
    // ١٠٠ — القفلُ الصحيحُ لعرض سعر السطر، وليس أساسَ الاسترداد).
    const listPrice = 100.0;
    const netAfterLineDiscount = 80.0;

    final invoiceId = await db.createSalesInvoice(
      invoiceNumber:
          'INV-DISPLAY-DISC-${DateTime.now().microsecondsSinceEpoch}',
      warehouseId: warehouseId,
      userId: 1,
      subtotal: listPrice,
      discount: 20,
      tax: 0,
      total: netAfterLineDiscount,
      paid: netAfterLineDiscount,
      paymentMethod: 'cash',
      items: [
        SalesInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: 1,
          unitPrice: listPrice,
          total: netAfterLineDiscount,
          costPrice: const Value(0),
        ),
      ],
    );
    final invoice = await (db.select(db.salesInvoices)
          ..where((s) => s.id.equals(invoiceId)))
        .getSingle();

    await openShiftFor(cashierId, 'فرع مطابقة العرض — خصم');

    final items = await db.getSalesInvoiceItems(invoiceId);
    final ok = await repo.processSalesReturn(
      invoice: invoice,
      returnQuantities: {items.first.id: 1},
      productCache: await productCacheFor(),
      userId: cashierId,
      userName: 'كاشيرُ مطابقة الخصم',
    );
    expect(ok, isTrue);

    final actuallySpent = await actualCashSpentFor(invoiceId);
    expect(actuallySpent, netAfterLineDiscount);

    final line = ReturnableLine(
      invoiceItemId: items.first.id,
      productId: items.first.productId,
      productName: 'منتج اختبار الخصم',
      soldQty: items.first.quantity,
      alreadyReturnedQty: 0,
      unitPrice: items.first.unitPrice,
      lineTotal: items.first.total,
    );
    final mode = PosReturnMode.fromLines(
      invoiceId: invoiceId,
      lines: [line],
      invoiceTotal: invoice.total,
      invoiceDeliveryFee: invoice.deliveryFee,
    );
    final setOk = mode.setQty(line.invoiceItemId, 1);
    expect(setOk, isTrue);

    expect(mode.refundTotal, actuallySpent,
        reason: 'قبل الإصلاح: المعروضُ كان يساوي سعرَ القائمة ١٠٠ (يتجاوز '
            'ما يُصرف فعلياً ٨٠ بمقدار خصم السطر بالضبط) — الكاشيرُ يرى '
            'مبلغاً أكبرَ ممّا سيخرج من الدرج فعلياً.');
  });
}

// ── Collaborator stubs — مطابقةٌ لِمَا في return_refund_hits_shift_drawer_test.dart
// (نفسُ نمط الإسكات: أيُّ نداءٍ غيرِ متوقَّعٍ يرمي بدل أن يمرّ صامتاً) ──────

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
