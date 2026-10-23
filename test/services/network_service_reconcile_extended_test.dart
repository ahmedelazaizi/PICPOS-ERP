// Spec 125 (US2 / FR-012 / FR-013) — Extended tests for the consistency
// checks added to NetworkService.reconcileWithDb on top of Spec 089.
//
// Truth table for the new checks:
//   • mode=standalone + standalone_setup_completed='true'        → Ok
//   • mode=standalone + missing + legacy setup_completed='true'  → Ok (backfill)
//   • mode=standalone + missing + no legacy                      → Inconsistent
//   • mode=server     + server_setup_completed='true'            → Ok
//   • mode=server     + missing + legacy + port>0                → Ok (backfill)
//   • mode=server     + missing                                  → Inconsistent
//   • mode=client     + client_first_sync_completed='true' + addr → Ok
//   • mode=client     + first_sync_completed='false'             → Inconsistent
//   • mode=client     + first_sync ok + no server_address        → Inconsistent
//   • mode=mirror     + mirror_first_sync_completed='true' + MirrorState → Ok
//   • mode=mirror     + first_sync missing                       → Inconsistent
//   • mode=mirror     + first_sync ok + MirrorState empty        → Inconsistent
//   • unknown mode value                                         → Inconsistent

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:picpos_erp/core/logging/diagnostic_logger.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/deployment/reconcile_result.dart';
import 'package:picpos_erp/services/deployment/settings_keys.dart';
import 'package:picpos_erp/services/mirror_state.dart';
import 'package:picpos_erp/services/network_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Stub flutter_secure_storage (no host side in unit tests).
  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

  group('NetworkService.reconcileWithDb — Spec 125 consistency checks', () {
    late AppDatabase db;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      DiagnosticLogger.enableTestMode();
      db = AppDatabase.forTesting();
      NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
      MirrorState.instance.debugSetForTests(); // clear all fields
    });

    tearDown(() async {
      await db.close();
    });

    // ── STANDALONE ─────────────────────────────────────────────────────

    test('standalone + standalone_setup_completed=true → ReconcileOk', () async {
      await db.setSetting('network_mode', 'standalone');
      await db.setSetting(
          DeploymentSettingsKeys.standaloneSetupCompleted, 'true');
      final result = await NetworkService.instance.reconcileWithDb(db);
      expect(result, isA<ReconcileOk>());
      expect((result as ReconcileOk).mode, NetworkMode.standalone);
    });

    test('standalone + missing flag + legacy setup_completed=true → Ok (backfilled)', () async {
      await db.setSetting('network_mode', 'standalone');
      await db.setSetting('setup_completed', 'true');
      final result = await NetworkService.instance.reconcileWithDb(db);
      expect(result, isA<ReconcileOk>());
      // verify backfill happened
      final backfilled = await db.getSettingValue(
          DeploymentSettingsKeys.standaloneSetupCompleted);
      expect(backfilled, 'true');
    });

    test('standalone + missing flag + no legacy → ReconcileInconsistent', () async {
      await db.setSetting('network_mode', 'standalone');
      final result = await NetworkService.instance.reconcileWithDb(db);
      expect(result, isA<ReconcileInconsistent>());
      expect((result as ReconcileInconsistent).reasonCode,
          ReconcileReasonCode.standaloneSetupIncomplete);
    });

    // ── SERVER ─────────────────────────────────────────────────────────

    test('server + server_setup_completed=true → ReconcileOk', () async {
      await db.setSetting('network_mode', 'server');
      await db.setSetting(
          DeploymentSettingsKeys.serverSetupCompleted, 'true');
      final result = await NetworkService.instance.reconcileWithDb(db);
      expect(result, isA<ReconcileOk>());
      expect((result as ReconcileOk).mode, NetworkMode.server);
    });

    test('server + missing flag + legacy setup_completed=true → Ok (backfilled)', () async {
      await db.setSetting('network_mode', 'server');
      await db.setSetting('setup_completed', 'true');
      // serverPort defaults to 8080 (>0)
      final result = await NetworkService.instance.reconcileWithDb(db);
      expect(result, isA<ReconcileOk>());
    });

    test('server + missing flag + no legacy → ReconcileInconsistent', () async {
      await db.setSetting('network_mode', 'server');
      final result = await NetworkService.instance.reconcileWithDb(db);
      expect(result, isA<ReconcileInconsistent>());
      expect((result as ReconcileInconsistent).reasonCode,
          ReconcileReasonCode.serverSetupIncomplete);
    });

    // ── CLIENT ─────────────────────────────────────────────────────────

    test('client + first_sync=true + server_address set → ReconcileOk', () async {
      await db.setSetting('network_mode', 'client');
      await db.setSetting(
          DeploymentSettingsKeys.clientFirstSyncCompleted, 'true');
      NetworkService.instance.setServerAddress('192.168.1.10', port: 8080);
      final result = await NetworkService.instance.reconcileWithDb(db);
      expect(result, isA<ReconcileOk>());
      expect((result as ReconcileOk).mode, NetworkMode.client);
    });

    test('client + first_sync missing → CLIENT_FIRSTSYNC_INCOMPLETE', () async {
      await db.setSetting('network_mode', 'client');
      final result = await NetworkService.instance.reconcileWithDb(db);
      expect(result, isA<ReconcileInconsistent>());
      expect((result as ReconcileInconsistent).reasonCode,
          ReconcileReasonCode.clientFirstSyncIncomplete);
    });

    test('client + first_sync ok but no server_address → CLIENT_PAIRING_MISSING', () async {
      await db.setSetting('network_mode', 'client');
      await db.setSetting(
          DeploymentSettingsKeys.clientFirstSyncCompleted, 'true');
      // serverAddress not set
      NetworkService.instance.setServerAddress('', port: 8080);
      final result = await NetworkService.instance.reconcileWithDb(db);
      expect(result, isA<ReconcileInconsistent>());
      expect((result as ReconcileInconsistent).reasonCode,
          ReconcileReasonCode.clientPairingMissing);
    });

    // ── MIRROR ─────────────────────────────────────────────────────────

    test('mirror + first_sync=true + MirrorState configured → ReconcileOk', () async {
      await db.setSetting('network_mode', 'mirror');
      await db.setSetting(
          DeploymentSettingsKeys.mirrorFirstSyncCompleted, 'true');
      MirrorState.instance.debugSetForTests(
        serverDisplayName: '192.168.1.10:8080',
        adminUserId: 1,
        lastHandshakeAt: DateTime.now().toUtc(),
      );
      final result = await NetworkService.instance.reconcileWithDb(db);
      expect(result, isA<ReconcileOk>());
      expect((result as ReconcileOk).mode, NetworkMode.mirror);
    });

    test('mirror + first_sync missing → MIRROR_FIRSTSYNC_INCOMPLETE', () async {
      await db.setSetting('network_mode', 'mirror');
      MirrorState.instance.debugSetForTests(
        serverDisplayName: 'x',
        lastHandshakeAt: DateTime.now().toUtc(),
      );
      final result = await NetworkService.instance.reconcileWithDb(db);
      expect(result, isA<ReconcileInconsistent>());
      expect((result as ReconcileInconsistent).reasonCode,
          ReconcileReasonCode.mirrorFirstSyncIncomplete);
    });

    test('mirror + first_sync ok but MirrorState empty → MIRROR_PAIRING_MISSING', () async {
      await db.setSetting('network_mode', 'mirror');
      await db.setSetting(
          DeploymentSettingsKeys.mirrorFirstSyncCompleted, 'true');
      // MirrorState.debugSetForTests() in setUp cleared everything → isConfigured=false
      final result = await NetworkService.instance.reconcileWithDb(db);
      expect(result, isA<ReconcileInconsistent>());
      expect((result as ReconcileInconsistent).reasonCode,
          ReconcileReasonCode.mirrorPairingMissing);
    });

    // ── EDGE CASES ─────────────────────────────────────────────────────

    test('unknown mode value → UNKNOWN_MODE', () async {
      await db.setSetting('network_mode', 'quantum_entangled');
      final result = await NetworkService.instance.reconcileWithDb(db);
      expect(result, isA<ReconcileInconsistent>());
      expect((result as ReconcileInconsistent).reasonCode,
          ReconcileReasonCode.unknownMode);
    });

    test('fresh install (DB+prefs empty) → ReconcileOk(standalone)', () async {
      final result = await NetworkService.instance.reconcileWithDb(db);
      expect(result, isA<ReconcileOk>());
      expect((result as ReconcileOk).mode, NetworkMode.standalone);
    });

    test('RECONCILE-OK log on successful path', () async {
      await db.setSetting('network_mode', 'standalone');
      await db.setSetting(
          DeploymentSettingsKeys.standaloneSetupCompleted, 'true');
      await NetworkService.instance.reconcileWithDb(db);
      expect(
        DiagnosticLogger.testLog.any(
          (l) => l.contains('RECONCILE-OK') && l.contains('standalone'),
        ),
        isTrue,
      );
    });

    test('RECONCILE-FAIL log includes reasonCode on inconsistent path', () async {
      await db.setSetting('network_mode', 'mirror');
      await db.setSetting(
          DeploymentSettingsKeys.mirrorFirstSyncCompleted, 'true');
      // MirrorState empty → MIRROR_PAIRING_MISSING
      await NetworkService.instance.reconcileWithDb(db);
      expect(
        DiagnosticLogger.testLog.any(
          (l) =>
              l.contains('RECONCILE-FAIL') &&
              l.contains(ReconcileReasonCode.mirrorPairingMissing),
        ),
        isTrue,
      );
    });
  });
}
