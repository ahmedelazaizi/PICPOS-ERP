// M2 (plan 2026-10-24): the branch-manager console against a REAL in-process
// host (the production router behind the production middleware, served over a
// loopback socket by shelf_io for the multi-branch scenario).
//
//  * branch context: the manager sees exactly the branches in his scope, the
//    server refuses a branch outside it (header and body), and the users /
//    assignment feeds follow the requested branch;
//  * acting user: a mirror write is recorded under the SIGNED-IN manager, never
//    the pairing admin, and a body naming somebody else is refused;
//  * the console permission is re-checked on every request; a revoked mirror is
//    refused; a write needs a session.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/api/api_auth_middleware.dart';

import '../helpers/lan_host_harness.dart';

void main() {
  late LanHost host;
  late HostFixture fx;
  late String base;
  late Transport http;
  final devices = <LanDevice>[];

  setUp(() async {
    host = await LanHost.start();
    fx = await HostFixture.seed(host.db);
    base = await host.serve();
    http = host.overHttp(base);
    // The manager also holds the permission of the write the test performs.
    final perms = await host.db.getAllPermissions();
    await host.db.setRolePermissions(fx.mgrRoleId, [
      for (final p in perms)
        if (const {'mirror_console', 'pos_expense', 'users_manage'}
            .contains(p.code))
          p.id
    ]);
  });

  tearDown(() async {
    for (final d in devices) {
      await d.dispose();
    }
    devices.clear();
    await host.close();
  });

  Future<LanDevice> mirror(String id, {String user = 'mgr1', String? pw}) async {
    final m = LanDevice(http, id, rolesFrom: host.db);
    devices.add(m);
    expect((await m.pair((await host.issue(kind: 'mirror')).code)).status, 200);
    final r = await m.login(user, pw ?? HostFixture.mgrPw);
    expect(r.status, 200, reason: '$user signs in on the console: $r');
    return m;
  }

  Future<ApiResp> call(
    LanDevice m,
    String method,
    String path, {
    int? branch,
    Object? body,
    bool session = true,
  }) =>
      m.transport(
        method,
        path,
        {
          ...m.headers(withSession: session),
          if (branch != null) 'x-branch-id': '$branch',
        },
        body == null ? null : jsonEncode(body),
      );

  List<String> usernames(ApiResp r) =>
      [for (final u in r.json['users'] as List) (u as Map)['username'] as String];

  group('current branch (multi-branch manager)', () {
    test('the console context lists exactly the manager\'s branches', () async {
      final m = await mirror('m-1');
      final r = await call(m, 'GET', '/api/mirror/context');
      expect(r.status, 200, reason: '$r');
      final ids = [for (final b in r.json['branches'] as List) (b as Map)['id']];
      expect(ids, [fx.branch1, fx.branch2]);
      expect(ids, isNot(contains(fx.branch3)));
      expect(r.json['fullAccess'], isFalse);
      expect(r.json['canConsole'], isTrue);
      expect(r.json['defaultBranchId'], anyOf(fx.branch1, fx.branch2));
    });

    test('the owner (full access) sees every branch', () async {
      final m = await mirror('m-admin', user: 'admin', pw: kHostAdminPw);
      final r = await call(m, 'GET', '/api/mirror/context');
      expect(r.json['fullAccess'], isTrue);
      expect((r.json['branches'] as List).length, 3);
    });

    test('a branch outside the scope is refused in the header; inside passes',
        () async {
      final m = await mirror('m-1');
      expect((await call(m, 'GET', '/api/branches', branch: fx.branch2)).status, 200);
      final out = await call(m, 'GET', '/api/branches', branch: fx.branch3);
      expect([out.status, out.code], [403, 'branch_access_denied']);
      final bad = await call(m, 'GET', '/api/branches', branch: -4);
      expect([bad.status, bad.code], [400, 'invalid_branch']);
    });

    test('the users feed and the assignment feed follow the current branch',
        () async {
      // custom (non-system) role: system-role holders are in EVERY branch feed
      final plain = await (host.db.select(host.db.roles)
            ..where((r) => r.name.equals('موظف فرع (test)')))
          .getSingle();
      final b1staff = await host.db.createUser(
          username: 'b1staff',
          password: 'B1#Staff12345',
          displayName: 'B1',
          roleId: plain.id);
      await host.db.setUserBranchAccess(b1staff, [fx.branch1]);
      final m = await mirror('m-1');
      final all = usernames(await call(m, 'GET', '/api/users'));
      expect(all, containsAll(['b1staff', 'acct1', 'b2cashier', 'mgr1']));
      expect(all, isNot(contains('outsider')),
          reason: 'branch 3 is outside the manager scope');

      final b1 = usernames(await call(m, 'GET', '/api/users?branch_id=${fx.branch1}'));
      expect(b1, containsAll(['b1staff', 'mgr1']));
      expect(b1, isNot(contains('b2cashier')));

      final b2 = usernames(await call(m, 'GET', '/api/users?branch_id=${fx.branch2}'));
      expect(b2, containsAll(['b2cashier', 'mgr1']));
      expect(b2, isNot(contains('b1staff')));

      final acc = await call(m, 'GET', '/api/user-branch-access');
      final branches = {
        for (final a in acc.json['user_branch_access'] as List) (a as Map)['branchId']
      };
      expect(branches, {fx.branch1, fx.branch2},
          reason: 'branch 3 assignments are not served to this manager');
    });

    test('a write body naming a branch outside the scope is refused; inside '
        'the branch is accepted', () async {
      final m = await mirror('m-1');
      final out = await call(m, 'POST', '/api/expenses',
          branch: fx.branch2,
          body: {'amount': 10, 'category': 'x', 'branchId': fx.branch3});
      expect([out.status, out.code], [403, 'branch_access_denied']);
      final ok = await call(m, 'POST', '/api/expenses',
          branch: fx.branch2,
          body: {'amount': 10, 'category': 'x', 'branchId': fx.branch2});
      expect(ok.status, 200, reason: '$ok');
    });
  });

  group('acting user', () {
    test('a mirror write is recorded under the signed-in manager, not the '
        'pairing admin', () async {
      final m = await mirror('m-1');
      const gid = 'gid-attr-1';
      final r = await call(m, 'POST', '/api/expenses',
          branch: fx.branch1,
          body: {
            'amount': 25,
            'category': 'attr',
            'globalId': gid,
            'branchId': fx.branch1,
          });
      expect(r.status, 200, reason: '$r');
      final row = await (host.db.select(host.db.safeTransactions)
            ..where((t) => t.globalId.equals(gid)))
          .getSingle();
      expect(row.userId, fx.mgrId);
      expect(row.userId, isNot(1));
    });

    test('a body that names another user (or actor) is refused', () async {
      final m = await mirror('m-1');
      for (final key in ['userId', 'actorUserId']) {
        final r = await call(m, 'POST', '/api/expenses',
            body: {'amount': 5, 'category': 'x', key: 1});
        expect([r.status, r.code], [403, 'actor_mismatch'], reason: key);
      }
      final same = await call(m, 'POST', '/api/expenses',
          body: {'amount': 5, 'category': 'x', 'userId': fx.mgrId});
      expect(same.status, 200, reason: 'his own id is fine');
    });

    test('a device-local user id is tolerated ONLY when the body\'s identity '
        'stamp names the signed-in user (and is rewritten to the session id)',
        () async {
      final m = await mirror('m-1');
      final ok = await call(m, 'POST', '/api/expenses', body: {
        'amount': 5,
        'category': 'x',
        'globalId': 'gid-local-id',
        'userId': 999, // the device's own id for the same person
        'createdByUsername': 'mgr1',
      });
      expect(ok.status, 200, reason: '$ok');
      final row = await (host.db.select(host.db.safeTransactions)
            ..where((t) => t.globalId.equals('gid-local-id')))
          .getSingle();
      expect(row.userId, fx.mgrId);
      final forged = await call(m, 'POST', '/api/expenses', body: {
        'amount': 5,
        'category': 'x',
        'userId': 1,
        'createdByUsername': 'admin',
      });
      expect([forged.status, forged.code], [403, 'actor_mismatch']);
    });
    test('administrative user calls keep their TARGET userId (user '
        'management from a mirror goes through the main)', () async {
      final m = await mirror('m-1');
      final r = await call(m, 'PUT', '/api/users/${fx.cashierB2Id}',
          body: {'displayName': 'Renamed by mgr', 'userId': fx.cashierB2Id});
      expect(r.status, 200, reason: '$r');
      final u = await host.db.getUserById(fx.cashierB2Id);
      expect(u!.user.displayName, 'Renamed by mgr');
    });

    test('a write without a session is refused honestly', () async {
      final m = await mirror('m-1');
      final r = await call(m, 'POST', '/api/expenses',
          body: {'amount': 5, 'category': 'x'}, session: false);
      expect([r.status, r.code], [401, 'session_required']);
      expect((await call(m, 'GET', '/api/branches', session: false)).status, 200,
          reason: 'reference reads stay open for the boot pull');
    });
  });

  group('authority', () {
    test('mirror_console is re-checked on every request', () async {
      final m = await mirror('m-1');
      expect((await call(m, 'GET', '/api/users')).status, 200);
      await host.db.setRolePermissions(fx.mgrRoleId, const []);
      final r = await call(m, 'GET', '/api/users');
      expect([r.status, r.code], [403, 'mirror_console_denied']);
    });

    test('a user without the console permission cannot sign in on a mirror',
        () async {
      final m = LanDevice(http, 'm-2', rolesFrom: host.db);
      devices.add(m);
      await m.pair((await host.issue(kind: 'mirror')).code);
      final r = await m.login('acct1', HostFixture.acctPw);
      expect([r.status, r.code], [403, 'mirror_console_denied']);
    });

    test('a revoked mirror is refused (device_revoked) and another mirror is '
        'not affected', () async {
      final a = await mirror('m-1');
      final b = await mirror('m-2');
      await host.pairing.revoke('m-1', actorUserId: 1);
      final r = await call(a, 'GET', '/api/mirror/context');
      expect([r.status, r.body], [401, contains('device_revoked')]);
      expect((await call(b, 'GET', '/api/mirror/context')).status, 200);
    });

    test('the realtime mode comes from the pairing row, not the query string',
        () async {
      await mirror('m-1');
      final c = LanDevice(http, 'c-1');
      devices.add(c);
      await c.pair((await host.issue(kind: 'client', branchId: fx.branch1)).code);
      expect((await ApiAuthMiddleware.pairedDevice('m-1'))!.deviceKind, 'mirror');
      final client = (await ApiAuthMiddleware.pairedDevice('c-1'))!;
      expect([client.deviceKind, client.branchId], ['client', fx.branch1]);
      expect(await ApiAuthMiddleware.pairedDevice('nobody'), isNull);
    });
  });
}
