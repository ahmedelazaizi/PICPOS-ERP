import 'dart:async' show unawaited;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/config/app_config.dart';
import '../../core/config/business_profile_provider.dart';
import '../../core/navigation/screen_id.dart';
import '../../core/permissions/permission_codes.dart';
import '../../services/login_rate_limiter.dart';
import '../../services/network_service.dart';
import '../../services/server_proxy.dart';
import '../../services/websocket_sync_client.dart';
import '../database/sync_interceptor.dart';
import 'providers.dart';
import 'e_invoicing_providers.dart';
import '../../services/shift_dialog_session_guard.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ROLES & PERMISSIONS PROVIDERS
// ═══════════════════════════════════════════════════════════════════════════

/// All roles provider
final allRolesProvider = StreamProvider.autoDispose<List<Role>>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  return repo.watchRoles();
});

/// All branches provider for management UI
final allBranchesProvider = StreamProvider.autoDispose<List<Branche>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchBranches();
});

/// All cost centers provider for filtering and display in invoice screens.
///
/// Spec 111 — deduplicates by case-folded name on the way out so multi-row
/// duplicates (sync artifacts, manual misentry) do not bloat dropdowns. The
/// oldest id within a name group wins so foreign keys keep pointing at the
/// canonical row; siblings are surfaced via DiagnosticLogger so the operator
/// can clean them up via the maintenance tools.
final allCostCentersProvider = StreamProvider.autoDispose<List<CostCenter>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchCostCenters().map(_dedupCostCentersByName);
});

List<CostCenter> _dedupCostCentersByName(List<CostCenter> raw) {
  if (raw.isEmpty) return raw;
  final byName = <String, CostCenter>{};
  final droppedNames = <String>[];
  for (final cc in raw) {
    final key = cc.name.trim().toLowerCase();
    final existing = byName[key];
    if (existing == null) {
      byName[key] = cc;
    } else {
      // Keep the oldest id (most likely the canonical row).
      if (cc.id < existing.id) {
        byName[key] = cc;
      }
      droppedNames.add(cc.name);
    }
  }
  if (droppedNames.isNotEmpty) {
    debugPrint(
      '[COST-CENTER-WARN] dedup removed ${droppedNames.length} '
      'duplicate cost-center rows from dropdown '
      '(names=${droppedNames.toSet().toList()}). '
      'Run the maintenance tool to dedup at the source.',
    );
  }
  return byName.values.toList();
}

/// All permissions provider
final allPermissionsProvider = FutureProvider<List<Permission>>((ref) async {
  final repo = ref.watch(authRepositoryProvider);
  return repo.getAllPermissions();
});

/// Current role permissions provider
final rolePermissionsProvider = FutureProvider.family<List<Permission>, int>((
  ref,
  roleId,
) async {
  final repo = ref.watch(authRepositoryProvider);
  return repo.getPermissionsForRole(roleId);
});

/// All users provider
final allUsersProvider = StreamProvider.autoDispose<List<UserWithRole>>((ref) {
  // Web stub or actual implementation
  final repo = ref.watch(authRepositoryProvider);
  return repo.watchAllUsers();
});

// ═══════════════════════════════════════════════════════════════════════════
// AUTH STATE WITH SESSION SECURITY
// ═══════════════════════════════════════════════════════════════════════════

class AuthState {
  final UserWithRole? userWithRole;
  final bool isAuthenticated;
  final DateTime? loginTime;
  final DateTime? lastActivity;

  /// Temporary elevation: an admin/manager who granted access.
  final UserWithRole? elevatedBy;
  final DateTime? elevationTime;

  /// Feature 004 (US3) — true while a System Admin ('مدير النظام') is logged
  /// in to a paired client device AND the server connection is live. Toggles
  /// off automatically when the connection drops and back on when it returns
  /// (see [AuthNotifier._recomputeElevation]). Drives cross-branch visibility
  /// (`branchScopeProvider`), the read-only banner ([mutationGuardProvider]),
  /// and activity-log tagging ([_maybeMarkElevated]).
  final bool isCrossBranchElevated;

  static const Duration sessionTimeout = Duration(hours: 8);
  static const Duration inactivityTimeout = Duration(minutes: 15);

  const AuthState({
    this.userWithRole,
    this.isAuthenticated = false,
    this.loginTime,
    this.lastActivity,
    this.elevatedBy,
    this.elevationTime,
    this.isCrossBranchElevated = false,
  });

  User? get user => userWithRole?.user;
  Role? get role => userWithRole?.role;

  bool get isElevated => elevatedBy != null;
  User? get effectiveUser => elevatedBy?.user ?? user;
  Role? get effectiveRole => elevatedBy?.role ?? role;
  User? get originalUser => user;

  bool get isAdmin {
    final roleName = effectiveRole?.name.toLowerCase() ?? '';
    return roleName.contains('admin') ||
        roleName.contains('مدير النظام') ||
        roleName.contains('مسؤول');
  }

  bool get isManager {
    final roleName = effectiveRole?.name.toLowerCase() ?? '';
    return isAdmin || roleName.contains('مدير') || roleName.contains('manager');
  }

  /// Is the *originally logged-in* user an admin, ignoring any temporary
  /// elevation? Used by UI gates that must never be bypassed by a stuck
  /// / stale elevation session (e.g. the sidebar password prompt — a
  /// cashier who once received a manager override should still face the
  /// prompt if the elevation is ambiguous or the guard fires during a
  /// transition). Pairs with [isAdmin] (which honours elevation).
  bool get isOriginallyAdmin {
    final roleName = role?.name.toLowerCase() ?? '';
    return roleName.contains('admin') ||
        roleName.contains('مدير النظام') ||
        roleName.contains('مسؤول');
  }

  /// Same idea as [isOriginallyAdmin] but for managers.
  bool get isOriginallyManager {
    final roleName = role?.name.toLowerCase() ?? '';
    return isOriginallyAdmin ||
        roleName.contains('مدير') ||
        roleName.contains('manager');
  }

  bool get isCashier {
    final roleName = role?.name.toLowerCase() ?? '';
    return roleName.contains('كاشير') || roleName.contains('cashier');
  }

  bool get isSessionExpired {
    if (loginTime == null || !isAuthenticated) return true;
    return DateTime.now().difference(loginTime!) > sessionTimeout;
  }

  bool get isInactive {
    if (lastActivity == null || !isAuthenticated) return true;
    return DateTime.now().difference(lastActivity!) > inactivityTimeout;
  }

  Duration get remainingSessionTime {
    if (loginTime == null) return Duration.zero;
    final elapsed = DateTime.now().difference(loginTime!);
    final remaining = sessionTimeout - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  String get sessionInfo {
    if (!isAuthenticated || user == null) return '';
    final remaining = remainingSessionTime;
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes % 60;
    return '$hours:${minutes.toString().padLeft(2, '0')}';
  }

  AuthState copyWith({
    UserWithRole? userWithRole,
    bool? isAuthenticated,
    DateTime? loginTime,
    DateTime? lastActivity,
    UserWithRole? Function()? elevatedByFn,
    DateTime? Function()? elevationTimeFn,
    bool? isCrossBranchElevated,
  }) {
    return AuthState(
      userWithRole: userWithRole ?? this.userWithRole,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      loginTime: loginTime ?? this.loginTime,
      lastActivity: lastActivity ?? this.lastActivity,
      elevatedBy: elevatedByFn != null ? elevatedByFn() : elevatedBy,
      elevationTime: elevationTimeFn != null
          ? elevationTimeFn()
          : elevationTime,
      isCrossBranchElevated:
          isCrossBranchElevated ?? this.isCrossBranchElevated,
    );
  }
}

/// قرار «ده مدير نظام فيتجاوز الصلاحيات؟» — المصدر الوحيد.
///
/// ── ليه مش `isAdmin || isManager` ────────────────────────────────────────
/// الاتنين دول بيتحددوا بمطابقة **نص اسم الدور**: `isManager` بترجّع `true`
/// لأي دور اسمه فيه «مدير». الأدوار المزروعة «مدير مالي» و«مدير فرع»
/// و«مدير مخزون» كلهم كانوا بيتجاوزوا كل صلاحيات الشاشات والقائمة، فسحب
/// صلاحية منهم ما كانش بيسري — وده كان البلاغ.
///
/// وكمان كان بيخالف طبقة قاعدة البيانات: `_isAdminRole` في
/// `permissions_dao.dart` صارمة (`isSystemRole && name == 'مدير النظام'`).
/// الطبقتين لازم يتفقوا على مين المدير، فده بيطابقها بالحرف.
///
/// شرط `isSystemRole` مقصود: من غيره أي مشغّل يخترع دور مخصص بالاسم ده
/// ويتجاوز كل حاجة.
extension AuthStateBypass on AuthState {
  bool get hasSystemAdminBypass {
    final role = effectiveRole;
    return role != null && role.isSystemRole && role.name == 'مدير النظام';
  }
}

class AuthNotifier extends Notifier<AuthState> {
  VoidCallback? _connectionListener;

  /// Feature 004 (US3, branch-scoped elevation) — reflects whether the
  /// currently-logged-in user has an UNRESTRICTED branch scope (i.e. their
  /// `user_branch_access` table is empty, the project's convention for
  /// "all branches"). A System Admin who is bound to a specific branch
  /// (one or more rows in user_branch_access) does NOT get cross-branch
  /// elevation — they manage their own branch only. Loaded asynchronously
  /// on login because [getUserAccessibleBranchIds] hits the database.
  bool _actorIsUnrestricted = false;

  @override
  AuthState build() {
    // Feature 004 (US3) — subscribe to the WebSocket connection-live signal
    // so we can flip `isCrossBranchElevated` back on when the server returns
    // and off when it drops, without forcing the user to re-login.
    final notifier = WebSocketSyncClient.instance.connected;
    _connectionListener = _recomputeElevation;
    notifier.addListener(_connectionListener!);
    ref.onDispose(() {
      if (_connectionListener != null) {
        notifier.removeListener(_connectionListener!);
        _connectionListener = null;
      }
    });
    return const AuthState();
  }

  /// Feature 004 (US3) — recompute `isCrossBranchElevated` as the persistent
  /// eligibility flag. The four conditions are:
  ///   1. role.isSystemRole && role.name == 'مدير النظام'
  ///   2. NetworkService.isClient (paired client device)
  ///   3. state.isAuthenticated
  ///   4. _actorIsUnrestricted (user_branch_access is empty == "all branches")
  ///
  /// **Why condition 4**: a System Admin bound to a specific branch should
  /// manage that branch only, not the whole company. Only the HQ-style admin
  /// (no branch restriction in user_branch_access) "mirrors the server" and
  /// sees every branch on a paired client.
  ///
  /// Connection liveness is **not** part of this flag — losing the WebSocket
  /// must not flip the eligibility off, otherwise [mutationGuardProvider]
  /// would never have both `isCrossBranchElevated == true` AND `live == false`
  /// at the same time and could not produce a read-only state. The guard
  /// reads `live` separately. Re-runs on every login/logout/role-change AND
  /// on WebSocket connection changes (via the listener wired in [build]) so
  /// the static snapshot stays in step with the auth state for the DAO
  /// activity-log prefix.
  void _recomputeElevation() {
    final role = state.userWithRole?.role;
    final isAdmin = role != null &&
        role.isSystemRole &&
        role.name == 'مدير النظام';
    final isPairedClient = NetworkService.instance.isClient;
    final next = state.isAuthenticated &&
        isAdmin &&
        isPairedClient &&
        _actorIsUnrestricted;
    ElevationSnapshot.isCrossBranchElevated = next;
    if (next == state.isCrossBranchElevated) return;
    state = state.copyWith(isCrossBranchElevated: next);
  }

  /// Async helper — refreshes [_actorIsUnrestricted] from the DB and then
  /// runs the elevation recomputation. Called on login. Until the DB read
  /// completes, the user is treated as branch-restricted (safe default).
  Future<void> _refreshActorBranchScope() async {
    final user = state.userWithRole?.user;
    if (user == null) {
      _actorIsUnrestricted = false;
    } else {
      try {
        final db = ref.read(databaseProvider);
        final ids = await db.getUserAccessibleBranchIds(user.id);
        // Project convention: empty access list == full access (all branches).
        _actorIsUnrestricted = ids.isEmpty;
      } catch (_) {
        // Defensive default — restrict on any DB error rather than over-grant.
        _actorIsUnrestricted = false;
      }
    }
    _recomputeElevation();
  }

  void login(UserWithRole userWithRole) {
    final now = DateTime.now();
    state = AuthState(
      userWithRole: userWithRole,
      isAuthenticated: true,
      loginTime: now,
      lastActivity: now,
    );
    // Phase 5A.3 (Issue 5) — publish the role name so the sync layer
    // (server_proxy.fetchDelta) can decide whether the next /api/sync/pull
    // should carry a `branch_id` filter. Admins skip the filter and keep
    // cross-branch visibility on a paired client device.
    SyncInterceptor.currentUserRole = userWithRole.role?.name;
    // المرحلة ١ / G2 — العلَم هو ما يقرأه حصر المزامنة فعلاً. نُنشر
    // [hasSystemAdminBypass] بعينه — الاقتران `isSystemRole && name == 'مدير
    // النظام'` — لا العمود `isSystemRole` وحده: العمود `true` كذلك لكاشير
    // ومخزني ومحاسب ومدير مالي، فنشره وحده كان هيدّي الكاشير سحباً غير
    // مقيّد. مصدر واحد للقرار مع permissions_dao._isAdminRole.
    SyncInterceptor.currentUserIsSystemAdmin = state.hasSystemAdminBypass;
    // Spec 060 Phase 2 — publish userId so ServerProxy can attach it as
    // X-User-Id on every outbound API call. Drives server-side per-user
    // permission enforcement when the `server_per_user_perms_enabled`
    // flag is on (no-op otherwise).
    SyncInterceptor.currentUserId = userWithRole.user.id;
    _recomputeElevation();
    // Branch scope load is async — kicks off here and rewrites the elevation
    // flag once the DB returns. Reset to false in the meantime (safe default).
    _actorIsUnrestricted = false;
    unawaited(_refreshActorBranchScope());
  }

  /// Hand the session from the current user to [incoming] in one step.
  ///
  /// ── ليه دالة واحدة مش `logout()` بعدها `login()` ─────────────────────────
  /// ده مش تفضيل شكلي — `logout()` بتصفّر `state` لـ `AuthState()` الفاضية،
  /// و`main.dart` بيحط **مفتاح على `MaterialApp` نفسه** مبني على حالة المصادقة:
  ///
  /// ```dart
  /// final isAuthenticated = ref.watch(authProvider).isAuthenticated;
  /// return MaterialApp(key: ValueKey('app_auth_$isAuthenticated'), …);
  /// ```
  ///
  /// فلحظة واحدة بـ `isAuthenticated == false` معناها **مفتاح جديد** → فلاتر
  /// بتهدم شجرة الودجت كلها وتبنيها من الأول على شاشة الدخول، وكل ديالوج مفتوح
  /// بيموت معاها — بما فيه ديالوج التحويل اللي بنكون واقفين فيه. أي إن
  /// `logout()` ثم `login()` كان هيعمل بالظبط العرض اللي التحويل موجود عشان
  /// يمنعه، حتى لو النداءين ورا بعض بسطر واحد.
  ///
  /// فالتنظيف هنا بيحصل **بلا لحظة الفراغ دي**: نفس تنظيف [logout] بالحرف،
  /// وبعده [login] فوراً — والحالة بتنتقل من مستخدم لمستخدم مباشرة.
  ///
  /// ── وليه مش نداءات مفكوكة في ديالوج التحويل ──────────────────────────────
  /// كان التحويل بينادي `login()` وبس، فالتنظيف اللي في `logout()` كان بيتفوّت:
  /// توكنات السيرفر المخزّنة، وحدّ محاولات الدخول، وعلامات «اتسأل يفتح وردية».
  /// حطّها هنا معناه إن أي مسار تحويل جاي بياخدها غصب عنه.
  void switchUser(UserWithRole incoming) {
    // ── تنظيف جلسة الخارج ──
    LoginRateLimiter.reset();
    // توكنات وإثباتات السيرفر مفهرسة بـ userId فالجاي مايقدرش يركب على توكن
    // الخارج أصلاً — بننضّفها عشان ما تفضلش في الذاكرة بلا داعي، ونفس نية
    // Spec 151 P1-8: «الجاي يبدأ بلا هوية موروثة».
    ServerProxy.instance.clearSessions();
    // Feature 012 / Issue C-SHIFT-LOOP — من غيرها تحويل A→B→A بيسيب A متعلّم
    // إنه اتسأل يفتح وردية، فما يتسألش تاني.
    clearShiftDialogPromptedUsers();

    // ── دخول الجاي ──
    // `login` بتبني `AuthState` جديدة (فالترقية المؤقتة بتسقط)، وبتعيد نشر
    // هوية التزامن، وبتصفّر نطاق الفروع وتعيد تحميله.
    login(incoming);
  }

  void elevate(UserWithRole adminUser) {
    if (!state.isAuthenticated) return;
    state = state.copyWith(
      elevatedByFn: () => adminUser,
      elevationTimeFn: () => DateTime.now(),
      lastActivity: DateTime.now(),
    );
    // Elevation grants admin powers temporarily — mirror it into the sync
    // layer so cross-branch reads are unblocked while elevated.
    SyncInterceptor.currentUserRole = adminUser.role?.name;
    // المرحلة ١ / G2 — الترقية تعمل بهوية الأدمن، فلازم العلَم ينتقل معها؛
    // لو فضل على قيمة المستخدم الأصلي كان الأدمن المُرقّي هيفضل محصوراً.
    // `hasSystemAdminBypass` تقرأ `effectiveRole` فتلقط دور المُرقِّي تلقائياً.
    SyncInterceptor.currentUserIsSystemAdmin = state.hasSystemAdminBypass;
    // Spec 060 Phase 2 — mirror the admin's userId so any server call made
    // while elevated is gated against the admin's permissions, not the
    // underlying user's (matches what role-elevation already does for
    // branch scope and for local permission checks).
    SyncInterceptor.currentUserId = adminUser.user.id;
  }

  void dropElevation() {
    if (!state.isElevated) return;
    state = state.copyWith(
      elevatedByFn: () => null,
      elevationTimeFn: () => null,
      lastActivity: DateTime.now(),
    );
    // Restore the underlying user's role so post-elevation pulls re-apply
    // the branch filter.
    SyncInterceptor.currentUserRole = state.userWithRole?.role?.name;
    // المرحلة ١ / G2 — إسقاط الترقية لازم يسحب العلَم كمان، وإلا فضل إعفاء
    // الأدمن ساري على المستخدم الأصلي بعد انتهاء الترقية. الحالة اتحدّثت
    // فوق (elevatedBy = null) فـ`effectiveRole` بقى دور المستخدم الأصلي.
    SyncInterceptor.currentUserIsSystemAdmin = state.hasSystemAdminBypass;
    // Spec 060 Phase 2 — restore the underlying user's id symmetrically.
    SyncInterceptor.currentUserId = state.userWithRole?.user.id;
  }

  void updateActivity() {
    if (state.isAuthenticated) {
      state = state.copyWith(lastActivity: DateTime.now());
    }
  }

  bool checkSession() {
    if (!state.isAuthenticated) return false;
    if (state.isSessionExpired) {
      logout();
      return false;
    }
    updateActivity();
    return true;
  }

  void logout() {
    LoginRateLimiter.reset(); // Clear rate limiter to allow re-login
    _actorIsUnrestricted = false;
    state = const AuthState();
    SyncInterceptor.currentUserRole = null;
    // المرحلة ١ / G2 — المسح إلزامي: علَم جلسة سابقة باقٍ بعد الخروج معناه
    // مستخدم تالٍ يرث إعفاء مدير النظام من حصر الفروع.
    SyncInterceptor.currentUserIsSystemAdmin = null;
    SyncInterceptor.currentUserId = null;
    // Spec 151 (P1-8) — drop all cached session tokens + in-memory credential
    // proofs so the next user that signs in starts with no inherited identity.
    ServerProxy.instance.clearSessions();
    _recomputeElevation();
    // Feature 012 / Issue C-SHIFT-LOOP — clear the same-session
    // already-prompted set so the next user that signs in starts with a
    // clean slate. Otherwise a cashier swap on the same physical device
    // would inherit the previous cashier's "already prompted" mark.
    clearShiftDialogPromptedUsers();
  }

  /// Feature 004 (US3) — public hook for tests and for non-WS code paths
  /// (e.g. NetworkService mode change) to force a recomputation of the
  /// elevation flag without inventing a fake user/login.
  @visibleForTesting
  void debugRecomputeElevation() => _recomputeElevation();

  /// Feature 004 (US3, branch-scoped elevation) — test-only override of the
  /// async `_actorIsUnrestricted` flag. Production code populates it from
  /// `getUserAccessibleBranchIds`; tests use this to simulate HQ-bound
  /// admins (true) vs. branch-bound admins (false) without seeding a DB.
  @visibleForTesting
  void debugSetActorUnrestricted(bool value) {
    _actorIsUnrestricted = value;
    _recomputeElevation();
  }
}

/// Feature 004 (US3) — Riverpod-friendly view of
/// `WebSocketSyncClient.instance.connected`. Re-emits whenever the underlying
/// `ValueNotifier<bool>` changes by invalidating itself, which produces
/// synchronous re-evaluation in dependent providers (so `mutationGuardProvider`
/// flips read-only/allow without an awaited microtask). Returns `true` when
/// the WebSocket has completed its server handshake.
final serverConnectionLiveProvider = Provider<bool>((ref) {
  final notifier = WebSocketSyncClient.instance.connected;
  void listener() => ref.invalidateSelf();
  notifier.addListener(listener);
  ref.onDispose(() => notifier.removeListener(listener));
  return notifier.value;
});

final authProvider = NotifierProvider<AuthNotifier, AuthState>(() {
  return AuthNotifier();
});

/// Current active branch ID provider (cached/reactive)
final activeBranchIdProvider = FutureProvider<int?>((ref) async {
  final authState = ref.watch(authProvider);
  final userId = authState.user?.id;
  if (userId == null) return null;

  if (NetworkService.instance.isClient) {
    final prefs = await SharedPreferences.getInstance();
    final clientBranchId = prefs.getInt('client_branch_id');
    if (clientBranchId != null) return clientBranchId;
  }

  final db = ref.read(databaseProvider);
  return db.getUserBranchId(userId);
});

/// Current user permissions provider.
///
/// IMPORTANT: reads the **originally logged-in** user, never `effectiveUser`.
/// Per-action admin approval (`_ManagerOverrideDialog`) must authorize a
/// single operation and then immediately fall back to the user's own
/// permissions — otherwise a sidebar-level elevation would silently bypass
/// every `PermissionGuard` in the tree. The sidebar walk-through flow
/// (`userAllowedScreensProvider` / `userNavItemsProvider`) keeps reading
/// `effectiveUser` so expanding the nav still works.
final currentUserPermissionsProvider = FutureProvider<List<String>>((
  ref,
) async {
  final authState = ref.watch(authProvider);
  final userId = authState.user?.id;
  if (userId == null) return [];

  final repo = ref.read(authRepositoryProvider);
  return repo.getUserPermissionCodes(userId);
});

/// Check if current user has specific permission.
///
/// Reads the original logged-in user (see [currentUserPermissionsProvider]
/// for the rationale — per-action elevation must not leak through here).
final hasPermissionProvider = FutureProvider.family<bool, String>((
  ref,
  permissionCode,
) async {
  final authState = ref.watch(authProvider);
  final user = authState.user;
  if (user == null) return false;

  final repo = ref.read(authRepositoryProvider);
  return repo.userHasPermission(user.id, permissionCode);
});

/// Current user role provider
final userRoleProvider = FutureProvider<Role?>((ref) async {
  final authState = ref.watch(authProvider);
  final user = authState.user;
  if (user == null || user.roleId == null) return null;

  final repo = ref.read(authRepositoryProvider);
  return repo.getRoleById(user.roleId!);
});

// ═══════════════════════════════════════════════════════════════════════════
// NAVIGATION PROVIDERS
// ═══════════════════════════════════════════════════════════════════════════

class NavItemDef {
  final IconData icon;
  final String label;
  final String? permission;
  final int index;
  final String? section; // Visual section header above this item
  final String? group;   // Group key for collapsible sidebar

  const NavItemDef({
    required this.icon,
    required this.label,
    this.permission,
    required this.index,
    this.section,
    this.group,
  });
}

/// كل عناصر القائمة الجانبية، بترتيبها ومرتبطة بأكواد الصلاحيات.
///
/// اتشالت من جوّه `userNavItemsProvider` لثابت مستوى الملف عشان اختبار
/// `screen_permission_map_test.dart` يقدر يتأكد إن عنصر القائمة الخاص
/// بكل شاشة متفق مع `screenPermissionMap[screenId]` — من غير ما يحتاج
/// يشغّل الـ provider بكل تبعياته (auth state, DB, إلخ).
const kAllNavItemDefs = [
  // ═══════════════════════════════════════════
  // 🏠 الرئيسية
  // ═══════════════════════════════════════════
  // كانت permission: null — أي حد يشوفها حتى لو الشاشة نفسها ممنوعة عنه.
  // قبل كده كان ده متّسق لأن لوحة التحكم كانت بتتحقن في allowedScreens
  // قسراً لكل الناس؛ دلوقتي screenPermissionMap بيربطها بـ dashboard_access
  // فعلاً، فلازم عنصر القائمة يتحكم بنفس الكود عشان مايفضلش رابط ميت لشاشة
  // ممنوعة (أو العكس).
  NavItemDef(icon: PhosphorIconsBold.house, label: 'الرئيسية', permission: PermissionCodes.dashboardAccess, index: 0, section: 'الرئيسية', group: 'home'),

  // ═══════════════════════════════════════════
  // 💰 المبيعات
  // ═══════════════════════════════════════════
  NavItemDef(icon: PhosphorIconsBold.shoppingCart, label: 'نقطة البيع', permission: 'pos_access', index: 1, section: 'المبيعات', group: 'sales'),
  NavItemDef(icon: PhosphorIconsBold.fileText, label: 'فواتير المبيعات', permission: 'sales_view', index: 17, group: 'sales'),
  NavItemDef(icon: PhosphorIconsBold.notepad, label: 'طلبات البيع', permission: 'sales_orders_view', index: 37, group: 'sales'),
  NavItemDef(icon: PhosphorIconsBold.circlesThree, label: 'الطاولات', permission: 'tables_view', index: 3, group: 'sales'),
  NavItemDef(icon: PhosphorIconsBold.tag, label: 'العروض', permission: 'offers_view', index: 2, group: 'sales'),
  NavItemDef(icon: PhosphorIconsBold.arrowUUpLeft, label: 'مردودات المبيعات', permission: 'sales_return_view', index: 44, group: 'sales'),

  // ═══════════════════════════════════════════
  // 🛒 المشتريات
  // ═══════════════════════════════════════════
  NavItemDef(icon: PhosphorIconsBold.receipt, label: 'فواتير المشتريات', permission: 'purchases_create', index: 9, section: 'المشتريات', group: 'purchases'),
  NavItemDef(icon: PhosphorIconsBold.clipboardText, label: 'أوامر الشراء', permission: 'purchase_orders_view', index: 30, group: 'purchases'),
  NavItemDef(icon: PhosphorIconsBold.arrowUUpLeft, label: 'مردودات المشتريات', permission: 'purchases_return_view', index: 45, group: 'purchases'),

  // ═══════════════════════════════════════════
  // 📦 المخزون والإنتاج
  // ═══════════════════════════════════════════
  NavItemDef(icon: PhosphorIconsBold.package, label: 'الأصناف', permission: 'products_add', index: 4, section: 'المخزون والإنتاج', group: 'inventory'),
  NavItemDef(icon: PhosphorIconsBold.squaresFour, label: 'التصنيفات', permission: 'products_add', index: 5, group: 'inventory'),
  NavItemDef(icon: PhosphorIconsBold.warehouse, label: 'المخزون', permission: 'inventory_view', index: 8, group: 'inventory'),
  NavItemDef(icon: PhosphorIconsBold.clipboardText, label: 'أرصدة المخزون', permission: 'inventory_view', index: 19, group: 'inventory'),
  NavItemDef(icon: PhosphorIconsBold.arrowsLeftRight, label: 'تحويل مخزني', permission: 'inventory_transfer', index: 20, group: 'inventory'),
  NavItemDef(icon: PhosphorIconsBold.arrowsDownUp, label: 'حركة المخزون', permission: 'inventory_view', index: 29, group: 'inventory'),
  NavItemDef(icon: PhosphorIconsBold.factory, label: 'التصنيع', permission: 'manufacturing_view', index: 25, group: 'inventory'),
  NavItemDef(icon: PhosphorIconsBold.truck, label: 'طلبات الصرف', permission: 'inventory_view', index: 38, group: 'inventory'),
  NavItemDef(icon: PhosphorIconsBold.money, label: 'التكاليف المحملة', permission: 'purchases_create', index: 41, group: 'inventory'),
  NavItemDef(icon: PhosphorIconsBold.listChecks, label: 'الجرد الدوري', permission: 'inventory_view', index: 42, group: 'inventory'),

  // ═══════════════════════════════════════════
  // 👥 العملاء والموردين
  // ═══════════════════════════════════════════
  NavItemDef(icon: PhosphorIconsBold.usersThree, label: 'العملاء والموردين', permission: 'customers_view', index: 6, section: 'العلاقات التجارية', group: 'relations'),
  NavItemDef(icon: PhosphorIconsBold.trophy, label: 'نقاط الولاء', permission: 'loyalty_view', index: 23, group: 'relations'),
  NavItemDef(icon: PhosphorIconsBold.truck, label: 'التوزيع', permission: 'distribution_view', index: 24, group: 'relations'),

  // ═══════════════════════════════════════════
  // 💵 المالية والمحاسبة
  // ═══════════════════════════════════════════
  NavItemDef(icon: PhosphorIconsBold.wallet, label: 'الخزينة', permission: 'treasury_view', index: 10, section: 'المالية والمحاسبة', group: 'accounting'),
  NavItemDef(icon: PhosphorIconsBold.lockKey, label: 'إغلاق الوردية', permission: PermissionCodes.posShiftClose, index: 56, group: 'accounting'),
  NavItemDef(icon: PhosphorIconsBold.treeStructure, label: 'دليل الحسابات', permission: 'settings_view', index: 27, group: 'accounting'),
  NavItemDef(icon: PhosphorIconsBold.notebook, label: 'دفتر اليومية', permission: 'settings_view', index: 32, group: 'accounting'),
  NavItemDef(icon: PhosphorIconsBold.book, label: 'دفتر الأستاذ', permission: 'settings_view', index: 36, group: 'accounting'),
  NavItemDef(icon: PhosphorIconsBold.link, label: 'ربط الحسابات', permission: 'settings_view', index: 31, group: 'accounting'),
  NavItemDef(icon: PhosphorIconsBold.treeStructure, label: 'مراكز التكلفة', permission: 'settings_view', index: 33, group: 'accounting'),
  NavItemDef(icon: PhosphorIconsBold.checks, label: 'الشيكات', permission: 'treasury_view', index: 34, group: 'accounting'),
  NavItemDef(icon: PhosphorIconsBold.buildings, label: 'الأصول الثابتة', permission: 'assets_view', index: 35, group: 'accounting'),
  NavItemDef(icon: PhosphorIconsBold.invoice, label: 'الفوترة الإلكترونية', permission: 'einvoice_view', index: 22, group: 'accounting'),
  NavItemDef(icon: PhosphorIconsBold.calendar, label: 'السنوات المالية', permission: 'settings_view', index: 28, group: 'accounting'),
  NavItemDef(icon: PhosphorIconsBold.coins, label: 'المصروفات التشغيلية', permission: 'settings_view', index: 26, group: 'accounting'),

  // ═══════════════════════════════════════════
  // 📊 التقارير والتحليلات
  // ═══════════════════════════════════════════
  NavItemDef(icon: PhosphorIconsBold.chartBar, label: 'التقارير', permission: 'reports_view', index: 11, section: 'التقارير', group: 'reports'),
  // Task 3d — كان على 'reports_view' وده كود عام؛ screenPermissionMap
  // بيربط الشاشة بـ analytics_view من زمان. اللي عنده reports_view بس
  // كان بيشوف الرابط وميقدرش يفتح الشاشة (رابط ميت). اتصلّح ليتفق مع
  // الخريطة — راجع منح analytics_view في RoleGrantMatrix.defaultGrants
  // والسيدر عشان محاسب/مدير مالي/مدير فرع/مدير مخزون ما يفقدوش الرابط.
  NavItemDef(icon: PhosphorIconsBold.chartPie, label: 'التحليلات', permission: PermissionCodes.analyticsView, index: 15, group: 'reports'),
  NavItemDef(icon: PhosphorIconsBold.chartBar, label: 'أداء الفروع', permission: 'reports_view', index: 39, group: 'reports'),
  NavItemDef(icon: PhosphorIconsBold.clipboardText, label: 'سجل العمليات', permission: 'audit_view', index: 18, group: 'reports'),
  NavItemDef(icon: PhosphorIconsBold.chartBar, label: 'تقارير مخصصة', permission: 'reports_view', index: 43, group: 'reports'),

  // ═══════════════════════════════════════════
  // ⚙️ النظام والإعدادات
  // ═══════════════════════════════════════════
  NavItemDef(icon: PhosphorIconsBold.cookingPot, label: 'المطبخ', permission: 'kitchen_view', index: 14, section: 'النظام', group: 'system'),
  // Task 3d — اختبار الاتفاق المعمّم كشف نفس عائلة عطل «التحليلات» هنا:
  // كان على 'settings_view' بينما screenPermissionMap يربط الشاشة بـ
  // branches_manage. راجع منح branches_manage لمحاسب متقدم تحت (كان
  // بيشوف الرابط عبر settings_view بس ماعندوش الكود الفعلي).
  NavItemDef(icon: PhosphorIconsBold.buildings, label: 'الفروع', permission: PermissionCodes.branchesManage, index: 13, group: 'system'),
  NavItemDef(icon: PhosphorIconsBold.mapPin, label: 'المناطق', permission: 'settings_view', index: 60, group: 'system'),
  NavItemDef(icon: PhosphorIconsBold.users, label: 'الموظفين', permission: 'hr_view', index: 16, group: 'system'),
  NavItemDef(icon: PhosphorIconsBold.scales, label: 'ميزان التسعير', permission: 'settings_scale', index: 21, group: 'system'),
  NavItemDef(icon: PhosphorIconsBold.gear, label: 'الإعدادات', permission: 'settings_view', index: 12, group: 'system'),
  NavItemDef(icon: PhosphorIconsBold.question, label: 'مركز المساعدة', permission: 'pos_access', index: 40, group: 'system'),
];

final userNavItemsProvider = FutureProvider<List<NavItemDef>>((ref) async {
  const allNavItems = kAllNavItemDefs;

  final authState = ref.watch(authProvider);
  // Use effectiveUser so explicit "Manager Mode" elevation expands the
  // sidebar (per-action elevation prompts re-check per click separately).
  final user = authState.effectiveUser;
  if (user == null) return [];

  debugPrint('[NAV] effectiveUser: id=${user.id} name=${user.displayName} roleId=${user.roleId}');

  // Phase C2: watch the runtime profile so this provider invalidates
  // and the navigation rebuilds whenever the developer changes the
  // business profile via developer-tools (or via SQL during dev).
  ref.watch(businessProfileProvider);

  final repo = ref.read(authRepositoryProvider);
  final activePlatform = ref.watch(activeEInvoicePlatformProvider).value;
  final allowedItems = <NavItemDef>[];
  final allowedScreenIds = AppConfig.allowedScreenIds.toSet();

  // SECURITY: Use the role recorded in the auth state at login, NOT the user's
  // current DB roleId. DeltaPullService and UserSyncStrategy can update the
  // users table mid-session (e.g. if the server's user id=3 has a different
  // role), which caused getUserPermissionCodes(user.id) to pick up the new
  // (potentially admin-level) roleId and silently escalate permissions.
  // Using the session-fixed role prevents this escalation without requiring
  // a re-login for normal permission updates to the role_permissions table.
  final sessionRoleId = authState.effectiveRole?.id;
  Set<String> userPermissions;
  if (sessionRoleId != null) {
    final perms = await repo.getPermissionsForRole(sessionRoleId);
    userPermissions = perms.map((p) => p.code).toSet();
  } else {
    userPermissions = const {};
  }

  debugPrint('[NAV] allowedScreenIds from AppConfig: $allowedScreenIds');

  for (final item in allNavItems) {
    final screenId = ScreenId.fromIndex(item.index);
    if (screenId == null || !allowedScreenIds.contains(screenId)) continue;
    if (item.index == ScreenId.dashboard.navigationIndex && authState.isCashier && !authState.isAdmin) continue;

    // Special handling for E-Invoicing
    if (item.index == ScreenId.eInvoice.navigationIndex) {
      if (activePlatform == null) {
        if (!authState.isAdmin) continue;
      }

      String label = item.label;
      if (activePlatform == 'eta') label = 'الفوترة الإلكترونية (مصر)';
      if (activePlatform == 'jofotara') label = 'الفوترة الإلكترونية (الأردن)';

      if (item.permission == null || userPermissions.contains(item.permission)) {
        allowedItems.add(NavItemDef(
          icon: item.icon,
          label: label,
          permission: item.permission,
          index: item.index,
          section: item.section,
          group: item.group,
        ));
      }
      continue;
    }

    if (item.permission == null ||
        authState.hasSystemAdminBypass ||
        userPermissions.contains(item.permission)) {
      allowedItems.add(item);
    }
  }
  debugPrint('[NAV] ✅ total allowed nav items: ${allowedItems.length} / ${allNavItems.length}');
  return allowedItems;
});

/// ربط الشاشة ← كود الصلاحية اللي بيتحكم في ظهورها.
///
/// ── القاعدة ──────────────────────────────────────────────────────────────
/// الشاشة اللي ليها كود خاص في `PermissionCodes` تتربط بيه، مش بكود عام.
/// كانت العروض والطاولات والمطبخ ولوحة التحكم كلهم على `pos_access`،
/// ومردودات البيع على `sales_view` — فسحب `offers_view` ما كانش بيخفي شاشة
/// العروض، لأن الكود ده ما كانش متوصّل بحاجة أصلاً.
///
/// الشاشات المحاسبية اللي لسه على `settings_view` مقصودة: مالهاش أكواد
/// خاصة في `masterList` لحد دلوقتي.
const screenPermissionMap = <ScreenId, String>{
  ScreenId.dashboard: 'dashboard_access',
  ScreenId.pos: 'pos_access',
  ScreenId.offers: 'offers_view',
  ScreenId.tables: 'tables_view',
  ScreenId.products: 'products_add',
  ScreenId.categories: 'products_add',
  ScreenId.parties: 'customers_view',
  ScreenId.inventory: 'inventory_view',
  ScreenId.purchases: 'purchases_create',
  ScreenId.treasury: 'treasury_view',
  ScreenId.reports: 'reports_view',
  ScreenId.settings: 'settings_view',
  ScreenId.branches: 'branches_manage',
  ScreenId.kitchen: 'kitchen_view',
  ScreenId.analytics: 'analytics_view',
  ScreenId.hr: 'hr_view',
  ScreenId.salesInvoices: 'sales_view',
  ScreenId.activityLog: 'audit_view',
  ScreenId.inventoryBonds: 'inventory_view',
  ScreenId.stockTransfer: 'inventory_transfer',
  ScreenId.scalePlu: 'settings_scale',
  ScreenId.eInvoice: 'einvoice_view',
  ScreenId.loyalty: 'loyalty_view',
  ScreenId.distribution: 'distribution_view',
  ScreenId.manufacturing: 'manufacturing_view',
  ScreenId.operationalExpenses: 'settings_view',
  ScreenId.chartOfAccounts: 'settings_view',
  ScreenId.fiscalYear: 'settings_view',
  ScreenId.stockMovements: 'inventory_view',
  ScreenId.purchaseOrders: 'purchase_orders_view',
  ScreenId.accountMapping: 'settings_view',
  ScreenId.journalEntries: 'settings_view',
  ScreenId.costCenters: 'settings_view',
  ScreenId.commercialPapers: 'treasury_view',
  ScreenId.fixedAssets: 'assets_view',
  ScreenId.generalLedger: 'settings_view',
  ScreenId.salesOrders: 'sales_orders_view',
  ScreenId.stockRequisitions: 'inventory_view',
  ScreenId.branchPerformance: 'reports_view',
  ScreenId.helpCenter: 'pos_access',
  ScreenId.landedCost: 'purchases_create',
  ScreenId.cycleCounting: 'inventory_view',
  ScreenId.reportBuilder: 'reports_view',
  ScreenId.salesReturns: 'sales_return_view',
  ScreenId.purchaseReturns: 'purchases_return_view',
  ScreenId.regions: 'settings_view',
  ScreenId.shiftClose: PermissionCodes.posShiftClose,
};

final userAllowedScreensProvider = FutureProvider<List<int>>((ref) async {
  final authState = ref.watch(authProvider);
  // Use effectiveUser so the explicit "وضع المدير" (Manager Mode) toggle
  // expands the cashier's nav to admin's full layout while it's active.
  // (My earlier P5 attempt to use `user` here broke that feature — what I
  // mistook for a "permission leak" was the user deliberately activating
  // Manager Mode. Action-scoped elevation prompts continue to be enforced
  // per-click via `_userHasPermissionFresh` in pos_main_operations.dart.)
  final user = authState.effectiveUser;
  if (user == null) return [];

  // Phase C2: watch the runtime profile so the screen list rebuilds when
  // the developer changes the business profile at runtime — without
  // requiring a logout / restart.
  ref.watch(businessProfileProvider);

  final repo = ref.read(authRepositoryProvider);
  final activePlatform = ref.watch(activeEInvoicePlatformProvider).value;
  final flavorAllowedScreenIds = AppConfig.allowedScreenIds.toSet();
  final allowedScreens = <int>[];

  // SECURITY: Use the role recorded in the auth state at login, NOT the user's
  // current DB roleId — same rationale as in userNavItemsProvider above.
  // DeltaPullService raw-INSERT and UserSyncStrategy can overwrite the user's
  // roleId mid-session, causing getUserPermissionCodes() to return the new
  // (possibly admin-level) role's permissions and grant access to all screens.
  final sessionRoleId = authState.effectiveRole?.id;
  Set<String> userPermissions;
  if (sessionRoleId != null) {
    final perms = await repo.getPermissionsForRole(sessionRoleId);
    userPermissions = perms.map((p) => p.code).toSet();
  } else {
    userPermissions = const {};
  }

  for (final entry in screenPermissionMap.entries) {
    if (!flavorAllowedScreenIds.contains(entry.key)) continue;

    // Check e-invoice specifically
    if (entry.key == ScreenId.eInvoice) {
      if (activePlatform == null && !authState.isAdmin) continue;
    }

    // System-admin bypass: grant access to all screens. حصريًا لصلاحية
    // النظام الحقيقية (hasSystemAdminBypass) مش لأي دور اسمه فيه «مدير».
    if (authState.hasSystemAdminBypass ||
        userPermissions.contains(entry.value)) {
      allowedScreens.add(entry.key.navigationIndex);
    }
  }

  // مايبقاش المستخدم من غير أي شاشة يفتحها — بيقع في واجهة فاضية بلا مخرج.
  // قبل كده كانت لوحة التحكم بتتحقن قسراً وده كان بيلغي `dashboard_access`
  // تماماً؛ دلوقتي بتتحقن فقط لما مايبقاش فيه بديل خالص.
  if (allowedScreens.isEmpty &&
      flavorAllowedScreenIds.contains(ScreenId.dashboard)) {
    allowedScreens.add(ScreenId.dashboard.navigationIndex);
  }

  return allowedScreens..sort();
});

// ═══════════════════════════════════════════════════════════════════════════
// N3/N4: USER-ACCESSIBLE BRANCHES & WAREHOUSES
// ═══════════════════════════════════════════════════════════════════════════

/// Map of userId -> list of branch names for display in user management.
/// Loads all branch assignments in bulk for efficiency.
final allUserBranchNamesProvider = FutureProvider<Map<int, List<String>>>((ref) async {
  final db = ref.read(databaseProvider);
  final allBranches = await db.getBranches();
  final branchMap = {for (final b in allBranches) b.id: b.name};

  final users = ref.watch(allUsersProvider).value ?? [];
  final result = <int, List<String>>{};
  for (final uw in users) {
    final branchIds = await db.getUserAccessibleBranchIds(uw.user.id);
    if (branchIds.isEmpty) {
      // Empty means full access — show 'all branches' indicator
      result[uw.user.id] = [];
    } else {
      result[uw.user.id] = branchIds
          .map((id) => branchMap[id])
          .whereType<String>()
          .toList();
    }
  }
  return result;
});

/// Returns only the branches the current user can access.
/// Empty access list from DAO = full access → returns all branches.
final userAccessibleBranchesProvider = FutureProvider<List<Branche>>((ref) async {
  final authState = ref.watch(authProvider);
  final userId = authState.user?.id;
  if (userId == null) return [];

  final db = ref.read(databaseProvider);
  final allBranches = await db.getBranches();
  final accessIds = await db.getUserAccessibleBranchIds(userId);

  // Empty = full access
  if (accessIds.isEmpty) return allBranches;
  return allBranches.where((b) => accessIds.contains(b.id)).toList();
});

/// Returns only the warehouses the current user can access.
///
/// نفس عقد [allWarehousesProvider] بالظبط — شوف التعليق هناك لتفصيل قرار
/// «مقفول على العميل/المرآة فقط». المنطق متكرّر هنا لأن المصدر مختلف
/// (تجميع من كل الفروع بدل stream)، لكن **القرار واحد** ومينفعش يختلفوا.
final userAccessibleWarehousesProvider = FutureProvider<List<Warehouse>>((ref) async {
  final authState = ref.watch(authProvider);
  final userId = authState.user?.id;
  if (userId == null) return [];

  final db = ref.read(databaseProvider);
  final allBranches = await db.getBranches();
  final scope = await db.getWarehouseScopeForUser(userId);

  // Collect all warehouses from all branches
  final allWarehouses = <Warehouse>[];
  for (final branch in allBranches) {
    allWarehouses.addAll(await db.getWarehousesByBranch(branch.id));
  }

  if (scope == null) return allWarehouses; // مميّز ⇒ بلا حصر
  if (scope.isEmpty) {
    // هويّةُ الجهاز لا توجيهُ الكتابة — انظر `NetworkService.isBranchScopedDevice`
    // ونظيرَه في `allWarehousesProvider` (القرارُ واحدٌ ومينفعش يختلفوا).
    if (NetworkService.instance.isBranchScopedDevice) {
      debugPrint('[WarehouseScope] ⚠ user=$userId غير مميّز وبلا تخصيص مخازن '
          'على جهاز عميل/مرآة ⇒ صفر مخازن (فشل مقفول)');
      return const <Warehouse>[];
    }
    return allWarehouses;
  }
  return allWarehouses.where((w) => scope.contains(w.id)).toList();
});

/// Bank safes available for the current user's branch.
/// If no branch is linked, returns ALL active bank safes (single-branch fallback).
final branchBankSafesProvider = FutureProvider<List<Safe>>((ref) async {
  final authState = ref.watch(authProvider);
  final userId = authState.effectiveUser?.id;
  final db = ref.read(databaseProvider);

  int? branchId;
  if (userId != null) {
    branchId = await db.getUserBranchId(userId);
  }
  return db.getBankSafesForBranch(branchId);
});

/// Cash safes available for the current user's branch.
/// If no branch is linked, returns ALL active cash safes (single-branch fallback).
final branchCashSafesProvider = FutureProvider<List<Safe>>((ref) async {
  final authState = ref.watch(authProvider);
  final userId = authState.effectiveUser?.id;
  final db = ref.read(databaseProvider);

  int? branchId;
  if (userId != null) {
    branchId = await db.getUserBranchId(userId);
  }
  return db.getCashSafesForBranch(branchId);
});
