// ═══════════════════════════════════════════════════════════════════════════
// A sales return must blend the returned goods back into WAC at the cost the
// journal entry uses — otherwise valuation and the GL drift apart permanently.
// ═══════════════════════════════════════════════════════════════════════════
//
// `returns_repository_impl` calls `adjustStock` to put the quantity back but
// never touches the product's weighted-average cost. The journal entry for the
// same return is built from `item.costPrice` — the cost FROZEN on the original
// invoice line. So the two halves disagree whenever the product's cost moved
// between the sale and the return:
//
//   • stock valuation  = current_stock × products.cost_price  (current WAC)
//   • GL account 1136  = Dr inventory at the frozen cost
//
// Reference scenario (buy 10@10 → sell 5 → buy 10@20 → return the 5):
//   WAC after the second purchase = (5×10 + 10×20) / 15 = 16.6667
//   returning 5 without re-blending → 20 units × 16.6667 = 333.33 valuation
//   the JE credits/debits          → 5 × 10 (frozen)     = 300.00 in the GL
//   drift = 33.33 on ONE return, and it never self-corrects.
//
// The fix is `updateProductWAC` BEFORE `adjustStock` (it reads current_stock,
// so ordering is load-bearing):
//   (15×16.6667 + 5×10) / 20 = 15  →  20 × 15 = 300 = the GL. Drift 0.
//
// NOTE ON THE FIX RECIPE: the triage document originally prescribed
// `reverseProductWAC`, copied from the PURCHASE return path. That is the wrong
// direction — a purchase return sends goods OUT, a sales return brings them
// IN. Applying it here yields (15×16.6667 − 5×10)/10 = 20 → 400 vs 300, i.e.
// +100 drift instead of +33.33. The correct sibling is the RECEIPT path in
// `purchase_dao.createPurchaseInvoice`.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/repositories/drift_accounting_repository.dart';
import 'package:picpos_erp/data/repositories/returns_repository_impl.dart';
import 'package:picpos_erp/domain/entities/product_entity.dart';
import 'package:picpos_erp/domain/repositories/audit_repository_interface.dart';
import 'package:picpos_erp/domain/repositories/i_products_repository.dart';
import 'package:picpos_erp/domain/repositories/inventory_repository.dart';
import 'package:picpos_erp/domain/repositories/parties_repository.dart';
import 'package:picpos_erp/domain/repositories/settings_repository.dart';
import 'package:picpos_erp/domain/repositories/treasury_repository.dart';
import 'package:picpos_erp/services/accounting_service.dart';

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
      username: 'wac_drift',
      password: 'test123',
      displayName: 'WAC Tester',
      roleId: roleId,
    );
    warehouseId = (await db.getDefaultWarehouse())!.id;

    productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'WAC-01',
        name: 'منتج',
        salePrice: const Value(100.0),
        costPrice: const Value(0),
        currentStock: const Value(0),
        trackInventory: const Value(true),
      ),
    );

    // شرطٌ لازمٌ منذ مواصفة 2026-08-18 (ح‑١): مرتجعٌ يصرف نقداً يستلزم
    // ورديّةً مفتوحة. هذا الملفُّ يقيس انحرافَ التكلفة عن الأستاذ لا سلوكَ
    // الورديّات، فالورديّةُ هنا تهيئةٌ لا موضوعُ اختبار.
    await db.openShift(userId, 0);
  });

  tearDown(() => db.close());

  /// Receive [qty] units at [unitCost], the same order the purchase DAO uses:
  /// WAC first (it reads the pre-receipt stock), then the stock move.
  Future<void> receive(double qty, double unitCost) async {
    await db.updateProductWAC(
      productId: productId,
      newQuantity: qty,
      newUnitCost: unitCost,
    );
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: qty,
      type: 'purchase',
      unitCost: unitCost,
      notes: 'seed receipt',
    );
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

  Future<SalesInvoiceData> sell(double qty, double frozenCost) async {
    final id = await db.createSalesInvoice(
      invoiceNumber: 'INV-WAC-1',
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
          costPrice: Value(frozenCost),
        ),
      ],
    );
    return (db.select(db.salesInvoices)..where((s) => s.id.equals(id)))
        .getSingle();
  }

  test('returning goods after the cost moved keeps valuation equal to the GL',
      () async {
    // buy 10 @ 10
    await receive(10, 10);
    expect((await db.getProductById(productId))!.costPrice, closeTo(10, 0.001));

    // sell 5 at a frozen cost of 10 — a sale must not move WAC
    final invoice = await sell(5, 10);
    expect((await db.getProductById(productId))!.costPrice, closeTo(10, 0.001),
        reason: 'issuing stock never changes the weighted average');

    // buy 10 @ 20 → WAC = (5×10 + 10×20)/15 = 16.6667
    await receive(10, 20);
    final blended = (await db.getProductById(productId))!.costPrice;
    expect(blended, closeTo(16.6667, 0.001));

    // return the 5 that were sold at the frozen cost of 10
    final items = await db.getSalesInvoiceItems(invoice.id);
    final ok = await repo.processSalesReturn(
      invoice: invoice,
      returnQuantities: {items.first.id: 5},
      productCache: {productId: await productEntity()},
      reason: 'اختبار',
      userId: userId,
      userName: 'WAC Tester',
    );
    expect(ok, isTrue);

    final after = (await db.getProductById(productId))!;
    expect(after.currentStock, closeTo(20, 0.001),
        reason: 'quantity is already correct today — the bug is the cost');

    expect(after.costPrice, closeTo(15.0, 0.001),
        reason: 'the 5 units came back carrying the 10 the ledger recognised, '
            'so WAC must re-blend to (15×16.6667 + 5×10)/20 = 15. '
            'Leaving it at 16.6667 values 20 units at 333.33 while the GL '
            'holds 300 — a permanent 33.33 divergence from one return');
  });

  test('warehouse-level average cost tracks the global WAC', () async {
    // Guards the second half of the fix: passing `unitCost` to adjustStock.
    // Without it the warehouse layer blends against products.cost_price (the
    // value BEFORE the WAC update), leaving inventory_balances.average_cost
    // disagreeing with products.cost_price even once the global figure is right.
    await receive(10, 10);
    final invoice = await sell(5, 10);
    await receive(10, 20);

    final items = await db.getSalesInvoiceItems(invoice.id);
    await repo.processSalesReturn(
      invoice: invoice,
      returnQuantities: {items.first.id: 5},
      productCache: {productId: await productEntity()},
      userId: userId,
      userName: 'WAC Tester',
    );

    final global = (await db.getProductById(productId))!.costPrice;
    final balance = await (db.select(db.inventoryBalances)
          ..where((b) =>
              b.productId.equals(productId) &
              b.warehouseId.equals(warehouseId)))
        .getSingle();

    expect(balance.averageCost, closeTo(global, 0.01),
        reason: 'the per-warehouse layer and the product-level WAC must agree, '
            'or every warehouse-scoped valuation report disagrees with the '
            'company-level one');
  });
}

// ── Collaborator stubs ──────────────────────────────────────────────────────

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
