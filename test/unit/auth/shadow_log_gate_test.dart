// Login leftover #1: the session gate persists what shadow mode would have
// refused (so the settings screen can summarise it), and only in shadow.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:picpos_erp/core/logging/diagnostic_logger.dart';
import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/data/repositories/auth_session_gate.dart';
import 'package:picpos_erp/data/database/daos/user_credential_dao.dart';
import 'package:picpos_erp/services/auth/credential_stamp_store.dart';
import 'package:picpos_erp/services/auth/offline_login_policy.dart';
import 'package:picpos_erp/services/auth/shadow_login_log.dart';
import 'package:picpos_erp/services/network_service.dart';
import 'package:picpos_erp/services/client_write_interceptor.dart';
import 'package:picpos_erp/services/mirror_state.dart';
import 'package:picpos_erp/services/server_proxy.dart';
import 'package:picpos_erp/domain/repositories/auth_repository.dart';

class _MemStore implements OfflineLoginStore {
  String? v;
  @override
  Future<String?> read() async => v;
  @override
  Future<void> write(String json) async => v = json;
}

/// The main is unreachable: the gate falls back to the offline policy.
class _DownMain implements SessionAuthorityPort {
  @override
  Future<SessionMintResult> acquire(
          {required int userId, String? username, String? password, String? cardCode}) async =>
      const SessionMintResult(SessionMintOutcome.unreachable);
  @override
  Future<SessionMintResult> mintDirect(
          {String? username, String? password, String? cardCode}) async =>
      const SessionMintResult(SessionMintOutcome.unreachable);
  @override
  Future<PasswordChangeResult> changeOwnPassword({
    String? username,
    String? currentPassword,
    String? cardCode,
    required String newPassword,
  }) async =>
      throw UnimplementedError();
  @override
  Future<bool> pullCredentialFeeds(AppDatabase db, String token) async => false;
  @override
  bool hasSessionToken(int userId) => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late AuthSessionGate gate;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    DiagnosticLogger.enableTestMode();
    db = AppDatabase.forTesting();
    await db.getBranches();
    ClientWriteInterceptor.setup();
    NetworkService.instance.debugSetModeForTests(NetworkMode.client);
    MirrorState.instance.debugSetForTests();
    final stamps = CredentialStampStore.forDb(db);
    gate = AuthSessionGate(
      db: db,
      policy: OfflineLoginPolicy(
        store: _MemStore(),
        stamps: stamps,
        readGraceDays: () async => null,
      ),
      stamps: stamps,
      authority: _DownMain(),
      refreshUsers: () async {},
    );
  });

  tearDown(() async {
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await db.close();
  });

  Future<UserWithRole> admin() async {
    await db.clearForcePasswordChangeFlag(1); // a temporary password cannot work offline
    return (await db.getUserById(1))!;
  }

  test('shadow: a never-delivered account is allowed AND recorded', () async {
    await AuthSessionGate.setMode(db, OfflineLoginMode.shadow);
    final out = await gate.afterLocalSuccess(await admin(), username: 'admin');
    expect(out.user.id, 1, reason: 'shadow still lets the user in');

    final s = await ShadowLoginLog(db).summary();
    expect(s.total, 1);
    expect(s.accounts, 1);
    expect(s.byDecision[OfflineLoginDecision.notProvisioned], 1);
  });

  test('enforce: the same account is refused and nothing is logged as '
      '"would reject"', () async {
    await AuthSessionGate.setMode(db, OfflineLoginMode.enforce);
    await expectLater(
        gate.afterLocalSuccess(await admin(), username: 'admin'),
        throwsA(isA<AuthRejectedException>()));
    expect((await ShadowLoginLog(db).summary()).isClean, isTrue);
  });

  test('a delivered account (fresh stamp) is allowed and not logged',
      () async {
    await AuthSessionGate.setMode(db, OfflineLoginMode.shadow);
    final u = await admin();
    await gate.policy.recordVerified(u.user.id, passwordHash: u.user.passwordHash);
    await gate.afterLocalSuccess(u, username: 'admin');
    expect((await ShadowLoginLog(db).summary()).isClean, isTrue);
  });

  test('switching shadow -> enforce -> shadow is a plain device-local setting',
      () async {
    expect(await gate.mode(), OfflineLoginMode.shadow, reason: 'default');
    await AuthSessionGate.setMode(db, OfflineLoginMode.enforce);
    expect(await gate.mode(), OfflineLoginMode.enforce);
    await AuthSessionGate.setMode(db, OfflineLoginMode.shadow);
    expect(await gate.mode(), OfflineLoginMode.shadow);
  });
}
