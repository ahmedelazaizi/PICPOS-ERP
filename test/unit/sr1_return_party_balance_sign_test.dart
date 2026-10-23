// ═══════════════════════════════════════════════════════════════════════════
// Pre-deploy batch B3 — SR-1: return must CREDIT (reduce) the customer's AR,
// not increase it
// ═══════════════════════════════════════════════════════════════════════════
//
// createSalesInvoice() is shared by sales AND returns (via `saleType`). Its
// customer-balance update used to do:
//   remaining = total - paid;
//   if (customerId != null && remaining > 0) adjustPartyBalance(customerId, remaining);
// unconditionally, for BOTH sale and return. adjustPartyBalance(id, amount)
// does `balance += amount` (positive = customer owes MORE).
//
// For a credit-sale RETURN, the DAO is called with total=+returnTotal,
// paid=cashRefund, so remaining = the AR portion refunded (arRefund). Adding
// +arRefund to the balance INCREASED the customer's debt instead of
// reducing it — while autoPostSalesReturn (same file) correctly CREDITS AR
// in the GL by the same arRefund. parties.balance and the GL diverged by
// ~2x arRefund on every credit-sale return.
//
// The fix threads `saleType` into the sign: sale → +remaining (unchanged),
// return → -remaining. This suite pins:
//   1. A credit sale still increases the customer's balance (unchanged
//      behavior — regression guard on the non-return path).
//   2. A full return of that credit sale DECREASES the balance back toward
//      zero (the SR-1 fix), not further away from it.
//   3. A cash-sale return (paid == total, remaining == 0) leaves the
//      balance untouched — the `remaining > 0` guard still short-circuits,
//      so the already-correct cash-return path is unaffected.
//
// Harness mirrors test/unit/process_sales_return_happy_path_test.dart's
// seeding pattern (role → createUser, getDefaultWarehouse, insertProduct +
// adjustStock) since that suite already exercises createSalesInvoice +
// autoPost successfully against AppDatabase.forTesting()'s startup seed.

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int userId;
  late int warehouseId;
  late int productId;

  setUp(() async {
    db = AppDatabase.forTesting();

    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(name: 'كاشير', isSystemRole: const Value(false)),
        );
    userId = await db.createUser(
      username: 'sr1_user',
      password: 'test',
      displayName: 'SR-1 Test User',
      roleId: roleId,
    );

    final wh = await db.getDefaultWarehouse();
    warehouseId = wh!.id;

    productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'SR1-P1',
        name: 'منتج اختبار SR-1',
        salePrice: const Value(100.0),
        costPrice: const Value(60.0),
        currentStock: const Value(0.0),
        trackInventory: const Value(true),
      ),
    );
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 50.0,
      type: 'in',
      notes: 'seed',
    );
  });

  tearDown(() async => db.close());

  Future<int> seedCustomer() => db.into(db.parties).insert(
        PartiesCompanion.insert(
          name: 'عميل اختبار SR-1',
          isCustomer: const Value(true),
          balance: const Value(0.0),
        ),
      );

  Future<double> partyBalance(int partyId) async {
    final p = await (db.select(db.parties)..where((t) => t.id.equals(partyId)))
        .getSingle();
    return p.balance;
  }

  group('SR-1 — createSalesInvoice customer-balance sign', () {
    test('credit sale (paid < total) INCREASES the customer balance '
        '(sale sign unaffected by the fix)', () async {
      final customerId = await seedCustomer();

      await db.createSalesInvoice(
        invoiceNumber: 'SR1-SALE-001',
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 300.0,
        discount: 0.0,
        tax: 0.0,
        total: 300.0,
        paid: 0.0, // fully on credit
        paymentMethod: 'credit',
        customerId: customerId,
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 3.0,
            unitPrice: 100.0,
            total: 300.0,
            costPrice: const Value(60.0),
          ),
        ],
      );

      expect(await partyBalance(customerId), 300.0,
          reason: 'credit sale must still increase what the customer owes');
    });

    test('a full RETURN of a credit sale DECREASES the balance back toward '
        'zero (SR-1 fix) instead of increasing it further', () async {
      final customerId = await seedCustomer();

      final saleId = await db.createSalesInvoice(
        invoiceNumber: 'SR1-SALE-002',
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 300.0,
        discount: 0.0,
        tax: 0.0,
        total: 300.0,
        paid: 0.0,
        paymentMethod: 'credit',
        customerId: customerId,
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 3.0,
            unitPrice: 100.0,
            total: 300.0,
            costPrice: const Value(60.0),
          ),
        ],
      );
      expect(await partyBalance(customerId), 300.0,
          reason: 'sanity check on the pre-return balance');

      final saleItems = await db.getSalesInvoiceItems(saleId);

      // Full return: nothing was paid on the original sale, so nothing is
      // cash-refunded either — the whole 300 is an AR credit (arRefund).
      await db.createSalesInvoice(
        invoiceNumber: 'SR1-RET-002',
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 300.0,
        discount: 0.0,
        tax: 0.0,
        total: 300.0,
        paid: 0.0,
        paymentMethod: 'credit',
        customerId: customerId,
        saleType: 'return',
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 3.0,
            unitPrice: 100.0,
            total: 300.0,
            costPrice: Value(saleItems.first.costPrice),
          ),
        ],
      );

      expect(await partyBalance(customerId), 0.0,
          reason: 'SR-1: the return must CREDIT (reduce) the AR it just '
              'increased, not pile another +300 on top of it (pre-fix this '
              'would have read 600.0)');
    });

    test('cash-sale return (paid == total, remaining == 0) leaves the '
        'balance UNCHANGED — the >0 guard still short-circuits', () async {
      final customerId = await seedCustomer();

      await db.createSalesInvoice(
        invoiceNumber: 'SR1-SALE-003',
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 100.0,
        discount: 0.0,
        tax: 0.0,
        total: 100.0,
        paid: 100.0, // fully paid cash — no AR at all
        paymentMethod: 'cash',
        customerId: customerId,
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 1.0,
            unitPrice: 100.0,
            total: 100.0,
            costPrice: const Value(60.0),
          ),
        ],
      );
      expect(await partyBalance(customerId), 0.0,
          reason: 'cash sale never touches AR (remaining == 0)');

      await db.createSalesInvoice(
        invoiceNumber: 'SR1-RET-003',
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 100.0,
        discount: 0.0,
        tax: 0.0,
        total: 100.0,
        paid: 100.0, // fully cash-refunded — remaining == 0
        paymentMethod: 'cash',
        customerId: customerId,
        saleType: 'return',
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 1.0,
            unitPrice: 100.0,
            total: 100.0,
            costPrice: const Value(60.0),
          ),
        ],
      );

      expect(await partyBalance(customerId), 0.0,
          reason: 'cash-sale return path must stay untouched by the SR-1 fix');
    });

    test('a credit RETURN for a customer near their credit limit is NOT '
        'blocked by the credit-limit guard and still reduces the balance',
        () async {
      // Customer with a 1000 credit limit.
      final customerId = await db.into(db.parties).insert(
            PartiesCompanion.insert(
              name: 'عميل قرب الحد الائتماني SR-1',
              isCustomer: const Value(true),
              balance: const Value(0.0),
              creditLimit: const Value(1000.0),
            ),
          );

      // Initial credit sale of 950 → balance 950, still under the 1000 limit
      // (projected 0 + 950 < 1000 → passes the guard on the sale path).
      final saleId = await db.createSalesInvoice(
        invoiceNumber: 'SR1-SALE-004',
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 950.0,
        discount: 0.0,
        tax: 0.0,
        total: 950.0,
        paid: 0.0,
        paymentMethod: 'credit',
        customerId: customerId,
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 9.5,
            unitPrice: 100.0,
            total: 950.0,
            costPrice: const Value(60.0),
          ),
        ],
      );
      expect(await partyBalance(customerId), 950.0,
          reason: 'sanity: customer is now 950 against a 1000 limit');

      final saleItems = await db.getSalesInvoiceItems(saleId);

      // Full credit return of the 950. Pre-fix, the credit-limit guard was
      // entered for returns too: projectedBalance = 950 (current) + 950
      // (remaining) = 1900 > 1000, and the fresh cashier has no override →
      // it threw 'تجاوز العميل الحد الائتماني' and the return was rejected.
      // Post-fix the guard excludes returns, so this must NOT throw and the
      // balance must DECREASE (the return credits the AR it created).
      await db.createSalesInvoice(
        invoiceNumber: 'SR1-RET-004',
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 950.0,
        discount: 0.0,
        tax: 0.0,
        total: 950.0,
        paid: 0.0,
        paymentMethod: 'credit',
        customerId: customerId,
        saleType: 'return',
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 9.5,
            unitPrice: 100.0,
            total: 950.0,
            costPrice: Value(saleItems.first.costPrice),
          ),
        ],
      );

      expect(await partyBalance(customerId), 0.0,
          reason: 'SR-1 guard fix: the credit return was applied (balance '
              'reduced from 950 → 0), not blocked by the credit-limit check');
    });
  });
}
