import '../db/database.dart';
import '../security.dart';
import 'errors.dart';
import 'rate_limiter.dart';

/// Device pairing (code -> device token), device authentication, token
/// rotation/revocation, rep login.
/// Rules mirror desktop LAN pairing (lib/services/api/lan_pairing_service.dart):
/// 8-char code without look-alikes, 10 min TTL, single use, 5 attempts/IP/10 min.
/// Difference: the device token is random and only its SHA-256 is stored, so
/// each device can be revoked/rotated individually.
class AuthService {
  AuthService(this.db, this.sessions, {RateLimiter? pairLimiter, RateLimiter? loginLimiter})
      : _pairLimiter = pairLimiter ?? RateLimiter(max: 5, window: const Duration(minutes: 10)),
        _loginLimiter = loginLimiter ?? RateLimiter(max: 10, window: const Duration(minutes: 10));
  final CloudDatabase db;
  final SessionTokens sessions;
  final RateLimiter _pairLimiter;
  final RateLimiter _loginLimiter;

  static const pairingTtl = Duration(minutes: 10);

  /// After a rotation the previous token keeps working until the device first
  /// uses the new one, at most this long (a lost rotate response must not lock
  /// the device out).
  static const rotationGrace = Duration(hours: 24);

  int get _now => DateTime.now().millisecondsSinceEpoch;

  Future<void> _audit(int? companyId, int? devicePk, int? employeeId, String action, String ip,
          [String? detail]) =>
      db.query('''
        INSERT INTO audit_log (company_id, device_pk, employee_id, action, entity, ip, detail, at)
        VALUES (@c, @d, @e, @a, 'device', @ip, @dt, @n)''',
          {'c': companyId, 'd': devicePk, 'e': employeeId, 'a': action, 'ip': ip, 'dt': detail, 'n': _now});

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

  Future<({String deviceToken, String deviceId, String employeeGlobalId})> pair({
    required String code,
    required String deviceId,
    String? deviceName,
    String ip = 'unknown',
  }) async {
    _pairLimiter.hit(ip, code: 'too_many_attempts');
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
        INSERT INTO devices (company_id, device_id, name, employee_id, token_hash, paired_at, last_seen_ip,
          token_rotated_at)
        VALUES (@c, @d, @nm, @e, @h, @n, @ip, @n)
        ON CONFLICT (device_id) DO UPDATE SET name=EXCLUDED.name, employee_id=EXCLUDED.employee_id,
          token_hash=EXCLUDED.token_hash, previous_token_hash=NULL, paired_at=EXCLUDED.paired_at,
          revoked_at=NULL, last_seen_ip=EXCLUDED.last_seen_ip, token_rotated_at=EXCLUDED.token_rotated_at''', {
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

  Future<DeviceContext> authenticateDevice(String? bearer, String? deviceId, {String ip = 'unknown'}) async {
    if (bearer == null || deviceId == null || bearer.isEmpty) {
      throw ApiError(401, 'missing_device_token');
    }
    final rows = await db.query('''
        SELECT id, company_id, employee_id, token_hash, revoked_at, previous_token_hash, token_rotated_at
        FROM devices WHERE device_id=@d''', {'d': deviceId});
    if (rows.isEmpty) throw ApiError(401, 'unknown_device');
    final r = rows.first.toColumnMap();
    final presented = sha256Hex(bearer);
    final current = constantTimeEquals(r['token_hash'] as String, presented);
    final prev = r['previous_token_hash'] as String?;
    final inGrace = prev != null &&
        constantTimeEquals(prev, presented) &&
        _now - ((r['token_rotated_at'] as int?) ?? 0) <= rotationGrace.inMilliseconds;
    if (!current && !inGrace) throw ApiError(401, 'invalid_device_token');
    if (r['revoked_at'] != null) throw ApiError(401, 'device_revoked');
    await db.query('''
        UPDATE devices SET last_seen_at=@n, last_seen_ip=@ip,
          previous_token_hash = CASE WHEN @cur THEN NULL ELSE previous_token_hash END
        WHERE id=@id''', {'n': _now, 'ip': ip, 'cur': current, 'id': r['id']});
    return DeviceContext(
      devicePk: r['id'] as int,
      deviceId: deviceId,
      companyId: r['company_id'] as int,
      employeeId: r['employee_id'] as int,
      ip: ip,
      tokenHash: presented,
    );
  }

  /// Issues a new device token. The token used for this call stays valid as
  /// the "previous" token until the new one is first used (≤ [rotationGrace]),
  /// so a lost response is recoverable; any older token stops working now.
  Future<String> rotateToken(DeviceContext d) async {
    final token = randomToken();
    await db.query('''
      UPDATE devices SET previous_token_hash=@prev, token_hash=@h, token_rotated_at=@n
      WHERE id=@id AND revoked_at IS NULL''',
        {'prev': d.tokenHash, 'h': sha256Hex(token), 'n': _now, 'id': d.devicePk});
    await _audit(d.companyId, d.devicePk, d.employeeId, 'token_rotated', d.ip);
    return token;
  }

  /// Revokes the device: all its calls get 401 `device_revoked` (the app wipes
  /// its local data) and its number leases are revoked (unused numbers become
  /// audited gaps, never re-issued).
  ///
  /// [companyId] scopes the revoke to one company (desktop link callers): a
  /// device of another company is reported as `unknown_device`.
  Future<void> revokeDevice(String deviceId, {String ip = 'unknown', String? reason, int? companyId}) async {
    final rows = await db.query('''
        UPDATE devices SET revoked_at=@n, previous_token_hash=NULL WHERE device_id=@d
        ${companyId == null ? '' : 'AND company_id=@c'}
        RETURNING id, company_id, employee_id''', {
      'n': _now,
      'd': deviceId,
      if (companyId != null) 'c': companyId,
    });
    if (rows.isEmpty) throw ApiError(404, 'unknown_device');
    await db.query(
        "UPDATE device_number_leases SET status='revoked' WHERE status IN ('active','exhausted') AND device_pk=@d",
        {'d': rows.first[0]});
    await _audit(rows.first[1] as int, rows.first[0] as int, rows.first[2] as int, 'device_revoked', ip,
        reason ?? deviceId);
  }

  /// Rep login on a paired device: PIN of the employee bound to the device.
  /// Limited to 10 attempts per device per 10 minutes.
  Future<String> login(DeviceContext d, String pin) async {
    _loginLimiter.hit(d.deviceId, code: 'too_many_attempts');
    final rows = await db.query(
        'SELECT pin_hash, is_active FROM employees WHERE id=@e', {'e': d.employeeId});
    if (rows.isEmpty || rows.first[1] != true) throw ApiError(401, 'employee_inactive');
    final hash = rows.first[0] as String?;
    if (hash == null || !verifyPin(pin, hash)) {
      await _audit(d.companyId, d.devicePk, d.employeeId, 'login_failed', d.ip);
      throw ApiError(401, 'invalid_pin');
    }
    await _audit(d.companyId, d.devicePk, d.employeeId, 'login', d.ip);
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
