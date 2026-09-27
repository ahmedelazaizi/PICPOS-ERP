import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';

/// PIR Integration Test 1: Void Sales Invoice — Full Reversal
/// Verifies stock restoration, treasury reversal, and audit trail on void.
void main() {
  late AppDatabase db;
  late int warehouseId;
  late int userId;
  late int productId;
  // ignore: unused_local_variable
  late int safeId;

  setUp(() async {
    db = AppDatabase.forTesting();

    final roleId = await db.into(db.roles).insert(
      RolesCompanion.insert(name: 'كاشير', isSystemRole: const Value(false)),
    );
    userId = await db.createUser(
      username: 'void_test',
      password: 'test123',
      displayName: 'Void Tester',
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

    final cashSafe = await db.getDefaultSafeByType('cash');
    safeId = cashSafe!.id;

    productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'VOID-01',
        name: 'منتج اختبار الإلغاء',
        salePrice: const Value(200.0),
        costPrice: const Value(120.0),
        trackInventory: const Value(true),
      ),
    );

    // Seed 100 units
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 100.0,
      type: 'adjustment',
    );
  });

  tearDown(() async => db.close());

  group('PIR-005: Void Invoice Integrity', () {
    test('Void restores stock to original quantity', () async {
      final before = await db.getProductById(productId);
      final stockBefore = before!.currentStock;

      // Sell 10 units
      final invoiceId = await db.createSalesInvoice(
        invoiceNumber: 'VOID-TEST-001',
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

      // Verify stock was reduced
      final afterSale = await db.getProductById(productId);
      expect(afterSale!.currentStock, stockBefore - 10.0);

      // Void the invoice
      await db.voidSalesInvoice(invoiceId, reason: 'اختبار إلغاء', deletedBy: userId);

      // Verify stock restored
      final afterVoid = await db.getProductById(productId);
      expect(afterVoid!.currentStock, stockBefore,
          reason: 'Stock should be fully restored after void');
    });

    test('Void reverses treasury balance', () async {
      final cashBefore = await db.getDefaultSafeByType('cash');
      final balanceBefore = cashBefore!.balance;

      final invoiceId = await db.createSalesInvoice(
        invoiceNumber: 'VOID-TEST-002',
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 500.0,
        discount: 0.0,
        tax: 0.0,
        total: 500.0,
        paid: 500.0,
        paymentMethod: 'cash',
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 5.0,
            unitPrice: 100.0,
            total: 500.0,
          ),
        ],
      );

      // Verify cash increased
      final afterSale = await db.getDefaultSafeByType('cash');
      expect(afterSale!.balance, balanceBefore + 500.0);

      // Void
      await db.voidSalesInvoice(invoiceId, reason: 'عكس اختبار', deletedBy: userId);

      // Verify cash restored
      final afterVoid = await db.getDefaultSafeByType('cash');
      expect(afterVoid!.balance, balanceBefore,
          reason: 'Cash balance should revert after void');
    });

    test('Voiding already voided invoice throws', () async {
      final invoiceId = await db.createSalesInvoice(
        invoiceNumber: 'VOID-TEST-003',
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
          ),
        ],
      );

      await db.voidSalesInvoice(invoiceId, deletedBy: userId);

      expect(
        () => db.voidSalesInvoice(invoiceId, deletedBy: userId),
        throwsException,
        reason: 'Double void should throw',
      );
    });

    test('Voided invoice preserves audit trail (not deleted)', () async {
      final invoiceId = await db.createSalesInvoice(
        invoiceNumber: 'VOID-TEST-004',
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
          ),
        ],
      );

      await db.voidSalesInvoice(invoiceId, reason: 'حفظ السجل', deletedBy: userId);

      // The invoice should still exist with status 'voided'
      final inv = await (db.select(db.salesInvoices)
            ..where((i) => i.id.equals(invoiceId)))
          .getSingleOrNull();
      expect(inv, isNotNull, reason: 'Voided invoice must remain in database');
      expect(inv!.status, 'voided');
      expect(inv.notes, contains('ملغي'));
    });
  });
}
