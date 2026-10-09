import 'dart:convert';

import 'package:postgres/postgres.dart' show Session;

import '../db/database.dart';
import '../security.dart';
import 'desktop_service.dart';
import 'errors.dart';
import 'rate_limiter.dart';

/// Authenticated «PicPos إدارة» device (+ optional session) context.
class AdminContext {
  AdminContext({
    required this.devicePk,
    required this.deviceId,
    required this.companyId,
    required this.userId,
    this.ip = 'unknown',
  });
  final int devicePk;
  final String deviceId;
  final int companyId;
  final int userId;
  final String ip;
}

/// Mirrored desktop user as seen by the cloud.
class AdminUser {
  AdminUser(this.row);
  final Map<String, dynamic> row;

  int get id => row['id'] as int;
  String get globalId => row['global_id'] as String;
  String get username => row['username'] as String;
  String? get displayName => row['display_name'] as String?;
  bool get mobileEnabled => row['mobile_enabled'] == true;
  List<String> get permissions => [for (final p in _list(row['permissions'])) '$p'];
  List<int> get branchScope => [
        for (final b in _list(row['branch_scope']))
          if (b is int) b else if (int.tryParse('$b') != null) int.parse('$b'),
      ];

  /// Plain or conditional (`cond:` marker) grant of [code].
  bool has(String code) => permissions.contains(code) || permissions.contains('cond:$code');

  /// Empty scope = all branches (desktop `UserBranchAccess` convention).
  bool get allBranches => branchScope.isEmpty;

  bool get canUseApp => mobileEnabled && has(AdminService.accessCode);

  Map<String, Object?> toJson() => {
        'globalId': globalId,
        'username': username,
        'displayName': displayName,
        'locale': row['locale'],
        'permissions': permissions,
        'branchScope': branchScope,
        'require2fa': row['require_2fa'] == true,
      };

  static List<Object?> _list(Object? v) {
    if (v is List) return v;
    if (v is String && v.isNotEmpty) {
      final d = jsonDecode(v);
      if (d is List) return d;
    }
    return const [];
  }
}

/// M-1 of ARCHITECTURE-M: users mirror + signing key + signed snapshots pushed
/// by the desktop; admin pairing, mobile-password login and permission-scoped
/// snapshot reads for «PicPos إدارة». The cloud never computes a figure: it
/// stores what the desktop signed and filters what a user may see.
class AdminService {
  AdminService(
    this.db,
    this.sessions, {
    RateLimiter? pairLimiter,
    RateLimiter? loginLimiter,
    DateTime Function()? clock,
  })  : _pairLimiter = pairLimiter ?? RateLimiter(max: 5, window: const Duration(minutes: 10)),
        _loginLimiter = loginLimiter ?? RateLimiter(max: 10, window: const Duration(minutes: 10)),
        _clock = clock ?? DateTime.now;

  final CloudDatabase db;

  /// Must use a secret distinct from rep sessions (see `CloudServices`), so a
  /// rep session can never be replayed on `/manage/*` and vice versa.
  final SessionTokens sessions;
  final RateLimiter _pairLimiter;
  final RateLimiter _loginLimiter;
  final DateTime Function() _clock;

  static const accessCode = 'mobile_admin_access';
  static const pairingTtl = Duration(minutes: 10);
  static const lockoutAfter = 5;
  static const lockoutFor = Duration(minutes: 15);
  static const dailyRetention = Duration(days: 35);
  static const maxSnapshotItems = 200;
  static const maxPayloadChars = 512 * 1024;

  /// Snapshot kind → permission code needed to read it (ARCHITECTURE-M §3.3).
  /// Prefix `approvals.` is handled by [approvalCodes].
  static const kindCodes = <String, List<String>>{
    'kpi.today': ['dashboard_sales_today'],
    'kpi.month': ['dashboard_sales_today'],
    'profit.today': ['dashboard_profit'],
    'profit.month': ['dashboard_profit'],
    'cash.position': ['treasury_view'],
    'parties.position': ['reports_view'],
    'branches.performance': ['reports_sales'],
    'reps.performance': ['reports_sales'],
  };

  /// `approvals.<category>` → any of these codes.
  static const approvalCodes = <String, List<String>>{
    'approvals.sales_returns': ['sales_return_approve'],
    'approvals.purchase_returns': ['purchases_return_approve'],
    'approvals.leave': ['hr_leave_approve'],
    'approvals.payroll': ['hr_payroll_approve', 'hr_payroll_post'],
    'approvals.journals': ['approve_journal'],
  };

  /// Daily kinds keep one row per day for [dailyRetention]; others keep only
  /// the latest row.
  static const dailyKinds = {'kpi.today', 'profit.today'};

  static final _scopeRe = RegExp(r'^(all|branch:\d{1,9})$');

  int get _now => _clock().millisecondsSinceEpoch;

  static List<String>? codesForKind(String kind) => kindCodes[kind] ?? approvalCodes[kind];

  /// Whether [u] may read snapshot ([kind], [scope]).
  static bool canRead(AdminUser u, String kind, String scope) {
    final codes = codesForKind(kind);
    if (codes == null || !codes.any(u.has)) return false;
    if (scope == 'all') return u.allBranches;
    final id = int.tryParse(scope.substring('branch:'.length));
    return u.allBranches || (id != null && u.branchScope.contains(id));
  }

  Future<void> _audit(int companyId, String action, String ip, [String? detail]) => db.query('''
        INSERT INTO audit_log (company_id, action, entity, ip, detail, at)
        VALUES (@c, @a, 'admin_device', @ip, @dt, @n)''',
      {'c': companyId, 'a': action, 'ip': ip, 'dt': detail, 'n': _now});

  // ───────────────────────────── desktop side ─────────────────────────────

  Future<void> setSigningKey(DesktopContext d, Map<String, Object?> body) async {
    final key = body['publicKey'];
    if (key is! String || !_isEd25519Key(key)) throw ApiError(400, 'invalid_public_key');
    await db.query('UPDATE desktop_links SET signing_public_key=@k, signing_key_set_at=@n WHERE id=@id',
        {'k': key, 'n': _now, 'id': d.linkPk});
    final decimals = body['decimals'];
    if (decimals is int && decimals >= 0 && decimals <= 6) {
      await db.query('UPDATE companies SET decimal_places=@d WHERE id=@c', {'d': decimals, 'c': d.companyId});
    }
  }

  static bool _isEd25519Key(String b64) {
    try {
      return base64.decode(b64).length == 32;
    } catch (_) {
      return false;
    }
  }

  /// Desktop wins; a row is applied when its `version` is ≥ the stored one.
  /// A user who is disabled for mobile or lost `mobile_admin_access` has all
  /// their admin devices revoked (→ 401 `device_revoked` → the app wipes).
  Future<Map<String, Object?>> upsertUsers(DesktopContext d, Object? users) async {
    if (users is! List || users.length > 1000) throw ApiError(400, 'users_required_max_1000');
    var applied = 0, skipped = 0, revoked = 0;
    for (final raw in users) {
      if (raw is! Map) throw ApiError(400, 'invalid_user');
      final u = raw.cast<String, Object?>();
      final gid = u['globalId'], username = u['username'], version = u['version'];
      if (gid is! String || gid.isEmpty || username is! String || username.isEmpty || version is! int) {
        throw ApiError(400, 'invalid_user', 'globalId, username and integer version are required');
      }
      final perms = u['permissions'] ?? const [];
      final scope = u['branchScope'] ?? const [];
      if (perms is! List || perms.any((p) => p is! String)) throw ApiError(400, 'invalid_permissions');
      if (scope is! List || scope.any((b) => b is! int)) throw ApiError(400, 'invalid_branch_scope');
      final hashGiven = u.containsKey('mobilePasswordHash');
      final hash = u['mobilePasswordHash'];
      if (hashGiven && hash != null && (hash is! String || !_isPbkdf2(hash))) {
        throw ApiError(400, 'invalid_password_hash');
      }
      final enabled = u['mobileEnabled'] == true;
      final res = await db.query('''
        INSERT INTO admin_users (company_id, global_id, username, display_name, locale, mobile_enabled,
          password_hash, permissions, branch_scope, require_2fa, version, updated_at)
        VALUES (@c, @g, @u, @dn, @l, @en, @h, CAST(@p AS JSONB), CAST(@b AS JSONB), @tf, @v, @n)
        ON CONFLICT (company_id, global_id) DO UPDATE SET
          username=EXCLUDED.username, display_name=EXCLUDED.display_name, locale=EXCLUDED.locale,
          mobile_enabled=EXCLUDED.mobile_enabled,
          password_hash=CASE WHEN @hg THEN EXCLUDED.password_hash ELSE admin_users.password_hash END,
          failed_logins=CASE WHEN @hg THEN 0 ELSE admin_users.failed_logins END,
          locked_until=CASE WHEN @hg THEN NULL ELSE admin_users.locked_until END,
          permissions=EXCLUDED.permissions, branch_scope=EXCLUDED.branch_scope,
          require_2fa=EXCLUDED.require_2fa, version=EXCLUDED.version, updated_at=EXCLUDED.updated_at
        WHERE admin_users.version <= EXCLUDED.version
        RETURNING id''', {
        'c': d.companyId,
        'g': gid,
        'u': username,
        'dn': u['displayName'] as String?,
        'l': u['locale'] as String?,
        'en': enabled,
        'h': hashGiven ? hash as String? : null,
        'hg': hashGiven,
        'p': jsonEncode(perms),
        'b': jsonEncode(scope),
        'tf': u['require2fa'] == true,
        'v': version,
        'n': _now,
      });
      if (res.isEmpty) {
        skipped++;
        continue;
      }
      applied++;
      if (!enabled || !perms.contains(accessCode) && !perms.contains('cond:$accessCode')) {
        final r = await db.query(
            'UPDATE admin_devices SET revoked_at=@n WHERE user_id=@u AND revoked_at IS NULL RETURNING device_id',
            {'n': _now, 'u': res.first[0]});
        for (final x in r) {
          revoked++;
          await _audit(d.companyId, 'admin_device_revoked', d.ip, 'user_disabled:${x[0]}');
        }
      }
    }
    return {'applied': applied, 'skipped': skipped, 'devicesRevoked': revoked};
  }

  static bool _isPbkdf2(String h) {
    final p = h.split('\$');
    if (p.length != 4 || p[0] != 'pbkdf2') return false;
    final it = int.tryParse(p[1]);
    // Bounded so a pushed hash cannot turn a login into a CPU burner.
    return it != null && it >= 1000 && it <= 1000000 && p[2].isNotEmpty && p[3].isNotEmpty;
  }

  Future<Map<String, Object?>> storeSnapshots(DesktopContext d, Object? items) async {
    if (items is! List || items.length > maxSnapshotItems) {
      throw ApiError(400, 'items_required_max_$maxSnapshotItems');
    }
    var stored = 0;
    for (final raw in items) {
      if (raw is! Map) throw ApiError(400, 'invalid_snapshot');
      final it = raw.cast<String, Object?>();
      final kind = it['kind'], scope = it['scope'], sig = it['signature'];
      final asOf = DateTime.tryParse('${it['asOf']}');
      if (kind is! String || codesForKind(kind) == null) throw ApiError(400, 'unknown_snapshot_kind', '$kind');
      if (scope is! String || !_scopeRe.hasMatch(scope)) throw ApiError(400, 'invalid_scope', '$scope');
      if (asOf == null || !asOf.isUtc) throw ApiError(400, 'invalid_as_of');
      if (sig is! String || !sig.startsWith('ed25519:')) throw ApiError(400, 'invalid_signature');
      if (it['payload'] is! Map) throw ApiError(400, 'invalid_payload');
      final payload = jsonEncode(it['payload']);
      if (payload.length > maxPayloadChars) throw ApiError(413, 'payload_too_large');
      final day = dailyKinds.contains(kind) ? asOf.toIso8601String().substring(0, 10) : 'latest';
      await db.query('''
        INSERT INTO snapshots (company_id, kind, scope, as_of_day, as_of, payload, signature, received_at)
        VALUES (@c, @k, @s, @d, @a, @p, @sig, @n)
        ON CONFLICT (company_id, kind, scope, as_of_day) DO UPDATE SET as_of=EXCLUDED.as_of,
          payload=EXCLUDED.payload, signature=EXCLUDED.signature, received_at=EXCLUDED.received_at
        WHERE snapshots.as_of <= EXCLUDED.as_of''', {
        'c': d.companyId,
        'k': kind,
        's': scope,
        'd': day,
        'a': asOf.millisecondsSinceEpoch,
        'p': payload,
        'sig': sig,
        'n': _now,
      });
      stored++;
    }
    await db.query("DELETE FROM snapshots WHERE company_id=@c AND as_of_day <> 'latest' AND as_of < @cut",
        {'c': d.companyId, 'cut': _now - dailyRetention.inMilliseconds});
    return {'stored': stored};
  }

  Future<({String code, int expiresAt})> issuePairingCode(DesktopContext d, String userGlobalId) async {
    final key = await _signingKey(d.companyId);
    if (key == null) throw ApiError(409, 'signing_key_missing');
    final u = await _userByGid(d.companyId, userGlobalId);
    if (u == null) throw ApiError(404, 'user_not_found');
    if (!u.canUseApp) throw ApiError(409, 'user_not_enabled_for_mobile');
    if (u.row['password_hash'] == null) throw ApiError(409, 'mobile_password_missing');
    final code = randomPairingCode();
    final exp = _now + pairingTtl.inMilliseconds;
    await db.query('''
      INSERT INTO pairing_codes (company_id, employee_id, code_hash, expires_at, created_at, kind, user_global_id)
      VALUES (@c, NULL, @h, @x, @n, 'admin', @g)''',
        {'c': d.companyId, 'h': sha256Hex(code), 'x': exp, 'n': _now, 'g': userGlobalId});
    return (code: code, expiresAt: exp);
  }

  Future<List<Map<String, Object?>>> listDevices(DesktopContext d) async {
    final rows = await db.query('''
      SELECT ad.device_id, ad.name, u.global_id, COALESCE(u.display_name, u.username), ad.paired_at,
        ad.last_seen_at, ad.revoked_at, ad.app_version
      FROM admin_devices ad JOIN admin_users u ON u.id = ad.user_id
      WHERE ad.company_id=@c
      ORDER BY (ad.revoked_at IS NOT NULL), ad.last_seen_at DESC NULLS LAST, ad.id DESC''', {'c': d.companyId});
    return [
      for (final r in rows)
        {
          'deviceId': r[0],
          'deviceName': r[1],
          'userGlobalId': r[2],
          'userName': r[3],
          'pairedAt': r[4],
          'lastSeenAt': r[5],
          'revokedAt': r[6],
          'revoked': r[6] != null,
          'appVersion': r[7],
        },
    ];
  }

  Future<void> revokeDevice(DesktopContext d, String deviceId) async {
    final r = await db.query('''
      UPDATE admin_devices SET revoked_at=COALESCE(revoked_at, @n), previous_token_hash=NULL
      WHERE device_id=@d AND company_id=@c RETURNING id''', {'n': _now, 'd': deviceId, 'c': d.companyId});
    if (r.isEmpty) throw ApiError(404, 'unknown_device');
    await _audit(d.companyId, 'admin_device_revoked', d.ip, 'desktop:${d.linkId}:$deviceId');
  }

  // ───────────────────────────── phone side ─────────────────────────────

  Future<Map<String, Object?>> pair({
    required String code,
    required String deviceId,
    String? deviceName,
    String? appVersion,
    String ip = 'unknown',
  }) async {
    _pairLimiter.hit(ip, code: 'too_many_attempts');
    final normalized = code.trim().toUpperCase();
    if (normalized.length != 8 || deviceId.trim().isEmpty || deviceId.length > 100) {
      throw ApiError(400, 'invalid_request');
    }
    return db.tx((s) async {
      final rows = await db.q(s, '''
        SELECT id, company_id, user_global_id, expires_at, used_at FROM pairing_codes
        WHERE code_hash=@h AND kind='admin' FOR UPDATE''', {'h': sha256Hex(normalized)});
      if (rows.isEmpty) throw ApiError(401, 'invalid_code');
      final pc = rows.first.toColumnMap();
      if (pc['used_at'] != null || (pc['expires_at'] as int) < _now) throw ApiError(401, 'code_expired');
      await db.q(s, 'UPDATE pairing_codes SET used_at=@n WHERE id=@id', {'n': _now, 'id': pc['id']});
      final companyId = pc['company_id'] as int;
      final ur = await db.q(s, 'SELECT * FROM admin_users WHERE company_id=@c AND global_id=@g',
          {'c': companyId, 'g': pc['user_global_id']});
      if (ur.isEmpty) throw ApiError(401, 'invalid_code');
      final user = AdminUser(ur.first.toColumnMap());
      if (!user.canUseApp) throw ApiError(403, 'mobile_access_denied');
      final existing = await db.q(s, 'SELECT company_id FROM admin_devices WHERE device_id=@d', {'d': deviceId});
      if (existing.isNotEmpty && existing.first[0] != companyId) {
        throw ApiError(409, 'device_belongs_to_other_company');
      }
      final token = randomToken();
      await db.q(s, '''
        INSERT INTO admin_devices (company_id, device_id, name, user_id, token_hash, paired_at, last_seen_ip,
          token_rotated_at, app_version, platform)
        VALUES (@c, @d, @nm, @u, @h, @n, @ip, @n, @av, 'android')
        ON CONFLICT (device_id) DO UPDATE SET name=EXCLUDED.name, user_id=EXCLUDED.user_id,
          token_hash=EXCLUDED.token_hash, previous_token_hash=NULL, paired_at=EXCLUDED.paired_at,
          revoked_at=NULL, last_seen_ip=EXCLUDED.last_seen_ip, token_rotated_at=EXCLUDED.token_rotated_at,
          app_version=EXCLUDED.app_version''', {
        'c': companyId,
        'd': deviceId,
        'nm': deviceName,
        'u': user.id,
        'h': sha256Hex(token),
        'n': _now,
        'ip': ip,
        'av': appVersion,
      });
      await db.q(s, "INSERT INTO audit_log (company_id, action, entity, ip, detail, at) "
          "VALUES (@c, 'admin_device_paired', 'admin_device', @ip, @d, @n)",
          {'c': companyId, 'ip': ip, 'd': deviceId, 'n': _now});
      final company = (await db.q(s, 'SELECT name, currency, decimal_places FROM companies WHERE id=@c',
              {'c': companyId}))
          .first;
      return {
        'deviceToken': token,
        'deviceId': deviceId,
        'user': {'globalId': user.globalId, 'username': user.username, 'displayName': user.displayName},
        'company': {'name': company[0], 'currency': company[1], 'decimals': company[2]},
        'desktopSigningKey': await _signingKey(companyId, s),
      };
    });
  }

  Future<void> logout(AdminContext a) => _audit(a.companyId, 'admin_logout', a.ip, a.deviceId);

  Future<void> unpairDevice(AdminContext a) async {
    final rows = await db.query('''
      UPDATE admin_devices SET revoked_at=@n, previous_token_hash=NULL
      WHERE id=@id AND revoked_at IS NULL RETURNING id''', {'n': _now, 'id': a.devicePk});
    if (rows.isNotEmpty) await _audit(a.companyId, 'admin_device_unpaired', a.ip, a.deviceId);
  }

  Future<AdminContext> authenticateDevice(String? bearer, String? deviceId,
      {String ip = 'unknown', bool allowRevoked = false}) async {
    if (bearer == null || bearer.isEmpty || deviceId == null || deviceId.isEmpty) {
      throw ApiError(401, 'missing_device_token');
    }
    final rows = await db.query('''
        SELECT id, company_id, user_id, token_hash, revoked_at FROM admin_devices WHERE device_id=@d''',
        {'d': deviceId});
    if (rows.isEmpty) throw ApiError(401, 'unknown_device');
    final r = rows.first.toColumnMap();
    if (!constantTimeEquals(r['token_hash'] as String, sha256Hex(bearer))) {
      throw ApiError(401, 'invalid_device_token');
    }
    if (r['revoked_at'] != null && !allowRevoked) throw ApiError(401, 'device_revoked');
    if (r['revoked_at'] == null) {
      await db.query('UPDATE admin_devices SET last_seen_at=@n, last_seen_ip=@ip WHERE id=@id',
          {'n': _now, 'ip': ip, 'id': r['id']});
    }
    return AdminContext(
      devicePk: r['id'] as int,
      deviceId: deviceId,
      companyId: r['company_id'] as int,
      userId: r['user_id'] as int,
      ip: ip,
    );
  }

  /// Mobile-password login of the user bound to the device. Rate-limited per
  /// device (10/10 min) and locked per user after [lockoutAfter] failures for
  /// [lockoutFor] (same policy as the desktop `LoginRateLimiter`).
  Future<Map<String, Object?>> login(AdminContext a, String username, String password) async {
    _loginLimiter.hit(a.deviceId, code: 'too_many_attempts');
    final user = await _user(a.userId);
    if (user == null || !user.canUseApp) throw ApiError(403, 'mobile_access_denied');
    final locked = user.row['locked_until'] as int?;
    if (locked != null && locked > _now) {
      throw ApiError(429, 'user_locked', null, ((locked - _now) / 1000).ceil());
    }
    final hash = user.row['password_hash'] as String?;
    final ok = username.trim().toLowerCase() == user.username.toLowerCase() &&
        hash != null &&
        verifyPin(password, hash);
    if (!ok) {
      final fails = (user.row['failed_logins'] as int) + 1;
      await db.query('UPDATE admin_users SET failed_logins=@f, locked_until=@l WHERE id=@id', {
        'f': fails >= lockoutAfter ? 0 : fails,
        'l': fails >= lockoutAfter ? _now + lockoutFor.inMilliseconds : null,
        'id': user.id,
      });
      await _audit(a.companyId, 'admin_login_failed', a.ip, a.deviceId);
      throw ApiError(401, 'invalid_credentials');
    }
    await db.query('UPDATE admin_users SET failed_logins=0, locked_until=NULL WHERE id=@id', {'id': user.id});
    await _audit(a.companyId, 'admin_login', a.ip, a.deviceId);
    final token = sessions.issue(employeeId: user.id, devicePk: a.devicePk, companyId: a.companyId);
    final claims = sessions.verify(token)!;
    return {
      'sessionToken': token,
      'expiresAt': DateTime.fromMillisecondsSinceEpoch(claims['exp'] as int, isUtc: true).toIso8601String(),
      'user': user.toJson(),
    };
  }

  /// Verifies the session token and re-reads the user, so a user disabled on
  /// the desktop loses access at the next users push even with a live token.
  Future<AdminUser> requireSession(AdminContext a, String? token) async {
    final claims = token == null ? null : sessions.verify(token);
    if (claims == null) throw ApiError(401, 'invalid_session');
    if (claims['did'] != a.devicePk || claims['uid'] != a.userId || claims['cid'] != a.companyId) {
      throw ApiError(401, 'session_device_mismatch');
    }
    final user = await _user(a.userId);
    if (user == null || !user.canUseApp) throw ApiError(403, 'mobile_access_denied');
    return user;
  }

  Future<Map<String, Object?>> snapshots(AdminContext a, AdminUser u, {List<String>? kinds, int? branch}) async {
    final rows = await db.query('''
      SELECT DISTINCT ON (kind, scope) kind, scope, as_of, payload, signature
      FROM snapshots WHERE company_id=@c
      ORDER BY kind, scope, as_of DESC''', {'c': a.companyId});
    final items = <Map<String, Object?>>[];
    for (final r in rows) {
      final kind = r[0] as String, scope = r[1] as String;
      if (kinds != null && !kinds.contains(kind)) continue;
      if (branch != null && scope != 'branch:$branch') continue;
      if (!canRead(u, kind, scope)) continue;
      items.add({
        'kind': kind,
        'scope': scope,
        'asOf': DateTime.fromMillisecondsSinceEpoch(r[2] as int, isUtc: true).toIso8601String(),
        'payload': jsonDecode(r[3] as String),
        'signature': r[4],
      });
    }
    final seen = await db.query(
        'SELECT MAX(last_seen_at) FROM desktop_links WHERE company_id=@c AND revoked_at IS NULL',
        {'c': a.companyId});
    return {
      'desktop': {'lastSeenAt': seen.first[0]},
      'serverTime': _now,
      'items': items,
    };
  }

  // ───────────────────────────── helpers ─────────────────────────────

  Future<String?> _signingKey(int companyId, [Session? session]) async {
    const sql = 'SELECT signing_public_key FROM desktop_links WHERE company_id=@c AND revoked_at IS NULL '
        'AND signing_public_key IS NOT NULL ORDER BY signing_key_set_at DESC LIMIT 1';
    final r = session == null ? await db.query(sql, {'c': companyId}) : await db.q(session, sql, {'c': companyId});
    return r.isEmpty ? null : r.first[0] as String?;
  }

  Future<AdminUser?> _userByGid(int companyId, String gid) async {
    final r = await db.query('SELECT * FROM admin_users WHERE company_id=@c AND global_id=@g', {'c': companyId, 'g': gid});
    return r.isEmpty ? null : AdminUser(r.first.toColumnMap());
  }

  Future<AdminUser?> _user(int id) async {
    final r = await db.query('SELECT * FROM admin_users WHERE id=@id', {'id': id});
    return r.isEmpty ? null : AdminUser(r.first.toColumnMap());
  }
}
