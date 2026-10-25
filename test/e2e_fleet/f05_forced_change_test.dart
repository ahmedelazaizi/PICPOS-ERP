// F5 - FORCED PASSWORD CHANGE at first login: a user created on the main with a
// temporary password signs in on the cashier device, is told to change it, the
// change is made ON THE MAIN (change-password endpoint), then the new
// credential works on ANOTHER device (accountant) and the temporary one is dead.
@Timeout(Duration(minutes: 4))
library;

import 'dart:io' show HttpOverrides;

import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/domain/repositories/auth_repository.dart';

import '../helpers/fleet_harness.dart';

void main() {
  Fleet.bindEnvironment();
  setUpAll(() => HttpOverrides.global = null);

  late Fleet fleet;
  setUp(() async {
    fleet = await Fleet.build(mirror: false);
    final main = fleet.main.db;
    final id = await main.createUser(
        username: 'newhire',
        password: kNewHireTempPw,
        displayName: 'New hire',
        roleId: (await main.getUserByUsername('cashier'))!.user.roleId,
        forcePasswordChange: true);
    await main.setUserBranchAccess(id, [fleet.branch1]);
  });
  tearDown(() => fleet.dispose());

  test('F5.1 temporary password -> change on the main -> works on another '
      'device; the temporary one is dead everywhere', () async {
    await expectLater(fleet.login(fleet.cashier, 'newhire', kNewHireTempPw),
        throwsA(isA<PasswordChangeRequired>()));

    await fleet.use(fleet.cashier);
    await fleet.repo(fleet.cashier).changeOwnPassword(
        username: 'newhire',
        currentPassword: kNewHireTempPw,
        newPassword: 'Hire#Fleet7788');

    final onMain = await fleet.main.db.authenticateUser('newhire', 'Hire#Fleet7788');
    expect(onMain, isNotNull, reason: 'the change was made ON the main');
    expect(onMain!.user.forcePasswordChange, isFalse);
    expect(await fleet.main.db.authenticateUser('newhire', kNewHireTempPw), isNull);

    expect(await fleet.login(fleet.cashier, 'newhire', 'Hire#Fleet7788'), isNotNull);
    // another device: never saw him; the main vouches, the credential is pulled
    expect(await fleet.login(fleet.accountant, 'newhire', 'Hire#Fleet7788'), isNotNull);
    expect(await fleet.accountant.db.authenticateUser('newhire', 'Hire#Fleet7788'),
        isNotNull);
    expect(await fleet.loginDenied(fleet.accountant, 'newhire', kNewHireTempPw), isTrue);
    expect(await fleet.loginDenied(fleet.cashier, 'newhire', kNewHireTempPw), isTrue);
  });

  test('F5.2 the change is policed on the main (wrong current, short, a '
      'password another user holds) and needs the main to be reachable',
      () async {
    await fleet.use(fleet.cashier);
    final repo = fleet.repo(fleet.cashier);
    Future<void> change(String current, String next) => repo.changeOwnPassword(
        username: 'newhire', currentPassword: current, newPassword: next);

    await expectLater(change('wrong-current-1', 'Hire#Fleet7788'), throwsA(isA<StateError>()));
    await expectLater(change(kNewHireTempPw, 'short'), throwsA(isA<StateError>()));
    await expectLater(change(kNewHireTempPw, kAcctPw), throwsA(isA<StateError>()),
        reason: "another user's password is refused (and never named)");
    expect(await fleet.main.db.authenticateUser('newhire', kNewHireTempPw), isNotNull,
        reason: 'nothing changed on the main');

    await fleet.mainDown();
    await expectLater(change(kNewHireTempPw, 'Hire#Fleet7788'), throwsA(isA<StateError>()),
        reason: 'offline: no change is possible');
    expect((await fleet.cashier.db.select(fleet.cashier.db.syncOutbox).get()), isEmpty,
        reason: 'a plaintext password is never queued');
    await fleet.mainUp();
    await change(kNewHireTempPw, 'Hire#Fleet7788');
    await change(kNewHireTempPw, 'Hire#Fleet7788'); // lost answer: idempotent
    expect(await fleet.main.db.authenticateUser('newhire', 'Hire#Fleet7788'), isNotNull);
  });
}