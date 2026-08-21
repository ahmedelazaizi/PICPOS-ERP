import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ural_erp/data/database/sync_interceptor.dart';
import '../core/logging/diagnostic_logger.dart';
import 'network_service.dart';
import '../core/config/brand.dart';

/// Centralized proxy for all write operations in client mode.
/// When the app is in client mode, all writes go through this proxy
/// to the server's API instead of writing to the local DB.
class ServerProxy {
  ServerProxy._();
  static final ServerProxy instance = ServerProxy._();

  /// PHASE-12 (S4): Secure storage for API token
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'ural_api_token';

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
      _storage.write(key: _tokenKey, value: token);
      // Mirror to SharedPreferences with the key NetworkService also writes
      // to. Without this mirror, a token saved by setApiToken() would never
      // appear in prefs, so NetworkService.init() couldn't restore it on the
      // next boot — the client would show
      //   ❌ fetchUsers returned null — token missing or server down
      // until the user manually triggered a /api/health handshake.
      unawaited(_writeTokenToPrefs(token));
    } else {
      _storage.delete(key: _tokenKey);
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
      _apiToken = await _storage.read(key: _tokenKey);
    } catch (_) {}
    if (_apiToken == null || _apiToken!.isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final fromPrefs = prefs.getString('network_api_token');
        if (fromPrefs != null && fromPrefs.isNotEmpty) {
          _apiToken = fromPrefs;
          // Mirror back into secure storage so both paths converge.
          unawaited(_storage.write(key: _tokenKey, value: fromPrefs));
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
    final sessionToken = userId != null ? _sessionTokens[userId] : null;
    return {
      'Content-Type': 'application/json',
      if (_apiToken != null) 'Authorization': 'Bearer $_apiToken',
      'X-Session-Token': ?sessionToken,
    };
  }

  /// Whether the app is in client mode
  static bool get isClientMode => NetworkService.instance.isClient;

  String get _baseUrl => NetworkService.instance.buildServerUrl();

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
    final body = json.encode(data);
    final rng = Random();

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        debugPrint('[ServerProxy] POST $endpoint (attempt $attempt/$maxAttempts)');
        final response = await http
            .post(url, headers: headers, body: body)
            .timeout(const Duration(seconds: 8)); // Fast-fail → outbox on slow network

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
    
    final response = await http
        .post(
          url,
          headers: headers,
          body: json.encode(data),
        )
        .timeout(const Duration(seconds: 8)); // Fast-fail → outbox on slow network

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
    
    final response = await http
        .put(
          url,
          headers: headers,
          body: json.encode(data),
        )
        .timeout(const Duration(seconds: 8));

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
    
    final response = await http
        .delete(url, headers: headers)
        .timeout(const Duration(seconds: 8));

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

  // ═══════════════════════════════════════════════════════════════
  // Sales
  // ═══════════════════════════════════════════════════════════════

  // PHASE-3 FIX: Critical financial write paths use _postWithRetry for resilience
  Future<int?> submitSale(Map<String, dynamic> saleData, {String? idempotencyKey}) async {
    final result = await _postWithRetry('/api/sales', saleData, idempotencyKey: idempotencyKey);
    return result['serverId'] as int?;
  }

  Future<int?> submitSalesReturn(Map<String, dynamic> returnData, {String? idempotencyKey}) async {
    final result = await post('/api/sales/return', returnData, idempotencyKey: idempotencyKey);
    return result['serverId'] as int?;
  }

  /// الاستبدال — حمولةٌ واحدةٌ يفكّها الخادمُ إلى مستندَين في معاملةٍ واحدة.
  ///
  /// لا مسارَين مرتبطَين: مسارٌ واحدٌ يعني أن نصفَ الاستبدال لا يصل وحدَه،
  /// فلا نافذةَ يبقى فيها العميلُ دائناً ببضاعةٍ أخذها.
  Future<int?> submitExchange(Map<String, dynamic> exchangeData,
      {String? idempotencyKey}) async {
    final result = await post('/api/sales/exchange', exchangeData,
        idempotencyKey: idempotencyKey);
    return result['serverId'] as int?;
  }

  Future<int?> submitHeldOrder(Map<String, dynamic> orderData, {String? idempotencyKey}) async {
    final result = await post('/api/sales/held', orderData, idempotencyKey: idempotencyKey);
    return result['serverId'] as int?;
  }

  /// FIX 3.4: idempotencyKey added so outbox replay prevents double-deletes
  Future<void> deleteHeldOrder(int id, {String? idempotencyKey}) async {
    await delete('/api/sales/held/$id', idempotencyKey: idempotencyKey);
  }

  /// FIX 3.4: idempotencyKey added so outbox replay prevents double-deletes
  Future<void> deleteSalesInvoice(int id, {String? idempotencyKey}) async {
    await delete('/api/sales/$id', idempotencyKey: idempotencyKey);
  }

  Future<void> updateSalesInvoice(int id, Map<String, dynamic> data, {String? idempotencyKey}) async {
    await put('/api/sales/$id', data, idempotencyKey: idempotencyKey);
  }

  /// C-02 (Spec 151) — submit a sales-invoice void to the server. The server
  /// resolves the invoice (globalId → invoiceNumber → id) and performs the
  /// authoritative stock/treasury/JE reversal; the client only caches a light
  /// local marker. Mirrors [submitVoidPurchase]. See
  /// `ApiSalesHandler.postVoidSale`.
  Future<int?> submitVoidSale(Map<String, dynamic> voidData, {String? idempotencyKey}) async {
    final result = await post('/api/sales/void', voidData, idempotencyKey: idempotencyKey);
    return result['serverId'] as int?;
  }

  /// Spec 151 C-05 — submit a customer COLLECTION to the server. The server
  /// resolves the invoice (globalId → invoiceNumber → id), advances
  /// invoice.paid and posts the authoritative Dr Safe / Cr Customer receipt + JE
  /// + safe move; the client caches only a light local paid marker. The
  /// collection is additive, so the server dedups on the incoming globalId. See
  /// `ApiSalesHandler.postSalesPayment`.
  Future<int?> submitSalesPayment(Map<String, dynamic> paymentData, {String? idempotencyKey}) async {
    final result = await post('/api/sales/payment', paymentData, idempotencyKey: idempotencyKey);
    return result['serverId'] as int?;
  }

  // ═══════════════════════════════════════════════════════════════
  // Expenses & Receipts
  // ═══════════════════════════════════════════════════════════════

  Future<int?> submitExpense({
    required double amount,
    required String category,
    String? description,
    int? partyId,
    // Feature 044 — let server remap to its own party id when the
    // mirror's local autoincrement diverges (`resolvePartyId` pattern).
    String? partyGlobalId,
    String? partyName,
    int? safeId,
    int? userId,
    int? costCenterId,
    int? branchId,
    String? globalId, // NEW: UUID-First sync
    // Spec 081 — must reach the server so it can skip the cash JE and the
    // safe transaction for cheque payments (commercial papers owns both).
    // Pre-081 the field was always null on the wire, so the server posted
    // a phantom Dr AP / Cr Cash JE on top of the correct CP entry.
    String? paperType,
    String? idempotencyKey,
  }) async {
    final result = await post('/api/expenses', {
      'amount': amount,
      'category': category,
      'description': description,
      'partyId': partyId,
      if (partyGlobalId != null && partyGlobalId.isNotEmpty)
        'partyGlobalId': partyGlobalId,
      if (partyName != null && partyName.isNotEmpty) 'partyName': partyName,
      'safeId': safeId,
      'userId': userId,
      'costCenterId': costCenterId,
      'branchId': branchId,
      'globalId': globalId,
      if (paperType != null && paperType.isNotEmpty) 'paperType': paperType,
    }, idempotencyKey: idempotencyKey);
    return result['serverId'] as int?;
  }

  /// FIX 3.4: idempotencyKey added so outbox replay prevents double-deletes
  Future<void> deleteExpense(int id, {String? idempotencyKey}) async {
    await delete('/api/expenses/$id', idempotencyKey: idempotencyKey);
  }

  Future<int?> submitReceipt({
    required double amount,
    required String category,
    String? description,
    int? partyId,
    // Feature 044 — `resolvePartyId` on server side maps to its own id.
    String? partyGlobalId,
    String? partyName,
    int? safeId,
    String? safeGlobalId, // Issue 12: lets server resolve to its own safe id
    int? userId,
    int? branchId,
    int? costCenterId,
    // Issue 3 (Feature 020): operator's CoA account pick — overrides the
    // category-default credit leg on the server's JE so the receipt's JE
    // matches the one the client posted locally.
    int? linkedAccountId,
    String? globalId, // UUID-First sync
    // Spec 133 — must reach the server so it can skip the cash JE and the
    // safe transaction for cheque receipts (commercial papers owns both).
    // Pre-133 the field was always null on the wire, so the server posted
    // a phantom Dr Safe / Cr Customer JE on top of the correct CP entry
    // → customer ledger showed two credits per cheque. Symmetric with
    // submitExpense's Spec 081 fix.
    String? paperType,
    String? idempotencyKey,
  }) async {
    final result = await post('/api/receipts', {
      'amount': amount,
      'category': category,
      'description': description,
      'partyId': partyId,
      if (partyGlobalId != null && partyGlobalId.isNotEmpty)
        'partyGlobalId': partyGlobalId,
      if (partyName != null && partyName.isNotEmpty) 'partyName': partyName,
      'safeId': safeId,
      'safeGlobalId': safeGlobalId,
      'userId': userId,
      'branchId': branchId,
      'costCenterId': costCenterId,
      'linkedAccountId': ?linkedAccountId,
      'globalId': globalId,
      if (paperType != null && paperType.isNotEmpty) 'paperType': paperType,
    }, idempotencyKey: idempotencyKey);
    return result['serverId'] as int?;
  }

  Future<void> submitSetDefaultSafe({required int safeId, String? idempotencyKey}) async {
    await post('/api/safes/set-default', {'safeId': safeId}, idempotencyKey: idempotencyKey);
  }

  // ═══════════════════════════════════════════════════════════════
  // Shifts
  // ═══════════════════════════════════════════════════════════════

  Future<int?> openShift(int userId, double openingBalance,
      {int? branchId, String? globalId, String? idempotencyKey}) async {
    final result = await post('/api/shifts/open', {
      'userId': userId,
      'openingBalance': openingBalance,
      // Spec 008 / FR-006: thread branchId so the server records which
      // branch the shift was opened on (multi-branch user support).
      'branchId': ?branchId,
      // Constitution R9: thread the local shift's globalId so the server
      // dedups by it and the matching close can be remapped without an
      // outbox-only id mapping.
      if (globalId != null && globalId.isNotEmpty) 'globalId': globalId,
    }, idempotencyKey: idempotencyKey);
    return result['shiftId'] as int?;
  }

  Future<void> closeShift(
    int shiftId,
    double actualCash, {
    String? notes,
    String? idempotencyKey,
    // Phase 5A.7 (Issue 2) — backfill fields. When the shift was opened
    // offline and the close arrives at the server before /api/shifts/open
    // has drained, these let the server reconstruct the shift in place
    // instead of pseudo-acknowledging the close.
    int? userId,
    double? openingBalance,
    DateTime? openedAt,
    // Constitution R9: shiftGlobalId lets the server resolve the local
    // shiftId (which may not exist on the server side because the open's
    // server-assigned id was never mapped back) → fixes the recurring
    // "Shift not found" 500 / DEAD-LETTER in production logs (2026-05-12).
    String? shiftGlobalId,
  }) async {
    await post('/api/shifts/close', {
      'shiftId': shiftId,
      'actualCash': actualCash,
      'notes': notes,
      'userId': ?userId,
      'openingBalance': ?openingBalance,
      if (openedAt != null) 'openedAt': openedAt.toIso8601String(),
      if (shiftGlobalId != null && shiftGlobalId.isNotEmpty)
        'shiftGlobalId': shiftGlobalId,
    }, idempotencyKey: idempotencyKey);
  }

  // ═══════════════════════════════════════════════════════════════
  // Parties
  // ═══════════════════════════════════════════════════════════════

  Future<int?> createParty(Map<String, dynamic> partyData, {String? idempotencyKey}) async {
    final result = await post('/api/parties', partyData, idempotencyKey: idempotencyKey);
    return result['serverId'] as int?;
  }

  Future<void> updateParty(int id, Map<String, dynamic> partyData, {String? idempotencyKey}) async {
    await put('/api/parties/$id', partyData, idempotencyKey: idempotencyKey);
  }

  Future<void> deleteParty(int id, {String? idempotencyKey}) async {
    await delete('/api/parties/$id', idempotencyKey: idempotencyKey);
  }

  // ═══════════════════════════════════════════════════════════════
  // Products
  // ═══════════════════════════════════════════════════════════════

  /// Lookup a product by barcode on the server — used as CLIENT-mode fallback
  /// when the barcode isn't found in the local cache (e.g. product assigned to
  /// a different warehouse and therefore not included in the branch sync).
  /// Returns the raw JSON map from the server, or null if not found / offline.
  Future<Map<String, dynamic>?> fetchProductByBarcode(String barcode, {int? branchId}) async {
    try {
      final encodedBarcode = Uri.encodeComponent(barcode);
      final branchParam = branchId != null ? '&branch_id=$branchId' : '';
      final url = Uri.parse('$_baseUrl/api/products/barcode?barcode=$encodedBarcode$branchParam');
      debugPrint('[ServerProxy] GET /api/products/barcode?barcode=$barcode$branchParam');
      final response = await http
          .get(url, headers: _authHeaders)
          .timeout(const Duration(seconds: 5));
      if (_isSuccessStatusCode(response.statusCode)) {
        final body = json.decode(response.body) as Map<String, dynamic>;
        if (body['found'] == true) return body;
      }
      return null;
    } catch (e) {
      debugPrint('[ServerProxy] fetchProductByBarcode error (offline?): $e');
      return null;
    }
  }

  Future<int?> createProduct(Map<String, dynamic> productData, {String? idempotencyKey}) async {
    final result = await post('/api/products', productData, idempotencyKey: idempotencyKey);
    return result['serverId'] as int?;
  }

  Future<void> updateProduct(int id, Map<String, dynamic> productData, {String? idempotencyKey}) async {
    await put('/api/products/$id', productData, idempotencyKey: idempotencyKey);
  }

  Future<void> deleteProduct(int id, {String? idempotencyKey}) async {
    await delete('/api/products/$id', idempotencyKey: idempotencyKey);
  }

  // ═══════════════════════════════════════════════════════════════
  // Purchases
  // ═══════════════════════════════════════════════════════════════

  Future<int?> createPurchase(Map<String, dynamic> purchaseData, {String? idempotencyKey}) async {
    final result = await post('/api/purchases', purchaseData, idempotencyKey: idempotencyKey);
    return result['serverId'] as int?;
  }

  Future<void> updatePurchase(int id, Map<String, dynamic> purchaseData, {String? idempotencyKey}) async {
    await put('/api/purchases/$id', purchaseData, idempotencyKey: idempotencyKey);
  }

  Future<void> deletePurchase(int id, {String? idempotencyKey}) async {
    await delete('/api/purchases/$id', idempotencyKey: idempotencyKey);
  }

  Future<int?> submitPurchaseReturn(Map<String, dynamic> returnData, {String? idempotencyKey}) async {
    final result = await post('/api/purchases/return', returnData, idempotencyKey: idempotencyKey);
    return result['serverId'] as int?;
  }

  /// Feature 015 — submit a purchase-return edit (atomic reverse + recreate)
  /// to the server. Same payload shape as [submitPurchaseReturn] plus the
  /// caller's globalId for idempotency on retry.
  Future<int?> submitPurchaseReturnEdit(Map<String, dynamic> editData, {String? idempotencyKey}) async {
    final result = await post('/api/purchases/return/edit', editData, idempotencyKey: idempotencyKey);
    return result['serverId'] as int?;
  }

  /// PR-2 (pre-deploy batch B6) — submit a purchase-invoice void to the
  /// server. The server resolves the invoice (globalId → invoiceNumber →
  /// id) and performs the authoritative stock/AP/treasury/JE reversal;
  /// the client only caches a light local marker. See
  /// `ApiPurchaseHandler.postVoidPurchase`.
  Future<int?> submitVoidPurchase(Map<String, dynamic> voidData, {String? idempotencyKey}) async {
    final result = await post('/api/purchases/void', voidData, idempotencyKey: idempotencyKey);
    return result['serverId'] as int?;
  }

  /// Spec 151 C-03 — submit a purchase-invoice PAYMENT to the server. The
  /// server resolves the invoice (globalId → invoiceNumber → id), advances
  /// invoice.paid and posts the authoritative Dr AP / Cr cash JE + safe move;
  /// the client caches only a light local paid marker. The payment is additive,
  /// so the server dedups on the incoming globalId. See
  /// `ApiPurchaseHandler.postPurchasePayment`.
  Future<int?> submitPurchasePayment(Map<String, dynamic> paymentData, {String? idempotencyKey}) async {
    final result = await post('/api/purchases/payment', paymentData, idempotencyKey: idempotencyKey);
    return result['serverId'] as int?;
  }

  // ═══════════════════════════════════════════════════════════════
  // Inventory
  // ═══════════════════════════════════════════════════════════════

  Future<void> adjustStock({
    required int productId,
    required int warehouseId,
    required double quantity,
    String? type,
    String? notes,
    String? productGlobalId,
    String? warehouseGlobalId, // Spec 136 ISS-26 #2 — robust warehouse routing
    String? adjustmentEventGid, // Spec 135 BUG-A
    String? idempotencyKey,
  }) async {
    await post('/api/inventory/adjust', {
      'productId': productId,
      'productGlobalId': productGlobalId,
      'warehouseId': warehouseId,
      if (warehouseGlobalId != null && warehouseGlobalId.isNotEmpty)
        'warehouseGlobalId': warehouseGlobalId,
      'quantity': quantity,
      'type': type,
      'notes': notes,
      if (adjustmentEventGid != null && adjustmentEventGid.isNotEmpty)
        'adjustmentEventGid': adjustmentEventGid,
    }, idempotencyKey: idempotencyKey);
  }

  Future<int?> submitInventoryBond(Map<String, dynamic> bondData, {String? idempotencyKey}) async {
    final result = await post('/api/inventory/bond', bondData, idempotencyKey: idempotencyKey);
    return result['serverId'] as int?;
  }

  // ═══════════════════════════════════════════════════════════════
  // Treasury
  // ═══════════════════════════════════════════════════════════════

  Future<void> closeSafe(int safeId, {int? userId, double? cashAmount, double? bankAmount, String? notes, String? closeEventGid, String? idempotencyKey}) async {
    await post('/api/safes/close', {
      'safeId': safeId,
      'userId': userId,
      'cashAmount': ?cashAmount,
      'bankAmount': ?bankAmount,
      'notes': ?notes,
      if (closeEventGid != null && closeEventGid.isNotEmpty) 'closeEventGid': closeEventGid,
    }, idempotencyKey: idempotencyKey);
  }

  // ═══════════════════════════════════════════════════════════════
  // Settings
  // ═══════════════════════════════════════════════════════════════

  Future<void> saveSettings(Map<String, String> settings, {String? idempotencyKey}) async {
    // Spec 135 silent-drift (d) — settings is a serverWins + upsert table, so a
    // transient rate-limit (429) or 5xx is safe to retry inline with backoff.
    // Previously the bare post() threw on the first 429 and the mirror's
    // settings push was dropped (or bounced to the outbox for a much later
    // drain), so a settings change silently failed to reach the server during
    // a burst. requestWithRetry re-sends the idempotent upsert.
    await requestWithRetry(
      operationName: 'saveSettings',
      operation: () => post('/api/settings', settings, idempotencyKey: idempotencyKey),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Categories
  // ═══════════════════════════════════════════════════════════════

  Future<int?> createCategory({
    required String name,
    required String color,
    int? printerId,
    String? iconName,
    bool isGlobal = true,
    List<int>? branchIds,
    String? globalId,
    String? idempotencyKey,
  }) async {
    final response = await post('/api/categories', {
      'globalId': ?globalId,
      'name': name,
      'color': color,
      'printerId': printerId,
      'iconName': iconName,
      'isGlobal': isGlobal,
      'branchIds': ?branchIds,
    }, idempotencyKey: idempotencyKey);
    return response['id'] as int?;
  }

  Future<void> updateCategory({
    required int id,
    required String name,
    required String color,
    int? printerId,
    String? iconName,
    bool isGlobal = true,
    List<int>? branchIds,
    String? idempotencyKey,
  }) async {
    await put('/api/categories/$id', {
      'name': name,
      'color': color,
      'printerId': printerId,
      'iconName': iconName,
      'isGlobal': isGlobal,
      'branchIds': ?branchIds,
    }, idempotencyKey: idempotencyKey);
  }

  /// FIX 3.4: idempotencyKey added so outbox replay prevents double-deletes.
  /// Feature 045: [moveToCategoryId] is forwarded as a query string so the
  /// server's `deleteCategory` handler can run the bulk-move inside its
  /// soft-delete transaction. A literal null on the wire (`?moveTo=` empty
  /// or absent) means "leave products uncategorized".
  Future<void> deleteCategory(
    int id, {
    int? moveToCategoryId,
    String? idempotencyKey,
  }) async {
    final qs = moveToCategoryId != null
        ? '?moveToCategoryId=$moveToCategoryId'
        : '';
    await delete('/api/categories/$id$qs', idempotencyKey: idempotencyKey);
  }

  // ═══════════════════════════════════════════════════════════════
  // Users (Admin)
  // ═══════════════════════════════════════════════════════════════

  Future<int?> createUser({
    required String username,
    required String password,
    required String displayName,
    int? roleId,
    List<int>? branchIds,
    String? globalId,
    String? cardCode,
  }) async {
    final response = await post('/api/users', {
      'username': username,
      'password': password,
      'displayName': displayName,
      'roleId': roleId,
      'branchIds': ?branchIds,
      'globalId': ?globalId,
      if (cardCode != null && cardCode.isNotEmpty) 'cardCode': cardCode,
    });
    return response['id'] as int?;
  }

  Future<void> updateUser(int userId, Map<String, dynamic> fields, {String? idempotencyKey}) async {
    await put('/api/users/$userId', fields, idempotencyKey: idempotencyKey);
  }

  /// Fetch ALL users' current state from the server (includes defaultScreen,
  /// roleId, permissions tokens, hashed credentials). Used at client login
  /// to guarantee fresh user metadata independent of the main sync schedule.
  ///
  /// Returns the raw users list from the `/api/users` endpoint, or `null`
  /// if the server is unreachable or returned an error.
  Future<List<Map<String, dynamic>>?> fetchUsers() async {
    try {
      // Restore token from secure storage if not already in memory — this
      // covers the case where the client app just started and hasn't yet
      // completed the /api/health handshake that populates the token.
      if (_apiToken == null || _apiToken!.isEmpty) {
        await restoreToken();
      }
      // Last-ditch: token still missing? Trigger a fresh /api/health
      // handshake. Without this, the post-login refresh would always
      // surface "❌ fetchUsers returned null — token missing or server down"
      // for clients whose secure-storage was cleared (e.g. after a
      // Windows-profile reset or app reinstall).
      if (_apiToken == null || _apiToken!.isEmpty) {
        try {
          final ns = NetworkService.instance;
          final addr = ns.serverAddress ?? '';
          if (addr.isNotEmpty && addr != 'localhost') {
            await ns.testServerConnection(addr, ns.serverPort);
          }
        } catch (e) {
          debugPrint('[ServerProxy] fetchUsers: handshake retry failed: $e');
        }
      }
      final url = Uri.parse('$_baseUrl/api/users');
      final tokenPreview = (_apiToken ?? '').isEmpty
          ? 'NONE'
          : '${_apiToken!.substring(0, _apiToken!.length.clamp(0, 8))}...';
      debugPrint('[ServerProxy] fetchUsers → GET $url (token=$tokenPreview)');

      // Use dart:io HttpClient (not package:http) so we can:
      //   1. Tolerate self-signed certificates with badCertificateCallback —
      //      the client log showed fetchUsers returning null in 0.02s while
      //      the parallel "_fetchJson"-based table syncs succeeded; the only
      //      meaningful difference between the two paths is HTTPS handshake
      //      handling.
      //   2. Set the same headers the sync service uses
      //      ('ngrok-skip-browser-warning', custom User-Agent), so a
      //      tunnelled server doesn't return the ngrok interstitial HTML
      //      that http.get treats as a 200 with a non-JSON body.
      // The connection timeout is split: 8 s for the TCP/TLS handshake,
      // then a soft 12 s ceiling on the overall request — still bounded so
      // login isn't blocked indefinitely.
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 8);
      client.badCertificateCallback = (cert, host, port) => true;
      try {
        final request = await client.getUrl(url);
        if (_apiToken != null && _apiToken!.isNotEmpty) {
          request.headers.set('Authorization', 'Bearer $_apiToken');
        }
        request.headers.set('Content-Type', 'application/json');
        request.headers.set('ngrok-skip-browser-warning', 'true');
        request.headers.set('User-Agent', '${Brand.name}-Client');
        // Spec 151 (P1-8) — keep parity with [_authHeaders]: send the signed
        // `X-Session-Token` (never the old, no-longer-trusted `X-User-Id`).
        // fetchUsers typically runs during the post-login refresh, by which
        // time [acquireSession] has minted a token; if it hasn't yet (offline
        // login) the header is simply omitted.
        final sessionUserId = SyncInterceptor.currentUserId;
        final sessionToken =
            sessionUserId != null ? _sessionTokens[sessionUserId] : null;
        if (sessionToken != null) {
          request.headers.set('X-Session-Token', sessionToken);
        }

        final response = await request.close()
            .timeout(const Duration(seconds: 12));
        final body = await response.transform(utf8.decoder).join();

        if (!(response.statusCode >= 200 && response.statusCode < 300)) {
          debugPrint('[ServerProxy] fetchUsers ❌ HTTP ${response.statusCode} '
              '— body preview: ${body.substring(0, body.length.clamp(0, 200))}');
          return null;
        }
        final decoded = json.decode(body) as Map<String, dynamic>;
        final users = decoded['users'];
        if (users is List) {
          debugPrint('[ServerProxy] fetchUsers ✓ got ${users.length} users');
          return users.cast<Map<String, dynamic>>();
        }
        debugPrint('[ServerProxy] fetchUsers ⚠ unexpected response shape');
        return null;
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      debugPrint('[ServerProxy] fetchUsers error: $e');
      return null;
    }
  }

  Future<void> updateUserPassword(int userId, String password, {String? idempotencyKey}) async {
    await post('/api/users/$userId/password', {'password': password}, idempotencyKey: idempotencyKey);
  }

  Future<void> updateUserPin(int userId, String? pin, {String? idempotencyKey}) async {
    await post('/api/users/$userId/pin', {'pin': pin}, idempotencyKey: idempotencyKey);
  }

  // ═══════════════════════════════════════════════════════════════
  // Roles
  // ═══════════════════════════════════════════════════════════════

  Future<int?> createRole({
    required String name,
    String? description,
    bool isSystemRole = false,
  }) async {
    final response = await post('/api/roles', {
      'name': name,
      'description': ?description,
      'isSystemRole': isSystemRole,
    });
    return response['id'] as int?;
  }

  Future<void> setRolePermissions(int roleId, List<String> permissionCodes,
      {String? idempotencyKey, String? roleGlobalId, String? roleName}) async {
    // _postWithRetry (3 attempts with exponential backoff) instead of plain
    // post(). Permission edits are critical and infrequent — paying a few
    // seconds of retry on a transient 5xx is cheaper than losing the
    // admin's work to a single connection wobble. The Idempotency-Key
    // header makes retries safe on the server side.
    //
    // Spec 136 ISS-15: carry the role's globalId (and name) so the server can
    // resolve/create the role before the FK-bound permission write — a role
    // created on a mirror lives only in that node's local db.
    await _postWithRetry('/api/roles/$roleId/permissions', {
      'permissionCodes': permissionCodes,
      'roleGlobalId': ?roleGlobalId,
      'roleName': ?roleName,
    }, idempotencyKey: idempotencyKey);
  }

  // ═══════════════════════════════════════════════════════════════
  // Warehouses
  // ═══════════════════════════════════════════════════════════════

  Future<int?> createWarehouse({
    required String name,
    int? branchId,
    String? globalId,
  }) async {
    final response = await post('/api/warehouses', {
      'name': name,
      'branchId': branchId,
      'globalId': ?globalId,
    });
    return response['id'] as int?;
  }

  Future<void> updateWarehouse(int id, Map<String, dynamic> fields, {String? idempotencyKey}) async {
    await put('/api/warehouses/$id', fields, idempotencyKey: idempotencyKey);
  }

  Future<void> setDefaultWarehouse(int id, {String? idempotencyKey}) async {
    await put('/api/warehouses/$id', {'setDefault': true}, idempotencyKey: idempotencyKey);
  }

  Future<void> unsetDefaultWarehouse(int id, {String? idempotencyKey}) async {
    await put('/api/warehouses/$id', {'unsetDefault': true}, idempotencyKey: idempotencyKey);
  }

  Future<void> deleteWarehouse(int id, {String? idempotencyKey}) async {
    await delete('/api/warehouses/$id', idempotencyKey: idempotencyKey);
  }

  // ═══════════════════════════════════════════════════════════════
  // User Region Access (Feature 006 / MM.C — F3 hot-fix)
  //
  // Standalone endpoint (not part of putUser like branchIds/warehouseIds)
  // because regions are an optional access tier with their own table.
  // ═══════════════════════════════════════════════════════════════

  Future<void> setUserRegionAccess(
    int userId,
    List<int> regionIds, {
    String? idempotencyKey,
  }) async {
    await post(
      '/api/user-region-access',
      {'userId': userId, 'regionIds': regionIds},
      idempotencyKey: idempotencyKey,
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Cost Centers (Feature 006 / MM.C)
  // ═══════════════════════════════════════════════════════════════

  Future<int?> createCostCenter(
    Map<String, dynamic> data, {
    String? idempotencyKey,
  }) async {
    final result = await post('/api/cost_centers', data, idempotencyKey: idempotencyKey);
    return result['id'] as int?;
  }

  Future<void> updateCostCenter(int id, Map<String, dynamic> data, {String? idempotencyKey}) async {
    await put('/api/cost_centers/$id', data, idempotencyKey: idempotencyKey);
  }

  Future<void> deleteCostCenter(int id, {String? idempotencyKey}) async {
    await delete('/api/cost_centers/$id', idempotencyKey: idempotencyKey);
  }

  // ═══════════════════════════════════════════════════════════════
  // Accounts (CoA) + Account Mappings (Feature 006 / MM.C)
  // ═══════════════════════════════════════════════════════════════

  Future<int?> createAccount(
    Map<String, dynamic> data, {
    String? idempotencyKey,
  }) async {
    final result = await post('/api/accounts', data, idempotencyKey: idempotencyKey);
    return result['id'] as int?;
  }

  Future<void> updateAccount(int id, Map<String, dynamic> data, {String? idempotencyKey}) async {
    await put('/api/accounts/$id', data, idempotencyKey: idempotencyKey);
  }

  Future<void> deleteAccount(int id, {String? idempotencyKey}) async {
    await delete('/api/accounts/$id', idempotencyKey: idempotencyKey);
  }

  Future<void> setAccountMapping(
    Map<String, dynamic> data, {
    String? idempotencyKey,
  }) async {
    await post('/api/account-mappings', data, idempotencyKey: idempotencyKey);
  }

  Future<void> deleteAccountMapping({
    required String purpose,
    int? costCenterId,
    String? idempotencyKey,
  }) async {
    final cc = costCenterId != null ? '&cost_center_id=$costCenterId' : '';
    final url = Uri.parse(
        '$_baseUrl/api/account-mappings?purpose=${Uri.encodeComponent(purpose)}$cc');
    final headers = Map<String, String>.from(_authHeaders);
    if (idempotencyKey != null) {
      headers['X-Idempotency-Key'] = idempotencyKey;
    }
    final response = await http
        .delete(url, headers: headers)
        .timeout(const Duration(seconds: 8));
    if (!_isSuccessStatusCode(response.statusCode)) {
      throw Exception(
          'Server error (${response.statusCode}): ${response.body}');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Safes (Feature 006 / MM.C — mirror-mode admin CRUD)
  //
  // Operational endpoints (close / transaction / transfer / set-default)
  // already exist above; these handle structural CRUD only.
  // ═══════════════════════════════════════════════════════════════

  Future<int?> createSafe(
    Map<String, dynamic> data, {
    String? idempotencyKey,
  }) async {
    final result = await post('/api/safes', data, idempotencyKey: idempotencyKey);
    return result['id'] as int?;
  }

  Future<void> updateSafe(int id, Map<String, dynamic> data, {String? idempotencyKey}) async {
    await put('/api/safes/$id', data, idempotencyKey: idempotencyKey);
  }

  Future<void> deleteSafe(int id, {String? idempotencyKey}) async {
    await delete('/api/safes/$id', idempotencyKey: idempotencyKey);
  }

  // ═══════════════════════════════════════════════════════════════
  // Branches (Feature 006 / MM.C — mirror-mode admin CRUD)
  // ═══════════════════════════════════════════════════════════════

  Future<int?> createBranch(
    Map<String, dynamic> data, {
    String? idempotencyKey,
  }) async {
    final result = await post('/api/branches', data, idempotencyKey: idempotencyKey);
    return result['id'] as int?;
  }

  Future<void> updateBranch(int id, Map<String, dynamic> data, {String? idempotencyKey}) async {
    await put('/api/branches/$id', data, idempotencyKey: idempotencyKey);
  }

  Future<void> deleteBranch(
    int id, {
    int? reassignUsersToBranchId,
    String? idempotencyKey,
  }) async {
    // Feature 049 (v131) — forward `reassignUsersToBranchId` via query
    // string so the server-side handler runs the bulk-reassign +
    // soft-delete inside one transaction. Null means "no reassign";
    // the server then throws the Arabic FK-prevention error.
    final qs = reassignUsersToBranchId != null
        ? '?reassignUsersToBranchId=$reassignUsersToBranchId'
        : '';
    await delete('/api/branches/$id$qs', idempotencyKey: idempotencyKey);
  }

  // ═══════════════════════════════════════════════════════════════
  // Commercial Papers
  // ═══════════════════════════════════════════════════════════════

  Future<int?> createCommercialPaper(Map<String, dynamic> data, {String? idempotencyKey}) async {
    final result = await post('/api/commercial-papers', data, idempotencyKey: idempotencyKey);
    return result['serverId'] as int?;
  }

  Future<void> updateCommercialPaperStatus(
    int id, {
    required String status,
    int? changedBy,
    String? changedByUsername,
    String? notes,
    int? endorsedToPartyId,
    String? globalId,
    // Feature 048 (v130) — caller-chosen contra leg for the auto-posted
    // JE. The server resolves the integer id via the globalId variant
    // when chart-of-accounts auto-increments diverge between client
    // and server (same remap pattern as partyGlobalId).
    int? counterAccountId,
    String? counterAccountGlobalId,
  }) async {
    // Feature 014 / Issue 3 — the path id is the LOCAL id and does
    // NOT match the server's. The server resolves by `globalId` when
    // present; the path `id` becomes a hint only.
    //
    // Feature 042 (Bug 5) — also forward `changedByUsername` so the
    // server can remap `changedBy` via `_resolveUserIdNullable`
    // (paper_status_history.changed_by NOT NULL FK to users(id) was
    // failing on every mirror status-change before this).
    await put('/api/commercial-papers/$id/status', {
      'status': status,
      'changedBy': changedBy,
      if (changedByUsername != null && changedByUsername.isNotEmpty)
        'changedByUsername': changedByUsername,
      'notes': notes,
      'endorsedToPartyId': endorsedToPartyId,
      if (globalId != null && globalId.isNotEmpty) 'globalId': globalId,
      'counterAccountId': ?counterAccountId,
      if (counterAccountGlobalId != null && counterAccountGlobalId.isNotEmpty)
        'counterAccountGlobalId': counterAccountGlobalId,
    });
  }

  Future<void> renewCommercialPaper(
    int id, {
    required String newDueDate,
    int? changedBy,
    String? notes,
  }) async {
    await post('/api/commercial-papers/$id/renew', {
      'newDueDate': newDueDate,
      'changedBy': changedBy,
      'notes': notes,
    });
  }

  Future<void> partialCollectPaper(
    int id, {
    required double amount,
    int? changedBy,
    String? notes,
  }) async {
    await post('/api/commercial-papers/$id/partial-collect', {
      'amount': amount,
      'changedBy': changedBy,
      'notes': notes,
    });
  }

  Future<void> depositPaperForCollection(
    int id, {
    required int bankSafeId,
    int? changedBy,
    String? notes,
  }) async {
    await post('/api/commercial-papers/$id/deposit', {
      'bankSafeId': bankSafeId,
      'changedBy': changedBy,
      'notes': notes,
    });
  }

  Future<void> reissuePaper(
    int id, {
    required int newPartyId,
    int? changedBy,
    String? notes,
  }) async {
    await post('/api/commercial-papers/$id/reissue', {
      'newPartyId': newPartyId,
      'changedBy': changedBy,
      'notes': notes,
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // Backup
  // ═══════════════════════════════════════════════════════════════

  Future<void> uploadBackup(String clientName, List<int> dbBytes) async {
    await post('/api/backup', {
      'clientName': clientName,
      'dbData': base64Encode(dbBytes),
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // Journal Entries (Client → Server)
  // ═══════════════════════════════════════════════════════════════

  Future<void> submitJournalEntry({
    required String description,
    required String date,
    required List<Map<String, dynamic>> lines,
    String? referenceType,
    int? referenceId,
    bool isAutoPosted = true,
    int? costCenterId,
    int? branchId,
    String? globalId, // NEW: UUID-First sync
    String? idempotencyKey,
  }) async {
    await post('/api/journals', {
      'description': description,
      'date': date,
      'lines': lines,
      'referenceType': referenceType,
      'referenceId': referenceId,
      'isAutoPosted': isAutoPosted,
      'costCenterId': costCenterId,
      'branchId': branchId,
      'globalId': globalId,
    }, idempotencyKey: idempotencyKey);
  }

  // ═══════════════════════════════════════════════════════════════
  // Safe Transactions (Client → Server)
  // ═══════════════════════════════════════════════════════════════

  Future<void> submitSafeTransaction({
    required int safeId,
    required String transactionType,
    required double amount,
    String category = 'general',
    String? description,
    int? userId,
    String? referenceType,
    int? referenceId,
    String? globalId, // NEW: UUID-First sync
    String? idempotencyKey,
    // Phase 5B.4 (Issue 7) — server uses safeGlobalId to resolve to its
    // own safe.id (and therefore the right linked GL account) instead of
    // trusting the client's local safe.id. costCenterId likewise lets the
    // server stamp the JE with the dialog-selected cost center, not its
    // default. Mirrors the postReceipt flow shipped in commit 0d93217.
    String? safeGlobalId,
    int? costCenterId,
    // Spec 087 (F2) — thread the partyId end-to-end. The server's
    // postSafeTransaction handler resolves partyGlobalId → server's
    // partyId so the row lands with the correct party link and the
    // voucher appears in customer/supplier statements.
    int? partyId,
    String? partyGlobalId,
  }) async {
    // PHASE-3 FIX: Treasury operations use retry logic for network resilience
    await _postWithRetry('/api/safes/transaction', {
      'safeId': safeId,
      'transactionType': transactionType,
      'amount': amount,
      'category': category,
      'description': description,
      'userId': userId,
      'referenceType': referenceType,
      'referenceId': referenceId,
      'globalId': globalId,
      if (safeGlobalId != null && safeGlobalId.isNotEmpty)
        'safeGlobalId': safeGlobalId,
      'costCenterId': ?costCenterId,
      'partyId': ?partyId,
      if (partyGlobalId != null && partyGlobalId.isNotEmpty)
        'partyGlobalId': partyGlobalId,
    }, idempotencyKey: idempotencyKey);
  }

  Future<void> submitSafeTransfer({
    required int fromSafeId,
    required int toSafeId,
    required double amount,
    int? userId,
    String? description,
    String? globalId,
    String? idempotencyKey,
  }) async {
    await post('/api/safes/transfer', {
      'fromSafeId': fromSafeId,
      'toSafeId': toSafeId,
      'amount': amount,
      'userId': userId,
      'description': description,
      // `/api/safes/transfer` مش بيقرا هيدر الـidempotency، فالـglobalId هو
      // مسار الـdedup الوحيد — زي `postSafeTransaction` و`postExpense`.
      'globalId': globalId,
    }, idempotencyKey: idempotencyKey);
  }

  // ═══════════════════════════════════════════════════════════════
  // Stock Transfers (Client → Server)
  // ═══════════════════════════════════════════════════════════════

  Future<void> submitStockTransfer({
    required int fromWarehouseId,
    required int toWarehouseId,
    required List<Map<String, dynamic>> items,
    int? userId,
    String? notes,
    String? globalId,
    String? idempotencyKey,
  }) async {
    await post('/api/inventory/transfer', {
      'fromWarehouseId': fromWarehouseId,
      'toWarehouseId': toWarehouseId,
      'items': items,
      'userId': userId,
      'notes': notes,
      // Spec 129 F4 — caller-minted UUIDv7. Server dedups against this.
      if (globalId != null && globalId.isNotEmpty) 'globalId': globalId,
    }, idempotencyKey: idempotencyKey);
  }

  // ═══════════════════════════════════════════════════════════════
  // Units of Measure (UOM)
  // ═══════════════════════════════════════════════════════════════

  // ═══════════════════════════════════════════════════════════════
  // UNITS & BARCODES
  // ═══════════════════════════════════════════════════════════════

  Future<int?> submitUnit(Map<String, dynamic> data, {String? idempotencyKey}) async {
    final res = await post('/api/units', data, idempotencyKey: idempotencyKey);
    return res['serverId'] as int?;
  }

  Future<bool> updateUnit(int id, Map<String, dynamic> data, {String? idempotencyKey}) async {
    await put('/api/units/$id', data, idempotencyKey: idempotencyKey);
    return true;
  }

  Future<bool> deleteUnit(int id, {String? idempotencyKey}) async {
    await delete('/api/units/$id', idempotencyKey: idempotencyKey);
    return true;
  }

  Future<int?> submitProductUnitMapping(Map<String, dynamic> data, {String? idempotencyKey}) async {
    final res = await post('/api/product-units', data, idempotencyKey: idempotencyKey);
    return res['serverId'] as int?;
  }

  Future<bool> updateProductUnitMapping(int id, Map<String, dynamic> data, {String? idempotencyKey}) async {
    await put('/api/product-units/$id', data, idempotencyKey: idempotencyKey);
    return true;
  }

  Future<bool> deleteProductUnitMapping(int id, {String? idempotencyKey}) async {
    await delete('/api/product-units/$id', idempotencyKey: idempotencyKey);
    return true;
  }

  Future<int?> submitProductBarcode(Map<String, dynamic> data, {String? idempotencyKey}) async {
    final res = await post('/api/product-barcodes', data, idempotencyKey: idempotencyKey);
    return res['serverId'] as int?;
  }

  Future<bool> deleteProductBarcode(int id, {String? idempotencyKey}) async {
    await delete('/api/product-barcodes/$id', idempotencyKey: idempotencyKey);
    return true;
  }

  // ═══════════════════════════════════════════════════════════════
  // Regions
  // ═══════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>?> fetchRegions() async {
    try {
      final url = Uri.parse('$_baseUrl/api/regions');
      debugPrint('[ServerProxy] GET /api/regions');
      final response = await http
          .get(url, headers: _authHeaders)
          .timeout(const Duration(seconds: 10));
      if (_isSuccessStatusCode(response.statusCode)) {
        final body = json.decode(response.body) as Map<String, dynamic>;
        final list = body['regions'] as List;
        return list.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('[ServerProxy] fetchRegions error: $e');
    }
    return null;
  }

  Future<int?> createRegion({
    required String name,
    String? address,
    String? phone,
    int? costCenterId,
  }) async {
    final result = await post('/api/regions', {
      'name': name,
      'address': address,
      'phone': phone,
      'costCenterId': costCenterId,
    });
    return result['id'] as int?;
  }

  Future<bool> updateRegion({
    required int id,
    required String name,
    String? address,
    String? phone,
    int? costCenterId,
  }) async {
    await put('/api/regions/$id', {
      'name': name,
      'address': address,
      'phone': phone,
      'costCenterId': costCenterId,
    });
    return true;
  }

  // ═══════════════════════════════════════════════════════════════
  // S4.1: Party Groups
  // ═══════════════════════════════════════════════════════════════

  Future<int?> createPartyGroup(
    Map<String, dynamic> data, {
    String? idempotencyKey,
  }) async {
    final result = await post('/api/party-groups', data, idempotencyKey: idempotencyKey);
    return result['id'] as int?;
  }

  Future<bool> updatePartyGroup(
    int id,
    Map<String, dynamic> data, {
    String? idempotencyKey,
  }) async {
    await put('/api/party-groups/$id', data, idempotencyKey: idempotencyKey);
    return true;
  }

  Future<bool> deletePartyGroup(int id, {String? idempotencyKey}) async {
    await delete('/api/party-groups/$id', idempotencyKey: idempotencyKey);
    return true;
  }

  // ═══════════════════════════════════════════════════════════════
  // S4.1: Purchase Orders
  // ═══════════════════════════════════════════════════════════════

  Future<int?> createPurchaseOrder(
    Map<String, dynamic> data, {
    String? idempotencyKey,
  }) async {
    final result = await post('/api/purchase-orders', data, idempotencyKey: idempotencyKey);
    return result['id'] as int?;
  }

  Future<bool> updatePurchaseOrderStatus(
    int id,
    String status, {
    String? idempotencyKey,
  }) async {
    await put('/api/purchase-orders/$id/status', {'status': status},
        idempotencyKey: idempotencyKey);
    return true;
  }

  Future<bool> deletePurchaseOrder(int id, {String? idempotencyKey}) async {
    await delete('/api/purchase-orders/$id', idempotencyKey: idempotencyKey);
    return true;
  }

  // ═══════════════════════════════════════════════════════════════
  // S4.1: Sales Orders
  // ═══════════════════════════════════════════════════════════════

  Future<int?> createSalesOrder(
    Map<String, dynamic> data, {
    String? idempotencyKey,
  }) async {
    final result = await post('/api/sales-orders', data, idempotencyKey: idempotencyKey);
    return result['id'] as int?;
  }

  Future<bool> updateSalesOrderStatus(
    int id,
    String status, {
    String? idempotencyKey,
  }) async {
    await put('/api/sales-orders/$id/status', {'status': status},
        idempotencyKey: idempotencyKey);
    return true;
  }

  Future<bool> deleteSalesOrder(int id, {String? idempotencyKey}) async {
    await delete('/api/sales-orders/$id', idempotencyKey: idempotencyKey);
    return true;
  }

  // ═══════════════════════════════════════════════════════════════
  // S4.1: Quotations
  // ═══════════════════════════════════════════════════════════════

  Future<int?> createQuotation(
    Map<String, dynamic> data, {
    String? idempotencyKey,
  }) async {
    final result = await post('/api/quotations', data, idempotencyKey: idempotencyKey);
    return result['id'] as int?;
  }

  Future<bool> updateQuotationStatus(
    int id,
    String status, {
    int? convertedInvoiceId,
    String? idempotencyKey,
  }) async {
    await put('/api/quotations/$id/status', {
      'status': status,
      'convertedToInvoiceId': ?convertedInvoiceId,
    }, idempotencyKey: idempotencyKey);
    return true;
  }

  Future<bool> updateQuotation(
    int id,
    Map<String, dynamic> data, {
    String? idempotencyKey,
  }) async {
    await put('/api/quotations/$id', data, idempotencyKey: idempotencyKey);
    return true;
  }

  Future<bool> deleteQuotation(int id, {String? idempotencyKey}) async {
    await delete('/api/quotations/$id', idempotencyKey: idempotencyKey);
    return true;
  }

  // ═══════════════════════════════════════════════════════════════
  // S4.1: Price Lists
  // ═══════════════════════════════════════════════════════════════

  Future<int?> createPriceList(
    Map<String, dynamic> data, {
    String? idempotencyKey,
  }) async {
    final result = await post('/api/price-lists', data, idempotencyKey: idempotencyKey);
    return result['id'] as int?;
  }

  Future<bool> updatePriceList(
    int id,
    Map<String, dynamic> data, {
    String? idempotencyKey,
  }) async {
    await put('/api/price-lists/$id', data, idempotencyKey: idempotencyKey);
    return true;
  }

  Future<bool> setPriceListItem(
    Map<String, dynamic> data, {
    String? idempotencyKey,
  }) async {
    await post('/api/price-list-items', data, idempotencyKey: idempotencyKey);
    return true;
  }

  // ═══════════════════════════════════════════════════════════════
  // S4.1: Printers
  // ═══════════════════════════════════════════════════════════════

  Future<int?> createPrinter(
    Map<String, dynamic> data, {
    String? idempotencyKey,
  }) async {
    final result = await post('/api/printers', data, idempotencyKey: idempotencyKey);
    return result['id'] as int?;
  }

  Future<bool> updatePrinter(
    int id,
    Map<String, dynamic> data, {
    String? idempotencyKey,
  }) async {
    await put('/api/printers/$id', data, idempotencyKey: idempotencyKey);
    return true;
  }

  Future<bool> deletePrinter(int id, {String? idempotencyKey}) async {
    await delete('/api/printers/$id', idempotencyKey: idempotencyKey);
    return true;
  }

  // ─── P3.1: Delta Pull ────────────────────────────────────────────────────

  /// Fetch records from [table] that changed since [since] (epoch seconds).
  /// Returns `{ "rows": [...], "serverTime": <int epoch> }` or null on error.
  /// When [since] is null the server performs a full table dump.
  ///
  /// Phase 5A.3 (Issue 5) / المرحلة ١ G2: النداء يحمل `&branch_id=<id>` فيقصّ
  /// الخادمُ الجداولَ المحصورة قبل الإرسال. الإعفاء الوحيد من الحصر هو **مدير
  /// النظام** (وجهاز المرآة) — لا «المدير أو المدير المالي» كما كان هنا:
  /// تفصيل القرار في [_branchScopeQueryParam].
  /// Fetch one PAGE of a table's delta.
  ///
  /// [limit] bounds the rows the server materialises for this request; the
  /// response carries `hasMore`. [cursorTs]/[cursorId] are the keyset cursor
  /// for pages 2..N — the `(last_modified_at, id)` pair of the last row the
  /// caller applied. Callers must loop until `hasMore == false` before
  /// advancing their watermark (see `DeltaPullService.pullTable`).
  Future<Map<String, dynamic>?> fetchDelta(
    String table, {
    DateTime? since,
    int? limit,
    int? cursorTs,
    int? cursorId,
  }) async {
    try {
      final sinceParam = since != null
          ? '&since=${since.millisecondsSinceEpoch ~/ 1000}'
          : '';
      final limitParam = limit != null ? '&limit=$limit' : '';
      final cursorParam = (cursorTs != null && cursorId != null)
          ? '&cursorTs=$cursorTs&cursorId=$cursorId'
          : '';
      final branchParam = await _branchScopeQueryParam();
      final url = Uri.parse('$_baseUrl/api/sync/pull?table=$table'
          '$sinceParam$limitParam$cursorParam$branchParam');
      final response = await http
          .get(url, headers: _authHeaders)
          .timeout(const Duration(seconds: 30));
      if (!_isSuccessStatusCode(response.statusCode)) {
        debugPrint('[ServerProxy] fetchDelta $table HTTP ${response.statusCode}');
        return null;
      }
      return json.decode(response.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[ServerProxy] fetchDelta $table: $e');
      return null;
    }
  }

  /// المرحلة ١ / G2 — يبني `&branch_id=<id>` لنداءات المزامنة المحصورة.
  ///
  /// **يُرجع `''` (بلا حصر) لمدير النظام وحده**، لأن إعداد البدء يحتاج
  /// قراءة البيانات الأساسية كاملة قبل ربط الجهاز بفرع.
  ///
  /// كان يستعمل [SyncInterceptor.isCurrentUserAdmin] — مطابقة نصّية على
  /// اسم الدور تمنح «مسؤول مبيعات» صلاحية كاملة. وكان يُرجع `''` أيضاً
  /// عندما لا يكون الجهاز مربوطاً بفرع، أي **يفشل مفتوحاً**: جهاز غير
  /// مُعَدّ كان يسحب بيانات الشركة كاملة. كلاهما مُغلق الآن.
  ///
  /// ⚠️ العلَم أدناه هو الاقتران `isSystemRole && name == 'مدير النظام'` كما
  /// ينشره متحكّم المصادقة — **لا** العمود `isSystemRole` وحده، فهو `true`
  /// لخمسة أدوار مزروعة منها الكاشير ومدير مالي.
  Future<String> _branchScopeQueryParam() async {
    if (SyncInterceptor.currentUserIsSystemAdmin == true) return '';

    // جهاز المرآة — بلا تغيير (المواصفة §٢). المرآة لا تكتب
    // `client_branch_id` إطلاقاً (يكتبه معالج الإعداد وشاشة وضع الشبكة
    // فقط)، فكانت هتقع على سنتينل `-1`. وبما أن الاقتران يمنحها توكن جلسة
    // أدمن مُتحقَّق منه، كان الخادم هيرجّع صفر صفوف بينما
    // `DeltaPullService.shouldWithholdWatermark` لا يحجب العلامة المائية
    // إلا للنداء **بلا توكن** ⇒ علامة مائية تتقدّم فوق استجابة فارغة
    // وفجوة دائمة. المرآة ليست جهاز فرع أصلاً: نطاقها الفروع كلها.
    if (SyncInterceptor.isMirrorMode) return '';

    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt('client_branch_id');
    if (id == null) {
      // يفشل مقفولاً. السنتينل يطابق `ApiHandler._kNoBranchAccess` فيقصّ
      // الخادمُ الصفوفَ إلى صفر بدل أن يعيدها كلها.
      return '&branch_id=-1';
    }
    return '&branch_id=$id';
  }

  /// منفذ اختبار لـ[_branchScopeQueryParam]. المنطق أعلاه هو حدّ أمني،
  /// واختباره عبر نداء HTTP كامل يخلط فشله بفشل الشبكة.
  @visibleForTesting
  Future<String> debugBranchScopeQueryParam() => _branchScopeQueryParam();

  /// Returns the authoritative server clock (epoch seconds) from
  /// `/api/sync/time`. Falls back to `null` on failure — callers should
  /// then decide whether to retry or use a safe local approximation.
  Future<int?> fetchServerTime() async {
    try {
      final url = Uri.parse('$_baseUrl/api/sync/time');
      final response = await http
          .get(url, headers: _authHeaders)
          .timeout(const Duration(seconds: 10));
      if (!_isSuccessStatusCode(response.statusCode)) return null;
      final body = json.decode(response.body) as Map<String, dynamic>;
      return body['serverTime'] as int?;
    } catch (e) {
      debugPrint('[ServerProxy] fetchServerTime: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Mirror-mode admin verification (Feature 006 / MM.C)
  // ═══════════════════════════════════════════════════════════════

  /// Outcome of a `verifyAdmin` call. Distinguishes wrong-password (401)
  /// from non-admin-role (403) so the wizard can surface a precise
  /// message — both are user-actionable but in different ways.
  Future<MirrorAdminVerification> verifyAdmin({
    required String username,
    required String password,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/api/auth/verify-admin');
      final response = await http
          .post(
            url,
            headers: _authHeaders,
            body: json.encode({'username': username, 'password': password}),
          )
          .timeout(const Duration(seconds: 10));

      if (_isSuccessStatusCode(response.statusCode)) {
        final body = json.decode(response.body) as Map<String, dynamic>;
        final id = body['userId'];
        final userId = id is int
            ? id
            : (id is num ? id.toInt() : int.tryParse('${id ?? ''}'));
        if (userId == null) {
          return MirrorAdminVerification.failed(
            'Server response missing userId',
          );
        }
        return MirrorAdminVerification.success(
          userId: userId,
          displayName: (body['displayName'] as String?) ?? username,
          roleName: (body['roleName'] as String?) ?? '',
        );
      }
      if (response.statusCode == 401) {
        return MirrorAdminVerification.invalidCredentials();
      }
      if (response.statusCode == 403) {
        return MirrorAdminVerification.notAdmin();
      }
      return MirrorAdminVerification.failed(
        'HTTP ${response.statusCode}: ${response.body}',
      );
    } catch (e) {
      return MirrorAdminVerification.failed(e.toString());
    }
  }

  /// Push a single activity log entry from a client to the server.
  /// Uses the standard retry + idempotency-key pattern.
  Future<void> pushActivityLog(
    Map<String, dynamic> data, {
    String? idempotencyKey,
  }) async {
    await _postWithRetry(
      '/api/activity-logs/push',
      data,
      idempotencyKey: idempotencyKey,
    );
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
  Future<void> acquireSession({
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
    if (!bypassModeGate && !SyncInterceptor.isClientMode) return;
    // Remember the proof (in memory only) so a token can be re-minted later.
    _sessionProofs[userId] = _SessionProof(
      username: username,
      password: password,
      cardCode: cardCode,
    );
    await _mintSession(userId);
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

  /// POST the remembered proof for [userId] to `/api/auth/session` and cache
  /// the returned opaque token. No-op when no usable proof is held. Swallows
  /// ALL errors — a failed mint leaves any previously-cached token untouched
  /// (never clears a good token on a transient failure). Never logs the token
  /// or the credential.
  Future<void> _mintSession(int userId) async {
    final proof = _sessionProofs[userId];
    if (proof == null) return;

    final body = <String, dynamic>{};
    if (proof.cardCode != null && proof.cardCode!.isNotEmpty) {
      body['cardCode'] = proof.cardCode;
    } else if (proof.username != null &&
        proof.username!.isNotEmpty &&
        proof.password != null &&
        proof.password!.isNotEmpty) {
      body['username'] = proof.username;
      body['password'] = proof.password;
    } else {
      return; // nothing usable to send
    }

    try {
      final url = Uri.parse('$_baseUrl/api/auth/session');
      final response = await http
          .post(url, headers: _authHeaders, body: json.encode(body))
          .timeout(const Duration(seconds: 8));
      if (_isSuccessStatusCode(response.statusCode) &&
          response.body.isNotEmpty) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final token = data['token'] as String?;
        if (token != null && token.isNotEmpty) {
          _sessionTokens[userId] = token;
          _sessionMintedAt[userId] = DateTime.now();
          debugPrint('[ServerProxy] session token acquired for uid=$userId');
          return;
        }
      }
      debugPrint('[ServerProxy] session token NOT acquired for uid=$userId '
          '(HTTP ${response.statusCode})');
    } catch (e) {
      debugPrint('[ServerProxy] acquireSession failed for uid=$userId: $e');
    }
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
