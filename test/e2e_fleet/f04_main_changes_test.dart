// F4 - CHANGES ON THE MAIN reach the devices: new user, password change,
// deactivation, branch removal, role/permission change. Online the main's "no"
// is binding at once; offline the old state is honoured only inside the grace.
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
  setUp(() async => fleet = await Fleet.build(mirror: false));
  tearDown(() => fleet.dispose());

  Future<int> cashierRole() async =>
      (await fleet.main.db.getUserByUsername('cashier'))!.user.roleId!;

  test('F4.1 a user created on the main signs in on the FIRST attempt on both '
      'branch devices (verified on the main, pulled, stamped)', () async {
    final id = await fleet.main.db.createUser(
        username: 'newcomer',
        password: 'Newc#Fleet4321',
        displayName: 'n',
        roleId: await cashierRole());
    await fleet.main.db.setUserBranchAccess(id, [fleet.branch1]);
    for (final d in [fleet.cashier, fleet.accountant]) {
      expect(await d.db.getUserByUsername('newcomer'), isNull, reason: d.label);
      expect(await fleet.login(d, 'newcomer', 'Newc#Fleet4321'), isNotNull,
          reason: '${d.label}: first attempt');
      expect(await d.db.authenticateUser('newcomer', 'Newc#Fleet4321'), isNotNull,
          reason: '${d.label}: now stored locally with the main\'s credential');
    }
  });

  test('F4.2 a password changed on the main: online the old one is refused at '
      'once; during an outage it works only inside the grace, then never',
      () async {
    await fleet.login(fleet.cashier, 'accountant', kAcctPw); // warm, stamped

    await fleet.main.db.updateUserPassword(
        userId: fleet.userIds['accountant']!, newPassword: 'Rotated#Fleet55');
    expect(await fleet.cashier.db.authenticateUser('accountant', kAcctPw), isNotNull,
        reason: 'the device has not learned yet: its local hash still matches');
    expect(await fleet.loginDenied(fleet.cashier, 'accountant', kAcctPw), isTrue,
        reason: 'online: the main says no, at once');
    expect(await fleet.login(fleet.cashier, 'accountant', 'Rotated#Fleet55'), isNotNull);
    expect(await fleet.cashier.db.authenticateUser('accountant', kAcctPw), isNull,
        reason: 'converged: the old hash is gone from the device');

    // the same change while the ACCOUNTANT'S device is cut off
    await fleet.login(fleet.accountant, 'accountant', 'Rotated#Fleet55');
    await fleet.mainDown();
    await fleet.main.db.updateUserPassword(
        userId: fleet.userIds['accountant']!, newPassword: 'Rotated2#Fleet66');
    fleet.now = fleet.now.add(const Duration(days: 3));
    expect(await fleet.login(fleet.accountant, 'accountant', 'Rotated#Fleet55'), isNotNull,
        reason: 'offline inside the grace: the device cannot know yet');
    fleet.now = fleet.now.add(const Duration(days: 6));
    expect(await fleet.loginDenied(fleet.accountant, 'accountant', 'Rotated#Fleet55'), isTrue,
        reason: 'beyond the grace the stale credential is dead');
    await fleet.mainUp();
    expect(await fleet.loginDenied(fleet.accountant, 'accountant', 'Rotated#Fleet55'), isTrue,
        reason: 'back online: refused immediately');
    expect(await fleet.login(fleet.accountant, 'accountant', 'Rotated2#Fleet66'), isNotNull);
  });

  test('F4.3 a deactivated user: refused online at once, and the device '
      'converges (row inactive) after a sync', () async {
    await fleet.main.db.toggleUserActive(
        userId: fleet.userIds['branchadmin']!, isActive: false);
    expect(await fleet.loginDenied(fleet.cashier, 'branchadmin', kBranchAdminPw), isTrue);
    await fleet.login(fleet.cashier, 'cashier', kCashPw); // a live session
    await fleet.syncTables(fleet.cashier, ['users']);
    expect((await (fleet.cashier.db.select(fleet.cashier.db.users)
              ..where((u) => u.username.equals('branchadmin')))
            .getSingle())
        .isActive,
        isFalse,
        reason: 'converged after the sync');
    await fleet.mainDown();
    expect(await fleet.loginDenied(fleet.cashier, 'branchadmin', kBranchAdminPw), isTrue,
        reason: 'and it stays refused while the main is away');
  });

  test('F4.4 a branch removed from a user: refused with the branch message '
      'online, and the assignment disappears from the device after a sync',
      () async {
    await fleet.login(fleet.cashier, 'branchadmin', kBranchAdminPw);
    final id = fleet.userIds['branchadmin']!;
    await fleet.main.db.setUserBranchAccess(id, [fleet.branch2]);
    await expectLater(
        fleet.login(fleet.cashier, 'branchadmin', kBranchAdminPw),
        throwsA(isA<AuthRejectedException>().having(
            (e) => e.message, 'message', contains('ليس لديك صلاحية الدخول لهذا الفرع'))));
    await fleet.login(fleet.cashier, 'cashier', kCashPw);
    await fleet.syncTables(fleet.cashier, ['user_branch_access']);
    final rows = await (fleet.cashier.db.select(fleet.cashier.db.userBranchAccess)
          ..where((r) => r.userId.equals(id)))
        .get();
    expect(rows.where((r) => r.branchId == fleet.branch1), isEmpty,
        reason: 'the removed assignment converged away');
  });

  test('F4.5 a permission revoked from a role on the main: the main refuses '
      'the action and the device\'s copy converges after a sync', () async {
    final cashierId = fleet.userIds['cashier']!;
    expect(await fleet.cashier.db.userHasPermission(cashierId, 'sales_create'), isTrue);
    await fleet.login(fleet.cashier, 'cashier', kCashPw);

    final role = (await fleet.main.db.getUserByUsername('cashier'))!.user.roleId!;
    final all = await fleet.main.db.getAllPermissions();
    final keep = (await fleet.main.db.getPermissionsForRole(role))
        .where((p) => p.code != 'sales_create')
        .map((p) => p.id)
        .toList();
    expect(keep.length, lessThan((await fleet.main.db.getPermissionsForRole(role)).length));
    await fleet.main.db.setRolePermissions(role, keep);
    expect(all, isNotEmpty);

    // enforcement is on the main: the sale is refused (it is queued, not stored)
    final id = await fleet.sell(fleet.cashier,
        invoiceNo: 'NOPERM-1', globalId: 'gid-noperm-1', total: 5, username: 'cashier');
    expect(id, isNull);
    expect(await fleet.main.db.select(fleet.main.db.salesInvoices).get(), isEmpty,
        reason: 'revoked permission: nothing was booked');

    expect(await fleet.cashier.db.userHasPermission(cashierId, 'sales_create'), isTrue,
        reason: 'not converged yet');
    await fleet.syncTables(fleet.cashier, ['role_permissions']);
    expect(await fleet.cashier.db.userHasPermission(cashierId, 'sales_create'), isFalse,
        reason: 'converged after the sync');
  });
}