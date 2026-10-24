// P1 (plan 2026-10-24) on a REAL PostgreSQL: the self-service password change,
// the administrative reset, and the multi-branch `/api/users` feed use only
// Drift (no raw SQL), but the Argon2id write, `activity_logs` audit insert,
// `isIn(scope)` filter and the `users.last_modified_at` bump (the sync-pull
// watermark that carries the new hash to other devices) must hold on PG too.
@Tags(['pg'])
library;

import 'dart:convert';

import 'package:drift/drift.dart' as d;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;

import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/api/api_handler.dart';
import 'package:picpos_erp/services/api/api_session_token.dart';
import 'package:picpos_erp/services/api/api_user_context.dart';
import 'package:picpos_erp/services/api/server_login_throttle.dart';

import '_support/pg_fixture.dart';

void main() {
  late PgTestFixture fx;
  late ApiHandler handler;
  late int roleId, cashierId, b2Id, adminId;

  setUpAll(() async {
    fx = await bootPgTestSchema();
    ApiSessionToken.setKeyForTesting('pg-password-flow-key');
  });
  tearDownAll(() => fx.tearDown());

  setUp(() async {
    ServerLoginThrottle.reset();
    await fx.db.delete(fx.db.activityLogs).go();
    await fx.db.delete(fx.db.userBranchAccess).go();
    await fx.db.delete(fx.db.rolePermissions).go();
    await fx.db.delete(fx.db.users).go();
    await fx.db.delete(fx.db.roles).go();
    await fx.db.customStatement(
      "INSERT INTO branches (id, name) VALUES (2, 'B2'), (3, 'B3') "
      'ON CONFLICT (id) DO NOTHING',
    );
    final adminRole = await fx.db.into(fx.db.roles).insert(
        RolesCompanion.insert(name: 'مدير النظام', isSystemRole: const d.Value(true)));
    roleId = await fx.db.into(fx.db.roles).insert(RolesCompanion.insert(name: 'plain'));
    adminId = await fx.db.createUser(
        username: 'admin', password: 'Admin#Pass12345', displayName: 'a', roleId: adminRole);
    cashierId = await fx.db.createUser(
        username: 'cashier1',
        password: 'Cash#Init123',
        displayName: 'c',
        roleId: roleId,
        forcePasswordChange: true);
    b2Id = await fx.db.createUser(
        username: 'b2user', password: 'B2#User12345', displayName: 'b', roleId: roleId);
    await fx.db.setUserBranchAccess(cashierId, [2]);
    await fx.db.setUserBranchAccess(b2Id, [3]);
    handler = ApiHandler(fx.db);
  });

  Future<(int, Map<String, dynamic>)> call(String method, String path,
      {Object? body, Map<String, Object> ctx = const {}}) async {
    final res = await handler.buildRouter().call(shelf.Request(
      method,
      Uri.parse('http://localhost$path'),
      body: body == null ? null : jsonEncode(body),
      headers: {'content-type': 'application/json'},
      context: ctx,
    ));
    final text = await res.readAsString();
    return (res.statusCode, jsonDecode(text) as Map<String, dynamic>);
  }

  Future<DateTime?> lastModified(int id) async {
    final row = await fx.db
        .customSelect('SELECT last_modified_at FROM users WHERE id = ?',
            variables: [d.Variable<int>(id)])
        .getSingle();
    final v = row.data['last_modified_at'];
    return v is DateTime ? v : DateTime.tryParse('$v');
  }

  test('change-password: Argon2id, flag cleared, audit row, watermark bumped, '
      'device branch enforced', () async {
    final before = await lastModified(cashierId);
    await Future<void>.delayed(const Duration(milliseconds: 1100));

    final denied = await call('POST', '/api/auth/change-password',
        body: {
          'username': 'b2user',
          'currentPassword': 'B2#User12345',
          'newPassword': 'Other#Pass7890',
        },
        ctx: {'lanDeviceId': 'dev-1', 'lanDeviceKind': 'client', 'lanDeviceBranchId': 2});
    expect([denied.$1, denied.$2['code']], [403, 'branch_access_denied']);

    final ok = await call('POST', '/api/auth/change-password',
        body: {
          'username': 'cashier1',
          'currentPassword': 'Cash#Init123',
          'newPassword': 'My#NewPass456',
        },
        ctx: {'lanDeviceId': 'dev-1', 'lanDeviceKind': 'client', 'lanDeviceBranchId': 2});
    expect(ok.$1, 200, reason: '${ok.$2}');
    expect(ok.$2['passwordHash'], startsWith(r'$argon2id$'));
    expect(ApiSessionToken.verify(ok.$2['token'] as String), cashierId);

    final row = await (fx.db.select(fx.db.users)..where((u) => u.id.equals(cashierId))).getSingle();
    expect(row.forcePasswordChange, isFalse);
    expect(await fx.db.authenticateUser('cashier1', 'My#NewPass456'), isNotNull);
    expect(await fx.db.authenticateUser('cashier1', 'Cash#Init123'), isNull);

    final logs = await fx.db.select(fx.db.activityLogs).get();
    expect(logs.where((l) => l.action == 'password_changed_self'), hasLength(1));

    final after = await lastModified(cashierId);
    expect(after, isNotNull);
    expect(after!.isAfter(before!), isTrue,
        reason: 'the sync-pull watermark must advance so other devices get the hash');

    final pull = await call('GET', '/api/sync/pull?table=users&since=0',
        ctx: {ApiUserCtx.userIdKey: adminId});
    final rows = (pull.$2['rows'] as List).cast<Map<String, dynamic>>();
    final mine = rows.firstWhere((r) => r['username'] == 'cashier1');
    expect('${mine['password_hash']}', startsWith(r'$argon2id$'));
    expect(mine['force_password_change'] == 1 || mine['force_password_change'] == false,
        isTrue);
  });

  test('admin reset through PUT applies on PG and /api/users carries the flag '
      'and the multi-branch scope', () async {
    final put = await call('PUT', '/api/users/$b2Id',
        body: {'password': 'Reset#Pass123', 'forcePasswordChange': true},
        ctx: {ApiUserCtx.userIdKey: adminId});
    expect(put.$1, 200, reason: '${put.$2}');
    expect(await fx.db.authenticateUser('b2user', 'B2#User12345'), isNull);
    expect((await fx.db.authenticateUser('b2user', 'Reset#Pass123'))!.user.forcePasswordChange,
        isTrue);

    final mgr = await fx.db.createUser(
        username: 'mgr', password: 'Mgr#Pass123456', displayName: 'm', roleId: roleId);
    await fx.db.setUserBranchAccess(mgr, [2, 3]);
    final feed = await call('GET', '/api/users', ctx: {ApiUserCtx.userIdKey: mgr});
    final users = (feed.$2['users'] as List).cast<Map<String, dynamic>>();
    expect(users.map((u) => u['username']), containsAll(['cashier1', 'b2user', 'mgr']));
    expect(users.firstWhere((u) => u['username'] == 'b2user')['forcePasswordChange'], isTrue);
    expect(feed.$2['serverTime'], isA<int>());
  });
}
