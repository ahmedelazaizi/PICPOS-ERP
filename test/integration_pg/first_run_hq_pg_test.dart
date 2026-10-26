// First-run HQ (main server) setup against a LIVE PostgreSQL.
//
// Runs the real finish pieces of the HQ path (`serverBoundFinisher` →
// ServerSetupWriter.write + ServerProvisioningService.armPostgresMode, then the
// local ModeActivator tail) and proves what the app reads after the restart:
//   * the device record is IN PostgreSQL (mode=server, port, pgConfigured) and
//     `setup_completed` is the very last committed write;
//   * the seeded admin/admin is dead once the setup replaced its password and
//     the HQ user created by the wizard can log in;
//   * a restart (new AppDatabase on the same PG) → ProvisioningApplier restores
//     the record WITHOUT an ADOPT-BACKFILL, the gate asks for the one-time
//     self-check, and the HQ self-check passes;
//   * a second finish is idempotent.
//
// Run: flutter test test/integration_pg/first_run_hq_pg_test.dart --tags pg \
//        --run-skipped        (PG_TEST_DSN as in scripts/run_pg_tests.dart)

@Tags(['pg'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/logging/diagnostic_logger.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/deployment/commit_result.dart';
import 'package:picpos_erp/services/deployment/gate_stage.dart';
import 'package:picpos_erp/services/deployment/mode_activator.dart';
import 'package:picpos_erp/services/deployment/provisioning_applier.dart';
import 'package:picpos_erp/services/deployment/provisioning_record.dart';
import 'package:picpos_erp/services/deployment/self_check.dart';
import 'package:picpos_erp/services/deployment/settings_keys.dart';
import 'package:picpos_erp/services/mirror_state.dart';
import 'package:picpos_erp/services/network_service.dart';
import 'package:picpos_erp/services/server_proxy.dart';
import 'package:picpos_erp/services/setup/seeded_admin_retire.dart';
import 'package:picpos_erp/services/setup/server_provisioning_service.dart';
import 'package:picpos_erp/services/setup/server_setup_writer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '_support/pg_fixture.dart';

const _adminPw = 'Hq#Admin2026x';
const _userPw = 'Cashier#2026y';
const _port = 8099;

PostgresConfig _cfgFromDsn() {
  final uri = Uri.parse(Platform.environment['PG_TEST_DSN']!);
  final ui = uri.userInfo.split(':');
  return PostgresConfig(
    host: uri.host,
    port: uri.port == 0 ? 5432 : uri.port,
    database: uri.pathSegments.isNotEmpty ? uri.pathSegments.first : 'postgres',
    username: ui.first,
    password: ui.length > 1 ? ui[1] : '',
  );
}

ServerSetupInput _input() => const ServerSetupInput(
      companyName: 'شركة الاختبار',
      currency: 'JOD',
      businessProfile: 'retail',
      businessType: 'retail',
      vatEnabled: true,
      vatRate: 16,
      fiscalYear: 2026,
      branchName: 'المقر الرئيسي',
      branchCode: 'HQ1',
      warehouseName: 'المخزن الرئيسي',
      adminPassword: _adminPw,
      developerPassword: '',
      offlineDays: 5,
      serverPort: _port,
      users: [
        ServerSetupUser(
          name: 'أمين الصندوق',
          username: 'cashier1',
          password: _userPw,
          roleName: 'Cashier',
          scope: 'HQ',
        ),
      ],
    );

Future<Map<String, int>> _xmin(AppDatabase db) async {
  final rows = await db
      .customSelect('SELECT key, xmin::text::bigint AS x FROM settings')
      .get();
  return {for (final r in rows) r.read<String>('key'): r.read<int>('x')};
}

Future<int> _count(AppDatabase db, String table) async => (await db
        .customSelect('SELECT COUNT(*) AS n FROM $table')
        .getSingle())
    .read<int>('n');

SelfCheckItem _item(SelfCheckReport r, SelfCheckId id) =>
    r.items.firstWhere((i) => i.id == id);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => null);

  late PgTestFixture fx;
  late PostgresConfig cfg;

  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    SharedPreferences.setMockInitialValues({});
    DiagnosticLogger.enableTestMode();
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    MirrorState.instance.debugSetForTests();
    ServerProxy.instance.setApiToken('');
    ProvisioningApplier.last = const AdoptReport();
    ActivationHints.clear();
    cfg = _cfgFromDsn();
    fx = await bootPgTestSchema();
    await fx.db.getAllRoles(); // force the migration + seed
  });

  tearDownAll(() async {
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await fx.tearDown();
  });

  test('1 fresh PG: seeded admin/admin exists, no record, gate = setup',
      () async {
    expect(await fx.db.authenticateUser('admin', 'admin'), isNotNull);
    expect(await ProvisioningStore.read(fx.db), isNull);
    expect(await resolveGateStage(fx.db), GateStage.setup);
  });

  test('2 HQ finish: record in PG, setup_completed committed last, admin '
      'replaced, HQ user created', () async {
    final before = await _xmin(fx.db);
    final writer = ServerSetupWriter();
    final report = await writer.write(cfg, _input());
    await ServerProvisioningService().armPostgresMode(cfg);
    expect(report.createdUsers, 1);

    // the record is in PostgreSQL
    final rec = (await ProvisioningStore.read(fx.db))!;
    expect(rec.mode, 'server');
    expect(rec.deviceKind, 'server');
    expect(rec.serverPort, _port);
    expect(rec.pgConfigured, isTrue);
    expect(rec.selfCheckPending, isTrue);
    expect(rec.setupCompletedAt, isNotNull);

    // derived keys were written to PG too
    expect(await fx.db.getSettingValue('network_mode'), 'server');
    expect(await fx.db.getSettingValue('deployment_mode'), 'server');
    expect(await fx.db.getSettingValue('server_setup_completed'), 'true');
    expect(await fx.db.getSettingValue('setup_completed'), 'true');
    expect(await fx.db.getSettingValue('company_name'), 'شركة الاختبار');
    expect(await fx.db.getSettingValue('offline_login_grace_days'), '5');

    // setup_completed is the very last write: it shares the final transaction
    // with the record and no key was committed by a later transaction.
    final after = await _xmin(fx.db);
    const recKey = DeploymentSettingsKeys.deviceProvisioning;
    final last = after['setup_completed']!;
    expect(after[recKey], last, reason: 'record and setup_completed commit '
        'together in the final transaction');
    expect(after['network_mode'], last);
    for (final e in after.entries) {
      if (before[e.key] == e.value) continue; // untouched by the finish
      expect(e.value, lessThanOrEqualTo(last),
          reason: '${e.key} was committed AFTER setup_completed');
    }
    expect(after['company_name']!, lessThan(last),
        reason: 'the core (company) commits before the final transaction');

    // admin: the seeded credential is gone, the chosen one works
    expect(await fx.db.authenticateUser('admin', 'admin'), isNull);
    expect(await fx.db.authenticateUser('admin', _adminPw), isNotNull);
    final u = await fx.db.authenticateUser('cashier1', _userPw);
    expect(u, isNotNull);
    expect(u!.user.forcePasswordChange, isTrue);
    expect(await retireSeededAdmin(fx.db), isFalse,
        reason: 'nothing left to retire');

    // the local tail commits the same mode on this device's own database
    final local = AppDatabase.forTesting();
    try {
      final res = await ModeActivator(db: local)
          .commit(const ActivationPlan(mode: NetworkMode.server, port: _port));
      expect(res, isA<CommitOk>(), reason: '$res');
      final lrec = (await ProvisioningStore.read(local))!;
      expect(lrec.mode, 'server');
      expect(lrec.serverPort, _port);
    } finally {
      await local.close();
    }
  });

  test('3 restart: new AppDatabase on the same PG → record restored, NO '
      'backfill, gate = selfCheck, HQ self-check passes', () async {
    // a "restart": process memory is gone, only PG (and prefs) survive
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    SharedPreferences.setMockInitialValues({});
    ProvisioningApplier.last = const AdoptReport();
    final db2 = openExtraPgConnection();
    try {
      final r = await ProvisioningApplier.ensure(db2);
      expect(r.backfilled, isFalse, reason: 'the record existed: no backfill');
      expect(r.record?.mode, 'server');
      expect(r.record?.pgConfigured, isTrue);
      expect(r.repairs, isEmpty,
          reason: 'the writer already produced every derived key: $r');
      expect(await resolveGateStage(db2), GateStage.selfCheck);

      // boot reconcile puts the mode back in memory from the record
      final rc = await NetworkService.instance.reconcileWithDb(db2);
      expect(NetworkService.instance.mode, NetworkMode.server, reason: '$rc');

      final report = await SelfCheckRunner(db: db2).run();
      expect(
          report.items
              .map((i) => '${i.id.name}=${i.status.name}')
              .join(' '),
          isNotEmpty);
      expect(_item(report, SelfCheckId.record).failed, isFalse);
      expect(_item(report, SelfCheckId.mode).failed, isFalse);
      expect(_item(report, SelfCheckId.database).failed, isFalse);
      expect(_item(report, SelfCheckId.noDefaultAdmin).failed, isFalse);
      expect(report.canContinue, isTrue);
      expect(report.allPass, isTrue,
          reason: report.items
              .map((i) => '${i.id.name}=${i.status.name}')
              .join(' '));

      await markSelfCheckPassedIn(db2);
      expect(await resolveGateStage(db2), GateStage.ready);
    } finally {
      await db2.close();
    }
  });

  test('4 a backfilled record (no pgConfigured flag) cannot pass the HQ '
      'self-check', () async {
    final rec = (await ProvisioningStore.read(fx.db))!;
    await ProvisioningStore.write(
        fx.db,
        ProvisioningRecord(
            mode: 'server',
            deviceKind: 'server',
            serverPort: _port,
            setupCompletedAt: rec.setupCompletedAt)); // as the boot backfill builds it
    try {
      NetworkService.instance.debugSetModeForTests(NetworkMode.server);
      final report = await SelfCheckRunner(db: fx.db).run();
      expect(_item(report, SelfCheckId.database).failed, isTrue);
      expect(report.canContinue, isFalse);
    } finally {
      await ProvisioningStore.write(fx.db, rec);
    }
  });

  test('5 second finish is idempotent (same rows, same stamps, same logins)',
      () async {
    final recBefore = (await ProvisioningStore.read(fx.db))!;
    final counts = {
      for (final t in ['branches', 'warehouses', 'users', 'fiscal_years'])
        t: await _count(fx.db, t)
    };
    final writer = ServerSetupWriter();
    final report = await writer.write(cfg, _input());
    await ServerProvisioningService().armPostgresMode(cfg);

    expect(report.createdUsers, 0);
    expect(report.updatedUsers, 1);
    for (final t in counts.keys) {
      expect(await _count(fx.db, t), counts[t], reason: '$t duplicated');
    }
    final recAfter = (await ProvisioningStore.read(fx.db))!;
    expect(recAfter.setupCompletedAt, recBefore.setupCompletedAt,
        reason: 'the first completion stamp is kept');
    expect(jsonEncode(recAfter.toJson()['mode']), jsonEncode('server'));
    expect(recAfter.pgConfigured, isTrue);
    expect(await fx.db.authenticateUser('admin', 'admin'), isNull);
    expect(await fx.db.authenticateUser('admin', _adminPw), isNotNull);
    expect(await fx.db.getSettingValue('setup_completed'), 'true');
  });
}
