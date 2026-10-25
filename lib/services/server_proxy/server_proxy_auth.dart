// ServerProxy - signed session minting with a classified answer, direct
// verification through the main system, online-only password change and the
// token-bearing credential feed (plan 2026-10-24, P2 / B.6.1 + B.6.3 + B.7.2).
part of '../server_proxy.dart';

/// What the main system answered when a device asked for a user session.
enum SessionMintOutcome {
  ok,
  invalidCredential,
  passwordChangeRequired,
  branchDenied,
  mirrorDenied,
  lockedOut,
  deviceRevoked,

  /// 403 "Invalid API token" / legacy window over / `device_scope`, or the host
  /// was re-initialised (session key id changed): the answer is NOT about this
  /// user, so the offline policy decides.
  deviceUnpaired,

  /// Timeout, no network, 5xx, 404 (older host).
  unreachable,
}

class SessionMintResult {
  const SessionMintResult(this.outcome,
      {this.token, this.userId, this.statusCode, this.serverTime});
  final SessionMintOutcome outcome;
  final String? token;
  final int? userId;
  final int? statusCode;
  final DateTime? serverTime;

  bool get ok => outcome == SessionMintOutcome.ok;

  /// The main system gave a binding "no" about THIS user.
  bool get isUserDenial =>
      outcome == SessionMintOutcome.invalidCredential ||
      outcome == SessionMintOutcome.branchDenied ||
      outcome == SessionMintOutcome.mirrorDenied;
}

/// Pure classifier of `POST /api/auth/session` answers (unit-testable).
SessionMintOutcome classifySessionAnswer(int status, Map<String, dynamic> body) {
  final code = '${body['code'] ?? ''}';
  final error = '${body['error'] ?? ''}';
  if (status >= 200 && status < 300) {
    final t = body['token'];
    return t is String && t.isNotEmpty
        ? SessionMintOutcome.ok
        : SessionMintOutcome.unreachable;
  }
  if (status == 401) {
    if (code == 'device_revoked' || error == 'device_revoked') {
      return SessionMintOutcome.deviceRevoked;
    }
    if (code == 'invalid_credentials' || error == 'Invalid credentials') {
      return SessionMintOutcome.invalidCredential;
    }
    return SessionMintOutcome.deviceUnpaired;
  }
  if (status == 403) {
    switch (code) {
      case 'password_change_required':
        return SessionMintOutcome.passwordChangeRequired;
      case 'branch_access_denied':
        return SessionMintOutcome.branchDenied;
      case 'mirror_console_denied':
        return SessionMintOutcome.mirrorDenied;
    }
    return SessionMintOutcome.deviceUnpaired;
  }
  if (status == 429) return SessionMintOutcome.lockedOut;
  return SessionMintOutcome.unreachable;
}

enum PasswordChangeOutcome {
  ok,
  invalidCredential,

  /// 400/409 policy answers: [PasswordChangeResult.code] names the rule.
  rejected,
  branchDenied,
  mirrorDenied,
  lockedOut,

  /// 404: the host predates `POST /api/auth/change-password`.
  hostTooOld,
  unreachable,
}

class PasswordChangeResult {
  const PasswordChangeResult(this.outcome,
      {this.code, this.token, this.userId, this.passwordHash, this.serverTime});
  final PasswordChangeOutcome outcome;
  final String? code;
  final String? token;
  final int? userId;
  final String? passwordHash;
  final DateTime? serverTime;
  bool get ok => outcome == PasswordChangeOutcome.ok;
}

/// The signing-key id the main last announced to us (in memory). A 401 is only
/// binding when it comes from the same host: a re-initialised host (new key)
/// can answer "unknown user" for everyone - that must not lock the cashiers out.
String? _knownSessionKeyId;

/// Test hook: forget the remembered host identity.
@visibleForTesting
void debugResetKnownSessionKeyId() => _knownSessionKeyId = null;

extension ServerProxyAuth on ServerProxy {
  Map<String, dynamic> _decodeObject(String body) {
    try {
      final d = json.decode(body);
      return d is Map<String, dynamic> ? d : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  DateTime? _serverTimeOf(Object? ms) =>
      ms is num ? DateTime.fromMillisecondsSinceEpoch(ms.toInt(), isUtc: true) : null;

  Future<String?> _hostSessionKeyId() async {
    try {
      final r = await TlsTrust.httpClient()
          .get(Uri.parse('$_baseUrl/api/health'), headers: _authHeaders)
          .timeout(ServerProxy.requestTimeout);
      final id = _decodeObject(r.body)['sessionKeyId'];
      return id is String && id.isNotEmpty ? id : null;
    } catch (_) {
      return null;
    }
  }

  /// POST the proof to `/api/auth/session` and classify the answer. Never
  /// throws. Does not touch any cache.
  Future<SessionMintResult> _postSession(Map<String, dynamic> body) async {
    try {
      final r = await TlsTrust.httpClient()
          .post(Uri.parse('$_baseUrl/api/auth/session'),
              headers: _authHeaders, body: json.encode(body))
          .timeout(ServerProxy.requestTimeout);
      final data = _decodeObject(r.body);
      var outcome = classifySessionAnswer(r.statusCode, data);
      if (outcome == SessionMintOutcome.invalidCredential &&
          _knownSessionKeyId != null) {
        final now = await _hostSessionKeyId();
        if (now != null && now != _knownSessionKeyId) {
          outcome = SessionMintOutcome.deviceUnpaired; // another host answered
        }
      }
      if (outcome == SessionMintOutcome.ok && _knownSessionKeyId == null) {
        _knownSessionKeyId = await _hostSessionKeyId();
      }
      return SessionMintResult(
        outcome,
        token: data['token'] as String?,
        userId: (data['userId'] as num?)?.toInt(),
        statusCode: r.statusCode,
      );
    } catch (e) {
      debugPrint('[ServerProxy] session request failed: $e');
      return const SessionMintResult(SessionMintOutcome.unreachable);
    }
  }

  Map<String, dynamic>? _proofBody(String? username, String? password, String? cardCode) {
    if (cardCode != null && cardCode.isNotEmpty) return {'cardCode': cardCode};
    if (username != null &&
        username.isNotEmpty &&
        password != null &&
        password.isNotEmpty) {
      return {'username': username, 'password': password};
    }
    return null;
  }

  /// POST the remembered proof for [userId] and cache the opaque token. A failed
  /// mint leaves any previously cached token untouched. Never logs the token or
  /// the credential.
  Future<SessionMintResult> _mintSession(int userId) async {
    final proof = _sessionProofs[userId];
    final body = proof == null
        ? null
        : _proofBody(proof.username, proof.password, proof.cardCode);
    if (body == null) return const SessionMintResult(SessionMintOutcome.unreachable);
    final res = await _postSession(body);
    if (res.ok) {
      _sessionTokens[userId] = res.token!;
      _sessionMintedAt[userId] = DateTime.now();
      debugPrint('[ServerProxy] session token acquired for uid=$userId');
    } else {
      debugPrint('[ServerProxy] session token NOT acquired for uid=$userId '
          '(${res.outcome.name} HTTP ${res.statusCode})');
    }
    return res;
  }

  /// Verify a credential on the main WITHOUT remembering the proof or caching
  /// the token (used for a user this device has never seen, B.6.3).
  Future<SessionMintResult> mintDirect(
      {String? username, String? password, String? cardCode}) async {
    final body = _proofBody(username, password, cardCode);
    if (body == null) return const SessionMintResult(SessionMintOutcome.unreachable);
    return _postSession(body);
  }

  /// GET [path] bearing an explicit session [token] (no signed-in user yet).
  /// Returns the decoded object, or `null` on any failure.
  Future<Map<String, dynamic>?> fetchFeedWithToken(String path, String token) async {
    try {
      final r = await TlsTrust.httpClient()
          .get(Uri.parse('$_baseUrl$path'),
              headers: {..._authHeaders, 'X-Session-Token': token})
          .timeout(ServerProxy.requestTimeout);
      if (r.statusCode < 200 || r.statusCode >= 300) return null;
      return _decodeObject(r.body);
    } catch (_) {
      return null;
    }
  }

  /// `POST /api/auth/change-password` - ONLINE ONLY, never queued (the plaintext
  /// password must not reach the disk). On success the minted session is cached
  /// for the returned user and the new proof is remembered in memory.
  Future<PasswordChangeResult> changeOwnPassword({
    String? username,
    String? currentPassword,
    String? cardCode,
    required String newPassword,
  }) async {
    final body = <String, dynamic>{
      if (cardCode != null && cardCode.isNotEmpty)
        'cardCode': cardCode
      else ...{'username': username, 'currentPassword': currentPassword},
      'newPassword': newPassword,
    };
    try {
      final r = await TlsTrust.httpClient()
          .post(Uri.parse('$_baseUrl/api/auth/change-password'),
              headers: _authHeaders, body: json.encode(body))
          .timeout(ServerProxy.requestTimeout);
      final data = _decodeObject(r.body);
      final code = data['code'] as String?;
      switch (r.statusCode) {
        case 200:
          final uid = (data['userId'] as num?)?.toInt();
          final token = data['token'] as String?;
          if (uid == null || token == null) {
            return const PasswordChangeResult(PasswordChangeOutcome.unreachable);
          }
          _sessionTokens[uid] = token;
          _sessionMintedAt[uid] = DateTime.now();
          if (username != null && username.isNotEmpty) {
            _sessionProofs[uid] =
                _SessionProof(username: username, password: newPassword);
          }
          return PasswordChangeResult(PasswordChangeOutcome.ok,
              token: token,
              userId: uid,
              passwordHash: data['passwordHash'] as String?,
              serverTime: _serverTimeOf(data['serverTime']));
        case 401:
          return const PasswordChangeResult(PasswordChangeOutcome.invalidCredential);
        case 403:
          if (code == 'branch_access_denied') {
            return const PasswordChangeResult(PasswordChangeOutcome.branchDenied);
          }
          if (code == 'mirror_console_denied') {
            return const PasswordChangeResult(PasswordChangeOutcome.mirrorDenied);
          }
          return PasswordChangeResult(PasswordChangeOutcome.rejected, code: code);
        case 400:
        case 409:
          return PasswordChangeResult(PasswordChangeOutcome.rejected, code: code);
        case 404:
          return const PasswordChangeResult(PasswordChangeOutcome.hostTooOld);
        case 429:
          return const PasswordChangeResult(PasswordChangeOutcome.lockedOut);
        default:
          return const PasswordChangeResult(PasswordChangeOutcome.unreachable);
      }
    } catch (e) {
      debugPrint('[ServerProxy] changeOwnPassword failed: $e');
      return const PasswordChangeResult(PasswordChangeOutcome.unreachable);
    }
  }
}
