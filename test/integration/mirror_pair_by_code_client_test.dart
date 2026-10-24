// M1 client side (plan 2026-10-24): `MirrorPairingService.pairWithCode` /
// `ClientLinkService.pairMirrorWithCode` against a REAL host socket.
// The mirror receives a per-device token (no `/api/health` shared key, no
// admin login), is recorded in MirrorState, and the token is revocable.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:picpos_erp/services/api/lan_pairing_service.dart';
import 'package:picpos_erp/services/device_identity_service.dart';
import 'package:picpos_erp/services/mirror_pairing_service.dart';
import 'package:picpos_erp/services/mirror_state.dart';
import 'package:picpos_erp/services/network_service.dart';
import 'package:picpos_erp/services/server_proxy.dart';
import 'package:picpos_erp/services/setup/client_link_service.dart';

import '../helpers/lan_host_harness.dart';

void main() {
  late LanHost host;
  late int port;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    DeviceIdentityService.instance.adoptForPairing('mirror-laptop-1');
    ServerProxy.instance.setApiToken(null);
    MirrorState.instance.debugSetForTests();
    host = await LanHost.start();
    await HostFixture.seed(host.db);
    port = Uri.parse(await host.serve()).port;
  });

  tearDown(() async {
    ServerProxy.instance.setApiToken(null);
    MirrorState.instance.debugSetForTests();
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    await host.close();
  });

  test('a mirror pairs by code: own device token, MirrorState set, the token '
      'is the one the host revokes', () async {
    final offer = await host.issue(kind: 'mirror');
    final r = await MirrorPairingService.instance.pairWithCode(
      host: '127.0.0.1',
      port: port,
      code: offer.code,
      deviceName: 'Manager laptop',
    );
    expect(r.isSuccess, isTrue, reason: '${r.outcome} ${r.message}');
    expect(MirrorState.instance.isConfigured, isTrue);
    expect(r.message, isNull);
    expect(MirrorState.instance.adminUserId, isNull,
        reason: 'no admin identity is stamped any more');

    final token = ServerProxy.instance.apiToken;
    expect(token, isNotEmpty);
    expect(token, isNot('legacy-shared-token'));
    final row = await host.pairing.deviceById('mirror-laptop-1');
    expect([row!.deviceKind, row.branchId, row.revoked], ['mirror', null, false]);
    expect(
        await host.pairing.verifyDeviceToken(token: token!, deviceId: 'mirror-laptop-1'),
        isTrue);

    await host.pairing.revoke('mirror-laptop-1', actorUserId: 1);
    expect(
        await host.pairing.verifyDeviceToken(token: token, deviceId: 'mirror-laptop-1'),
        isFalse);
  });

  test('a wrong code and a missing code fail without touching MirrorState',
      () async {
    final wrong = await MirrorPairingService.instance
        .pairWithCode(host: '127.0.0.1', port: port, code: 'WRONG123');
    expect(wrong.isSuccess, isFalse);
    expect(wrong.outcome, MirrorPairingOutcome.pairingFailed);
    final empty = await MirrorPairingService.instance
        .pairWithCode(host: '127.0.0.1', port: port, code: ' ');
    expect(empty.outcome, MirrorPairingOutcome.missingFields);
    expect(MirrorState.instance.isConfigured, isFalse);
  });

  test('a client or legacy code cannot pair a mirror', () async {
    final client = await host.issue(kind: 'client', branchId: 1);
    final r = await MirrorPairingService.instance.pairWithCode(
      host: '127.0.0.1',
      port: port,
      code: client.code,
    );
    expect(r.outcome, MirrorPairingOutcome.pairingFailed);
    expect(await host.pairing.deviceById('mirror-laptop-1'), isNull,
        reason: 'the mirror states its kind; a client code is refused');
    expect(MirrorState.instance.isConfigured, isFalse);
    // ...and the refused attempt did not burn the code.
    final c = LanDevice(host.overHttp('http://127.0.0.1:$port'), 'c-1');
    expect((await c.pair(client.code)).status, 200);
    await c.dispose();
  });

  test('ClientLinkService.pairMirrorWithCode reports paired / pairFailed',
      () async {
    final svc = ClientLinkService(
        db: host.db, loadBranches: () async => const []);
    final ok = await svc.pairMirrorWithCode(
        host: '127.0.0.1', port: port, code: (await host.issue(kind: 'mirror')).code);
    expect(ok.outcome, ClientLinkOutcome.paired, reason: '${ok.message}');
    final bad = await svc.pairMirrorWithCode(
        host: '127.0.0.1', port: port, code: 'NOPE1234');
    expect(bad.outcome, ClientLinkOutcome.pairFailed);
    expect(bad.ok, isFalse);
  });
}
