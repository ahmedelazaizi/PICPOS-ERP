// ═══════════════════════════════════════════════════════════════════════════
// POS Full Sale Flow — E2E Integration Tests (Gap A)
//
// Covers the complete point-of-sale sale lifecycle:
//   - Cash sale: stock deducted, safe credited
//   - Split payment (cash + bank): both safes updated
//   - Sale to customer: party AR balance updated
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int warehouseId;
  late int userId;

  Future<int> seedProduct(String code, {double salePrice = 100.0, double costPrice = 60.0, double stock = 50.0}) async {
    final id = await db.insertProduct(
      ProductsCompanion.insert(
        code: code,
        name: 'منتج $code',
        salePrice: Value(salePrice),
        costPrice: Value(costPrice),
        trackInventory: const Value(true),
      ),
    );
    await db.adjustStock(
      productId: id,
      warehouseId: warehouseId,
      quantity: stock,
      type: 'initial',
    );
    return id;
  }

  setUp(() async {
    db = AppDatabase.forTesting();

    final roleId = await db.into(db.roles).insert(
      RolesCompanion.insert(name: 'كاشير', isSystemRole: const Value(false)),
    );
    userId = await db.createUser(
      username: 'cashier1',
      password: 'pw',
      displayName: 'Cashier',
      roleId: roleId,
    );

    final wh = await db.getDefaultWarehouse();
    warehouseId = wh!.id;
  });

  tearDown(() => db.close());

  // ─────────────────────────────────────────────────────────────────────────
  group('POS Cash Sale', () {
    // ─────────────────────────────────────────────────────────────────────
    test('stock decreases and cash safe is credited after cash sale', () async {
      final productId = await seedProduct('POS-001', salePrice: 50.0, stock: 20.0);
      final cashSafe = await db.getDefaultSafeByType('cash');
      final safeBalanceBefore = cashSafe!.balance;

      await db.createSalesInvoice(
        invoiceNumber: 'POS-CASH-001',
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 150.0,
        discount: 0.0,
        tax: 0.0,
        total: 150.0,
        paid: 150.0,
        paymentMethod: 'cash',
        cashSafeId: cashSafe.id,
        cashAmount: 150.0,
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 3.0,
            unitPrice: 50.0,
            total: 150.0,
          ),
        ],
      );

      final stockAfter = await _getWarehouseStock(db, productId, warehouseId);
      expect(stockAfter, equals(17.0), reason: '20 - 3 = 17 units remaining');

      final safeAfter = await db.getDefaultSafeByType('cash');
      expect(safeAfter!.balance, equals(safeBalanceBefore + 150.0));
    });

    test('multiple line items are all deducted from stock', () async {
      final p1 = await seedProduct('POS-002A', salePrice: 40.0, stock: 10.0);
      final p2 = await seedProduct('POS-002B', salePrice: 60.0, stock: 10.0);

      final cashSafe = await db.getDefaultSafeByType('cash');
      await db.createSalesInvoice(
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 200.0,
        discount: 0.0,
        tax: 0.0,
        total: 200.0,
        paid: 200.0,
        paymentMethod: 'cash',
        cashSafeId: cashSafe!.id,
        cashAmount: 200.0,
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: p1,
            quantity: 2.0,
            unitPrice: 40.0,
            total: 80.0,
          ),
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: p2,
            quantity: 2.0,
            unitPrice: 60.0,
            total: 120.0,
          ),
        ],
      );

      expect(await _getWarehouseStock(db, p1, warehouseId), equals(8.0));
      expect(await _getWarehouseStock(db, p2, warehouseId), equals(8.0));
    });

    test('discount reduces the total but not the quantity deducted', () async {
      final productId = await seedProduct('POS-003', salePrice: 100.0, stock: 10.0);
      final cashSafe = await db.getDefaultSafeByType('cash');

      await db.createSalesInvoice(
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 200.0,
        discount: 20.0,
        tax: 0.0,
        total: 180.0,
        paid: 180.0,
        paymentMethod: 'cash',
        cashSafeId: cashSafe!.id,
        cashAmount: 180.0,
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 2.0,
            unitPrice: 100.0,
            total: 200.0,
          ),
        ],
      );

      final stock = await _getWarehouseStock(db, productId, warehouseId);
      expect(stock, equals(8.0), reason: 'Discount does not affect quantity');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('POS Split Payment', () {
    // ─────────────────────────────────────────────────────────────────────
    test('split cash+bank payment credits both safes correctly', () async {
      final productId = await seedProduct('POS-SPLIT-001', salePrice: 200.0, stock: 5.0);
      final cashSafe = await db.getDefaultSafeByType('cash');
      final bankSafe = await db.getDefaultSafeByType('bank');
      if (bankSafe == null) return; // skip if no bank safe seeded

      final cashBefore = cashSafe!.balance;
      final bankBefore = bankSafe.balance;

      await db.createSalesInvoice(
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 200.0,
        discount: 0.0,
        tax: 0.0,
        total: 200.0,
        paid: 200.0,
        paymentMethod: 'multiple',
        cashSafeId: cashSafe.id,
        cashAmount: 100.0,
        bankSafeId: bankSafe.id,
        bankAmount: 100.0,
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

      final cashAfter = await db.getDefaultSafeByType('cash');
      final bankAfter = await db.getDefaultSafeByType('bank');
      expect(cashAfter!.balance, equals(cashBefore + 100.0));
      expect(bankAfter!.balance, equals(bankBefore + 100.0));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('POS Customer Sale (AR)', () {
    // ─────────────────────────────────────────────────────────────────────
    test('sale on credit increases customer AR balance', () async {
      final productId = await seedProduct('POS-AR-001', salePrice: 120.0, stock: 10.0);
      final customerId = await db.into(db.parties).insert(
        PartiesCompanion.insert(name: 'عميل اختبار', isCustomer: const Value(true)),
      );

      final cashSafe = await db.getDefaultSafeByType('cash');
      await db.createSalesInvoice(
        warehouseId: warehouseId,
        userId: userId,
        customerId: customerId,
        subtotal: 240.0,
        discount: 0.0,
        tax: 0.0,
        total: 240.0,
        paid: 0.0, // credit sale — nothing paid up front
        paymentMethod: 'credit',
        cashSafeId: cashSafe?.id,
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 2.0,
            unitPrice: 120.0,
            total: 240.0,
          ),
        ],
      );

      final customer = await (db.select(db.parties)
            ..where((p) => p.id.equals(customerId)))
          .getSingle();
      expect(customer.balance, greaterThan(0), reason: 'Customer owes 240 on credit sale');

      final stock = await _getWarehouseStock(db, productId, warehouseId);
      expect(stock, equals(8.0));
    });
  });
}

Future<double> _getWarehouseStock(AppDatabase db, int productId, int warehouseId) async {
  final balance = await (db.select(db.inventoryBalances)
        ..where((b) => b.productId.equals(productId) & b.warehouseId.equals(warehouseId)))
      .getSingleOrNull();
  return balance?.quantity ?? 0.0;
}
