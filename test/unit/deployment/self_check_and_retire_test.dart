// A1: the seeded-admin retirement and the one-time self-check runner.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:picpos_erp/core/logging/diagnostic_logger.dart';
import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/services/deployment/mode_activator.dart';
import 'package:picpos_erp/services/deployment/provisioning_applier.dart';
import 'package:picpos_erp/services/deployment/provisioning_record.dart';
import 'package:picpos_erp/services/deployment/self_check.dart';
import 'package:picpos_erp/services/mirror_state.dart';
import 'package:picpos_erp/services/network_service.dart';
import 'package:picpos_erp/services/server_proxy.dart';
import 'package:picpos_erp/services/setup/seeded_admin_retire.dart';

SelfCheckItem _item(SelfCheckReport r, SelfCheckId id) =>
    r.items.firstWhere((i) => i.id == id);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => null);

  late AppDatabase db;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    SharedPreferences.setMockInitialValues({'network_api_token': 'tok'});
    DiagnosticLogger.enableTestMode();
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    MirrorState.instance.debugSetForTests();
    ServerProxy.instance.setApiToken('tok');
    ProvisioningApplier.last = const AdoptReport();
    ActivationHints.clear();
    db = AppDatabase.forTesting();
  });

  tearDown(() async {
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    MirrorState.instance.debugSetForTests();
    ActivationHints.clear();
    // updateUserPassword fires a password-collision scan without awaiting it.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await db.close();
  });

  group('retireSeededAdmin', () {
    test('admin/admin stops working, the row stays, the call is idempotent',
        () async {
      expect(await db.authenticateUser('admin', 'admin'), isNotNull);
      expect(await retireSeededAdmin(db), isTrue);
      expect(await db.authenticateUser('admin', 'admin'), isNull);
      final row = await (db.select(db.users)
            ..where((u) => u.username.equals('admin')))
          .getSingle();
      expect(row.isActive, isTrue, reason: 'invoices reference the row');
      expect(row.forcePasswordChange, isTrue);
      expect(await retireSeededAdmin(db), isFalse);
    });

    test('a credential delivered AFTER the retirement works (not poisoned)',
        () async {
      await retireSeededAdmin(db);
      await db.updateUserPassword(userId: 1, newPassword: 'Delivered#2026x');
      expect(await db.authenticateUser('admin', 'Delivered#2026x'), isNotNull);
    });

    test('a custom admin password is never touched', () async {
      await db.updateUserPassword(userId: 1, newPassword: 'Custom#Admin2026');
      expect(await retireSeededAdmin(db), isFalse);
      expect(await db.authenticateUser('admin', 'Custom#Admin2026'), isNotNull);
    });
  });

  group('ActivationHints', () {
    test('clear() resets the device kind and the delivery stamp', () {
      ActivationHints.deviceKind = 'pos';
      ActivationHints.credentialsDeliveredAt = DateTime.now();
      ActivationHints.clear();
      expect(ActivationHints.deviceKind, isNull);
      expect(ActivationHints.credentialsDeliveredAt, isNull);
    });
  });

  group('SelfCheckRunner', () {
    Future<void> completedMirror({
      bool firstSync = true,
      bool branches = true,
      bool delivered = true,
    }) async {
      NetworkService.instance.setServerAddress('10.0.0.5', port: 8080);
      await NetworkService.instance.setMode(NetworkMode.mirror, db: db);
      await MirrorState.instance
          .setPaired(serverDisplayName: 'hq:8080', adminUserId: null);
      await db.setSetting('deployment_mode', 'mirror');
      await db.setSetting('setup_completed', 'true');
      if (firstSync) await db.setSetting('mirror_first_sync_completed', 'true');
      if (!branches) {
        await db.customStatement('PRAGMA foreign_keys = OFF');
        await db.customStatement('DELETE FROM warehouses');
        await db.customStatement('DELETE FROM branches');
      }
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
          credentialsDeliveredAt: delivered ? DateTime.now().toUtc() : null,
        ),
      );
      await db.updateUserPassword(userId: 1, newPassword: 'Delivered#2026x');
    }

    test('a healthy mirror: every item passes; the login may proceed',
        () async {
      await completedMirror();
      final r = await SelfCheckRunner(db: db, probeServer: () async => true).run();
      expect(r.allPass, isTrue,
          reason: r.items.map((i) => '${i.id.name}=${i.status.name}').join(' '));
      expect(r.canContinue, isTrue);
    });

    test('mode mismatch (memory says standalone) is a BLOCKING failure',
        () async {
      await completedMirror();
      NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
      final r = await SelfCheckRunner(db: db, probeServer: () async => true).run();
      expect(_item(r, SelfCheckId.mode).failed, isTrue);
      expect(r.canContinue, isFalse);
    });

    test('lost device token: pairing fails (blocking) and asks to re-pair',
        () async {
      await completedMirror();
      ProvisioningApplier.last = const AdoptReport(rePairRequired: true);
      final r = await SelfCheckRunner(db: db, probeServer: () async => true).run();
      expect(_item(r, SelfCheckId.pairing).failed, isTrue);
      expect(r.needsRePair, isTrue);
      expect(r.canContinue, isFalse);
    });

    test('first sync flag missing or no master data: blocking', () async {
      await completedMirror(firstSync: false);
      var r = await SelfCheckRunner(db: db, probeServer: () async => true).run();
      expect(_item(r, SelfCheckId.firstSync).failed, isTrue);
      expect(r.canContinue, isFalse);
      await db.setSetting('mirror_first_sync_completed', 'true');
      await db.customStatement('PRAGMA foreign_keys = OFF');
      await db.customStatement('DELETE FROM warehouses');
      r = await SelfCheckRunner(db: db, probeServer: () async => true).run();
      expect(_item(r, SelfCheckId.firstSync).failed, isTrue);
    });

    test('the main unreachable is a WARNING (offline start allowed)', () async {
      await completedMirror();
      final r = await SelfCheckRunner(db: db, probeServer: () async => false).run();
      expect(_item(r, SelfCheckId.server).failed, isTrue);
      expect(r.canContinue, isTrue);
    });

    test('a networked device still holding admin/admin: the check retires it '
        'and passes', () async {
      await completedMirror();
      // put the seeded credential back
      await db.updateUserPassword(userId: 1, newPassword: 'admin');
      expect(await db.authenticateUser('admin', 'admin'), isNotNull);
      final r = await SelfCheckRunner(db: db, probeServer: () async => true).run();
      expect(_item(r, SelfCheckId.noDefaultAdmin).failed, isFalse);
      expect(await db.authenticateUser('admin', 'admin'), isNull);
    });

    test('credentials never delivered: warning, not a lock-out', () async {
      await completedMirror(delivered: false);
      final r = await SelfCheckRunner(db: db, probeServer: () async => true).run();
      expect(_item(r, SelfCheckId.users).failed, isTrue);
      expect(r.canContinue, isTrue);
    });

    test('no device record at all: blocking', () async {
      final r = await SelfCheckRunner(db: db).run();
      expect(_item(r, SelfCheckId.record).failed, isTrue);
      expect(r.canContinue, isFalse);
    });

    test('standalone: network items are "not required"', () async {
      await NetworkService.instance.setMode(NetworkMode.standalone, db: db);
      await db.setSetting('deployment_mode', 'standalone');
      await db.updateUserPassword(userId: 1, newPassword: 'Owner#Pass2026');
      await ProvisioningStore.write(
          db,
          const ProvisioningRecord(mode: 'standalone', deviceKind: 'standalone'));
      final r = await SelfCheckRunner(db: db).run();
      for (final id in [SelfCheckId.pairing, SelfCheckId.server, SelfCheckId.firstSync, SelfCheckId.users]) {
        expect(_item(r, id).status, SelfCheckStatus.skip, reason: id.name);
      }
      expect(r.allPass, isTrue);
    });

    test('markSelfCheckPassedIn ends the pending state (shown once)', () async {
      await completedMirror();
      expect((await ProvisioningStore.read(db))!.selfCheckPending, isTrue);
      await markSelfCheckPassedIn(db);
      expect((await ProvisioningStore.read(db))!.selfCheckPending, isFalse);
    });
  });
}
