// ═══════════════════════════════════════════════════════════════════════════
// End-to-end repro of the reported defect: process a sales return exactly the
// way the «مرتجع المبيعات» screen does (standalone path), then open the
// «سجل المرتجعات» dialog's query. Pre-fix it returned NOTHING, because the
// standalone path writes no `sale_type='return'` row and the dialog's query
// (`getSalesReturns`) matched only that shape. The purchases dialog keys off
// the ORIGINAL invoice's status, which is why it always worked.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/repositories/drift_accounting_repository.dart';
import 'package:ural_erp/data/repositories/returns_repository_impl.dart';
import 'package:ural_erp/domain/entities/product_entity.dart';
import 'package:ural_erp/domain/repositories/audit_repository_interface.dart';
import 'package:ural_erp/domain/repositories/i_products_repository.dart';
import 'package:ural_erp/domain/repositories/inventory_repository.dart';
import 'package:ural_erp/domain/repositories/parties_repository.dart';
import 'package:ural_erp/domain/repositories/settings_repository.dart';
import 'package:ural_erp/domain/repositories/treasury_repository.dart';
import 'package:ural_erp/services/accounting_service.dart';

void main() {
  late AppDatabase db;
  late ReturnsRepositoryImpl repo;
  late int warehouseId;
  late int userId;
  late int productId;

  setUp(() async {
    db = AppDatabase.forTesting();
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

    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(name: 'كاشير', isSystemRole: const Value(false)),
        );
    userId = await db.createUser(
      username: 'ret_hist',
      password: 'test123',
      displayName: 'Return Tester',
      roleId: roleId,
    );

    warehouseId = (await db.getDefaultWarehouse())!.id;

    productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'HIST-01',
        name: 'منتج',
        salePrice: const Value(100.0),
        costPrice: const Value(60.0),
        currentStock: const Value(0),
        trackInventory: const Value(true),
      ),
    );
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 100,
      type: 'in',
      notes: 'seed',
    );
  });

  tearDown(() => db.close());

  Future<SalesInvoiceData> seedSale(String number, double qty) async {
    final id = await db.createSalesInvoice(
      invoiceNumber: number,
      warehouseId: warehouseId,
      userId: userId,
      subtotal: qty * 100,
      discount: 0,
      tax: 0,
      total: qty * 100,
      paid: qty * 100,
      paymentMethod: 'cash',
      items: [
        SalesInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: qty,
          unitPrice: 100,
          total: qty * 100,
          costPrice: const Value(60),
        ),
      ],
    );
    return (db.select(db.salesInvoices)..where((s) => s.id.equals(id)))
        .getSingle();
  }

  Future<ProductEntity> productEntity() async {
    final p = await db.getProductById(productId);
    return ProductEntity(
      id: p!.id,
      name: p.name,
      code: p.code,
      salePrice: p.salePrice,
      costPrice: p.costPrice,
      currentStock: p.currentStock,
      minStock: p.minStock,
      trackInventory: p.trackInventory,
    );
  }

  test('a partial return processed on this screen appears in سجل المرتجعات',
      () async {
    final invoice = await seedSale('INV-HIST-1', 10);
    final items = await db.getSalesInvoiceItems(invoice.id);

    final ok = await repo.processSalesReturn(
      invoice: invoice,
      returnQuantities: {items.first.id: 4},
      productCache: {productId: await productEntity()},
      reason: 'تالف',
      userId: userId,
      userName: 'Return Tester',
      isFullReturn: false,
    );
    expect(ok, isTrue);

    // ROOT CAUSE pin: the standalone path writes NO `sale_type='return'`
    // document, so the query the dialog used to run finds nothing. If this
    // ever starts returning a row, the dedup in getSalesReturnHistoryEntries
    // is what keeps the entry from being listed twice.
    expect(
      await db.getSalesReturns(
        DateTime.now().subtract(const Duration(days: 365)),
        DateTime.now(),
      ),
      isEmpty,
      reason: 'this is why the old dialog query was permanently empty',
    );

    final history = await repo.getSalesReturnHistoryEntries(
      fromDate: DateTime.now().subtract(const Duration(days: 365)),
      toDate: DateTime.now(),
    );

    expect(history, hasLength(1),
        reason: 'the return processed by THIS screen must be listed');
    final entry = history.single;
    expect(entry.originalInvoiceId, invoice.id);
    expect(entry.originalInvoiceNumber, 'INV-HIST-1');
    expect(entry.isFullReturn, isFalse);
    // 4 of 10 units at 100 = 400 refunded, against a 1000 original.
    expect(entry.returnAmount, closeTo(400, 0.01));
    expect(entry.originalInvoiceTotal, closeTo(1000, 0.01));

    // The eye-icon lookup must resolve the actual returned lines.
    final details = await db.getSalesReturnItemDetails(entry.originalInvoiceId);
    expect(details, hasLength(1));
    expect((details.first['returned_qty'] as num).toDouble(), closeTo(4, 0.01));
  });

  test('two returns on different invoices are both listed', () async {
    final a = await seedSale('INV-HIST-A', 5);
    final b = await seedSale('INV-HIST-B', 3);
    final pc = {productId: await productEntity()};

    final aItems = await db.getSalesInvoiceItems(a.id);
    final bItems = await db.getSalesInvoiceItems(b.id);

    await repo.processSalesReturn(
      invoice: a,
      returnQuantities: {aItems.first.id: 5},
      productCache: pc,
      userId: userId,
      userName: 'T',
      isFullReturn: true,
    );
    await repo.processSalesReturn(
      invoice: b,
      returnQuantities: {bItems.first.id: 1},
      productCache: pc,
      userId: userId,
      userName: 'T',
      isFullReturn: false,
    );

    final history = await repo.getSalesReturnHistoryEntries(
      fromDate: DateTime.now().subtract(const Duration(days: 365)),
      toDate: DateTime.now(),
    );

    expect(history, hasLength(2));
    final byNumber = {
      for (final e in history) e.originalInvoiceNumber: e,
    };
    expect(byNumber['INV-HIST-A']!.isFullReturn, isTrue);
    expect(byNumber['INV-HIST-A']!.returnAmount, closeTo(500, 0.01));
    expect(byNumber['INV-HIST-B']!.isFullReturn, isFalse);
    expect(byNumber['INV-HIST-B']!.returnAmount, closeTo(100, 0.01));
  });
}

// AccountingService is only reached by cancelSalesReturn, which these tests
// don't exercise — the standalone processSalesReturn path posts through the
// DAO directly.
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
