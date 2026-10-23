// Spec 089 — Tests for NetworkService.reconcileWithDb().
//
// Covers the four cases in the reconcile truth table:
//   1. DB has value, prefs empty       → DB wins, prefs gets mirrored.
//   2. DB has value, prefs disagrees   → DB wins, prefs overwritten, warn logged.
//   3. DB empty, prefs is standalone   → 'standalone' written to DB.
//   4. DB empty, prefs is client/etc.  → STALE PREFS, force standalone,
//                                        prefs cleared, warn logged.
//   5. DB empty, prefs empty           → no-op (fresh install, wizard runs).

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:picpos_erp/core/logging/diagnostic_logger.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/network_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // flutter_secure_storage (used by ServerProxy.setApiToken inside
  // NetworkService.loadSettings / resetToStandalone) calls a platform
  // method channel that has no host side in unit tests. Stub it so the
  // tests can exercise the API-token-clearing code path without crashing.
  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (call) async {
    // All operations (read/write/delete/containsKey) are silent no-ops.
    if (call.method == 'read' || call.method == 'readAll') return null;
    return null;
  });

  group('NetworkService.reconcileWithDb (Spec 089)', () {
    late AppDatabase db;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      DiagnosticLogger.enableTestMode();
      db = AppDatabase.forTesting();
      // Reset singleton to a known starting point.
      NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    });

    tearDown(() async {
      await db.close();
    });

    test('Case 1 — DB has value, prefs empty: DB wins and is mirrored to prefs', () async {
      await db.setSetting('network_mode', 'client');
      // No network_mode in prefs (default state from setUp).

      await NetworkService.instance.reconcileWithDb(db);

      expect(NetworkService.instance.isClient, isTrue,
          reason: 'in-memory mode should follow DB value');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('network_mode'), 'client',
          reason: 'prefs should be back-filled from DB');
    });

    test('Case 2 — DB has value, prefs disagrees: DB wins and overwrites prefs', () async {
      SharedPreferences.setMockInitialValues({'network_mode': 'standalone'});
      await db.setSetting('network_mode', 'server');
      // Reload to pick up the new prefs value into the singleton.
      await NetworkService.instance.loadSettings();
      expect(NetworkService.instance.isStandalone, isTrue,
          reason: 'precondition: in-memory should reflect prefs');

      await NetworkService.instance.reconcileWithDb(db);

      expect(NetworkService.instance.isServer, isTrue,
          reason: 'DB is canonical → in-memory should flip to server');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('network_mode'), 'server',
          reason: 'prefs should be overwritten with DB value');
      expect(
        DiagnosticLogger.testLog.any((e) => e.contains('NETMODE-RECONCILE')),
        isTrue,
        reason: 'reconcile should record a warning when the stores disagreed',
      );
    });

    test('Case 3 — DB empty, prefs is standalone: standalone written to DB', () async {
      SharedPreferences.setMockInitialValues({'network_mode': 'standalone'});
      await NetworkService.instance.loadSettings();
      expect(await db.getSettingValue('network_mode'), isNull,
          reason: 'precondition: DB has no network_mode');

      await NetworkService.instance.reconcileWithDb(db);

      expect(await db.getSettingValue('network_mode'), 'standalone',
          reason: 'reconcile should propagate prefs → DB for the no-conflict case');
      expect(NetworkService.instance.isStandalone, isTrue);
    });

    test('Case 4 — DB empty, prefs says client: STALE PREFS, force standalone', () async {
      // The split-brain field bug: DB was wiped (Documents/UralCash deleted)
      // but SharedPreferences survived with the old 'client' value.
      SharedPreferences.setMockInitialValues({
        'network_mode': 'client',
        'network_server_address': '192.168.1.50',
        'network_api_token': 'stale-token-xyz',
        'client_branch_id': 7,
      });
      await NetworkService.instance.loadSettings();
      expect(NetworkService.instance.isClient, isTrue,
          reason: 'precondition: prefs makes the boot think it is a client');

      await NetworkService.instance.reconcileWithDb(db);

      expect(NetworkService.instance.isStandalone, isTrue,
          reason: 'stale prefs without DB backing must be forced to standalone');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('network_mode'), isNull,
          reason: 'stale network_mode pref must be cleared');
      expect(prefs.getString('network_server_address'), isNull,
          reason: 'stale server address must be cleared');
      expect(prefs.getString('network_api_token'), isNull,
          reason: 'stale API token must be cleared');
      expect(prefs.getInt('client_branch_id'), isNull,
          reason: 'stale client branch must be cleared');
      expect(
        DiagnosticLogger.testLog.any((e) =>
            e.contains('NETMODE-RECONCILE') && e.contains('STALE PREFS')),
        isTrue,
        reason: 'stale-prefs branch must emit a warning for support visibility',
      );
      // DB stays empty — the wizard will write the real value.
      expect(await db.getSettingValue('network_mode'), isNull);
    });

    test('Case 5 — DB empty, prefs empty: no-op (fresh install)', () async {
      // Both stores empty; nothing for reconcile to do.
      await NetworkService.instance.reconcileWithDb(db);

      expect(NetworkService.instance.isStandalone, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('network_mode'), isNull,
          reason: 'wizard will set this on first finalize');
      expect(await db.getSettingValue('network_mode'), isNull);
      expect(
        DiagnosticLogger.testLog.any((e) => e.contains('NETMODE-RECONCILE')),
        isFalse,
        reason: 'no warning expected on a fresh install',
      );
    });

    test('setMode(db: db) writes to BOTH prefs and DB atomically', () async {
      // Wizard / settings screen pattern: pass DB so the new mode lands
      // in both stores in one call.
      await NetworkService.instance.setMode(NetworkMode.client, db: db);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('network_mode'), 'client');
      expect(await db.getSettingValue('network_mode'), 'client');
      expect(NetworkService.instance.isClient, isTrue);
    });

    test('setMode(db: db) still writes DB when in-memory mode is unchanged',
        () async {
      SharedPreferences.setMockInitialValues({'network_mode': 'client'});
      await NetworkService.instance.loadSettings();
      expect(NetworkService.instance.isClient, isTrue,
          reason: 'precondition: singleton already has requested mode');
      expect(await db.getSettingValue('network_mode'), isNull,
          reason: 'precondition: DB has not been reconciled yet');

      await NetworkService.instance.setMode(NetworkMode.client, db: db);

      expect(await db.getSettingValue('network_mode'), 'client',
          reason: 'same-mode calls from settings/wizard must still repair DB');
    });

    test('resetToStandalone(db: db) writes standalone to DB and clears prefs', () async {
      SharedPreferences.setMockInitialValues({
        'network_mode': 'client',
        'network_server_address': '10.0.0.5',
        'network_api_token': 'tok',
      });
      await NetworkService.instance.loadSettings();
      await db.setSetting('network_mode', 'client');

      await NetworkService.instance.resetToStandalone(db: db);

      expect(await db.getSettingValue('network_mode'), 'standalone',
          reason: 'DB must be updated to standalone, not left at "client"');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('network_mode'), 'standalone');
      expect(prefs.getString('network_server_address'), isNull);
      expect(prefs.getString('network_api_token'), isNull);
      expect(NetworkService.instance.isStandalone, isTrue);
    });

    test('reconcileWithDb is idempotent across repeated boots', () async {
      await db.setSetting('network_mode', 'mirror');
      await NetworkService.instance.reconcileWithDb(db);
      DiagnosticLogger.enableTestMode(); // clears prior log entries

      await NetworkService.instance.reconcileWithDb(db);

      expect(NetworkService.instance.isMirror, isTrue);
      expect(
        DiagnosticLogger.testLog.any((e) => e.contains('NETMODE-RECONCILE')),
        isFalse,
        reason: 'second reconcile finds the stores in agreement → silent',
      );
    });
  });
}
