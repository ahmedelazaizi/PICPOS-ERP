// P1 (plan 2026-10-24, B.7.1): POST /api/auth/change-password through the real
// middleware chain (in-process): validation, throttling shared with
// /api/auth/session, device-branch scope, duplicate password, idempotent
// replay, session revocation, audit without secrets, rate-limit class.
import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/core/auth/password_policy.dart';
import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/services/api/api_rate_limiter.dart';
import 'package:picpos_erp/services/api/api_session_token.dart';

import '../../helpers/lan_host_harness.dart';

void main() {
  late LanHost host;
  late HostFixture fx;
  late LanDevice dev; // paired `client` device of branch 1

  Map<String, Object> body(String user, String cur, String next) =>
      {'username': user, 'currentPassword': cur, 'newPassword': next};

  Future<ApiResp> change(Map<String, Object> b, {LanDevice? from}) =>
      (from ?? dev).post('/api/auth/change-password', b, withSession: false);

  setUp(() async {
    host = await LanHost.start();
    fx = await HostFixture.seed(host.db);
    dev = LanDevice(host.direct, 'dev-1');
    final offer = await host.issue(kind: 'client', branchId: fx.branch1);
    expect((await dev.pair(offer.code)).status, 200);
  });
  tearDown(() async {
    await dev.dispose();
    await host.close();
  });

  test('200: sets the password, clears the flag, hashes with Argon2id, '
      'returns a session', () async {
    final r = await change(body('cashier1', kInitialPw, 'My#NewPass456'));
    expect(r.status, 200, reason: '$r');
    expect(r.json.keys,
        containsAll(['token', 'userId', 'expiresInMs', 'passwordHash', 'serverTime']));
    expect(ApiSessionToken.verify(r.json['token'] as String), fx.cashierId);
    final row = await host.db.getUserByUsername('cashier1');
    expect(row!.user.forcePasswordChange, isFalse);
    expect(row.user.passwordHash, startsWith(r'$argon2id$'));
    expect(row.user.passwordHash, r.json['passwordHash']);
  });

  test('400: missing fields, short, same as current, same as the username',
      () async {
    expect((await change({'username': 'cashier1'})).status, 400);
    expect((await change({'newPassword': 'abcdefgh1'})).status, 400);
    final short = await change(body('cashier1', kInitialPw, 'short1'));
    expect([short.status, short.code], [400, PasswordPolicyCode.tooShort]);
    final same = await change(body('cashier1', kInitialPw, kInitialPw));
    expect([same.status, same.code], [400, PasswordPolicyCode.sameAsCurrent]);
    expect(validateNewPassword('administrator', null, 'Administrator'),
        PasswordPolicyCode.sameAsUsername);
    expect(await host.db.authenticateUser('cashier1', kInitialPw), isNotNull,
        reason: 'a refused change leaves the password untouched');
  });

  test('401 on a wrong current password; 5 failures lock the bucket SHARED '
      'with /api/auth/session (429)', () async {
    for (var i = 0; i < 5; i++) {
      final r = await change(body('cashier1', 'wrong-$i', 'My#NewPass456'));
      expect([r.status, r.code], [401, 'invalid_credentials']);
    }
    final locked = await change(body('cashier1', kInitialPw, 'My#NewPass456'));
    expect([locked.status, locked.code], [429, 'locked_out']);
    final session = await dev.login('cashier1', kInitialPw);
    expect(session.status, 429, reason: 'one counter for both endpoints');
  });

  test('403 branch_access_denied for a user of another branch; the password '
      'stays', () async {
    final r = await change(body('b2cashier', HostFixture.b2Pw, 'My#NewPass456'));
    expect([r.status, r.code], [403, 'branch_access_denied']);
    expect(await host.db.authenticateUser('b2cashier', HostFixture.b2Pw),
        isNotNull);
  });

  test('409 password_rejected when the password is in use; never names who',
      () async {
    final r = await change(body('cashier1', kInitialPw, HostFixture.acctPw));
    expect([r.status, r.code], [409, 'password_rejected']);
    expect(r.body, isNot(contains('acct1')));
  });

  test('idempotent replay: the same body twice -> 200 twice, one change',
      () async {
    final b = body('cashier1', kInitialPw, 'My#NewPass456');
    final first = await change(b);
    final second = await change(b);
    expect(first.json['alreadyApplied'], isFalse);
    expect([second.status, second.json['alreadyApplied']], [200, true]);
    // a wrong "current" that is not the new password is still a failure
    final bad = await change(body('cashier1', 'nope', 'Other#Pass789'));
    expect(bad.status, 401);
  });

  test('the user\'s older sessions die; the returned one works', () async {
    final before = ApiSessionToken.mint(fx.cashierId);
    final r = await change(body('cashier1', kInitialPw, 'My#NewPass456'));
    expect(ApiSessionToken.verify(before), isNull);
    expect(ApiSessionToken.verify(r.json['token'] as String), fx.cashierId);
  });

  test('card path: only an account still forced to change may use it', () async {
    await (host.db.update(host.db.users)..where((u) => u.id.equals(fx.acctId)))
        .write(const UsersCompanion(cardCode: Value('CARD-ACCT')));
    await (host.db.update(host.db.users)..where((u) => u.id.equals(fx.cashierId)))
        .write(const UsersCompanion(cardCode: Value('CARD-CASH')));
    final denied =
        await change({'cardCode': 'CARD-ACCT', 'newPassword': 'My#NewPass456'});
    expect([denied.status, denied.code], [403, 'card_change_not_allowed']);
    final ok =
        await change({'cardCode': 'CARD-CASH', 'newPassword': 'My#NewPass456'});
    expect(ok.status, 200, reason: '$ok');
    expect(await host.db.authenticateUser('cashier1', 'My#NewPass456'),
        isNotNull);
  });

  test('audit line is written and holds no secret', () async {
    await change(body('cashier1', kInitialPw, 'My#NewPass456'));
    final logs = await host.db.select(host.db.activityLogs).get();
    final mine = logs.where((l) => l.action == 'password_changed_self').toList();
    expect(mine, hasLength(1));
    expect(mine.single.userName, 'cashier1');
    expect(mine.single.description, contains('device=dev-1'));
    for (final l in logs) {
      expect('${l.description} ${l.oldValue} ${l.newValue}',
          isNot(anyOf(contains('My#NewPass456'), contains(kInitialPw))));
    }
  });

  test('a successful change advances users.last_modified_at (sync watermark), '
      'a refused one does not', () async {
    Future<int> stamp() async {
      final r = await host.db
          .customSelect('SELECT last_modified_at AS v FROM users WHERE id = ?',
              variables: [Variable.withInt(fx.cashierId)])
          .getSingle();
      // NULL until the first UPDATE (the SQLite trigger is AFTER UPDATE only).
      return (r.data['v'] as num?)?.toInt() ?? 0;
    }

    // A fresh in-memory schema has no v129 delta-sync trigger (it comes from
    // migrations); install the production one so this proves the password write
    // is a plain UPDATE that leaves `row_version` to the trigger (what the PG
    // twin in test/integration_pg/auth_password_flow_pg_test.dart relies on).
    await host.db.customStatement('''
      CREATE TRIGGER IF NOT EXISTS users_bump_version
      AFTER UPDATE ON users FOR EACH ROW
      WHEN NEW.row_version = OLD.row_version
      BEGIN
        UPDATE users SET last_modified_at = strftime('%s', 'now'),
          row_version = OLD.row_version + 1 WHERE id = NEW.id;
      END
    ''');
    final before = await stamp();
    expect((await change(body('cashier1', 'wrong', 'My#NewPass456'))).status,
        401);
    expect(await stamp(), before, reason: 'a refused change must not bump');
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect((await change(body('cashier1', kInitialPw, 'My#NewPass456'))).status,
        200);
    expect(await stamp(), greaterThan(before),
        reason: 'the sync-pull watermark must advance so other devices get '
            'the new hash');
  });

  test('503 while the session key is not derived', () async {
    ApiSessionToken.clearKey();
    final r = await change(body('cashier1', kInitialPw, 'My#NewPass456'));
    expect(r.status, 503);
    ApiSessionToken.setKeyForTesting('lan-host-harness-key');
  });

  test('it is a credential endpoint: rate-limited in the read class, listed '
      'in the router', () {
    expect(ApiRateLimiter.classifyPath('/api/auth/change-password'),
        ApiRateLimiter.classifyPath('/api/auth/session'));
    expect(ApiRateLimiter.classifyPath('/api/auth/change-password'),
        RateLimitClass.read);
  });

  test('the device bearer is required (the call is not anonymous)', () async {
    final anon = LanDevice(host.direct, 'ghost');
    final r = await anon.post(
        '/api/auth/change-password', body('cashier1', kInitialPw, 'My#NewPass456'),
        withSession: false);
    expect(r.status, anyOf(401, 403));
    expect(await host.db.authenticateUser('cashier1', kInitialPw), isNotNull);
  });
}
