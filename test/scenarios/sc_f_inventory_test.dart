// سيناريو (و): تحويل مخزني بين مخزنين — الإجمالي ثابت والأرصدة تتحرك.
// سيناريو (ز): جرد/تسوية مخزون — الفرق يُرحَّل بقيد.
import 'package:flutter_test/flutter_test.dart';

import 'scenario_world.dart';

void main() {
  late ScenarioWorld w;
  late int product;
  late int wh2;

  setUp(() async {
    w = await ScenarioWorld.create();
    product = await w.addProduct('F1', price: 100, cost: 60, stock: 20);
    wh2 = await w.addWarehouse('مخزن الفرع');
  });
  tearDown(() => w.dispose());

  group('(و) تحويل بين مخزنين', () {
    test('تحويل 8 من 20: مخزن1=12 ومخزن2=8 والإجمالي 20 ثابت', () async {
      final invBefore = await w.accountNet('113');
      await w.db.transferStock(
          fromWarehouseId: w.warehouseId,
          toWarehouseId: wh2,
          items: [
            {'productId': product, 'quantity': 8.0}
          ],
          userId: w.userId,
          notes: 'سيناريو');

      expect(await w.whQty(product, w.warehouseId), closeTo(12, kEps));
      expect(await w.whQty(product, wh2), closeTo(8, kEps));
      expect(await w.stock(product), closeTo(20, kEps),
          reason: 'إجمالي الصنف لا يتغير بالتحويل');
      final bonds = await w.db.getInventoryBondsByType('transfer');
      expect(bonds, hasLength(1));

      // قيدا الخروج والدخول عبر «بضاعة في الطريق» 1134 (480 لكل منهما)، وصافي
      // المخزون 113 في الأستاذ لا يتغير (نفس المنشأة).
      expect(await w.accountNet('113') - invBefore, closeTo(0, kEps));
      expect(await w.accountNet('1134'), closeTo(0, kEps));
      final cnt = await w.db.customSelect(
          "select count(*) n from journal_entries where reference_type like 'inventory_transfer%'").getSingle();
      expect(cnt.data['n'], 2);
      expect(await w.unbalancedEntries(), isEmpty);
    });

    test('تحويل أكبر من الرصيد يُرفض ولا يغيّر الأرصدة', () async {
      await expectLater(
          w.db.transferStock(
              fromWarehouseId: w.warehouseId,
              toWarehouseId: wh2,
              items: [
                {'productId': product, 'quantity': 25.0}
              ],
              userId: w.userId,
              notes: ''),
          throwsA(isA<Exception>()));
      expect(await w.whQty(product, w.warehouseId), closeTo(20, kEps));
      expect(await w.whQty(product, wh2), closeTo(0, kEps));
      expect(await w.stock(product), closeTo(20, kEps));
    });

    test('تحويل ثم تحويل عكسي يعيد الأرصدة الأصلية', () async {
      Future<void> move(int from, int to, double q) => w.db.transferStock(
          fromWarehouseId: from,
          toWarehouseId: to,
          items: [
            {'productId': product, 'quantity': q}
          ],
          userId: w.userId,
          notes: '');
      await move(w.warehouseId, wh2, 20);
      expect(await w.whQty(product, w.warehouseId), closeTo(0, kEps));
      await move(wh2, w.warehouseId, 20);
      expect(await w.whQty(product, w.warehouseId), closeTo(20, kEps));
      expect(await w.whQty(product, wh2), closeTo(0, kEps));
    });
  });

  group('(ز) جرد وتسوية مخزون', () {
    Future<void> countAndApply(double counted) async {
      final plan = await w.db.createCycleCountPlan(
          name: 'جرد سيناريو',
          warehouseId: w.warehouseId,
          frequency: 'monthly',
          productsPerTask: 50,
          createdBy: w.userId);
      final task = await w.db.generateCycleCountTask(
          planId: plan,
          warehouseId: w.warehouseId,
          productsPerTask: 50,
          assignedTo: w.userId);
      expect(task, greaterThan(0));
      await w.db.startCycleCountTask(task);
      final item = (await w.db.getCycleCountItems(task))
          .firstWhere((i) => i.productId == product);
      await w.db.submitCount(itemId: item.id, countedQty: counted);
      // finalize = إكمال + تطبيق الفروق على المخزون + قيد تسوية مجمّع واحد
      await w.db.finalizeCycleCountTask(task);
    }

    test('عجز جرد 3 وحدات (17 من 20): المخزون 17 وقيد خسارة 3 × 60 = 180',
        () async {
      final before = await w.journalTotals();
      final invBefore = await w.accountNet('113');
      await countAndApply(17);

      expect(await w.stock(product), closeTo(17, kEps));
      expect(await w.whQty(product, w.warehouseId), closeTo(17, kEps));
      final after = await w.journalTotals();
      expect(after.debit - before.debit, closeTo(180, kEps),
          reason: 'قيد تسوية بقيمة الفرق بتكلفة الصنف');
      expect(after.credit - before.credit, closeTo(180, kEps));
      expect(await w.accountNet('113') - invBefore, closeTo(-180, kEps));
      expect(await w.unbalancedEntries(), isEmpty);
    });

    test('زيادة جرد وحدتان (22 من 20): المخزون 22 وقيد مكسب 120', () async {
      final before = await w.journalTotals();
      final invBefore = await w.accountNet('113');
      await countAndApply(22);
      expect(await w.stock(product), closeTo(22, kEps));
      final after = await w.journalTotals();
      expect(after.debit - before.debit, closeTo(120, kEps));
      expect(after.credit - before.credit, closeTo(120, kEps));
      expect(await w.accountNet('113') - invBefore, closeTo(120, kEps));
      expect(await w.unbalancedEntries(), isEmpty);
    });

    test('جرد مطابق (20 من 20) لا يولّد قيداً', () async {
      final before = await w.journalTotals();
      await countAndApply(20);
      expect(await w.stock(product), closeTo(20, kEps));
      final after = await w.journalTotals();
      expect(after.debit, closeTo(before.debit, kEps));
    });
  });
}
