import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers/auth_providers.dart';
import 'sync_event_bus.dart';

/// Bridges Drift-side sync events → Riverpod permission providers.
///
/// **The problem this solves**
///
/// `currentUserPermissionsProvider`, `userAllowedScreensProvider`, and
/// `userNavItemsProvider` (all in `data/providers/auth_providers.dart`) are
/// `FutureProvider`s that depend on `authProvider` only — they do NOT watch
/// the `role_permissions` / `users` / `roles` / `permissions` tables.
///
/// When the server pushes a permission change to this client (via WebSocket
/// `data_changed`) and the matching sync strategy refreshes the SQLite tables,
/// Drift's internal `watch()` streams fire — but Riverpod's FutureProviders
/// are not Drift-aware, so they keep serving cached values.
///
/// Result without this bridge: the user has to manually re-sync, log out, or
/// restart the app to see updated permissions. The `PermissionGuard` widget
/// keeps reading the stale cache and shows the "manager override password"
/// dialog even when the permission was just granted.
///
/// **How this bridge works**
///
/// Each permission-affecting sync strategy (`RolePermissionSyncStrategy`,
/// `UserSyncStrategy`, `PermissionSyncStrategy`, `RoleSyncStrategy`) emits a
/// `SyncTablePulled(table, …)` event after `db.markTablesUpdated(...)`.
/// `DeltaPullService.pullTable` already emits the same event for tables it
/// handles. This class subscribes to `SyncEventBus.instance.stream`, filters
/// for the four permission-affecting tables, and explicitly invalidates the
/// Riverpod providers so the next read re-queries the now-refreshed DB.
///
/// **Activation**
///
/// `main_desktop.dart` (or any place with access to a `ProviderContainer` /
/// `Ref`) must call `ref.read(permissionSyncBridgeProvider)` once at startup
/// to materialise the bridge. Riverpod keeps it alive for the app lifetime
/// because `Provider` results are cached until the container is disposed.
class PermissionSyncBridge {
  PermissionSyncBridge._(this._ref) {
    _sub = SyncEventBus.instance.stream.listen(_onEvent);
  }

  final Ref _ref;
  StreamSubscription<SyncEvent>? _sub;

  /// Tables whose changes affect what the user is allowed to do or see.
  /// Any other `SyncTablePulled` event is ignored.
  static const _permissionTables = <String>{
    'role_permissions',
    'users',
    'permissions',
    'roles',
  };

  void _onEvent(SyncEvent event) {
    if (event is! SyncTablePulled) return;
    if (!_permissionTables.contains(event.table)) return;
    // Invalidate every provider that reads from these tables. Riverpod will
    // re-run them lazily on next watch.
    _ref.invalidate(currentUserPermissionsProvider);
    _ref.invalidate(userAllowedScreensProvider);
    _ref.invalidate(userNavItemsProvider);
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}

/// One-shot provider that materialises the bridge. Read it once at app
/// startup — `Provider` caches the value, so subsequent reads are no-ops.
final permissionSyncBridgeProvider = Provider<PermissionSyncBridge>((ref) {
  final bridge = PermissionSyncBridge._(ref);
  ref.onDispose(bridge.dispose);
  return bridge;
});
