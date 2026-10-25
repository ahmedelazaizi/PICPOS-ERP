// Live rejection by the main system (plan P2 / B.6.1-B.6.2): when the device is
// online the main's answer is binding, even when the local hash matches. The
// answer is cached with the stamp so it survives a later outage.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/data/database/sync_interceptor.dart';
import 'package:picpos_erp/data/repositories/auth_repository_impl.dart';
import 'package:picpos_erp/data/repositories/auth_session_gate.dart' show AuthSessionGate;
import 'package:picpos_erp/domain/repositories/auth_repository.dart';
import 'package:picpos_erp/services/auth/credential_stamp_store.dart';
import 'package:picpos_erp/services/auth/offline_login_policy.dart';
import 'package:picpos_erp/services/network_service.dart';
import 'package:picpos_erp/services/sync/strategies/setting_sync_strategy.dart'
    show isDeviceLocalSettingKey;
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
  late DateTime now;
  late int cashierId;
  var refreshed = 0;
  const pw = 'Cash#Pass123';

  CredentialStampStore stamps() => CredentialStampStore.forDb(db, clock: () => now);

  AuthRepositoryImpl repo() => AuthRepositoryImpl(
        db,
        offlinePolicy: OfflineLoginPolicy(
          store: MemSecure(),
          stamps: stamps(),
          readGraceDays: () async => null,
          clock: () => now,
        ),
        authority: host,
        fetchUserBranchAccess: (_) async => false,
        refreshUsers: () async => refreshed++,
      );

  Future<void> expectRejected(String messagePart) => expectLater(
      repo().authenticateUser('cashier', pw),
      throwsA(isA<StateError>()
          .having((e) => e.message, 'message', contains(messagePart))));

  setUp(() async {
    NetworkService.instance.debugSetModeForTests(NetworkMode.client);
    SyncInterceptor.instance = _Interceptor();
    db = AppDatabase.forTesting();
    host = FakeAuthority();
    refreshed = 0;
    now = DateTime.utc(2026, 11, 1, 8);
    final branch = (await db.select(db.branches).get()).first.id;
    SharedPreferences.setMockInitialValues({'client_branch_id': branch});
    final role = await db.into(db.roles).insert(RolesCompanion.insert(
        name: 'cashier-live', isSystemRole: const Value(false)));
    cashierId = await db.createUser(
        username: 'cashier', password: pw, displayName: 'c', roleId: role);
    await db.setUserBranchAccess(cashierId, [branch]);
  });

  tearDown(() async {
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    SyncInterceptor.instance = null;
    ServerProxy.instance.clearSessions();
    await db.close();
  });

  test('ok: the user is in, the stamp is written (session), the credential '
      'sent is the one the user typed', () async {
    host.acquireOutcome = SessionMintOutcome.ok;
    final u = await repo().authenticateUser('cashier', pw);
    expect(u, isNotNull);
    expect(host.acquireCalls.single.username, 'cashier');
    expect(host.acquireCalls.single.password, pw);
    final s = (await stamps().read(cashierId))!;
    expect([s.src, s.at], [StampSource.session, now]);
    expect(s.fp, credentialFingerprint(u!.user.passwordHash));
  });

  group('the main says no while the local hash still matches', () {
    test('invalidCredential -> rejected with the live message, stamp turns '
        '"rejected", a users refresh is scheduled', () async {
      host.acquireOutcome = SessionMintOutcome.invalidCredential;
      await expectRejected('تغيّرت على النظام الرئيسي');
      expect((await stamps().read(cashierId))!.src, StampSource.rejected);
      expect(refreshed, 1);
    });

    test('the refusal survives a later outage - even in SHADOW mode', () async {
      host.acquireOutcome = SessionMintOutcome.invalidCredential;
      await expectRejected('النظام الرئيسي');
      host.acquireOutcome = SessionMintOutcome.unreachable;
      expect(await db.getSettingValue(OfflineLoginMode.settingKey), isNull,
          reason: 'default mode = shadow');
      await expectRejected('النظام الرئيسي');
    });

    test('...until the main delivers a new credential for that user', () async {
      host.acquireOutcome = SessionMintOutcome.invalidCredential;
      await expectRejected('النظام الرئيسي');
      // the main changed the password: the sync brings the new hash + stamp
      await db.updateUserPassword(userId: cashierId, newPassword: 'New#Pass12345');
      final hash = (await db.getUserById(cashierId))!.user.passwordHash;
      await stamps().stampFromSync(cashierId, hash);
      host.acquireOutcome = SessionMintOutcome.unreachable;
      expect(await repo().authenticateUser('cashier', 'New#Pass12345'), isNotNull);
      expect(await db.authenticateUser('cashier', pw), isNull);
    });

    test('the main later accepts him again -> ok overwrites "rejected"', () async {
      host.acquireOutcome = SessionMintOutcome.invalidCredential;
      await expectRejected('النظام الرئيسي');
      host.acquireOutcome = SessionMintOutcome.ok;
      expect(await repo().authenticateUser('cashier', pw), isNotNull);
      expect((await stamps().read(cashierId))!.src, StampSource.session);
    });

    test('branchDenied -> rejected with the branch message + rejected stamp',
        () async {
      host.acquireOutcome = SessionMintOutcome.branchDenied;
      await expectRejected('ليس لديك صلاحية الدخول لهذا الفرع');
      expect((await stamps().read(cashierId))!.src, StampSource.rejected);
    });

    test('mirrorDenied -> rejected (not a mirror-console account)', () async {
      host.acquireOutcome = SessionMintOutcome.mirrorDenied;
      await expectRejected('كونسول مدير الفروع');
    });

    test('lockedOut -> rejected, but NO "rejected" stamp (the lock is temporary)',
        () async {
      host.acquireOutcome = SessionMintOutcome.lockedOut;
      await expectRejected('قفل الحساب مؤقتاً على النظام الرئيسي');
      expect((await stamps().read(cashierId))?.src, isNot(StampSource.rejected));
    });
  });

  test('passwordChangeRequired -> PasswordChangeRequired(username), no login',
      () async {
    host.acquireOutcome = SessionMintOutcome.passwordChangeRequired;
    await expectLater(
        repo().authenticateUser('cashier', pw),
        throwsA(isA<PasswordChangeRequired>()
            .having((e) => e.username, 'username', 'cashier')
            .having((e) => e.viaCard, 'viaCard', false)));
  });

  group('revoked device', () {
    test('deviceRevoked -> every login is refused, also after the outage '
        '(flag is device-local), until the main accepts the device again',
        () async {
      host.acquireOutcome = SessionMintOutcome.deviceRevoked;
      await expectRejected('أُلغي اعتماد هذا الجهاز');
      expect(await db.getSettingValue('device_revoked_v1'), 'true');
      host.acquireOutcome = SessionMintOutcome.unreachable;
      await expectRejected('أُلغي اعتماد هذا الجهاز');
      host.acquireOutcome = SessionMintOutcome.ok; // re-paired
      expect(await repo().authenticateUser('cashier', pw), isNotNull);
      expect(await db.getSettingValue('device_revoked_v1'), '');
    });
  });

  group('main absent or not recognising this device -> the offline policy', () {
    for (final o in [SessionMintOutcome.unreachable, SessionMintOutcome.deviceUnpaired]) {
      test('$o: stamped user allowed in grace, expired after', () async {
        await stamps().stampFromSync(cashierId, (await db.getUserById(cashierId))!.user.passwordHash);
        host.acquireOutcome = o;
        expect(await repo().authenticateUser('cashier', pw), isNotNull);
        now = now.add(const Duration(days: 8));
        await expectRejected('انتهت مدة الدخول دون اتصال');
      });
    }

    test('a temporary-password user cannot work offline: change it while '
        'connected', () async {
      await db.createUser(
          username: 'temp',
          password: 'Temp#Pass123',
          displayName: 't',
          forcePasswordChange: true);
      final tid = (await db.getUserByUsername('temp'))!.user.id;
      await db.setUserBranchAccess(
          tid, [(await db.select(db.branches).get()).first.id]);
      host.acquireOutcome = SessionMintOutcome.unreachable;
      await expectLater(
          repo().authenticateUser('temp', 'Temp#Pass123'),
          throwsA(isA<StateError>().having(
              (e) => e.message, 'message', contains('يتطلب اتصالًا'))));
    });

    test('ok from the main clears a stale local force-change flag', () async {
      await (db.update(db.users)..where((u) => u.id.equals(cashierId)))
          .write(const UsersCompanion(forcePasswordChange: Value(true)));
      host.acquireOutcome = SessionMintOutcome.ok;
      final u = await repo().authenticateUser('cashier', pw);
      expect(u!.user.forcePasswordChange, isFalse);
      expect((await db.getUserById(cashierId))!.user.forcePasswordChange, isFalse);
    });
  });

  group('changeOwnPassword (online only)', () {
    Future<void> run() => repo().changeOwnPassword(
        username: 'cashier', currentPassword: pw, newPassword: 'Brand#New1234');
    Future<void> expectMsg(String part) => expectLater(
        run(),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains(part))));

    test('ok: the hash the main returned is written locally, flag cleared, '
        'stamped; nothing was sent for local storage', () async {
      final fresh = (await db.getUserById(cashierId))!.user.passwordHash;
      expect(fresh, isNotEmpty);
      // the main returns ITS hash of the new password
      final mainHash = await _hashOf('Brand#New1234');
      host.change = PasswordChangeResult(PasswordChangeOutcome.ok,
          token: 't', userId: cashierId, passwordHash: mainHash, serverTime: now);
      await (db.update(db.users)..where((u) => u.id.equals(cashierId)))
          .write(const UsersCompanion(forcePasswordChange: Value(true)));
      await run();
      final u = (await db.getUserById(cashierId))!.user;
      expect(u.passwordHash, mainHash);
      expect(u.forcePasswordChange, isFalse);
      expect(await db.authenticateUser('cashier', 'Brand#New1234'), isNotNull);
      expect((await stamps().read(cashierId))!.fp, credentialFingerprint(mainHash));
    });

    test('unreachable: refused, local hash untouched (no offline change)',
        () async {
      host.change = const PasswordChangeResult(PasswordChangeOutcome.unreachable);
      final before = (await db.getUserById(cashierId))!.user.passwordHash;
      await expectMsg('يتطلب اتصالًا بالنظام الرئيسي');
      expect((await db.getUserById(cashierId))!.user.passwordHash, before);
    });

    test('older host (404): tells the user to update the main', () async {
      host.change = const PasswordChangeResult(PasswordChangeOutcome.hostTooOld);
      await expectMsg('حدِّث النظام الرئيسي');
    });

    test('policy / duplicate answers become clear messages', () async {
      host.change = const PasswordChangeResult(PasswordChangeOutcome.rejected,
          code: 'password_too_short');
      await expectMsg('8');
      host.change = const PasswordChangeResult(PasswordChangeOutcome.rejected,
          code: 'password_rejected');
      await expectMsg('غير مقبولة');
      host.change = const PasswordChangeResult(PasswordChangeOutcome.lockedOut);
      await expectMsg('قفل الحساب');
    });
  });

  group('shadow -> enforce switch (device-local)', () {
    late int ghostId;
    setUp(() async {
      // an upgraded device that already ran its one-time stamping
      await db.setSetting(CredentialStampStore.bootstrappedKey, 'true');
      ghostId = await db.createUser(
          username: 'ghost', password: 'Gh0st#Pass123', displayName: 'g');
      await db.setUserBranchAccess(
          ghostId, [(await db.select(db.branches).get()).first.id]);
    });

    test('shadow admits the never-delivered user and reports what enforce '
        'would reject; the switch flips it', () async {
      final seen = <String>[];
      AuthRepositoryImpl withHook() => AuthRepositoryImpl(
            db,
            offlinePolicy: OfflineLoginPolicy(
              store: MemSecure(),
              stamps: stamps(),
              readGraceDays: () async => null,
              clock: () => now,
            ),
            authority: host,
            fetchUserBranchAccess: (_) async => false,
            refreshUsers: () async {},
            onShadowWouldReject: (v, id) => seen.add('${v.decision.name}:$id'),
          );
      expect(await withHook().authenticateUser('ghost', 'Gh0st#Pass123'), isNotNull);
      expect(seen, ['notProvisioned:$ghostId']);

      await AuthSessionGate.setMode(db, OfflineLoginMode.enforce);
      expect(await db.getSettingValue('offline_login_mode'), 'enforce');
      await expectLater(withHook().authenticateUser('ghost', 'Gh0st#Pass123'),
          throwsA(isA<AuthRejectedException>().having(
              (e) => e.message, 'message', contains('غير مُسلَّم'))));

      await AuthSessionGate.setMode(db, OfflineLoginMode.shadow); // roll back
      expect(await withHook().authenticateUser('ghost', 'Gh0st#Pass123'), isNotNull);
    });

    test('the switch never overrides the main: a live refusal is binding in '
        'both modes', () async {
      for (final m in OfflineLoginMode.values) {
        await AuthSessionGate.setMode(db, m);
        host.acquireOutcome = SessionMintOutcome.invalidCredential;
        await expectRejected('النظام الرئيسي');
      }
    });

    test('the mode key is device-local (never pushed to / pulled from another '
        'device)', () {
      expect(isDeviceLocalSettingKey('offline_login_mode'), isTrue);
      for (final k in [
        'offline_cred_stamps_v1',
        'offline_cred_stamps_bootstrapped_v1',
        'offline_login_max_seen_v1',
        'device_revoked_v1',
      ]) {
        expect(isDeviceLocalSettingKey(k), isTrue, reason: k);
      }
      expect(isDeviceLocalSettingKey('offline_login_grace_days'), isFalse,
          reason: 'the grace stays a central setting');
    });
  });

  test('B.8: a standalone / main device never calls the main', () async {
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    SyncInterceptor.instance = null;
    host.acquireOutcome = SessionMintOutcome.invalidCredential;
    expect(await repo().authenticateUser('cashier', pw), isNotNull);
    expect(host.acquireCalls, isEmpty);
    expect(host.directCalls, isEmpty);
    expect(await stamps().readAll(), isEmpty);
  });
}

Future<String> _hashOf(String pw) async {
  final d = AppDatabase.forTesting();
  try {
    final id = await d.createUser(username: 'xyz', password: pw, displayName: 'x');
    return (await d.getUserById(id))!.user.passwordHash;
  } finally {
    await d.close();
  }
}
