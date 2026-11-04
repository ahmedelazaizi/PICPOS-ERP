// بند ٦ — ب: الفاتورة المحفوظة بخصم مبلغٍ ثابت تحمل المبلغَ الدقيق، والتعليقُ
// ثم الاسترجاعُ يحفظ المبلغ. المسارُ الحقيقيّ: المنسّق ← قاعدة بيانات الاختبار.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import 'package:picpos_erp/domain/usecases/sales/hold_order_usecase.dart';
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
    final svc = AccountingService(
      DriftAccountingRepository(db),
      _StubParties(),
      _StubTreasury(),
      _StubProducts(),
      _StubInventory(),
      _StubSettings(),
      _StubAudit(),
    );
    orch = SalesTransactionOrchestrator(db, svc);
    final roleId = await db.into(db.roles).insert(
        RolesCompanion.insert(name: 'كاشير', isSystemRole: const Value(false)));
    userId = await db.createUser(
      username: 'disc_amt',
      password: 'pw123456',
      displayName: 'كاشير',
      roleId: roleId,
    );
    warehouseId = (await db.getDefaultWarehouse())!.id;
    productId = await db.insertProduct(ProductsCompanion.insert(
      code: 'DA-1',
      name: 'صنف',
      salePrice: const Value(100),
      costPrice: const Value(40),
      currentStock: const Value(100),
      trackInventory: const Value(true),
    ));
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 100,
      type: 'purchase',
      unitCost: 40,
      notes: 'رصيد',
    );
    await db.openShift(userId, 0);
  });

  tearDown(() async {
    SyncInterceptor.instance = null;
  });

  Future<SaleResult> sell({
    double? amount,
    double percent = 0,
    bool tax = false,
    required double paid,
  }) =>
      orch.completeSalesTransaction(SaleRequest(
        items: [
          CartItemEntity(
            productId: productId,
            productName: 'صنف',
            productCode: 'DA-1',
            quantity: 1,
            unitPrice: 100,
          ),
        ],
        warehouseId: warehouseId,
        userId: userId,
        paymentMethod: 'cash',
        paidAmount: paid,
        cashAmount: paid,
        discountPercent: percent,
        invoiceDiscountAmount: amount,
        taxEnabled: tax,
        taxPercent: 14,
      ));

  Future<SalesInvoiceData> invoice(int id) =>
      (db.select(db.salesInvoices)..where((s) => s.id.equals(id))).getSingle();

  Future<double> journalImbalance(int invId) async {
    final entries = await (db.select(db.journalEntries)
          ..where((e) => e.referenceId.equals(invId)))
        .get();
    var net = 0.0;
    for (final e in entries) {
      for (final l in await (db.select(db.journalEntryLines)
            ..where((l) => l.entryId.equals(e.id)))
          .get()) {
        net += l.debit - l.credit;
      }
    }
    expect(entries, isNotEmpty);
    return net;
  }

  group('الحفظ', () {
    test('مبلغ 10.00 على أساس 100 ⇒ discount=10.00 بالضبط وtotal=90.00', () async {
      final r = await sell(amount: 10.00, paid: 90);
      expect(r.isSuccess, isTrue, reason: r.errorMessage);
      final inv = await invoice(r.invoiceId!);
      expect(inv.discount, 10.00);
      expect(inv.subtotal, 100.00);
      expect(inv.total, 90.00);
      expect(inv.tax, 0);
      expect(await journalImbalance(r.invoiceId!), closeTo(0, 1e-9));
    });

    test('مع ضريبة 14%: الضريبة على الصافي (12.60) والقيد متوازن', () async {
      final r = await sell(amount: 10.00, tax: true, paid: 102.6);
      expect(r.isSuccess, isTrue, reason: r.errorMessage);
      final inv = await invoice(r.invoiceId!);
      expect(inv.discount, 10.00);
      expect(inv.tax, closeTo(12.6, 1e-9));
      expect(inv.total, closeTo(102.6, 1e-9));
      expect(await journalImbalance(r.invoiceId!), closeTo(0, 1e-9));
    });

    test('المبلغ يُقصّ عند الأساس: 500 على أساس 100 ⇒ discount=100', () async {
      final r = await sell(amount: 500, paid: 0);
      expect(r.isSuccess, isTrue, reason: r.errorMessage);
      final inv = await invoice(r.invoiceId!);
      expect(inv.discount, 100);
      expect(inv.total, 0);
    });

    test('بلا مبلغ: النسبة كما كانت (12.5% ⇒ 12.50)', () async {
      final r = await sell(percent: 12.5, paid: 87.5);
      expect(r.isSuccess, isTrue, reason: r.errorMessage);
      expect((await invoice(r.invoiceId!)).discount, 12.5);
    });
  });

  group('التعليق ثم الاسترجاع', () {
    late ProviderContainer container;
    late HoldOrderUseCase hold;

    setUp(() {
      container = ProviderContainer(
          overrides: [databaseProvider.overrideWith((ref) => db)]);
      hold = container.read(holdOrderUseCaseProvider);
      addTearDown(container.dispose);
    });

    const item = CartItemEntity(
        productId: 1,
        productName: 'x',
        productCode: 'x',
        quantity: 1,
        unitPrice: 100);

    Future<int> heldId() async =>
        (await db.select(db.heldOrders).get()).single.id;

    test('المبلغ يُحفظ بـdiscountIsPercent=false ويُسترجع مبلغاً', () async {
      expect(
        await hold.executeHold(HoldOrderRequest(
            items: [item.copyWith(productId: productId)],
            subtotal: 100,
            discountPercent: 0,
            discountAmount: 10.00)),
        isNotNull,
      );
      final row = (await db.select(db.heldOrders).get()).single;
      expect(row.discount, 10.00);
      expect(row.discountIsPercent, isFalse);

      final res = (await hold.executeRetrieve(row.id))!;
      expect(res.discountAmount, 10.00);
      expect(res.discountPercent, 0);
    });

    test('النسبة تبقى نسبةً (توافق رجعي)', () async {
      await hold.executeHold(HoldOrderRequest(
          items: [item.copyWith(productId: productId)],
          subtotal: 100,
          discountPercent: 15));
      final id = await heldId();
      final res = (await hold.executeRetrieve(id))!;
      expect(res.discountAmount, isNull);
      expect(res.discountPercent, 15);
    });
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
