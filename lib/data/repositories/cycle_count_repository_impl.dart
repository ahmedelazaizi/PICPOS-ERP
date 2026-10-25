import '../database/database.dart' as db;
import '../database/sync_interceptor.dart';
import '../../services/api/m1_wh/wh_count_service.dart';
import '../../services/api/m1_wh/wh_doc_store.dart';
import '../../services/api/m1_wh/wh_http.dart' show WhError;
import '../../domain/repositories/cycle_count_repository.dart';

class CycleCountRepositoryImpl implements ICycleCountRepository {
  final db.AppDatabase _db;

  CycleCountRepositoryImpl(this._db);

  @override
  Future<int> createCycleCountPlan({
    required String name,
    required int warehouseId,
    required String frequency,
    String abcClassification = 'all',
    int productsPerTask = 20,
    int? createdBy,
  }) {
    return _db.createCycleCountPlan(
      name: name,
      warehouseId: warehouseId,
      frequency: frequency,
      abcClassification: abcClassification,
      productsPerTask: productsPerTask,
      createdBy: createdBy,
    );
  }

  @override
  Future<List<db.CycleCountPlanData>> getActiveCycleCountPlans() {
    return _db.getActiveCycleCountPlans();
  }

  @override
  Future<List<db.CycleCountPlanData>> getCycleCountPlans({int? warehouseId}) {
    return _db.getCycleCountPlans(warehouseId: warehouseId);
  }

  @override
  Future<void> updatePlanStatus(int planId, String status) {
    return _db.updatePlanStatus(planId, status);
  }

  @override
  Future<int> generateCycleCountTask({
    required int planId,
    required int warehouseId,
    required int productsPerTask,
    String? abcClassification,
    int? assignedTo,
  }) {
    return _db.generateCycleCountTask(
      planId: planId,
      warehouseId: warehouseId,
      productsPerTask: productsPerTask,
      abcClassification: abcClassification,
      assignedTo: assignedTo,
    );
  }

  @override
  Future<List<db.CycleCountTaskData>> getCycleCountTasks({
    DateTime? fromDate,
    DateTime? toDate,
    int? assignedTo,
    String? status,
  }) {
    return _db.getCycleCountTasks(
      fromDate: fromDate,
      toDate: toDate,
      assignedTo: assignedTo,
      status: status,
    );
  }

  @override
  Future<List<db.CycleCountItemData>> getCycleCountItems(int taskId) {
    return _db.getCycleCountItems(taskId);
  }

  @override
  Future<List<db.CycleCountItemView>> getCycleCountItemsWithProduct(int taskId) {
    return _db.getCycleCountItemsWithProduct(taskId);
  }

  @override
  Future<void> submitCount({
    required int itemId,
    required double countedQty,
    String? notes,
  }) {
    return _db.submitCount(
      itemId: itemId,
      countedQty: countedQty,
      notes: notes,
    );
  }

  @override
  Future<void> startCycleCountTask(int taskId) {
    return _db.startCycleCountTask(taskId);
  }

  @override
  Future<List<Map<String, dynamic>>> getVarianceReport({
    DateTime? fromDate,
    DateTime? toDate,
    int? warehouseId,
  }) {
    return _db.getVarianceReport(
      fromDate: fromDate,
      toDate: toDate,
      warehouseId: warehouseId,
    );
  }

  @override
  Future<double> getCountAccuracy({int? planId}) {
    return _db.getCountAccuracy(planId: planId);
  }

  @override
  Future<void> finalizeCycleCountTask(int taskId, {int? approverUserId}) async {
    // Pre-deploy BLOCKER (option B): same local-only silent-loss hazard as
    // stock-audit finalize — the cycle-count subsystem is not yet sync-aware, so
    // on a client/mirror device the applied adjustments + settlement JE never
    // reach HQ and are reverted on the next serverWins pull. Refuse until a
    // sync-aware finalize exists; finalize on the server.
    if (SyncInterceptor.isClientMode) {
      throw StateError(
          'لا يمكن اعتماد الجرد من جهاز عميل أو مرآة. نفّذ الجرد واعتماده على الخادم الرئيسي.');
    }
    // WH-008: a task with count passes from the warehouse phones is approved by
    // the SAME rule as on the phone (recount first, an approver who is none of
    // the counters, the documents posted) - never by skipping it.
    final counts = WhCountService(_db, WhDocStore(_db));
    if (await counts.hasPhonePasses(taskId)) {
      if (approverUserId == null) {
        throw StateError('لهذه المهمة جرد من تطبيق المخازن؛ يلزم اعتماد مستخدم غير من عدّها.');
      }
      try {
        await _db.transaction(() => counts.approveFromDesk(taskId, approverUserId));
      } on WhError catch (e) {
        throw StateError(switch (e.code) {
          'recount_required' => 'يلزم عدّ ثانٍ بعدّاد آخر قبل الاعتماد.',
          'self_approval' => 'لا يعتمد الجرد من عدّه أو أُسندت إليه المهمة؛ يعتمده مستخدم آخر.',
          'permission_denied' => 'ليست لديك صلاحية اعتماد الجرد.',
          _ => 'تعذّر اعتماد الجرد (${e.code}).',
        });
      }
      return;
    }
    return _db.finalizeCycleCountTask(taskId);
  }
}
