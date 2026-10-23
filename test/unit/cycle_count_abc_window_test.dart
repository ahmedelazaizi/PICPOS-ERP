// ═══════════════════════════════════════════════════════════════════════════
// نافذةُ الـ٩٠ يوماً في توليد مهامّ الجرد الدوريّ (ABC)
// ═══════════════════════════════════════════════════════════════════════════
//
// `generateCycleCountTask` ترتِّب الأصنافَ بقيمةِ حركتها في آخر ٩٠ يوماً، وكانت
// تقارن `sm.created_at > datetime('now', '-90 days')`: عمودٌ يخزِّنه drift عدداً
// صحيحاً بثواني الحقبة، في مواجهةِ نصِّ تاريخٍ من SQLite. وترتيبُ الأنواع في
// SQLite يضع كلَّ عددٍ صحيحٍ قبل أيِّ نصّ، فالشرطُ كاذبٌ دائماً: `movement_value`
// يساوي صفراً لكلِّ صنف، فيسقط ترتيبُ ABC صامتاً إلى ترتيب rowid. (وعلى
// PostgreSQL لا وجودَ لدالّة `datetime` أصلاً.)
//
// هذا الاختبارُ يزرع صنفاً قيمتُه ضخمةٌ لكنّها خارجَ النافذة، وآخرَ قيمتُه ضئيلةٌ
// لكنّها داخلها، ثمّ يؤكّد أنّ الداخلَ يسبق — وهو ما لا يتحقّق إلّا إذا كانت
// المقارنةُ تقع بين ثوانٍ وثوانٍ.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int warehouseId;
  late int planId;
  late int oldButBigId; // حركةٌ ضخمةٌ عمرُها ٩٥ يوماً — خارجَ النافذة
  late int recentSmallId; // حركةٌ ضئيلةٌ عمرُها ٨٥ يوماً — داخلَ النافذة

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.delete(db.stockMovements).go();

    warehouseId = await db.into(db.warehouses).insert(
      WarehousesCompanion.insert(
        name: 'مخزنُ الجرد',
        isActive: const Value(true),
      ),
    );

    // الترتيبُ في الإدراج مقصود: صاحبُ الحركة القديمة يأخذ المعرِّفَ الأصغر،
    // فلو تعادلت القيمُ عند صفرٍ (وهو عطبُ النصّ مقابل الثواني) لسبق بالـrowid.
    oldButBigId = await db.into(db.products).insert(
      ProductsCompanion.insert(
        code: 'CC-OLD',
        name: 'صنفٌ ركد منذ ٩٥ يوماً',
        costPrice: const Value(100.0),
        trackInventory: const Value(true),
      ),
    );
    recentSmallId = await db.into(db.products).insert(
      ProductsCompanion.insert(
        code: 'CC-NEW',
        name: 'صنفٌ تحرّك منذ ٨٥ يوماً',
        costPrice: const Value(10.0),
        trackInventory: const Value(true),
      ),
    );

    for (final productId in [oldButBigId, recentSmallId]) {
      await db.into(db.inventoryBalances).insert(
        InventoryBalancesCompanion.insert(
          productId: productId,
          warehouseId: warehouseId,
          quantity: const Value(5.0),
        ),
      );
    }

    final now = DateTime.now();
    // ٩٥ يوماً × (١٠٠ وحدة × ١٠٠ تكلفة) = ١٠٬٠٠٠ — لكنّها خارجَ النافذة.
    await db.into(db.stockMovements).insert(
      StockMovementsCompanion.insert(
        productId: oldButBigId,
        warehouseId: warehouseId,
        movementType: 'purchase',
        quantity: 100.0,
        unitCost: const Value(100.0),
        balanceAfter: 5.0,
        createdAt: Value(now.subtract(const Duration(days: 95))),
      ),
    );
    // ٨٥ يوماً × (١٠ وحدات × ١٠ تكلفة) = ١٠٠ — لكنّها داخلَ النافذة.
    await db.into(db.stockMovements).insert(
      StockMovementsCompanion.insert(
        productId: recentSmallId,
        warehouseId: warehouseId,
        movementType: 'purchase',
        quantity: 10.0,
        unitCost: const Value(10.0),
        balanceAfter: 5.0,
        createdAt: Value(now.subtract(const Duration(days: 85))),
      ),
    );

    planId = await db.into(db.cycleCountPlans).insert(
      CycleCountPlansCompanion.insert(
        name: 'خطّةُ الجرد',
        warehouseId: warehouseId,
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('generateCycleCountTask — نافذةُ الـ٩٠ يوماً', () {
    test('الحركةُ داخلَ النافذة تسبق الحركةَ الأضخمَ خارجها', () async {
      final taskId = await db.generateCycleCountTask(
        planId: planId,
        warehouseId: warehouseId,
        productsPerTask: 2,
      );
      expect(taskId, greaterThan(0));

      final items = await db.getCycleCountItems(taskId);
      expect(items.map((i) => i.productId).toList(),
          [recentSmallId, oldButBigId],
          reason: 'مقارنةُ الثواني بالنصّ تُصفِّر القيمتين فيعود ترتيبُ الـrowid');
    });

    test('حين يُطلب صنفٌ واحدٌ يقع الاختيارُ على المتحرِّك داخلَ النافذة', () async {
      final taskId = await db.generateCycleCountTask(
        planId: planId,
        warehouseId: warehouseId,
        productsPerTask: 1,
      );

      final items = await db.getCycleCountItems(taskId);
      expect(items.length, 1);
      expect(items.single.productId, recentSmallId);
    });
  });
}
