// ═══════════════════════════════════════════════════════════════════════════
// مرتجعُ المبيعات — من أيِّ خزنةٍ يخرج المال؟
// ═══════════════════════════════════════════════════════════════════════════
//
// كان `ProcessSalesReturnUseCase` ينادي `getDefaultSafeByType('cash')`:
// **الخزنةُ الافتراضيّة للنظام** مهما كان فرعُ الفاتورة. بينما مسارُ البيع
// (`_recordSalesReceipt`) يحلّ خزنةَ الفرع من المخزن أوّلاً. فالمالُ يدخل
// خزنةَ فرعٍ ويخرج من أخرى: فرعٌ ينتفخ رصيدُه وفرعٌ يعجز، بلا حركةٍ تفسّر
// أيَّهما.
//
// الاختبارُ يقيس الاتّجاهين معاً — أن المرتجع يتبع خزنةَ فرع الفاتورة، وأن
// الرجوعَ إلى افتراضيِّ النظام يبقى حين لا خزنةَ للفرع.

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/activity_logger.dart';
import 'package:ural_erp/domain/usecases/returns/process_sales_return_usecase.dart';

String _why(ReturnResult r) => r is ReturnFailure ? r.error : '';

void main() {
  late AppDatabase db;
  late ProcessSalesReturnUseCase useCase;
  late int userId;
  late int productId;

  /// خزنةُ النظام الافتراضيّة المبذورة — `صندوق الكاشير` (‏`branchId` فارغ).
  late Safe systemCashSafe;

  setUp(() async {
    db = AppDatabase.forTesting();
    useCase = ProcessSalesReturnUseCase(db, ActivityLogger(db));

    final roleId = await db
        .into(db.roles)
        .insert(RolesCompanion.insert(name: 'كاشير'));
    userId = await db.createUser(
      username: 'refund_user',
      password: 'test',
      displayName: 'Refund User',
      roleId: roleId,
    );

    systemCashSafe = (await db.getDefaultSafeByType('cash'))!;

    productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'REF-P1',
        name: 'منتج المرتجع',
        salePrice: const Value(100.0),
        costPrice: const Value(60.0),
        trackInventory: const Value(false),
      ),
    );
  });

  tearDown(() async => db.close());

  /// فرعٌ ومخزنُه — والخزنةُ اختياريّة كي يُقاس الرجوعُ عند غيابها.
  Future<({int branchId, int warehouseId, int? safeId})> seedBranch({
    required String name,
    required bool withCashSafe,
  }) async {
    final branchId = await db
        .into(db.branches)
        .insert(BranchesCompanion.insert(name: name));
    final warehouseId = await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(
            name: 'مخزن $name',
            branchId: Value(branchId),
          ),
        );
    int? safeId;
    if (withCashSafe) {
      safeId = await db.into(db.safes).insert(
            SafesCompanion.insert(
              name: 'خزنة $name',
              safeType: const Value('cash'),
              branchId: Value(branchId),
              isDefault: const Value(true),
            ),
          );
    }
    return (branchId: branchId, warehouseId: warehouseId, safeId: safeId);
  }

  Future<({int invoiceId, int itemId})> sellOneUnit(int warehouseId) async {
    final invoiceId = await db.createSalesInvoice(
      invoiceNumber: 'INV-REF-$warehouseId',
      warehouseId: warehouseId,
      userId: userId,
      subtotal: 100.0,
      discount: 0.0,
      tax: 0.0,
      total: 100.0,
      paid: 100.0,
      paymentMethod: 'cash',
      items: [
        SalesInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: 1.0,
          unitPrice: 100.0,
          total: 100.0,
          costPrice: const Value(60.0),
        ),
      ],
    );
    final items = await db.getSalesInvoiceItems(invoiceId);
    return (invoiceId: invoiceId, itemId: items.first.id);
  }

  Future<ReturnResult> returnOneUnit(int invoiceId, int itemId) {
    return useCase.execute(
      SalesReturnRequest(
        originalInvoiceId: invoiceId,
        items: [
          ReturnItemInput(
            originalItemId: itemId,
            productId: productId,
            productName: 'منتج المرتجع',
            quantity: 1.0,
            unitPrice: 100.0,
          ),
        ],
        returnReason: 'قياس',
        userId: userId,
        isFullReturn: true,
      ),
    );
  }

  Future<List<SafeTransactionData>> refundRows(int invoiceId) {
    return (db.select(db.safeTransactions)
          ..where((t) =>
              t.referenceType.equals('sales_return') &
              t.referenceId.equals(invoiceId)))
        .get();
  }

  test('المرتجعُ يخرج من خزنة فرع الفاتورة لا من افتراضيِّ النظام', () async {
    final branch = await seedBranch(name: 'الشمال', withCashSafe: true);
    final sale = await sellOneUnit(branch.warehouseId);

    final result = await returnOneUnit(sale.invoiceId, sale.itemId);
    expect(result.isSuccess, isTrue, reason: _why(result));

    final rows = await refundRows(sale.invoiceId);
    expect(rows, hasLength(1));
    expect(
      rows.single.safeId,
      branch.safeId,
      reason: 'المالُ دخل خزنةَ الفرع عند البيع، فيجب أن يخرج منها',
    );
    expect(rows.single.safeId, isNot(systemCashSafe.id));
  });

  test('فرعٌ بلا خزنةِ نقدٍ ⇒ الرجوعُ إلى افتراضيِّ النظام كما كان', () async {
    final branch = await seedBranch(name: 'الجنوب', withCashSafe: false);
    final sale = await sellOneUnit(branch.warehouseId);

    final result = await returnOneUnit(sale.invoiceId, sale.itemId);
    expect(result.isSuccess, isTrue, reason: _why(result));

    final rows = await refundRows(sale.invoiceId);
    expect(rows, hasLength(1));
    expect(rows.single.safeId, systemCashSafe.id);
  });

  test('الرصيدُ ينقص مرّةً واحدةً على خزنة الفرع', () async {
    final branch = await seedBranch(name: 'الشرق', withCashSafe: true);
    final sale = await sellOneUnit(branch.warehouseId);

    final afterSale = await db.getSafeById(branch.safeId!);
    await returnOneUnit(sale.invoiceId, sale.itemId);
    final afterReturn = await db.getSafeById(branch.safeId!);

    expect(afterReturn!.balance, closeTo(afterSale!.balance - 100.0, 0.001));
  });

  test('لا خزنةَ نقدٍ إطلاقاً ⇒ يُرفَض المرتجعُ ولا يُترَك أثرٌ نصفيّ', () async {
    final branch = await seedBranch(name: 'الغرب', withCashSafe: true);
    final sale = await sellOneUnit(branch.warehouseId);

    // بعد البيع تُعطَّل كلُّ خزائن النقد: `getDefaultSafeByType` ترشّح
    // `isActive`، فلا خزنةَ صرفٍ تبقى.
    await (db.update(db.safes)..where((s) => s.safeType.equals('cash')))
        .write(const SafesCompanion(isActive: Value(false)));

    final result = await returnOneUnit(sale.invoiceId, sale.itemId);

    expect(result.isFailure, isTrue,
        reason: 'قيدُ الأستاذ يُسجّل صرفاً نقديّاً؛ فصرفٌ بلا خزنةٍ '
            'يفصل الدفاترَ عن الدرج');
    expect(await refundRows(sale.invoiceId), isEmpty);

    // والمعاملةُ رجعت كاملةً: حالةُ الفاتورة لم تنقلب إلى «مرتجعة».
    final invoice = await db.getSalesInvoiceById(sale.invoiceId);
    expect(invoice!.status, isNot('returned'));
  });
}
