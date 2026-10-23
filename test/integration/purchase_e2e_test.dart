import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:picpos_erp/data/database/database.dart';

/// E2E Test: Complete Purchase Flow (Sprint 17)
/// Purchase → Stock Addition → Supplier Balance → WAC Update
void main() {
  late AppDatabase db;
  late int warehouseId;
  late int userId;
  late int productId;
  // ignore: unused_local_variable
  late int supplierId;

  setUp(() async {
    db = AppDatabase.forTesting();

    final roleId = await db.into(db.roles).insert(
      RolesCompanion.insert(name: 'مدير', isSystemRole: const Value(false)),
    );
    userId = await db.createUser(
      username: 'purchase_test',
      password: 'test123',
      displayName: 'Purchase Tester',
      roleId: roleId,
    );

    final wh = await db.getDefaultWarehouse();
    warehouseId = wh!.id;

    productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'PUR-01',
        name: 'منتج مشتريات',
        salePrice: const Value(150.0),
        costPrice: const Value(80.0),
        currentStock: const Value(20.0),
        trackInventory: const Value(true),
      ),
    );

    // Create supplier
    supplierId = await db.into(db.parties).insert(
      PartiesCompanion.insert(
        name: 'مورد تجريبي',
        isCustomer: const Value(false),
        isSupplier: const Value(true),
      ),
    );
  });

  tearDown(() async => db.close());

  group('E2E Purchase Flow', () {
    test('Purchase adds stock and records movement', () async {
      final initialProduct = await db.getProductById(productId);
      final initialStock = initialProduct!.currentStock;

      // Simulate purchase: add 30 units
      await db.adjustStock(
        productId: productId,
        warehouseId: warehouseId,
        quantity: 30,
        type: 'purchase',
        referenceType: 'purchase_invoice',
        referenceId: 1,
        notes: 'شراء 30 وحدة',
      );

      final afterPurchase = await db.getProductById(productId);
      expect(afterPurchase!.currentStock, initialStock + 30);

      // Verify movement
      final movements = await db.getMovementsForProduct(productId);
      expect(movements.any((m) => m.movementType == 'purchase'), isTrue);
    });

    test('Purchase creates payment voucher for supplier', () async {
      final cashSafe = await db.getDefaultSafeByType('cash');
      final initialBalance = cashSafe!.balance;

      // Pay supplier 2400 (30 units * 80 cost)
      await db.createPaymentVoucher(
        amount: 2400.0,
        category: 'supplier_payment',
        description: 'سداد مورد تجريبي',
        safeId: cashSafe.id,
        userId: userId,
      );

      final afterPayment = await db.getDefaultSafeByType('cash');
      expect(afterPayment!.balance, initialBalance - 2400.0);
    });

    test('WAC updates after purchase at different cost', () async {
      final before = await db.getProductById(productId);
      final initialCost = before!.costPrice;
      final initialStock = before.currentStock;

      // Purchase at higher cost
      const newUnitCost = 100.0;
      const newQuantity = 10.0;

      await db.updateProductWAC(
        productId: productId,
        newQuantity: newQuantity,
        newUnitCost: newUnitCost,
      );

      final after = await db.getProductById(productId);
      // WAC = (initialStock * initialCost + newQty * newCost) / (initialStock + newQty)
      final expectedWAC = (initialStock * initialCost + newQuantity * newUnitCost) /
          (initialStock + newQuantity);
      expect(after!.costPrice, closeTo(expectedWAC, 0.01));
    });

    test('Purchase + Sale cycle maintains correct stock', () async {
      // Purchase 50
      await db.adjustStock(
        productId: productId,
        warehouseId: warehouseId,
        quantity: 50,
        type: 'purchase',
        referenceType: 'purchase_invoice',
        referenceId: 2,
      );

      // Sell 15
      await db.adjustStock(
        productId: productId,
        warehouseId: warehouseId,
        quantity: -15,
        type: 'sale',
        referenceType: 'sales_invoice',
        referenceId: 1,
      );

      // Expected: 20 (initial) + 50 - 15 = 55
      final product = await db.getProductById(productId);
      expect(product!.currentStock, 55.0);
    });
  });
}
