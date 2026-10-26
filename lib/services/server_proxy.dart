import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'tls_trust.dart';
import 'api/client_schema_gate.dart';
import '../web/web_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:picpos_erp/data/database/sync_interceptor.dart';
import '../core/logging/diagnostic_logger.dart';
import 'network_service.dart';
import 'device_identity_service.dart';
import 'legacy_identifiers.dart';
import 'storage_key_migration.dart';
import '../core/config/brand.dart';
import '../domain/models/voucher_book.dart';
import 'approval/approval_proof_carrier.dart';
import 'mirror_branch_context.dart';

part 'server_proxy/server_proxy_console.dart';
part 'server_proxy/server_proxy_wh_desk.dart';
part 'server_proxy/server_proxy_trading.dart';
part 'server_proxy/server_proxy_cash.dart';
part 'server_proxy/server_proxy_master_data.dart';
part 'server_proxy/server_proxy_admin.dart';
part 'server_proxy/server_proxy_auth.dart';
part 'server_proxy/server_proxy_reads.dart';

/// Centralized proxy for all write operations in client mode.
/// When the app is in client mode, all writes go through this proxy
/// to the server's API instead of writing to the local DB.
class ServerProxy {
  ServerProxy._();
  static final ServerProxy instance = ServerProxy._();

  /// Per-request HTTP timeout for write calls (fast-fail -> outbox). Production
  /// default is 8 s; tests on slow runners may raise it (injectable, not a setting).
  static Duration requestTimeout = const Duration(seconds: 8);

  /// PHASE-12 (S4): Secure storage for API token
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'picpos_api_token';

  /// Secure-storage view with the old-name → new-name migration
  /// (`StorageKeyMigration`): reads fall back to the old key and copy it,
  /// writes/deletes cover both names so a stale token can't resurrect.
  static const _tokenStore = FlutterSecureSecretStore(_storage);
  static String get _oldTokenKey => LegacyIdentifiers.apiTokenStorageKey;

  /// API authentication token (received from health check handshake)
  String? _apiToken;

  /// Public getter for the API token
  String? get apiToken => _apiToken;

  /// Set the API token after successful health check handshake
  /// PHASE-12: Also persists to secure storage AND SharedPreferences so the
  /// two restore paths (here and NetworkService.init) stay in sync.
  void setApiToken(String? token) {
    _apiToken = token;
    if (token != null && token.isNotEmpty) {
      unawaited(StorageKeyMigration.write(
        _tokenStore,
        newKey: _tokenKey,
        oldKey: _oldTokenKey,
        value: token,
      ).catchError((Object _) {}));
      // Mirror to SharedPreferences with the key NetworkService also writes
      // to. Without this mirror, a token saved by setApiToken() would never
      // appear in prefs, so NetworkService.init() couldn't restore it on the
      // next boot — the client would show
      //   ❌ fetchUsers returned null — token missing or server down
      // until the user manually triggered a /api/health handshake.
      unawaited(_writeTokenToPrefs(token));
    } else {
      unawaited(StorageKeyMigration.delete(
        _tokenStore,
        newKey: _tokenKey,
        oldKey: _oldTokenKey,
      ).catchError((Object _) {}));
      unawaited(_clearTokenFromPrefs());
    }
  }

  Future<void> _writeTokenToPrefs(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('network_api_token', token);
    } catch (_) {}
  }

  Future<void> _clearTokenFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('network_api_token');
    } catch (_) {}
  }

  /// PHASE-12: Restore token from secure storage on app startup.
  /// Falls back to SharedPreferences (the key NetworkService writes after
  /// /api/health) when secure storage is empty — covers the case where the
  /// secure-storage entry was wiped by an OS update or by switching user
  /// profiles, but the prefs copy is still intact.
  Future<void> restoreToken() async {
    if (_apiToken != null && _apiToken!.isNotEmpty) return;
    try {
      _apiToken = await StorageKeyMigration.read(
        _tokenStore,
        newKey: _tokenKey,
        oldKey: _oldTokenKey,
      );
    } catch (_) {}
    if (_apiToken == null || _apiToken!.isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final fromPrefs = prefs.getString('network_api_token');
        if (fromPrefs != null && fromPrefs.isNotEmpty) {
          _apiToken = fromPrefs;
          // Mirror back into secure storage so both paths converge.
          unawaited(StorageKeyMigration.write(
            _tokenStore,
            newKey: _tokenKey,
            oldKey: _oldTokenKey,
            value: fromPrefs,
          ).catchError((Object _) {}));
        }
      } catch (_) {}
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Spec 151 (P1-8) — signed per-user session tokens
  // ═══════════════════════════════════════════════════════════════
  //
  // Replaces the forgeable, client-asserted `X-User-Id` header. On a
  // successful LOCAL login the client presents the SAME credential to
  // `POST /api/auth/session`; the server re-verifies it against its own
  // (serverWins-synced) user table and mints an opaque, HMAC-signed token
  // the client echoes back in `X-Session-Token`. The server derives the
  // acting userId from that token, so a holder of the shared bearer token
  // can no longer assert an arbitrary uid.
  //
  // Both the tokens AND the credential proofs live IN MEMORY ONLY — they are
  // NEVER written to secure storage, SharedPreferences, or logs. Persisting a
  // credential/identity at rest is exactly the weakness this fix removes.
  // Everything here is dropped on logout via [clearSessions].

  /// uid → opaque, server-issued session token. The client never parses it,
  /// it only stores and echoes it in `X-Session-Token`.
  final Map<int, String> _sessionTokens = {};

  /// uid → in-memory credential proof, so a token can be re-minted on
  /// reconnect / after expiry (see [ensureSession]) without re-prompting.
  final Map<int, _SessionProof> _sessionProofs = {};

  /// uid → when its cached token was minted. Drives PROACTIVE refresh: a
  /// branch-scoped GET fails CLOSED (empty, not 401) when the token expires, so
  /// nothing on the read path would otherwise trigger a re-mint. Re-minting
  /// well inside the server TTL keeps a long-lived session (e.g. an always-on
  /// mirror console) from silently going blind at day 30.
  final Map<int, DateTime> _sessionMintedAt = {};

  /// Re-mint a cached token once it is older than this (well under the server's
  /// 30-day TTL). Checked on every [ensureSession] (the 5-min reconnect cycle).
  static const Duration _sessionRefreshAfter = Duration(hours: 12);

  /// Get auth headers including API token.
  ///
  /// Spec 151 (P1-8): stamp `X-Session-Token` for the signed-in user (from
  /// [SyncInterceptor.currentUserId]) so the server can derive the acting
  /// userId from an UNFORGEABLE token instead of the old, client-asserted
  /// `X-User-Id` header (which the server no longer trusts). The token is only
  /// present once [acquireSession] has run for that user; pre-login flows
  /// (health handshake, mirror verifyAdmin) and offline logins that haven't
  /// minted a token yet simply omit the header. The `/api/auth/session`
  /// endpoint itself only needs the shared bearer, so a missing/other-user
  /// session token here is harmless for that call.
  Map<String, String> get _authHeaders {
    final userId = SyncInterceptor.currentUserId;
    final deviceId = DeviceIdentityService.instance.tryGetDeviceId();
    final sessionToken = userId != null ? _sessionTokens[userId] : null;
    return {
      'Content-Type': 'application/json',
      // الويب: لا bearer للجهاز أبداً — الهوية رمز الجلسة وحده.
      if (_apiToken != null && WebSession.activeWebClient == null)
        'Authorization': 'Bearer $_apiToken',
      if (deviceId != null && deviceId.isNotEmpty) 'X-Device-Id': deviceId,
      'X-Session-Token': ?sessionToken,
      ..._consoleHeaders(), // M2 X-Branch-Id (mirror) + P5 X-Approval-Proof
      if (ClientSchemaGate.clientSchemaVersion != null) // SYNC-001
        'X-Client-Schema': '${ClientSchemaGate.clientSchemaVersion}',
    };
  }

  /// Whether the app is in client mode
  static bool get isClientMode => NetworkService.instance.isClient;

  /// م3-7: على الويب العنوان من جلسة الويب (نفس أصل الصفحة افتراضياً).
  String get _baseUrl =>
      WebSession.activeWebClient?.baseUrl ??
      NetworkService.instance.buildServerUrl();

  /// م3-7: يسجّل رمز جلسة الويب (`aud:'web'`) للمستخدم [userId] ليُرسَل في
  /// `X-Session-Token` على كل نداء. في الذاكرة فقط (كباقي الرموز).
  void setSessionToken(int userId, String token) {
    _sessionTokens[userId] = token;
    _sessionMintedAt[userId] = DateTime.now();
  }

  // ═══════════════════════════════════════════════════════════════
  // FIX 3.3: Status Code Classification
  // ═══════════════════════════════════════════════════════════════

  /// Accepts 200 OK, 201 Created, 202 Accepted, 204 No Content.
  bool _isSuccessStatusCode(int statusCode) =>
      statusCode >= 200 && statusCode < 300;

  // ═══════════════════════════════════════════════════════════════
  // Generic HTTP methods
  // ═══════════════════════════════════════════════════════════════

  // ═══════════════════════════════════════════════════════════════
  // PHASE-3 FIX: Retry with Exponential Backoff
  // ═══════════════════════════════════════════════════════════════

  /// Performs a POST with exponential backoff retry.
  /// Retries up to [maxAttempts] times on network errors or 5xx server errors.
  /// Idempotency-Key header ensures server deduplication on retries.
  Future<Map<String, dynamic>> _postWithRetry(
    String endpoint,
    Map<String, dynamic> data, {
    String? idempotencyKey,
    int maxAttempts = 3,
  }) async {
    final url = Uri.parse('$_baseUrl$endpoint');
    final headers = Map<String, String>.from(_authHeaders);
    if (idempotencyKey != null) {
      headers['X-Idempotency-Key'] = idempotencyKey;
    }
    final body = _encodeBody(headers, data);
    final rng = Random();

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        debugPrint('[ServerProxy] POST $endpoint (attempt $attempt/$maxAttempts)');
        final response = await TlsTrust.httpClient()
            .post(url, headers: headers, body: body)
            .timeout(ServerProxy.requestTimeout); // Fast-fail → outbox on slow network

        // PHASE-3 FIX: Accept any 2xx status (200 OK, 201 Created, 204 No Content)
        if (response.statusCode >= 200 && response.statusCode < 300) {
          if (response.body.isEmpty) return {};
          return json.decode(response.body) as Map<String, dynamic>;
        }

        // 4xx = client error: do NOT retry
        if (response.statusCode >= 400 && response.statusCode < 500) {
          throw Exception('Server error (${response.statusCode}): ${response.body}');
        }

        // 5xx = server error: retry
        if (attempt == maxAttempts) {
          throw Exception('Server error after $maxAttempts attempts (${response.statusCode}): ${response.body}');
        }

      } on TimeoutException {
        if (attempt == maxAttempts) rethrow;
      } on http.ClientException {
        if (attempt == maxAttempts) rethrow;
      }

      // Exponential backoff with jitter: 1s, 2s, 4s (capped at 8s)
      final delay = Duration(
        milliseconds: (pow(2, attempt - 1) * 1000 + rng.nextInt(500)).round(),
      );
      debugPrint('[ServerProxy] Retry in ${delay.inMilliseconds}ms...');
      await Future.delayed(delay);
    }
    throw Exception('POST $endpoint failed after $maxAttempts attempts');
  }

  Future<Map<String, dynamic>> post(
    String endpoint,
    Map<String, dynamic> data, {
    String? idempotencyKey,
  }) async {
    final url = Uri.parse('$_baseUrl$endpoint');
    debugPrint('[ServerProxy] POST $endpoint');
    
    final headers = Map<String, String>.from(_authHeaders);
    if (idempotencyKey != null) {
      headers['X-Idempotency-Key'] = idempotencyKey;
    }
    
    final response = await TlsTrust.httpClient()
        .post(
          url,
          headers: headers,
          body: _encodeBody(headers, data),
        )
        .timeout(ServerProxy.requestTimeout); // Fast-fail → outbox on slow network

    // FIX 3.3: Use named helper — accepts 200, 201, 202, 204
    if (_isSuccessStatusCode(response.statusCode)) {
      if (response.body.isEmpty) return {};
      return json.decode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Server error (${response.statusCode}): ${response.body}');
  }
  Future<Map<String, dynamic>> put(
    String endpoint,
    Map<String, dynamic> data, {
    String? idempotencyKey,
  }) async {
    final url = Uri.parse('$_baseUrl$endpoint');
    debugPrint('[ServerProxy] PUT $endpoint');
    
    final headers = Map<String, String>.from(_authHeaders);
    if (idempotencyKey != null) {
      headers['X-Idempotency-Key'] = idempotencyKey;
    }
    
    final response = await TlsTrust.httpClient()
        .put(
          url,
          headers: headers,
          body: _encodeBody(headers, data),
        )
        .timeout(ServerProxy.requestTimeout);

    // FIX 3.3: Use named helper — accepts 200, 201, 202, 204
    if (_isSuccessStatusCode(response.statusCode)) {
      if (response.body.isEmpty) return {};
      return json.decode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Server error (${response.statusCode}): ${response.body}');
  }

  Future<Map<String, dynamic>> delete(String endpoint, {String? idempotencyKey}) async {
    final url = Uri.parse('$_baseUrl$endpoint');
    debugPrint('[ServerProxy] DELETE $endpoint');
    
    final headers = Map<String, String>.from(_authHeaders);
    if (idempotencyKey != null) {
      headers['X-Idempotency-Key'] = idempotencyKey;
    }
    
    final response = await TlsTrust.httpClient()
        .delete(url, headers: headers)
        .timeout(ServerProxy.requestTimeout);

    // FIX 3.3: Use named helper
    if (_isSuccessStatusCode(response.statusCode)) {
      if (response.body.isEmpty) return {};
      return json.decode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Server error (${response.statusCode}): ${response.body}');
  }

  // ═══════════════════════════════════════════════════════════════
  // FIX 3.5: General requestWithRetry (covers GET, and any retryable op)
  // ═══════════════════════════════════════════════════════════════

  /// Retries [operation] with exponential backoff on transient failures.
  ///
  /// Retryable by default: SocketException, TimeoutException, and
  /// HTTP 408/429/500/502/503/504. Non-retryable 4xx errors are
  /// re-thrown immediately on first occurrence.
  ///
  /// [initialDelayMs] is the base delay; each retry doubles it (with
  /// random jitter up to 200ms to avoid thundering herd).
  Future<T> requestWithRetry<T>({
    required Future<T> Function() operation,
    required String operationName,
    int maxRetries = 3,
    int initialDelayMs = 100,
    Set<int> retryableStatusCodes = const {408, 429, 500, 502, 503, 504},
  }) async {
    var delayMs = initialDelayMs;
    final rng = Random();

    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        return await operation();
      } on TimeoutException catch (e) {
        if (attempt == maxRetries) {
          debugPrint('[$operationName] Timeout after $maxRetries attempts: $e');
          rethrow;
        }
        debugPrint('[$operationName] Timeout on attempt $attempt, retrying in ${delayMs}ms');
      } on Exception catch (e) {
        final msg = e.toString();
        final isNetwork = msg.contains('SocketException') ||
            msg.contains('Connection refused') ||
            msg.contains('Connection reset') ||
            msg.contains('HandshakeException');

        if (isNetwork) {
          if (attempt == maxRetries) {
            debugPrint('[$operationName] Network error after $maxRetries attempts: $e');
            // Phase 1 diagnostics: a write that never reached the server after
            // all retries — the classic "invoice stuck locally" field case.
            await DiagnosticLogger.logError(DiagnosticLogger.syncPush,
                '$operationName (unreachable after $maxRetries retries)', e);
            rethrow;
          }
          debugPrint('[$operationName] Network error on attempt $attempt, retrying in ${delayMs}ms');
        } else {
          // Check if the status code is retryable
          final statusMatch = RegExp(r'\((\d{3})\)').firstMatch(msg);
          final statusCode = int.tryParse(statusMatch?.group(1) ?? '');
          if (statusCode != null && retryableStatusCodes.contains(statusCode) && attempt < maxRetries) {
            debugPrint('[$operationName] Status $statusCode on attempt $attempt, retrying in ${delayMs}ms');
          } else {
            // Non-retryable (4xx client error, or max retries on 5xx)
            // Phase 1 diagnostics: the server actively rejected the write.
            await DiagnosticLogger.logError(DiagnosticLogger.syncPush,
                '$operationName (server rejected)', e);
            rethrow;
          }
        }
      }

      // Exponential backoff with jitter
      final jitter = rng.nextInt(200);
      await Future.delayed(Duration(milliseconds: delayMs + jitter));
      delayMs *= 2;
    }
    throw Exception('[$operationName] failed after $maxRetries attempts (unreachable)');
  }

  /// The [VoucherBookException] a `409` body carries, else `null`.
  static VoucherBookException? voucherBookRejectionOf(Object error) {
    final text = '$error';
    final start = text.indexOf('{');
    if (!text.contains('voucherBookKey') || start < 0) return null;
    try {
      final body = json.decode(text.substring(start)) as Map<String, dynamic>;
      return VoucherBookException(body['voucherBookKey'] as String, {
        ...?(body['voucherBookParams'] as Map?)?.cast<String, Object?>(),
      });
    } catch (_) {
      return null;
    }
  }
  // ═══════════════════════════════════════════════════════════════
  // Spec 151 (P1-8) — session-token acquisition / refresh / teardown
  // ═══════════════════════════════════════════════════════════════

  /// Obtain a signed per-user session token from the server.
  ///
  /// Called at the credential choke point ([AuthRepositoryImpl.authenticate*])
  /// right after a SUCCESSFUL local login, while the plaintext credential is
  /// still in scope. Only acts in client/mirror mode — gated on
  /// [SyncInterceptor.isClientMode] (true for client OR mirror, per R9), NOT
  /// the narrower `NetworkService.isClient` (false on a mirror).
  ///
  /// The credential proof is remembered IN MEMORY so [ensureSession] can
  /// re-mint the token after a reconnect / expiry without prompting the user
  /// again. Pass EITHER `username`+`password` OR `cardCode`.
  ///
  /// Never throws into the login flow: all failures are swallowed and just
  /// leave the token unset, so the next login / reconnect cycle retries. When
  /// the server is unreachable at login (offline-first) no token is minted
  /// here; [ensureSession] fills it in once the server becomes reachable.
  Future<SessionMintResult> acquireSession({
    required int userId,
    String? username,
    String? password,
    String? cardCode,
    // Spec 151 P1-8b — the mirror pairing flow mints an admin token BEFORE
    // `NetworkService.setMode(mirror)` has run (pairing is committer step 2,
    // setMode is step 4), so `isClientMode` is still false at that instant.
    // Pairing is inherently a client/mirror operation, so let that flow
    // bypass the mode gate. Every other caller (login) leaves this false and
    // keeps the original gate. See [MirrorPairingService.pair].
    bool bypassModeGate = false,
  }) async {
    if (!bypassModeGate && !SyncInterceptor.isClientMode) {
      return const SessionMintResult(SessionMintOutcome.unreachable);
    }
    // Remember the proof (in memory only) so a token can be re-minted later.
    _sessionProofs[userId] = _SessionProof(
      username: username,
      password: password,
      cardCode: cardCode,
    );
    return _mintSession(userId);
  }

  /// Reconnect / deferred-issuance hook. For the current signed-in user, if we
  /// hold a credential proof but have no cached session token (e.g. the user
  /// logged in while the server was unreachable, or a prior 401 evicted the
  /// token via [invalidateSessionToken]), mint one now. No-op outside
  /// client/mirror mode, with no logged-in user, with no proof, or when a
  /// token is already cached. Never throws.
  Future<void> ensureSession() async {
    if (!SyncInterceptor.isClientMode) return;
    final userId = SyncInterceptor.currentUserId;
    if (userId == null) return;
    if (_sessionProofs[userId] == null) return; // nothing to re-mint from
    final mintedAt = _sessionMintedAt[userId];
    final stale = mintedAt == null ||
        DateTime.now().difference(mintedAt) > _sessionRefreshAfter;
    // Have a fresh token → nothing to do. Missing OR stale → (re-)mint.
    if (_sessionTokens[userId] != null && !stale) return;
    await _mintSession(userId);
  }

  /// Drop the cached session token for [userId] (defaults to the current
  /// signed-in user) while KEEPING its credential proof, so the next
  /// [ensureSession] re-mints a fresh token. Called from the outbox 401
  /// handler when the server rejects a stale/expired token. In-memory only →
  /// synchronous.
  void invalidateSessionToken([int? userId]) {
    final uid = userId ?? SyncInterceptor.currentUserId;
    if (uid == null) return;
    _sessionTokens.remove(uid);
    _sessionMintedAt.remove(uid);
  }

  /// Drop EVERY cached session token (all users) while KEEPING the credential
  /// proofs, so the next [ensureSession] re-mints. Called when the server's
  /// `sessionKeyId` (from `/api/health`) changes — its signing key rotated, so
  /// all cached tokens are dead and GET reads would otherwise fail closed
  /// (empty, no 401) until the 12h refresh. In-memory only → synchronous.
  void invalidateAllSessionTokens() {
    _sessionTokens.clear();
    _sessionMintedAt.clear();
  }

  /// Clear every cached session token AND credential proof. Called on logout /
  /// user-switch. In-memory only → synchronous.
  void clearSessions() {
    _sessionTokens.clear();
    _sessionProofs.clear();
    _sessionMintedAt.clear();
  }

  /// Spec 151 P1-8b — whether a signed session token is currently cached for
  /// [userId] (defaults to the signed-in [SyncInterceptor.currentUserId]).
  ///
  /// The client sync paths gate their branch-scoped (transactional) pulls on
  /// this: the server fail-closes those endpoints to ZERO rows without an
  /// `X-Session-Token`, so a tokenless client must SKIP them (and must NOT
  /// advance their watermark) until a token exists post-login. Reference /
  /// master tables stay readable tokenless and are pulled regardless. Never
  /// exposes the token value itself.
  bool hasSessionToken([int? userId]) =>
      _sessionTokens[userId ?? SyncInterceptor.currentUserId] != null;

  /// Spec 151 P1-8b — the client's OWN cached session token for the signed-in
  /// user (or null). Used by [SyncService._fetchJson], whose raw `HttpClient`
  /// GET path bypasses [_authHeaders] and therefore needs the token stamped
  /// explicitly. Handing the client its own token back is not a disclosure —
  /// it is the identical value [_authHeaders] already sends on every proxied
  /// request.
  String? sessionTokenForCurrentUser() {
    final uid = SyncInterceptor.currentUserId;
    return uid != null ? _sessionTokens[uid] : null;
  }

}

/// In-memory credential proof used to (re-)mint a signed session token for a
/// single user (Spec 151 / P1-8). Held only for the lifetime of the process,
/// or until logout clears it. NEVER persisted to disk or logs.
class _SessionProof {
  const _SessionProof({this.username, this.password, this.cardCode});
  final String? username;
  final String? password;
  final String? cardCode;
}

/// Outcome of `ServerProxy.verifyAdmin`. Discriminated by [outcome] so the
/// caller (the setup wizard) can react with a precise message instead of
/// parsing exception strings.
class MirrorAdminVerification {
  const MirrorAdminVerification._({
    required this.outcome,
    this.userId,
    this.displayName,
    this.roleName,
    this.errorDetail,
  });

  factory MirrorAdminVerification.success({
    required int userId,
    required String displayName,
    required String roleName,
  }) => MirrorAdminVerification._(
        outcome: MirrorAdminVerificationOutcome.ok,
        userId: userId,
        displayName: displayName,
        roleName: roleName,
      );

  factory MirrorAdminVerification.invalidCredentials() =>
      const MirrorAdminVerification._(
        outcome: MirrorAdminVerificationOutcome.invalidCredentials,
      );

  factory MirrorAdminVerification.notAdmin() =>
      const MirrorAdminVerification._(
        outcome: MirrorAdminVerificationOutcome.notAdmin,
      );

  factory MirrorAdminVerification.failed(String detail) =>
      MirrorAdminVerification._(
        outcome: MirrorAdminVerificationOutcome.error,
        errorDetail: detail,
      );

  final MirrorAdminVerificationOutcome outcome;
  final int? userId;
  final String? displayName;
  final String? roleName;
  final String? errorDetail;

  bool get isSuccess => outcome == MirrorAdminVerificationOutcome.ok;
}

enum MirrorAdminVerificationOutcome { ok, invalidCredentials, notAdmin, error }
