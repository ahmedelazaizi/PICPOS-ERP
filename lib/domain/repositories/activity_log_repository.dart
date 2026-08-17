import '../../data/database/database.dart' show ActivityLog;

/// Activity Log repository interface
///
/// Defines the contract for activity logging operations.
/// Used as a cross-cutting concern across all presentation screens.
abstract class IActivityLogRepository {
  /// Log an activity. v138: `branchId` stamps the row at write time so the
  /// activity-log screen can filter at SQL level (Issue 18 cleanup).
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
  });

  /// Get activity logs (paginated, filtered).
  Future<List<dynamic>> getActivityLogs({
    int limit = 100,
    int offset = 0,
    DateTime? fromDate,
    DateTime? toDate,
    int? userId,
    String? action,
    String? entityType,
    int? branchId,
  });

  /// Get activity count for stats
  Future<int> getActivityCount({
    DateTime? fromDate,
    DateTime? toDate,
    int? userId,
  });

  /// Get distinct action types
  Future<List<String>> getDistinctActions();

  /// Get distinct entity types
  Future<List<String>> getDistinctEntityTypes();

  /// Delete old logs (maintenance)
  Future<int> deleteOldLogs(DateTime beforeDate);

  /// Get field change history for a specific entity
  Future<List<dynamic>> getFieldHistory({
    required String entityType,
    required int entityId,
  });

  /// سجلُّ كيانٍ واحدٍ مرتّباً من الأحدث.
  ///
  /// يُصفّي على `entityType` و`entityId` معاً — لا يكفي أحدُهما، وإلا
  /// اختلطت طاولةٌ بأخرى تحمل نفس المعرّف في كيانٍ مختلف. تغذّي شاشةَ
  /// سجل الطاولة (T11)، ويصلح الاستعلامُ نفسُه لأيّ كيانٍ آخر لاحقاً.
  Future<List<ActivityLog>> logsForEntity({
    required String entityType,
    required int entityId,
    int limit = 100,
  });
}
