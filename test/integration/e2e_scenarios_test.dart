import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';

/// Enterprise E2E Verification Scenarios (Phase 4)
/// Covers core financial and operational flows for production readiness.
void main() {
  late AppDatabase db;
  late int warehouseId;
  late int branchId;
  late int userId;
  late int productId;

  setUp(() async {
    db = AppDatabase.forTesting();
    
    // Seed initial system data (roles, accounts, etc. are seeded in onCreate/beforeOpen)
    final roleId = await db.into(db.roles).insert(
      RolesCompanion.insert(name: 'مدير نظام', isSystemRole: const Value(true)),
    );
    
    userId = await db.createUser(
      username: 'admin_test',
      password: 'admin_password',
      displayName: 'Admin Tester',
      roleId: roleId,
    );

    // Spec 062: grant the void-paid-invoice critical-op permission so the
    // gate in voidSalesInvoice allows voiding fully-paid invoices.
    final voidPerm = await (db.select(db.permissions)
          ..where((p) => p.code.equals(PermissionCodes.voidPaidInvoice))
          ..limit(1))
        .getSingle();
    await db.addPermissionToRole(roleId, voidPerm.id);

    branchId = await db.into(db.branches).insert(
      BranchesCompanion.insert(name: 'فرع الرئيسي'),
    );

    warehouseId = await db.into(db.warehouses).insert(
      WarehousesCompanion.insert(
        name: 'المخزن الرئيسي',
        branchId: Value(branchId),
        isDefault: const Value(true),
      ),
    );

    // Create a base product
    productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'PROD-001',
        name: 'منتج تجريبي',
        salePrice: const Value(100.0),
        costPrice: const Value(50.0),
        currentStock: const Value(0.0),
        trackInventory: const Value(true),
      ),
    );
  });

  tearDown(() async => db.close());

  group('Enterprise E2E Scenarios', () {
    
    test('Scenario 1: Purchase -> Pay Supplier -> Check Balance', () async {
      final supplierId = await db.into(db.parties).insert(
        PartiesCompanion.insert(name: 'مورد تجريبي', isSupplier: const Value(true)),
      );

      // 1. Purchase Invoice (10 units @ 60 = 600 total)
      final invoiceId = await db.createPurchaseInvoice(
        supplierId: supplierId,
        warehouseId: warehouseId,
        paid: 0.0,
        items: [
          PurchaseInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 10.0,
            unitCost: 60.0,
            taxRate: const Value(0.0),
            total: 600.0,
          ),
        ],
      );

      expect(invoiceId, isPositive);
      
      // Verify supplier balance is now 600 (Credit)
      final supplier = await (db.select(db.parties)..where((p) => p.id.equals(supplierId))).getSingle();
      expect(supplier.balance, 600.0); // Natural balance for payables is positive here

      // 2. Pay Supplier (400.0)
      final safe = await db.getDefaultSafeByType('cash');
      await db.createPaymentVoucher(
        amount: 400.0,
        category: 'suppliers',
        partyId: supplierId,
        safeId: safe!.id,
        userId: userId,
      );

      // 3. Check Final Balance
      final finalSupplier = await (db.select(db.parties)..where((p) => p.id.equals(supplierId))).getSingle();
      expect(finalSupplier.balance, 200.0); // 600 - 400 = 200 remaining liability
    });

    test('Scenario 2: POS Sale -> Daily Summary -> Void Reversal', () async {
      // Setup: ensure stock exists
      await db.adjustStock(
        productId: productId,
        warehouseId: warehouseId,
        quantity: 10.0,
        type: 'adjustment',
      );

      // 1. Create Sale (2 units @ 100 = 200)
      final invoiceId = await db.createSalesInvoice(
        invoiceNumber: 'SALE-E2E-001',
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
            quantity: 2.0,
            unitPrice: 100.0,
            total: 200.0,
          ),
        ],
      );

      final productAfterSale = await db.getProductById(productId);
      expect(productAfterSale!.currentStock, 8.0);

      // 2. Void Sale (Reverse everything)
      await db.voidSalesInvoice(invoiceId, deletedBy: userId);

      // 3. Verify Reversal
      final productAfterVoid = await db.getProductById(productId);
      expect(productAfterVoid!.currentStock, 10.0); // Back to original

      final voidedInv = await (db.select(db.salesInvoices)..where((i) => i.id.equals(invoiceId))).getSingle();
      expect(voidedInv.status, 'voided');
      expect(voidedInv.isDeleted, isTrue);
    });

    test('Scenario 3: Asset Acquisition -> Depreciation -> Balance Sheet', () async {
      // Feature 004 (US1, FR-005) requires every asset category to be linked
      // to BOTH an asset CoA account (parent for the per-asset sub-account
      // FixedAssetsDao mints) AND an accumulated-depreciation account before
      // any asset can be created under it. The seeder ships canonical rows
      // for both — 1213 (الآلات والمعدات الصناعية) and 1219 (مجمع إهلاك
      // الآلات) — so we just look them up and link the category up front.
      final assetAccount = await (db.select(db.accounts)
            ..where((a) => a.code.equals('1213'))
            ..limit(1))
          .getSingle();
      final depreciationAccount = await (db.select(db.accounts)
            ..where((a) => a.code.equals('1219'))
            ..limit(1))
          .getSingle();

      // 1. Acquire Asset (Machine @ 12000, 10 years life, Straight Line)
      final categoryId = await db.createAssetCategory(
        name: 'آلات ومعدات',
        defaultUsefulLife: 10,
        defaultDepreciationMethod: 'straight_line',
        accountId: assetAccount.id,
        depreciationAccountId: depreciationAccount.id,
      );

      final assetId = await db.createFixedAsset(
        code: 'ASSET-001',
        name: 'ماكينة تصنيع',
        categoryId: categoryId,
        purchasePrice: 12000.0,
        purchaseDate: DateTime(2026, 1, 1),
        usefulLifeYears: 10,
      );

      // 2. Run Depreciation (1 month)
      // Recant logic: 12000 / (10 * 12) = 100 per month
      final count = await db.runMonthlyDepreciation(DateTime(2026, 1, 31));
      expect(count, 1);

      // 3. Verify Book Value
      final asset = await db.getFixedAssetById(assetId);
      expect(asset!.accumulatedDepreciation, 100.0);
      expect(asset.purchasePrice - asset.accumulatedDepreciation, 11900.0);
    });

    test('Scenario 4: User Multi-Branch Access -> Restricted Reporting', () async {
      // 1. Create another branch & user
      final branchId2 = await db.into(db.branches).insert(
        BranchesCompanion.insert(name: 'فرع الإسكندرية'),
      );
      
      final restrictedUserId = await db.createUser(
        username: 'branch_user',
        password: 'password123',
        displayName: 'Branch User',
      );

      // 2. Set restricted access to Branch 1 ONLY
      await db.setUserBranchAccess(restrictedUserId, [branchId]);

      // 3. Verify can access Branch 1 IDs
      final accessible = await db.getUserAccessibleBranchIds(restrictedUserId);
      expect(accessible, contains(branchId));
      expect(accessible, isNot(contains(branchId2)));

      // Logic check: verify that the application layer uses this for filtering
      // (This test confirms the DAO correctly stores/returns the restricted list)
    });

    test('Scenario 5: Negative Stock Guard -> Operation Rejection', () async {
      // Ensure product has 5 units
      await db.adjustStock(
        productId: productId,
        warehouseId: warehouseId,
        quantity: 5.0,
        type: 'adjustment',
      );

      // Attempt to adjust stock by -10 (insufficient)
      expect(
        () => db.adjustStock(
          productId: productId,
          warehouseId: warehouseId,
          quantity: -10.0,
          type: 'sale',
        ),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('الكمية المتوفرة'))),
      );
    });
  });
}
