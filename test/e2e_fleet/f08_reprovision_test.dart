// F8 - RE-PROVISION: switching a paired CLIENT device to MIRROR through the
// single re-provision entry (`resetProvisioning`, then the normal install with
// a mirror code) yields mode=mirror with MirrorState configured. The owner's old
// logs showed a mirror choice committed as client: the activator must never
// commit anything but the chosen mode, and must refuse (not downgrade) a mirror
// commit without a mirror pairing.
@Timeout(Duration(minutes: 4))
library;

import 'dart:io' show HttpOverrides;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/services/deployment/commit_result.dart';
import 'package:picpos_erp/services/deployment/mode_activator.dart';
import 'package:picpos_erp/services/deployment/provisioning_applier.dart';
import 'package:picpos_erp/services/deployment/provisioning_record.dart';
import 'package:picpos_erp/services/deployment/provisioning_reset.dart';
import 'package:picpos_erp/services/deployment/reconcile_result.dart';
import 'package:picpos_erp/services/mirror_state.dart';
import 'package:picpos_erp/services/network_service.dart';
import 'package:picpos_erp/services/sync_service.dart';

import '../helpers/fleet_harness.dart';

void main() {
  Fleet.bindEnvironment();
  setUpAll(() => HttpOverrides.global = null);

  late Fleet fleet;
  setUp(() async => fleet = await Fleet.build(mirror: false));
  tearDown(() => fleet.dispose());

  /// A cold start of the active device: process globals forgotten, rebuilt from
  /// the DB + prefs exactly as `main.dart` does.
  Future<ReconcileResult> reboot(FleetDevice d) async {
    SyncService.clearInstance();
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    MirrorState.instance.debugSetForTests();
    await MirrorState.instance.loadSettings();
    await NetworkService.instance.loadSettings();
    await ProvisioningApplier.ensure(d.db);
    return NetworkService.instance.reconcileWithDb(d.db);
  }

  test('F8.1 the accountant device is re-provisioned as a MIRROR: mode=mirror, '
      'MirrorState configured, record + derived keys agree, a reboot keeps it',
      () async {
    final d = fleet.accountant;
    await fleet.use(d);
    // before: a configured client
    expect(NetworkService.instance.mode, NetworkMode.client);
    expect(await d.db.getSettingValue('network_mode'), 'client');
    expect(MirrorState.instance.isConfigured, isFalse);
    expect((await SharedPreferences.getInstance()).getInt('client_branch_id'),
        fleet.branch1);

    // the single re-provision entry forgets mode + pairing, keeps business data
    final usersBefore = (await d.db.select(d.db.users).get()).length;
    await resetProvisioning(d.db);
    expect(await d.db.getSettingValue('network_mode'), isNull);
    expect(await d.db.getSettingValue('setup_completed'), isNull);
    expect((await SharedPreferences.getInstance()).getInt('client_branch_id'), isNull);
    expect((await d.db.select(d.db.users).get()).length, usersBefore,
        reason: 'business data is not touched');

    // the owner now chooses MIRROR: the normal install with a mirror code
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    d.kind = 'mirror';
    final rep = await fleet.installMirror(d, 'manager', kManagerFleetPw);
    expect(rep.ok, isTrue, reason: '$rep');

    expect(NetworkService.instance.mode, NetworkMode.mirror);
    expect(MirrorState.instance.isConfigured, isTrue);
    expect(await d.db.getSettingValue('network_mode'), 'mirror');
    expect(await d.db.getSettingValue('deployment_mode'), 'mirror');
    expect(await d.db.getSettingValue('last_committed_mode'), 'mirror');
    final rec = (await ProvisioningStore.read(d.db))!;
    expect(rec.mode, 'mirror');
    expect(rec.deviceKind, 'mirror');
    expect((await SharedPreferences.getInstance()).getInt('client_branch_id'), isNull,
        reason: 'a mirror is not branch-bound');

    // the main sees the same device id as a mirror now (not a stale client row)
    final dev = (await fleet.main.pairing.listDevices())
        .firstWhere((x) => x.deviceId == d.deviceId);
    expect(dev.deviceKind, 'mirror');

    final boot = await reboot(d);
    expect(boot, isA<ReconcileOk>(), reason: '$boot');
    expect(NetworkService.instance.mode, NetworkMode.mirror);
    expect(MirrorState.instance.isConfigured, isTrue);

    // and the manager can really sign in on it (his identity, mirror_console)
    expect(await fleet.login(d, 'manager', kManagerFleetPw), isNotNull);
  });

  test('F8.2 a mirror commit WITHOUT a mirror pairing is refused - never '
      'committed as client', () async {
    final d = fleet.accountant;
    await fleet.use(d);
    await resetProvisioning(d.db);
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    final r = await ModeActivator(db: d.db).commit(ActivationPlan(
        mode: NetworkMode.mirror, host: '127.0.0.1', port: fleet.port));
    expect(r, isA<CommitFailed>());
    expect((r as CommitFailed).reasonCode, 'MIRROR_NOT_PAIRED');
    expect(await d.db.getSettingValue('network_mode'), isNot('client'));
    expect(await d.db.getSettingValue('network_mode'), isNot('mirror'));
    expect(NetworkService.instance.mode, NetworkMode.standalone);
  });

  test('F8.3 the reverse: re-provisioning the mirror as a CLIENT drops the '
      'mirror identity', () async {
    final f = fleet;
    final d = f.mirror;
    expect((await f.installMirror(d, 'manager', kManagerFleetPw)).ok, isTrue);
    expect(MirrorState.instance.isConfigured, isTrue);
    await resetProvisioning(d.db);
    expect(MirrorState.instance.isConfigured, isFalse);
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    d.kind = 'client';
    final rep = await f.installClient(d, 'cashier', kCashPw);
    expect(rep.ok, isTrue, reason: '$rep');
    expect(NetworkService.instance.mode, NetworkMode.client);
    expect(MirrorState.instance.isConfigured, isFalse);
    expect(await d.db.getSettingValue('network_mode'), 'client');
    expect((await ProvisioningStore.read(d.db))!.mode, 'client');
    expect(await reboot(d), isA<ReconcileOk>());
    expect(NetworkService.instance.mode, NetworkMode.client);
  });
}
