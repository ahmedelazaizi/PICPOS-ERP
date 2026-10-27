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
// users), host.log, devices.json (after `list`), fixtures.json (what the
// `product|po|count` commands created), facts-<name>.json (`facts`),
// api-<label>.json (`api`), ack.txt (one line per processed command).
// Control: append a line to LAB_DIR\cmd.txt (line N gets "N|msg" in ack.txt):
//   issue <B1|B2>   -> new warehouse pairing code (appended to host.json codes)
//   revoke-all      -> revokes every paired PHONE (the lab's own API probe device is spared)
//   list            -> writes devices.json
//   stop            -> shuts the host down
// Warehouse-phase lab commands ('|' separated):
//   setting|key|value
//   product|key|barcode|name|cost|trackExpiry(0/1)|qtyB1|qtyB1b|qtyB2
//   po|key|prodKey:qty,prodKey:qty          (open PO 'sent' in B1 Main WH)
//   count|key|prodKey,prodKey               (cycle-count task in B1 Main WH)
//   facts|name                              (stock, docs, events, journal, POs, counts)
//   convert|receiptGid                      (accountant: receipt -> purchase invoice)
//   api|label|user|METHOD|path|jsonBody|idempotencyKey   (real HTTPS call from a lab probe phone)
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show BooleanExpressionOperators, Value, driftRuntimeOptions;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/core/logging/diagnostic_logger.dart';
import 'package:picpos_erp/core/permissions/role_grant_matrix.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/database/wh_mobile_docs_schema.dart';
import 'package:picpos_erp/services/api/api_auth_middleware.dart';
import 'package:picpos_erp/services/api/api_session_token.dart';
import 'package:picpos_erp/services/api/lan_pairing_service.dart';
import 'package:picpos_erp/services/api/m1_wh/wh_doc_store.dart';
import 'package:picpos_erp/services/api/m1_wh/wh_receipt_posting.dart';
import 'package:picpos_erp/services/network_service.dart';
import 'package:picpos_erp/services/role_grant_preflight_service.dart';
import 'package:picpos_erp/services/setup/server_setup_writer.dart';

const _pwClerk = 'WhClerk#2026';
const _pwClerk2 = 'WhClerk2#2026';
const _pwClerk3 = 'WhClerk3#2026';
const _pwSuper = 'WhSuper#2026';
const _pwStore = 'WhStore#2026';
const _pwMgr = 'WhMgr#2026';
const _pwAcct = 'WhAcct#2026';
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

Object? _enc(Object? o) => o is DateTime ? o.toIso8601String() : o.toString();

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
    for (final f in ['cmd.txt', 'ack.txt', 'fixtures.json']) {
      final x = File('${labDir.path}\\$f');
      if (x.existsSync()) x.deleteSync();
    }
    for (final f in labDir.listSync().whereType<File>()) {
      final n = f.uri.pathSegments.last;
      if (n.startsWith('facts-') || n.startsWith('api-')) f.deleteSync();
    }

    TestWidgetsFlutterBinding.ensureInitialized();
    // flutter_test replaces dart:io HttpClient with a stub that answers 400;
    // the lab probe phone needs the real one.
    HttpOverrides.global = null;
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
              name: 'Lab Clerk Three', username: 'clerk3', password: _pwClerk3,
              roleName: kWarehouseClerkRole, scope: 'B1', forcePasswordChange: false),
          ServerSetupUser(
              name: 'Lab Supervisor', username: 'super1', password: _pwSuper,
              roleName: kWarehouseSupervisorRole, scope: 'ALL', forcePasswordChange: false),
          ServerSetupUser(
              name: 'Lab Storekeeper', username: 'store1', password: _pwStore,
              roleName: 'مخزني', scope: 'B1', forcePasswordChange: false),
          ServerSetupUser(
              name: 'Lab Stock Manager', username: 'mgr1', password: _pwMgr,
              roleName: 'مدير مخزون', scope: 'B1', forcePasswordChange: false),
          ServerSetupUser(
              name: 'Lab Accountant', username: 'acct1', password: _pwAcct,
              roleName: 'محاسب', scope: 'B1', forcePasswordChange: false),
          ServerSetupUser(
              name: 'Lab Cashier', username: 'cashier1', password: _pwCashier,
              roleName: 'كاشير', scope: 'B1', forcePasswordChange: false),
        ],
      ),
    );
    // goods_in_transit / inventory / shrinkage accounts for the staged transfer.
    await db.syncDefaultAccounts();
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
    // Second warehouse of branch B1 (transfers stay inside the device's branch).
    final wh1b = await db.createWarehouseForBranch(name: 'B1 Second WH', branchId: b1);
    final p1 = await db.into(db.products).insert(ProductsCompanion.insert(
        code: 'LAB-1', name: 'Lab Milk', barcode: const Value('6221234567890')));
    final p2 = await db.into(db.products).insert(ProductsCompanion.insert(
        code: 'LAB-2', name: 'Lab Juice', barcode: const Value('6229876543210')));
    for (final (p, w, q) in [(p1, wh1, 12.0), (p1, wh2, 99.0), (p2, wh1, 7.0), (p2, wh2, 55.0)]) {
      await db.into(db.inventoryBalances).insert(InventoryBalancesCompanion.insert(
          productId: p, warehouseId: w, quantity: Value(q)));
    }
    final users = {for (final u in await db.select(db.users).get()) u.username: u.id};
    final idToUser = {for (final e in users.entries) e.value: e.key};
    final passwords = <String, String>{
      'clerk1': _pwClerk, 'clerk2': _pwClerk2, 'clerk3': _pwClerk3, 'super1': _pwSuper,
      'store1': _pwStore, 'mgr1': _pwMgr, 'acct1': _pwAcct, 'cashier1': _pwCashier,
    };
    // Warehouse access: a clerk sees only his own branch's warehouse.
    await db.setUserWarehouseAccess(users['clerk1']!, [wh1]);
    await db.setUserWarehouseAccess(users['clerk2']!, [wh2]);
    await db.setUserWarehouseAccess(users['clerk3']!, [wh1]);
    await db.setUserWarehouseAccess(users['super1']!, [wh1, wh1b, wh2]);
    await db.setUserWarehouseAccess(users['store1']!, [wh1, wh1b]);
    await db.setUserWarehouseAccess(users['mgr1']!, [wh1, wh1b]);
    await db.setUserWarehouseAccess(users['acct1']!, [wh1, wh1b]);
    final adminId = users['admin']!;
    final acctId = users['acct1']!;
    log('seeded branches B1=$b1 B2=$b2 warehouses B1=$wh1 B1b=$wh1b B2=$wh2 users=$users');

    // C5 (SEC-006): the freshly provisioned DB has NO lan_legacy_token_enabled row;
    // the real startServer (initializeLegacyTransition) must turn the shared bearer OFF.
    final legacySettingBeforeStart = await db.getSettingValue('lan_legacy_token_enabled');
    log('legacy setting before startServer = $legacySettingBeforeStart');
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

    // ── lab probe phone: a second REAL paired warehouse device used ONLY to
    //    make HTTPS calls from the host process (DTO assertions) ──
    final probeClient = HttpClient()
      ..badCertificateCallback = (cert, host, p) {
        final got = sha256.convert(cert.der).toString();
        final want = (fp ?? '').toLowerCase().replaceAll(':', '');
        if (got != want) log('probe: certificate fingerprint differs from host fp (got $got) - loopback, accepted');
        return true;
      };
    final probeDeviceId = 'lab-probe-${Random().nextInt(1 << 30).toRadixString(16)}';
    String? probeToken;
    final probeSessions = <String, String>{};

    Future<({int status, String body})> rawHttp(String method, String path,
        {Map<String, String> headers = const {}, String? body}) async {
      final req = await probeClient.openUrl(method, Uri.parse('https://127.0.0.1:$port$path'));
      headers.forEach(req.headers.set);
      if (body != null) {
        req.headers.set('content-type', 'application/json; charset=utf-8');
        req.add(utf8.encode(body));
      }
      final res = await req.close();
      return (status: res.statusCode, body: await res.transform(utf8.decoder).join());
    }

    Future<void> ensureProbe() async {
      if (probeToken != null) return;
      final offer = await NetworkService.instance.issueLanPairingCode(
          actorUserId: adminId, deviceKind: 'warehouse', branchId: b1);
      final r = await rawHttp('POST', '/api/pair',
          body: jsonEncode({
            'pairingCode': offer!.code,
            'deviceId': probeDeviceId,
            'deviceName': 'Lab probe',
            'deviceKind': 'warehouse'
          }));
      expect(r.status, 200, reason: 'probe pairing: ${r.body}');
      probeToken = (jsonDecode(r.body) as Map)['token'] as String;
      log('probe phone paired as $probeDeviceId');
    }

    Future<String> probeLogin(String user) async {
      await ensureProbe();
      final r = await rawHttp('POST', '/api/auth/session',
          headers: {'authorization': 'Bearer $probeToken', 'x-device-id': probeDeviceId},
          body: jsonEncode({'username': user, 'password': passwords[user]}));
      if (r.status != 200) throw StateError('probe login $user -> ${r.status} ${r.body}');
      return probeSessions[user] = (jsonDecode(r.body) as Map)['token'] as String;
    }

    Future<Map<String, Object?>> probeCall(String user, String method, String path,
        {String? body, String? key}) async {
      Future<({int status, String body})> go(String session) => rawHttp(method, path, headers: {
            'authorization': 'Bearer $probeToken',
            'x-device-id': probeDeviceId,
            'x-session-token': session,
            if (method != 'GET') 'x-idempotency-key': key ?? 'probe-${DateTime.now().microsecondsSinceEpoch}',
          }, body: body);
      var r = await go(probeSessions[user] ?? await probeLogin(user));
      if (r.status == 401) r = await go(await probeLogin(user));
      Object? parsed;
      try {
        parsed = jsonDecode(r.body);
      } catch (_) {
        parsed = r.body;
      }
      return {'user': user, 'method': method, 'path': path, 'status': r.status, 'body': parsed};
    }

    // ── lab probe CASHIER tablet (kind=pos, branch B1): host-side evidence for the
    //    device-scope policy (C5). Spared by revoke-all like the warehouse probe. ──
    final posProbeId = 'lab-pos-probe-${Random().nextInt(1 << 30).toRadixString(16)}';
    String? posProbeToken;
    final posSessions = <String, String>{};

    Future<void> ensurePosProbe() async {
      if (posProbeToken != null) return;
      final offer = await NetworkService.instance.issueLanPairingCode(
          actorUserId: adminId, deviceKind: 'pos', branchId: b1);
      final r = await rawHttp('POST', '/api/pair',
          body: jsonEncode({
            'pairingCode': offer!.code,
            'deviceId': posProbeId,
            'deviceName': 'Lab pos probe',
            'deviceKind': 'pos'
          }));
      expect(r.status, 200, reason: 'pos probe pairing: ${r.body}');
      posProbeToken = (jsonDecode(r.body) as Map)['token'] as String;
      log('pos probe tablet paired as $posProbeId');
    }

    Object? parseBody(String b) {
      try {
        return jsonDecode(b);
      } catch (_) {
        return b;
      }
    }

    /// user '-' = device token only (no signed-in user).
    Future<Map<String, Object?>> posCall(String user, String method, String path,
        {String? body, String? key}) async {
      await ensurePosProbe();
      String? session;
      if (user != '-') {
        final l = await rawHttp('POST', '/api/auth/session',
            headers: {'authorization': 'Bearer $posProbeToken', 'x-device-id': posProbeId},
            body: jsonEncode({'username': user, 'password': passwords[user]}));
        if (l.status != 200) {
          return {'user': user, 'stage': 'login', 'method': 'POST', 'path': '/api/auth/session', 'status': l.status, 'body': parseBody(l.body)};
        }
        session = posSessions[user] = (jsonDecode(l.body) as Map)['token'] as String;
      }
      final r = await rawHttp(method, path, headers: {
        'authorization': 'Bearer $posProbeToken',
        'x-device-id': posProbeId,
        'x-session-token': ?session,
        if (method != 'GET') 'x-idempotency-key': key ?? 'pp-${DateTime.now().microsecondsSinceEpoch}',
      }, body: body);
      return {'user': user, 'stage': 'call', 'method': method, 'path': path, 'status': r.status, 'body': parseBody(r.body)};
    }

    // ── fixtures + facts ──
    final fixtures = <String, Map<String, Object?>>{'products': {}, 'pos': {}, 'counts': {}};
    void writeFixtures() =>
        File('${labDir.path}\\fixtures.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(fixtures));

    Future<List<Map<String, Object?>>> q(String sql) async =>
        [for (final r in await db.customSelect(sql).get()) r.data.cast<String, Object?>()];

    Future<Object?> safe(Future<Object?> Function() f) async {
      try {
        return await f();
      } catch (e) {
        return {'error': '$e'};
      }
    }

    Future<Map<String, Object?>> collectFacts(String name) async {
      await db.ensureWhMobileDocsSchema();
      final docs = await q('SELECT * FROM wh_mobile_docs ORDER BY id');
      for (final d in docs) {
        d['created_by_name'] = idToUser[(d['created_by'] as num?)?.toInt()];
        d['approved_by_name'] = idToUser[(d['approved_by'] as num?)?.toInt()];
        d['lines'] = await q('SELECT * FROM wh_mobile_doc_lines WHERE doc_id = ${d['id']} ORDER BY id');
      }
      final events = await q('SELECT * FROM wh_mobile_doc_events ORDER BY id');
      for (final e in events) {
        e['actor_name'] = idToUser[(e['actor_user_id'] as num?)?.toInt()];
      }
      final git = await db.getAccountByPurpose('goods_in_transit');
      return {
        'name': name,
        'at': DateTime.now().toIso8601String(),
        'warehouses': {'B1': wh1, 'B1b': wh1b, 'B2': wh2},
        'users': users,
        'stock': await safe(() async {
          final out = <String, Map<String, Object?>>{};
          for (final r in await q('SELECT p.barcode AS barcode, p.name AS name, ib.warehouse_id AS wh, ib.quantity AS qty '
              'FROM inventory_balances ib JOIN products p ON p.id = ib.product_id ORDER BY p.id, ib.warehouse_id')) {
            final bc = '${r['barcode']}';
            out.putIfAbsent(bc, () => {'name': r['name']});
            out[bc]!['${r['wh']}'] = r['qty'];
          }
          return out;
        }),
        'docs': docs,
        'events': events,
        'purchaseOrders': await safe(() async {
          final pos = await q('SELECT * FROM purchase_orders ORDER BY id');
          for (final p in pos) {
            p['items'] = await q('SELECT * FROM purchase_order_items WHERE order_id = ${p['id']} ORDER BY id');
          }
          return pos;
        }),
        'purchaseInvoices': await safe(() => q('SELECT * FROM purchase_invoices ORDER BY id')),
        'journal': await safe(() => q(
            'SELECT je.id AS entry_id, je.description AS description, je.reference_type AS reference_type, '
            'je.reference_id AS reference_id, a.code AS account_code, a.name AS account_name, jl.debit AS debit, jl.credit AS credit '
            "FROM journal_entries je JOIN journal_entry_lines jl ON jl.entry_id = je.id JOIN accounts a ON a.id = jl.account_id "
            "WHERE je.reference_type LIKE 'wh%' OR je.reference_type LIKE 'purchase%' ORDER BY je.id, jl.id")),
        'goodsInTransitBalance': git == null
            ? null
            : await safe(() async => (await q('SELECT COALESCE(SUM(debit),0) - COALESCE(SUM(credit),0) AS bal FROM journal_entry_lines WHERE account_id = ${git.id}')).first['bal']),
        'stockMovements': await safe(() => q(
            "SELECT * FROM stock_movements WHERE reference_type LIKE 'wh%' OR reference_type LIKE 'purchase%' ORDER BY id")),
        'batches': await safe(() => q('SELECT * FROM product_batches ORDER BY id')),
        'countTasks': await safe(() async {
          final ts = await q('SELECT * FROM cycle_count_tasks ORDER BY id');
          for (final t in ts) {
            t['items'] = await q('SELECT * FROM cycle_count_items WHERE task_id = ${t['id']} ORDER BY id');
          }
          return ts;
        }),
        'settings': {
          for (final k in ['wh_staged_transfers_enabled', 'wh_receipt_overage_pct', 'warehouse_bins_enabled'])
            k: await db.getSettingValue(k),
        },
        'devices': await safe(() => q('SELECT device_id, name, device_kind, branch_id, revoked, last_seen_at FROM lan_paired_devices')),
      };
    }

    final codes = <Map<String, dynamic>>[];
    late void Function() writeJson;
    Future<void> issue(String branch, [String kind = 'warehouse']) async {
      final id = branch == 'B2' ? b2 : b1;
      final offer = await NetworkService.instance.issueLanPairingCode(
          actorUserId: adminId, deviceKind: kind, branchId: id);
      if (offer == null) {
        log('ISSUE FAILED: issueLanPairingCode returned null');
        return;
      }
      codes.add({
        'branch': branch,
        'kind': kind,
        'branchId': id,
        'code': offer.code,
        'expiresAt': offer.expiresAt.toIso8601String(),
        'qrPayload': offer.qrPayload,
      });
      log('issued $kind code ${offer.code} for $branch');
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
        'warehouses': {'B1': wh1, 'B1b': wh1b, 'B2': wh2},
        'users': {
          'clerk1': {'password': _pwClerk, 'branch': 'B1', 'role': 'warehouse clerk'},
          'clerk2': {'password': _pwClerk2, 'branch': 'B2', 'role': 'warehouse clerk'},
          'clerk3': {'password': _pwClerk3, 'branch': 'B1', 'role': 'warehouse clerk (second counter)'},
          'super1': {'password': _pwSuper, 'branch': 'ALL', 'role': 'warehouse supervisor'},
          'store1': {'password': _pwStore, 'branch': 'B1', 'role': 'storekeeper (transfer, no approve)'},
          'mgr1': {'password': _pwMgr, 'branch': 'B1', 'role': 'stock manager'},
          'acct1': {'password': _pwAcct, 'branch': 'B1', 'role': 'accountant'},
          'cashier1': {'password': _pwCashier, 'branch': 'B1', 'note': 'no warehouse_mobile_access'},
        },
        'products': {
          '6221234567890': {'name': 'Lab Milk', 'B1': 12, 'B2': 99},
          '6229876543210': {'name': 'Lab Juice', 'B1': 7, 'B2': 55},
        },
        'codes': codes,
        'legacySettingBeforeStart': legacySettingBeforeStart ?? 'null',
        'ready': true,
      }));
    };

    // NOTE: LanPairingService keeps ONE pending offer; each issue supersedes
    // the previous code. The driver issues a fresh code before each pairing.
    await ensureProbe();
    await ensurePosProbe();
    await issue('B1');

    // ── command interpreter ──
    Future<String> run(String cmd) async {
      final parts = cmd.split('|');
      switch (parts[0]) {
        case 'setting':
          await db.setSetting(parts[1], parts[2]);
          return 'setting ${parts[1]}=${parts[2]}';
        case 'product':
          {
            final (key, barcode, pname) = (parts[1], parts[2], parts[3]);
            final cost = double.parse(parts[4]);
            final id = await db.insertProduct(ProductsCompanion.insert(
              code: 'LP-$key', name: pname, salePrice: Value(cost * 2), costPrice: Value(cost),
              trackInventory: const Value(true), trackExpiry: Value(parts[5] == '1'), barcode: Value(barcode),
            ));
            for (final (w, qs) in [(wh1, parts[6]), (wh1b, parts[7]), (wh2, parts[8])]) {
              final qty = double.parse(qs);
              if (qty > 0) {
                await db.adjustStock(productId: id, warehouseId: w, quantity: qty, type: 'purchase', unitCost: cost);
              }
            }
            fixtures['products']![key] = {'id': id, 'barcode': barcode, 'name': pname};
            writeFixtures();
            return 'product $key id=$id';
          }
        case 'po':
          {
            final supplier = await db.into(db.parties).insert(
                PartiesCompanion.insert(name: 'Lab Supplier ${parts[1]}', isSupplier: const Value(true)));
            final lines = <Map<String, Object?>>[];
            final items = <PurchaseOrderItemsCompanion>[];
            for (final seg in parts[2].split(',')) {
              final kv = seg.split(':');
              final pid = (fixtures['products']![kv[0]]! as Map)['id'] as int;
              final qty = double.parse(kv[1]);
              items.add(PurchaseOrderItemsCompanion.insert(
                  orderId: 0, productId: pid, quantity: qty, unitCost: 40, total: 40 * qty));
              lines.add({'product': kv[0], 'productId': pid, 'ordered': qty});
            }
            final id = await db.createPurchaseOrder(
                supplierId: supplier, warehouseId: wh1, orderDate: DateTime.now(), items: items);
            await db.updatePurchaseOrderStatus(id, 'sent');
            final po = await db.getPurchaseOrderById(id);
            fixtures['pos']![parts[1]] = {
              'id': id, 'ref': po?.globalId ?? '$id', 'orderNumber': po?.orderNumber, 'lines': lines,
            };
            writeFixtures();
            return 'po ${parts[1]} id=$id number=${po?.orderNumber}';
          }
        case 'count':
          {
            final plan = await db.into(db.cycleCountPlans).insert(
                CycleCountPlansCompanion.insert(name: 'Lab plan ${parts[1]}', warehouseId: wh1));
            final prods = [for (final k in parts[2].split(',')) (fixtures['products']![k]! as Map)['id'] as int];
            final task = await db.into(db.cycleCountTasks).insert(CycleCountTasksCompanion.insert(
                planId: plan, taskDate: DateTime.now(), productCount: Value(prods.length)));
            for (final pid in prods) {
              final bal = await (db.select(db.inventoryBalances)
                    ..where((b) => b.productId.equals(pid) & b.warehouseId.equals(wh1)))
                  .getSingleOrNull();
              await db.into(db.cycleCountItems).insert(CycleCountItemsCompanion.insert(
                  taskId: task, productId: pid, expectedQty: bal?.quantity ?? 0));
            }
            final t = await (db.select(db.cycleCountTasks)..where((x) => x.id.equals(task))).getSingle();
            fixtures['counts']![parts[1]] = {'taskId': task, 'ref': t.globalId ?? '$task', 'products': parts[2]};
            writeFixtures();
            return 'count ${parts[1]} task=$task';
          }
        case 'facts':
          {
            final f = await collectFacts(parts[1]);
            File('${labDir.path}\\facts-${parts[1]}.json')
                .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(jsonDecode(jsonEncode(f, toEncodable: _enc))));
            return 'facts ${parts[1]}';
          }
        case 'convert':
          {
            final store = WhDocStore(db);
            Map<String, Object?> res;
            try {
              final doc = await store.mustGet(parts[1]);
              res = await db.transaction(() => WhReceiptPosting(db, store).convert(doc, acctId));
            } catch (e) {
              res = {'error': '$e'};
            }
            File('${labDir.path}\\api-convert.json').writeAsStringSync(jsonEncode(res, toEncodable: _enc));
            return 'convert ${parts[1]} -> ${jsonEncode(res, toEncodable: _enc)}';
          }
        case 'posapi':
          {
            // posapi|label|user(or -)|METHOD|path|jsonBody|idempotencyKey  (device token of the pos probe tablet)
            final res = await posCall(parts[2], parts[3], parts[4],
                body: parts.length > 5 && parts[5].isNotEmpty ? parts[5] : null,
                key: parts.length > 6 && parts[6].isNotEmpty ? parts[6] : null);
            File('${labDir.path}\\api-${parts[1]}.json')
                .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(jsonDecode(jsonEncode(res, toEncodable: _enc))));
            return 'posapi ${parts[1]} -> ${res['status']}';
          }
        case 'legacy':
          {
            // legacy|label|METHOD|path|deviceId : an OLD-style phone using the shared LAN bearer.
            var tok = ApiAuthMiddleware.activeToken;
            if (tok == null) {
              tok = 'lab-legacy-shared-bearer-0123456789abcdef';
              ApiAuthMiddleware.setToken(tok); // test hook: this machine derived no legacy seed
              log('legacy: no derived bearer on this machine; set a lab bearer');
            }
            final r = await rawHttp(parts[2], parts[3],
                headers: {'authorization': 'Bearer $tok', 'x-device-id': parts[4], 'x-device-name': 'Lab old phone'});
            final res = {'method': parts[2], 'path': parts[3], 'status': r.status, 'body': parseBody(r.body)};
            File('${labDir.path}\\api-${parts[1]}.json')
                .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(jsonDecode(jsonEncode(res, toEncodable: _enc))));
            return 'legacy ${parts[1]} -> ${r.status}';
          }
        case 'legacyfacts':
          {
            final t = LegacyTokenTelemetry.instance;
            final f = {
              'name': parts[1],
              'settingLanLegacyTokenEnabled': await db.getSettingValue('lan_legacy_token_enabled'),
              'settingBeforeStart': legacySettingBeforeStart,
              'requestsAccepted': t.requests,
              'refusedRequests': t.refusedRequests,
              'attempts': [
                for (final a in t.attempts)
                  {'deviceId': a.deviceId, 'name': a.name, 'ip': a.ip, 'accepted': a.accepted, 'refused': a.refused}
              ],
            };
            File('${labDir.path}\\facts-${parts[1]}.json')
                .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(jsonDecode(jsonEncode(f, toEncodable: _enc))));
            return 'legacyfacts ${parts[1]}';
          }
        case 'api':
          {
            // api|label|user|METHOD|path|body|key
            final res = await probeCall(parts[2], parts[3], parts[4],
                body: parts.length > 5 && parts[5].isNotEmpty ? parts[5] : null,
                key: parts.length > 6 && parts[6].isNotEmpty ? parts[6] : null);
            File('${labDir.path}\\api-${parts[1]}.json')
                .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(jsonDecode(jsonEncode(res, toEncodable: _enc))));
            return 'api ${parts[1]} -> ${res['status']}';
          }
      }
      return 'unknown command';
    }

    // ── stay alive, obey commands ──
    final deadline = DateTime.now().add(Duration(minutes: minutes));
    var stop = false;
    var done = 0;
    final ackFile = File('${labDir.path}\\ack.txt');
    while (!stop && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!cmdFile(labDir).existsSync()) continue;
      final lines = cmdFile(labDir).readAsLinesSync();
      for (; done < lines.length; done++) {
        final cmd = lines[done].trim();
        var msg = 'ok';
        if (cmd.isEmpty) {
          ackFile.writeAsStringSync('$done|empty\n', mode: FileMode.append);
          continue;
        }
        log('CMD $cmd');
        try {
          if (cmd.startsWith('issue')) {
            // issue [B1|B2] [pos]  (second word = branch, third = device kind; default warehouse)
            final w = cmd.split(' ');
            await issue(w.length > 1 ? w[1] : 'B1', w.length > 2 ? w[2] : 'warehouse');
          } else if (cmd == 'revoke-all' || cmd == 'list') {
            const sel = 'SELECT device_id, name, device_kind, branch_id, revoked, last_seen_at FROM lan_paired_devices';
            if (cmd == 'revoke-all') {
              for (final r in await db.customSelect(sel).get()) {
                if (r.data['device_id'] == probeDeviceId || r.data['device_id'] == posProbeId) continue; // the lab's own API probes stay paired
                await NetworkService.instance.revokeLanDevice(r.data['device_id'] as String, actorUserId: adminId);
                log('revoked ${r.data['device_id']}');
              }
            }
            File('${labDir.path}\\devices.json')
                .writeAsStringSync(jsonEncode([for (final r in await db.customSelect(sel).get()) r.data]));
          } else if (cmd == 'stop') {
            stop = true;
          } else {
            msg = await run(cmd);
          }
        } catch (e, st) {
          msg = 'ERROR $e';
          log('CMD FAILED $cmd: $e\n$st');
        }
        log('ACK $done $msg');
        ackFile.writeAsStringSync('$done|${msg.replaceAll('\n', ' ')}\n', mode: FileMode.append);
      }
    }
    log('host stopping');
    probeClient.close(force: true);
    await decoy.close(force: true);
    await NetworkService.instance.stopServer();
    File('${labDir.path}\\host.json').writeAsStringSync('{"ready":false}');
  });
}

File cmdFile(Directory d) => File('${d.path}\\cmd.txt');
