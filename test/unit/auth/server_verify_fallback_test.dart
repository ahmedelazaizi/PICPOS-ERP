// B.6.3 (plan P2): a user unknown to this device is verified ON THE MAIN; only
// then are users + branch access pulled - with that user's token. A password
// without a username is never sent as a password, and the login screen no
// longer pulls users anonymously (the CRED-WIPE trigger).
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/data/database/sync_interceptor.dart';
import 'package:picpos_erp/data/repositories/auth_repository_impl.dart';
import 'package:picpos_erp/domain/repositories/auth_repository.dart';
import 'package:picpos_erp/services/auth/credential_stamp_store.dart';
import 'package:picpos_erp/services/auth/offline_login_policy.dart';
import 'package:picpos_erp/services/network_service.dart';
import 'package:picpos_erp/services/server_proxy.dart';

import 'fake_authority.dart';
import 'stamp_test_support.dart';

class _Interceptor extends SyncInterceptor {
  @override
  bool get isClientModeImpl => true;
  @override
  bool get isMirrorModeImpl => false;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late FakeAuthority host;
  late int branch;
  late int roleId;
  const pw = 'New#Cashier123';

  AuthRepositoryImpl repo() => AuthRepositoryImpl(
        db,
        offlinePolicy: OfflineLoginPolicy(
          store: MemSecure(),
          stamps: CredentialStampStore.forDb(db),
          readGraceDays: () async => null,
        ),
        authority: host,
        fetchUserBranchAccess: (_) async => false,
        refreshUsers: () async {},
      );

  /// What a token-bearing pull does: the row + its branch access arrive.
  Future<bool> deliverNewCashier(AppDatabase d, String token) async {
    final id = await d.createUser(
        username: 'newbie', password: pw, displayName: 'n', roleId: roleId);
    await d.setUserBranchAccess(id, [branch]);
    return true;
  }

  setUp(() async {
    NetworkService.instance.debugSetModeForTests(NetworkMode.client);
    SyncInterceptor.instance = _Interceptor();
    db = AppDatabase.forTesting();
    host = FakeAuthority();
    branch = (await db.select(db.branches).get()).first.id;
    SharedPreferences.setMockInitialValues({'client_branch_id': branch});
    roleId = await db.into(db.roles).insert(RolesCompanion.insert(
        name: 'cashier-fb', isSystemRole: const Value(false)));
  });

  tearDown(() async {
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    SyncInterceptor.instance = null;
    ServerProxy.instance.clearSessions();
    await db.close();
  });

  test('a user created on the main logs in on the FIRST attempt while online: '
      'verified there, pulled with his token, then admitted locally', () async {
    host.directOutcome = SessionMintOutcome.ok;
    host.acquireOutcome = SessionMintOutcome.ok;
    host.onPull = deliverNewCashier;
    final u = await repo().authenticateUser('newbie', pw);
    expect(u, isNotNull);
    expect(host.directCalls.single.username, 'newbie');
    expect(host.directCalls.single.password, pw);
    expect(host.pulls, 1);
    expect(host.acquireCalls, hasLength(1), reason: 'normal session afterwards');
  });

  test('wrong password for an unknown user: the main says no -> null, no pull',
      () async {
    host.directOutcome = SessionMintOutcome.invalidCredential;
    expect(await repo().authenticateUser('newbie', 'nope'), isNull);
    expect(host.pulls, 0);
  });

  test('main unreachable -> null (the device cannot invent an account)',
      () async {
    expect(await repo().authenticateUser('newbie', pw), isNull);
    expect(host.pulls, 0);
  });

  test('the main accepted but demands a new password -> '
      'PasswordChangeRequired (no pull, no login)', () async {
    host.directOutcome = SessionMintOutcome.passwordChangeRequired;
    await expectLater(repo().authenticateUser('newbie', 'Temp#Pass123'),
        throwsA(isA<PasswordChangeRequired>()));
    expect(host.pulls, 0);
  });

  test('a password with NO username is never sent as a password: only '
      'as a card code', () async {
    await repo().authenticateByPasswordOrCard('Some#Typed1').catchError((_) => null);
    for (final c in host.directCalls) {
      expect(c.password, isNull);
      expect(c.username, isNull);
      expect(c.cardCode, 'Some#Typed1');
    }
  });

  test('fresh device (no credentials ever delivered) + password only -> '
      'asks for the username', () async {
    await expectLater(
        repo().authenticateByPasswordOrCard('Some#Typed1'),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('أدخل اسم المستخدم'))));
  });

  test('an unknown CARD is verified on the main and the user pulled',
      () async {
    host.directOutcome = SessionMintOutcome.ok;
    host.acquireOutcome = SessionMintOutcome.ok;
    host.onPull = (d, t) async {
      final id = await d.createUser(
          username: 'cardy',
          password: 'Card#Pass123',
          displayName: 'c',
          roleId: roleId,
          cardCode: 'CARD-77');
      await d.setUserBranchAccess(id, [branch]);
      return true;
    };
    expect(await repo().authenticateByCardCode('CARD-77'), isNotNull);
    expect(host.directCalls.single.cardCode, 'CARD-77');
  });

  test('standalone / main: no verification on the main at all', () async {
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    SyncInterceptor.instance = null;
    expect(await repo().authenticateUser('newbie', pw), isNull);
    expect(host.directCalls, isEmpty);
  });

  test('the login screen no longer pulls users anonymously (CRED-WIPE trigger)',
      () {
    final src = File('lib/presentation/screens/login_screen.dart').readAsStringSync();
    expect(src, isNot(contains("performTableSync(serverUrl, 'users')\n")));
    expect(src, isNot(contains('Local auth failed in client mode')));
    expect(src, contains('on PasswordChangeRequired'));
  });
}
