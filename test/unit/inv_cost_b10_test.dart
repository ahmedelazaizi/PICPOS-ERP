// ═══════════════════════════════════════════════════════════════════════════
// Spec 149 pre-deploy batch B10 — S-INV-COST
// ═══════════════════════════════════════════════════════════════════════════
//
// Fix 1 (PUR-1 / INV-2) — createPurchaseInvoice / updatePurchaseInvoice now
//   thread the receipt line's real unitCost into adjustStock(), and
//   adjustStock now forwards a real unitCost (on a positive-quantity inflow)
//   into _updateWarehouseBalance's `cost:` argument instead of always using
//   product.costPrice. Before this fix, the per-warehouse
//   inventory_balances.average_cost blend used the GLOBAL WAC — which, by
//   the time adjustStock ran, had ALREADY been re-blended by
//   updateProductWAC to include THIS SAME receipt — so the warehouse blend
//   effectively double-counted the receipt and drifted from the true
//   per-warehouse receipt cost on any price change / multi-warehouse setup.
//
// Fix 2 (INV-3) — updateProductWAC and _updateWarehouseBalance now guard a
//   negative RESULT, not just a non-positive denominator. If stock was
//   already negative (oversold via allowNegativeSale) and a restock brings
//   the total back above zero, the blend's numerator can still be deeply
//   negative even though qty+new > 0 — that used to write a negative
//   costPrice / average_cost straight into the WAC columns. Mirrors the
//   guard reverseProductWAC already had (falls back to
//   recalculateProductWAC for the global column; clamps to the incoming
//   receipt cost for the per-warehouse column, since there is no per-
//   warehouse recalc helper).
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int branchId;
  late int warehouseId;
  late int warehouseId2;
  late int supplierId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();

    branchId = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'main-b10',
            globalId: const Value('gid-br-b10'),
          ),
        );
    warehouseId = await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(
            name: 'wh-b10-a',
            branchId: Value(branchId),
            globalId: const Value('gid-wh-b10-a'),
          ),
        );
    warehouseId2 = await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(
            name: 'wh-b10-b',
            branchId: Value(branchId),
            globalId: const Value('gid-wh-b10-b'),
          ),
        );
    supplierId = await db.into(db.parties).insert(
          PartiesCompanion.insert(
            name: 'مورد B10',
            isSupplier: const Value(true),
            isCustomer: const Value(false),
            globalId: const Value('gid-supplier-b10'),
          ),
        );
  });

  tearDown(() async => db.close());

  Future<int> makeProduct(String code, {bool allowNegativeSale = false}) {
    return db.insertProduct(
      ProductsCompanion.insert(
        code: code,
        name: 'منتج اختبار $code',
        salePrice: const Value(200.0),
        costPrice: const Value(0.0),
        currentStock: const Value(0),
        trackInventory: const Value(true),
        allowNegativeSale: Value(allowNegativeSale),
      ),
    );
  }

  /// Posts an UNPAID (credit) purchase invoice for a single line — mirrors
  /// the B8 test helper. Routes through the real createPurchaseInvoice DAO
  /// method so both updateProductWAC AND adjustStock run exactly as they do
  /// in production.
  Future<int> creditPurchase({
    required int productId,
    required int whId,
    required double qty,
    required double unitCost,
  }) {
    final total = qty * unitCost;
    return db.createPurchaseInvoice(
      supplierId: supplierId,
      warehouseId: whId,
      paid: 0.0,
      paymentMethod: 'credit',
      items: [
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: qty,
          unitCost: unitCost,
          total: total,
        ),
      ],
    );
  }

  Future<double?> warehouseAverageCost(int productId, int whId) async {
    final row = await (db.select(db.inventoryBalances)
          ..where((b) =>
              b.productId.equals(productId) & b.warehouseId.equals(whId)))
        .getSingleOrNull();
    return row?.averageCost;
  }

  // ───────────────────────────────────────────────────────────────────────
  // PUR-1 / INV-2 — per-warehouse average_cost blends the RECEIPT unitCost
  // ───────────────────────────────────────────────────────────────────────
  group('PUR-1 — per-warehouse average_cost blends the receipt unitCost', () {
    test(
        'same warehouse, two purchases at different costs → correct weighted '
        'blend (30.0), not the double-blended global-WAC artifact', () async {
      final productId = await makeProduct('B10-PUR1-A');

      await creditPurchase(
          productId: productId, whId: warehouseId, qty: 10, unitCost: 20);
      await creditPurchase(
          productId: productId, whId: warehouseId, qty: 10, unitCost: 40);

      final avg = await warehouseAverageCost(productId, warehouseId);
      expect(avg, isNotNull);
      // True weighted blend of the two RECEIPTS: (10*20 + 10*40) / 20 = 30.0.
      // The pre-fix bug fed the ALREADY-updated global WAC (which by the
      // second purchase had itself become 30.0, folding in unitCost=40) back
      // into the warehouse blend as `cost`, producing
      // (10*20 + 10*30) / 20 = 25.0 instead — a silent drift from the real
      // receipt cost.
      expect(avg!, closeTo(30.0, 0.001));
    });

    test(
        'two DIFFERENT warehouses at different receipt costs → each '
        'warehouse keeps ITS OWN cost, not a shared global WAC', () async {
      final productId = await makeProduct('B10-PUR1-B');

      await creditPurchase(
          productId: productId, whId: warehouseId, qty: 10, unitCost: 20);
      await creditPurchase(
          productId: productId, whId: warehouseId2, qty: 10, unitCost: 100);

      final avg1 = await warehouseAverageCost(productId, warehouseId);
      final avg2 = await warehouseAverageCost(productId, warehouseId2);
      final globalWac = (await db.getProductById(productId))!.costPrice;

      // Sanity: the GLOBAL WAC blends BOTH warehouses' receipts —
      // (10*20 + 10*100) / 20 = 60.0.
      expect(globalWac, closeTo(60.0, 0.001));

      expect(avg1, isNotNull);
      expect(avg2, isNotNull);
      expect(avg1!, closeTo(20.0, 0.001),
          reason: 'warehouse #1 only ever received stock at 20');
      expect(avg2!, closeTo(100.0, 0.001),
          reason: 'warehouse #2 only ever received stock at 100');
      expect(avg1, isNot(closeTo(globalWac, 0.001)));
      expect(avg2, isNot(closeTo(globalWac, 0.001)));
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // INV-3 — negative-RESULT guard (not just non-positive denominator)
  // ───────────────────────────────────────────────────────────────────────
  group('INV-3 — negative WAC result guard on restock-after-oversell', () {
    test(
        'global products.costPrice never goes negative after an oversold '
        'restock — falls back to recalculateProductWAC', () async {
      final productId =
          await makeProduct('B10-INV3-G', allowNegativeSale: true);

      await creditPurchase(
          productId: productId, whId: warehouseId, qty: 10, unitCost: 50);
      expect((await db.getProductById(productId))!.costPrice,
          closeTo(50.0, 0.001));

      // Oversell into negative stock (allowNegativeSale permits it).
      await db.adjustStock(
        productId: productId,
        warehouseId: warehouseId,
        quantity: -30,
        type: 'sale',
      );
      expect((await db.getProductById(productId))!.currentStock,
          closeTo(-20.0, 0.001));

      // Restock at a low cost while still net-negative. Raw formula:
      // ((-20*50) + (25*1)) / 5 = -195 — must NOT land in costPrice.
      await creditPurchase(
          productId: productId, whId: warehouseId, qty: 25, unitCost: 1);

      final costAfter = (await db.getProductById(productId))!.costPrice;
      expect(costAfter, greaterThanOrEqualTo(0),
          reason: 'INV-3 guard must intercept the negative raw WAC (-195) '
              'and fall back to recalculateProductWAC instead of writing it');

      // ── ٢‑٧: الاحتياطيُّ لم يعد «متوسّطَ الشراء مدى الحياة» ────────────
      //
      // كان هنا `expect(costAfter, closeTo(15.0, 0.001))` بحجّة أنّ
      // «الاحتياطيَّ السليم = مزيجُ الشراء التاريخيّ كلِّه: (10@50 + 25@1)/35».
      // وذلك رقمٌ **لا يقابله شيءٌ في الأستاذ**: يقسم تكلفةَ كلِّ وحدةٍ
      // اشتُريت على عددِ كلِّ وحدةٍ اشتُريت، فيتجاهل أنّ ٣٠ وحدةً خرجت.
      // والنتيجةُ المقيسة بـ`getInventoryGlReconciliation` في السيناريو
      // النظيف (‏شراء ١٠@١٠ ← بيع ٥ ← شراء ١٠@٢٠ ← إعادةُ حساب): تقييمٌ
      // ٢٢٥ مقابل أستاذٍ ٢٥٠ — انحرافٌ ٢٥ بلا قيدٍ ولا خطأ، ثمّ يتسرّب
      // الرقمُ إلى تكلفة كلِّ بيعةٍ لاحقة.
      //
      // فالدالّةُ صارت تشتقّ التكلفةَ من دفتر الحركات (‏القيمةُ المتبقّية ÷
      // الموجود). وفي **هذه** الحالة الشاذّة القيمةُ المتبقّيةُ سالبةٌ
      // (‏٥٠٠ − ١٥٠٠ + ٢٥ = −٩٧٥ على موجودٍ ٥) فلا تكلفةَ وحدةٍ صالحة —
      // فتُترَك القيمةُ السابقةُ كما هي بدل اختراع رقمٍ يبدو معقولاً ويُخفي
      // الشذوذ. وهذا **عينُ** ما تريده INV-3: ألّا تُكتَب قيمةٌ سالبة.
      expect(costAfter, closeTo(50.0, 0.001),
          reason: 'التكلفةُ السابقة (‏٥٠ من الشراء الأوّل) تبقى — الشذوذُ '
              'يبقى مرئيّاً في تقرير المصالحة بدل أن يُطمَس برقمٍ مخترَع');
    });

    test(
        'per-warehouse average_cost never goes negative after an oversold '
        'restock — clamps to the incoming receipt cost', () async {
      final productId =
          await makeProduct('B10-INV3-W', allowNegativeSale: true);

      await creditPurchase(
          productId: productId, whId: warehouseId, qty: 10, unitCost: 50);
      expect(await warehouseAverageCost(productId, warehouseId),
          closeTo(50.0, 0.001));

      await db.adjustStock(
        productId: productId,
        warehouseId: warehouseId,
        quantity: -30,
        type: 'sale',
      );
      final balAfterSale = await (db.select(db.inventoryBalances)
            ..where((b) =>
                b.productId.equals(productId) &
                b.warehouseId.equals(warehouseId)))
          .getSingle();
      expect(balAfterSale.quantity, closeTo(-20.0, 0.001));
      expect(balAfterSale.averageCost, closeTo(50.0, 0.001),
          reason: 'sanity: deductions never touch average_cost');

      // Raw formula for the warehouse blend too: ((-20*50) + (25*1)) / 5 =
      // -195 — must clamp instead of going negative.
      await creditPurchase(
          productId: productId, whId: warehouseId, qty: 25, unitCost: 1);

      final avgAfter = await warehouseAverageCost(productId, warehouseId);
      expect(avgAfter, isNotNull);
      expect(avgAfter!, greaterThanOrEqualTo(0),
          reason: 'INV-3 warehouse guard must clamp instead of writing the '
              'negative raw result (-195)');
      // No per-warehouse recalc helper exists, so the guard clamps to the
      // incoming receipt cost (1.0) — the one trustworthy price for this
      // event.
      expect(avgAfter, closeTo(1.0, 0.001));
    });
  });
}
