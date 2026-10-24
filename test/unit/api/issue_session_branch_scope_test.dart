// P1 / M1 (plan 2026-10-24): POST /api/auth/session is decided by the PAIRED
// DEVICE too - the branch a client is bound to, `mirror_console` on a mirror -
// and every issuance is audited (throttled) without a secret.
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/services/api/api_auth_support.dart';
import 'package:picpos_erp/services/role_grant_preflight_service.dart';

import '../../helpers/lan_host_harness.dart';

void main() {
  late LanHost host;
  late HostFixture fx;

  Future<LanDevice> device(String id, {String? kind, int? branch}) async {
    final d = LanDevice(host.direct, id);
    final offer = await host.issue(kind: kind, branchId: branch);
    expect((await d.pair(offer.code)).status, 200);
    return d;
  }

  setUp(() async {
    AuthAudit.resetForTesting();
    host = await LanHost.start();
    fx = await HostFixture.seed(host.db);
  });
  tearDown(() => host.close());

  test('a branch device refuses a user of another branch with '
      'branch_access_denied (and a code), before any forced-change answer',
      () async {
    final d = await device('c-1', kind: 'client', branch: fx.branch1);
    final r = await d.login('b2cashier', HostFixture.b2Pw);
    expect([r.status, r.code], [403, 'branch_access_denied']);
    final forced = await d.login('cashier1', kInitialPw);
    expect([forced.status, forced.code], [403, 'password_change_required']);
    expect((await d.login('acct1', HostFixture.acctPw)).status, 200);
  });

  test('the program owner (admin) is never refused by the device branch',
      () async {
    final d = await device('c-1', kind: 'client', branch: fx.branch2);
    expect((await d.login('admin', kHostAdminPw)).status, 200);
  });

  test('a user with NO branch assignment is refused on a branch device',
      () async {
    final none = await host.db.createUser(
        username: 'nobranch',
        password: 'No#Branch12345',
        displayName: 'n',
        roleId: fx.mgrRoleId);
    expect(none, isPositive);
    final d = await device('c-1', kind: 'client', branch: fx.branch1);
    final r = await d.login('nobranch', 'No#Branch12345');
    expect([r.status, r.code], [403, 'branch_access_denied']);
  });

  test('an admin-kind or unbound device does not apply the branch rule',
      () async {
    final d = await device('a-1', kind: 'admin');
    expect((await d.login('b2cashier', HostFixture.b2Pw)).status, 200);
  });

  test('a mirror admits only holders of mirror_console', () async {
    final m = await device('m-1', kind: 'mirror');
    final refused = await m.login('acct1', HostFixture.acctPw);
    expect([refused.status, refused.code], [403, 'mirror_console_denied']);
    expect((await m.login('mgr1', HostFixture.mgrPw)).status, 200);
    expect((await m.login('admin', kHostAdminPw)).status, 200,
        reason: 'the system admin role holds every permission');
  });

  test('the default grants give mirror_console to «مدير النظام» and «مدير '
      'مالي» only', () async {
    await RoleGrantPreflightService(host.db).grantMissingDefaults();
    final fm = await (host.db.select(host.db.roles)
          ..where((r) => r.name.equals('مدير مالي')))
        .getSingle();
    final fmUser = await host.db.createUser(
        username: 'fm1',
        password: 'Fin#Manager123',
        displayName: 'fm',
        roleId: fm.id);
    expect(await host.db.userHasPermission(fmUser, 'mirror_console'), isTrue);
    expect(await host.db.userHasPermission(fx.acctId, 'mirror_console'), isFalse);
    expect(await host.db.userHasPermission(fx.cashierId, 'mirror_console'),
        isFalse);
  });

  test('every issuance is audited once per user+device per 10 minutes, with '
      'no secret', () async {
    final d = await device('c-1', kind: 'client', branch: fx.branch1);
    await d.login('acct1', HostFixture.acctPw);
    await d.login('acct1', HostFixture.acctPw);
    final logs = await host.db.select(host.db.activityLogs).get();
    final issued = logs.where((l) => l.action == 'session_issued').toList();
    expect(issued, hasLength(1));
    expect(issued.single.description, contains('device=c-1'));
    expect(issued.single.description, contains('kind=client'));
    expect(issued.single.description, isNot(contains(HostFixture.acctPw)));
    expect(AuthAudit.shouldLogSession(fx.acctId, 'c-1',
        now: DateTime.now().add(const Duration(minutes: 11))), isTrue);
  });

  test('a failed login carries the invalid_credentials code', () async {
    final d = await device('c-1', kind: 'client', branch: fx.branch1);
    final r = await d.login('acct1', 'nope');
    expect([r.status, r.code], [401, 'invalid_credentials']);
    expect(r.json['error'], 'Invalid credentials');
  });
}
