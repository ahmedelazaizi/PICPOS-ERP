// ═══════════════════════════════════════════════════════════════════════════
// S-ISSUE (Spec 148) — Stock Requisition fulfilled by warehouse transfer, E2E
//
// US1: approving a pending requisition issues the goods via the existing
//      transfer path (supplier → requester warehouse), marks it fulfilled and
//      links it to the produced bond; failures leave it pending with no effect.
// US2: status reads back canonical (created → pending, legacy → pending).
// US3: delete is atomic + guarded (pending only).
//
// Direction is intentionally crossed: create screen names fromBranchId =
// requester ("الفرع الطالب لي"), toBranchId = supplier ("الفرع المورد منه"),
// so goods flow FROM the supplier (toBranchId) TO the requester (fromBranchId).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/inventory_service.dart';
import 'package:picpos_erp/data/repositories/inventory_repository_impl.dart';
import 'package:picpos_erp/domain/entities/stock_requisition_entity.dart';
import 'package:picpos_erp/domain/entities/stock_requisition_item_entity.dart';
import 'package:picpos_erp/domain/repositories/settings_repository.dart';
import 'package:picpos_erp/core/enums/requisition_status.dart';

/// approveRequisition never touches settingsRepo — a noSuchMethod fake avoids
/// implementing the whole ISettingsRepository surface.
class _FakeSettingsRepo implements ISettingsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('settingsRepo not used by approveRequisition');
}

void main() {
  late AppDatabase db;
  late InventoryService svc;
  late int userId;
  late int requesterBranch; // fromBranchId
  late int supplierBranch; // toBranchId
  late int requesterWh;
  late int supplierWh;

  setUp(() async {
    db = AppDatabase.forTesting();
    svc = InventoryService(db, _FakeSettingsRepo());

    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(name: 'مخزني', isSystemRole: const Value(false)),
        );
    userId = await db.createUser(
      username: 'skuser', password: 'pw', displayName: 'SK', roleId: roleId,
    );

    requesterBranch = await db.into(db.branches).insert(
          BranchesCompanion.insert(name: 'فرع طالب', globalId: const Value('gid-req')),
        );
    supplierBranch = await db.into(db.branches).insert(
          BranchesCompanion.insert(name: 'فرع مورد', globalId: const Value('gid-sup')),
        );
    requesterWh = await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(
            name: 'مستودع الطالب',
            branchId: Value(requesterBranch),
            isDefault: const Value(true),
            globalId: const Value('gid-wh-req'),
          ),
        );
    supplierWh = await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(
            name: 'مستودع المورد',
            branchId: Value(supplierBranch),
            isDefault: const Value(true),
            globalId: const Value('gid-wh-sup'),
          ),
        );
  });

  tearDown(() => db.close());

  // ── helpers ────────────────────────────────────────────────────────────
  Future<int> seedProduct(String code, {double stockInSupplier = 0.0}) async {
    final pid = await db.insertProduct(ProductsCompanion.insert(
      code: code, name: 'صنف $code',
      salePrice: const Value(50.0), costPrice: const Value(30.0),
      trackInventory: const Value(true), allowNegativeSale: const Value(false),
    ));
    if (stockInSupplier > 0) {
      await db.adjustStock(
        productId: pid, warehouseId: supplierWh, quantity: stockInSupplier,
        type: 'initial',
      );
    }
    return pid;
  }

  Future<double> whStock(int pid, int wh) async {
    final b = await (db.select(db.inventoryBalances)
          ..where((x) => x.productId.equals(pid) & x.warehouseId.equals(wh)))
        .getSingleOrNull();
    return b?.quantity ?? 0.0;
  }

  /// Create a pending requisition: requester=fromBranch, supplier=toBranch.
  Future<int> makeRequisition({
    required int productId,
    required double qty,
    int? fromBranch,
    int? toBranch,
    String status = 'pending',
  }) async {
    return db.createStockRequisition(
      requisition: StockRequisitionsCompanion.insert(
        requisitionNumber: 'REQ-$productId-${qty.toInt()}',
        fromBranchId: fromBranch ?? requesterBranch,
        toBranchId: toBranch ?? supplierBranch,
        status: Value(status),
      ),
      items: [
        StockRequisitionItemsCompanion.insert(
          requisitionId: 0, productId: productId, quantity: qty,
        ),
      ],
    );
  }

  Future<void> expectBalanced(String refType, int refId) async {
    final r = await db.customSelect(
      '''SELECT COALESCE(SUM(l.debit),0) AS d, COALESCE(SUM(l.credit),0) AS c
         FROM journal_entry_lines l
         JOIN journal_entries e ON e.id = l.entry_id
         WHERE e.reference_type = ? AND e.reference_id = ?''',
      variables: [Variable(refType), Variable(refId)],
    ).getSingle();
    final d = (r.data['d'] as num).toDouble();
    final c = (r.data['c'] as num).toDouble();
    expect((d - c).abs() < 0.005, isTrue, reason: 'entry must balance: dr=$d cr=$c');
  }

  // ═══ US1 — Approval issues the goods via a transfer ════════════════════
  group('US1 — approve issues transfer', () {
    test('approve moves stock supplier→requester, marks fulfilled + linked', () async {
      final p = await seedProduct('ISS-A', stockInSupplier: 20.0);
      final reqId = await makeRequisition(productId: p, qty: 5.0);

      final bondId = await svc.approveRequisition(requisitionId: reqId, userId: userId);

      // Crossed direction: goods LEFT the supplier warehouse, arrived at requester.
      expect(await whStock(p, supplierWh), 15.0);
      expect(await whStock(p, requesterWh), 5.0);

      // Requisition fulfilled + linked to the produced bond.
      final req = await db.getStockRequisitionById(reqId);
      expect(req!.status, 'fulfilled');
      expect(req.fulfilledByTransferId, bondId);

      // The transfer's two goods-in-transit entries are posted and balanced.
      await expectBalanced('inventory_transfer_out', bondId);
      await expectBalanced('inventory_transfer_in', bondId);
    });

    test('insufficient source stock → throws, stays pending, zero movement', () async {
      final p = await seedProduct('ISS-B', stockInSupplier: 2.0);
      final reqId = await makeRequisition(productId: p, qty: 5.0);

      await expectLater(
        svc.approveRequisition(requisitionId: reqId, userId: userId),
        throwsA(isA<Exception>()),
      );

      expect(await whStock(p, supplierWh), 2.0); // unchanged
      expect(await whStock(p, requesterWh), 0.0);
      final req = await db.getStockRequisitionById(reqId);
      expect(req!.status, 'pending');
      expect(req.fulfilledByTransferId, isNull);
    });

    test('reject → rejected, no movement', () async {
      final p = await seedProduct('ISS-C', stockInSupplier: 20.0);
      final reqId = await makeRequisition(productId: p, qty: 5.0);

      await svc.rejectRequisition(requisitionId: reqId);

      final req = await db.getStockRequisitionById(reqId);
      expect(req!.status, 'rejected');
      expect(await whStock(p, supplierWh), 20.0);
      expect(await whStock(p, requesterWh), 0.0);
    });

    test('double approve → exactly one transfer bond (second throws)', () async {
      final p = await seedProduct('ISS-D', stockInSupplier: 20.0);
      final reqId = await makeRequisition(productId: p, qty: 5.0);

      await svc.approveRequisition(requisitionId: reqId, userId: userId);
      await expectLater(
        svc.approveRequisition(requisitionId: reqId, userId: userId),
        throwsA(isA<Exception>()), // no longer pending
      );

      final bonds = await (db.select(db.inventoryBonds)
            ..where((b) => b.type.equals('transfer')))
          .get();
      expect(bonds.length, 1);
      expect(await whStock(p, supplierWh), 15.0); // not moved twice
    });

    test('supplier branch has no default warehouse → throws, stays pending', () async {
      final p = await seedProduct('ISS-E', stockInSupplier: 20.0);
      final orphanBranch = await db.into(db.branches).insert(
            BranchesCompanion.insert(name: 'فرع بلا مستودع', globalId: const Value('gid-orphan')),
          );
      // Requester = normal branch, supplier = orphan (no default warehouse).
      final reqId = await makeRequisition(
        productId: p, qty: 5.0, fromBranch: requesterBranch, toBranch: orphanBranch,
      );

      await expectLater(
        svc.approveRequisition(requisitionId: reqId, userId: userId),
        throwsA(isA<Exception>()),
      );
      final req = await db.getStockRequisitionById(reqId);
      expect(req!.status, 'pending');
    });
  });

  // ═══ US2 — Status reads back canonical ═════════════════════════════════
  group('US2 — canonical status mapping', () {
    test('created via repository reads back pending (not draft/unknown)', () async {
      final repo = InventoryRepositoryImpl(db);
      final p = await seedProduct('ISS-S1');
      final id = await repo.createStockRequisition(
        StockRequisitionEntity(
          id: 0,
          requisitionNumber: 'REQ-S1',
          requisitionDate: DateTime(2026, 7, 7),
          fromBranchId: requesterBranch,
          toBranchId: supplierBranch,
          status: RequisitionStatus.pending,
          createdByUserId: userId,
          createdAt: DateTime(2026, 7, 7),
        ),
        [
          const StockRequisitionItemEntity(
            id: 0, requisitionId: 0, productId: 0, quantity: 1.0,
          ).copyWith(productId: p),
        ],
      );
      final read = await repo.getStockRequisitionById(id);
      expect(read!.status, RequisitionStatus.pending);
      // A global identity was stamped for future sync dedup.
      final raw = await db.getStockRequisitionById(id);
      expect(raw!.globalId != null && raw.globalId!.isNotEmpty, isTrue);
    });

    test('legacy "draft" DB string degrades to pending', () async {
      final repo = InventoryRepositoryImpl(db);
      final p = await seedProduct('ISS-S2');
      final id = await makeRequisition(productId: p, qty: 1.0, status: 'draft');
      final read = await repo.getStockRequisitionById(id);
      expect(read!.status, RequisitionStatus.pending);
    });
  });

  // ═══ US3 — Delete is atomic + guarded ══════════════════════════════════
  group('US3 — atomic guarded delete', () {
    test('delete pending removes header + all items (no orphans)', () async {
      final p1 = await seedProduct('ISS-D1');
      final reqId = await db.createStockRequisition(
        requisition: StockRequisitionsCompanion.insert(
          requisitionNumber: 'REQ-DEL',
          fromBranchId: requesterBranch,
          toBranchId: supplierBranch,
          status: const Value('pending'),
        ),
        items: [
          StockRequisitionItemsCompanion.insert(requisitionId: 0, productId: p1, quantity: 1.0),
          StockRequisitionItemsCompanion.insert(requisitionId: 0, productId: p1, quantity: 2.0),
          StockRequisitionItemsCompanion.insert(requisitionId: 0, productId: p1, quantity: 3.0),
        ],
      );

      await db.deleteStockRequisition(reqId);

      expect(await db.getStockRequisitionById(reqId), isNull);
      expect(await db.getStockRequisitionItems(reqId), isEmpty);
    });

    test('delete non-pending is refused, nothing removed', () async {
      final p = await seedProduct('ISS-D2', stockInSupplier: 20.0);
      final reqId = await makeRequisition(productId: p, qty: 5.0);
      await svc.approveRequisition(requisitionId: reqId, userId: userId); // → fulfilled

      await expectLater(
        db.deleteStockRequisition(reqId),
        throwsA(isA<Exception>()),
      );
      expect(await db.getStockRequisitionById(reqId), isNotNull);
      expect(await db.getStockRequisitionItems(reqId), isNotEmpty);
    });
  });
}
