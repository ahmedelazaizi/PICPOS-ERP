// ═══════════════════════════════════════════════════════════════════════════
// Field bugs in the جرد (stock-audit / cycle-count) area — regression tests.
//
// BUG-A: the stock-audit "add item" flow must add a row ONCE (actual = expected),
//        NOT accumulate +1 like a per-unit barcode scan.
// BUG-B: cycle-count items must resolve the real product name + category name
//        (the screen used to render "صنف #<id>").
// BUG-C: a cycle-count finalize with an UN-submitted count must not silently move
//        stock — the count has to be persisted first (the UI now flushes it).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int warehouseId;
  late int userId;

  setUp(() async {
    db = AppDatabase.forTesting();
    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(name: 'جارد', isSystemRole: const Value(false)),
        );
    userId = await db.createUser(
      username: 'counter', password: 'pw', displayName: 'Counter', roleId: roleId,
    );
    warehouseId = (await db.getDefaultWarehouse())!.id;
  });

  tearDown(() => db.close());

  Future<int> seedProduct(String code, {int? categoryId, double stock = 0}) async {
    final pid = await db.insertProduct(ProductsCompanion.insert(
      code: code, name: 'صنف $code',
      salePrice: const Value(0.0), costPrice: const Value(10.0),
      categoryId: Value(categoryId),
      trackInventory: const Value(true),
    ));
    if (stock != 0) {
      await db.adjustStock(
        productId: pid, warehouseId: warehouseId, quantity: stock, type: 'initial',
      );
    }
    return pid;
  }

  Future<double> balance(int pid) async {
    final b = await (db.select(db.inventoryBalances)
          ..where((x) => x.productId.equals(pid) & x.warehouseId.equals(warehouseId)))
        .getSingleOrNull();
    return b?.quantity ?? 0.0;
  }

  // ═══ BUG-A — stock-audit "add item" adds once, doesn't accumulate ═════════
  group('BUG-A: stock-audit add-item', () {
    test('addAuditItemOnce adds the row ONCE with actual = expected', () async {
      final pid = await seedProduct('AUD-1', stock: 12);
      final auditId = await db.createStockAudit(userId: userId);

      final added = await db.addAuditItemOnce(
        auditId: auditId, productId: pid, expectedQuantity: 12.0,
      );
      expect(added, isTrue);

      final items = await db.getAuditItems(auditId);
      expect(items.length, 1);
      // Neutral start: actual == expected (current stock), difference 0.
      expect(items.first.actualQuantity, 12.0);
      expect(items.first.expectedQuantity, 12.0);
      expect(items.first.difference, 0.0);
    });

    test('re-adding the same item is a no-op (no accumulation)', () async {
      final pid = await seedProduct('AUD-2', stock: 5);
      final auditId = await db.createStockAudit(userId: userId);

      expect(await db.addAuditItemOnce(auditId: auditId, productId: pid, expectedQuantity: 5.0), isTrue);
      // Second "add" for the same item must NOT create a row nor bump the count.
      expect(await db.addAuditItemOnce(auditId: auditId, productId: pid, expectedQuantity: 5.0), isFalse);

      final items = await db.getAuditItems(auditId);
      expect(items.length, 1);
      expect(items.first.actualQuantity, 5.0, reason: 'add-item must not accumulate');
    });

    test('a genuine per-unit scan DOES accumulate (unchanged path)', () async {
      final pid = await seedProduct('AUD-3', stock: 0);
      final auditId = await db.createStockAudit(userId: userId);

      // scanBarcode's behaviour: read existing, save actual = existing + 1.
      Future<void> scanOnce() async {
        final existing = (await db.getAuditItems(auditId))
            .where((i) => i.productId == pid)
            .fold<double>(0, (_, i) => i.actualQuantity);
        await db.saveAuditItem(
          auditId: auditId, productId: pid, expectedQuantity: 0.0,
          actualQuantity: existing + 1,
        );
      }

      await scanOnce();
      await scanOnce();
      await scanOnce();

      final items = await db.getAuditItems(auditId);
      expect(items.length, 1);
      expect(items.first.actualQuantity, 3.0, reason: 'three scans → actual 3');
    });
  });

  // ═══ BUG-B — cycle-count items resolve product + category names ═══════════
  group('BUG-B: cycle-count item names', () {
    test('getCycleCountItemsWithProduct returns real product + category names', () async {
      final catId = await db.into(db.categories).insert(
            CategoriesCompanion.insert(name: 'مشروبات'),
          );
      final pid = await seedProduct('CYC-N', categoryId: catId, stock: 30);

      final planId = await db.createCycleCountPlan(
        name: 'خطة', warehouseId: warehouseId, frequency: 'monthly', productsPerTask: 50,
      );
      final taskId = await db.generateCycleCountTask(
        planId: planId, warehouseId: warehouseId, productsPerTask: 50,
      );

      final views = await db.getCycleCountItemsWithProduct(taskId);
      final v = views.firstWhere((x) => x.productId == pid);
      expect(v.productName, 'صنف CYC-N', reason: 'real product name, not "صنف #<id>"');
      expect(v.categoryName, 'مشروبات');
      expect(v.productCode, 'CYC-N');
      // count fields still delegate through to the underlying row
      expect(v.expectedQty, 30.0);
    });
  });

  // ═══ BUG-C — un-submitted count must not silently move stock ══════════════
  group('BUG-C: finalize needs a persisted count', () {
    test('finalize with NO submitted count leaves stock unchanged', () async {
      // This is the exact data-layer symptom the UI fix guards against: without
      // a persisted countedQty, applyCycleCountAdjustments skips the item, so
      // finalize adjusts nothing (the old UI still toasted success).
      final pid = await seedProduct('CYC-U', stock: 100);
      final planId = await db.createCycleCountPlan(
        name: 'خطة', warehouseId: warehouseId, frequency: 'monthly', productsPerTask: 50,
      );
      final taskId = await db.generateCycleCountTask(
        planId: planId, warehouseId: warehouseId, productsPerTask: 50,
      );
      await db.startCycleCountTask(taskId);

      // Deliberately DO NOT submitCount — mimic "typed but never persisted".
      await db.finalizeCycleCountTask(taskId);

      expect(await balance(pid), 100.0, reason: 'no persisted count → no stock change');
    });

    test('finalize AFTER a persisted count moves stock to the counted qty', () async {
      final pid = await seedProduct('CYC-S', stock: 100);
      final planId = await db.createCycleCountPlan(
        name: 'خطة', warehouseId: warehouseId, frequency: 'monthly', productsPerTask: 50,
      );
      final taskId = await db.generateCycleCountTask(
        planId: planId, warehouseId: warehouseId, productsPerTask: 50,
      );
      await db.startCycleCountTask(taskId);

      final item = (await db.getCycleCountItems(taskId)).firstWhere((i) => i.productId == pid);
      await db.submitCount(itemId: item.id, countedQty: 92.0);
      await db.finalizeCycleCountTask(taskId);

      expect(await balance(pid), 92.0, reason: 'persisted count → stock moves');
    });
  });
}
