import '../../domain/repositories/fingerprint_repository.dart';
import '../database/database.dart' as db;
import '../database/extensions/hr_extensions.dart';
import '../../services/fingerprint_service.dart';

class FingerprintRepositoryImpl implements IFingerprintRepository {
  final db.AppDatabase _db;
  final FingerprintService _service;

  FingerprintRepositoryImpl(this._db, this._service);

  @override
  Future<bool> testConnection(String ip, int port) => _service.testConnection(ip, port);

  @override
  Future<bool> connect(String ip, int port) => _service.connect(ip, port);

  @override
  Future<void> disconnect() => _service.disconnect();

  @override
  Future<List<DeviceAttendanceLog>> fetchLogs() => _service.fetchAttendanceLogs();

  @override
  Future<bool> uploadUser(String uid, String name) => _service.uploadUser(uid, name);

  @override
  Future<db.Employee?> getEmployeeByDeviceUserId(String deviceUserId) async {
    final query = _db.select(_db.employees)
      ..where((e) => e.deviceUserId.equals(deviceUserId));
    return query.getSingleOrNull();
  }

  // B2 — both of these used to write blind. `importCheckIn` inserted a row per
  // call with no match on (employeeId, date), and the device's logs are never
  // cleared (`clearAttendanceLogs()` is a stub returning false,
  // fingerprint_service.dart:167) while `fingerprint_last_sync` is written but
  // never read back as a filter — so every «ترحيل الحضور» re-read the SAME
  // logs. Three presses over 26 days produced 78 `present` rows, and salary is
  // computed by counting them: a 3000 salary paid 7800.
  //
  // The correct upsert already existed as `importDeviceCheckIn` /
  // `importDeviceCheckOut` (hr_extensions.dart) with no caller at all. These
  // now delegate to it instead of carrying a second, wrong implementation.
  //
  // The durable UNIQUE(employee_id, date) guard is provided by the existing
  // v152 migration and the import methods below use that upsert path. Device
  // cursor filtering remains a separate service-level concern.

  @override
  Future<void> importCheckIn(int employeeId, DateTime timestamp) =>
      _db.importDeviceCheckIn(employeeId, timestamp);

  @override
  Future<void> importCheckOut(int employeeId, DateTime timestamp) =>
      _db.importDeviceCheckOut(employeeId, timestamp);

  @override
  Future<List<db.Employee>> getAllEmployees({required Set<int>? allowedBranchIds}) =>
      // كان `select(employees).get()` خاماً — بلا أيّ حصر. وجهازُ البصمة
      // **في فرعٍ بعينه**، فرفعُ موظفي الشركة كلِّها إليه يضع أسماءَهم على
      // جهازٍ لا يملكه صاحبُ الفرع. والتوحيدُ على `_db.getAllEmployees` يجعل
      // دلالةَ الحصر واحدةً في المسارين (‏NULL = مستوى الشركة فيبقى مرئياً).
      _db.getAllEmployees(allowedBranchIds: allowedBranchIds);
}
