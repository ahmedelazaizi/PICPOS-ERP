// DEVICE LAB host (docs/testing/DEVICE-LAB.md). NOT a regression test: it only
// runs when LAB_HOST=1 (tool/device_lab/run_lab.ps1 sets it) and then stays
// alive for LAB_MINUTES serving the REAL production LAN stack to an Android
// emulator over real sockets:
//   NetworkService.startServer (real ApiHandler + rate limiter + auth
//   middleware + LanPairingService + lan_tls self-signed certificate) bound to
//   0.0.0.0:LAB_PORT, TLS on.  Data: an in-memory AppDatabase seeded through
//   the production ServerSetupWriter + role defaults.
// Also serves a PLAIN-HTTP decoy on LAB_HTTP_PORT (the app must refuse it).
//
// Outputs (LAB_DIR, default D:\qa\device-lab):  host.json  (codes, fingerprint,
// users), host.log, devices.json (after `list`).
// Control: append a line to LAB_DIR\cmd.txt:
//   issue <B1|B2>   -> new warehouse pairing code (appended to host.json codes)
//   revoke-all      -> revokes every paired device (real revoke())
//   list            -> writes devices.json
//   stop            -> shuts the host down
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/core/logging/diagnostic_logger.dart';
import 'package:picpos_erp/core/permissions/role_grant_matrix.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/api/api_session_token.dart';
import 'package:picpos_erp/services/network_service.dart';
import 'package:picpos_erp/services/role_grant_preflight_service.dart';
import 'package:picpos_erp/services/setup/server_setup_writer.dart';

const _pwClerk = 'WhClerk#2026';
const _pwClerk2 = 'WhClerk2#2026';
const _pwSuper = 'WhSuper#2026';
const _pwCashier = 'Cashier#2026';
const _pwAdmin = 'LabAdmin#2026';

/// In-memory flutter_secure_storage (the host reads/writes its secrets and the
/// TLS PEMs there; flutter test has no native side).
final _secure = <String, String>{};

void _mockSecureStorage() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
    final a = (call.arguments as Map?) ?? const {};
    final key = a['key'] as String?;
    switch (call.method) {
      case 'write':
        _secure[key!] = a['value'] as String;
        return null;
      case 'read':
        return _secure[key];
      case 'delete':
        _secure.remove(key);
        return null;
      case 'deleteAll':
        _secure.clear();
        return null;
      case 'containsKey':
        return _secure.containsKey(key);
      case 'readAll':
        return Map<String, String>.from(_secure);
    }
    return null;
  });
}

void main() {
  final on = Platform.environment['LAB_HOST'] == '1';
  test('device-lab host', skip: on ? false : 'LAB_HOST!=1 (device lab only)',
      timeout: Timeout.none, () async {
    final labDir = Directory(Platform.environment['LAB_DIR'] ?? r'D:\qa\device-lab')
      ..createSync(recursive: true);
    final port = int.parse(Platform.environment['LAB_PORT'] ?? '18443');
    final httpPort = int.parse(Platform.environment['LAB_HTTP_PORT'] ?? '18080');
    final minutes = int.parse(Platform.environment['LAB_MINUTES'] ?? '40');
    final logFile = File('${labDir.path}\\host.log');
    void log(String m) {
      final line = '${DateTime.now().toIso8601String()} $m';
      logFile.writeAsStringSync('$line\n', mode: FileMode.append);
      // ignore: avoid_print
      print(line);
    }

    logFile.writeAsStringSync('');
    final cmdFile = File('${labDir.path}\\cmd.txt');
    if (cmdFile.existsSync()) cmdFile.deleteSync();

    TestWidgetsFlutterBinding.ensureInitialized();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    I18nCatalog.setCatalog(const {});
    SharedPreferences.setMockInitialValues({});
    _mockSecureStorage();
    DiagnosticLogger.enableTestMode();
    ApiSessionToken.setKeyForTesting('device-lab-session-key');

    // ── seed through the production services ──
    final db = AppDatabase.forTesting();
    await RoleGrantPreflightService(db).grantMissingDefaults();
    final setup = await ServerSetupWriter().apply(
      db,
      const ServerSetupInput(
        companyName: 'Device Lab Co',
        currency: 'JOD',
        businessProfile: 'retail',
        businessType: 'retail',
        vatEnabled: true,
        vatRate: 16,
        fiscalYear: 2026,
        branchName: 'Branch One',
        branchCode: 'B1',
        warehouseName: 'B1 Main WH',
        branches: [ServerSetupBranch(code: 'B2', name: 'Branch Two')],
        adminPassword: _pwAdmin,
        developerPassword: 'LabDev#2026xx',
        offlineDays: 7,
        users: [
          ServerSetupUser(
              name: 'Lab Clerk', username: 'clerk1', password: _pwClerk,
              roleName: kWarehouseClerkRole, scope: 'B1', forcePasswordChange: false),
          ServerSetupUser(
              name: 'Lab Clerk Two', username: 'clerk2', password: _pwClerk2,
              roleName: kWarehouseClerkRole, scope: 'B2', forcePasswordChange: false),
          ServerSetupUser(
              name: 'Lab Supervisor', username: 'super1', password: _pwSuper,
              roleName: kWarehouseSupervisorRole, scope: 'ALL', forcePasswordChange: false),
          ServerSetupUser(
              name: 'Lab Cashier', username: 'cashier1', password: _pwCashier,
              roleName: 'كاشير', scope: 'B1', forcePasswordChange: false),
        ],
      ),
    );
    final b1 = setup.branchIds['B1']!;
    final b2 = setup.branchIds['B2']!;
    Future<int> whOf(int branch, String name) async {
      final whs = await db.select(db.warehouses).get();
      final have = whs.where((w) => w.branchId == branch);
      if (have.isNotEmpty) return have.first.id;
      return db.createWarehouseForBranch(name: name, branchId: branch, isDefault: true);
    }

    final wh1 = await whOf(b1, 'B1 Main WH');
    final wh2 = await whOf(b2, 'B2 Main WH');
    final p1 = await db.into(db.products).insert(ProductsCompanion.insert(
        code: 'LAB-1', name: 'Lab Milk', barcode: const Value('6221234567890')));
    final p2 = await db.into(db.products).insert(ProductsCompanion.insert(
        code: 'LAB-2', name: 'Lab Juice', barcode: const Value('6229876543210')));
    for (final (p, w, q) in [(p1, wh1, 12.0), (p1, wh2, 99.0), (p2, wh1, 7.0), (p2, wh2, 55.0)]) {
      await db.into(db.inventoryBalances).insert(InventoryBalancesCompanion.insert(
          productId: p, warehouseId: w, quantity: Value(q)));
    }
    final users = {for (final u in await db.select(db.users).get()) u.username: u.id};
    // Warehouse access: a clerk sees only his own branch's warehouse.
    await db.setUserWarehouseAccess(users['clerk1']!, [wh1]);
    await db.setUserWarehouseAccess(users['clerk2']!, [wh2]);
    await db.setUserWarehouseAccess(users['super1']!, [wh1, wh2]);
    final adminId = users['admin']!;
    log('seeded branches B1=$b1 B2=$b2 warehouses B1=$wh1 B2=$wh2 users=$users');

    // ── the REAL production server start (TLS on, 0.0.0.0) ──
    NetworkService.instance.debugSetModeForTests(NetworkMode.server);
    final started = await NetworkService.instance.startServer(db, port: port);
    expect(started, isTrue, reason: 'NetworkService.startServer failed (see log)');
    final fp = NetworkService.instance.serverCertFingerprint;
    expect(fp, isNotNull);
    expect(NetworkService.instance.httpScheme, 'https');
    log('REAL host listening https 0.0.0.0:$port fingerprint=$fp');

    // plain-HTTP decoy (must be refused by the app)
    final decoy = await shelf_io.serve(
        (shelf.Request r) => shelf.Response.ok(
            jsonEncode({'serverId': 'decoy', 'apiLevel': 1, 'tls': false}),
            headers: {'content-type': 'application/json'}),
        InternetAddress.anyIPv4,
        httpPort);
    log('plain HTTP decoy on 0.0.0.0:${decoy.port}');

    final codes = <Map<String, dynamic>>[];
    late void Function() writeJson;
    Future<void> issue(String branch) async {
      final id = branch == 'B2' ? b2 : b1;
      final offer = await NetworkService.instance.issueLanPairingCode(
          actorUserId: adminId, deviceKind: 'warehouse', branchId: id);
      if (offer == null) {
        log('ISSUE FAILED: issueLanPairingCode returned null');
        return;
      }
      codes.add({
        'branch': branch,
        'branchId': id,
        'code': offer.code,
        'expiresAt': offer.expiresAt.toIso8601String(),
        'qrPayload': offer.qrPayload,
      });
      log('issued warehouse code ${offer.code} for $branch');
      writeJson();
    }

    writeJson = () {
      File('${labDir.path}\\host.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
        'port': port,
        'httpPort': httpPort,
        'emulatorHost': '10.0.2.2',
        'address': '10.0.2.2:$port',
        'plainHttpAddress': '10.0.2.2:$httpPort',
        'fingerprint': fp,
        'branches': {'B1': b1, 'B2': b2},
        'warehouses': {'B1': wh1, 'B2': wh2},
        'users': {
          'clerk1': {'password': _pwClerk, 'branch': 'B1'},
          'clerk2': {'password': _pwClerk2, 'branch': 'B2'},
          'super1': {'password': _pwSuper, 'branch': 'ALL'},
          'cashier1': {'password': _pwCashier, 'branch': 'B1', 'note': 'no warehouse_mobile_access'},
        },
        'products': {
          '6221234567890': {'name': 'Lab Milk', 'B1': 12, 'B2': 99},
          '6229876543210': {'name': 'Lab Juice', 'B1': 7, 'B2': 55},
        },
        'codes': codes,
        'ready': true,
      }));
    };

    // NOTE: LanPairingService keeps ONE pending offer; each issue supersedes
    // the previous code. The driver issues a fresh code before each pairing.
    await issue('B1');

    // ── stay alive, obey commands ──
    final deadline = DateTime.now().add(Duration(minutes: minutes));
    var stop = false;
    var done = 0;
    while (!stop && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!cmdFile.existsSync()) continue;
      final lines = cmdFile.readAsLinesSync();
      for (; done < lines.length; done++) {
        final cmd = lines[done].trim();
        if (cmd.isEmpty) continue;
        log('CMD $cmd');
        if (cmd.startsWith('issue')) {
          await issue(cmd.split(' ').length > 1 ? cmd.split(' ')[1] : 'B1');
        } else if (cmd == 'revoke-all' || cmd == 'list') {
          final rows = await db
              .customSelect('SELECT device_id, name, device_kind, branch_id, revoked, last_seen_at '
                  'FROM lan_paired_devices')
              .get();
          if (cmd == 'revoke-all') {
            for (final r in rows) {
              await NetworkService.instance
                  .revokeLanDevice(r.data['device_id'] as String, actorUserId: adminId);
              log('revoked ${r.data['device_id']}');
            }
          }
          final after = await db
              .customSelect('SELECT device_id, name, device_kind, branch_id, revoked, last_seen_at '
                  'FROM lan_paired_devices')
              .get();
          File('${labDir.path}\\devices.json').writeAsStringSync(
              jsonEncode([for (final r in after) r.data]));
        } else if (cmd == 'stop') {
          stop = true;
        }
      }
    }
    log('host stopping');
    await decoy.close(force: true);
    await NetworkService.instance.stopServer();
    File('${labDir.path}\\host.json').writeAsStringSync('{"ready":false}');
  });
}
