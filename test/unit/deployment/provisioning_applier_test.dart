// A1 (adoption contract): the device record + its boot re-application.
// "Record wins": a corrupt / missing prefs layer or a drifted derived key is
// repaired from the DB-backed record at EVERY boot, idempotently, and a legacy
// install gets its record once (ADOPT-BACKFILL).
import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:picpos_erp/core/logging/diagnostic_logger.dart';
import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/services/deployment/gate_stage.dart';
import 'package:picpos_erp/services/deployment/provisioning_applier.dart';
import 'package:picpos_erp/services/deployment/provisioning_record.dart';
import 'package:picpos_erp/services/deployment/reconcile_result.dart';
import 'package:picpos_erp/services/mirror_state.dart';
import 'package:picpos_erp/services/network_service.dart';
import 'package:picpos_erp/services/server_proxy.dart';

ProvisioningRecord _record({
  String mode = 'mirror',
  DateTime? setupCompletedAt,
  int? branchId,
}) =>
    ProvisioningRecord(
      mode: mode,
      deviceKind: mode,
      serverHost: '10.0.0.5',
      serverPort: 8081,
      branchId: branchId,
      firstSyncAt: DateTime.utc(2026, 10, 25),
      setupCompletedAt: setupCompletedAt ?? DateTime.utc(2026, 10, 25),
      mirrorServerName: mode == 'mirror' ? 'hq:8081' : null,
      mirrorAdminUserId: mode == 'mirror' ? 1 : null,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => null);

  late AppDatabase db;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    SharedPreferences.setMockInitialValues({});
    DiagnosticLogger.enableTestMode();
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    NetworkService.instance.setServerAddress('', port: 8080);
    MirrorState.instance.debugSetForTests();
    ServerProxy.instance.setApiToken('');
    ProvisioningApplier.last = const AdoptReport();
    db = AppDatabase.forTesting();
  });

  tearDown(() async {
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    MirrorState.instance.debugSetForTests();
    await db.close();
  });

  group('record', () {
    test('JSON round-trips; garbage / wrong shape / unknown mode parse to null',
        () {
      final r = _record(branchId: 3, mode: 'client');
      final back = ProvisioningRecord.tryParse(jsonEncode(r.toJson()))!;
      expect(back.mode, 'client');
      expect(back.branchId, 3);
      expect(back.serverHost, '10.0.0.5');
      expect(back.serverPort, 8081);
      expect(back.setupCompletedAt, r.setupCompletedAt);
      expect(back.firstSyncAt, r.firstSyncAt);
      expect(ProvisioningRecord.tryParse(null), isNull);
      expect(ProvisioningRecord.tryParse(''), isNull);
      expect(ProvisioningRecord.tryParse('not json'), isNull);
      expect(ProvisioningRecord.tryParse('[1,2]'), isNull);
      expect(ProvisioningRecord.tryParse('{"mode":"bogus"}'), isNull);
      expect(r.derivedSettings['network_mode'], 'client');
      expect(r.derivedSettings['client_branch_id'], '3');
    });

    test('derived keys per mode', () {
      expect(_record(mode: 'mirror').derivedSettings,
          containsPair('mirror_first_sync_completed', 'true'));
      expect(_record(mode: 'client').derivedSettings,
          containsPair('client_first_sync_completed', 'true'));
      expect(_record(mode: 'server').derivedSettings,
          containsPair('server_setup_completed', 'true'));
      expect(_record(mode: 'standalone').derivedSettings,
          containsPair('standalone_setup_completed', 'true'));
    });
  });

  group('ensure()', () {
    test('first run (no record, setup unfinished): nothing is invented',
        () async {
      final r = await ProvisioningApplier.ensure(db);
      expect(r.record, isNull);
      expect(r.backfilled, isFalse);
      expect(await ProvisioningStore.read(db), isNull);
      expect(await resolveGateStage(db), GateStage.setup);
    });

    test('ADOPT-BACKFILL: a legacy completed client install gets its record '
        'ONCE, from the current keys, and nothing else changes', () async {
      SharedPreferences.setMockInitialValues({'network_api_token': 'tok'});
      await db.setSetting('network_mode', 'client');
      await db.setSetting('client_first_sync_completed', 'true');
      await db.setSetting('setup_completed', 'true');
      final first = await ProvisioningApplier.ensure(db);
      expect(first.backfilled, isTrue);
      final rec = (await ProvisioningStore.read(db))!;
      expect(rec.mode, 'client');
      expect(rec.firstSyncAt, isNotNull);
      expect(rec.setupCompletedAt, isNotNull);
      expect(rec.selfCheckPending, isFalse,
          reason: 'a legacy install never sees the one-time self-check');
      final second = await ProvisioningApplier.ensure(db);
      expect(second.backfilled, isFalse);
      expect(second.repairs, isEmpty, reason: 'idempotent');
      expect(await resolveGateStage(db), GateStage.ready);
    });

    test('backfill does not fabricate a first sync that never happened',
        () async {
      await db.setSetting('network_mode', 'mirror');
      await db.setSetting('setup_completed', 'true');
      await ProvisioningApplier.ensure(db);
      final rec = (await ProvisioningStore.read(db))!;
      expect(rec.firstSyncAt, isNull);
      expect(await db.getSettingValue('mirror_first_sync_completed'), isNull);
    });

    test('a corrupt record is ignored (never crashes the boot) and a completed '
        'install is backfilled over it', () async {
      await db.setSetting('device_provisioning_v1', '{{{ broken');
      await db.setSetting('network_mode', 'standalone');
      await db.setSetting('setup_completed', 'true');
      final r = await ProvisioningApplier.ensure(db);
      expect(r.backfilled, isTrue);
      expect((await ProvisioningStore.read(db))!.mode, 'standalone');
    });

    test('the RECORD wins over drifted derived keys (and logs ADOPT-REPAIR)',
        () async {
      await ProvisioningStore.write(db, _record());
      // someone / something drifted the keys
      await db.setSetting('network_mode', 'standalone');
      await db.setSetting('deployment_mode', 'server');
      await db.setSetting('setup_completed', 'true');
      await db.setSetting('mirror_first_sync_completed', 'false');
      final r = await ProvisioningApplier.ensure(db);
      expect(r.repairs, isNotEmpty);
      expect(await db.getSettingValue('network_mode'), 'mirror');
      expect(await db.getSettingValue('deployment_mode'), 'mirror');
      expect(await db.getSettingValue('mirror_first_sync_completed'), 'true');
      expect(await db.getSettingValue('last_committed_mode'), 'mirror');
      expect((await ProvisioningApplier.ensure(db)).repairs, isEmpty,
          reason: 'second boot: nothing left to repair');
    });

    test('missing / wiped PREFS: address, port, branch and the mirror identity '
        'come back from the record; the device asks to RE-PAIR (no token)',
        () async {
      await db.setSetting('setup_completed', 'true');
      await ProvisioningStore.write(db, _record(mode: 'client', branchId: 7));
      SharedPreferences.setMockInitialValues({}); // prefs wiped
      final r = await ProvisioningApplier.ensure(db);
      expect(NetworkService.instance.serverAddress, '10.0.0.5');
      expect(NetworkService.instance.serverPort, 8081);
      expect((await SharedPreferences.getInstance()).getInt('client_branch_id'), 7);
      expect(r.rePairRequired, isTrue);
      expect(await resolveGateStage(db), GateStage.selfCheck);

      // mirror: MirrorState is restored too
      await ProvisioningStore.write(db, _record());
      MirrorState.instance.debugSetForTests();
      await ProvisioningApplier.ensure(db);
      expect(MirrorState.instance.isConfigured, isTrue);
      expect(MirrorState.instance.serverDisplayName, 'hq:8081');
    });

    test('a surviving device token means NO re-pair prompt', () async {
      SharedPreferences.setMockInitialValues({'network_api_token': 'tok-123'});
      await db.setSetting('setup_completed', 'true');
      await ProvisioningStore.write(db, _record(mode: 'client', branchId: 1));
      final r = await ProvisioningApplier.ensure(db);
      expect(r.rePairRequired, isFalse);
      expect(await resolveGateStage(db), GateStage.ready);
    });

    test('mid-setup record (setup unfinished): the applier does not touch the '
        'keys, the gate keeps the setup', () async {
      await ProvisioningStore.write(
          db,
          const ProvisioningRecord(mode: 'client', deviceKind: 'client')
              .copyWith(selfCheckPending: true));
      await db.setSetting('network_mode', 'standalone');
      final r = await ProvisioningApplier.ensure(db);
      expect(r.repairs, isEmpty);
      expect(await db.getSettingValue('network_mode'), 'standalone');
      expect(await resolveGateStage(db), GateStage.setup);
    });

    test('record complete but setup_completed lost: the record restores it',
        () async {
      await ProvisioningStore.write(db, _record(mode: 'standalone'));
      expect(await db.getSettingValue('setup_completed'), isNull);
      await ProvisioningApplier.ensure(db);
      expect(await db.getSettingValue('setup_completed'), 'true');
    });

    test('networked setup just finished -> self-check once, then ready',
        () async {
      await db.setSetting('setup_completed', 'true');
      SharedPreferences.setMockInitialValues({'network_api_token': 't'});
      await ProvisioningStore.write(
          db, _record(mode: 'client', branchId: 1).copyWith(selfCheckPending: true));
      await ProvisioningApplier.ensure(db);
      expect(await resolveGateStage(db), GateStage.selfCheck);
      final rec = (await ProvisioningStore.read(db))!;
      await ProvisioningStore.write(db, rec.copyWith(selfCheckPending: false));
      expect(await resolveGateStage(db), GateStage.ready);
    });
  });

  group('reconcile re-applies the record first (boot order)', () {
    test('DB network_mode drifted to standalone while the record says mirror: '
        'the boot comes back as MIRROR, not as a silent standalone', () async {
      await db.setSetting('setup_completed', 'true');
      await ProvisioningStore.write(db, _record());
      await db.setSetting('network_mode', 'standalone');
      SharedPreferences.setMockInitialValues({'network_mode': 'standalone'});
      MirrorState.instance.debugSetForTests();
      final r = await NetworkService.instance.reconcileWithDb(db);
      expect(r, isA<ReconcileOk>(), reason: '$r');
      expect(NetworkService.instance.mode, NetworkMode.mirror);
      expect(MirrorState.instance.isConfigured, isTrue);
    });
  });
}
