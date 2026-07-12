import '../database/database.dart';
import '../../domain/repositories/activity_log_repository.dart';

/// Data-layer implementation of IActivityLogRepository
/// Delegates all operations to the Drift AppDatabase DAO extensions.
class ActivityLogRepositoryImpl implements IActivityLogRepository {
  final AppDatabase _db;

  ActivityLogRepositoryImpl(this._db);

  @override
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
    return _db.logActivity(
      userId: userId,
      userName: userName,
      action: action,
      entityType: entityType,
      entityId: entityId,
      description: description,
      oldValue: oldValue,
      newValue: newValue,
      amount: amount,
      ipAddress: ipAddress,
      deviceInfo: deviceInfo,
      branchId: branchId,
    );
  }

  @override
  Future<List<dynamic>> getActivityLogs({
    int limit = 100,
    int offset = 0,
    DateTime? fromDate,
    DateTime? toDate,
    int? userId,
    String? action,
    String? entityType,
    int? branchId,
  }) {
    return _db.getActivityLogs(
      limit: limit,
      offset: offset,
      fromDate: fromDate,
      toDate: toDate,
      userId: userId,
      action: action,
      entityType: entityType,
      branchId: branchId,
    );
  }

  @override
  Future<int> getActivityCount({
    DateTime? fromDate,
    DateTime? toDate,
    int? userId,
  }) {
    return _db.getActivityCount(
      fromDate: fromDate,
      toDate: toDate,
      userId: userId,
    );
  }

  @override
  Future<List<String>> getDistinctActions() => _db.getDistinctActions();

  @override
  Future<List<String>> getDistinctEntityTypes() => _db.getDistinctEntityTypes();

  @override
  Future<int> deleteOldLogs(DateTime beforeDate) =>
      _db.deleteOldLogs(beforeDate);

  @override
  Future<List<dynamic>> getFieldHistory({
    required String entityType,
    required int entityId,
  }) {
    return _db.getFieldHistory(
      entityType: entityType,
      entityId: entityId,
    );
  }
}
