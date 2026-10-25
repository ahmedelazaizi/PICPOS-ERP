// FLEET harness (owner's reference deployment, in ONE process, REAL HTTP):
//   MAIN (server) <-> ACCOUNTANT (client, B1) / CASHIER (client, B1) / MIRROR.
// NOT a test file. Used by test/e2e_fleet/*.
//
// * The MAIN is a [LanHost]: separate in-memory AppDatabase, the real router
//   behind the real rate limiter + auth middleware, served by `shelf_io` on
//   loopback. It is provisioned with the production `ServerSetupWriter` and
//   committed with the production `ModeActivator`.
// * Every device has its OWN AppDatabase and is installed with the production
//   services only: `ClientLinkService` (pair by code / connectAndSync), the
//   `FirstUserVerifier` (+ `HttpMainAuthPort`), `retireSeededAdmin` (inside the
//   verifier) and `ModeActivator`.
// * The app's singletons (NetworkService, ServerProxy, MirrorState, prefs, the
//   device id, SyncInterceptor) are process-wide, so a device is "switched on"
//   with [Fleet.use]: its saved globals are restored and the previous device's
//   are parked. The clock is injected ([Fleet.now]) into the credential stamps
//   and the offline-login policy - nothing sleeps.
//
// KNOWN-DEFECT shims (see docs/audits/2026-10-24-mirror-and-admin-login/
// FLEET-E2E-RESULTS.md): FLEET-1/3 (missing `GET /api/pos-terminals` and
// `GET /api/sale-bom-consumptions`) are fixed in the router, so their stubs are
// gone. The `/api/user-branch-access` scoping shim
// (FLEET-2) is no longer needed by the tree (F11.3 pins that) and is kept only
// as a safety net. The scenarios that pin the defects (f11) switch the shims
// off with `Fleet.shimOn = false`.
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;

import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/data/database/sync_interceptor.dart';
import 'package:picpos_erp/data/repositories/auth_repository_impl.dart';
import 'package:picpos_erp/data/repositories/auth_session_gate.dart';
import 'package:picpos_erp/domain/repositories/auth_repository.dart';
import 'package:picpos_erp/services/auth/credential_stamp_store.dart';
import 'package:picpos_erp/services/auth/offline_login_policy.dart';
import 'package:picpos_erp/services/client_write_interceptor.dart';
import 'package:picpos_erp/services/delta_pull_service.dart';
import 'package:picpos_erp/services/deployment/commit_result.dart';
import 'package:picpos_erp/services/deployment/mode_activator.dart';
import 'package:picpos_erp/services/device_identity_service.dart';
import 'package:picpos_erp/services/mirror_state.dart';
import 'package:picpos_erp/services/network_service.dart';
import 'package:picpos_erp/services/offline_sync_worker.dart';
import 'package:picpos_erp/services/server_proxy.dart';
import 'package:picpos_erp/services/setup/branch_account_verifier.dart';
import 'package:picpos_erp/services/setup/client_link_service.dart';
import 'package:picpos_erp/services/setup/first_user_verifier.dart';
import 'package:picpos_erp/services/setup/main_auth_port.dart';
import 'package:picpos_erp/services/password_collision_scanner.dart';
import 'package:picpos_erp/services/setup/server_setup_writer.dart';
import 'package:picpos_erp/services/sync_event_bus.dart';
import 'package:picpos_erp/services/sync_service.dart';

import '../unit/auth/stamp_test_support.dart';
import 'lan_host_harness.dart';

/// `FLEET_RUN_KNOWN_DEFECTS=1` runs the tests that pin a product defect (they
/// FAIL on purpose: that is the evidence). Otherwise they are skipped with the
/// stable reason `KNOWN-DEFECT-<id>: ...`.
Object knownDefect(String reason) =>
    Platform.environment['FLEET_RUN_KNOWN_DEFECTS'] == '1' ? false : reason;

/// Passwords of the main's users (all distinct: the collision scanner).
const kMainAdminPw = 'MainAdmin#2026';
const kAcctPw = 'Acct#Fleet4567';
const kCashPw = 'Cash#Fleet4567';
const kBranchAdminPw = 'BrAdm#Fleet789';
const kManagerFleetPw = 'Mgr#Fleet12345';
const kB2Pw = 'B2Emp#Fleet123';
const kNewHireTempPw = 'Temp#Fleet0001';

/// The app's mode/interceptor are PROCESS globals. The in-process main must
/// behave like a separate process: while it handles a request it is a SERVER
/// without a client write interceptor (otherwise its own accounting would try
/// to POST journals to itself through the device's interceptor). Re-entrant.
shelf.Middleware hostIsolation() {
  var depth = 0;
  late SyncInterceptor? savedInterceptor;
  late int? savedUser;
  late NetworkMode savedMode;
  return (inner) => (req) async {
        if (depth++ == 0) {
          savedInterceptor = SyncInterceptor.instance;
          savedUser = SyncInterceptor.currentUserId;
          savedMode = NetworkService.instance.mode;
          SyncInterceptor.instance = null;
          SyncInterceptor.currentUserId = null;
          NetworkService.instance.debugSetModeForTests(NetworkMode.server);
        }
        try {
          return await inner(req);
        } finally {
          if (--depth == 0) {
            SyncInterceptor.instance = savedInterceptor;
            SyncInterceptor.currentUserId = savedUser;
            NetworkService.instance.debugSetModeForTests(savedMode);
          }
        }
      };
}

/// AFTER auth: scopes /api/user-branch-access to the users the same device
/// receives from /api/users (KNOWN-DEFECT FLEET-2).
shelf.Middleware fleetDefectShim(bool Function() enabled) =>
    (inner) => (req) async {
      if (!enabled()) return inner(req);
      final path = req.url.path;
      if (req.method == 'GET' && path == 'api/user-branch-access') {
        final res = await inner(req);
        if (res.statusCode != 200) return res;
        final body = jsonDecode(await res.readAsString()) as Map<String, dynamic>;
        final users = await inner(shelf.Request(
          'GET',
          req.requestedUri.replace(path: '/api/users', query: ''),
          headers: req.headers,
          context: req.context,
        ));
        final feed = jsonDecode(await users.readAsString()) as Map<String, dynamic>;
        final visible = {
          for (final u in (feed['users'] as List? ?? const []))
            (u as Map)['id'] as int,
        };
        final rows = [
          for (final r in (body['user_branch_access'] as List))
            if (visible.contains((r as Map)['userId'])) r,
        ];
        return shelf.Response.ok(
            jsonEncode({'user_branch_access': rows, 'count': rows.length}),
            headers: {'content-type': 'application/json'});
      }
      return inner(req);
    };

/// One branch device (or the mirror).
class FleetDevice {
  FleetDevice(this.label, this.kind);
  final String label;

  /// `client` | `mirror` (what the main binds the pairing code to).
  /// Mutable: a re-provision changes what the device is (see F8).
  String kind;
  final AppDatabase db = AppDatabase.forTesting();
  final MemSecure secure = MemSecure();

  // parked globals
  Map<String, Object> prefs = {};
  String? deviceId;
  String? apiToken;
  NetworkMode mode = NetworkMode.standalone;
  bool linked = false;
  bool mirrorPaired = false;
  int? currentUserId;

  /// Last install report.
  ProvisioningReport? report;
  bool get isMirror => kind == 'mirror';

  Future<void> dispose() async {
    await PasswordCollisionScanner.drain(db);
    await db.close();
  }
}

class ProvisioningReport {
  ProvisioningReport(this.pair, this.sync, this.verification, this.commit);
  final ClientLinkResult pair;
  final ClientLinkResult sync;
  final AccountVerification? verification;
  final CommitResult? commit;
  bool get ok =>
      pair.ok &&
      sync.ok &&
      (verification?.ok ?? false) &&
      commit is CommitOk;
  @override
  String toString() =>
      'pair=${pair.outcome}/${pair.message} sync=${sync.outcome}/${sync.message} '
      'verify=${verification?.ok}/${verification?.error} commit=$commit';
}

class Fleet {
  Fleet._();

  late LanHost main;
  late String base;
  late int port;
  late int branch1;
  late int branch2;
  late Map<String, int> userIds;
  final accountant = FleetDevice('ACCOUNTANT', 'client');
  final cashier = FleetDevice('CASHIER', 'client');
  final mirror = FleetDevice('MIRROR', 'mirror');
  List<FleetDevice> get devices => [accountant, cashier, mirror];

  /// Injected clock (stamps, offline policy). Advance it instead of waiting.
  DateTime now = DateTime.now().toUtc();

  /// When false the unshimmed router answers (defect probes only).
  bool shimOn = true;

  FleetDevice? _active;

  // The offline worker is a process singleton: once a test used it, it is
  // re-pointed at this never-closed database so its timers never touch a
  // closed one.
  static final AppDatabase _sink = AppDatabase.forTesting();
  static bool _workerUsed = false;

  /// A raw HTTP view of [d] (its device token + id), for assertions on what
  /// the main answers to that device. The returned object is NOT a device.
  Future<LanDevice> peer(FleetDevice d) async {
    await use(d);
    final p = LanDevice(main.overHttp(base), d.deviceId!, name: d.label);
    p.deviceToken = ServerProxy.instance.apiToken;
    return p;
  }

  /// Starts the production outbox worker on [d]'s database (offline replay).
  Future<void> startWorker(FleetDevice d) async {
    await use(d);
    _workerUsed = true;
    OfflineSyncWorker.instance.initialize(d.db);
  }

  /// Replays the outbox of [d] through the production worker.
  Future<void> drain(FleetDevice d) async {
    await use(d);
    // The worker's own watchers may already be draining (then our call returns
    // at once): wait, bounded, until nothing is left pending.
    for (var i = 0; i < 200; i++) {
      await OfflineSyncWorker.instance.drainOutbox(force: true);
      if ((await d.db.getPendingSyncItems(limit: 1)).isEmpty) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  /// Calls the main's router DIRECTLY (no shim), for the defect probes.
  Future<ApiResp> rawRouter(String method, String path,
      {Map<String, String> headers = const {}, String? body}) async {
    shimOn = false;
    try {
      return await main.direct(method, path, headers, body);
    } finally {
      shimOn = true;
    }
  }

  // ───────────────────────────── lifecycle ─────────────────────────────

  static void bindEnvironment() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (call) async => null);
  }

  /// The main, provisioned like the first-run server path does (production
  /// `ServerSetupWriter` + `ModeActivator(server)`); devices NOT installed.
  static Future<Fleet> startMain({bool shim = true}) async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    I18nCatalog.setCatalog(const {});
    SharedPreferences.setMockInitialValues({});
    final f = Fleet._();
    f.main = await LanHost.start(
      legacyToken: true,
      now: () => f.now,
      innerShim: (inner) {
        final isolate = hostIsolation();
        return isolate(shim ? fleetDefectShim(() => f.shimOn)(inner) : inner);
      },
    );
    final db = f.main.db;
    // roles the owner created at the main (before users reference them)
    final perms = await db.getAllPermissions();
    int permId(String code) => perms.firstWhere((p) => p.code == code).id;
    final mgrRole = await db
        .into(db.roles)
        .insert(RolesCompanion.insert(name: 'مدير فروع (fleet)'));
    await db.setRolePermissions(mgrRole, [permId('mirror_console')]);
    final branchAdminRole = await db
        .into(db.roles)
        .insert(RolesCompanion.insert(name: 'مسؤول فرع (fleet)'));
    await db.setRolePermissions(
        branchAdminRole, [permId('settings_edit'), permId('pos_access')]);
    await db
        .into(db.roles)
        .insert(RolesCompanion.insert(name: 'موظف فرع (fleet)'));

    final report = await ServerSetupWriter().apply(
      db,
      ServerSetupInput(
        companyName: 'شركة الأسطول',
        currency: 'JOD',
        businessProfile: 'retail',
        businessType: 'retail',
        vatEnabled: true,
        vatRate: 16,
        fiscalYear: DateTime.now().year,
        branchName: 'الفرع الأول',
        branchCode: 'B1',
        warehouseName: 'مخزن الفرع الأول',
        branches: const [ServerSetupBranch(code: 'B2', name: 'الفرع الثاني')],
        adminPassword: kMainAdminPw,
        developerPassword: 'Dev#Fleet12345',
        offlineDays: 7,
        users: [
          const ServerSetupUser(
              name: 'المحاسب', username: 'accountant', password: kAcctPw,
              roleName: 'محاسب', scope: 'B1', forcePasswordChange: false),
          const ServerSetupUser(
              name: 'الكاشير', username: 'cashier', password: kCashPw,
              roleName: 'كاشير', scope: 'B1', forcePasswordChange: false),
          const ServerSetupUser(
              name: 'مسؤول الفرع', username: 'branchadmin', password: kBranchAdminPw,
              roleName: 'مسؤول فرع (fleet)', scope: 'B1', forcePasswordChange: false),
          const ServerSetupUser(
              name: 'مدير الفروع', username: 'manager', password: kManagerFleetPw,
              roleName: 'مدير فروع (fleet)', scope: 'ALL', forcePasswordChange: false),
          const ServerSetupUser(
              name: 'موظف الفرع الثاني', username: 'b2emp', password: kB2Pw,
              roleName: 'موظف فرع (fleet)', scope: 'B2', forcePasswordChange: false),
        ],
      ),
    );
    // the owner lets the accountant collect customer payments
    await grantPermissions(db, 'محاسب', ['sales_edit']);
    await grantPermissions(db, 'موظف فرع (fleet)', ['sales_create', 'sales_view']);
    f.branch1 = report.branchIds['B1']!;
    f.branch2 = report.branchIds['B2']!;
    f.userIds = {
      for (final u in await db.select(db.users).get()) u.username: u.id,
    };
    await db.setSetting('offline_login_grace_days', '7');
    // The main commits its own mode through the production activator.
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    final res = await ModeActivator(db: db).commit(const ActivationPlan(
        mode: NetworkMode.server, host: '127.0.0.1', port: 8080));
    expect(res, isA<CommitOk>(),
        reason: res is CommitFailed ? '${res.reasonCode} ${res.reasonAr}' : '$res');
    f.base = await f.main.serve();
    f.port = Uri.parse(f.base).port;
    return f;
  }

  /// Adds [codes] to the permissions of the role named [roleName] on [db].
  static Future<void> grantPermissions(
      AppDatabase db, String roleName, List<String> codes) async {
    final role = (await db.getAllRoles()).firstWhere((r) => r.name == roleName);
    final all = await db.getAllPermissions();
    final held = (await db.getPermissionsForRole(role.id)).map((p) => p.id).toSet();
    for (final c in codes) {
      held.add(all.firstWhere((p) => p.code == c).id);
    }
    await db.setRolePermissions(role.id, held.toList());
  }

  /// Main + the three devices installed through the production flow.
  static Future<Fleet> build({
    bool shim = true,
    bool mirror = true,
    bool accountant = true,
  }) async {
    final f = await startMain(shim: shim);
    expect((await f.installClient(f.cashier, 'cashier', kCashPw)).ok, isTrue,
        reason: '${f.cashier.report}');
    if (accountant) {
      expect(
          (await f.installClient(f.accountant, 'accountant', kAcctPw)).ok, isTrue,
          reason: '${f.accountant.report}');
    }
    if (mirror) {
      expect((await f.installMirror(f.mirror, 'manager', kManagerFleetPw)).ok,
          isTrue,
          reason: '${f.mirror.report}');
    }
    return f;
  }

  Future<void> dispose() async {
    try {
      await _park();
    } catch (_) {}
    if (_workerUsed) OfflineSyncWorker.instance.initialize(_sink);
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    SyncInterceptor.instance = null;
    SyncInterceptor.currentUserId = null;
    CredentialStampStore.debugClock = null;
    ServerProxy.instance.setApiToken(null);
    ServerProxy.instance.clearSessions();
    MirrorState.instance.debugSetForTests();
    SyncService.clearInstance();
    for (final d in devices) {
      await d.dispose();
    }
    await main.close();
  }

  // ─────────────────────── switching the process globals ───────────────────────

  Future<void> _park() async {
    final d = _active;
    if (d == null) return;
    await Future<void>.delayed(Duration.zero);
    final p = await SharedPreferences.getInstance();
    d.prefs = {for (final k in p.getKeys()) k: p.get(k)!};
    d.apiToken = ServerProxy.instance.apiToken;
    d.deviceId = DeviceIdentityService.instance.tryGetDeviceId();
    d.mode = NetworkService.instance.mode;
    d.currentUserId = SyncInterceptor.currentUserId;
    d.mirrorPaired = MirrorState.instance.isConfigured;
    d.linked = (NetworkService.instance.serverAddress ?? '').isNotEmpty;
  }

  /// Switches the process to [d] (idempotent).
  Future<void> use(FleetDevice d) async {
    if (identical(_active, d)) return;
    await _park();
    _active = d;
    SharedPreferences.setMockInitialValues(Map<String, Object>.from(d.prefs));
    DeviceIdentityService.instance.resetForTest();
    if (d.deviceId != null) {
      DeviceIdentityService.instance.adoptForPairing(d.deviceId!);
    }
    SyncService.clearInstance();
    ServerProxy.instance.clearSessions();
    ServerProxy.instance.setApiToken(d.apiToken);
    NetworkService.instance.debugSetModeForTests(d.mode);
    if (d.linked) {
      NetworkService.instance.setServerAddress('127.0.0.1', port: port);
    }
    if (d.mirrorPaired) {
      MirrorState.instance.debugSetForTests(
        serverDisplayName: '127.0.0.1:$port',
        lastHandshakeAt: now,
      );
    } else {
      MirrorState.instance.debugSetForTests();
    }
    if (d.mode == NetworkMode.client || d.mode == NetworkMode.mirror) {
      ClientWriteInterceptor.setup();
      ClientWriteInterceptor.initialize(d.db);
    } else {
      SyncInterceptor.instance = null;
    }
    SyncInterceptor.currentUserId = d.currentUserId;
    CredentialStampStore.debugClock = () => now;
    DeltaPullService.instance.initialize(d.db);
  }

  /// The main as the active "device" (server mode globals).
  Future<void> useMain() async {
    await _park();
    _active = null;
    NetworkService.instance.debugSetModeForTests(NetworkMode.server);
    SyncInterceptor.instance = null;
    SyncInterceptor.currentUserId = null;
    ServerProxy.instance.clearSessions();
    ServerProxy.instance.setApiToken(null);
    MirrorState.instance.debugSetForTests();
  }

  // ───────────────────────────── installation ─────────────────────────────

  Future<ProvisioningReport> installClient(
      FleetDevice d, String user, String password,
      {String? newPassword, int? branch, bool closeAccessGap = true}) async {
    await use(d);
    final b = branch ?? branch1;
    ActivationHints.clear();
    final offer = await main.issue(kind: 'client', branchId: b);
    final link = ClientLinkService(
        db: d.db, loadBranches: () => d.db.select(d.db.branches).get());
    final pair = await link.pairDevice(
        address: '127.0.0.1', port: port, code: offer.code, deviceName: d.label);
    if (!pair.ok) return d.report = ProvisioningReport(pair, pair, null, null);
    d.deviceId = DeviceIdentityService.instance.tryGetDeviceId();
    final sync = await link.connectAndSync(
        address: '127.0.0.1', port: port, confirmRePair: () async => true);
    if (!sync.ok) return d.report = ProvisioningReport(pair, sync, null, null);
    final v = await _verifier(d).verify(
        username: user, password: password, branchId: b, newPassword: newPassword);
    if (!v.ok) return d.report = ProvisioningReport(pair, sync, v, null);
    if (closeAccessGap) await _closeAccessGap(user, newPassword ?? password, d);
    final commit = await _activate(d, NetworkMode.client);
    return d.report = ProvisioningReport(pair, sync, v, commit);
  }

  Future<ProvisioningReport> installMirror(
      FleetDevice d, String user, String password,
      {bool closeAccessGap = true}) async {
    await use(d);
    ActivationHints.clear();
    final offer = await main.issue(kind: 'mirror');
    final link = ClientLinkService(
        db: d.db, loadBranches: () => d.db.select(d.db.branches).get());
    final pair = await link.pairMirrorWithCode(
        host: '127.0.0.1', port: port, code: offer.code, deviceName: d.label);
    if (!pair.ok) return d.report = ProvisioningReport(pair, pair, null, null);
    d.deviceId = DeviceIdentityService.instance.tryGetDeviceId();
    final sync = await link.connectAndSync(
        address: '127.0.0.1',
        port: port,
        confirmRePair: () async => true,
        mirror: true);
    if (!sync.ok) return d.report = ProvisioningReport(pair, sync, null, null);
    final v = await _verifier(d).verify(username: user, password: password);
    if (!v.ok) return d.report = ProvisioningReport(pair, sync, v, null);
    if (closeAccessGap) await _closeAccessGap(user, password, d);
    final commit = await _activate(d, NetworkMode.mirror);
    return d.report = ProvisioningReport(pair, sync, v, commit);
  }

  /// KNOWN-DEFECT FLEET-5 workaround: the first-user verification delivers the
  /// users (with credentials) but NOT their branch-access rows, and the login's
  /// branch check runs before the session pull. This performs, once, the
  /// token-bearing credential pull the app only does after the check.
  Future<void> _closeAccessGap(String user, String password, FleetDevice d) async {
    final m = await ServerProxy.instance.mintDirect(username: user, password: password);
    if (m.ok) await ServerProxyAuthority().pullCredentialFeeds(d.db, m.token!);
  }

  FirstUserVerifier _verifier(FleetDevice d) => FirstUserVerifier(
        db: d.db,
        port: HttpMainAuthPort(
          baseUrl: base,
          deviceToken: ServerProxy.instance.apiToken ?? '',
          deviceId: DeviceIdentityService.instance.tryGetDeviceId(),
          deviceName: d.label,
        ),
        permissionCodes: (_) async => const [],
        saveClientBranchId: d.isMirror
            ? null
            : (b) async =>
                (await SharedPreferences.getInstance()).setInt('client_branch_id', b),
      );

  Future<CommitResult> _activate(FleetDevice d, NetworkMode mode) async {
    final r = await ModeActivator(db: d.db).commit(ActivationPlan(
        mode: mode, host: '127.0.0.1', port: port));
    if (r is CommitOk) {
      await d.db.setSetting('setup_completed', 'true');
      ClientWriteInterceptor.setup();
      ClientWriteInterceptor.initialize(d.db);
    }
    return r;
  }
  // ───────────────────────────── helpers ─────────────────────────────

  /// Production repository of [d] (real gate/policy/stamps, injected clock).
  AuthRepositoryImpl repo(FleetDevice d,
          {void Function(OfflineLoginVerdict, int)? onShadow}) =>
      AuthRepositoryImpl(
        d.db,
        onShadowWouldReject: onShadow,
        offlinePolicy: OfflineLoginPolicy(
          store: d.secure,
          stamps: CredentialStampStore.forDb(d.db, clock: () => now),
          readGraceDays: () async =>
              int.tryParse(await d.db.getSettingValue('offline_login_grace_days') ?? ''),
          clock: () => now,
        ),
        refreshUsers: () async {
          final s = SyncService(
              serverUrl: NetworkService.instance.buildServerUrl(), localDb: d.db);
          await s.initialize();
          await s.syncTable('users');
        },
      );

  /// Sign-in on [d] through `AuthRepositoryImpl` (gate + policy). Throws what
  /// the app would show.
  Future<UserWithRole?> login(FleetDevice d, String user, String password) async {
    await use(d);
    UserWithRole? u;
    try {
      u = await repo(d).authenticateUser(user, password);
    } finally {
      await settle();
    }
    if (u != null) SyncInterceptor.currentUserId = u.user.id;
    return u;
  }

  /// A successful online sign-in fires a background DeltaPull.pullAll()
  /// (fire-and-forget in production). Wait for it so the next step of a
  /// scenario never races it (the only wait in the suite, bounded).
  Future<void> settle() async {
    if (!main.isServing) return; // a pull against a stopped main only fails slowly
    await Future<void>.delayed(const Duration(milliseconds: 30));
    for (var i = 0; i < 1200 && SyncEventBus.instance.isPulling.value; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  /// True when the sign-in is DENIED the way the app denies it: the gate
  /// throws [AuthRejectedException] / [PasswordChangeRequired], or the
  /// repository returns null (wrong credentials).
  Future<bool> loginDenied(FleetDevice d, String user, String password) async {
    try {
      return await login(d, user, password) == null;
    } on AuthRejectedException {
      return true;
    } on PasswordChangeRequired {
      return true;
    }
  }

  Future<void> setGateMode(FleetDevice d, OfflineLoginMode m) =>
      AuthSessionGate.setMode(d.db, m);

  /// The main stops answering (sockets closed, data kept) / answers again on
  /// the SAME address.
  Future<void> mainDown() async {
    await settle();
    await main.stopServing();
    // No in-memory session survives into the outage (a login during it holds
    // only the proof; the app mints the token on reconnection).
    ServerProxy.instance.clearSessions();
  }

  Future<void> mainUp() async {
    if (!main.isServing) await main.serve(port: port);
    await settle();
  }

  /// `SyncService.syncTable` for [tables] on [d] (the production pull).
  Future<void> syncTables(FleetDevice d, List<String> tables) async {
    await use(d);
    final s = SyncService(
        serverUrl: NetworkService.instance.buildServerUrl(), localDb: d.db);
    await s.initialize();
    for (final t in tables) {
      await s.syncTable(t);
    }
  }

  /// The production delta pull (/api/sync/pull) of [tables] on [d].
  Future<void> deltaPull(FleetDevice d, List<String> tables) async {
    await use(d);
    DeltaPullService.instance.initialize(d.db);
    await DeltaPullService.instance.pullMultiple(tables);
  }

  /// A sale payload as the POS builds it, through the REAL
  /// `ClientWriteInterceptor.submitSale` (HTTP first, outbox when unreachable).
  Future<int?> sell(FleetDevice d,
      {required String invoiceNo,
      required String globalId,
      required double total,
      double? paid,
      required String username,
      bool onCredit = false}) async {
    await use(d);
    final wh = (await d.db.select(d.db.warehouses).get()).first.id;
    // a credit sale is booked to a customer (collections post to his account)
    final customer = onCredit
        ? (await d.db.select(d.db.parties).get())
            .firstWhere((p) => p.isCustomer && (p.globalId ?? '').isNotEmpty)
        : null;
    return ClientWriteInterceptor.submitSale({
      if (customer != null) 'customerId': customer.id,
      if (customer != null) 'customerGlobalId': customer.globalId,
      'invoiceNumber': invoiceNo,
      'globalId': globalId,
      'subtotal': total,
      'total': total,
      'paid': paid ?? total,
      'paymentMethod': 'cash',
      'warehouseId': wh,
      'branchId': branch1,
      'userId': SyncInterceptor.currentUserId ?? userIds[username],
      'createdByUsername': username,
      'items': <Object>[],
    });
  }
}
