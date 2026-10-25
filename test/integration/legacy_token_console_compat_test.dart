// M2 (plan 2026-10-24): the console guard must NOT close the legacy shared
// token. A pre-M1 mirror / client that still presents the shared bearer (no
// paired device row => no `lanDeviceKind`) keeps working exactly as before:
// reads, session login and user feeds are untouched by the mirror_console rules.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/services/api/api_auth_middleware.dart';

import '../helpers/lan_host_harness.dart';

void main() {
  late LanHost host;
  late HostFixture fx;
  late String base;
  late LanDevice legacy;

  setUp(() async {
    ApiAuthMiddleware.closePairingWindow();
    host = await LanHost.start(legacyToken: true);
    fx = await HostFixture.seed(host.db);
    base = await host.serve();
    legacy = LanDevice(host.overHttp(base), 'old-mirror', rolesFrom: host.db)
      ..deviceToken = 'legacy-shared-token';
  });

  tearDown(() async {
    await legacy.dispose();
    await host.close();
  });

  test('the shared token still reads, signs a user in and feeds users', () async {
    expect((await legacy.get('/api/branches', withSession: false)).status, 200);
    // A user WITHOUT mirror_console signs in: the console rule is for paired
    // `mirror` devices only.
    final login = await legacy.login('acct1', HostFixture.acctPw);
    expect(login.status, isNot(403), reason: '$login');
    final users = await legacy.get('/api/users');
    expect(users.status, 200, reason: '$users');
  });

  test('a legacy caller is not subject to the console branch/actor rules',
      () async {
    final login = await legacy.login('admin', kHostAdminPw);
    expect(login.status, 200, reason: '$login');
    final r = await legacy.transport(
      'GET',
      '/api/branches',
      {...legacy.headers(), 'x-branch-id': '${fx.branch3}'},
      null,
    );
    expect(r.status, 200, reason: 'no mirror guard for the legacy bearer: $r');
    expect(jsonEncode(r.json), isNotEmpty);
  });
}
