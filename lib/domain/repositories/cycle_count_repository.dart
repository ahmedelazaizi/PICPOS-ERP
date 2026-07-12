import '../../data/database/database.dart' as db;

abstract class ICycleCountRepository {
  Future<int> createCycleCountPlan({
    required String name,
    required int warehouseId,
    required String frequency,
    String abcClassification = 'all',
    int productsPerTask = 20,
    int? createdBy,
  });

  Future<List<db.CycleCountPlanData>> getActiveCycleCountPlans();

  Future<List<db.CycleCountPlanData>> getCycleCountPlans({int? warehouseId});

  Future<void> updatePlanStatus(int planId, String status);

  Future<int> generateCycleCountTask({
    required int planId,
    required int warehouseId,
    required int productsPerTask,
    String? abcClassification,
    int? assignedTo,
  });

  Future<List<db.CycleCountTaskData>> getCycleCountTasks({
    DateTime? fromDate,
    DateTime? toDate,
    int? assignedTo,
    String? status,
  });

  Future<List<db.CycleCountItemData>> getCycleCountItems(int taskId);

  Future<void> submitCount({
    required int itemId,
    required double countedQty,
    String? notes,
  });

  Future<void> startCycleCountTask(int taskId);

  Future<List<Map<String, dynamic>>> getVarianceReport({
    DateTime? fromDate,
    DateTime? toDate,
    int? warehouseId,
  });

  Future<double> getCountAccuracy({int? planId});

  /// Spec 147 (S-COUNT): atomic finalize — completes the task, applies the
  /// variances, and posts ONE settlement JE in a single transaction. Replaces
  /// the old repo-level completeCycleCountTask + applyCycleCountAdjustments
  /// (removed — they had no callers once the screen switched to finalize).
  Future<void> finalizeCycleCountTask(int taskId);
}
