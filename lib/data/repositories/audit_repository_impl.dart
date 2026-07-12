import '../../domain/repositories/audit_repository_interface.dart';
import '../database/database.dart';

class AuditRepositoryImpl implements IAuditRepository {
  final AppDatabase _db;

  AuditRepositoryImpl(this._db);

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
    );
  }

  @override
  Future<void> logEmployeeAction({
    required int? userId,
    required String userName,
    required String action,
    required int employeeId,
    required String description,
    String? oldValue,
    String? newValue,
  }) async {
    await logActivity(
      userId: userId,
      userName: userName,
      action: action,
      entityType: 'employee',
      entityId: employeeId,
      description: description,
      oldValue: oldValue,
      newValue: newValue,
    );
  }

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
