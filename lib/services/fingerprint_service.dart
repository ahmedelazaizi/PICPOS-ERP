import 'package:flutter/foundation.dart';
import 'package:flutter_zkteco/flutter_zkteco.dart';

/// A single attendance log entry from a ZKTeco device.
class DeviceAttendanceLog {
  /// User ID on the device.
  final String uid;

  /// Timestamp of the event.
  final DateTime timestamp;

  /// 0 = Check-In, 1 = Check-Out.
  final int status;

  /// 0 = Password, 1 = Fingerprint, 2 = Card.
  final int verifyMode;

  DeviceAttendanceLog({
    required this.uid,
    required this.timestamp,
    required this.status,
    required this.verifyMode,
  });

  @override
  String toString() => 'Log(uid=$uid, time=$timestamp, status=$status)';
}

/// A user registered on the fingerprint device.
class DeviceUser {
  final String uid;
  final String name;
  final int privilege;

  DeviceUser({required this.uid, required this.name, required this.privilege});

  @override
  String toString() => 'DeviceUser(uid=$uid, name=$name)';
}

/// Service for communicating with ZKTeco fingerprint/attendance devices
/// over TCP/IP using the `flutter_zkteco` SDK.
///
/// ZKTeco devices communicate on TCP port 4370 by default.
/// This service wraps that communication with a high-level API
/// for connection testing, attendance log retrieval, and user management.
class FingerprintService {
  ZKTeco? _device;

  /// Whether the service is currently connected to a device.
  bool get isConnected => _device != null;

  /// Connect to a ZKTeco device at [ip]:[port].
  ///
  /// Returns `true` if the connection succeeds.
  Future<bool> connect(String ip, int port) async {
    try {
      _device = ZKTeco(
        ip,
        port: port,
        timeout: const Duration(seconds: 5),
        tcp: true,
        retry: 3,
      );
      final connected = await _device!.connect();
      if (connected) {
        debugPrint('[FingerprintService] Connected to $ip:$port via ZKTeco SDK');
        return true;
      } else {
        debugPrint('[FingerprintService] Connection failed to $ip:$port');
        _device = null;
        return false;
      }
    } catch (e) {
      debugPrint('[FingerprintService] Connect error: $e');
      _device = null;
      return false;
    }
  }

  /// Disconnect from the current device.
  Future<void> disconnect() async {
    try {
      await _device?.disconnect();
    } catch (_) {
      // Ignore close errors
    }
    _device = null;
  }

  /// Test connection to a device without persisting.
  ///
  /// Connects and immediately disconnects. Returns `true` on success.
  Future<bool> testConnection(String ip, int port) async {
    try {
      final testDevice = ZKTeco(
        ip,
        port: port,
        timeout: const Duration(seconds: 5),
        tcp: true,
        retry: 1,
      );
      final connected = await testDevice.connect();
      if (connected) {
        await testDevice.disconnect();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Fetch attendance logs from the connected device.
  ///
  /// Returns a list of [DeviceAttendanceLog] entries.
  /// Uses flutter_zkteco SDK `getAttendanceLogs()`.
  Future<List<DeviceAttendanceLog>> fetchAttendanceLogs() async {
    _ensureConnected();
    try {
      final logs = await _device!.getAttendanceLogs();
      debugPrint('[FingerprintService] Fetched ${logs.length} attendance logs');
      return logs.map((log) {
        return DeviceAttendanceLog(
          uid: log.id ?? '',
          timestamp: log.timestamp ?? DateTime.now(),
          status: log.state ?? 0,
          verifyMode: log.type ?? 0,
        );
      }).toList();
    } catch (e) {
      debugPrint('[FingerprintService] fetchAttendanceLogs error: $e');
      return [];
    }
  }

  /// Fetch registered users from the device.
  /// Uses flutter_zkteco SDK `getUsers()`.
  Future<List<DeviceUser>> fetchDeviceUsers() async {
    _ensureConnected();
    try {
      final users = await _device!.getUsers();
      debugPrint('[FingerprintService] Fetched ${users.length} device users');
      return users.map((u) => DeviceUser(
            uid: u.userId ?? '',
            name: u.name ?? '',
            privilege: u.role == UserType.admin ? 14 : 0,
          )).toList();
    } catch (e) {
      debugPrint('[FingerprintService] fetchDeviceUsers error: $e');
      return [];
    }
  }

  /// Upload an employee to the device.
  /// Note: flutter_zkteco v1.2.0 does not expose setUser().
  /// This method is a stub for future SDK versions.
  Future<bool> uploadUser(String uid, String name) async {
    _ensureConnected();
    debugPrint('[FingerprintService] uploadUser uid=$uid name=$name — SDK does not support setUser yet');
    return false;
  }

  /// Clear all attendance logs from the device (post-import cleanup).
  /// Note: flutter_zkteco v1.2.0 does not expose clearAttendanceLogs().
  /// This method is a stub for future SDK versions.
  Future<bool> clearAttendanceLogs() async {
    _ensureConnected();
    debugPrint('[FingerprintService] clearAttendanceLogs — SDK does not support clearLogs yet');
    return false;
  }

  void _ensureConnected() {
    if (!isConnected) {
      throw StateError('الجهاز غير متصل');
    }
  }

  /// Release resources.
  void dispose() {
    disconnect();
  }
}
