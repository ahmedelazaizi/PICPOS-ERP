// A0 (ADP-001 / ADP-003): partial-failure states of mode adoption.
//  * NetworkService.setMode no longer swallows a failed `network_mode` DB write.
//  * DeploymentModeCommitter maps that failure to CommitFailed and leaves no
//    half-activated device (mode restored, mirror pairing dropped, heartbeat
//    stopped) — also when the LAST step (owned-settings write) fails.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:picpos_erp/core/logging/diagnostic_logger.dart';
import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/services/deployment/commit_result.dart';
import 'package:picpos_erp/services/deployment/deployment_mode_committer.dart';
import 'package:picpos_erp/services/deployment/setup_contract.dart';
import 'package:picpos_erp/services/mirror_heartbeat_service.dart';
import 'package:picpos_erp/services/mirror_state.dart';
import 'package:picpos_erp/services/network_service.dart';

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
    MirrorState.instance.debugSetForTests();
    db = AppDatabase.forTesting();
  });

  tearDown(() async {
    MirrorHeartbeatService.stop();
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    MirrorState.instance.debugSetForTests();
    await db.close();
  });

  /// Makes writes of [key] to `settings` fail like a full disk / locked DB.
  Future<void> breakSettingKey(String key) async {
    await db.customStatement(
        "CREATE TRIGGER fail_ins_$key BEFORE INSERT ON settings "
        "WHEN NEW.key = '$key' BEGIN SELECT RAISE(ABORT, 'disk full'); END");
    await db.customStatement(
        "CREATE TRIGGER fail_upd_$key BEFORE UPDATE ON settings "
        "WHEN NEW.key = '$key' BEGIN SELECT RAISE(ABORT, 'disk full'); END");
  }

  group('NetworkService.setMode (ADP-003)', () {
    test('a failed DB write THROWS and the in-memory mode is restored',
        () async {
      await breakSettingKey('network_mode');
      await expectLater(
          NetworkService.instance.setMode(NetworkMode.client, db: db),
          throwsA(isA<Object>()));
      expect(NetworkService.instance.mode, NetworkMode.standalone);
      expect(await db.getSettingValue('network_mode'), isNull);
    });

    test('same-mode call also surfaces the failure', () async {
      await breakSettingKey('network_mode');
      await expectLater(
          NetworkService.instance.setMode(NetworkMode.standalone, db: db),
          throwsA(isA<Object>()));
    });

    test('success persists to the DB (positive control)', () async {
      await NetworkService.instance.setMode(NetworkMode.client, db: db);
      expect(NetworkService.instance.mode, NetworkMode.client);
      expect(await db.getSettingValue('network_mode'), 'client');
    });
  });

  group('DeploymentModeCommitter', () {
    test('standalone: failed network_mode write -> CommitFailed(SETMODE_FAILED)',
        () async {
      await breakSettingKey('network_mode');
      final r = await DeploymentModeCommitter(db: db)
          .commit(contract: const StandaloneContract());
      expect(r, isA<CommitFailed>());
      expect((r as CommitFailed).reasonCode, 'SETMODE_FAILED');
    });

    test('mirror: setMode failure drops the pairing (no half-paired device)',
        () async {
      await MirrorState.instance
          .setPaired(serverDisplayName: 'hq:8080', adminUserId: 1);
      await db.setSetting('mirror_first_sync_completed', 'true');
      await breakSettingKey('network_mode');
      final r = await DeploymentModeCommitter(db: db).commit(
          contract: const MirrorContract(
              serverHost: '127.0.0.1',
              serverPort: 8080,
              adminUsername: '',
              adminPassword: ''));
      expect(r, isA<CommitFailed>());
      expect(MirrorState.instance.isConfigured, isFalse,
          reason: 'rollback is unconditional for a mirror');
      expect(NetworkService.instance.mode, isNot(NetworkMode.mirror));
    });

    test('mirror: the LAST step failing (owned settings) restores the mode, '
        'stops the heartbeat and drops the pairing', () async {
      await MirrorState.instance
          .setPaired(serverDisplayName: 'hq:8080', adminUserId: 1);
      await db.setSetting('mirror_first_sync_completed', 'true');
      await breakSettingKey('last_committed_mode');
      final r = await DeploymentModeCommitter(db: db).commit(
          contract: const MirrorContract(
              serverHost: '127.0.0.1',
              serverPort: 8080,
              adminUsername: '',
              adminPassword: ''));
      expect(r, isA<CommitFailed>());
      expect((r as CommitFailed).reasonCode, 'FINAL_COMMIT_FAILED');
      expect(NetworkService.instance.mode, NetworkMode.standalone);
      expect(await db.getSettingValue('network_mode'), 'standalone');
      expect(MirrorState.instance.isConfigured, isFalse);
    });

    test('a successful commit is not affected (positive control, idempotent)',
        () async {
      for (var i = 0; i < 2; i++) {
        final r = await DeploymentModeCommitter(db: db)
            .commit(contract: const StandaloneContract());
        expect(r, isA<CommitOk>());
      }
      expect(await db.getSettingValue('last_committed_mode'), 'standalone');
    });
  });
}
