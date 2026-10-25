// ═══════════════════════════════════════════════════════════════════════════
// REPRO-MIRROR harness — host ⇄ client in one process (no GUI, no sockets).
//
// NOT a test file (no `_test.dart` suffix) — imported by the repro tests.
//
// * host   : AppDatabase.forTesting() fronted by the REAL `ApiHandler` router
//            (`buildRouter().call(Request)` — same pattern as
//            test/integration/api_p1_8b_sync_scope_test.dart).
// * client : a second AppDatabase.forTesting() (carries its own seeded
//            admin/admin, exactly like a freshly installed device).
// * "wire" : [hostGet] feeds the router a `shelf.Request`; the JSON is then
//            applied on the client with the SAME production code that applies
//            it on a device: `UserSyncStrategy.syncFromJson` (full sync /
//            login fallback) or `DeltaPullService.upsertRowForTest` (delta).
//
// What is NOT driven: real sockets/TLS, `ServerProxy` HTTP, the Flutter UI.
// Mode is switched with `NetworkService.debugSetModeForTests` +
// `MirrorState.debugSetForTests` + the real `ClientWriteInterceptor.setup()`.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:convert';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;

import 'package:picpos_erp/core/logging/diagnostic_logger.dart';
import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/data/database/sync_interceptor.dart';
import 'package:picpos_erp/services/api/api_auth_middleware.dart';
import 'package:picpos_erp/services/api/api_handler.dart';
import 'package:picpos_erp/services/api/api_rate_limiter.dart';
import 'package:picpos_erp/services/api/api_session_token.dart';
import 'package:picpos_erp/services/api/api_user_context.dart';
import 'package:picpos_erp/services/api/server_login_throttle.dart';
import 'package:picpos_erp/services/setup/branch_account_verifier.dart';
import 'package:picpos_erp/services/setup/first_user_verifier.dart';
import 'package:picpos_erp/services/setup/main_auth_port.dart';
import 'package:picpos_erp/services/client_write_interceptor.dart';
import 'package:picpos_erp/services/delta_pull_service.dart';
import 'package:picpos_erp/services/mirror_state.dart';
import 'package:picpos_erp/services/network_service.dart';
import 'package:picpos_erp/services/server_proxy.dart';
import 'package:picpos_erp/services/sync/strategies/user_sync_strategy.dart';

const kAdminCustomPw = 'AdminCustom#2026';
const kCashierInitialPw = 'Cash#Init123';
const kAccountantInitialPw = 'Acct#Init456';
const kManagerPw = 'Mgr#Multi789';

/// Unreachable server: connect() is refused immediately, never hangs.
const _deadHost = '127.0.0.1';
const _deadPort = 1;

class Peers {
  Peers._(this.host, this.client, this.api);

  final AppDatabase host;
  final AppDatabase client;
  final ApiHandler api;

  late int cashierRoleId;
  late int accountantRoleId;
  late int managerRoleId; // custom (non-system) role: «مدير فروع»
  late int branch1; // seeded default branch (same id on both peers)
  late int branch2;
  late int cashierId;
  late int accountantId;
  late int managerId;

  // ── wire ────────────────────────────────────────────────────────────────
  Future<shelf.Response> hostRaw(String method, String path,
      {int? userId, Object? body}) {
    return api.buildRouter().call(shelf.Request(
          method,
          Uri.parse('http://localhost$path'),
          body: body == null ? null : jsonEncode(body),
          headers: body == null ? null : {'content-type': 'application/json'},
          context: userId != null ? {ApiUserCtx.userIdKey: userId} : const {},
        ));
  }

  Future<Map<String, dynamic>> hostGet(String path, {int? userId}) async {
    final r = await hostRaw('GET', path, userId: userId);
    final text = await r.readAsString();
    if (r.statusCode != 200) {
      throw StateError('GET $path -> ${r.statusCode}: $text');
    }
    return jsonDecode(text) as Map<String, dynamic>;
  }

  /// Full-sync path (first sync, login fallback `performTableSync('users')`).
  Future<Map<String, dynamic>> syncUsersFull({int? asUser}) async {
    final json = await hostGet('/api/users', userId: asUser);
    await UserSyncStrategy(client).syncFromJson(json);
    return json;
  }

  /// Delta-pull path (`/api/sync/pull?table=users` → `_upsertRow`).
  Future<List<Map<String, dynamic>>> syncUsersDelta({int? asUser}) async {
    final json = await hostGet('/api/sync/pull?table=users', userId: asUser);
    DeltaPullService.instance.initialize(client);
    final rows = [
      for (final r in json['rows'] as List) Map<String, dynamic>.from(r as Map)
    ];
    for (final r in rows) {
      await DeltaPullService.instance.upsertRowForTest('users', r);
    }
    return rows;
  }

  /// A1: the first sync of a freshly paired device, as the NEW setup performs it:
  /// the tokenless user rows arrive first (no credentials), then the FIRST USER
  /// is verified on the main (session -> change-password when temporary ->
  /// `/api/users` as that user -> apply -> seeded `admin/admin` retired).
  Future<AccountVerification> firstSync({
    String username = 'admin',
    String password = kAdminCustomPw,
    String? newPassword,
  }) async {
    await syncUsersFull(); // pre-login rows: no hashes (window closed)
    return FirstUserVerifier(
      db: client,
      port: _PeerMainPort(this),
      permissionCodes: (_) async => const [],
    ).verify(username: username, password: password, newPassword: newPassword);
  }

  // ── reads on either peer ────────────────────────────────────────────────
  Future<User?> userOn(AppDatabase db, String username) =>
      (db.select(db.users)..where((u) => u.username.equals(username)))
          .getSingleOrNull();

  Future<bool> canLogin(AppDatabase db, String u, String p) async =>
      (await db.authenticateUser(u, p)) != null;

  // ── mode switching (real classes, test hooks) ───────────────────────────
  void asClient() {
    ClientWriteInterceptor.setup();
    NetworkService.instance.debugSetModeForTests(NetworkMode.client);
    MirrorState.instance.debugSetForTests();
    _pointAtDeadServer();
  }

  void asMirror({bool configured = true}) {
    ClientWriteInterceptor.setup();
    NetworkService.instance.debugSetModeForTests(NetworkMode.mirror);
    MirrorState.instance.debugSetForTests(
      serverDisplayName: configured ? 'HQ-Test' : null,
      adminUserId: configured ? 1 : null,
      lastHandshakeAt: configured ? DateTime.now().toUtc() : null,
    );
    _pointAtDeadServer();
  }

  void _pointAtDeadServer() {
    NetworkService.instance.setServerAddress(_deadHost, port: _deadPort);
  }

  Future<void> dispose() async {
    ApiAuthMiddleware.closePairingWindow();
    SyncInterceptor.instance = null;
    SyncInterceptor.currentUserId = null;
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    MirrorState.instance.debugSetForTests();
    ServerProxy.instance.clearSessions();
    await host.close();
    await client.close();
  }
}

/// The device's calls to the main, answered by the real router (no sockets).
class _PeerMainPort implements MainAuthPort {
  _PeerMainPort(this.peers);
  final Peers peers;

  Future<MainSession> _session(shelf.Response r) async {
    final text = await r.readAsString();
    final json = text.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(text) as Map<String, dynamic>;
    final code = json['code'] as String?;
    if (r.statusCode == 200) {
      return MainSession(MainAuthOutcome.ok,
          token: json['token'] as String?,
          userId: (json['userId'] as num?)?.toInt());
    }
    return MainSession(switch ((r.statusCode, code)) {
      (401, _) => MainAuthOutcome.invalidCredentials,
      (403, 'password_change_required') => MainAuthOutcome.passwordChangeRequired,
      (403, 'branch_access_denied') => MainAuthOutcome.branchDenied,
      (429, _) => MainAuthOutcome.lockedOut,
      (409, _) => MainAuthOutcome.passwordRejected,
      _ => MainAuthOutcome.error,
    });
  }

  @override
  Future<MainSession> createSession(String username, String password) async =>
      _session(await peers.hostRaw('POST', '/api/auth/session',
          body: {'username': username, 'password': password}));

  @override
  Future<MainSession> changePassword(
          String username, String currentPassword, String newPassword) async =>
      _session(await peers.hostRaw('POST', '/api/auth/change-password', body: {
        'username': username,
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      }));

  @override
  Future<Map<String, dynamic>?> fetchUsers(String sessionToken) async {
    final uid = ApiSessionToken.verify(sessionToken);
    if (uid == null) return null;
    return peers.hostGet('/api/users', userId: uid);
  }
}

/// Builds the canonical fixture:
///  host   : admin(id 1, CUSTOM password), cashier1 (initial pw, force change),
///           acct1 (initial pw), mgr1 (custom role, access to BOTH branches)
///  client : fresh install — only the seeded admin/admin
Future<Peers> createPeers() async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  SharedPreferences.setMockInitialValues({'client_branch_id': 1});
  DiagnosticLogger.enableTestMode();
  ApiSessionToken.setKeyForTesting('peer-harness-session-key');
  ApiSessionToken.clearRevokedForTesting();
  ServerLoginThrottle.reset();
  ApiRateLimiter.reset();
  ApiAuthMiddleware.closePairingWindow();
  NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
  SyncInterceptor.instance = null;

  final host = AppDatabase.forTesting();
  final client = AppDatabase.forTesting();
  final p = Peers._(host, client, ApiHandler(host));

  Future<int> roleId(String name) async => (await (host.select(host.roles)
            ..where((r) => r.name.equals(name))
            ..limit(1))
          .getSingle())
      .id;
  p.cashierRoleId = await roleId('كاشير');
  p.accountantRoleId = await roleId('محاسب');
  p.branch1 = (await host.select(host.branches).get()).first.id;
  p.branch2 = await host.into(host.branches).insert(BranchesCompanion.insert(
      name: 'فرع ثانٍ', globalId: const Value('gid-br-repro-2')));
  p.managerRoleId = await host
      .into(host.roles)
      .insert(RolesCompanion.insert(name: 'مدير فروع (repro)'));

  // the custom role reaches the client via the roles sync that precedes users
  await client.into(client.roles).insert(RolesCompanion.insert(
      name: 'مدير فروع (repro)', id: Value(p.managerRoleId)));

  await host.updateUserPassword(userId: 1, newPassword: kAdminCustomPw);
  p.cashierId = await host.createUser(
      username: 'cashier1',
      password: kCashierInitialPw,
      displayName: 'كاشير',
      roleId: p.cashierRoleId,
      forcePasswordChange: true);
  p.accountantId = await host.createUser(
      username: 'acct1',
      password: kAccountantInitialPw,
      displayName: 'محاسب',
      roleId: p.accountantRoleId);
  p.managerId = await host.createUser(
      username: 'mgr1',
      password: kManagerPw,
      displayName: 'مدير فروع',
      roleId: p.managerRoleId);
  await host.setUserBranchAccess(p.cashierId, [p.branch1]);
  await host.setUserBranchAccess(p.accountantId, [p.branch1]);
  await host.setUserBranchAccess(p.managerId, [p.branch1, p.branch2]);
  return p;
}
