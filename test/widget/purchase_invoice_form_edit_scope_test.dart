// ═══════════════════════════════════════════════════════════════════════════
// تحريرُ فاتورة مشترياتٍ خارجَ نطاق الجهاز — القيمةُ تبقى معروضة
// ═══════════════════════════════════════════════════════════════════════════
//
// قائمتا المخزن ومركز التكلفة في نافذة المشتريات محصورتان عمداً: المخازنُ
// بفرع الجهاز (Spec 103) ومراكزُ التكلفة بالنشط وحدَه. والحصرُ صحيحٌ لمسار
// الإنشاء، وخاطئٌ لمسار **التحرير**: فاتورةٌ قائمةٌ قد تحمل مخزنَ فرعٍ آخر
// أو مركزَ تكلفةٍ أُوقف بعد إصدارها، فتخرج قيمتُها من `items` ويُطلق
// `DropdownButtonFormField` توكيدَه في debug ويرسم حقلاً فارغاً في release —
// ثم يُعاد الحفظُ بقيمةٍ أخرى صامتاً.
//
// لا قاعدةَ بيانات هنا: مستودعاتٌ مزيَّفةٌ بالكامل، فلا مؤقّتَ drift يعلّق
// التفكيك.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart' as db;
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/repositories/accounting_repository.dart';
import 'package:picpos_erp/domain/repositories/branch_repository.dart';
import 'package:picpos_erp/domain/repositories/i_products_repository.dart';
import 'package:picpos_erp/domain/repositories/purchases_repository.dart';
import 'package:picpos_erp/presentation/screens/purchase_invoices/widgets/purchase_invoice_form.dart';

const _inScopeWarehouseId = 1;
const _outOfScopeWarehouseId = 99;
const _activeCostCenterId = 10;
const _stoppedCostCenterId = 77;

db.Warehouse _warehouse(int id, String name) => db.Warehouse(
      id: id,
      name: name,
      type: 'main',
      isDefault: false,
      isActive: true,
      isSystemDefault: false,
      rowVersion: 1,
    );

db.CostCenter _costCenter(int id, String name, {required bool isActive}) =>
    db.CostCenter(
      id: id,
      code: 'CC$id',
      name: name,
      isActive: isActive,
      createdAt: DateTime(2026, 1, 1),
      rowVersion: 1,
    );

class _StubProductRepo implements IProductRepository {
  @override
  Future<List<db.Category>> getCategories() async => const [];
  @override
  Future<List<db.Party>> getSuppliers() async => const [];
  @override
  Future<List<db.Product>> getAllProducts() async => const [];
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class _StubBranchRepo implements IBranchRepository {
  int getWarehouseByIdCalls = 0;

  /// القائمةُ المحصورة — مخزنُ الفاتورة ليس فيها.
  @override
  Future<List<db.Warehouse>> getScopedWarehouses() async =>
      [_warehouse(_inScopeWarehouseId, 'مخزن الفرع')];

  @override
  Future<db.Warehouse?> getWarehouseById(int id) async {
    getWarehouseByIdCalls++;
    return id == _outOfScopeWarehouseId
        ? _warehouse(_outOfScopeWarehouseId, 'مخزن فرعٍ آخر')
        : null;
  }

  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class _StubAccountingRepo implements IAccountingRepository {
  int getCostCenterByIdCalls = 0;

  /// النشطُ وحدَه — مركزُ الفاتورة أُوقف بعد إصدارها.
  @override
  Future<List<db.CostCenter>> getActiveCostCenters() async =>
      [_costCenter(_activeCostCenterId, 'مركز نشط', isActive: true)];

  @override
  Future<db.CostCenter?> getCostCenterById(int id) async {
    getCostCenterByIdCalls++;
    return id == _stoppedCostCenterId
        ? _costCenter(_stoppedCostCenterId, 'مركز موقوف', isActive: false)
        : null;
  }

  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class _StubPurchasesRepo implements PurchasesRepository {
  @override
  Future<List<PurchaseInvoiceItemWithProduct>> getInvoiceItemsWithProduct(
          int invoiceId) async =>
      const [];
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

db.PurchaseInvoiceData _invoice({
  required int warehouseId,
  required int? costCenterId,
}) =>
    db.PurchaseInvoiceData(
      id: 5,
      invoiceNumber: 'PINV-5',
      supplierId: 1,
      warehouseId: warehouseId,
      invoiceDate: DateTime(2026, 5, 1),
      subtotal: 100,
      discount: 0,
      tax: 0,
      total: 100,
      paid: 0,
      // آجل عمداً: فرعُ «نقدي» يراقب `allSafesProvider` وهو يحتاج قاعدةً.
      paymentMethod: 'credit',
      status: 'posted',
      isLocked: false,
      costCenterId: costCenterId,
      isDeleted: false,
      updatedAt: DateTime(2026, 5, 1),
      rowVersion: 1,
      createdAt: DateTime(2026, 5, 1),
    );

Future<void> _pumpForm(
  WidgetTester tester, {
  required db.PurchaseInvoiceData? editInvoice,
  required _StubBranchRepo branchRepo,
  required _StubAccountingRepo accountingRepo,
}) async {
  // سطحٌ عريضٌ عمداً: النافذةُ نافذةُ سطحِ مكتب، والضيقُ يُنتج فيضَ `RenderFlex`
  // فيبتلع التوكيدَ الذي نقيسه.
  tester.view.physicalSize = const Size(3200, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        productRepositoryProvider.overrideWithValue(_StubProductRepo()),
        branchRepositoryProvider.overrideWithValue(branchRepo),
        accountingRepositoryProvider.overrideWithValue(accountingRepo),
        purchasesRepositoryProvider.overrideWithValue(_StubPurchasesRepo()),
        // النموذجُ صار يتقاطع مع نطاقِ المستخدم فوق نطاقِ الجهاز، فلا بدّ من
        // تثبيت الطرفِ الثاني هنا أيضاً — وإلّا قرأ المزوِّدُ الحقيقيُّ قاعدةً
        // غيرَ مهيّأةٍ فأفرغ التقاطعَ وسقط الاختبارُ لسببٍ ليس موضوعَه.
        // ونُثبِّته على **نفسِ** محتوى الحصر: التقاطعُ يُقاس لا يُوسَّع.
        assignableWarehousesProvider(null).overrideWith(
          (ref) async => [_warehouse(_inScopeWarehouseId, 'مخزن الفرع')],
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 3000,
            height: 1600,
            child: PurchaseInvoiceForm(
              editInvoice: editInvoice,
              onSave: ({
                required partyId,
                required invoiceNumber,
                required supplierInvoiceNumber,
                required date,
                required total,
                required discount,
                required tax,
                required netAmount,
                required paidAmount,
                required notes,
                required items,
                required warehouseId,
                required costCenterId,
                required isDraft,
                required paymentMethod,
                safeId,
                printAfterSave = false,
              }) async {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('مخزنُ فاتورةٍ خارجَ حصرِ الجهاز يبقى معروضاً في وضع التحرير',
      (tester) async {
    final branchRepo = _StubBranchRepo();
    final accountingRepo = _StubAccountingRepo();
    await _pumpForm(
      tester,
      editInvoice: _invoice(
        warehouseId: _outOfScopeWarehouseId,
        costCenterId: _stoppedCostCenterId,
      ),
      branchRepo: branchRepo,
      accountingRepo: accountingRepo,
    );

    // التوكيدُ الأوّل: لا استثناء. `DropdownButtonFormField` يُسقط التوكيدَ
    // إن كانت `initialValue` خارجَ `items` — وهذا هو العطلُ بعينه.
    expect(tester.takeException(), isNull);

    // والثاني: القيمةُ **معروضة** لا فارغة.
    expect(find.text('مخزن فرعٍ آخر'), findsOneWidget,
        reason: 'مخزنُ الفاتورة سقط من القائمة فرُسم الحقلُ فارغاً');
    expect(find.text('مركز موقوف'), findsOneWidget,
        reason: 'مركزُ تكلفة الفاتورة سقط من القائمة بعد إيقافه');
  });

  testWidgets('الإنشاءُ الجديد لا يجلب صفّاً خارجَ الحصر', (tester) async {
    final branchRepo = _StubBranchRepo();
    final accountingRepo = _StubAccountingRepo();
    await _pumpForm(
      tester,
      editInvoice: null,
      branchRepo: branchRepo,
      accountingRepo: accountingRepo,
    );

    expect(tester.takeException(), isNull);
    expect(branchRepo.getWarehouseByIdCalls, 0,
        reason: 'الحصرُ ارتفع عن مسار الإنشاء — وهو ما يمنعه Spec 103');
    expect(accountingRepo.getCostCenterByIdCalls, 0,
        reason: 'مركزٌ موقوفٌ قد يتسرّب إلى قائمة الإنشاء');
    expect(find.text('مخزن فرعٍ آخر'), findsNothing);
    expect(find.text('مركز موقوف'), findsNothing);
  });

  testWidgets('تحريرُ فاتورةٍ داخلَ الحصر لا يجلب شيئاً زائداً', (tester) async {
    final branchRepo = _StubBranchRepo();
    final accountingRepo = _StubAccountingRepo();
    await _pumpForm(
      tester,
      editInvoice: _invoice(
        warehouseId: _inScopeWarehouseId,
        costCenterId: _activeCostCenterId,
      ),
      branchRepo: branchRepo,
      accountingRepo: accountingRepo,
    );

    expect(tester.takeException(), isNull);
    expect(branchRepo.getWarehouseByIdCalls, 0);
    expect(accountingRepo.getCostCenterByIdCalls, 0);
    expect(find.text('مخزن الفرع'), findsOneWidget);
  });
}
