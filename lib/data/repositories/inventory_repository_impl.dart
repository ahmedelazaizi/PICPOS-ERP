import 'package:drift/drift.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/database/sync_interceptor.dart';
import '../../domain/repositories/inventory_repository.dart';
import '../../domain/entities/stock_requisition_entity.dart';
import '../../domain/entities/stock_requisition_item_entity.dart';
import '../../core/enums/requisition_status.dart';
import '../../core/utils/uuid_v7.dart';

class InventoryRepositoryImpl implements InventoryRepository {
  final AppDatabase _db;

  InventoryRepositoryImpl(this._db);

  @override
  Future<void> adjustStock({
    required int productId,
    required int warehouseId,
    required double quantity,
    String? type,
    String? notes,
    String? adjustmentEventGid,
  }) async {
    await _db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: quantity,
      type: type,
      notes: notes,
      adjustmentEventGid: adjustmentEventGid,
    );
  }

  @override
  Future<double> getProductStock(int productId, {int? warehouseId}) async {
    // Get current stock from the product record directly
    final product = await (_db.select(
      _db.products,
    )..where((t) => t.id.equals(productId))).getSingleOrNull();
    return product?.currentStock ?? 0.0;
  }

  @override
  Future<bool> hasOpeningStockMovement({
    required int productId,
    required int warehouseId,
  }) =>
      _db.hasOpeningStockMovement(
        productId: productId,
        warehouseId: warehouseId,
      );

  @override
  Stream<List<StockMovementData>> watchProductMovements(int productId) {
    final query = _db.select(_db.stockMovements).join([
      leftOuterJoin(_db.products, _db.products.id.equalsExp(_db.stockMovements.productId)),
      leftOuterJoin(_db.warehouses, _db.warehouses.id.equalsExp(_db.stockMovements.warehouseId)),
    ])
      ..where(_db.stockMovements.productId.equals(productId))
      ..orderBy([OrderingTerm.desc(_db.stockMovements.createdAt)]);

    return query.watch().map((rows) => rows.map((row) {
          final m = row.readTable(_db.stockMovements);
          final p = row.readTableOrNull(_db.products);
          final w = row.readTableOrNull(_db.warehouses);
          return StockMovementData(
            id: m.id,
            productId: m.productId,
            warehouseId: m.warehouseId,
            movementType: m.movementType,
            quantity: m.quantity,
            balanceAfter: m.balanceAfter,
            unitCost: m.unitCost,
            productName: p?.name,
            warehouseName: w?.name,
            referenceType: m.referenceType,
            referenceId: m.referenceId,
            notes: m.notes,
            createdAt: m.createdAt,
          );
        }).toList());
  }

  @override
  Future<List<StockMovementData>> getMovementsByDateRange(
    DateTime from,
    DateTime to, {
    List<int>? warehouseIds,
    int limit = 500,
  }) async {
    final query = _db.select(_db.stockMovements).join([
      leftOuterJoin(_db.products, _db.products.id.equalsExp(_db.stockMovements.productId)),
      leftOuterJoin(_db.warehouses, _db.warehouses.id.equalsExp(_db.stockMovements.warehouseId)),
    ])
      ..where(_db.stockMovements.createdAt.isBetweenValues(from, to))
      ..orderBy([OrderingTerm.desc(_db.stockMovements.createdAt)])
      // كان بلا حدّ خالص، بينما التوأم في الـDAO عنده limit=500 و
      // watchAllStockMovements تحته مباشرةً عنده 100. المسار ده هو اللي شاشة
      // حركة المخزون بتستعمله، فكان بيحمّل كل الحركات في الذاكرة.
      ..limit(limit);

    // حصر المخازن: null = بلا حدّ (وصول كامل)، [] = لا شيء. نفس عُرف
    // sales_analytics_dao.dart:182 و inventory_dao.dart:1219 — والـ isIn([])
    // في drift بيدي Constant(false) فالقايمة الفاضية بتفشل مقفولة لوحدها.
    //
    // من غير ده كانت الشاشة بتعرض unit_cost و balance_after لكل حركة في كل
    // مخازن الشركة لمستخدم محصور بفرع — التكلفة والرصيد بيان مالي.
    if (warehouseIds != null) {
      query.where(_db.stockMovements.warehouseId.isIn(warehouseIds));
    }

    final rows = await query.get();
    return rows.map((row) {
      final m = row.readTable(_db.stockMovements);
      final p = row.readTableOrNull(_db.products);
      final w = row.readTableOrNull(_db.warehouses);
      return StockMovementData(
        id: m.id,
        productId: m.productId,
        warehouseId: m.warehouseId,
        movementType: m.movementType,
        quantity: m.quantity,
        balanceAfter: m.balanceAfter,
        unitCost: m.unitCost,
        productName: p?.name,
        warehouseName: w?.name,
        referenceType: m.referenceType,
        referenceId: m.referenceId,
        notes: m.notes,
        createdAt: m.createdAt,
      );
    }).toList();
  }

  @override
  Stream<List<StockMovementData>> watchAllStockMovements({int limit = 100}) {
    final query = _db.select(_db.stockMovements).join([
      leftOuterJoin(_db.products, _db.products.id.equalsExp(_db.stockMovements.productId)),
      leftOuterJoin(_db.warehouses, _db.warehouses.id.equalsExp(_db.stockMovements.warehouseId)),
    ])
      ..orderBy([OrderingTerm.desc(_db.stockMovements.createdAt)])
      ..limit(limit);

    return query.watch().map((rows) => rows.map((row) {
          final m = row.readTable(_db.stockMovements);
          final p = row.readTableOrNull(_db.products);
          final w = row.readTableOrNull(_db.warehouses);
          return StockMovementData(
            id: m.id,
            productId: m.productId,
            warehouseId: m.warehouseId,
            movementType: m.movementType,
            quantity: m.quantity,
            balanceAfter: m.balanceAfter,
            unitCost: m.unitCost,
            productName: p?.name,
            warehouseName: w?.name,
            referenceType: m.referenceType,
            referenceId: m.referenceId,
            notes: m.notes,
            createdAt: m.createdAt,
          );
        }).toList());
  }

  @override
  Stream<List<WarehouseData>> watchWarehouses() {
    return _db.watchAllWarehouses().map(
      (list) => list
          .map(
            (w) => WarehouseData(
              id: w.id,
              name: w.name,
              location: null,
              isDefault: w.isDefault,
              costCenterId: w.costCenterId,
              branchId: w.branchId,
            ),
          )
          .toList(),
    );
  }

  @override
  Future<WarehouseData?> getWarehouseById(int id) async {
    final w = await _db.getWarehouseById(id);
    if (w == null) return null;
    return WarehouseData(
      id: w.id,
      name: w.name,
      location: null,
      isDefault: w.isDefault,
      costCenterId: w.costCenterId,
      branchId: w.branchId,
    );
  }

  @override
  Future<WarehouseData?> getDefaultWarehouse() async {
    final w = await _db.getDefaultWarehouse();
    if (w == null) return null;
    return WarehouseData(
      id: w.id,
      name: w.name,
      location: null,
      isDefault: w.isDefault,
      costCenterId: w.costCenterId,
      branchId: w.branchId,
    );
  }

  @override
  Future<void> transferStock({
    required int productId,
    required int fromWarehouseId,
    required int toWarehouseId,
    required double quantity,
    String? notes,
  }) async {
    await _db.transferStock(
      fromWarehouseId: fromWarehouseId,
      toWarehouseId: toWarehouseId,
      items: [
        {'productId': productId, 'quantity': quantity},
      ],
      notes: notes,
    );
  }

  @override
  Future<List<ProductBatchData>> getProductBatches(int productId) async {
    final list = await _db.getProductBatches(productId);
    return list
        .map(
          (b) => ProductBatchData(
            id: b.id,
            productId: b.productId,
            batchNumber: b.batchNumber,
            expiryDate: b.expiryDate,
            quantity: b.quantity,
            costPrice: b.unitCost,
            createdAt: b.createdAt,
          ),
        )
        .toList();
  }

  @override
  Future<List<ProductBatchData>> getExpiredBatches() async {
    final list = await _db.getExpiredBatches();
    return list
        .map(
          (b) => ProductBatchData(
            id: b.id,
            productId: b.productId,
            batchNumber: b.batchNumber,
            expiryDate: b.expiryDate,
            quantity: b.quantity,
            costPrice: b.unitCost,
            createdAt: b.createdAt,
          ),
        )
        .toList();
  }

  @override
  Future<List<ProductBatchData>> getExpiringBatches(int days) async {
    final list = await _db.getExpiringBatches(days);
    return list
        .map(
          (b) => ProductBatchData(
            id: b.id,
            productId: b.productId,
            batchNumber: b.batchNumber,
            expiryDate: b.expiryDate,
            quantity: b.quantity,
            costPrice: b.unitCost,
            createdAt: b.createdAt,
          ),
        )
        .toList();
  }

  @override
  Future<List<LowStockProductData>> getLowStockProducts() async {
    final list = await _db.getLowStockProducts();
    return list
        .map(
          (p) => LowStockProductData(
            productId: p.id,
            productName: p.name,
            currentStock: p.currentStock,
            minimumStock: p.minStock,
            shortage: p.minStock - p.currentStock,
          ),
        )
        .toList();
  }

  @override
  Future<InventoryValuation> getInventoryValuation({int? warehouseId}) async {
    // Calculate inventory valuation from products
    final products = await (_db.select(_db.products)).get();
    double totalCost = 0;
    double totalSale = 0;
    int count = 0;
    for (final p in products) {
      final stock = p.currentStock;
      if (stock > 0) {
        totalCost += stock * p.costPrice;
        totalSale += stock * p.salePrice;
        count++;
      }
    }
    return InventoryValuation(
      totalCostValue: totalCost,
      totalSaleValue: totalSale,
      potentialProfit: totalSale - totalCost,
      itemCount: count,
    );
  }

  @override
  Stream<List<HeldOrder>> watchHeldOrders() {
    return _db.watchHeldOrders();
  }

  @override
  Stream<List<StockAudit>> watchOpenAudit() {
    return _db.watchOpenAudit().map((event) => event != null ? [event] : []);
  }

  @override
  Future<bool> hasActiveStockAudit() async {
    final openAudit = await (_db.select(_db.stockAudits)
      ..where((t) => t.status.equals('open'))
      ..limit(1))
      .getSingleOrNull();
    return openAudit != null;
  }

  @override
  Future<List<StockAuditItem>> getAuditItems(int auditId) {
    return _db.getAuditItems(auditId);
  }

  @override
  Future<int> createStockAudit({int? userId}) {
    return _db.createStockAudit(userId: userId);
  }

  @override
  Future<void> saveAuditItem({
    required int auditId,
    required int productId,
    required double expectedQuantity,
    required double actualQuantity,
  }) {
    return _db.saveAuditItem(
      auditId: auditId,
      productId: productId,
      expectedQuantity: expectedQuantity,
      actualQuantity: actualQuantity,
    );
  }

  @override
  Future<bool> addAuditItemOnce({
    required int auditId,
    required int productId,
    required double expectedQuantity,
  }) {
    return _db.addAuditItemOnce(
      auditId: auditId,
      productId: productId,
      expectedQuantity: expectedQuantity,
    );
  }

  @override
  Future<void> finalizeAudit(int auditId) {
    // Pre-deploy BLOCKER (option B): the stock-count subsystem is not yet
    // sync-aware — finalizeAudit writes inventory movements + the settlement JE
    // straight to the local DB. On a client/mirror device those never reach HQ
    // and are reverted on the next serverWins pull (R4). Until a sync-aware
    // finalize exists, refuse on client/mirror; counts are finalized on the server.
    if (SyncInterceptor.isClientMode) {
      throw StateError(
          'لا يمكن اعتماد الجرد من جهاز عميل أو مرآة. نفّذ الجرد واعتماده على الخادم الرئيسي.');
    }
    return _db.finalizeAudit(auditId);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STOCK REQUISITIONS
  // ═══════════════════════════════════════════════════════════════════════════

  // Spec 148 — delegate to the single canonical parser (legacy/unknown →
  // pending). Keeps the two call sites stable.
  RequisitionStatus _parseStatus(String s) => parseStatus(s);

  @override
  Stream<List<StockRequisitionEntity>> watchAllStockRequisitions({DateTime? startDate, DateTime? endDate}) {
    var query = _db.select(_db.stockRequisitions)
      ..orderBy([(r) => OrderingTerm.desc(r.createdAt)]);
    if (startDate != null) query.where((r) => r.requisitionDate.isBiggerOrEqualValue(startDate));
    if (endDate != null) query.where((r) => r.requisitionDate.isSmallerOrEqualValue(endDate));

    return query.watch().map((list) => list.map((req) => StockRequisitionEntity(
      id: req.id,
      requisitionNumber: req.requisitionNumber,
      requisitionDate: req.requisitionDate,
      fromBranchId: req.fromBranchId,
      toBranchId: req.toBranchId,
      status: _parseStatus(req.status),
      notes: req.notes,
      createdByUserId: req.createdBy ?? 0,
      createdAt: req.createdAt,
    )).toList());
  }

  @override
  Future<StockRequisitionEntity?> getStockRequisitionById(int id) async {
    final req = await (_db.select(_db.stockRequisitions)..where((r) => r.id.equals(id))).getSingleOrNull();
    if (req == null) return null;
    
    return StockRequisitionEntity(
      id: req.id,
      requisitionNumber: req.requisitionNumber,
      requisitionDate: req.requisitionDate,
      fromBranchId: req.fromBranchId,
      toBranchId: req.toBranchId,
      status: _parseStatus(req.status),
      notes: req.notes,
      createdByUserId: req.createdBy ?? 0,
      createdAt: req.createdAt,
    );
  }

  @override
  Future<List<StockRequisitionItemEntity>> getStockRequisitionItems(int requisitionId) async {
    final list = await (_db.select(_db.stockRequisitionItems)
          ..where((i) => i.requisitionId.equals(requisitionId)))
        .get();
    return list.map((item) => StockRequisitionItemEntity(
      id: item.id,
      requisitionId: item.requisitionId,
      productId: item.productId,
      quantity: item.quantity,
      notes: item.notes,
    )).toList();
  }

  @override
  Future<int> createStockRequisition(StockRequisitionEntity requisition, List<StockRequisitionItemEntity> items) async {
    return _db.transaction(() async {
      final reqId = await _db.into(_db.stockRequisitions).insert(
        StockRequisitionsCompanion.insert(
          requisitionNumber: requisition.requisitionNumber,
          fromBranchId: requisition.fromBranchId,
          toBranchId: requisition.toBranchId,
          // Spec 148 — write the canonical status explicitly (entity ↔ DB
          // agree) and stamp a global identity for future cross-node dedup.
          status: Value(statusToDb(requisition.status)),
          globalId: Value(UuidV7.generate()),
          createdBy: Value(requisition.createdByUserId),
          notes: Value(requisition.notes ?? ''),
        ),
      );
      for (final item in items) {
        await _db.into(_db.stockRequisitionItems).insert(
          StockRequisitionItemsCompanion.insert(
            requisitionId: reqId,
            productId: item.productId,
            quantity: item.quantity,
            notes: Value(item.notes ?? ''),
          ),
        );
      }
      return reqId;
    });
  }

  @override
  Future<void> updateStockRequisitionStatus(int id, String status) async {
    await (_db.update(_db.stockRequisitions)..where((r) => r.id.equals(id))).write(
      StockRequisitionsCompanion(status: Value(status)),
    );
  }

  @override
  // Spec 148 (R3) — delegate to the DAO's atomic, draft/pending-guarded delete
  // (children + header in one transaction) instead of two unguarded raw deletes.
  Future<void> deleteStockRequisition(int id) => _db.deleteStockRequisition(id);

  @override
  Future<List<StockMovementData>> getStockMovementsByReference(String referenceType, int referenceId) async {
    final query = _db.select(_db.stockMovements).join([
      leftOuterJoin(_db.products, _db.products.id.equalsExp(_db.stockMovements.productId)),
      leftOuterJoin(_db.warehouses, _db.warehouses.id.equalsExp(_db.stockMovements.warehouseId)),
    ])
      ..where(_db.stockMovements.referenceType.equals(referenceType) & _db.stockMovements.referenceId.equals(referenceId))
      ..orderBy([OrderingTerm.desc(_db.stockMovements.createdAt)]);

    final rows = await query.get();
    return rows.map((row) {
      final m = row.readTable(_db.stockMovements);
      final p = row.readTableOrNull(_db.products);
      final w = row.readTableOrNull(_db.warehouses);
      return StockMovementData(
        id: m.id,
        productId: m.productId,
        warehouseId: m.warehouseId,
        movementType: m.movementType,
        quantity: m.quantity,
        balanceAfter: m.balanceAfter,
        unitCost: m.unitCost,
        productName: p?.name,
        warehouseName: w?.name,
        referenceType: m.referenceType,
        referenceId: m.referenceId,
        notes: m.notes,
        createdAt: m.createdAt,
      );
    }).toList();
  }

  @override
  Future<void> deleteStockMovement(int id) async {
    await (_db.delete(_db.stockMovements)..where((t) => t.id.equals(id))).go();
  }

  @override
  Future<double> getProductWarehouseCost(int productId, int warehouseId) async {
    final balance = await _db.customSelect(
      'SELECT average_cost FROM inventory_balances '
      'WHERE product_id = ? AND warehouse_id = ? LIMIT 1',
      variables: [Variable(productId), Variable(warehouseId)],
      readsFrom: {_db.inventoryBalances},
    ).getSingleOrNull();
    if (balance != null) {
      final avgCost = (balance.data['average_cost'] as num?)?.toDouble() ?? 0;
      if (avgCost > 0) return avgCost;
    }
    // Fallback to product cost price
    final product = await _db.getProductById(productId);
    return product?.costPrice ?? 0;
  }
}
