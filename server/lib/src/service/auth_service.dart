import '../db/database.dart';
import '../security.dart';
import 'errors.dart';

/// Device pairing (code -> device token), device authentication, rep login.
/// Rules mirror desktop LAN pairing (lib/services/api/lan_pairing_service.dart):
/// 8-char code without look-alikes, 10 min TTL, single use, 5 attempts/IP/10 min.
/// Difference: the device token is random and only its SHA-256 is stored, so
/// each device can be revoked/rotated individually.
class AuthService {
  AuthService(this.db, this.sessions);
  final CloudDatabase db;
  final SessionTokens sessions;

  static const pairingTtl = Duration(minutes: 10);
  static const _maxAttempts = 5;
  static const _window = Duration(minutes: 10);
  final Map<String, List<DateTime>> _attempts = {};

  int get _now => DateTime.now().millisecondsSinceEpoch;

  Future<({String code, int expiresAt})> issuePairingCode({
    required int companyId,
    required String employeeGlobalId,
  }) async {
    final emp = await db.query(
        'SELECT id FROM employees WHERE company_id=@c AND global_id=@g AND is_active',
        {'c': companyId, 'g': employeeGlobalId});
    if (emp.isEmpty) throw ApiError(404, 'employee_not_found');
    final code = randomPairingCode();
    final exp = _now + pairingTtl.inMilliseconds;
    await db.query(
        'INSERT INTO pairing_codes (company_id, employee_id, code_hash, expires_at, created_at) '
        'VALUES (@c, @e, @h, @x, @n)',
        {'c': companyId, 'e': emp.first[0], 'h': sha256Hex(code), 'x': exp, 'n': _now});
    return (code: code, expiresAt: exp);
  }

  bool _allowAttempt(String ip) {
    final now = DateTime.now();
    final list = _attempts.putIfAbsent(ip, () => [])
      ..removeWhere((t) => now.difference(t) > _window);
    if (list.length >= _maxAttempts) return false;
    list.add(now);
    return true;
  }

  Future<({String deviceToken, String deviceId, String employeeGlobalId})> pair({
    required String code,
    required String deviceId,
    String? deviceName,
    String ip = 'unknown',
  }) async {
    if (!_allowAttempt(ip)) throw ApiError(429, 'too_many_attempts');
    final normalized = code.trim().toUpperCase();
    if (normalized.length != 8 || deviceId.trim().isEmpty) {
      throw ApiError(400, 'invalid_request');
    }
    return db.tx((s) async {
      // Lookup by hash (an equality on a hash leaks nothing useful about the code).
      final rows = await db.q(s, '''
        SELECT pc.id, pc.company_id, pc.employee_id, pc.expires_at, pc.used_at, e.global_id
        FROM pairing_codes pc JOIN employees e ON e.id = pc.employee_id
        WHERE pc.code_hash = @h FOR UPDATE OF pc''', {'h': sha256Hex(normalized)});
      if (rows.isEmpty) throw ApiError(401, 'invalid_code');
      final r = rows.first.toColumnMap();
      if (r['used_at'] != null || (r['expires_at'] as int) < _now) {
        throw ApiError(401, 'code_expired');
      }
      await db.q(s, 'UPDATE pairing_codes SET used_at=@n WHERE id=@id', {'n': _now, 'id': r['id']});
      final token = randomToken();
      final existing = await db.q(
          s, 'SELECT id, company_id FROM devices WHERE device_id=@d', {'d': deviceId});
      if (existing.isNotEmpty && existing.first[1] != r['company_id']) {
        throw ApiError(409, 'device_belongs_to_other_company');
      }
      await db.q(s, '''
        INSERT INTO devices (company_id, device_id, name, employee_id, token_hash, paired_at, last_seen_ip)
        VALUES (@c, @d, @nm, @e, @h, @n, @ip)
        ON CONFLICT (device_id) DO UPDATE SET name=EXCLUDED.name, employee_id=EXCLUDED.employee_id,
          token_hash=EXCLUDED.token_hash, paired_at=EXCLUDED.paired_at, revoked_at=NULL,
          last_seen_ip=EXCLUDED.last_seen_ip''', {
        'c': r['company_id'],
        'd': deviceId,
        'nm': deviceName,
        'e': r['employee_id'],
        'h': sha256Hex(token),
        'n': _now,
        'ip': ip,
      });
      await db.q(s, "INSERT INTO audit_log (company_id, employee_id, action, entity, ip, detail, at) "
          "VALUES (@c, @e, 'device_paired', 'device', @ip, @d, @n)",
          {'c': r['company_id'], 'e': r['employee_id'], 'ip': ip, 'd': deviceId, 'n': _now});
      return (deviceToken: token, deviceId: deviceId, employeeGlobalId: r['global_id'] as String);
    });
  }

  Future<DeviceContext> authenticateDevice(String? bearer, String? deviceId) async {
    if (bearer == null || deviceId == null || bearer.isEmpty) {
      throw ApiError(401, 'missing_device_token');
    }
    final rows = await db.query(
        'SELECT id, company_id, employee_id, token_hash, revoked_at FROM devices WHERE device_id=@d',
        {'d': deviceId});
    if (rows.isEmpty) throw ApiError(401, 'unknown_device');
    final r = rows.first.toColumnMap();
    if (!constantTimeEquals(r['token_hash'] as String, sha256Hex(bearer))) {
      throw ApiError(401, 'invalid_device_token');
    }
    if (r['revoked_at'] != null) throw ApiError(401, 'device_revoked');
    await db.query('UPDATE devices SET last_seen_at=@n WHERE id=@id', {'n': _now, 'id': r['id']});
    return DeviceContext(
      devicePk: r['id'] as int,
      deviceId: deviceId,
      companyId: r['company_id'] as int,
      employeeId: r['employee_id'] as int,
    );
  }

  Future<void> revokeDevice(String deviceId) async {
    await db.query('UPDATE devices SET revoked_at=@n WHERE device_id=@d', {'n': _now, 'd': deviceId});
    await db.query(
        "UPDATE device_number_leases SET status='revoked' WHERE status='active' AND "
        'device_pk = (SELECT id FROM devices WHERE device_id=@d)',
        {'d': deviceId});
  }

  /// Rep login on a paired device: PIN of the employee bound to the device.
  Future<String> login(DeviceContext d, String pin) async {
    final rows = await db.query(
        'SELECT pin_hash, is_active FROM employees WHERE id=@e', {'e': d.employeeId});
    if (rows.isEmpty || rows.first[1] != true) throw ApiError(401, 'employee_inactive');
    final hash = rows.first[0] as String?;
    if (hash == null || !verifyPin(pin, hash)) throw ApiError(401, 'invalid_pin');
    return sessions.issue(
        employeeId: d.employeeId, devicePk: d.devicePk, companyId: d.companyId);
  }

  void requireSession(DeviceContext d, String? sessionToken) {
    final claims = sessionToken == null ? null : sessions.verify(sessionToken);
    if (claims == null) throw ApiError(401, 'invalid_session');
    if (claims['did'] != d.devicePk || claims['uid'] != d.employeeId) {
      throw ApiError(401, 'session_device_mismatch');
    }
  }
}
