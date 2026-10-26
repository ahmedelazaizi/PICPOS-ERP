// SEC-006 / gate G-3: the legacy shared LAN bearer is a server setting.
// New servers start with it OFF; a server provisioned before this setting
// existed keeps it ON (a missing key means ON); when OFF the middleware
// refuses it with 401 `legacy_token_disabled` and the telemetry still counts
// the attempt (device, user-agent, last seen). Real host, real middleware.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/api/api_auth_middleware.dart';
import 'package:picpos_erp/services/api/lan_pairing_service.dart';
import 'package:picpos_erp/services/permission_enforcer.dart';

import '../helpers/lan_host_harness.dart';

void main() {
  late LanHost host;
  const legacy = 'legacy-shared-token';

  Future<ApiResp> callLegacy(String device, {String ua = 'okhttp/4.12'}) =>
      host.direct('GET', '/api/users', {
        'authorization': 'Bearer $legacy',
        'x-device-id': device,
        'x-device-name': 'Tablet $device',
        'user-agent': ua,
      }, null);

  setUp(() {
    LegacyTokenTelemetry.instance.reset();
  });
  tearDown(() async => host.close());

  test('a NEW server refuses the legacy bearer: 401 legacy_token_disabled, '
      'and the refused attempt is counted with device + user-agent', () async {
    host = await LanHost.start(); // fresh, provisioned by this version
    ApiAuthMiddleware.setToken(legacy);
    expect(await host.pairing.legacyTokenEnabled(), isFalse);

    final r = await callLegacy('old-tablet', ua: 'Dalvik/2.1');
    expect(r.status, 401, reason: '$r');
    expect(r.json['error'], 'legacy_token_disabled');

    final t = LegacyTokenTelemetry.instance;
    expect(t.refusedRequests, 1);
    final a = t.attempts.single;
    expect(a.deviceId, 'old-tablet');
    expect(a.userAgent, 'Dalvik/2.1');
    expect(a.refused, 1);
    expect(a.accepted, 0);
    expect(a.lastSeen, isNotNull);
    // A refused attempt does not register the device as a legacy user.
    expect((await host.pairing.legacyUsage()).inUse, isFalse);
  });

  test('a server provisioned BEFORE the setting existed keeps the legacy '
      'bearer ON (missing key = ON)', () async {
    host = await LanHost.start(legacyToken: true);
    await host.db.customStatement(
        "DELETE FROM settings WHERE key = 'lan_legacy_token_enabled'");
    expect(await host.pairing.legacyTokenEnabled(), isTrue);
    final r = await callLegacy('old-tablet');
    expect(r.status, 200, reason: '$r');
    expect(LegacyTokenTelemetry.instance.attempts.single.accepted, 1);
    expect((await host.pairing.legacyUsage()).inUse, isTrue);
  });

  test('turning it OFF refuses legacy devices at once but paired devices '
      'keep working; turning it ON again restores the legacy bearer',
      () async {
    host = await LanHost.start(legacyToken: true);
    final dev = LanDevice(host.direct, 'paired-1');
    final offer = await host.issue();
    expect((await dev.pair(offer.code)).status, 200);
    expect((await callLegacy('old-tablet')).status, 200);

    await host.pairing.setLegacyTokenEnabled(false, actorUserId: 1);
    final refused = await callLegacy('old-tablet');
    expect(refused.status, 401);
    expect(refused.json['error'], 'legacy_token_disabled');
    expect((await dev.get('/api/users', withSession: false)).status, 200);

    await host.pairing.setLegacyTokenEnabled(true, actorUserId: 1);
    expect((await callLegacy('old-tablet')).status, 200);
    final a = LegacyTokenTelemetry.instance.attempts
        .singleWhere((x) => x.deviceId == 'old-tablet');
    expect(a.accepted, 2);
    expect(a.refused, 1);
  });

  test('a wrong bearer is still a plain 403, not a legacy refusal', () async {
    host = await LanHost.start();
    ApiAuthMiddleware.setToken(legacy);
    final r = await host.direct('GET', '/api/users', {
      'authorization': 'Bearer nope',
      'x-device-id': 'x',
    }, null);
    expect(r.status, 403);
    expect(LegacyTokenTelemetry.instance.refusedRequests, 0);
  });

  test('toggling needs devices_pair_manage', () async {
    host = await LanHost.start(legacyToken: true);
    final locked = LanPairingService.forTesting(
      installSecret: 'per-install-secret-with-at-least-32-bytes',
      db: host.db,
      hasPermission: (_, _) async => false,
    );
    await expectLater(locked.setLegacyTokenEnabled(false, actorUserId: 2),
        throwsA(isA<PermissionDeniedException>()));
    expect(await locked.legacyTokenEnabled(), isTrue);
  });
}
