// Audit 2026-10-23 axis A — SEC-001 / SEC-002 / SEC-011 / SEC-003 repro tests.
//
//  * SEC-001: renaming the built-in admin must NOT make `GET /api/users`
//    silently re-create a known-password `admin` system-admin account.
//  * SEC-002: `POST /api/auth/session` and `/api/auth/verify-admin` must refuse
//    accounts that still carry `force_password_change` (default credentials).
//  * SEC-003: a device session token must stop working once its user is
//    deactivated / locked / had the password changed.

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/api/api_handler.dart';
import 'package:ural_erp/services/api/api_session_token.dart';
import 'package:ural_erp/services/api/api_user_context.dart';
import 'package:ural_erp/services/api/server_login_throttle.dart';
import 'package:ural_erp/services/security_service.dart';

void main() {
  late AppDatabase db;
  late ApiHandler handler;

  setUp(() async {
    db = AppDatabase.forTesting();
    handler = ApiHandler(db);
    ApiSessionToken.setKeyForTesting('unit-test-session-key');
    ApiSessionToken.clearRevokedForTesting();
    ServerLoginThrottle.reset();
    // Force the lazy seed so the in-memory DB has its built-in admin.
    await db.select(db.users).get();
  });

  tearDown(() async {
    ApiSessionToken.clearKey();
    await db.close();
  });

  Future<shelf.Response> call(String method, String path,
      {Object? body, Map<String, Object>? context}) {
    return Future.value(handler.buildRouter().call(shelf.Request(
      method,
      Uri.parse('http://localhost$path'),
      body: body == null ? null : jsonEncode(body),
      context: context,
    )));
  }

  Future<int> addUser(
    String username,
    String password, {
    bool force = false,
    int roleId = 1,
  }) async {
    final hash = await SecurityService.hashPasswordArgon2(password);
    return db.into(db.users).insert(UsersCompanion.insert(
          username: username,
          passwordHash: hash,
          displayName: username,
          roleId: Value(roleId),
          isActive: const Value(true),
          forcePasswordChange: Value(force),
        ));
  }

  group('SEC-001 — no silent re-creation of admin/admin', () {
    test('renaming the built-in admin then GET /api/users creates no new user',
        () async {
      await (db.update(db.users)..where((u) => u.id.equals(1)))
          .write(const UsersCompanion(username: Value('owner')));
      final before = (await db.select(db.users).get()).length;

      final res = await call('GET', '/api/users');
      expect(res.statusCode, 200);

      final after = await db.select(db.users).get();
      expect(after.length, before, reason: 'user count must be unchanged');
      expect(after.where((u) => u.username == 'admin'), isEmpty,
          reason: 'a known-password admin must never be auto-created');
    });

    test('the __dup_1_admin rename-back repair still works', () async {
      await (db.update(db.users)..where((u) => u.id.equals(1)))
          .write(const UsersCompanion(username: Value('__dup_1_admin')));
      await call('GET', '/api/users');
      final row = await (db.select(db.users)..where((u) => u.id.equals(1)))
          .getSingle();
      expect(row.username, 'admin');
    });
  });

  group('SEC-002 — forced-change accounts get no API session', () {
    test('/api/auth/session refuses force_password_change users', () async {
      await addUser('temp', 'Temp#12345', force: true);
      final res = await call('POST', '/api/auth/session',
          body: {'username': 'temp', 'password': 'Temp#12345'});
      expect(res.statusCode, 403);
      final body = jsonDecode(await res.readAsString()) as Map;
      expect(body.containsKey('token'), isFalse);
      expect(body['code'], 'password_change_required');
    });

    test('/api/auth/verify-admin refuses force_password_change users',
        () async {
      await addUser('tempadm', 'Temp#12345', force: true);
      final res = await call('POST', '/api/auth/verify-admin',
          body: {'username': 'tempadm', 'password': 'Temp#12345'});
      expect(res.statusCode, 403);
    });

    test('a normal user still receives a session', () async {
      await addUser('normal', 'Normal#12345');
      final res = await call('POST', '/api/auth/session',
          body: {'username': 'normal', 'password': 'Normal#12345'});
      expect(res.statusCode, 200);
      final body = jsonDecode(await res.readAsString()) as Map;
      expect(body['token'], isA<String>());
    });
  });

  group('SEC-003 — device tokens are revocable server-side', () {
    test('deactivated user: requirePermission → 401', () async {
      final uid = await addUser('leaver', 'Leaver#12345');
      final token = ApiSessionToken.mint(uid);
      final verified = ApiSessionToken.verify(token);
      expect(verified, uid);
      await (db.update(db.users)..where((u) => u.id.equals(uid)))
          .write(const UsersCompanion(isActive: Value(false)));
      final req = shelf.Request('POST', Uri.parse('http://localhost/x'),
          context: {ApiUserCtx.userIdKey: uid});
      final denied =
          await ApiUserCtx.requirePermission(req, db, 'sales_create');
      expect(denied?.statusCode, 401);
    });

    test('locked user: requirePermission → 401', () async {
      final uid = await addUser('locked', 'Locked#12345');
      await (db.update(db.users)..where((u) => u.id.equals(uid)))
          .write(const UsersCompanion(isLocked: Value(true)));
      final req = shelf.Request('POST', Uri.parse('http://localhost/x'),
          context: {ApiUserCtx.userIdKey: uid});
      final denied =
          await ApiUserCtx.requirePermission(req, db, 'sales_create');
      expect(denied?.statusCode, 401);
    });

    test('revokeUser(user) invalidates previously minted tokens',
        () async {
      final t0 = DateTime.now().millisecondsSinceEpoch - 5000;
      final token = ApiSessionToken.mint(7, nowMs: t0);
      expect(ApiSessionToken.verify(token), 7);
      final revokedAt = DateTime.now().millisecondsSinceEpoch;
      ApiSessionToken.revokeUser(7, nowMs: revokedAt);
      expect(ApiSessionToken.verify(token), isNull);
      // A token minted after the revocation works again.
      final fresh = ApiSessionToken.mint(7, nowMs: revokedAt + 1);
      expect(ApiSessionToken.verify(fresh), 7);
    });

    test('device token TTL is short (<= 24h)', () {
      expect(ApiSessionToken.ttlMs, lessThanOrEqualTo(24 * 3600 * 1000));
    });
  });
}
