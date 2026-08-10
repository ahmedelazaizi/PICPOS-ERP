// ═══════════════════════════════════════════════════════════════════════════
// سندُ الإضافة يُسجَّل بتكلفة الصنف القديمة لا بتكلفة السند
// ═══════════════════════════════════════════════════════════════════════════
//
// `InventoryService.createAddingBond` يقرأ `item.unitCost` ويجمع به قيمةَ
// السند، ثم ينادي `adjustStock` **بلا** `unitCost` — و`adjustStock` يرجع
// حينها إلى `product.costPrice`.
//
// فالسندُ يقول قيمةً، وحركةُ المخزون ورصيدُ المخزن يقولان قيمةً أخرى:
// * `stock_movements.unit_cost` يُكتب بالتكلفة القديمة.
// * `inventory_balances.average_cost` يُمزَج بالتكلفة القديمة، فتقييمُ
//   المخزون في التقارير يخالف قيمةَ السند وقيدَه.
//
// مقيس: صنفٌ تكلفتُه صفرٌ يدخل بسندٍ ١٠ وحداتٍ × ١٠ = ١٠٠ ⇒ الحركةُ والرصيد
// يقولان صفراً. انحرافُ ١٠٠ في سندٍ واحد.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/domain/repositories/settings_repository.dart';
import 'package:ural_erp/services/inventory_service.dart';

/// إعداداتٌ صامتة — طريقةُ التكلفة تقع على الافتراضي.
class _StubSettingsRepo implements ISettingsRepository {
  @override
  Future<String?> getSetting(String key) async => null;
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  late AppDatabase db;
  late InventoryService service;
  late int warehouseId;
  late int productId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    service = InventoryService(db, _StubSettingsRepo());
    warehouseId = (await db.getDefaultWarehouse())!.id;
    productId = await db.insertProduct(ProductsCompanion.insert(
      code: 'BND-1',
      name: 'صنفُ السند',
      salePrice: const Value(20),
      costPrice: const Value(0), // لسه ما اتسعّرش — الحالةُ الشائعة عند التأسيس
      trackInventory: const Value(true),
    ));
  });

  tearDown(() async => db.close());

  Future<int> addBond({required double qty, required double unitCost}) =>
      service.createAddingBond(
        warehouseId: warehouseId,
        items: [
          InventoryBondItemsCompanion.insert(
            bondId: 0,
            productId: productId,
            quantity: qty,
            unitCost: Value(unitCost),
          ),
        ],
        notes: 'سندُ اختبار',
      );

  test('حركةُ المخزون تُسجَّل بتكلفة السند لا بتكلفة الصنف القديمة', () async {
    await addBond(qty: 10, unitCost: 10);

    final move = await (db.select(db.stockMovements)
          ..where((m) => m.productId.equals(productId)))
        .getSingle();

    expect(move.unitCost, closeTo(10, 0.001),
        reason: 'اتقاس صفر — `adjustStock` رجع لـ product.costPrice لأن السند '
            'ما مرّرش unitCost. قيمةُ الحركة صفرٌ بينما السند يقول ١٠٠.');
  });

  test('ورصيدُ المخزن يتقيَّم بتكلفة السند كذلك', () async {
    await addBond(qty: 10, unitCost: 10);

    final bal = await (db.select(db.inventoryBalances)
          ..where((b) =>
              b.productId.equals(productId) &
              b.warehouseId.equals(warehouseId)))
        .getSingle();

    expect(bal.quantity, closeTo(10, 0.001), reason: 'ضابط: الكمية دخلت');
    expect(bal.averageCost, closeTo(10, 0.001),
        reason: 'اتقاس صفر — تقييمُ المخزون في التقارير هيقول صفر لبضاعةٍ '
            'قيمتُها ١٠٠، وقيدُ السند وحدَه هو اللي شايل القيمة.');
  });

  test('سندٌ ثانٍ بتكلفةٍ مختلفة يمزج متوسّطاً معقولاً', () async {
    await addBond(qty: 10, unitCost: 10);
    await addBond(qty: 10, unitCost: 20);

    final bal = await (db.select(db.inventoryBalances)
          ..where((b) =>
              b.productId.equals(productId) &
              b.warehouseId.equals(warehouseId)))
        .getSingle();

    expect(bal.quantity, closeTo(20, 0.001));
    expect(bal.averageCost, closeTo(15, 0.001),
        reason: '(١٠×١٠ + ١٠×٢٠) ÷ ٢٠ = ١٥');
  });
}
