// A1 acceptance - the mode CHOSEN in the first-run flow is the mode COMMITTED,
// and the pairing state matches it. Closes the owner's old-log failure: he chose
// MIRROR and the log showed `COMMIT-BEGIN mode=client` /
// `MirrorState.isConfigured=false` / `MIRROR-WIPE` from the client path.
//
// Real pipeline in process: serverBoundFinisher -> runFinishTail ->
// ModeActivator -> DeploymentModeCommitter (first-sync leg through a fake host)
// -> "reboot" (NetworkService.reconcileWithDb, which re-applies the device
// record first).
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
import 'package:picpos_erp/services/deployment/mode_activator.dart';
import 'package:picpos_erp/services/deployment/provisioning_record.dart';
import 'package:picpos_erp/services/deployment/reconcile_result.dart';
import 'package:picpos_erp/services/deployment/setup_contract.dart';
import 'package:picpos_erp/services/mirror_heartbeat_service.dart';
import 'package:picpos_erp/services/mirror_state.dart';
import 'package:picpos_erp/services/network_service.dart';
import 'package:picpos_erp/services/sync_service.dart';

import '../widget/first_run/first_run_test_kit.dart';

class _FakeHost extends SyncService {
  _FakeHost(this.db)
      : super(serverUrl: 'http://fake-host:8080', localDb: db);
  final AppDatabase db;
  int calls = 0;

  @override
  Future<SyncResult> fullSync() async {
    calls++;
    await db.into(db.branches).insert(BranchesCompanion.insert(name: 'HQ'));
    await db.into(db.warehouses).insert(WarehousesCompanion.insert(name: 'HQ-WH'));
    return SyncResult(success: true, message: 'ok', itemsSynced: 7);
  }
}

class _Persistence extends RecordingPersistence {
  _Persistence(this.db, {this.committer}) {
    branches = [testBranch(1, 'الفرع', 'BR1')];
  }
  final AppDatabase db;
  final DeploymentModeCommitter? committer;
  String? failureCode;

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
    final result = await ModeActivator(db: db, committer: committer).commit(
      ActivationPlan(
        mode: mode,
        port: serverPort,
        host: NetworkService.instance.serverAddress,
      ),
    );
    if (result is CommitFailed) failureCode = result.reasonCode;
    return result is CommitFailed ? result.reasonAr : null;
  }
}

/// A committer that "succeeds" without committing anything - the activator must
/// notice and refuse (never a silent fallback).
class _LyingCommitter extends DeploymentModeCommitter {
  _LyingCommitter(AppDatabase db) : super(db: db);

  @override
  Future<CommitResult> commit({
    required SetupContract contract,
    CommitProgressCallback? onProgress,
    bool forceResync = false,
    String? deviceKind,
  }) async =>
      CommitOk(mode: contract.targetMode, totalDuration: Duration.zero);
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
    ActivationHints.clear();
    db = AppDatabase.forTesting();
  });

  tearDown(() async {
    MirrorHeartbeatService.stop();
    SyncService.clearInstance();
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    MirrorState.instance.debugSetForTests();
    ActivationHints.clear();
    await db.close();
  });

  Future<ReconcileResult> reboot() async {
    SyncService.clearInstance();
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    MirrorState.instance.debugSetForTests();
    await MirrorState.instance.loadSettings();
    await NetworkService.instance.loadSettings();
    return NetworkService.instance.reconcileWithDb(db);
  }

  Future<SetupRunResult> finish(FirstRunDraft draft, {_Persistence? p}) {
    final events = <String>[];
    final fin = serverBoundFinisher(
        writer: FakeServerWriter(events), provisioning: FakeProvisioning(events));
    return fin(draft, _secrets, p ?? _Persistence(db));
  }

  /// What the link / first-sync steps leave behind for [path].
  Future<void> linked(FirstRunPath path) async {
    NetworkService.instance.setServerAddress('127.0.0.1', port: 8080);
    await NetworkService.instance.saveSettings();
    if (path == FirstRunPath.mirror) {
      await MirrorState.instance
          .setPaired(serverDisplayName: 'hq:8080', adminUserId: null);
    }
  }

  FirstRunDraft draftFor(FirstRunPath path) => FirstRunDraft(draftId: 'd', path: path)
      .copyWith(endpoint: '127.0.0.1', selectedBranchId: 1);

  test('the path -> mode mapping is explicit and total', () {
    expect({for (final p in FirstRunPath.values) p: networkModeForPath(p)}, {
      FirstRunPath.standalone: NetworkMode.standalone,
      FirstRunPath.hq: NetworkMode.server,
      FirstRunPath.branch: NetworkMode.client,
      FirstRunPath.mirror: NetworkMode.mirror,
    });
  });

  for (final c in [
    (FirstRunPath.mirror, NetworkMode.mirror),
    (FirstRunPath.branch, NetworkMode.client),
    (FirstRunPath.hq, NetworkMode.server),
  ]) {
    test('choosing ${c.$1.name} commits mode=${c.$2.name}, the record and the '
        'derived keys agree, and a reboot comes back as ${c.$2.name}', () async {
      if (c.$1 != FirstRunPath.hq) await linked(c.$1);
      final host = _FakeHost(db);
      final p = _Persistence(db);
      final r = await finish(draftFor(c.$1), p: p);
      expect(r.ok, isTrue, reason: '${r.error} ${p.failureCode}');

      final mode = c.$2.name;
      expect(await db.getSettingValue('network_mode'), mode);
      expect(await db.getSettingValue('deployment_mode'), mode);
      expect(await db.getSettingValue('last_committed_mode'), mode);
      final rec = (await ProvisioningStore.read(db))!;
      expect(rec.mode, mode);
      expect(rec.networkMode, c.$2);
      expect(NetworkService.instance.mode, c.$2);
      expect(MirrorState.instance.isConfigured, c.$2 == NetworkMode.mirror,
          reason: 'MirrorState matches the committed mode');
      if (c.$2 == NetworkMode.mirror) {
        expect(await db.getSettingValue('mirror_first_sync_completed'), 'true');
        expect(rec.deviceKind, 'mirror');
        expect(host.calls, 1);
      }
      if (c.$2 == NetworkMode.client) {
        expect(await db.getSettingValue('client_first_sync_completed'), 'true');
        expect(rec.branchId, isNull,
            reason: 'prefs had no branch yet (the step writes it); the tail does');
      }
      expect(await db.getSettingValue('setup_completed'), 'true');
      expect(rec.selfCheckPending, isTrue,
          reason: 'a networked setup is followed by the self-check');

      final boot = await reboot();
      expect(boot, isA<ReconcileOk>(), reason: '$boot');
      expect(NetworkService.instance.mode, c.$2);
      expect(MirrorState.instance.isConfigured, c.$2 == NetworkMode.mirror);
    });
  }

  test('SCENARIO: the wizard is reopened after a half-finished BRANCH attempt '
      'left network_mode=client in memory, prefs and the DB; the owner now '
      'chooses MIRROR -> mirror is what is committed', () async {
    // the half-finished attempt (older builds wrote the mode at the link step)
    await db.setSetting('network_mode', 'client');
    await db.setSetting('client_first_sync_completed', 'true');
    NetworkService.instance.setServerAddress('10.9.9.9', port: 8080);
    await NetworkService.instance.setMode(NetworkMode.client, db: db);
    expect(NetworkService.instance.mode, NetworkMode.client);

    // ... then the mirror path: pair by mirror code (MirrorState) and finish
    await linked(FirstRunPath.mirror);
    _FakeHost(db);
    final p = _Persistence(db);
    final r = await finish(draftFor(FirstRunPath.mirror), p: p);
    expect(r.ok, isTrue, reason: '${r.error} ${p.failureCode}');
    expect(await db.getSettingValue('last_committed_mode'), 'mirror');
    expect(await db.getSettingValue('deployment_mode'), 'mirror');

    expect(await db.getSettingValue('network_mode'), 'mirror');
    expect((await ProvisioningStore.read(db))!.mode, 'mirror');
    expect(NetworkService.instance.mode, NetworkMode.mirror);
    expect(MirrorState.instance.isConfigured, isTrue);

    final boot = await reboot();
    expect(boot, isA<ReconcileOk>(), reason: '$boot');
    expect(NetworkService.instance.mode, NetworkMode.mirror);
    expect(MirrorState.instance.isConfigured, isTrue);
  });

  test('SCENARIO (reverse): a stale MIRROR identity from an abandoned attempt '
      'does not survive when the owner then commits a CLIENT', () async {
    await linked(FirstRunPath.mirror); // MirrorState configured, stale
    expect(MirrorState.instance.isConfigured, isTrue);
    await linked(FirstRunPath.branch);
    _FakeHost(db);
    final r = await finish(draftFor(FirstRunPath.branch));
    expect(r.ok, isTrue, reason: '${r.error}');
    expect(await db.getSettingValue('network_mode'), 'client');
    expect(MirrorState.instance.isConfigured, isFalse);
    expect((await ProvisioningStore.read(db))!.mode, 'client');
    expect(await reboot(), isA<ReconcileOk>());
    expect(NetworkService.instance.mode, NetworkMode.client);
  });

  test('a mirror commit without a mirror pairing is refused, not downgraded',
      () async {
    final p = _Persistence(db);
    _FakeHost(db);
    final r = await finish(draftFor(FirstRunPath.mirror), p: p);
    expect(r.ok, isFalse);
    expect(p.failureCode, 'MIRROR_NOT_PAIRED');
    expect(await db.getSettingValue('network_mode'), isNot('mirror'));
    expect(await db.getSettingValue('setup_completed'), isNot('true'));
    expect(NetworkService.instance.mode, NetworkMode.standalone);
  });

  test('if the committer claims success but the device did not take the '
      'chosen mode, the activator fails the commit (MODE_MISMATCH)', () async {
    final p = _Persistence(db, committer: _LyingCommitter(db));
    await linked(FirstRunPath.mirror);
    final r = await finish(draftFor(FirstRunPath.mirror), p: p);
    expect(r.ok, isFalse);
    expect(p.failureCode, 'MODE_MISMATCH');
    expect(await db.getSettingValue('setup_completed'), isNot('true'));
  });
}
