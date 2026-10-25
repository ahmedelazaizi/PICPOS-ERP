// Host + paired-device harness for the credential / pairing tests (plan
// 2026-10-24, P1 + M1). NOT a test file.
//
// * [LanHost] is the main system: an in-memory `AppDatabase`, the REAL
//   `ApiHandler` router behind the REAL `ApiRateLimiter` + `ApiAuthMiddleware`
//   (device bearer, route policy, session token), and a `LanPairingService`.
//   It can be driven in-process ([LanHost.handler]) or over a real socket
//   ([LanHost.serve] -> `shelf_io`).
// * [LanDevice] is a peer with ITS OWN `AppDatabase` (a fresh install, with the
//   seeded `admin/admin`). It talks to the host only through HTTP headers /
//   bodies - exactly what a branch device or a mirror sends - and applies the
//   user feed with the production `UserSyncStrategy`.
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show InsertMode, Value, driftRuntimeOptions;
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'package:picpos_erp/core/logging/diagnostic_logger.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/api/api_auth_middleware.dart';
import 'package:picpos_erp/services/api/api_handler.dart';
import 'package:picpos_erp/services/api/api_rate_limiter.dart';
import 'package:picpos_erp/services/api/api_session_token.dart';
import 'package:picpos_erp/services/api/lan_pairing_api_handler.dart';
import 'package:picpos_erp/services/api/lan_pairing_service.dart';
import 'package:picpos_erp/services/api/server_login_throttle.dart';
import 'package:picpos_erp/services/password_collision_scanner.dart';
import 'package:picpos_erp/services/sync/strategies/user_sync_strategy.dart';

const kHostAdminPw = 'AdminCustom#2026';
const kInitialPw = 'Cash#Init123';

/// One API answer.
class ApiResp {
  ApiResp(this.status, this.body);
  final int status;
  final String body;
  Map<String, dynamic> get json {
    final d = jsonDecode(body);
    return d is Map<String, dynamic> ? d : <String, dynamic>{};
  }

  String? get code => json['code'] as String?;
  @override
  String toString() => '$status $body';
}

typedef Transport = Future<ApiResp> Function(
    String method, String path, Map<String, String> headers, String? body);

class LanHost {
  LanHost._(this.db, this.pairing);

  final AppDatabase db;
  final LanPairingService pairing;
  DateTime Function() clock = DateTime.now;
  late final shelf.Handler handler;
  HttpServer? _server;

  static Future<LanHost> start({
    bool legacyToken = false,
    DateTime Function()? now,
  }) async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    DiagnosticLogger.enableTestMode();
    ApiRateLimiter.reset();
    ServerLoginThrottle.reset();
    ApiSessionToken.setKeyForTesting('lan-host-harness-key');
    ApiSessionToken.clearRevokedForTesting();
    final db = AppDatabase.forTesting();
    await db.ensureLanPairingSchema();
    late LanHost host;
    final pairing = LanPairingService.forTesting(
      installSecret: 'per-install-secret-with-at-least-32-bytes',
      db: db,
      now: now == null ? null : () => host.clock(),
      hasPermission: (_, _) async => true,
    );
    host = LanHost._(db, pairing);
    if (now != null) host.clock = now;
    await pairing.initializeLegacyTransition();
    ApiAuthMiddleware.setPairingService(pairing);
    LanPairingApiHandler.setService(pairing);
    ApiAuthMiddleware.clearToken();
    if (legacyToken) ApiAuthMiddleware.setToken('legacy-shared-token');
    ApiAuthMiddleware.markReady();
    host.handler = const shelf.Pipeline()
        .addMiddleware(ApiRateLimiter.createMiddleware())
        .addMiddleware(ApiAuthMiddleware.createMiddleware())
        .addHandler(ApiHandler(db).buildRouter().call);
    return host;
  }

  /// Serves [handler] on loopback; returns the base URL.
  Future<String> serve() async {
    _server = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, 0);
    return 'http://127.0.0.1:${_server!.port}';
  }

  Future<PairingOffer> issue({
    String? kind,
    int? branchId,
    int actor = 1,
    String? fingerprint,
  }) =>
      pairing.issuePairingCode(
        serverHost: 'host.test',
        port: 8080,
        serverFingerprint: fingerprint,
        actorUserId: actor,
        deviceKind: kind,
        branchId: branchId,
      );

  /// In-process transport: the request goes through the full middleware chain.
  Transport get direct => (method, path, headers, body) async {
        final res = await handler(shelf.Request(
          method,
          Uri.parse('http://lan.test$path'),
          headers: headers,
          body: body,
        ));
        return ApiResp(res.statusCode, await res.readAsString());
      };

  /// Socket transport for a server started with [serve].
  Transport overHttp(String base) => (method, path, headers, body) async {
        final req = http.Request(method, Uri.parse('$base$path'))
          ..headers.addAll(headers);
        if (body != null) req.body = body;
        final res = await http.Response.fromStream(await req.send());
        return ApiResp(res.statusCode, res.body);
      };

  Future<void> close() async {
    // updateUserPassword fires a password-collision scan without awaiting it;
    // wait for exactly those scans (not a fixed sleep: Argon2 under load takes
    // longer than any guess) before the database goes away.
    await PasswordCollisionScanner.drain(db);
    await _server?.close(force: true);
    ApiAuthMiddleware.clearPairingService();
    ApiAuthMiddleware.clearReady();
    ApiAuthMiddleware.clearToken();
    LanPairingApiHandler.clearService();
    await db.close();
  }
}

class LanDevice {
  LanDevice(this.transport, this.id, {String? name, this.rolesFrom})
      : name = name ?? 'dev-$id';

  /// The host database whose roles reach the device before its users do (the
  /// roles sync precedes the users sync; the device needs them for the FK).
  final AppDatabase? rolesFrom;

  final Transport transport;
  final String id;
  final String name;

  /// The device's OWN database (a fresh install); created on first use.
  AppDatabase? _db;
  AppDatabase get db => _db ??= AppDatabase.forTesting();
  String? deviceToken;
  String? session;
  static const jsonHeader = {'content-type': 'application/json'};

  Map<String, String> headers({bool withSession = true, String? bearer}) => {
        ...jsonHeader,
        'authorization': 'Bearer ${bearer ?? deviceToken ?? ''}',
        'x-device-id': id,
        'x-device-name': name,
        if (withSession && session != null) 'x-session-token': session!,
      };

  Future<ApiResp> pair(String code, {String? kind, int? branchId}) async {
    final r = await transport(
      'POST',
      '/api/pair',
      {...jsonHeader, 'x-device-id': id},
      jsonEncode({
        'pairingCode': code,
        'deviceId': id,
        'deviceName': name,
        'deviceKind': ?kind,
        'branchId': ?branchId,
      }),
    );
    if (r.status == 200) deviceToken = r.json['token'] as String?;
    return r;
  }

  Future<ApiResp> post(String path, Object body, {bool withSession = true}) =>
      transport('POST', path, headers(withSession: withSession), jsonEncode(body));

  Future<ApiResp> put(String path, Object body) =>
      transport('PUT', path, headers(), jsonEncode(body));

  Future<ApiResp> get(String path, {bool withSession = true}) =>
      transport('GET', path, headers(withSession: withSession), null);

  /// `POST /api/auth/session`; on 200 the token becomes the device's session.
  Future<ApiResp> login(String username, String password) async {
    final r = await post(
        '/api/auth/session', {'username': username, 'password': password},
        withSession: false);
    if (r.status == 200) session = r.json['token'] as String?;
    return r;
  }

  /// `GET /api/users` and apply it with the production sync strategy.
  Future<ApiResp> syncUsers({bool withSession = true}) async {
    final r = await get('/api/users', withSession: withSession);
    if (r.status == 200) {
      for (final role in await (rolesFrom?.select(rolesFrom!.roles).get() ?? Future.value(<Role>[]))) {
        await db.into(db.roles).insert(
            RolesCompanion.insert(name: role.name, id: Value(role.id)),
            mode: InsertMode.insertOrIgnore);
      }
      await UserSyncStrategy(db).syncFromJson(r.json);
    }
    return r;
  }

  Future<bool> canLogin(String username, String password) async =>
      (await db.authenticateUser(username, password)) != null;

  Future<void> dispose() async {
    final d = _db;
    if (d == null) return;
    await PasswordCollisionScanner.drain(d);
    await d.close();
  }
}

/// The canonical host data used by the credential tests.
class HostFixture {
  late int branch1, branch2, branch3;
  late int cashierId; // branch 1, temporary password + force change
  late int acctId; // branch 1
  late int cashierB2Id; // branch 2
  late int mgrId; // branches 1 + 2, holds mirror_console
  late int outsiderId; // branch 3 only
  late int mgrRoleId;
  static const mgrPw = 'Mgr#Multi789';
  static const acctPw = 'Acct#Init456';
  static const b2Pw = 'B2#Cash12345';
  static const outsiderPw = 'Out#Side12345';

  static Future<HostFixture> seed(AppDatabase db) async {
    final f = HostFixture();
    Future<int> role(String n) async => (await (db.select(db.roles)
              ..where((r) => r.name.equals(n))
              ..limit(1))
            .getSingle())
        .id;
    f.branch1 = (await db.select(db.branches).get()).first.id;
    f.branch2 = await db.into(db.branches).insert(
        BranchesCompanion.insert(name: 'Branch 2', code: const Value('B2')));
    f.branch3 = await db.into(db.branches).insert(
        BranchesCompanion.insert(name: 'Branch 3', code: const Value('B3')));
    f.mgrRoleId = await db
        .into(db.roles)
        .insert(RolesCompanion.insert(name: 'مدير فروع (test)'));
    // Not a system role: holders of system roles are always part of every
    // branch's feed (by design), which would hide the branch scoping.
    final plainRole = await db
        .into(db.roles)
        .insert(RolesCompanion.insert(name: 'موظف فرع (test)'));
    final perms = await db.getAllPermissions();
    final mirror = perms.firstWhere((p) => p.code == 'mirror_console');
    await db.setRolePermissions(f.mgrRoleId, [mirror.id]);

    await db.updateUserPassword(userId: 1, newPassword: kHostAdminPw);
    f.cashierId = await db.createUser(
        username: 'cashier1',
        password: kInitialPw,
        displayName: 'Cashier',
        roleId: await role('كاشير'),
        forcePasswordChange: true);
    f.acctId = await db.createUser(
        username: 'acct1',
        password: acctPw,
        displayName: 'Accountant',
        roleId: await role('محاسب'));
    f.cashierB2Id = await db.createUser(
        username: 'b2cashier',
        password: b2Pw,
        displayName: 'B2',
        roleId: plainRole);
    f.mgrId = await db.createUser(
        username: 'mgr1',
        password: mgrPw,
        displayName: 'Manager',
        roleId: f.mgrRoleId);
    f.outsiderId = await db.createUser(
        username: 'outsider',
        password: outsiderPw,
        displayName: 'Outsider',
        roleId: plainRole);
    await db.setUserBranchAccess(f.cashierId, [f.branch1]);
    await db.setUserBranchAccess(f.acctId, [f.branch1]);
    await db.setUserBranchAccess(f.cashierB2Id, [f.branch2]);
    await db.setUserBranchAccess(f.mgrId, [f.branch1, f.branch2]);
    await db.setUserBranchAccess(f.outsiderId, [f.branch3]);
    return f;
  }
}