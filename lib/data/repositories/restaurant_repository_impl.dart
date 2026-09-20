import 'package:drift/drift.dart';
import '../database/database.dart';
import '../../domain/models/floor_plan_layout.dart';
import '../../domain/models/tables_report_row.dart';
import '../../domain/repositories/restaurant_repository.dart';
import '../../core/utils/uuid_v7.dart';
import '../database/sync_interceptor.dart';
import '../../services/client_write_interceptor.dart';

class RestaurantRepositoryImpl implements IRestaurantRepository {
  final AppDatabase _db;

  RestaurantRepositoryImpl(this._db);

  @override
  Stream<List<TableSection>> watchAllSections() => _db.watchAllSections();

  @override
  Future<List<TableSection>> getAllSections() => _db.getAllSections();

  @override
  Future<int> createSection(String name) => _db.createSection(name);

  @override
  Future<bool> updateSection(int id, String name) async {
    await _db.updateSection(id, name);
    return true;
  }

  @override
  Future<void> deleteSection(int id) => _db.deleteSection(id);

  @override
  Stream<List<RestaurantTable>> watchTablesInSection(int sectionId) =>
      _db.watchTablesBySection(sectionId);

  @override
  Future<List<RestaurantTable>> getAllTables() =>
      (_db.select(_db.restaurantTables)
            ..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .get();

  @override
  Future<int> createTable({
    required String name,
    required int capacity,
    required int sectionId,
  }) => _db.createTable(
    name: name,
    sectionId: sectionId,
    capacity: capacity,
  );

  @override
  Future<bool> updateTable({
    required int id,
    required String name,
    required int capacity,
    required int sectionId,
  }) async {
    await _db.updateTableInfo(
      id,
      name: name,
      sectionId: sectionId,
      capacity: capacity,
    );
    return true;
  }

  @override
  Future<void> deleteTable(int id) => _db.deleteTable(id);

  @override
  Future<void> updateTableStatus(int id, String status) =>
      _db.updateTableStatus(id, status);

  @override
  Future<void> updateTablePosition(int id, double x, double y) =>
      (_db.update(_db.restaurantTables)..where((t) => t.id.equals(id))).write(
        RestaurantTablesCompanion(x: Value(x), y: Value(y)),
      );

  // ═══ مصمّمُ القاعة (قسمُ ٧) ════════════════════════════

  @override
  Future<FloorPlanSectionLayout?> getFloorPlanLayout(int sectionId) =>
      _db.getFloorPlanSectionLayout(sectionId);

  @override
  Future<List<FloorPlanSectionBox>> getFloorPlanSectionBoxes() =>
      _db.getFloorPlanSectionBoxes();

  /// حفظُ المخطَّط — محلّيّاً دائماً، وإلى الخادم في وضع العميل.
  ///
  /// 🔴 **والتوسيمُ يسبقُ الكتابتَين معاً.** لو وُلّدَ المعرِّفُ
  ///    العالميُّ داخلَ كلّ كتابةٍ على حدة لحمل صفُّ العميل وصفُّ
  ///    الخادم هويّتَين مختلفتَين لمعلَمٍ واحد — فيعود الجدارُ
  ///    **مضاعَفاً** عند أوّل سحبِ دلتا.
  @override
  Future<void> saveFloorPlanLayout(FloorPlanSectionLayout layout) async {
    final stamped = stampMissingGlobalIds(layout, UuidV7.generate);

    if (SyncInterceptor.isClientMode) {
      // والفحصُ **قبل** أيّ كتابة: إرسالٌ يُهمَل بعد حفظٍ محلّيٍّ
      // يترك الجهازَ وحدَه يرى مخطَّطاً لا يراه غيرُه.
      final bad = validateFloorPlanWireIdentity(stamped);
      if (bad != null) throw StateError(bad);
      await ClientWriteInterceptor.dispatchWrite(
        () => ClientWriteInterceptor.submitFloorPlan(
          floorPlanLayoutToJson(stamped),
        ),
        tag: 'FLOOR-PLAN-SYNC',
      );
    }

    await _db.saveFloorPlanLayout(stamped);
  }

  @override
  Future<TableReservation?> getActiveReservationForTable(int tableId) =>
      _db.getActiveReservationForTable(tableId);

  @override
  Future<void> createReservation({
    required int tableId,
    required String customerName,
    String? customerPhone,
    required DateTime reservationTime,
    required int partySize,
    String? notes,
  }) => _db.createReservation(
    tableId: tableId,
    customerName: customerName,
    customerPhone: customerPhone,
    reservationTime: reservationTime,
    partySize: partySize,
    notes: notes,
  );

  @override
  Future<void> cancelReservation(int id) => _db.cancelReservation(id);

  @override
  Future<void> seatReservation(int id, {int? userId, double taxRate = 0}) =>
      _db.seatReservation(id, userId: userId, taxRate: taxRate);

  @override
  Future<void> transferTableOrder(int sourceTableId, int targetTableId) =>
      _db.transferTableOrder(sourceTableId, targetTableId);

  @override
  Future<void> partialTransferTableOrder({
    required int sourceTableId,
    required int targetTableId,
    required Map<int, double> itemQuantities,
  }) => _db.partialTransferTableOrder(
    sourceTableId: sourceTableId,
    targetTableId: targetTableId,
    itemQuantities: itemQuantities,
  );

  @override
  Future<TableOrder?> getActiveOrderForTable(int tableId) =>
      _db.getActiveOrderForTable(tableId);

  @override
  Future<List<TableOrderItem>> getTableOrderItems(int orderId) =>
      _db.getTableOrderItems(orderId);

  @override
  Future<int> createTableOrder(int tableId,
          {int? userId, double taxRate = 0}) =>
      _db.createTableOrder(tableId, userId: userId, taxRate: taxRate);

  @override
  Future<void> mergeTableOrders(int sourceTableId, int targetTableId) =>
      _db.mergeTableOrders(sourceTableId, targetTableId);

  @override
  Future<void> addOrUpdateTableOrderItem({
    required int orderId,
    required int productId,
    required double quantity,
    required double unitPrice,
    double taxRate = 0,
  }) =>
      _db.addOrUpdateTableOrderItem(
        orderId: orderId,
        productId: productId,
        quantity: quantity,
        unitPrice: unitPrice,
        taxRate: taxRate,
      );

  @override
  Future<void> clearTableOrderItems(int orderId) =>
      _db.clearTableOrderItems(orderId);

  @override
  Future<List<TableOrderInput>> getTableOrdersForReport({
    required DateTime from,
    required DateTime to,
    int? sectionId,
    int? tableId,
    int? userId,
    Set<int>? branchIds,
    Set<int>? allowedBranchIds,
  }) =>
      _db.getTableOrdersForReport(
        from: from,
        to: to,
        sectionId: sectionId,
        tableId: tableId,
        userId: userId,
        branchIds: branchIds,
        allowedBranchIds: allowedBranchIds,
      );
}
