// A1 leftovers: the post-setup self-check items "a delta pull answers within
// 60 seconds" and "company / currency / plan match the main" - honest states
// from fake ports (no network): pass, fail with a reason, skip when a port is
// not available; never a fake success.
import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:picpos_erp/core/logging/diagnostic_logger.dart';
import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/services/deployment/provisioning_applier.dart';
import 'package:picpos_erp/services/deployment/provisioning_record.dart';
import 'package:picpos_erp/services/deployment/self_check.dart';
import 'package:picpos_erp/services/mirror_state.dart';
import 'package:picpos_erp/services/network_service.dart';
import 'package:picpos_erp/services/server_proxy.dart';

SelfCheckItem _item(SelfCheckReport r, SelfCheckId id) =>
    r.items.firstWhere((i) => i.id == id);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => null);

  late AppDatabase db;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    SharedPreferences.setMockInitialValues({'network_api_token': 'tok'});
    DiagnosticLogger.enableTestMode();
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    MirrorState.instance.debugSetForTests();
    ServerProxy.instance.setApiToken('tok');
    ProvisioningApplier.last = const AdoptReport();
    db = AppDatabase.forTesting();
    NetworkService.instance.setServerAddress('10.0.0.5', port: 8080);
    await NetworkService.instance.setMode(NetworkMode.mirror, db: db);
    await MirrorState.instance
        .setPaired(serverDisplayName: 'hq:8080', adminUserId: null);
    await db.setSetting('deployment_mode', 'mirror');
    await db.setSetting('setup_completed', 'true');
    await db.setSetting('mirror_first_sync_completed', 'true');
    await db.setSetting('system_currency', 'JOD');
    await db.setSetting('business_profile', 'restaurant');
    await db.setSetting('company_global_id', 'gid-1');
    await ProvisioningStore.write(
      db,
      ProvisioningRecord(
        mode: 'mirror',
        deviceKind: 'mirror',
        serverHost: '10.0.0.5',
        serverPort: 8080,
        firstSyncAt: DateTime.now().toUtc(),
        setupCompletedAt: DateTime.now().toUtc(),
        mirrorServerName: 'hq:8080',
        selfCheckPending: true,
        credentialsDeliveredAt: DateTime.now().toUtc(),
      ),
    );
    await db.updateUserPassword(userId: 1, newPassword: 'Delivered#2026x');
  });

  tearDown(() async {
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    MirrorState.instance.debugSetForTests();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await db.close();
  });

  Future<SelfCheckReport> run({
    Future<bool> Function()? pull,
    Future<Map<String, String>?> Function()? main,
    bool up = true,
    Duration budget = const Duration(seconds: 60),
  }) =>
      SelfCheckRunner(
        db: db,
        probeServer: () async => up,
        deltaPull: pull,
        fetchMainSettings: main,
        deltaPullTimeout: budget,
      ).run();

  group('delta pull within 60 seconds', () {
    test('a pull that answers passes', () async {
      final r = await run(pull: () async => true);
      expect(_item(r, SelfCheckId.deltaPull).status, SelfCheckStatus.pass);
    });

    test('a pull that never answers fails with the reason (not blocking)',
        () async {
      final r = await run(
          pull: () => Completer<bool>().future,
          budget: const Duration(milliseconds: 50));
      final i = _item(r, SelfCheckId.deltaPull);
      expect(i.status, SelfCheckStatus.fail);
      expect(i.detail, contains('no answer'));
      expect(i.blocking, isFalse);
      expect(r.canContinue, isTrue);
    });

    test('a refused or throwing pull fails', () async {
      var r = await run(pull: () async => false);
      expect(_item(r, SelfCheckId.deltaPull).status, SelfCheckStatus.fail);
      r = await run(pull: () async => throw StateError('boom'));
      expect(_item(r, SelfCheckId.deltaPull).status, SelfCheckStatus.fail);
    });

    test('the main down fails (never a fake pass) and the port is not called',
        () async {
      var called = false;
      final r = await run(
          up: false,
          pull: () async {
            called = true;
            return true;
          });
      expect(_item(r, SelfCheckId.deltaPull).status, SelfCheckStatus.fail);
      expect(called, isFalse);
    });

    test('no port = skip, not a success', () async {
      final r = await run();
      expect(_item(r, SelfCheckId.deltaPull).status, SelfCheckStatus.skip);
    });
  });

  group('company / currency / plan match the main', () {
    final same = {
      'company_global_id': 'gid-1',
      'system_currency': 'JOD',
      'business_profile': 'restaurant',
    };

    test('equal values pass', () async {
      final r = await run(main: () async => same);
      expect(_item(r, SelfCheckId.mainMatch).status, SelfCheckStatus.pass);
    });

    test('a different currency fails and names it', () async {
      final r = await run(main: () async => {...same, 'system_currency': 'EGP'});
      final i = _item(r, SelfCheckId.mainMatch);
      expect(i.status, SelfCheckStatus.fail);
      expect(i.detail, contains('currency'));
      expect(i.detail, isNot(contains('plan')));
    });

    test('a different company and plan fail together', () async {
      final r = await run(
          main: () async => {
                ...same,
                'company_global_id': 'gid-OTHER',
                'business_profile': 'retail',
              });
      final i = _item(r, SelfCheckId.mainMatch);
      expect(i.status, SelfCheckStatus.fail);
      expect(i.detail, allOf(contains('company'), contains('plan')));
    });

    test('a value the main has and this device lacks is a mismatch', () async {
      await db.customStatement(
          "DELETE FROM settings WHERE key = 'system_currency'");
      final r = await run(main: () async => same);
      expect(_item(r, SelfCheckId.mainMatch).status, SelfCheckStatus.fail);
    });

    test('a key the main does not publish is not compared', () async {
      final r = await run(main: () async => {'system_currency': 'JOD'});
      expect(_item(r, SelfCheckId.mainMatch).status, SelfCheckStatus.pass);
    });

    test('the main not answering fails; down main fails; no port skips',
        () async {
      var r = await run(main: () async => null);
      expect(_item(r, SelfCheckId.mainMatch).status, SelfCheckStatus.fail);
      r = await run(up: false, main: () async => same);
      expect(_item(r, SelfCheckId.mainMatch).status, SelfCheckStatus.fail);
      r = await run();
      expect(_item(r, SelfCheckId.mainMatch).status, SelfCheckStatus.skip);
    });
  });
}
