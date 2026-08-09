import '../../data/database/database.dart' as db;
import '../../services/fingerprint_service.dart';

abstract class IFingerprintRepository {
  Future<bool> testConnection(String ip, int port);
  Future<bool> connect(String ip, int port);
  Future<void> disconnect();
  Future<List<DeviceAttendanceLog>> fetchLogs();
  Future<bool> uploadUser(String uid, String name);
  
  // Database ops
  Future<db.Employee?> getEmployeeByDeviceUserId(String deviceUserId);
  Future<void> importCheckIn(int employeeId, DateTime timestamp);
  Future<void> importCheckOut(int employeeId, DateTime timestamp);
  Future<List<db.Employee>> getAllEmployees({required Set<int>? allowedBranchIds});
}
