abstract class IAuditRepository {
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
  });

  Future<void> logEmployeeAction({
    required int? userId,
    required String userName,
    required String action,
    required int employeeId,
    required String description,
    String? oldValue,
    String? newValue,
  });

  Future<List<dynamic>> getFieldHistory({
    required String entityType,
    required int entityId,
  });
}
