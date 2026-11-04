// تكلفة مؤقتة عند CostRequiredException: المسار الحقيقيّ (المنسّق ← قاعدة
// الاختبار). الحفظ الأول يفشل فشلاً مُهيكلاً، والثاني بتكلفة السطر ينجح
// وتُسجَّل على الصنف.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/sync_interceptor.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/data/repositories/drift_accounting_repository.dart';
import 'package:picpos_erp/data/repositories/sales_transaction_orchestrator.dart';
import 'package:picpos_erp/domain/entities/cart_item_entity.dart';
import 'package:picpos_erp/domain/repositories/audit_repository_interface.dart';
import 'package:picpos_erp/domain/repositories/i_products_repository.dart';
import 'package:picpos_erp/domain/repositories/inventory_repository.dart';
import 'package:picpos_erp/domain/repositories/parties_repository.dart';
import 'package:picpos_erp/domain/repositories/sales_repository.dart';
import 'package:picpos_erp/domain/repositories/settings_repository.dart';
import 'package:picpos_erp/services/accounting_service.dart';

void main() {
  late AppDatabase db;
  late SalesTransactionOrchestrator orch;
  late int userId;
  late int warehouseId;
  late int productId;

  setUp(() async {
    SyncInterceptor.instance = null;
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    await db.setSetting('enable_negative_sales', 'true');
    // الافتراضي صار warn؛ مسار السؤال عن التكلفة يتطلب block صراحةً.
    await db.setSetting('zero_cost_policy', 'block');
    orch = SalesTransactionOrchestrator(
      db,
      AccountingService(
        DriftAccountingRepository(db),
        _StubParties(),
        _StubTreasury(),
        _StubProducts(),
        _StubInventory(),
        _StubSettings(),
        _StubAudit(),
      ),
    );
    final roleId = await db.into(db.roles).insert(
        RolesCompanion.insert(name: 'كاشير', isSystemRole: const Value(false)));
    userId = await db.createUser(
      username: 'cost_req',
      password: 'pw123456',
      displayName: 'كاشير',
      roleId: roleId,
    );
    warehouseId = (await db.getDefaultWarehouse())!.id;
    productId = await db.insertProduct(ProductsCompanion.insert(
      code: 'CR-1',
      name: 'صنف بلا تكلفة',
      salePrice: const Value(10),
      trackInventory: const Value(true),
    ));
    await db.openShift(userId, 0);
  });

  tearDown(() async {
    SyncInterceptor.instance = null;
    await db.close();
  });

  Future<SaleResult> sell({Map<int, double> costs = const {}}) =>
      orch.completeSalesTransaction(SaleRequest(
        items: [
          CartItemEntity(
            productId: productId,
            productName: 'صنف بلا تكلفة',
            productCode: 'CR-1',
            quantity: 2,
            unitPrice: 10,
          ),
        ],
        warehouseId: warehouseId,
        userId: userId,
        paymentMethod: 'cash',
        paidAmount: 20,
        cashAmount: 20,
        taxEnabled: false,
        provisionalCosts: costs,
      ));

  test('بلا تكلفة: فشلٌ مُهيكَل بمعرّف الصنف واسمه ولا فاتورة', () async {
    final r = await sell();
    expect(r.isSuccess, isFalse);
    final f = r as SaleFailure;
    expect(f.costRequiredProductId, productId);
    expect(f.costRequiredProductName, 'صنف بلا تكلفة');
    expect(await db.select(db.salesInvoices).get(), isEmpty);
  });

  test('إعادة المحاولة بتكلفة مؤقتة تنجح وتُسجَّل على السطر والصنف', () async {
    expect((await sell()).isSuccess, isFalse);

    final r = await sell(costs: {productId: 6.5});
    expect(r.isSuccess, isTrue, reason: r.errorMessage);

    final line = (await db.select(db.salesInvoiceItems).get()).single;
    expect(line.costPrice, 6.5);
    expect((await db.getProductById(productId))!.costPrice, 6.5);
  });

  test('تكلفة صفر لا تُقبل (تبقى block)', () async {
    final r = await sell(costs: {productId: 0});
    expect(r.isSuccess, isFalse);
    expect((r as SaleFailure).costRequiredProductId, productId);
  });
}

class _StubParties implements IPartiesRepository {
  @override
  dynamic noSuchMethod(Invocation inv) {
    if (inv.memberName == #getPartyById) return Future<Null>.value(null);
    throw UnsupportedError('parties repo not used here');
  }
}

class _StubTreasury implements ITreasuryRepository {
  @override
  Future<List<Map<String, dynamic>>> getSafeAccountsForReference(
          String referenceType, int referenceId) async =>
      [];

  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('treasury repo: ${inv.memberName}');
}

class _StubProducts implements IProductRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('product repo not used here');
}

class _StubInventory implements InventoryRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('inventory repo not used here');
}

class _StubSettings implements ISettingsRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('settings repo not used here');
}

class _StubAudit implements IAuditRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('audit repo not used here');
}