// A0 (ADP-012 / ADP-001 / ADP-003): the mode chosen in the first-run setup is
// REALLY activated, not just remembered.
//
// Real pipeline, in process: serverBoundFinisher -> runFinishTail ->
// DeploymentModeCommitter (REAL, including its first-sync leg through a fake
// SyncService that "pulls" master data) -> NetworkService.setMode(db:) -> then a
// "reboot" (all in-memory facts dropped, DB + prefs kept) and the real boot
// decision NetworkService.reconcileWithDb. Closes BLOCKED-R4-e of the
// reproduction suite.
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
import 'package:picpos_erp/services/deployment/deployment_mode_committer.dart';
import 'package:picpos_erp/services/deployment/reconcile_result.dart';
import 'package:picpos_erp/services/mirror_heartbeat_service.dart';
import 'package:picpos_erp/services/mirror_state.dart';
import 'package:picpos_erp/services/network_service.dart';
import 'package:picpos_erp/services/sync_service.dart';

import '../widget/first_run/first_run_test_kit.dart';

/// A host that really "delivers" master data (and can be told to fail).
class _FakeHost extends SyncService {
  _FakeHost(this.db, {this.fail = false})
      : super(serverUrl: 'http://fake-host:8080', localDb: db);
  final AppDatabase db;
  bool fail;
  int calls = 0;

  @override
  Future<SyncResult> fullSync() async {
    calls++;
    if (fail) return SyncResult(success: false, message: 'host unreachable', itemsSynced: 0);
    await db.into(db.branches).insert(BranchesCompanion.insert(name: 'HQ'));
    await db.into(db.warehouses).insert(WarehousesCompanion.insert(name: 'HQ-WH'));
    return SyncResult(success: true, message: 'ok', itemsSynced: 7);
  }
}

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
    final committer = DeploymentModeCommitter(db: db);
    final contract = committer.buildContract(
      target: mode,
      serverPort: serverPort,
      serverHost: NetworkService.instance.serverAddress,
    );
    final result = await committer.commit(contract: contract);
    return result is CommitFailed ? result.reasonCode : null;
  }
}

const _secrets = FirstRunSecrets(
  adminPassword: 'S3cretPass',
  adminPasswordConfirm: 'S3cretPass',
  developerPassword: 'dev1',
  developerPasswordConfirm: 'dev1',
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
    I18nCatalog.setCatalog(const {});
    SharedPreferences.setMockInitialValues({});
    DiagnosticLogger.enableTestMode();
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    MirrorState.instance.debugSetForTests();
    SyncService.clearInstance();
    db = AppDatabase.forTesting();
  });

  tearDown(() async {
    MirrorHeartbeatService.stop();
    SyncService.clearInstance();
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    MirrorState.instance.debugSetForTests();
    await db.close();
  });

  /// "Process restart": drop every in-memory fact, keep DB + prefs.
  Future<ReconcileResult> reboot() async {
    SyncService.clearInstance();
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    MirrorState.instance.debugSetForTests();
    await MirrorState.instance.loadSettings();
    await NetworkService.instance.loadSettings();
    return NetworkService.instance.reconcileWithDb(db);
  }

  Future<SetupRunResult> finish(FirstRunPath path, FirstRunDraft draft) {
    final events = <String>[];
    final fin = serverBoundFinisher(
        writer: FakeServerWriter(events), provisioning: FakeProvisioning(events));
    return fin(draft, _secrets, _RealCommitPersistence(db));
  }

  Future<void> linkLikeTheLinkStep({required bool mirror}) async {
    NetworkService.instance.setServerAddress('127.0.0.1', port: 8080);
    await NetworkService.instance.saveSettings();
    if (mirror) {
      await MirrorState.instance
          .setPaired(serverDisplayName: 'hq:8080', adminUserId: 1);
    }
  }

  group('mirror', () {
    test('first sync runs in the committer, then a reboot comes back as an '
        'ACTIVE mirror', () async {
      await linkLikeTheLinkStep(mirror: true);
      final host = _FakeHost(db);
      expect(await db.getSettingValue('mirror_first_sync_completed'), isNull);

      final r = await finish(
          FirstRunPath.mirror,
          const FirstRunDraft(draftId: 'm', path: FirstRunPath.mirror)
              .copyWith(endpoint: '127.0.0.1'));
      expect(r.ok, isTrue, reason: '${r.error}');
      expect(host.calls, 1, reason: 'the committer ran the first sync');
      expect(await db.getSettingValue('mirror_first_sync_completed'), 'true');
      expect(await db.getSettingValue('network_mode'), 'mirror');

      final boot = await reboot();
      expect(boot, isA<ReconcileOk>(), reason: '$boot');
      expect(NetworkService.instance.mode, NetworkMode.mirror);
      expect(MirrorState.instance.isConfigured, isTrue);
      expect((boot as ReconcileOk).forceFirstSync, isFalse);
      expect(await db.getSettingValue('mirror_first_sync_completed'), 'true');
    });

    test('a failing first sync: no half-activation — mirror pairing dropped, '
        'mode not committed, flags not set; the retry then succeeds',
        () async {
      await linkLikeTheLinkStep(mirror: true);
      final host = _FakeHost(db, fail: true);
      final draft = const FirstRunDraft(draftId: 'm', path: FirstRunPath.mirror)
          .copyWith(endpoint: '127.0.0.1');

      final failed = await finish(FirstRunPath.mirror, draft);
      expect(failed.ok, isFalse);
      expect(MirrorState.instance.isConfigured, isFalse,
          reason: 'A0: pairing is rolled back for a mirror on ANY failure');
      expect(await db.getSettingValue('mirror_first_sync_completed'), isNot('true'));
      expect(await db.getSettingValue('network_mode'), isNot('mirror'));
      expect(NetworkService.instance.mode, isNot(NetworkMode.mirror));

      // retry after the operator re-links
      host.fail = false;
      await linkLikeTheLinkStep(mirror: true);
      final ok = await finish(FirstRunPath.mirror, draft);
      expect(ok.ok, isTrue, reason: '${ok.error}');
      final boot = await reboot();
      expect(boot, isA<ReconcileOk>(), reason: '$boot');
      expect(NetworkService.instance.mode, NetworkMode.mirror);
    });

    test('rebooting twice stays consistent (idempotent boot)', () async {
      await linkLikeTheLinkStep(mirror: true);
      _FakeHost(db);
      await finish(
          FirstRunPath.mirror,
          const FirstRunDraft(draftId: 'm', path: FirstRunPath.mirror)
              .copyWith(endpoint: '127.0.0.1'));
      expect(await reboot(), isA<ReconcileOk>());
      expect(await reboot(), isA<ReconcileOk>());
      expect(NetworkService.instance.mode, NetworkMode.mirror);
    });
  });

  group('client (branch)', () {
    test('first sync runs, then a reboot comes back as an ACTIVE client',
        () async {
      await linkLikeTheLinkStep(mirror: false);
      final host = _FakeHost(db);
      final r = await finish(
          FirstRunPath.branch,
          const FirstRunDraft(draftId: 'b', path: FirstRunPath.branch)
              .copyWith(selectedBranchId: 1));
      expect(r.ok, isTrue, reason: '${r.error}');
      expect(host.calls, 1);
      expect(await db.getSettingValue('client_first_sync_completed'), 'true');
      final boot = await reboot();
      expect(boot, isA<ReconcileOk>(), reason: '$boot');
      expect(NetworkService.instance.mode, NetworkMode.client);
    });

    test('a failing first sync leaves the device un-committed', () async {
      await linkLikeTheLinkStep(mirror: false);
      _FakeHost(db, fail: true);
      final r = await finish(
          FirstRunPath.branch,
          const FirstRunDraft(draftId: 'b', path: FirstRunPath.branch)
              .copyWith(selectedBranchId: 1));
      expect(r.ok, isFalse);
      expect(await db.getSettingValue('client_first_sync_completed'), isNot('true'));
      expect(await db.getSettingValue('network_mode'), isNot('client'));
    });
  });
}
