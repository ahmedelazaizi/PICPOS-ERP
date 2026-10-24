// A0 (ADP-009): the Fatal-setup screen's exit. resetProvisioning forgets the
// mode, the pairing and the first-run flags — and ONLY those.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/presentation/screens/provisioning_reset_done_app.dart';
import 'package:picpos_erp/services/deployment/provisioning_reset.dart';
import 'package:picpos_erp/services/deployment/reconcile_result.dart';
import 'package:picpos_erp/services/mirror_state.dart';
import 'package:picpos_erp/services/network_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => null);

  late AppDatabase db;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    I18nCatalog.setCatalog(const {});
    SharedPreferences.setMockInitialValues({
      'network_mode': 'mirror',
      'network_server_address': '10.0.0.5',
      'network_server_port': 8080,
      'network_api_token': 'tok',
      'client_branch_id': 3,
      'unrelated_pref': 'keep-me',
    });
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    MirrorState.instance.debugSetForTests();
    db = AppDatabase.forTesting();
    for (final k in [...kProvisioningDbKeys, 'company_name']) {
      await db.setSetting(k, 'x');
    }
    await MirrorState.instance
        .setPaired(serverDisplayName: 'hq:8080', adminUserId: 1);
  });

  tearDown(() async {
    MirrorState.instance.debugSetForTests();
    await db.close();
  });

  test('clears provisioning state (DB + prefs + pairing) and keeps the rest',
      () async {
    await resetProvisioning(db);

    for (final k in kProvisioningDbKeys) {
      expect(await db.getSettingValue(k), anyOf(isNull, isEmpty), reason: k);
    }
    expect(await db.getSettingValue('company_name'), 'x',
        reason: 'business settings are not provisioning state');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('network_mode'), 'standalone');
    expect(prefs.getString('network_server_address'), isNull);
    expect(prefs.getString('network_api_token'), isNull);
    expect(prefs.getInt('client_branch_id'), isNull);
    expect(prefs.getString('unrelated_pref'), 'keep-me');
    expect(MirrorState.instance.isConfigured, isFalse);
  });

  test('business data survives (users, branches)', () async {
    final users = (await db.select(db.users).get()).length;
    final branches = (await db.select(db.branches).get()).length;
    await resetProvisioning(db);
    expect((await db.select(db.users).get()).length, users);
    expect((await db.select(db.branches).get()).length, branches);
  });

  test('idempotent: a second reset is a no-op', () async {
    await resetProvisioning(db);
    await resetProvisioning(db);
    expect(await db.getSettingValue('network_mode'), anyOf(isNull, isEmpty));
  });

  test('after the reset the next boot is a clean standalone (wizard) boot',
      () async {
    await resetProvisioning(db);
    SharedPreferences.setMockInitialValues({'network_mode': 'standalone'});
    await NetworkService.instance.loadSettings();
    await MirrorState.instance.loadSettings();
    final boot = await NetworkService.instance.reconcileWithDb(db);
    expect(boot, isNot(isA<ReconcileInconsistent>()), reason: '$boot');
  });

  group('runProvisioningResetFlow', () {
    testWidgets('success -> restart-required screen whose button closes the '
        'program', (tester) async {
      Widget? launched;
      await runProvisioningResetFlow(() async {}, launch: (w) => launched = w);
      expect(launched, isA<ProvisioningResetDoneApp>());
      expect((launched! as ProvisioningResetDoneApp).error, isNull);

      var closed = false;
      await tester.pumpWidget(ProvisioningResetDoneApp(onClose: () => closed = true));
      expect(find.byType(FilledButton), findsOneWidget);
      await tester.tap(find.byType(FilledButton));
      expect(closed, isTrue);
    });

    testWidgets('a failing reset is reported, not swallowed', (tester) async {
      Widget? launched;
      await runProvisioningResetFlow(() async => throw StateError('disk full'),
          launch: (w) => launched = w);
      final app = launched! as ProvisioningResetDoneApp;
      expect(app.error, contains('disk full'));
      await tester.pumpWidget(app);
      expect(find.textContaining('disk full'), findsOneWidget);
    });
  });
}
