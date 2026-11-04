// انحدار: بيعةٌ نقديّةٌ بلا وردية مفتوحة تصل **كاستثناءٍ مُهيكَل** إلى الواجهة.
//
// الخللُ الذي يحرسه: `CheckoutController.processPayment` كان يلتقط كلَّ استثناء
// بـ`catch (e)` عام، فيحوّل `ShiftRequiredException` إلى نصٍّ خام في `state.error`
// (‏«AppException(SHIFT_REQUIRED_FOR_CASH_REFUND)…»)، فلا يصل إلى
// `runWithOpenShiftPrompt` ولا يُعرض حوارُ فتحِ الوردية. المديرُ (لا تُفتح له
// وردية تلقائياً) كان لا يستطيع إتمامَ أيّ بيعٍ نقدي.
//
// المسارُ الحقيقيّ كاملاً على قاعدة اختبار: ProviderContainer ← CheckoutController
// ← CompleteSaleUseCase ← المنسّق ← DAO. لا يُحاكى شيءٌ من الطبقات الوسيطة.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/errors/app_exceptions.dart';
import 'package:picpos_erp/data/database/sync_interceptor.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/entities/product_entity.dart';
import 'package:picpos_erp/presentation/pos/providers/cart_controller.dart';
import 'package:picpos_erp/presentation/pos/providers/checkout_controller.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late int adminId;
  late int warehouseId;
  late int productId;

  const unitPrice = 100.0;
  const unitCost = 40.0;

  ProductEntity entity() => ProductEntity(
        id: productId,
        code: 'SHIFT-1',
        name: 'صنف الوردية',
        salePrice: unitPrice,
        costPrice: unitCost,
        currentStock: 10,
        minStock: 0,
        trackInventory: true,
      );

  CartController cartCtl() => container.read(cartControllerProvider.notifier);
  CartState cartState() => container.read(cartControllerProvider);
  CheckoutController checkout() =>
      container.read(checkoutControllerProvider.notifier);
  CheckoutState checkoutState() => container.read(checkoutControllerProvider);

  Future<bool> payCash(double total) => checkout().processPayment(
        method: 'cash',
        total: total,
        cashAmount: total,
      );

  setUp(() async {
    SyncInterceptor.instance = null;
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    warehouseId = (await db.getDefaultWarehouse())!.id;

    // `CheckoutController` يقرأ `authState.originalUser?.id ?? 1` ⇒ المستخدمُ ١
    // هو البائع. وهو مديرُ النظام المزروع أصلاً في قاعدة الاختبار.
    final admin = (await db.select(db.users).get()).first;
    adminId = admin.id;
    expect(adminId, 1, reason: 'الاختبارُ يفترض أنّ المستخدمَ الافتراضيّ ١');
    final roles = await db.select(db.roles).get();
    final adminRole = roles.firstWhere((r) => r.id == admin.roleId);
    expect(adminRole.name, 'مدير النظام',
        reason: 'البائعُ يجب أن يكون مديرَ النظام كما في الشكوى');

    productId = await db.insertProduct(ProductsCompanion.insert(
      code: 'SHIFT-1',
      name: 'صنف الوردية',
      salePrice: const Value(unitPrice),
      costPrice: const Value(unitCost),
      trackInventory: const Value(true),
    ));
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 10,
      type: 'purchase',
      unitCost: unitCost,
      notes: 'رصيد',
    );

    // لا ورديّةَ مفتوحةً لأحد: هذا هو الشرطُ الذي يرفض البيعةَ النقدية.
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWith((ref) => db),
      branchScopeProvider
          .overrideWith((ref) async => const BranchScope.fullAccess()),
      posDefaultTaxRateProvider.overrideWith((ref) async => 0.16),
    ]);
  });

  tearDown(() async {
    SyncInterceptor.instance = null;
    container.dispose();
    await db.close();
  });

  test(
      'بيعةٌ نقديّةٌ بلا وردية: يُرمى ShiftRequiredException بلا نصٍّ خام، '
      'ثم بعد فتح الوردية تنجح الدفعةُ نفسها وتُنشأ فاتورة', () async {
    cartCtl().addItem(entity(), quantity: 1);
    final total = cartState().total;
    expect(total, unitPrice, reason: 'تجهيزة: سلّةٌ فيها صنفٌ واحد');

    // ── المحاولةُ الأولى: بلا وردية ⇒ استثناءٌ مُهيكَل يصل إلى الواجهة ──
    await expectLater(
      payCash(total),
      throwsA(isA<ShiftRequiredException>()),
      reason: 'الاستثناءُ يجب أن يصل إلى runWithOpenShiftPrompt لا أن يُبتلع',
    );

    final afterFail = checkoutState();
    expect(afterFail.isProcessing, isFalse,
        reason: 'لا يبقى المعالِجُ معلّقاً بعد الاستثناء');
    expect(afterFail.error, isNull,
        reason: 'لا نصّ خامٌ مثل «AppException(SHIFT_REQUIRED…)» في الحالة');
    expect(afterFail.lastInvoiceId, isNull);
    expect(await db.select(db.salesInvoices).get(), isEmpty,
        reason: 'لا فاتورةَ قبل فتح الوردية');
    expect(cartState().items, hasLength(1),
        reason: 'السلّةُ لم تُمسّ: الكاشيرُ سيعيد الدفعةَ نفسها');
    expect((await db.getProductById(productId))!.currentStock, 10,
        reason: 'لا خصمَ مخزونٍ قبل نجاح البيعة');

    // ── فتحُ الوردية ثم الدفعةُ نفسها ──
    await db.openShift(adminId, 0);

    final ok = await payCash(total);
    expect(ok, isTrue, reason: checkoutState().error);

    final after = checkoutState();
    expect(after.isProcessing, isFalse);
    expect(after.error, isNull);
    expect(after.lastInvoiceId, isNotNull, reason: 'فاتورةُ البيعة مُعرَّفة');

    final invoices = await db.select(db.salesInvoices).get();
    expect(invoices, hasLength(1));
    expect(invoices.single.id, after.lastInvoiceId);
    expect(invoices.single.paymentMethod, 'cash');
    expect(cartState().items, isEmpty, reason: 'السلّةُ تُفرَّغ بعد النجاح');
    expect((await db.getProductById(productId))!.currentStock, 9,
        reason: 'المخزونُ ينقص بقطعةٍ واحدة');
  });
}
