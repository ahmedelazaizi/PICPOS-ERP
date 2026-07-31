// ═══════════════════════════════════════════════════════════════════════════
// `AuthNotifier.switchUser` — handing the till to another cashier in place.
//
// The invariant that matters most here is NEGATIVE: the session must never be
// unauthenticated, not even for one frame. `main.dart` keys the whole
// MaterialApp on `isAuthenticated`:
//
//     MaterialApp(key: ValueKey('app_auth_$isAuthenticated'), …)
//
// so a single empty state changes that key, tears down the entire widget tree
// and rebuilds it on the login screen — killing the switch dialog mid-flow and
// producing exactly the "it kicked me out to the login screen" report this
// method exists to prevent. `logout()` then `login()` would do that.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/providers/auth_providers.dart';
import 'package:ural_erp/services/network_service.dart';
import 'package:ural_erp/data/database/sync_interceptor.dart';
import 'package:ural_erp/services/shift_dialog_session_guard.dart';
import 'package:ural_erp/services/websocket_sync_client.dart';

UserWithRole _user(int id, String name, {String roleName = 'كاشير'}) {
  final role = Role(
    id: roleName == 'كاشير' ? 1 : 2,
    name: roleName,
    isSystemRole: roleName != 'كاشير',
    createdAt: DateTime(2026),
    rowVersion: 0,
  );
  final user = User(
    id: id,
    username: 'u$id',
    passwordHash: 'h',
    passwordSalt: '',
    displayName: name,
    roleId: role.id,
    defaultScreen: 'pos',
    isLocked: false,
    isActive: true,
    discountLimitIsPercent: true,
    forcePasswordChange: false,
    createdAt: DateTime(2026),
    rowVersion: 0,
  );
  return UserWithRole(user: user, role: role);
}

void main() {
  late ProviderContainer container;

  setUp(() {
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    WebSocketSyncClient.instance.connected.value = false;
    shiftDialogPromptedUserIds.clear();
    container = ProviderContainer();
    container.read(authProvider);
  });

  tearDown(() {
    container.dispose();
    shiftDialogPromptedUserIds.clear();
  });

  test('never passes through an unauthenticated state', () {
    container.read(authProvider.notifier).login(_user(1, 'أحمد'));

    final seen = <bool>[];
    container.listen(
      authProvider,
      (_, next) => seen.add(next.isAuthenticated),
      fireImmediately: false,
    );

    container.read(authProvider.notifier).switchUser(_user(2, 'سارة'));

    expect(seen, isNotEmpty, reason: 'the switch must emit a new state');
    expect(seen.contains(false), isFalse,
        reason: 'an empty AuthState flips the MaterialApp key and rebuilds the '
            'whole tree onto the login screen — the exact bug being fixed');
    expect(container.read(authProvider).isAuthenticated, isTrue);
  });

  test('the incoming user becomes the session user', () {
    container.read(authProvider.notifier).login(_user(1, 'أحمد'));
    container.read(authProvider.notifier).switchUser(_user(2, 'سارة'));

    final state = container.read(authProvider);
    expect(state.user?.id, 2);
    expect(state.user?.displayName, 'سارة');
    // `originalUser` is what checkout stamps on the invoice; it must follow.
    expect(state.originalUser?.id, 2);
  });

  test('sync identity is republished so writes attribute to the new user', () {
    container.read(authProvider.notifier).login(_user(1, 'أحمد'));
    expect(SyncInterceptor.currentUserId, 1);

    container.read(authProvider.notifier)
        .switchUser(_user(2, 'سارة', roleName: 'مدير النظام'));

    expect(SyncInterceptor.currentUserId, 2,
        reason: 'X-User-Id on outbound calls must be the new cashier');
    expect(SyncInterceptor.currentUserRole, 'مدير النظام',
        reason: 'the sync layer branch-filters on this role');
  });

  test('clears the "already prompted to open a shift" marks', () {
    container.read(authProvider.notifier).login(_user(1, 'أحمد'));
    shiftDialogPromptedUserIds.add(1);

    container.read(authProvider.notifier).switchUser(_user(2, 'سارة'));

    expect(shiftDialogPromptedUserIds, isEmpty,
        reason: 'otherwise switching A→B→A leaves A marked as prompted and A '
            'is never asked to open a shift again');
  });

  test('drops a temporary elevation held by the outgoing user', () {
    container.read(authProvider.notifier).login(_user(1, 'أحمد'));
    container.read(authProvider.notifier)
        .elevate(_user(9, 'مدير', roleName: 'مدير النظام'));
    expect(container.read(authProvider).isElevated, isTrue);

    container.read(authProvider.notifier).switchUser(_user(2, 'سارة'));

    expect(container.read(authProvider).isElevated, isFalse,
        reason: 'a manager override granted to the outgoing cashier must not '
            'carry into the incoming one');
    expect(container.read(authProvider).effectiveUser?.id, 2);
  });

  test('logout still fully ends the session (unchanged)', () {
    container.read(authProvider.notifier).login(_user(1, 'أحمد'));
    container.read(authProvider.notifier).logout();

    expect(container.read(authProvider).isAuthenticated, isFalse);
    expect(SyncInterceptor.currentUserId, isNull);
  });
}
