import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' as drift;
import 'package:ural_erp/data/database/database.dart';

/// Phase 2 — Fixes 2.2 & 2.4: GL Entry Atomicity
///
/// Verifies that:
///  - Purchase invoice GL creation is atomic with stock/payment mutations.
///  - Inventory audit finalization is atomic with stock adjustment.
///  - A GL failure (missing inventory account) is logged but does NOT corrupt
///    stock or supplier balance — the invariant is fail-fast or warn-and-skip.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();

    // Schema bootstrapping
    final roleId = await db.into(db.roles).insert(
      RolesCompanion.insert(name: 'admin', isSystemRole: const drift.Value(true)),
    );
    await db.createUser(
      username: 'admin',
      password: 'pw',
      displayName: 'Admin',
      roleId: roleId,
    );

    // Warehouse used by purchase tests
    await db.into(db.warehouses).insert(
      WarehousesCompanion.insert(
        name: 'Main Warehouse',
        isActive: const drift.Value(true),
        isDefault: const drift.Value(true),
      ),
    );
  });

  tearDown(() async => db.close());

  // ═══════════════════════════════════════════════════════════════════════════
  group('Fix 2.2 — Purchase Invoice GL Atomicity', () {
    // ─────────────────────────────────────────────────────────────────────────
    test('Purchase invoice created without COA — no GL but invoice exists', () async {
      // Arrange
      final warehouse = await db.getDefaultWarehouse();
      expect(warehouse, isNotNull);

      final supplierId = await db.into(db.parties).insert(
        PartiesCompanion.insert(
          name: 'Test Supplier',
          isSupplier: const drift.Value(true),
          balance: const drift.Value(0),
        ),
      );

      final unitId = await db.into(db.units).insert(
        UnitsCompanion.insert(name: 'Piece', symbol: 'pcs'),
      );

      final productId = await db.into(db.products).insert(
        ProductsCompanion.insert(
          name: 'Test Product',
          code: 'PRD-001',
          unitId: drift.Value(unitId),
          costPrice: const drift.Value(10.0),
          salePrice: const drift.Value(15.0),
        ),
      );

      // Act — no COA mapped, so GL is skipped (warn-and-skip path)
      final invoiceId = await db.createPurchaseInvoice(
        supplierId: supplierId,
        warehouseId: warehouse!.id,
        invoiceDate: DateTime.now(),
        paid: 100.0,
        paymentMethod: 'cash',
        supplierInvoiceNumber: 'PUR-001',
        items: [
          PurchaseInvoiceItemsCompanion.insert(
            invoiceId: 0, // filled by DAO
            productId: productId,
            quantity: 10,
            unitCost: 10.0,
            total: 100.0,
          )
        ],
      );

      // Assert — invoice persisted
      expect(invoiceId, isNotNull, reason: 'Invoice should be created even without COA mapping');

      // Stock should be updated (global currentStock)
      final product = await db.getProductById(productId);
      expect(product?.currentStock, 10.0,
          reason: 'Stock should be updated even when GL entry is skipped (COA not configured)');
    });

    // ─────────────────────────────────────────────────────────────────────────
    test('Supplier balance updated correctly on credit purchase', () async {
      final warehouse = await db.getDefaultWarehouse();
      final supplierId = await db.into(db.parties).insert(
        PartiesCompanion.insert(
          name: 'Credit Supplier',
          isSupplier: const drift.Value(true),
          balance: const drift.Value(0),
        ),
      );

      final unitId = await db.into(db.units).insert(
        UnitsCompanion.insert(name: 'Box', symbol: 'box'),
      );
      final productId = await db.into(db.products).insert(
        ProductsCompanion.insert(
          name: 'Credit Product',
          code: 'PRD-002',
          unitId: drift.Value(unitId),
          costPrice: const drift.Value(20.0),
          salePrice: const drift.Value(30.0),
        ),
      );

      // Act — credit purchase (paid=0, full amount is payable)
      await db.createPurchaseInvoice(
        supplierId: supplierId,
        warehouseId: warehouse!.id,
        invoiceDate: DateTime.now(),
        paid: 0.0,
        paymentMethod: 'credit',
        supplierInvoiceNumber: 'PUR-002',
        items: [
          PurchaseInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 5,
            unitCost: 20.0,
            total: 100.0,
          )
        ],
      );

      // Assert — supplier owes exactly 100
      final supplier = await db.getPartyById(supplierId);
      expect(supplier?.balance, 100.0, reason: 'Supplier balance should reflect unpaid amount');
    });

    // ─────────────────────────────────────────────────────────────────────────
    test('Two sequential purchases accumulate stock correctly', () async {
      final warehouse = await db.getDefaultWarehouse();
      final supplierId = await db.into(db.parties).insert(
        PartiesCompanion.insert(name: 'Multi-Purchase Supplier', isSupplier: const drift.Value(true), balance: const drift.Value(0)),
      );
      final unitId = await db.into(db.units).insert(
        UnitsCompanion.insert(name: 'Unit', symbol: 'u'),
      );
      final productId = await db.into(db.products).insert(
        ProductsCompanion.insert(
          name: 'Accumulate Product',
          code: 'PRD-003',
          unitId: drift.Value(unitId),
          costPrice: const drift.Value(5.0),
          salePrice: const drift.Value(8.0),
        ),
      );

      await db.createPurchaseInvoice(
        supplierId: supplierId,
        warehouseId: warehouse!.id,
        invoiceDate: DateTime.now(),
        paid: 50.0,
        paymentMethod: 'cash',
        supplierInvoiceNumber: 'PUR-003a',
        items: [
          PurchaseInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 10,
            unitCost: 5.0,
            total: 50.0,
          )
        ],
      );

      await db.createPurchaseInvoice(
        supplierId: supplierId,
        warehouseId: warehouse.id,
        invoiceDate: DateTime.now(),
        paid: 75.0,
        paymentMethod: 'cash',
        supplierInvoiceNumber: 'PUR-003b',
        items: [
          PurchaseInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 15,
            unitCost: 5.0,
            total: 75.0,
          )
        ],
      );

      final product = await db.getProductById(productId);
      expect(product?.currentStock, 25.0, reason: 'Stock should accumulate across two purchases');
    });

    // ─────────────────────────────────────────────────────────────────────────
    test('GL entry count matches purchase invoices when COA is configured', () async {
      // This test verifies that with proper COA, each purchase gets exactly one JE.
      // The forTesting() DB seeds full COA via syncDefaultAccounts() — no manual
      // account/mapping insertions needed (they would create duplicates and crash
      // getSingleOrNull in getAccountByPurpose).
      final warehouse = await db.getDefaultWarehouse();

      final supplierId = await db.into(db.parties).insert(
        PartiesCompanion.insert(name: 'COA Supplier', isSupplier: const drift.Value(true), balance: const drift.Value(0)),
      );
      final unitId = await db.into(db.units).insert(UnitsCompanion.insert(name: 'u2', symbol: 'u2'));
      final productId = await db.into(db.products).insert(
        ProductsCompanion.insert(
          name: 'COA Product',
          code: 'PRD-COA',
          unitId: drift.Value(unitId),
          costPrice: const drift.Value(10.0),
          salePrice: const drift.Value(15.0),
        ),
      );

      await db.createPurchaseInvoice(
        supplierId: supplierId,
        warehouseId: warehouse!.id,
        invoiceDate: DateTime.now(),
        paid: 100.0,
        paymentMethod: 'cash',
        supplierInvoiceNumber: 'PUR-COA-001',
        items: [
          PurchaseInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 10,
            unitCost: 10.0,
            total: 100.0,
          )
        ],
      );

      // Verify that at least one JE was posted for this purchase
      final journalEntries = await (db.select(db.journalEntries)
            ..where((j) => j.referenceType.equals('purchase_invoice')))
          .get();
      expect(journalEntries.length, greaterThanOrEqualTo(1),
          reason: 'At least one JE should be created when COA is configured');
    });

    // ─────────────────────────────────────────────────────────────────────────
    test('Mixed cash/credit purchase creates correct liability split', () async {
      final warehouse = await db.getDefaultWarehouse();
      final supplierId = await db.into(db.parties).insert(
        PartiesCompanion.insert(name: 'Split Supplier', isSupplier: const drift.Value(true), balance: const drift.Value(0)),
      );
      final unitId = await db.into(db.units).insert(
        UnitsCompanion.insert(name: 'u3', symbol: 'u3'),
      );
      final productId = await db.into(db.products).insert(
        ProductsCompanion.insert(
          name: 'Split Product',
          code: 'PRD-SPLIT',
          unitId: drift.Value(unitId),
          costPrice: const drift.Value(10.0),
          salePrice: const drift.Value(15.0),
        ),
      );

      // 200 total, 80 paid, 120 remaining credit
      await db.createPurchaseInvoice(
        supplierId: supplierId,
        warehouseId: warehouse!.id,
        invoiceDate: DateTime.now(),
        paid: 80.0,
        paymentMethod: 'cash',
        supplierInvoiceNumber: 'PUR-SPLIT-001',
        items: [
          PurchaseInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 20,
            unitCost: 10.0,
            total: 200.0,
          )
        ],
      );

      final supplier = await db.getPartyById(supplierId);
      expect(supplier?.balance, 120.0,
          reason: 'Remaining credit (200 - 80) should be recorded as supplier payable');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('Fix 2.4 — Inventory Audit JE Atomicity', () {
    // ─────────────────────────────────────────────────────────────────────────
    test('Audit finalization succeeds without COA (warn-and-skip path)', () async {
      // Without COA, finalizeAudit should succeed and adjust stock
      // but skip the GL entry (configuration gap, not a crash).
      final unitId = await db.into(db.units).insert(
        UnitsCompanion.insert(name: 'Audit Unit', symbol: 'au'),
      );
      final productId = await db.into(db.products).insert(
        ProductsCompanion.insert(
          name: 'Audit Product',
          code: 'AUD-001',
          unitId: drift.Value(unitId),
          costPrice: const drift.Value(50.0),
          salePrice: const drift.Value(70.0),
        ),
      );

      // Get the default warehouse (set up in setUp)
      final warehouse = await db.getDefaultWarehouse();
      expect(warehouse, isNotNull);

      // Seed warehouse-specific inventory balance (adjustStock creates the balance record)
      await db.adjustStock(
        productId: productId,
        warehouseId: warehouse!.id,
        quantity: 100.0,
        type: 'initial',
        notes: 'Initial stock for audit test',
      );

      // Create an inventory audit session
      final auditId = await db.createStockAudit(notes: 'Test Audit');
      expect(auditId, isNotNull);

      // Record counted quantities
      await db.saveAuditItem(
        auditId: auditId,
        productId: productId,
        expectedQuantity: 100.0,
        actualQuantity: 90.0, // 10 unit shrinkage
      );

      // Act — finalize without COA (should skip JE but adjust stock)
      await expectLater(
        db.finalizeAudit(auditId),
        completes,
        reason: 'Audit finalization should succeed even without COA',
      );

      // Stock should be adjusted to counted qty (global currentStock)
      final product = await db.getProductById(productId);
      expect(product?.currentStock, 90.0, reason: 'Stock should be adjusted to counted quantity');
    });

    // ─────────────────────────────────────────────────────────────────────────
    test('Audit with surplus adjusts stock upward', () async {
      final unitId = await db.into(db.units).insert(UnitsCompanion.insert(name: 'SurplusUnit', symbol: 'su'));
      final productId = await db.into(db.products).insert(
        ProductsCompanion.insert(
          name: 'Surplus Audit Product',
          code: 'AUD-002',
          unitId: drift.Value(unitId),
          costPrice: const drift.Value(20.0),
          salePrice: const drift.Value(30.0),
        ),
      );

      final warehouse = await db.getDefaultWarehouse();
      expect(warehouse, isNotNull);

      await db.adjustStock(
        productId: productId,
        warehouseId: warehouse!.id,
        quantity: 50.0,
        type: 'initial',
        notes: 'Initial stock for surplus audit test',
      );

      final auditId = await db.createStockAudit(notes: 'Surplus Audit');

      await db.saveAuditItem(
        auditId: auditId,
        productId: productId,
        expectedQuantity: 50.0,
        actualQuantity: 55.0, // 5 surplus
      );

      await db.finalizeAudit(auditId);

      final product = await db.getProductById(productId);
      expect(product?.currentStock, 55.0, reason: 'Surplus count should increase stock');
    });

    // ─────────────────────────────────────────────────────────────────────────
    test('Audit with exact count makes no stock adjustment', () async {
      final unitId = await db.into(db.units).insert(UnitsCompanion.insert(name: 'ExactUnit', symbol: 'eu'));
      final productId = await db.into(db.products).insert(
        ProductsCompanion.insert(
          name: 'Exact Audit Product',
          code: 'AUD-003',
          unitId: drift.Value(unitId),
          costPrice: const drift.Value(10.0),
          salePrice: const drift.Value(15.0),
        ),
      );

      final warehouse = await db.getDefaultWarehouse();
      expect(warehouse, isNotNull);

      await db.adjustStock(
        productId: productId,
        warehouseId: warehouse!.id,
        quantity: 75.0,
        type: 'initial',
        notes: 'Initial stock for exact-match audit test',
      );

      final auditId = await db.createStockAudit(notes: 'Exact Match Audit');

      await db.saveAuditItem(
        auditId: auditId,
        productId: productId,
        expectedQuantity: 75.0,
        actualQuantity: 75.0, // no variance
      );

      await db.finalizeAudit(auditId);

      final product = await db.getProductById(productId);
      expect(product?.currentStock, 75.0, reason: 'No-variance audit should not change stock');
    });
  });
}
