// ServerProxy - settings, users, roles, region access and backup writes.
part of '../server_proxy.dart';

/// Settings, users (admin), roles, user-region access and backup of [ServerProxy].
extension ServerProxyAdminWrites on ServerProxy {
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
      final client = TlsTrust.ioClient(
        connectionTimeout: const Duration(seconds: 8),
      );
      try {
        final request = await client.getUrl(url);
        if (_apiToken != null && _apiToken!.isNotEmpty) {
          request.headers.set('Authorization', 'Bearer $_apiToken');
        }
        final deviceId = DeviceIdentityService.instance.tryGetDeviceId();
        if (deviceId != null && deviceId.isNotEmpty) {
          request.headers.set('X-Device-Id', deviceId);
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
  // Backup
  // ═══════════════════════════════════════════════════════════════

  Future<void> uploadBackup(String clientName, List<int> dbBytes) async {
    await post('/api/backup', {
      'clientName': clientName,
      'dbData': base64Encode(dbBytes),
    });
  }
}
