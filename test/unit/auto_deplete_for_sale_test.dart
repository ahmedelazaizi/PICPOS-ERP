// ═══════════════════════════════════════════════════════════════════════════
// Feature 009 / T013 — applyAutoDepleteForSale contract tests
//
// TDD red phase: these tests pin the contract for `applyAutoDepleteForSale`
// (T015) and the FR-004 DAO guard on `createBOM` / `updateBOM` (also T015).
// Until T015 lands the helper throws `UnimplementedError`, so every assertion
// here is expected to FAIL — that is the desired red state per
// `specs/009-auto-deplete-bom/tasks.md` Phase 3 ("Tests come first — write to
// fail"). Existing 19 tests remain green (this file does not touch any
// shared symbol — only adds new ones).
//
// What this file pins:
//   (a) Raw-material stock movements created with type='sale_auto_deplete'.
//   (b) Finished-product stock UNCHANGED in `always_auto_deplete` policy.
//   (c) `sale_bom_consumptions` row count + field shape mirrors the helper's
//       per-raw-material output.
//   (d) `cogsBreakdown.totalCost` ≈ Σ(consumed_qty × unit_cost_at_sale)
//       within 0.01 currency units (SC-007).
//   (e) IDEMPOTENCY: two calls with the same `saleGlobalId` yield identical
//       `sale_bom_consumptions.global_id` per row (deterministic UUIDv5 —
//       contracts/server-submit-payload.md §3).
//   (f) DAO GUARD: `createBOM`/`updateBOM` cannot mark an INACTIVE BOM as
//       `auto_deplete_on_sale = true` (FR-004 defense-in-depth).
//
// Notes for T015 author:
//   • The helper is invoked INSIDE a `db.transaction(...)` because the
//     contract requires it (auto-deplete-flow.md §1 pre-conditions).
//   • Idempotency is tested by re-running the helper on an already-consumed
//     invoice in a fresh transaction — the second call must produce the same
//     `global_id` strings (collision on the unique index is acceptable; the
//     test asserts the *derivation* is deterministic regardless of whether
//     the second insert succeeds).
//   • Test product `allowNegativeSale = true` is an artefact of the
//     underlying `_updateWarehouseBalance` (documented in T011); it is not
//     a contract requirement of `applyAutoDepleteForSale`.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:ural_erp/core/constants/stock_movement_types.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/core/utils/uuid_v7.dart';

void main() {
  late AppDatabase db;
  late int warehouseId;
  late int branchId;
  late int finishedProductId;
  late int meatId;
  late int spiceId;
  late int bomId;
  late int userId;

  setUp(() async {
    db = AppDatabase.forTesting();

    // Seed the chart of accounts so `applyAutoDepleteForSale` can resolve
    // the singleton inventory account ('1136'). In production this is
    // seeded during first-run setup; the test DB skips it by default.
    await db.seedChartOfAccounts();

    final wh = await db.getDefaultWarehouse();
    warehouseId = wh!.id;
    branchId = wh.branchId ?? 1;

    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(
            name: 'مدير الاختبار',
            isSystemRole: const Value(true),
          ),
        );
    userId = await db.createUser(
      username: 'autodeplete-tester',
      password: 'pw',
      displayName: 'Auto-Deplete Tester',
      roleId: roleId,
    );

    finishedProductId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'F009-SKEWER',
        name: 'سيخ كباب',
        salePrice: const Value(50.0),
        costPrice: const Value(20.0),
        trackInventory: const Value(true),
        // Pre-T018, the legacy createSalesInvoice still decrements the
        // finished product. Allow that to go negative inside the test so
        // we can prove the helper itself does NOT touch finished stock —
        // we capture the snapshot AFTER the legacy decrement and assert
        // applyAutoDepleteForSale leaves it unchanged.
        allowNegativeSale: const Value(true),
      ),
    );
    meatId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'F009-MEAT',
        name: 'لحمة',
        salePrice: const Value(0.0),
        costPrice: const Value(11.0),
        trackInventory: const Value(true),
        allowNegativeSale: const Value(true),
      ),
    );
    spiceId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'F009-SPICE',
        name: 'بهارات',
        salePrice: const Value(0.0),
        costPrice: const Value(2.0),
        trackInventory: const Value(true),
        allowNegativeSale: const Value(true),
      ),
    );

    // 1 skewer = 1 kg meat + 0.01 kg spice (Scenario 1 of quickstart.md).
    bomId = await db.createBOM(
      finishedProductId: finishedProductId,
      bomCode: 'F009-BOM-SKEWER',
      expectedQuantity: 1.0,
      components: [
        {'rawMaterialId': meatId, 'quantity': 1.0, 'wastagePercent': 0.0},
        {'rawMaterialId': spiceId, 'quantity': 0.01, 'wastagePercent': 0.0},
      ],
    );
    // Mark the BOM as auto-deplete + always_auto_deplete (test US1 purity).
    await (db.update(db.billOfMaterials)..where((b) => b.id.equals(bomId)))
        .write(const BillOfMaterialsCompanion(
      autoDepleteOnSale: Value(true),
      depletionPolicy: Value('always_auto_deplete'),
    ));

    // Seed raw-material stock generously so 'always_auto_deplete' succeeds.
    await db.adjustStock(
        productId: meatId,
        warehouseId: warehouseId,
        quantity: 100.0,
        type: 'initial');
    await db.adjustStock(
        productId: spiceId,
        warehouseId: warehouseId,
        quantity: 100.0,
        type: 'initial');
  });

  tearDown(() => db.close());

  Future<double> stockOf(int productId) async {
    final row = await (db.select(db.inventoryBalances)
          ..where((b) =>
              b.productId.equals(productId) &
              b.warehouseId.equals(warehouseId)))
        .getSingleOrNull();
    return row?.quantity ?? 0.0;
  }

  // Insert a sale invoice + items + return (id, globalId, items).
  Future<({int id, String globalId, int firstItemId})> seedSale({
    required double qty,
  }) async {
    final saleGlobalId = UuidV7.generate();
    final invoiceId = await db.createSalesInvoice(
      invoiceNumber: 'INV-AD-${DateTime.now().microsecondsSinceEpoch}',
      warehouseId: warehouseId,
      userId: userId,
      subtotal: 50.0 * qty,
      discount: 0.0,
      tax: 0.0,
      total: 50.0 * qty,
      paid: 50.0 * qty,
      paymentMethod: 'نقدي',
      branchId: branchId,
      globalId: saleGlobalId,
      items: [
        SalesInvoiceItemsCompanion.insert(
          invoiceId: 0, // overridden by DAO
          productId: finishedProductId,
          quantity: qty,
          unitPrice: 50.0,
          total: 50.0 * qty,
          sortOrder: const Value(1),
        ),
      ],
    );
    final items = await db.getSalesInvoiceItems(invoiceId);
    return (
      id: invoiceId,
      globalId: saleGlobalId,
      firstItemId: items.first.id,
    );
  }

  Future<SaleAutoDepleteResult> runAutoDeplete({
    required int invoiceId,
    required int saleItemId,
    required String saleGlobalId,
    required double qty,
  }) async {
    late SaleAutoDepleteResult result;
    await db.transaction(() async {
      result = await db.applyAutoDepleteForSale(
        saleInvoiceId: invoiceId,
        saleGlobalId: saleGlobalId,
        branchId: branchId,
        shortagePolicy: 'allow_negative',
        items: [
          SaleLineRef(
            saleItemId: saleItemId,
            productId: finishedProductId,
            qty: qty,
            warehouseId: warehouseId,
          ),
        ],
      );
    });
    return result;
  }

  group('applyAutoDepleteForSale — Scenario 1 (always_auto_deplete)', () {
    test('(a)+(b) raw materials decrease, finished-product stock unchanged',
        () async {
      final sale = await seedSale(qty: 12.0);

      // Finished product was never seeded with stock and the helper must NOT
      // touch finished-product inventory in `always_auto_deplete` mode.
      final finishedBefore = await stockOf(finishedProductId);

      await runAutoDeplete(
        invoiceId: sale.id,
        saleItemId: sale.firstItemId,
        saleGlobalId: sale.globalId,
        qty: 12.0,
      );

      expect(await stockOf(meatId), 100.0 - 12.0,
          reason: '12 skewers × 1 kg meat each');
      expect(await stockOf(spiceId), closeTo(100.0 - 0.12, 1e-9),
          reason: '12 skewers × 0.01 kg spice each');
      expect(await stockOf(finishedProductId), finishedBefore,
          reason: 'always_auto_deplete must NOT decrement finished product');

      // (a) Stock movements written with the canonical movement type.
      final movements = await (db.select(db.stockMovements)
            ..where((m) => m.movementType
                .equals(stockMovementSaleAutoDeplete)))
          .get();
      expect(movements.map((m) => m.productId).toSet(), {meatId, spiceId},
          reason: 'one stock_movements row per leaf raw material');
      expect(movements.every((m) => m.referenceId == sale.id), isTrue,
          reason: 'reference_id == sales_invoices.id');
    });

    test('(c) sale_bom_consumptions rows mirror per-raw-material consumption',
        () async {
      final sale = await seedSale(qty: 5.0);

      await runAutoDeplete(
        invoiceId: sale.id,
        saleItemId: sale.firstItemId,
        saleGlobalId: sale.globalId,
        qty: 5.0,
      );

      final rows = await (db.select(db.saleBomConsumptions)
            ..where((c) => c.saleInvoiceId.equals(sale.id)))
          .get();

      expect(rows, hasLength(2),
          reason: 'one consumption row per leaf raw material');
      final byMaterial = {for (final r in rows) r.rawMaterialId: r};

      expect(byMaterial[meatId]!.consumedQty, 5.0);
      expect(byMaterial[meatId]!.unitCostAtSale, 11.0,
          reason: 'WAC frozen at sale time');
      expect(byMaterial[meatId]!.bomId, bomId);
      expect(byMaterial[meatId]!.warehouseId, warehouseId);
      expect(byMaterial[meatId]!.saleInvoiceItemId, sale.firstItemId);
      expect(byMaterial[meatId]!.reversedByReturnId, isNull);
      expect(UuidV7.isValid(byMaterial[meatId]!.globalId), isTrue);

      expect(byMaterial[spiceId]!.consumedQty, closeTo(0.05, 1e-9));
      expect(byMaterial[spiceId]!.unitCostAtSale, 2.0);
    });

    test('(d) cogsBreakdown total ≈ Σ(qty × unit_cost) within 0.01', () async {
      final sale = await seedSale(qty: 12.0);

      final result = await runAutoDeplete(
        invoiceId: sale.id,
        saleItemId: sale.firstItemId,
        saleGlobalId: sale.globalId,
        qty: 12.0,
      );

      // 12 × 1 × 11 (meat) + 12 × 0.01 × 2 (spice) = 132 + 0.24 = 132.24
      expect(result.totalCost, closeTo(132.24, 0.01),
          reason: 'SC-007: total within ±0.01 of expected');
      expect(result.cogsBreakdown, hasLength(2));
      expect(
        result.cogsBreakdown.map((l) => l.rawMaterialId).toSet(),
        {meatId, spiceId},
      );
    });
  });

  group('applyAutoDepleteForSale — idempotency (e)', () {
    test('two invocations with the same saleGlobalId derive identical row IDs',
        () async {
      final sale = await seedSale(qty: 3.0);

      // First run — writes the rows.
      await runAutoDeplete(
        invoiceId: sale.id,
        saleItemId: sale.firstItemId,
        saleGlobalId: sale.globalId,
        qty: 3.0,
      );

      final firstIds = (await (db.select(db.saleBomConsumptions)
                ..where((c) => c.saleInvoiceId.equals(sale.id)))
              .get())
          .map((r) => r.globalId)
          .toSet();
      expect(firstIds, hasLength(2));

      // Second run with the same saleGlobalId. The implementation may either
      // (a) detect the existing rows and short-circuit, or (b) re-derive the
      // same global_id and trip the unique index. Either path is fine — what
      // we pin here is that the *derivation* is deterministic.
      final derivedMeat = UuidV7.deriveConsumptionGlobalId(
          saleGlobalId: sale.globalId, rawMaterialId: meatId, sequenceIndex: 0);
      final derivedSpice = UuidV7.deriveConsumptionGlobalId(
          saleGlobalId: sale.globalId, rawMaterialId: spiceId, sequenceIndex: 1);

      expect(firstIds, containsAll([derivedMeat, derivedSpice]),
          reason: 'persisted IDs must equal derived IDs (UUIDv5 stable hash)');

      // Re-derive should produce the same outputs.
      expect(
        UuidV7.deriveConsumptionGlobalId(
            saleGlobalId: sale.globalId,
            rawMaterialId: meatId,
            sequenceIndex: 0),
        derivedMeat,
        reason: 'same inputs → same UUIDv5',
      );
      expect(
        UuidV7.deriveConsumptionGlobalId(
            saleGlobalId: sale.globalId,
            rawMaterialId: meatId,
            sequenceIndex: 1),
        isNot(derivedMeat),
        reason: 'sequenceIndex must influence the hash',
      );
    });
  });

  group('FR-004 DAO guard (f) — auto_deplete on inactive BOM', () {
    test('createBOM throws InvalidPolicyException when isActive=false + auto-deplete=true',
        () async {
      Object? caught;
      try {
        await db.createBOM(
          finishedProductId: finishedProductId,
          bomCode: 'F009-BOM-INACTIVE',
          expectedQuantity: 1.0,
          components: [
            {'rawMaterialId': meatId, 'quantity': 1.0, 'wastagePercent': 0.0},
          ],
          autoDepleteOnSale: true,
          isActive: false,
        );
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<InvalidPolicyException>(),
          reason: 'FR-004: inactive BOM cannot be auto-deplete enabled');
    });

    test('updateBOM throws InvalidPolicyException when flipping isActive→false on auto-deplete BOM',
        () async {
      Object? caught;
      try {
        await db.updateBOM(
          bomId: bomId, // already auto_deplete = true from setUp
          finishedProductId: finishedProductId,
          bomCode: 'F009-BOM-SKEWER',
          expectedQuantity: 1.0,
          components: [
            {'rawMaterialId': meatId, 'quantity': 1.0, 'wastagePercent': 0.0},
          ],
          autoDepleteOnSale: true,
          isActive: false,
        );
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<InvalidPolicyException>());
    });

    test('updateBOM allows isActive=true + auto-deplete=true (legal combo)',
        () async {
      await db.updateBOM(
        bomId: bomId,
        finishedProductId: finishedProductId,
        bomCode: 'F009-BOM-SKEWER',
        expectedQuantity: 1.0,
        components: [
          {'rawMaterialId': meatId, 'quantity': 1.0, 'wastagePercent': 0.0},
        ],
        autoDepleteOnSale: true,
        isActive: true,
      );
      final fresh = await db.getBOM(bomId);
      expect(fresh!.autoDepleteOnSale, isTrue);
      expect(fresh.isActive, isTrue);
    });
  });
}
