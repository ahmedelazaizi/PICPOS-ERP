// P1 / M1 (plan 2026-10-24): GET /api/users scope.
//  * MIR-010 (was REPRO-R3-j): a multi-branch manager receives the users of ALL
//    his granted branches, not only the first one.
//  * a device bound to a branch receives that branch only (its credentials);
//  * the fail-closed sentinel is not widened; an explicit in-scope branch_id
//    still narrows;
//  * the feed carries forcePasswordChange + serverTime and never the PIN.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;

import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/services/api/api_handler.dart';
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

  Future<Map<String, dynamic>> feed(String query,
      {int? userId, Map<String, Object> ctx = const {}}) async {
    final res = await router(shelf.Request(
      'GET',
      Uri.parse('http://localhost/api/users$query'),
      context: {ApiUserCtx.userIdKey: ?userId, ...ctx},
    ));
    expect(res.statusCode, 200);
    return jsonDecode(await res.readAsString()) as Map<String, dynamic>;
  }

  List<String> names(Map<String, dynamic> j) =>
      [for (final u in j['users'] as List) (u as Map)['username'] as String];

  test('REPRO-R3-j (moved): a multi-branch manager gets the users of BOTH '
      'granted branches', () async {
    final other = await host.db.createUser(
        username: 'b2second',
        password: 'B2#Second12345',
        displayName: 'b2s',
        roleId: fx.mgrRoleId);
    await host.db.setUserBranchAccess(other, [fx.branch2]);
    final n = names(await feed('', userId: fx.mgrId));
    expect(n, containsAll(['mgr1', 'cashier1', 'acct1', 'b2cashier', 'b2second']));
    expect(n, isNot(contains('outsider')),
        reason: 'branch 3 is not granted to the manager');
  });

  test('an explicit branch_id inside the scope still narrows to that branch',
      () async {
    final b1 = await host.db.createUser(
        username: 'b1plain',
        password: 'B1#Plain12345',
        displayName: 'b1',
        roleId: fx.mgrRoleId);
    await host.db.setUserBranchAccess(b1, [fx.branch1]);
    final n = names(await feed('?branch_id=${fx.branch2}', userId: fx.mgrId));
    expect(n, contains('b2cashier'));
    expect(n, isNot(contains('b1plain')));
    expect(names(await feed('', userId: fx.mgrId)), contains('b1plain'));
  });

  test('a user with no assignment stays fail-closed (sentinel, not widened)',
      () async {
    final lone = await host.db.createUser(
        username: 'lone',
        password: 'Lone#Pass12345',
        displayName: 'l',
        roleId: fx.mgrRoleId);
    final n = names(await feed('', userId: lone));
    expect(n, isNot(containsAll(['acct1', 'b2cashier'])));
    expect(n, isNot(contains('outsider')));
  });

  test('a device bound to a branch gets that branch only, even for an admin '
      'session', () async {
    final n = names(await feed('', userId: 1, ctx: {
      'lanDeviceBranchId': fx.branch1,
      'lanDeviceKind': 'client',
    }));
    expect(n, containsAll(['admin', 'cashier1', 'acct1', 'mgr1']));
    expect(n, isNot(contains('b2cashier')));
    expect(n, isNot(contains('outsider')));
  });

  test('a mirror device is not branch-bound: the manager keeps his full scope',
      () async {
    final n = names(await feed('', userId: fx.mgrId, ctx: {
      'lanDeviceKind': 'mirror',
    }));
    expect(n, containsAll(['cashier1', 'b2cashier']));
  });

  test('forcePasswordChange + serverTime are present, the PIN never is',
      () async {
    final j = await feed('', userId: 1);
    final cashier = (j['users'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((u) => u['username'] == 'cashier1');
    expect(cashier['forcePasswordChange'], isTrue);
    final acct = (j['users'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((u) => u['username'] == 'acct1');
    expect(acct['forcePasswordChange'], isFalse);
    expect(cashier.containsKey('pin'), isFalse);
    final t = j['serverTime'] as int;
    expect((DateTime.now().millisecondsSinceEpoch - t).abs(), lessThan(60000));
  });

  test('without identity and without the pairing window no credential leaves',
      () async {
    final j = await feed('');
    for (final u in (j['users'] as List).cast<Map<String, dynamic>>()) {
      expect(u.containsKey('passwordHash'), isFalse);
      expect(u.containsKey('cardCode'), isFalse);
    }
  });
}
