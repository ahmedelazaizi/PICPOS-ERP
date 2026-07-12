import 'package:drift/drift.dart';
import '../../domain/repositories/fingerprint_repository.dart';
import '../database/database.dart' as db;
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

  @override
  Future<void> importCheckIn(int employeeId, DateTime timestamp) async {
    await _db.into(_db.employeeAttendance).insert(
      db.EmployeeAttendanceCompanion.insert(
        employeeId: employeeId,
        date: DateTime(timestamp.year, timestamp.month, timestamp.day),
        checkIn: Value(timestamp),
      ),
    );
  }

  @override
  Future<void> importCheckOut(int employeeId, DateTime timestamp) async {
    // Find the latest open attendance record and update its check-out
    final openRecord = await (_db.select(_db.employeeAttendance)
          ..where((a) => a.employeeId.equals(employeeId))
          ..where((a) => a.checkOut.isNull())
          ..orderBy([(a) => OrderingTerm.desc(a.checkIn)])
          ..limit(1))
        .getSingleOrNull();
    if (openRecord != null) {
      await (_db.update(_db.employeeAttendance)
            ..where((a) => a.id.equals(openRecord.id)))
          .write(db.EmployeeAttendanceCompanion(checkOut: Value(timestamp)));
    }
  }

  @override
  Future<List<db.Employee>> getAllEmployees() =>
      _db.select(_db.employees).get();
}
