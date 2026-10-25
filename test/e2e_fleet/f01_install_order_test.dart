// F1 - INSTALL ORDER of the owner's fleet: main first, then the branch devices
// (accountant, cashier) paired as client for B1, then the mirror. Everything is
// driven by the production services over real HTTP (see fleet_harness.dart).
@Timeout(Duration(minutes: 4))
library;

import 'dart:io' show HttpOverrides;

import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/services/api/lan_pairing_service.dart';
import 'package:picpos_erp/services/deployment/provisioning_record.dart';
import 'package:picpos_erp/services/mirror_state.dart';
import 'package:picpos_erp/services/network_service.dart';

import '../helpers/fleet_harness.dart';
import '../helpers/lan_host_harness.dart';

void main() {
  Fleet.bindEnvironment();
  setUpAll(() => HttpOverrides.global = null);

  late Fleet fleet;
  setUp(() async => fleet = await Fleet.startMain());
  tearDown(() => fleet.dispose());

  test('F1.1 the main is provisioned first: company, branches, roles, users; '
      'committed as server with a device record', () async {
    final db = fleet.main.db;
    expect(await db.getSettingValue('company_name'), 'شركة الأسطول');
    expect(await db.getSettingValue('system_currency'), 'JOD');
    expect(await db.getSettingValue('network_mode'), 'server');
    final rec = await ProvisioningStore.read(db);
    expect(rec?.mode, 'server');
    final names = (await db.select(db.branches).get()).map((b) => b.code).toSet();
    expect(names, containsAll(['B1', 'B2']));
    for (final u in ['accountant', 'cashier', 'branchadmin', 'manager', 'b2emp']) {
      expect(await db.getUserByUsername(u), isNotNull, reason: u);
    }
    expect(await db.authenticateUser('admin', 'admin'), isNull,
        reason: 'the main never keeps admin/admin');
    expect(await db.authenticateUser('admin', kMainAdminPw), isNotNull);
  });

  test('F1.2 pairing codes are bound to branch + kind: a code never lets the '
      'device choose another branch or kind', () async {
    final clientCode = await fleet.main.issue(kind: 'client', branchId: fleet.branch1);
    final probe = LanDevice(fleet.main.overHttp(fleet.base), 'probe-1');
    // asks for branch 2 and the mirror kind: the code decides
    final r = await probe.pair(clientCode.code,
        kind: 'client', branchId: fleet.branch2);
    expect(r.status, 200, reason: '$r');
    expect(r.json['deviceKind'], 'client');
    expect(r.json['branchId'], fleet.branch1);
    // a mirror code refuses a device that states the client kind
    final mirrorCode = await fleet.main.issue(kind: 'mirror');
    final wrong = LanDevice(fleet.main.overHttp(fleet.base), 'probe-2');
    final w = await wrong.pair(mirrorCode.code, kind: 'client');
    expect(w.status, isNot(200), reason: 'kind mismatch is refused: $w');
    // ... and it is not burnt by the refusal
    final right = LanDevice(fleet.main.overHttp(fleet.base), 'probe-3');
    expect((await right.pair(mirrorCode.code, kind: 'mirror')).status, 200);
    await probe.dispose();
    await wrong.dispose();
    await right.dispose();
  });

  test('F1.3 install order: cashier + accountant pair as client for B1, the '
      'mirror pairs as mirror; each ends committed in its OWN mode', () async {
    final c = await fleet.installClient(fleet.cashier, 'cashier', kCashPw);
    expect(c.ok, isTrue, reason: '$c');
    final a = await fleet.installClient(fleet.accountant, 'accountant', kAcctPw);
    expect(a.ok, isTrue, reason: '$a');
    final m = await fleet.installMirror(fleet.mirror, 'manager', kManagerFleetPw);
    expect(m.ok, isTrue, reason: '$m');

    for (final d in [fleet.cashier, fleet.accountant]) {
      final rec = await ProvisioningStore.read(d.db);
      expect(rec?.mode, 'client', reason: d.label);
      expect(await d.db.getSettingValue('network_mode'), 'client');
      expect(await d.db.getSettingValue('client_first_sync_completed'), 'true');
    }
    final mrec = await ProvisioningStore.read(fleet.mirror.db);
    expect(mrec?.mode, 'mirror');
    expect(await fleet.mirror.db.getSettingValue('network_mode'), 'mirror');
    await fleet.use(fleet.mirror);
    expect(NetworkService.instance.mode, NetworkMode.mirror);
    expect(MirrorState.instance.isConfigured, isTrue);

    // the main sees exactly three paired devices with the right kinds
    final kinds = {
      for (final id in [
        fleet.cashier.deviceId,
        fleet.accountant.deviceId,
        fleet.mirror.deviceId
      ])
        id!: (await fleet.main.pairing.deviceById(id))?.deviceKind,
    };
    expect(kinds.values.where((k) => k == 'client').length, 2);
    expect(kinds.values.where((k) => k == 'mirror').length, 1);
    final branchOf = (await fleet.main.pairing.deviceById(fleet.cashier.deviceId!))!;
    expect(branchOf.branchId, fleet.branch1);
  });

  test('F1.4 on every device the seeded admin is disabled and only the '
      "main's users can sign in; wrong password and another branch's user "
      'are rejected', () async {
    await fleet.installClient(fleet.cashier, 'cashier', kCashPw);
    await fleet.installClient(fleet.accountant, 'accountant', kAcctPw);
    await fleet.installMirror(fleet.mirror, 'manager', kManagerFleetPw);

    for (final d in [fleet.cashier, fleet.accountant]) {
      expect(await d.db.authenticateUser('admin', 'admin'), isNull,
          reason: '${d.label}: seeded admin/admin retired');
      expect(await d.db.authenticateUser('admin', kMainAdminPw), isNull,
          reason: '${d.label}: a branch session never receives the admin hash');
      // users of the branch work locally with the main's credentials
      expect(await d.db.authenticateUser('cashier', kCashPw), isNotNull);
      expect(await d.db.authenticateUser('accountant', kAcctPw), isNotNull);
      expect(await d.db.authenticateUser('branchadmin', kBranchAdminPw), isNotNull,
          reason: '${d.label}: branch admin of B1');
      // the main's wrong-password / other-branch answers (online path)
      expect(await d.db.authenticateUser('cashier', 'wrong-Password1'), isNull);
      expect(await d.db.authenticateUser('b2emp', kB2Pw), isNull,
          reason: '${d.label}: B2 user was never delivered');
      expect(await d.db.getUserByUsername('b2emp'), isNull);
    }
    expect(await fleet.mirror.db.authenticateUser('admin', 'admin'), isNull);
    expect(await fleet.mirror.db.authenticateUser('manager', kManagerFleetPw),
        isNotNull);

    // online sign-in through the real repository (gate -> the main decides)
    expect(await fleet.loginDenied(fleet.cashier, 'cashier', 'wrong-Password1'), isTrue);
    expect(await fleet.loginDenied(fleet.cashier, 'b2emp', kB2Pw), isTrue,
        reason: "another branch's user is refused for this device");
    expect(await fleet.loginDenied(fleet.cashier, 'admin', 'admin'), isTrue);
    expect(await fleet.login(fleet.cashier, 'cashier', kCashPw), isNotNull);
    expect(await fleet.login(fleet.accountant, 'accountant', kAcctPw), isNotNull);
    expect(await fleet.login(fleet.mirror, 'manager', kManagerFleetPw), isNotNull);
    expect(await fleet.loginDenied(fleet.mirror, 'cashier', kCashPw), isTrue,
        reason: 'mirror_console is required on the mirror');
  });
}