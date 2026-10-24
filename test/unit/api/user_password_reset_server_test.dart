// RESET-001, server half (plan 2026-10-24): PUT /api/users/<id> used to IGNORE
// a `password` in the body while answering success. It now applies it under the
// same `users_manage` gate as POST /api/users/<id>/password, or refuses
// honestly; the forced-change flag propagates; sessions of the user die.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;

import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/services/api/api_handler.dart';
import 'package:picpos_erp/services/api/api_session_token.dart';
import 'package:picpos_erp/services/api/api_user_context.dart';

import '../../helpers/lan_host_harness.dart';

void main() {
  late LanHost host;
  late HostFixture fx;
  late shelf.Handler router;

  setUp(() async {
    host = await LanHost.start();
    fx = await HostFixture.seed(host.db);
    router = ApiHandler(host.db).buildRouter().call;
  });
  tearDown(() => host.close());

  Future<ApiResp> call(String method, String path, Map<String, Object?> body,
      {int? as}) async {
    final res = await router(shelf.Request(
      method,
      Uri.parse('http://localhost$path'),
      body: jsonEncode(body),
      headers: {'content-type': 'application/json'},
      context: {ApiUserCtx.userIdKey: ?as},
    ));
    return ApiResp(res.statusCode, await res.readAsString());
  }

  test('PUT with a password APPLIES it (the old one stops working)', () async {
    final r = await call('PUT', '/api/users/${fx.acctId}',
        {'password': 'Reset#Pass123'}, as: 1);
    expect(r.status, 200, reason: '$r');
    expect(await host.db.authenticateUser('acct1', HostFixture.acctPw), isNull);
    expect(await host.db.authenticateUser('acct1', 'Reset#Pass123'), isNotNull);
  });

  test('PUT password + forcePasswordChange:true leaves the flag set', () async {
    await call('PUT', '/api/users/${fx.acctId}',
        {'password': 'Reset#Pass123', 'forcePasswordChange': true}, as: 1);
    final u = await host.db.getUserByUsername('acct1');
    expect(u!.user.forcePasswordChange, isTrue);
  });

  test('PUT forcePasswordChange alone sets/clears the flag, password untouched',
      () async {
    await call('PUT', '/api/users/${fx.acctId}', {'forcePasswordChange': true},
        as: 1);
    var u = await host.db.getUserByUsername('acct1');
    expect(u!.user.forcePasswordChange, isTrue);
    expect(await host.db.authenticateUser('acct1', HostFixture.acctPw), isNotNull);
    await call('PUT', '/api/users/${fx.acctId}', {'forcePasswordChange': false},
        as: 1);
    u = await host.db.getUserByUsername('acct1');
    expect(u!.user.forcePasswordChange, isFalse);
  });

  test('refusals are honest and change nothing: 403 without users_manage, 400 '
      'for a non-string/empty password, 409 for a password in use', () async {
    final denied = await call('PUT', '/api/users/${fx.cashierId}',
        {'password': 'Reset#Pass123'}, as: fx.acctId);
    expect(denied.status, 403);
    expect((await call('PUT', '/api/users/${fx.acctId}', {'password': ''}, as: 1))
            .status,
        400);
    expect((await call('PUT', '/api/users/${fx.acctId}', {'password': 12345}, as: 1))
            .status,
        400);
    final dup = await call(
        'PUT', '/api/users/${fx.acctId}', {'password': HostFixture.b2Pw}, as: 1);
    expect([dup.status, dup.code], [409, 'password_rejected']);
    expect(await host.db.authenticateUser('acct1', HostFixture.acctPw), isNotNull);
    expect(await host.db.authenticateUser('cashier1', kInitialPw), isNotNull);
  });

  test('a real password change revokes the user\'s sessions', () async {
    final session = ApiSessionToken.mint(fx.acctId);
    await call('PUT', '/api/users/${fx.acctId}', {'password': 'Reset#Pass123'},
        as: 1);
    expect(ApiSessionToken.verify(session), isNull);
  });

  test('POST /password honours forcePasswordChange and the same refusals',
      () async {
    final ok = await call('POST', '/api/users/${fx.acctId}/password',
        {'password': 'Reset#Pass123', 'forcePasswordChange': true}, as: 1);
    expect(ok.status, 200, reason: '$ok');
    expect((await host.db.getUserByUsername('acct1'))!.user.forcePasswordChange,
        isTrue);
    final missing =
        await call('POST', '/api/users/${fx.acctId}/password', {}, as: 1);
    expect(missing.status, 400);
    final dup = await call('POST', '/api/users/${fx.acctId}/password',
        {'password': HostFixture.b2Pw}, as: 1);
    expect(dup.status, 409);
  });

  test('the bootstrap admin guards still hold for PUT', () async {
    final r = await call('PUT', '/api/users/1', {'isActive': false}, as: 1);
    expect(r.status, 403);
  });
}
