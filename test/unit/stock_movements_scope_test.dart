// ═══════════════════════════════════════════════════════════════════════════
// حركة المخزون — كل الحركات بتكلفتها وأرصدتها، بلا حصر وبلا سقف.
// ═══════════════════════════════════════════════════════════════════════════
//
// `InventoryRepositoryImpl.getMovementsByDateRange` كان **بلا حصر مخازن وبلا
// limit** — بينما توأمه في inventory_dao.dart:70 عنده limit=500، و
// watchAllStockMovements تحته مباشرةً في نفس الملف عنده limit=100. والمسار ده
// هو اللي شاشة حركة المخزون بتستعمله فعلاً.
//
// والصفوف بتحمل `unit_cost` و`balance_after` — تكلفة الشراء ورصيد المخزن —
// وده بيان مالي لا يقل حساسية عن أرصدة العملاء.
//
// الاختبار ده هو الشرط الموثَّق في خط أساس
// report_screens_resolve_branch_scope_test لإزالة الشاشة منه: إثبات سلوكي إن
// `[]` بتفشل مقفولة.
//
// العقد (نفس عُرف sales_analytics_dao.dart:182 و inventory_dao.dart:1219):
//   null = بلا حصر · [ids] = المخازن دي · [] = لا شيء
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/repositories/inventory_repository_impl.dart';

void main() {
  late AppDatabase db;
  late InventoryRepositoryImpl repo;
  late int warehouseA;
  late int warehouseB;
  late int productId;

  final from = DateTime(2026, 8, 1);
  final to = DateTime(2026, 8, 31);

  Future<void> movement({
    required int warehouseId,
    required double qty,
    required double unitCost,
    DateTime? at,
  }) =>
      db.into(db.stockMovements).insert(StockMovementsCompanion.insert(
            productId: productId,
            warehouseId: warehouseId,
            movementType: 'in',
            quantity: qty,
            balanceAfter: qty,
            unitCost: Value(unitCost),
            createdAt: Value(at ?? DateTime(2026, 8, 10)),
          ));

  setUp(() async {
    db = AppDatabase.forTesting();
    repo = InventoryRepositoryImpl(db);
    warehouseA = await db
        .into(db.warehouses)
        .insert(WarehousesCompanion.insert(name: 'مخزن أ'));
    warehouseB = await db
        .into(db.warehouses)
        .insert(WarehousesCompanion.insert(name: 'مخزن ب'));
    productId = await db
        .into(db.products)
        .insert(ProductsCompanion.insert(name: 'صنف', code: 'SM-1'));

    await movement(warehouseId: warehouseA, qty: 5, unitCost: 10);
    await movement(warehouseId: warehouseB, qty: 7, unitCost: 99);
  });

  tearDown(() => db.close());

  test('null = بلا حصر (سلوك غير متغيّر)', () async {
    final rows = await repo.getMovementsByDateRange(from, to);
    expect(rows.length, 2);
  });

  test('[A] بيرجّع مخزن أ وحده — التكلفة والرصيد ما بيتسربوش', () async {
    final rows =
        await repo.getMovementsByDateRange(from, to, warehouseIds: [warehouseA]);
    expect(rows.map((m) => m.warehouseId), [warehouseA]);
    expect(rows.single.unitCost, 10);
    expect(rows.any((m) => m.unitCost == 99), isFalse,
        reason: 'تكلفة شراء مخزن تاني بيان مالي');
  });

  test('[] بتفشل مقفولة — مش «كل المخازن»', () async {
    // ده الشرط اللي بيسمح بإزالة الشاشة من خط أساس الحارس البنيوي.
    final rows =
        await repo.getMovementsByDateRange(from, to, warehouseIds: const []);
    expect(rows, isEmpty);
  });

  test('[B] ضابط — بيرجّع مخزن ب فعلاً مش قايمة فاضية', () async {
    final rows =
        await repo.getMovementsByDateRange(from, to, warehouseIds: [warehouseB]);
    expect(rows.map((m) => m.warehouseId), [warehouseB]);
  });

  test('السقف بيتطبّق — الاستعلام مكانش عنده أي حد', () async {
    for (var i = 0; i < 8; i++) {
      await movement(warehouseId: warehouseA, qty: 1, unitCost: 1);
    }
    final rows = await repo.getMovementsByDateRange(from, to, limit: 3);
    expect(rows.length, 3);
  });
}
