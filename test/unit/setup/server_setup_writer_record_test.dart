// A1 leftover (HQ path): the main-server finish must write the device
// provisioning record INTO the server database in the same adoption contract
// as the other modes (mode=server, port, PG-configured flag, setup_completed
// LAST). Before the fix the PG database carried no record, so the first boot
// after the restart got an ADOPT-BACKFILL and no self-check.
import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/core/logging/diagnostic_logger.dart';
import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/services/deployment/gate_stage.dart';
import 'package:picpos_erp/services/deployment/provisioning_applier.dart';
import 'package:picpos_erp/services/deployment/provisioning_record.dart';
import 'package:picpos_erp/services/deployment/self_check.dart';
import 'package:picpos_erp/services/mirror_state.dart';
import 'package:picpos_erp/services/network_service.dart';
import 'package:picpos_erp/services/setup/server_setup_writer.dart';

ServerSetupInput _input({int port = 8080}) => ServerSetupInput(
      companyName: 'شركة الأمل',
      currency: 'JOD',
      businessProfile: 'restaurant',
      businessType: 'restaurant',
      vatEnabled: true,
      vatRate: 16,
      fiscalYear: 2026,
      branchName: 'المقر الرئيسي',
      branchCode: 'HQ-1',
      warehouseName: 'مخزن المقر',
      adminPassword: 'Adm1n#Strong',
      developerPassword: 'dev12345',
      serverPort: port,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => null);

  late AppDatabase db;
  final writer = ServerSetupWriter();

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    I18nCatalog.setCatalog(const {});
    SharedPreferences.setMockInitialValues({});
    DiagnosticLogger.enableTestMode();
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    MirrorState.instance.debugSetForTests();
    ProvisioningApplier.last = const AdoptReport();
    db = AppDatabase.forTesting();
    await db.getBranches();
  });

  tearDown(() async {
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await db.close();
  });

  test('the HQ finish writes the device record in the server database', () async {
    await writer.apply(db, _input(port: 9191));

    final rec = await ProvisioningStore.read(db);
    expect(rec, isNotNull, reason: 'the PG database must carry the record');
    expect(rec!.mode, 'server');
    expect(rec.deviceKind, 'server');
    expect(rec.serverPort, 9191);
    expect(rec.pgConfigured, isTrue);
    expect(rec.setupCompletedAt, isNotNull);
    expect(rec.selfCheckPending, isTrue,
        reason: 'the first boot after the restart shows the self-check');
    // The derived keys agree with the record (one adoption contract).
    for (final e in rec.derivedSettings.entries) {
      expect((await db.getSettingValue(e.key))?.trim(), e.value,
          reason: e.key);
    }
    expect((await db.getSettingValue('setup_completed'))?.trim(), 'true');
  });

  test('the first boot after the restart adopts the record: no backfill, '
      'the gate asks for the self-check', () async {
    await writer.apply(db, _input());

    NetworkService.instance.debugSetModeForTests(NetworkMode.server);
    final report = await ProvisioningApplier.ensure(db);

    expect(report.backfilled, isFalse);
    expect(report.repairs, isEmpty);
    expect(await resolveGateStage(db), GateStage.selfCheck);
  });

  test('running the writer twice keeps one consistent record', () async {
    await writer.apply(db, _input());
    final first = await ProvisioningStore.read(db);
    await writer.apply(db, _input());
    final second = await ProvisioningStore.read(db);
    expect(second!.mode, 'server');
    expect(second.pgConfigured, isTrue);
    expect(second.setupCompletedAt, first!.setupCompletedAt,
        reason: 'the first completion stamp is kept');
  });

  test('the record round-trips pgConfigured through JSON', () {
    const r = ProvisioningRecord(
        mode: 'server', deviceKind: 'server', pgConfigured: true);
    expect(ProvisioningRecord.tryParse(
            jsonEncode(r.toJson()))!
        .pgConfigured, isTrue);
    expect(ProvisioningRecord.tryParse('{"mode":"server"}')!.pgConfigured,
        isFalse);
  });

  group('self-check covers the HQ path', () {
    SelfCheckItem item(SelfCheckReport r, SelfCheckId id) =>
        r.items.firstWhere((i) => i.id == id);

    test('a finished HQ setup passes every item', () async {
      await writer.apply(db, _input());
      NetworkService.instance.debugSetModeForTests(NetworkMode.server);
      await ProvisioningApplier.ensure(db);

      final r = await SelfCheckRunner(db: db).run();

      expect(r.allPass, isTrue,
          reason: r.items.map((i) => '${i.id.name}=${i.status.name}').join(' '));
      expect(item(r, SelfCheckId.database).status, SelfCheckStatus.pass);
      expect(item(r, SelfCheckId.noDefaultAdmin).status, SelfCheckStatus.pass);
    });

    test('a server record without the PG flag fails and blocks the login',
        () async {
      await writer.apply(db, _input());
      final rec = (await ProvisioningStore.read(db))!;
      await ProvisioningStore.write(
          db,
          ProvisioningRecord(
              mode: rec.mode,
              deviceKind: rec.deviceKind,
              serverPort: rec.serverPort,
              setupCompletedAt: rec.setupCompletedAt,
              selfCheckPending: true));
      NetworkService.instance.debugSetModeForTests(NetworkMode.server);

      final r = await SelfCheckRunner(db: db).run();

      expect(item(r, SelfCheckId.database).status, SelfCheckStatus.fail);
      expect(r.canContinue, isFalse);
    });

    test('a server that still accepts admin/admin fails (blocking)', () async {
      await writer.apply(db, _input());
      await db.updateUserPassword(userId: 1, newPassword: 'admin');
      NetworkService.instance.debugSetModeForTests(NetworkMode.server);

      final r = await SelfCheckRunner(db: db).run();

      expect(item(r, SelfCheckId.noDefaultAdmin).status, SelfCheckStatus.fail);
      expect(r.canContinue, isFalse,
          reason: 'a main server with the factory password must not log in');
    });
  });
}
