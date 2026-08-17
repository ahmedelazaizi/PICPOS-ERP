part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ACTIVITY LOGS DAO (سجل العمليات)
// ═══════════════════════════════════════════════════════════════════════════

extension ActivityLogsDao on AppDatabase {
  /// Log an activity. v138 (Issue 18 cleanup): `branchId` is now stamped at
  /// write time so the activity-log screen filters at SQL level instead of
  /// approximating from user_branch_access mappings.
  Future<int> logActivity({
    required int? userId,
    required String userName,
    required String action,
    required String entityType,
    int? entityId,
    required String description,
    String? oldValue,
    String? newValue,
    double? amount,
    String? ipAddress,
    String? deviceInfo,
    int? branchId,
  }) {
    return into(activityLogs).insert(
      ActivityLogsCompanion.insert(
        userId: Value(userId),
        userName: userName,
        action: action,
        entityType: entityType,
        entityId: Value(entityId),
        // Feature 004 (US3, FR-025) — prefix the description with [ELEVATED]
        // when an elevated System Admin session is active. Applied once
        // here so every DAO callsite picks up the marker without coordinated
        // edits across treasury/fixed-assets/parties/accounts/products.
        description: maybeMarkElevated(description),
        oldValue: Value(oldValue),
        newValue: Value(newValue),
        amount: Value(amount),
        ipAddress: Value(ipAddress),
        deviceInfo: Value(deviceInfo),
        createdAt: Value(DateTime.now()),
        branchId: Value(branchId),
      ),
    );
  }

  /// Get all activity logs (paginated). v138 (Issue 18 cleanup): `branchId`
  /// applies a SQL-level filter on the persisted column, replacing the
  /// previous client-side approximation that misclassified users moved
  /// between branches.
  Future<List<ActivityLog>> getActivityLogs({
    int limit = 100,
    int offset = 0,
    DateTime? fromDate,
    DateTime? toDate,
    int? userId,
    String? action,
    String? entityType,
    int? branchId,
  }) {
    final query = select(activityLogs)
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
      ..limit(limit, offset: offset);

    if (fromDate != null) {
      query.where((t) => t.createdAt.isBiggerOrEqual(Variable(fromDate)));
    }
    if (toDate != null) {
      query.where((t) => t.createdAt.isSmallerOrEqual(Variable(toDate)));
    }
    if (userId != null) {
      query.where((t) => t.userId.equals(userId));
    }
    if (action != null) {
      query.where((t) => t.action.equals(action));
    }
    if (entityType != null) {
      query.where((t) => t.entityType.equals(entityType));
    }
    if (branchId != null) {
      query.where((t) => t.branchId.equals(branchId));
    }

    return query.get();
  }

  /// Get activity count for stats
  Future<int> getActivityCount({
    DateTime? fromDate,
    DateTime? toDate,
    int? userId,
  }) async {
    final query = selectOnly(activityLogs)
      ..addColumns([activityLogs.id.count()]);

    if (fromDate != null) {
      query.where(activityLogs.createdAt.isBiggerOrEqual(Variable(fromDate)));
    }
    if (toDate != null) {
      query.where(activityLogs.createdAt.isSmallerOrEqual(Variable(toDate)));
    }
    if (userId != null) {
      query.where(activityLogs.userId.equals(userId));
    }

    final result = await query.getSingle();
    return result.read(activityLogs.id.count()) ?? 0;
  }

  /// Get distinct action types
  Future<List<String>> getDistinctActions() async {
    final query = selectOnly(activityLogs, distinct: true)
      ..addColumns([activityLogs.action]);

    final results = await query.get();
    return results.map((r) => r.read(activityLogs.action)!).toList();
  }

  /// Get distinct entity types
  Future<List<String>> getDistinctEntityTypes() async {
    final query = selectOnly(activityLogs, distinct: true)
      ..addColumns([activityLogs.entityType]);

    final results = await query.get();
    return results.map((r) => r.read(activityLogs.entityType)!).toList();
  }

  /// Delete old logs (for maintenance)
  Future<int> deleteOldLogs(DateTime beforeDate) {
    return (delete(
      activityLogs,
    )..where((t) => t.createdAt.isSmallerThan(Variable(beforeDate)))).go();
  }

  /// سجلُّ كيانٍ واحدٍ مرتّباً من الأحدث — يغذّي شاشةَ سجل الطاولة (T11).
  /// يُصفّى على `entityType` و`entityId` معاً فلا تتسرّب سجلّاتُ كيانٍ آخر
  /// يصادف نفسَ الرقم (مثلاً طاولةٌ وطلبٌ بنفس المعرّف).
  Future<List<ActivityLog>> logsForEntity({
    required String entityType,
    required int entityId,
    int limit = 100,
  }) {
    return (select(activityLogs)
          ..where(
            (t) =>
                t.entityType.equals(entityType) & t.entityId.equals(entityId),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(limit))
        .get();
  }
}
