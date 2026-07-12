// Spec 136 (field 2026-06-09) — Sales-report KPI cards must respect the SAME
// filters as the invoice list below them.
//
// Before the fix, getSalesAnalytics ignored paymentMethod + saleType (those
// were applied only client-side to the list), so picking "نقدي" showed a card
// that still summed EVERY payment method while the rows summed to cash-only.
// It also skipped an EMPTY warehouseIds list (region/branch picked but
// resolving to no warehouse), showing company-wide totals instead of zero.
//
// These tests lock both behaviours at the DAO layer — the single source the
// cards read from.

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int productId;
  final from = DateTime(2026, 1, 1);
  final to = DateTime(2026, 12, 31);
  final saleDate = DateTime(2026, 6, 1);

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(name: 'مخزن 1'),
        ); // id=1
    await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(name: 'مخزن 2'),
        ); // id=2
    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(
              name: 'مدير', isSystemRole: const Value(true)),
        );
    await db.createUser(
      username: 'user1',
      password: 'pass123',
      displayName: 'User One',
      roleId: roleId,
    );
    productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'P1',
        name: 'صنف',
        salePrice: const Value(100.0),
        trackInventory: const Value(false),
      ),
    );
  });

  tearDown(() async => db.close());

  Future<void> sale({
    required String number,
    required double subtotal,
    required double tax,
    required String paymentMethod,
    String saleType = 'default',
    int warehouseId = 1,
  }) async {
    await db.createSalesInvoice(
      invoiceNumber: number,
      warehouseId: warehouseId,
      userId: 1,
      subtotal: subtotal,
      discount: 0.0,
      tax: tax,
      total: subtotal + tax,
      paid: subtotal + tax,
      paymentMethod: paymentMethod,
      saleType: saleType,
      invoiceDate: saleDate,
      items: [
        SalesInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: 1.0,
          unitPrice: subtotal,
          total: subtotal,
        ),
      ],
    );
  }

  group('Spec 136 — getSalesAnalytics filter parity', () {
    test('payment-method filter narrows the card totals (cash only)', () async {
      await sale(number: 'C1', subtotal: 100, tax: 15, paymentMethod: 'cash');
      await sale(number: 'K1', subtotal: 200, tax: 30, paymentMethod: 'card');
      await sale(number: 'T1', subtotal: 50, tax: 7.5, paymentMethod: 'transfer');

      final all = await db.getSalesAnalytics(from, to);
      expect(all.invoiceCount, 3);
      expect(all.totalSales, closeTo(115 + 230 + 57.5, 0.001));

      final cash = await db.getSalesAnalytics(from, to, paymentMethod: 'cash');
      expect(cash.invoiceCount, 1);
      expect(cash.totalSales, closeTo(115, 0.001));
      expect(cash.totalTax, closeTo(15, 0.001));
    });

    test('bank_group collapses card + transfer + bank', () async {
      await sale(number: 'C1', subtotal: 100, tax: 15, paymentMethod: 'cash');
      await sale(number: 'K1', subtotal: 200, tax: 30, paymentMethod: 'card');
      await sale(number: 'T1', subtotal: 50, tax: 7.5, paymentMethod: 'transfer');
      await sale(number: 'B1', subtotal: 80, tax: 0, paymentMethod: 'bank');

      final bankGroup =
          await db.getSalesAnalytics(from, to, paymentMethod: 'bank_group');
      // card(230) + transfer(57.5) + bank(80) = 367.5 ; cash excluded
      expect(bankGroup.invoiceCount, 3);
      expect(bankGroup.totalSales, closeTo(230 + 57.5 + 80, 0.001));
    });

    test('sale-type filter narrows the card totals', () async {
      await sale(number: 'D1', subtotal: 100, tax: 0, paymentMethod: 'cash');
      await sale(
          number: 'TL1',
          subtotal: 50,
          tax: 0,
          paymentMethod: 'cash',
          saleType: 'talabat');

      final talabat =
          await db.getSalesAnalytics(from, to, saleType: 'talabat');
      expect(talabat.invoiceCount, 1);
      expect(talabat.totalSales, closeTo(50, 0.001));
    });

    test('EMPTY warehouseIds (region with no warehouse) → zero, not all',
        () async {
      await sale(number: 'C1', subtotal: 100, tax: 15, paymentMethod: 'cash');

      // null = no filter → everything
      final unfiltered = await db.getSalesAnalytics(from, to);
      expect(unfiltered.invoiceCount, 1);

      // empty list = a region/branch was picked but resolves to NO warehouse
      // → the cards must agree with the (empty) list, i.e. show zero.
      final emptyScope =
          await db.getSalesAnalytics(from, to, warehouseIds: <int>[]);
      expect(emptyScope.invoiceCount, 0);
      expect(emptyScope.totalSales, 0.0);
    });

    test('warehouseIds still scopes correctly when non-empty', () async {
      await sale(
          number: 'W1',
          subtotal: 100,
          tax: 0,
          paymentMethod: 'cash',
          warehouseId: 1);
      await sale(
          number: 'W2',
          subtotal: 200,
          tax: 0,
          paymentMethod: 'cash',
          warehouseId: 2);

      final wh1 = await db.getSalesAnalytics(from, to, warehouseIds: [1]);
      expect(wh1.invoiceCount, 1);
      expect(wh1.totalSales, closeTo(100, 0.001));

      final whNone = await db.getSalesAnalytics(from, to, warehouseIds: [999]);
      expect(whNone.invoiceCount, 0);
    });
  });
}
