// ═══════════════════════════════════════════════════════════════════════════
// R4 (moved from the reproduction suite) - does the mode chosen in first-run
// survive the next boot, and does the boot re-apply the device record?
//
// Drives the REAL pipeline end to end, in process:
//   serverBoundFinisher -> runFinishTail -> SetupPersistence.commitDeploymentMode
//     -> REAL ModeActivator -> REAL DeploymentModeCommitter (writes the device
//        record `device_provisioning_v1` with the derived keys in ONE txn)
//   then the REAL next-boot decision: NetworkService.reconcileWithDb (which
//   first re-applies the record - ProvisioningApplier).
//
// The first-sync leg of the committer is covered by
// first_run_mirror_real_activation_test.dart and the real-host integration test.
// ═══════════════════════════════════════════════════════════════════════════
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/core/logging/diagnostic_logger.dart';
import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/domain/models/first_run/first_run_draft.dart';
import 'package:picpos_erp/domain/models/first_run/first_run_path.dart';
import 'package:picpos_erp/presentation/screens/first_run/first_run_finish_server.dart';
import 'package:picpos_erp/presentation/screens/setup_wizard/setup_finish_runner.dart';
import 'package:picpos_erp/services/deployment/commit_result.dart';
import 'package:picpos_erp/services/deployment/mode_activator.dart';
import 'package:picpos_erp/services/deployment/gate_stage.dart';
import 'package:picpos_erp/services/deployment/provisioning_applier.dart';
import 'package:picpos_erp/services/deployment/reconcile_result.dart';
import 'package:picpos_erp/services/mirror_heartbeat_service.dart';
import 'package:picpos_erp/services/mirror_state.dart';
import 'package:picpos_erp/services/network_service.dart';
import 'package:picpos_erp/services/sync/mirror_settings_keys.dart';
import 'package:picpos_erp/services/sync/strategies/setting_sync_strategy.dart';

import '../widget/first_run/first_run_test_kit.dart';

/// Real settings table + real committer behind the first-run port.
class _RealCommitPersistence extends RecordingPersistence {
  _RealCommitPersistence(this.db) {
    branches = [testBranch(1, 'الفرع', 'BR1')];
  }
  final AppDatabase db;

  @override
  Future<void> saveSetting(String key, String value) async {
    await super.saveSetting(key, value);
    await db.setSetting(key, value);
  }

  @override
  Future<void> saveCachedSetting(String key, String value) async {
    await super.saveCachedSetting(key, value);
    await db.setSetting(key, value);
  }

  @override
  Future<String?> commitDeploymentMode(NetworkMode mode, int serverPort) async {
    final result = await ModeActivator(db: db).commit(ActivationPlan(
      mode: mode,
      port: serverPort,
      host: NetworkService.instance.serverAddress,
    ));
    return result is CommitFailed ? result.reasonAr : null;
  }
}

const _admin = FirstRunSecrets(
  adminPassword: 'S3cretPass',
  adminPasswordConfirm: 'S3cretPass',
  developerPassword: 'dev1',
  developerPasswordConfirm: 'dev1',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_secure_storage channel is used by ServerProxy.setApiToken.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => null);

  late AppDatabase db;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    I18nCatalog.setCatalog(const {});
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

  /// "Process restart": drop every in-memory fact, keep DB + prefs.
  Future<ReconcileResult> nextBoot() async {
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    await MirrorState.instance.loadSettings(); // main_desktop initPlatform
    await NetworkService.instance.loadSettings(); // prefs → memory
    return NetworkService.instance.reconcileWithDb(db);
  }

  Future<SetupRunResult> finish(FirstRunPath path,
      {FirstRunDraft? draft, _RealCommitPersistence? p}) {
    final events = <String>[];
    final fin = serverBoundFinisher(
        writer: FakeServerWriter(events), provisioning: FakeProvisioning(events));
    final d = draft ?? FirstRunDraft(draftId: 'd', path: path);
    return fin(d, _admin, p ?? _RealCommitPersistence(db));
  }

  group('R4 — finish with mode=X, then next-boot reconciliation', () {
    test('CHAR-R4-a mirror: effective mode after reboot is MIRROR', () async {
      // State the link step leaves behind + what performFirstSync would set.
      await MirrorState.instance
          .setPaired(serverDisplayName: 'hq:8080', adminUserId: 1);
      NetworkService.instance.setServerAddress('127.0.0.1', port: 8080);
      await db.setSetting('mirror_first_sync_completed', 'true');
      await db.setSetting(kMirrorCacheIntegrityV1AppliedFlag, 'true');

      final r = await finish(FirstRunPath.mirror,
          draft: const FirstRunDraft(draftId: 'm', path: FirstRunPath.mirror)
              .copyWith(endpoint: '127.0.0.1'));
      expect(r.ok, isTrue, reason: '${r.error}');
      expect(await db.getSettingValue('network_mode'), 'mirror');
      expect(await db.getSettingValue('deployment_mode'), 'mirror');
      expect(await db.getSettingValue('setup_completed'), 'true');

      final boot = await nextBoot();
      expect(boot, isA<ReconcileOk>(), reason: '$boot');
      expect(NetworkService.instance.mode, NetworkMode.mirror);
      expect((boot as ReconcileOk).forceFirstSync, isFalse);
    });

    test('CHAR-R4-b client (branch path): effective mode after reboot is '
        'CLIENT', () async {
      NetworkService.instance.setServerAddress('10.0.0.5', port: 8080);
      await db.setSetting('client_first_sync_completed', 'true');
      final r = await finish(FirstRunPath.branch,
          draft: const FirstRunDraft(draftId: 'b', path: FirstRunPath.branch)
              .copyWith(selectedBranchId: 1));
      expect(r.ok, isTrue, reason: '${r.error}');
      final boot = await nextBoot();
      expect(boot, isA<ReconcileOk>(), reason: '$boot');
      expect(NetworkService.instance.mode, NetworkMode.client);
    });

    test('CHAR-R4-c server (HQ path): effective mode after reboot is SERVER',
        () async {
      final r = await finish(FirstRunPath.hq,
          draft: const FirstRunDraft(draftId: 'h', path: FirstRunPath.hq)
              .copyWith(companyName: 'شركة', currency: 'JOD'));
      expect(r.ok, isTrue, reason: '${r.error}');
      final boot = await nextBoot();
      expect(boot, isA<ReconcileOk>(), reason: '$boot');
      expect(NetworkService.instance.mode, NetworkMode.server);
    });

    test('CHAR-R4-d MirrorState survives a process restart only because '
        'setPaired also writes prefs (memory-only state would be fatal)',
        () async {
      await MirrorState.instance
          .setPaired(serverDisplayName: 'hq:8080', adminUserId: 1);
      MirrorState.instance.debugSetForTests(); // restart: memory gone
      expect(MirrorState.instance.isConfigured, isFalse);
      await MirrorState.instance.loadSettings();
      expect(MirrorState.instance.isConfigured, isTrue);
    });

    test('REPRO-R4-f mirror finished but the pairing prefs are gone (cleared '
        'prefs / other profile / MirrorState.clear in a rollback): the app '
        'must come back as mirror OR offer re-pair — not lose the mode',
        () async {
      await MirrorState.instance
          .setPaired(serverDisplayName: 'hq:8080', adminUserId: 1);
      NetworkService.instance.setServerAddress('127.0.0.1', port: 8080);
      await db.setSetting('mirror_first_sync_completed', 'true');
      await db.setSetting(kMirrorCacheIntegrityV1AppliedFlag, 'true');
      final r = await finish(FirstRunPath.mirror);
      expect(r.ok, isTrue, reason: '${r.error}');

      // Prefs are gone (cleared prefs / other profile) but the DB survived: the
      // pairing identity now lives in the DB-backed device record too.
      SharedPreferences.setMockInitialValues({});
      MirrorState.instance.debugSetForTests();
      NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
      final boot = await NetworkService.instance.reconcileWithDb(db);
      expect(boot, isA<ReconcileOk>(),
          reason: 'the record restores the mirror identity; reconcile = $boot');
      expect(NetworkService.instance.mode, NetworkMode.mirror);
      expect(MirrorState.instance.isConfigured, isTrue,
          reason: 'restored from the record, not lost');
      expect(await db.getSettingValue('network_mode'), 'mirror');

      // The device token (secure storage / prefs) is gone too: the app does NOT
      // show a Fatal screen, it asks to RE-PAIR through the self-check.
      expect(ProvisioningApplier.last.rePairRequired, isTrue);
      expect(await resolveGateStage(db), GateStage.selfCheck);
    });

    test('CHAR-R4-h host settings payload carrying network_mode=server / '
        'deployment_mode=server does NOT overwrite a mirror device', () async {
      await db.setSetting('network_mode', 'mirror');
      await db.setSetting('deployment_mode', 'mirror');
      await SettingSyncStrategy(db).syncFromJson({
        'settings': {
          'network_mode': 'server',
          'deployment_mode': 'server',
          'company_name': 'HQ Co',
        }
      });
      expect(await db.getSettingValue('network_mode'), 'mirror');
      expect(await db.getSettingValue('deployment_mode'), 'mirror');
      expect(await db.getSettingValue('company_name'), 'HQ Co');
    });

    // REPRO-R4-g moved to test/unit/sync/device_local_setting_keys_test.dart (green).

    test('BLOCKED-R4-e committer first-sync leg for mirror/client '
        '(performFirstSync against a live host)', () {},
        skip: 'needs a live HTTP host reachable through SyncService/ServerProxy '
            '(shelf_io.serve in a separate Isolate as test/scenarios/'
            'sc_n_api_sale_test.dart does) + LAN bearer/pairing; not built '
            'in this harness. Mirror/client are driven here with the '
            'first-sync flags pre-set exactly as performFirstSync leaves them.');
  });
}
