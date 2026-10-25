// M2 (plan 2026-10-24, MIR-012): the console's CURRENT BRANCH.
//  * the selectable branches are exactly what the main reported; a branch
//    outside them cannot be selected;
//  * the choice is a device-local setting that survives a restart, but is
//    re-validated against the signed-in manager's scope;
//  * it feeds `activeBranchIdProvider` (what screens query), the write payload
//    (`branchId`) and the `X-Branch-Id` header of every server call;
//  * a manager with no branch gets an explicit empty state, never "all".
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/data/providers/mirror_branch_context_provider.dart';
import 'package:picpos_erp/services/mirror_branch_context.dart';
import 'package:picpos_erp/services/network_service.dart';
import 'package:picpos_erp/services/sync/strategies/setting_sync_strategy.dart';

class _SignedIn extends AuthNotifier {
  @override
  AuthState build() => AuthState(
        isAuthenticated: true,
        userWithRole: UserWithRole(
          user: User(
            id: 1,
            username: 'mgr',
            passwordHash: '',
            passwordSalt: '',
            displayName: 'mgr',
            defaultScreen: '0',
            isLocked: false,
            isActive: true,
            discountLimitIsPercent: true,
            forcePasswordChange: false,
            createdAt: DateTime(2026, 1, 1),
            rowVersion: 1,
          ),
        ),
      );
}

MirrorConsoleContext ctx(List<int> ids, {int? def, bool full = false}) =>
    MirrorConsoleContext(
      userId: 1,
      fullAccess: full,
      canConsole: true,
      defaultBranchId: def,
      branches: [for (final i in ids) MirrorBranch(id: i, name: 'B$i')],
    );

void main() {
  late AppDatabase db;
  final bc = MirrorBranchContext.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting();
    bc.reset();
  });
  tearDown(() async {
    bc.reset();
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    await db.close();
  });

  test('the setting is device-local (never pushed or pulled)', () {
    expect(kDeviceLocalSettingKeys, contains(MirrorBranchContext.settingKey));
    expect(isDeviceLocalSettingKey('mirror_current_branch_id'), isTrue);
  });

  test('applyContext selects the main\'s default and persists it', () async {
    await bc.applyContext(ctx([1, 2], def: 1), db: db);
    expect(bc.currentBranchId, 1);
    expect(await db.getSettingValue(MirrorBranchContext.settingKey), '1');
    expect(bc.hasNoBranches, isFalse);
  });

  test('a branch outside the scope cannot be selected; inside it can',
      () async {
    await bc.applyContext(ctx([1, 2], def: 1), db: db);
    expect(await bc.select(3, db: db), isFalse);
    expect(bc.currentBranchId, 1);
    expect(await bc.select(2, db: db), isTrue);
    expect(bc.currentBranchId, 2);
    expect(await db.getSettingValue(MirrorBranchContext.settingKey), '2');
  });

  test('the stored choice survives a restart, and is dropped when it left '
      'the manager\'s scope', () async {
    await db.setSetting(MirrorBranchContext.settingKey, '2');
    await bc.restore(db);
    expect(bc.currentBranchId, 2, reason: 'known before the main answers');
    await bc.applyContext(ctx([1, 2], def: 1), db: db);
    expect(bc.currentBranchId, 2, reason: 'still in scope: kept');

    bc.reset();
    await db.setSetting(MirrorBranchContext.settingKey, '3');
    await bc.restore(db);
    await bc.applyContext(ctx([1, 2], def: 1), db: db);
    expect(bc.currentBranchId, 1, reason: 'branch 3 is no longer his');
  });

  test('a manager with NO branch gets an explicit empty state, no current '
      'branch', () async {
    await bc.applyContext(ctx(const []), db: db);
    expect(bc.hasNoBranches, isTrue);
    expect(bc.currentBranchId, isNull);
  });

  test('activeBranchIdProvider follows the current branch on a mirror, and '
      'switching re-evaluates it', () async {
    NetworkService.instance.debugSetModeForTests(NetworkMode.mirror);
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      authProvider.overrideWith(_SignedIn.new),
    ]);
    addTearDown(container.dispose);
    await bc.applyContext(ctx([1, 2], def: 1), db: db);
    expect(await container.read(activeBranchIdProvider.future), 1);
    expect(container.read(mirrorCurrentBranchProvider), 1);

    await bc.select(2, db: db);
    expect(container.read(mirrorCurrentBranchProvider), 2);
    expect(await container.read(activeBranchIdProvider.future), 2,
        reason: 'screens that read the active branch now query branch 2');
  });

  test('off a mirror the console branch is ignored', () async {
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      authProvider.overrideWith(_SignedIn.new),
    ]);
    addTearDown(container.dispose);
    await bc.applyContext(ctx([5], def: 5), db: db);
    expect(await container.read(activeBranchIdProvider.future), isNot(5));
  });
}
