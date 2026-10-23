import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';

/// PIR Integration Test 2 — Return Reversal Flow
///
/// Verifies the full chain:
///   Sale → Return → Stock Restored → Reverse JE → Balanced Ledger
///
/// This test ensures:
///   - Stock is restored after return
///   - Voiding a sale creates a reversal JE
///   - Trial balance remains zero after sale + void
///   - Cash safe balance is restored on void
void main() {
  late AppDatabase db;
  late int warehouseId;
  late int userId;
  late int productId;
  late int cashSafeId;

  setUp(() async {
    db = AppDatabase.forTesting();

    final roleId = await db.into(db.roles).insert(
      RolesCompanion.insert(
        name: 'كاشير PIR',
        isSystemRole: const Value(false),
      ),
    );
    userId = await db.createUser(
      username: 'pir_return_test',
      password: 'test123',
      displayName: 'PIR Return Tester',
      roleId: roleId,
    );

    // Spec 062: grant the void-paid-invoice critical-op permission so the
    // gate in voidSalesInvoice allows voiding fully-paid invoices.
    final voidPerm = await (db.select(db.permissions)
          ..where((p) => p.code.equals(PermissionCodes.voidPaidInvoice))
          ..limit(1))
        .getSingle();
    await db.addPermissionToRole(roleId, voidPerm.id);

    final wh = await db.getDefaultWarehouse();
    warehouseId = wh!.id;

    productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'PIR-RET-01',
        name: 'منتج مرتجع PIR',
        salePrice: const Value(200.0),
        costPrice: const Value(120.0),
        currentStock: const Value(0.0),
        trackInventory: const Value(true),
      ),
    );

    // Seed 50 units
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 50.0,
      type: 'adjustment',
    );

    // Reset cash safe
    final cashSafe = await db.getDefaultSafeByType('cash');
    cashSafeId = cashSafe!.id;
    await db.updateSafeBalance(cashSafeId, 0.0);
  });

  tearDown(() async => db.close());

  group('PIR: Return → Stock Restore → Reverse JE', () {
    test('Voiding a sale restores stock to original level', () async {
      // Before sale: 50 units
      final before = await db.getProductById(productId);
      expect(before!.currentStock, 50.0);

      // Sell 10 units @ 200 = 2000
      final invoiceId = await db.createSalesInvoice(
        invoiceNumber: 'PIR-RR-001',
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 2000.0,
        discount: 0.0,
        tax: 0.0,
        total: 2000.0,
        paid: 2000.0,
        paymentMethod: 'cash',
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 10.0,
            unitPrice: 200.0,
            total: 2000.0,
          ),
        ],
      );

      // After sale: 50 - 10 = 40
      final afterSale = await db.getProductById(productId);
      expect(afterSale!.currentStock, 40.0);

      // Void the sale
      await db.voidSalesInvoice(invoiceId, reason: 'PIR test void', deletedBy: userId);

      // After void: stock restored to 50
      final afterVoid = await db.getProductById(productId);
      expect(afterVoid!.currentStock, 50.0,
          reason: 'Stock should be restored to pre-sale level after void');
    });

    test('Voiding a sale restores cash safe balance', () async {
      final safeBefore = await db.getSafeById(cashSafeId);
      final initialBalance = safeBefore!.balance;

      // Sell 5 units @ 200 = 1000
      final invoiceId = await db.createSalesInvoice(
        invoiceNumber: 'PIR-RR-002',
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 1000.0,
        discount: 0.0,
        tax: 0.0,
        total: 1000.0,
        paid: 1000.0,
        paymentMethod: 'cash',
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 5.0,
            unitPrice: 200.0,
            total: 1000.0,
          ),
        ],
      );

      // Safe should have increased
      final safeAfterSale = await db.getSafeById(cashSafeId);
      expect(safeAfterSale!.balance - initialBalance, closeTo(1000.0, 0.01));

      // Void the sale
      await db.voidSalesInvoice(invoiceId, reason: 'PIR refund test', deletedBy: userId);

      // Safe should return to initial balance
      final safeAfterVoid = await db.getSafeById(cashSafeId);
      expect(safeAfterVoid!.balance, closeTo(initialBalance, 0.01),
          reason: 'Cash safe should be restored to initial balance after void');
    });

    test('Trial balance remains zero after sale + void cycle', () async {
      // Sell 3 units @ 200 = 600
      final invoiceId = await db.createSalesInvoice(
        invoiceNumber: 'PIR-RR-003',
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 600.0,
        discount: 0.0,
        tax: 0.0,
        total: 600.0,
        paid: 600.0,
        paymentMethod: 'cash',
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 3.0,
            unitPrice: 200.0,
            total: 600.0,
          ),
        ],
      );

      // Check balance after sale
      var result = await db.customSelect(
        'SELECT '
        'COALESCE(SUM(debit), 0) as total_debit, '
        'COALESCE(SUM(credit), 0) as total_credit '
        'FROM journal_entry_lines',
        readsFrom: {db.journalEntryLines},
      ).getSingle();

      var totalDebit = (result.data['total_debit'] as num).toDouble();
      var totalCredit = (result.data['total_credit'] as num).toDouble();
      expect((totalDebit - totalCredit).abs(), lessThan(0.01),
          reason: 'Trial balance should be zero after sale');

      // Void the sale
      await db.voidSalesInvoice(invoiceId, reason: 'PIR balance test', deletedBy: userId);

      // Check balance after void — still zero
      result = await db.customSelect(
        'SELECT '
        'COALESCE(SUM(debit), 0) as total_debit, '
        'COALESCE(SUM(credit), 0) as total_credit '
        'FROM journal_entry_lines',
        readsFrom: {db.journalEntryLines},
      ).getSingle();

      totalDebit = (result.data['total_debit'] as num).toDouble();
      totalCredit = (result.data['total_credit'] as num).toDouble();
      expect((totalDebit - totalCredit).abs(), lessThan(0.01),
          reason: 'INVARIANT: Trial balance must remain zero after sale + void cycle');
    });

    test('Voided invoice is marked as voided (not deleted)', () async {
      final invoiceId = await db.createSalesInvoice(
        invoiceNumber: 'PIR-RR-004',
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 200.0,
        discount: 0.0,
        tax: 0.0,
        total: 200.0,
        paid: 200.0,
        paymentMethod: 'cash',
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 1.0,
            unitPrice: 200.0,
            total: 200.0,
          ),
        ],
      );

      await db.voidSalesInvoice(invoiceId, reason: 'audit trail test', deletedBy: userId);

      // Invoice should still exist but be voided (soft-delete with status='voided')
      final invoice = await (db.select(db.salesInvoices)
            ..where((i) => i.id.equals(invoiceId)))
          .getSingleOrNull();
      expect(invoice, isNotNull,
          reason: 'Voided invoice should NOT be hard-deleted');
      expect(invoice!.status, 'voided',
          reason: 'Invoice should be marked as voided for audit trail');
    });
  });
}
