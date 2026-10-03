import 'dart:async' show unawaited;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/config/app_config.dart';
import '../../core/config/brand.dart';
import '../../core/config/business_profile_provider.dart';
import '../../core/navigation/screen_id.dart';
import '../../core/permissions/permission_codes.dart';
import '../../domain/models/nav_search.dart';
import '../../services/login_rate_limiter.dart';
import '../../services/network_service.dart';
import '../../services/manager_approval_cache.dart';
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
    // الفاعلُ يُنشَر مع كلّ تغيُّرِ حالةِ دخول — تنسب إليه الخدماتُ التي لا
    // تملك `ref` سطورَ سجلّها (طباعةُ الفواتير والتقارير). ومكانُه هنا لأنّ
    // هذه الدالّةَ تُنادى من كلّ مسارٍ يغيّر الحالة: الدخولُ والخروجُ
    // وتبديلُ المستخدم وتغيُّرُ الاتّصال.
    final actor = state.isAuthenticated ? state.userWithRole?.user : null;
    ActorSnapshot.set(actor?.id, actor?.displayName);

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
    // 🔴 موافقةُ المدير **لا تعبر تبديلَ المستخدم.** `ManagerApprovalCache`
    // تحمل أذوناً حيّةً لستّين ثانية، و`clear()` فيها كانت **بلا مستدعٍ
    // إطلاقاً** — فمديرٌ يصادق ثمّ يسلّم الجهازَ لكاشيرٍ خلال الدقيقة يترك
    // له إذناً جاهزاً يُصرَف على أوّل فعلٍ بنفس الكود. وهذا عينُ ما يمنعه
    // تنظيفُ الجلسة أعلاه للتوكنات.
    ManagerApprovalCache.instance.clear();
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
    // 🔴 نفسُ سببِ تنظيف التوكنات: إذنُ مديرٍ حيٌّ يعبر الخروجَ يصير إذناً
    // للمستخدم التالي. و`ManagerApprovalCache.clear()` كانت بلا مستدعٍ.
    ManagerApprovalCache.instance.clear();
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

/// رأسُ مجموعةٍ في القائمة الجانبيّة — مفتاحُها وتسميتُها وأيقونتُها.
///
/// ⚠️ **مكانُه هنا لا في `nav_widgets.dart`.** كان خريطةً خاصّةً
/// (`_groupMeta`) داخل طبقة العرض، وبانيها يسقط على بديلٍ صامت:
/// `_groupMeta[key] ?? _GroupMeta(groupKey, folder)`. فمدخلٌ يُنقَل إلى
/// مجموعةٍ بمفتاحٍ غيرِ معرَّفٍ يظهر تحت رأسٍ **بالمفتاح الإنجليزيّ الخام**
/// بلا خطأٍ ولا تحذير — وهو عطبٌ لا يُرى إلّا بفتح الشاشة. ورفعُه إلى ثابتٍ
/// عامٍّ يجعل الاتّفاقَ مقيساً في `sidebar_owner_layout_test.dart`.
class NavGroupDef {
  final String key;
  final String label;
  final IconData icon;

  const NavGroupDef(this.key, this.label, this.icon);
}

/// رؤوسُ المجموعات بترتيبها المنطقيّ.
///
/// ⚠️ والترتيبُ المعروضُ **لا يُقرأ من هنا**: الشريطُ يبني ترتيبَه من أوّلِ
/// ظهورٍ لكلّ مفتاحٍ في [kAllNavItemDefs]. فهذه القائمةُ تسميةٌ وأيقونة،
/// وموضعُ الرأس يُضبَط بموضع مداخله هناك.
///
/// ⚠️ **E-fix ٣ — الفصلُ لـPicPos وحدَه (قرارُ المالك).** UralCash يعود إلى
/// رؤوسه قبل المرحلة هـ حرفاً بحرف: [_kNavGroupDefsUralCash].
const kNavGroupDefs =
    Brand.isPicPos ? _kNavGroupDefsPicPos : _kNavGroupDefsUralCash;

const _kNavGroupDefsPicPos = <NavGroupDef>[
  NavGroupDef('home', 'Dashboard', PhosphorIconsBold.house),
  NavGroupDef('sales', 'المبيعات', PhosphorIconsBold.shoppingCart),
  // طلبُ المالك 2026-09-12: رأسٌ مستقلٌّ تحت المبيعات يجمع الطاولاتِ والمطبخ.
  NavGroupDef('restaurant', 'ادارة المطاعم', PhosphorIconsBold.forkKnife),
  NavGroupDef('purchases', 'المشتريات', PhosphorIconsBold.receipt),
  NavGroupDef('inventory', 'الاصناف والمخزون', PhosphorIconsBold.package),
  NavGroupDef('manufacturing', 'ادارة التصنيع', PhosphorIconsBold.factory),
  NavGroupDef('relations', 'العملاء والموردين', PhosphorIconsBold.usersThree),
  NavGroupDef('hr', 'الموارد البشرية', PhosphorIconsBold.identificationBadge),
  // المرحلة هـ / E1 (قرارُ المالك): «المالية والمحاسبة» انقسمت رأسَين —
  // «الإدارة المالية» (السندات والشيكات والخزينة والوردية) و«إدارة الحسابات»
  // (كلُّ شاشات المحاسبة الباقية، ومنها ما كان تحت «اليومية العامة»).
  NavGroupDef('accounting', 'الإدارة المالية', PhosphorIconsBold.wallet),
  // رأسان بأمر المالك 2026-09-20 — تبويباتُ حاوية «الحسابات»
  // صارت شاشاتٍ، والحاويةُ رأساً. والرأسُ هنا يطوي ويبسط
  // ولا ينتقل — `nav_widgets.dart` يربط `onTap` بالطيّ لا بالملاحة.
  // E1 — رأسُ «اليومية العامة» (`journal`) دُمج في «إدارة الحسابات».
  NavGroupDef('accounts', 'إدارة الحسابات', PhosphorIconsBold.bookOpen),
  NavGroupDef('reports', 'التقارير', PhosphorIconsBold.chartBar),
  NavGroupDef('system', 'اعداد النظام', PhosphorIconsBold.gear),
];

/// رؤوسُ UralCash كما كانت قبل `2aa66285` (المرحلة هـ): «المالية والمحاسبة»
/// و«الحسابات» و«اليومية العامة» — والمداخلُ في [_uralCashFinanceNavLayout].
const _kNavGroupDefsUralCash = <NavGroupDef>[
  NavGroupDef('home', 'Dashboard', PhosphorIconsBold.house),
  NavGroupDef('sales', 'المبيعات', PhosphorIconsBold.shoppingCart),
  NavGroupDef('restaurant', 'ادارة المطاعم', PhosphorIconsBold.forkKnife),
  NavGroupDef('purchases', 'المشتريات', PhosphorIconsBold.receipt),
  NavGroupDef('inventory', 'الاصناف والمخزون', PhosphorIconsBold.package),
  NavGroupDef('manufacturing', 'ادارة التصنيع', PhosphorIconsBold.factory),
  NavGroupDef('relations', 'العملاء والموردين', PhosphorIconsBold.usersThree),
  NavGroupDef('hr', 'الموارد البشرية', PhosphorIconsBold.identificationBadge),
  NavGroupDef('accounting', 'المالية والمحاسبة', PhosphorIconsBold.wallet),
  NavGroupDef('accounts', 'الحسابات', PhosphorIconsBold.bookOpen),
  NavGroupDef('journal', 'اليومية العامة', PhosphorIconsBold.notebook),
  NavGroupDef('reports', 'التقارير', PhosphorIconsBold.chartBar),
  NavGroupDef('system', 'اعداد النظام', PhosphorIconsBold.gear),
];

/// مداخلُ المالية في UralCash بترتيبها ورؤوسها قبل `2aa66285`:
/// (الفهرس، المجموعة، عنوانُ القسم فوقه).
const _kUralCashFinanceLayout = <(int, String, String?)>[
  (68, 'accounting', 'المالية والمحاسبة'),
  (69, 'accounting', null),
  (34, 'accounting', null),
  (67, 'accounting', null),
  (65, 'accounting', null),
  (66, 'accounting', null),
  (70, 'accounting', null),
  (10, 'accounting', null),
  (56, 'accounting', null),
  (35, 'accounting', null),
  (22, 'accounting', null),
  (28, 'accounting', null),
  (26, 'accounting', null),
  (27, 'accounts', 'الحسابات'),
  (33, 'accounts', null),
  (36, 'accounts', null),
  (73, 'accounts', null),
  (32, 'journal', 'اليومية العامة'),
  (74, 'journal', null),
  (53, 'journal', null),
];

/// يعيد ترتيبَ مداخل المالية من [shared] (تخطيطُ PicPos) إلى تخطيط UralCash
/// القديم في موضع أوّلها. ما لم يُذكَر في [_kUralCashFinanceLayout] يبقى
/// في موضعه — فمدخلٌ ماليٌّ جديدٌ لا يسقط من UralCash صامتاً.
List<NavItemDef> _uralCashFinanceNavLayout(List<NavItemDef> shared) {
  final byIndex = {for (final i in shared) i.index: i};
  final moved = {
    for (final e in _kUralCashFinanceLayout)
      if (byIndex.containsKey(e.$1)) e.$1,
  };
  final first = shared.indexWhere((i) => moved.contains(i.index));
  if (first < 0) return shared;
  return [
    for (final i in shared.take(first))
      if (!moved.contains(i.index)) i,
    for (final (index, group, section) in _kUralCashFinanceLayout)
      if (byIndex[index] case final i?)
        NavItemDef(
          icon: i.icon,
          label: i.label,
          permission: i.permission,
          index: i.index,
          section: section,
          group: group,
        ),
    for (final i in shared.skip(first))
      if (!moved.contains(i.index)) i,
  ];
}

/// كل عناصر القائمة الجانبية، بترتيبها ومرتبطة بأكواد الصلاحيات.
///
/// اتشالت من جوّه `userNavItemsProvider` لثابت مستوى الملف عشان اختبار
/// `screen_permission_map_test.dart` يقدر يتأكد إن عنصر القائمة الخاص
/// بكل شاشة متفق مع `screenPermissionMap[screenId]` — من غير ما يحتاج
/// يشغّل الـ provider بكل تبعياته (auth state, DB, إلخ).
///
/// ⚠️ E-fix ٣ — القائمةُ أدناه تخطيطُ PicPos (فصلُ المرحلة هـ)، وUralCash
/// يراها بتخطيط المالية القديم ([_uralCashFinanceNavLayout]).
final kAllNavItemDefs = Brand.isPicPos
    ? _picposHrNavLayout(_kNavItemDefsShared)
    : _uralCashFinanceNavLayout(_kNavItemDefsShared);

/// J4 — في PicPos تصير الشاشةُ القديمة (‏`16`) «الحضور والرواتب» تحت
/// «سجل الموظفين»، فلا يظهر مدخلان باسم «الموظفين». UralCash لا يمرّ من هنا.
List<NavItemDef> _picposHrNavLayout(List<NavItemDef> shared) => [
      for (final i in shared)
        if (i.index == 16)
          NavItemDef(
            icon: PhosphorIconsBold.calendarCheck,
            label: kPicPosLegacyHrLabel,
            permission: i.permission,
            index: i.index,
            group: i.group,
          )
        else
          i,
    ];

/// تسميةُ شاشة الموارد البشريّة القديمة في PicPos (J4).
const kPicPosLegacyHrLabel = 'الحضور والرواتب';

final _kNavItemDefsShared = [
  // ═══════════════════════════════════════════
  // 🏠 Dashboard
  // ═══════════════════════════════════════════
  // كانت permission: null — أي حد يشوفها حتى لو الشاشة نفسها ممنوعة عنه.
  // قبل كده كان ده متّسق لأن لوحة التحكم كانت بتتحقن في allowedScreens
  // قسراً لكل الناس؛ دلوقتي screenPermissionMap بيربطها بـ dashboard_access
  // فعلاً، فلازم عنصر القائمة يتحكم بنفس الكود عشان مايفضلش رابط ميت لشاشة
  // ممنوعة (أو العكس).
  const NavItemDef(icon: PhosphorIconsBold.house, label: 'Dashboard', permission: PermissionCodes.dashboardAccess, index: 0, section: 'Dashboard', group: 'home'),

  // ═══════════════════════════════════════════
  // 💰 المبيعات
  // ═══════════════════════════════════════════
  const NavItemDef(icon: PhosphorIconsBold.shoppingCart, label: 'البيع السريع', permission: 'pos_access', index: 1, section: 'المبيعات', group: 'sales'),
  const NavItemDef(icon: PhosphorIconsBold.fileText, label: 'فواتير المبيعات', permission: 'sales_view', index: 17, group: 'sales'),
  const NavItemDef(icon: PhosphorIconsBold.fileText, label: 'عروض الأسعار', permission: PermissionCodes.quotesView, index: 75, group: 'sales'),
  const NavItemDef(icon: PhosphorIconsBold.notepad, label: 'طلبات البيع', permission: 'sales_orders_view', index: 37, group: 'sales'),
  // ⚠️ **الموضعُ السادس** — لا الخامس. حارسُ `bookings_screen_wiring_test`
  // كان يقيس خمسةً (`ScreenId` · `AppScreen` · `screenPermissionMap` ·
  // نطاقاتُ الملفّات · `ScreenConfig`) والشاشةُ **ما زالت غائبةً عن القائمة
  // الجانبيّة**: هذه القائمةُ مصدرٌ مستقلٌّ لا يُشتقّ من تلك الخمسة.
  // بلاغُ المالك 2026-08-23. والحارسُ وُسِّع ليقيسها.
  const NavItemDef(icon: PhosphorIconsBold.calendarCheck, label: 'الحجوزات', permission: 'tables_view', index: 61, group: 'sales'),
  const NavItemDef(icon: PhosphorIconsBold.tag, label: 'العروض', permission: 'offers_view', index: 2, group: 'sales'),
  const NavItemDef(icon: PhosphorIconsBold.arrowUUpLeft, label: 'مرتجع المبيعات', permission: 'sales_return_view', index: 44, group: 'sales'),
  // المرحلة و — PicPos وحدَها (‏[kPicPosOnlyNavIndexes]).
  const NavItemDef(icon: PhosphorIconsBold.truck, label: 'إدارة المناديب والتوزيع', permission: 'distribution_view', index: 78, group: 'sales'),

  // ═══════════════════════════════════════════
  // 🍽️ ادارة المطاعم — طلبُ المالك 2026-09-12
  // ═══════════════════════════════════════════
  // ⚠️ **الحجوزاتُ تبقى في المبيعات** ولم تُنقَل معهما: أمرُ المالك سمّى
  // شاشتَين بعينِهما، والحجوزاتُ نطاقُها أوسعُ من المطعم (الصالوناتُ تحجز
  // ولا مطبخَ لها ولا طاولاتِ خدمة) — ونطاقُها في `ScreenRegistry` يشهد.
  const NavItemDef(icon: PhosphorIconsBold.circlesThree, label: 'الطاولات', permission: 'tables_view', index: 3, section: 'ادارة المطاعم', group: 'restaurant'),
  // مصمّمُ القاعة — مدخلٌ جانبيٌّ مستقلٌّ بأمر المالك 2026-09-18.
  //
  // ⚠️ **وصلاحيّتُه `tables_manage` لا `tables_view`**: النادلُ يرى
  //    الخريطةَ ولا يرسمُها، ومدخلٌ يراه ثمّ يُرفَض عند النقر أسوأُ
  //    من غيابِه.
  const NavItemDef(icon: PhosphorIconsBold.squaresFour, label: 'مصمم القاعة', permission: 'tables_manage', index: 72, group: 'restaurant'),
  const NavItemDef(icon: PhosphorIconsBold.cookingPot, label: 'المطبخ', permission: 'kitchen_view', index: 14, group: 'restaurant'),

  // ═══════════════════════════════════════════
  // 🛒 المشتريات
  // ═══════════════════════════════════════════
  const NavItemDef(icon: PhosphorIconsBold.receipt, label: 'فواتير المشتريات', permission: 'purchases_create', index: 9, section: 'المشتريات', group: 'purchases'),
  const NavItemDef(icon: PhosphorIconsBold.clipboardText, label: 'أوامر الشراء', permission: 'purchase_orders_view', index: 30, group: 'purchases'),
  const NavItemDef(icon: PhosphorIconsBold.arrowUUpLeft, label: 'مرتجع المشتريات', permission: 'purchases_return_view', index: 45, group: 'purchases'),
  // 🆕 المشتريات الخارجيّة — بندُ المالك 2026-09-18، آخرُ مجموعةِ
  // «المشتريات». وفيها وحدَها تُبلَغ «التكاليف المحمّلة».
  const NavItemDef(icon: PhosphorIconsBold.globeHemisphereEast, label: 'المشتريات الخارجية', permission: 'purchases_create', index: 71, group: 'purchases'),

  // ═══════════════════════════════════════════
  // 📦 الاصناف والمخزون
  // ═══════════════════════════════════════════
  const NavItemDef(icon: PhosphorIconsBold.package, label: 'الأصناف', permission: 'products_add', index: 4, section: 'الاصناف والمخزون', group: 'inventory'),
  const NavItemDef(icon: PhosphorIconsBold.squaresFour, label: 'التصنيفات', permission: 'products_add', index: 5, group: 'inventory'),
  const NavItemDef(icon: PhosphorIconsBold.warehouse, label: 'المخزون', permission: 'inventory_view', index: 8, group: 'inventory'),
  const NavItemDef(icon: PhosphorIconsBold.clipboardText, label: 'أرصدة المخزون', permission: 'inventory_view', index: 19, group: 'inventory'),
  const NavItemDef(icon: PhosphorIconsBold.arrowsLeftRight, label: 'سند تحويل اصناف', permission: 'inventory_transfer', index: 20, group: 'inventory'),
  const NavItemDef(icon: PhosphorIconsBold.arrowsDownUp, label: 'حركة المخزون', permission: 'inventory_view', index: 29, group: 'inventory'),
  // ⚠️ الثلاثةُ التاليةُ **متقاعدةٌ في PicPos** بأمر المالك 2026-09-12 —
  // راجع [kPicPosRetiredNavIndexes]. وتبقى مكتوبةً هنا لأن القائمةَ مشتركةٌ
  // مع الفورك الآخر، فحذفُ السطر يسحب الشاشةَ منه أيضاً.
  const NavItemDef(icon: PhosphorIconsBold.truck, label: 'طلبات الصرف', permission: 'inventory_view', index: 38, group: 'inventory'),
  const NavItemDef(icon: PhosphorIconsBold.money, label: 'التكاليف المحملة', permission: 'purchases_create', index: 41, group: 'inventory'),
  const NavItemDef(icon: PhosphorIconsBold.listChecks, label: 'الجرد الدوري', permission: 'inventory_view', index: 42, group: 'inventory'),

  // ═══════════════════════════════════════════
  // 🏭 ادارة التصنيع — طلبُ المالك 2026-09-12
  // ═══════════════════════════════════════════
  const NavItemDef(icon: PhosphorIconsBold.factory, label: 'التصنيع', permission: 'manufacturing_view', index: 25, section: 'ادارة التصنيع', group: 'manufacturing'),

  // ═══════════════════════════════════════════
  // 👥 العملاء والموردين
  // ═══════════════════════════════════════════
  const NavItemDef(icon: PhosphorIconsBold.usersThree, label: 'العملاء والموردين', permission: 'customers_view', index: 6, section: 'العملاء والموردين', group: 'relations'),
  const NavItemDef(icon: PhosphorIconsBold.user, label: 'العملاء', permission: 'customers_view', index: 76, section: 'العملاء والموردين', group: 'relations'),
  const NavItemDef(icon: PhosphorIconsBold.truck, label: 'الموردون', permission: 'customers_view', index: 77, group: 'relations'),
  const NavItemDef(icon: PhosphorIconsBold.trophy, label: 'نقاط العملاء', permission: 'loyalty_view', index: 23, group: 'relations'),
  const NavItemDef(icon: PhosphorIconsBold.truck, label: 'التوزيع', permission: 'distribution_view', index: 24, group: 'relations'),

  // ═══════════════════════════════════════════
  // 🧑‍💼 الموارد البشرية — طلبُ المالك 2026-09-12
  // ═══════════════════════════════════════════
  // J4 — PicPos وحدَها (‏[kPicPosOnlyNavIndexes]): سجلُّ الموظفين وملفُّهم،
  // والأقسامُ والمسمّياتُ والهيكل. وفي PicPos يُسمّى `16` «الحضور والرواتب»
  // (‏[_picposHrNavLayout]) حتى يحلّ محلَّه الجزآن ٢ و٣.
  const NavItemDef(icon: PhosphorIconsBold.identificationCard, label: 'سجل الموظفين', permission: 'hr_view', index: 79, section: 'الموارد البشرية', group: 'hr'),
  const NavItemDef(icon: PhosphorIconsBold.treeStructure, label: 'الأقسام والمسميات الوظيفية', permission: 'hr_view', index: 80, group: 'hr'),
  // J4 (الجزء ٢) — الحضورُ والإجازاتُ والورديّات (PicPos وحدَها).
  const NavItemDef(icon: PhosphorIconsBold.fingerprint, label: 'الحضور والانصراف', permission: 'hr_attendance_view', index: 81, group: 'hr'),
  const NavItemDef(icon: PhosphorIconsBold.airplaneTilt, label: 'الإجازات', permission: 'hr_leave_request', index: 82, group: 'hr'),
  const NavItemDef(icon: PhosphorIconsBold.clockClockwise, label: 'الورديات', permission: 'hr_shifts_manage', index: 83, group: 'hr'),
  // J4 (الجزء ٣) — الرواتبُ والسلفُ والعمولات (PicPos وحدَها)، وتحلّ محلَّ
  // «الحضور والرواتب» (‏`16`، [kPicPosReplacedNavIndexes]).
  const NavItemDef(icon: PhosphorIconsBold.money, label: 'الرواتب', permission: 'hr_payroll_view', index: 84, group: 'hr'),
  const NavItemDef(icon: PhosphorIconsBold.handCoins, label: 'السلف والجزاءات', permission: 'hr_payroll_view', index: 85, group: 'hr'),
  const NavItemDef(icon: PhosphorIconsBold.percent, label: 'عمولات المندوبين', permission: 'hr_payroll_view', index: 86, group: 'hr'),
  const NavItemDef(icon: PhosphorIconsBold.users, label: 'الموظفين', permission: 'hr_view', index: 16, section: 'الموارد البشرية', group: 'hr'),

  // ═══════════════════════════════════════════
  // 💵 المالية والمحاسبة
  // ═══════════════════════════════════════════
  // ⚠️ **الترتيبُ أمرُ مالكٍ 2026-09-18** (‏`PLAN-REDESIGN-SCREENS.md` §٣):
  //    سبعةٌ في صدر المجموعة ثمّ بقيّتُها كما هي. ولا يُقرأ الترتيبُ من
  //    `kNavGroupDefs` — الشريطُ يبني ترتيبَ الرؤوس من **أوّلِ ظهورٍ** لكلّ
  //    مفتاحٍ هنا، وترتيبَ المداخل من موضعها في هذه القائمة.
  //
  // ⚠️ **و«اليومية العامة» مطويّةٌ في PicPos** ضمن حاوية «الحسابات»
  //    (`kPicPosFoldedIntoAccountingHub` فيه الفهرس ٣٢). فصدرُ المجموعة
  //    المرئيُّ في PicPos يبدأ بما بعدها — والترتيبُ النسبيُّ كما طُلب،
  //    والطيُّ قرارٌ سابقٌ مستقلٌّ يُرفَع بسطر.
  const NavItemDef(icon: PhosphorIconsBold.arrowCircleDown, label: 'سند قبض', permission: 'treasury_view', index: 68, section: 'الإدارة المالية', group: 'accounting'),
  const NavItemDef(icon: PhosphorIconsBold.arrowCircleUp, label: 'سند صرف', permission: 'treasury_view', index: 69, group: 'accounting'),
  NavItemDef(icon: PhosphorIconsBold.checks, label: chequesScreenLabel, permission: 'treasury_view', index: 34, group: 'accounting'),
  // ⚠️ **بعد صدرِ المجموعة لا داخلَه.** ترتيبُ السبعةِ الأُوَل أمرُ مالكٍ
  //    2026-09-18 ويثبّته `asset_screens_have_their_writers_test`، وقد رُسم
  //    قبل أن يوجد الدفترُ أصلاً. ووضعُه بجوار «إدارة الشيكات» — وهو موضعُه
  //    المنطقيّ — يزيح ترتيباً طلبه المالكُ بنفسه، فذاك قرارُه لا اجتهادُنا.
  // E4 — وفي PicPos صار تبويباً داخل «إدارة الشيكات» فيُخفى مدخلُه هنا
  //    (‏`kPicPosReplacedNavIndexes`)؛ ويبقى لـUralCash كما هو.
  const NavItemDef(icon: PhosphorIconsBold.checkSquareOffset, label: 'دفتر الشيكات', permission: 'treasury_view', index: 70, group: 'accounting'),
  // ── بقيّةُ المجموعة كما هي ────────────────────────────────────────────
  const NavItemDef(icon: PhosphorIconsBold.wallet, label: 'الخزينة', permission: 'treasury_view', index: 10, group: 'accounting'),
  const NavItemDef(icon: PhosphorIconsBold.lockKey, label: 'إغلاق الوردية', permission: PermissionCodes.posShiftClose, index: 56, group: 'accounting'),

  // ═══════════════════════════════════════════
  // 📘 الحسابات — رأسٌ لا مدخل (أمرُ المالك 2026-09-20)
  // ═══════════════════════════════════════════
  //
  // كانت حاويةً تُفتَح شاشةً بتسعة تبويبات. صارت التبويباتُ
  // شاشاتٍ مستقلّةً، و«الحسابات» رأسَ مجموعةٍ يطوي ويبسط
  // ولا ينتقل إلى شاشة.
  //
  // ⚠️ **وموضعُ الرأس من هنا لا من `kNavGroupDefs`**: الشريطُ يبني
  //    ترتيبَه من **أوّل ظهورٍ** لكلّ مفتاح، فنقلُ أوّل مدخلٍ
  //    ينقل الرأسَ كلَّه.
  const NavItemDef(icon: PhosphorIconsBold.treeStructure, label: 'دليل الحسابات', permission: 'settings_view', index: 27, section: 'إدارة الحسابات', group: 'accounts'),
  const NavItemDef(icon: PhosphorIconsBold.crosshair, label: 'مراكز التكلفة', permission: 'settings_view', index: 33, group: 'accounts'),
  const NavItemDef(icon: PhosphorIconsBold.book, label: 'دفتر الأستاذ', permission: 'settings_view', index: 36, group: 'accounts'),
  // ⚠️ **شاشةٌ جديدةٌ لما لم يكن شاشةً**: ميزانُ المراجعة كان
  //    `view` داخلَ القوائم المالية يُبلَغ من تبويب `tb` وحدَه.
  const NavItemDef(icon: PhosphorIconsBold.scales, label: 'ميزان المراجعة', permission: 'reports_view', index: 73, group: 'accounts'),

  // ═══════════════════════════════════════════
  // 📒 اليومية العامة — رأسٌ جديد (أمرُ المالك 2026-09-20)
  // ═══════════════════════════════════════════
  NavItemDef(icon: PhosphorIconsBold.notebook, label: journalEntriesScreenLabel, permission: 'settings_view', index: 32, group: 'accounts'), // E1 — كانت رأسَ «اليومية العامة»
  // ⚠️ **وقوالبُ القيود لم يكن لها معرِّفٌ ولا مدخل**: تُفتَح
  //    بدفعةٍ من شاشة اليومية وبتبويب `tpl`. والدفعةُ تبقى.
  const NavItemDef(icon: PhosphorIconsBold.stack, label: 'قوالب القيود', permission: 'settings_view', index: 74, group: 'accounts'),
  const NavItemDef(icon: PhosphorIconsBold.bank, label: 'المطابقة البنكية', permission: 'settings_view', index: 53, group: 'accounts'),
  // ── E1 — منقولةٌ من «المالية والمحاسبة» إلى «إدارة الحسابات» ──
  // ⚠️ مصدرُ توصيلٍ **سادسٌ مستقلٌّ**: شاشةٌ صحيحةٌ في `ScreenId` و`AppScreen`
  //    وخريطةِ الصلاحيات والنطاقِ و`ScreenConfig` تبقى **غائبةً عن القائمة
  //    الجانبيّة** بلا هذين السطرين. وقع فعلاً مع الحجوزات 2026-08-22 وكلُّ
  //    الحرّاس خضراء.
  const NavItemDef(icon: PhosphorIconsBold.notePencil, label: 'سند قيد', permission: 'settings_view', index: 67, group: 'accounts'),
  const NavItemDef(icon: PhosphorIconsBold.folders, label: 'فئات الأصول', permission: 'assets_view', index: 65, group: 'accounts'),
  const NavItemDef(icon: PhosphorIconsBold.mapPin, label: 'التوزيع والمواقع', permission: 'assets_view', index: 66, group: 'accounts'),
  // حاويةُ «الحسابات» — مدخلٌ واحدٌ يفتح تبويباتِ التصميم السبعة. تظهر في
  // PicPos وحدَها، وتُطوى تحتها مداخلُ [kPicPosFoldedIntoAccountingHub].
  const NavItemDef(icon: PhosphorIconsBold.buildings, label: 'الأصول الثابتة', permission: 'assets_view', index: 35, group: 'accounts'),
  // ⚠️ مصدرُ توصيلٍ **سادسٌ مستقلٌّ** لا يُشتقّ من الخمسة قبله: شاشةٌ صحيحةٌ
  //    في `ScreenId` و`AppScreen` وخريطةِ الصلاحيات والنطاقِ و`ScreenConfig`
  //    تبقى **غائبةً عن القائمة الجانبيّة** بلا هذا السطر. وقع فعلاً مع
  //    الحجوزات 2026-08-22 وكلُّ الحرّاس خضراء.
  const NavItemDef(icon: PhosphorIconsBold.invoice, label: 'الفوترة الإلكترونية', permission: 'einvoice_view', index: 22, group: 'accounts'),
  const NavItemDef(icon: PhosphorIconsBold.calendar, label: 'السنوات المالية', permission: 'settings_view', index: 28, group: 'accounts'),
  const NavItemDef(icon: PhosphorIconsBold.coins, label: 'المصروفات التشغيلية', permission: 'settings_view', index: 26, group: 'accounts'),

  // ═══════════════════════════════════════════
  // 📊 التقارير والتحليلات
  // ═══════════════════════════════════════════
  const NavItemDef(icon: PhosphorIconsBold.chartBar, label: 'التقارير', permission: 'reports_view', index: 11, section: 'التقارير', group: 'reports'),
  // Task 3d — كان على 'reports_view' وده كود عام؛ screenPermissionMap
  // بيربط الشاشة بـ analytics_view من زمان. اللي عنده reports_view بس
  // كان بيشوف الرابط وميقدرش يفتح الشاشة (رابط ميت). اتصلّح ليتفق مع
  // الخريطة — راجع منح analytics_view في RoleGrantMatrix.defaultGrants
  // والسيدر عشان محاسب/مدير مالي/مدير فرع/مدير مخزون ما يفقدوش الرابط.
  const NavItemDef(icon: PhosphorIconsBold.chartPie, label: 'التحليلات', permission: PermissionCodes.analyticsView, index: 15, group: 'reports'),
  const NavItemDef(icon: PhosphorIconsBold.chartBar, label: 'أداء الفروع', permission: 'reports_view', index: 39, group: 'reports'),
  const NavItemDef(icon: PhosphorIconsBold.chartBar, label: 'اعداد وتصميم التقارير', permission: 'reports_view', index: 43, group: 'reports'),

  // ═══════════════════════════════════════════
  // ⚙️ اعداد النظام
  // ═══════════════════════════════════════════
  // Task 3d — اختبار الاتفاق المعمّم كشف نفس عائلة عطل «التحليلات» هنا:
  // كان على 'settings_view' بينما screenPermissionMap يربط الشاشة بـ
  // branches_manage. راجع منح branches_manage لمحاسب متقدم تحت (كان
  // بيشوف الرابط عبر settings_view بس ماعندوش الكود الفعلي).
  const NavItemDef(icon: PhosphorIconsBold.buildings, label: 'الفروع والمخازن', permission: PermissionCodes.branchesManage, index: 13, section: 'اعداد النظام', group: 'system'),
  const NavItemDef(icon: PhosphorIconsBold.mapPin, label: 'المناطق', permission: 'settings_view', index: 60, group: 'system'),
  const NavItemDef(icon: PhosphorIconsBold.scales, label: 'ميزان التسعير', permission: 'settings_scale', index: 21, group: 'system'),
  const NavItemDef(icon: PhosphorIconsBold.gear, label: 'الإعدادات', permission: 'settings_view', index: 12, group: 'system'),
  // طلبُ المالك 2026-09-12: نُقل من «التقارير» إلى شاشات النظام **تحت**
  // الإعدادات. وصلاحيّتُه `audit_view` كما هي — النقلُ يمسّ الموضعَ لا الحقّ.
  const NavItemDef(icon: PhosphorIconsBold.clipboardText, label: 'سجل العمليات', permission: 'audit_view', index: 18, group: 'system'),
  // ⚠️ المصدرُ **السادسُ** للتوصيل ولا يُشتقّ من الخمسة قبله: شاشةٌ صحيحةٌ في
  //    `ScreenId` و`AppScreen` والصلاحياتِ والنطاقِ و`ScreenConfig` تبقى
  //    غائبةً عن القائمة الجانبيّة بلا هذا السطر — وقع مع الحجوزات
  //    2026-08-22 وكلُّ الحرّاس خضراء.
  const NavItemDef(icon: PhosphorIconsBold.gitFork, label: 'حسم القوالب', permission: PermissionCodes.settingsPrinter, index: 64, group: 'system'),
  const NavItemDef(icon: PhosphorIconsBold.question, label: 'مركز المساعدة', permission: 'pos_access', index: 40, group: 'system'),
];

/// ✅ **الطيُّ رُفِع 2026-09-20 بأمر المالك — والحاويةُ حُذفت.**
///
/// كانت ستّةُ مداخلَ تُطوى تحت «الحسابات» في PicPos. صارت التبويباتُ
/// شاشاتٍ مستقلّةً تحت رأسَين: «الحسابات» و«اليومية العامة» — والرأسُ في
/// هذا الشريط يطوي ويبسط **ولا ينتقل إلى شاشة**.
///
/// ⚠️ **والمجموعةُ حقلٌ مشترَكٌ بين الفوركَين** (‏`group:` في `NavItemDef`
/// بلا فرعِ علامة)، فإعادةُ التوزيع تسري على UralCash أيضاً. والعملُ عليه
/// موقوفٌ بقرارٍ سابق، والتجميعُ **عرضٌ لا سلوك** — فقُبِل مكتوباً لا سهواً،
/// وبديلُه تفريعُ `group` بالعلامة وهو كلفةٌ بلا عائدٍ اليوم.
///
/// وتبقى الثابتةُ فارغةً لا محذوفةً: `brand_picpos_test` و
/// `brand_isolation_test` يقيسان أنّ الطيَّ **لا يُعاد** بلا قرار.
const kPicPosFoldedIntoAccountingHub = <int>{};

/// مداخلُ [items] بصيغةٍ قابلةٍ للبحث — مع كلماتِ [kNavSearchKeywords].
///
/// ⚠️ **المحوّلُ هنا لا في `domain`**: `nav_search.dart` حسابٌ خالصٌ في
/// طبقة النطاق، واستيرادُه `NavItemDef` من `data/providers` يقلب اتّجاهَ
/// الطبقات. فالمعرفةُ بالنوعَين تعيش في الطبقة الأعلى.
List<NavSearchEntry> navEntriesFromNavItems(List<NavItemDef> items) => [
      for (final i in items)
        NavSearchEntry(
          index: i.index,
          label: i.label,
          group: i.group,
          keywords: kNavSearchKeywords[i.index] ?? const [],
        ),
    ];

/// الشاشاتُ التي أسقطها المالكُ من PicPos — «مش محتاجهم يبقوا موجودين فى
/// النظام للعمل بيهم» (‏2026-09-12).
///
/// ⚠️ **إخفاءٌ لا حذف، والفرقُ مقصود.** الثلاثةُ تكتب في دفاترَ حيّة: الجردُ
/// الدوريُّ يُنشئ تسوياتِ مخزونٍ، والتكاليفُ المحمَّلةُ تدخل في تقييم المخزون
/// وتُرحَّل قيداً، وطلباتُ الصرف تُحرّك أرصدة. فحذفُ جداولها يُتلف تاريخاً
/// مُرحَّلاً لا يُستعاد، وحذفُ شاشاتها يترك صفوفاً لا نافذةَ لقراءتها.
/// والإخفاءُ يحقّق المطلوبَ — لا تُبلَغ ولا يُعمَل بها — ويُرَدُّ بسطر.
///
/// ⚠️ **ومحكومٌ بالعلامة**: [kAllNavItemDefs] قائمةٌ مشتركةٌ مع الفورك الآخر،
/// فحذفُ السطر منها يسحب الشاشةَ من منتَجٍ آخرَ لم يطلب أحدٌ تغييرَه. وهو
/// نفسُ عقدِ [kPicPosFoldedIntoAccountingHub].
///
/// ⚠️ **و`41` (التكاليفُ المحمّلة) بقيت هنا وخرجت من
/// [ScreenRegistry.picposRetired]** — 2026-09-20، المرحلة ٨. قرارُ المالك:
/// «تُفعَّل وتعيش داخل المشتريات الخارجيّة وحدَها، لا مدخلَ جانبيَّ لها».
/// فهذه الحالةُ الوحيدةُ التي **يُفترَق فيها الموضعان عمداً**: القائمةُ
/// تُخفيها، والنطاقُ يُبلغها — وشاشةُ الاستيراد وحدَها هي التي تُبلغها.
/// وحذفُها من هنا يُعيد المدخلَ الجانبيَّ الذي أسقطه المالك.
const kPicPosRetiredNavIndexes = <int>{
  38, // طلبات الصرف
  41, // التكاليف المحملة — مخفيّةٌ من القائمة، **مبلوغةٌ** من شاشة الاستيراد
  42, // الجرد الدوري (‏= `fieldAudit`، اسمان لفهرسٍ واحد)
};

const kPicPosOnlyNavIndexes = <int>{
  75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86,
};
// E4 — `70` (دفتر الشيكات) صار تبويباً داخل «إدارة الشيكات» في PicPos.
// E-fix ٤ب — `24` (التوزيع القديمة) حلّت محلَّها `78` في PicPos.
// J4 (الجزء ٣) — `16` (الحضور والرواتب) حلّت محلَّها `81`…`86` في PicPos.
const kPicPosReplacedNavIndexes = <int>{6, 16, 24, 70};

/// هل يظهر مدخلُ القائمة صاحبُ [index] لهذه العلامة؟
///
/// دالّةٌ خالصةٌ عن قصد: الفرعُ داخلَها ثابتُ ترجمةٍ (`Brand.isPicPos`)،
/// والبوّابةُ تشتغل على الافتراضي `uralcash` — فلو بقي الشرطُ مدفوناً في
/// حلقةِ [userNavItemsProvider] ما نُفِّذ فرعُ PicPos في أيّ اختبار.
/// وهكذا يقيسه `brand_picpos_test.dart` (‏يشغّله سكربتُ بناء PicPos) ويقيس
/// نقيضَه `brand_isolation_test.dart`.
bool navItemVisibleForBrand(int index) {
  // ✅ حاويةُ «الحسابات» حُذفت 2026-09-20، فلم يبقَ إلّا التقاعدُ — وهو
  // فرعُ علامةٍ أصيل: ثلاثُ شاشاتٍ أسقطَها المالكُ من PicPos وحدَها.
  //
  // ⚠️ ويبقى الطيُّ مقروءاً هنا ولو كان فارغاً: أوّلُ من يُعيد ملأه يُعيد
  //    السلوكَ كلَّه بسطر، والحارسان يمنعانه بلا قرار.
  if (Brand.isPicPos) {
    if (kPicPosRetiredNavIndexes.contains(index) ||
        kPicPosReplacedNavIndexes.contains(index)) return false;
    return !kPicPosFoldedIntoAccountingHub.contains(index);
  }
  return !kPicPosOnlyNavIndexes.contains(index);
}

final userNavItemsProvider = FutureProvider<List<NavItemDef>>((ref) async {
  final allNavItems = kAllNavItemDefs;

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

    if (!navItemVisibleForBrand(item.index)) continue;
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
  ScreenId.customers: 'customers_view',
  ScreenId.suppliers: 'customers_view',
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
  ScreenId.quotations: PermissionCodes.quotesView,
  ScreenId.activityLog: 'audit_view',
  ScreenId.inventoryBonds: 'inventory_view',
  ScreenId.stockTransfer: 'inventory_transfer',
  ScreenId.scalePlu: 'settings_scale',
  ScreenId.eInvoice: 'einvoice_view',
  ScreenId.loyalty: 'loyalty_view',
  ScreenId.distribution: 'distribution_view',
  ScreenId.repDistribution: 'distribution_view',
  ScreenId.hrEmployees: 'hr_view',
  ScreenId.hrOrganization: 'hr_view',
  ScreenId.hrAttendance: 'hr_attendance_view',
  ScreenId.hrLeave: 'hr_leave_request',
  ScreenId.hrShifts: 'hr_shifts_manage',
  ScreenId.hrPayroll: 'hr_payroll_view',
  ScreenId.hrAdvances: 'hr_payroll_view',
  ScreenId.hrCommissions: 'hr_payroll_view',
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
  // الحجوزاتُ تعرض عملاءَ ومبالغَ وتفتح مسارَ تفويترٍ — فصلاحيّتُها
  // `tables_view` نفسُها: من يدير الطاولاتِ يدير المواعيد.
  ScreenId.bookings: 'tables_view',
  // ⚠️ `reports_view` عن قصد لا `settings_view` كأخواتها في مجموعة
  //    الحسابات: الشاشةُ تُفتَح اليومَ من شاشة التقارير، فهذا ما يحرسها
  //    فعلاً. واختيارُ كودٍ آخرَ يبدّل **مَن يرى القوائمَ المالية** صامتاً
  //    في الاتّجاهين — والنقلُ إعادةُ تصنيفٍ لا إعادةُ تصريح.
  ScreenId.financialStatements: 'reports_view',
  // الحاويةُ على 'settings_view' — صلاحيّةُ ستٍّ من تبويباتها السبعة. والسابعُ
  // (‏ميزانُ المراجعة/القوائمُ المالية) يحرسه 'reports_view' داخلَ الحاوية،
  // فلا يوسّع دخولُها دائرةَ مَن يرى القوائمَ المالية.
  // خرجتا من حاوية «الحسابات» شاشتين — وبنفس كودَي تبويبَيهما لا بكودٍ
  // جديد: كودٌ جديدٌ يترك كلَّ دورٍ قائمٍ بلا الشاشة حتّى يُمنَح يدويّاً.
  ScreenId.trialBalance: 'reports_view',
  ScreenId.journalTemplates: 'settings_view',
  // نفسُ صلاحيّة الحاوية وستٍّ من تبويباتها — والحارسُ يشترط التطابق.
  ScreenId.bankReconciliation: 'settings_view',
  ScreenId.shiftClose: PermissionCodes.posShiftClose,
  // حسمُ القوالب: قراءةُ إعدادِ طباعةٍ وتشخيصُه، فصلاحيّتُه صلاحيةُ الطابعات
  // نفسُها. و`settings_view` كان سيوسّع الدائرةَ لكلِّ من يرى الإعدادات.
  ScreenId.templateResolution: PermissionCodes.settingsPrinter,
  // الفئاتُ والمواقعُ **تفصيلان في الأصول الثابتة** خرجا إلى مدخلَين — فلا
  // كودَ جديدٌ لهما. وكودٌ ثالثٌ كان يترك كلَّ دورٍ قائمٍ بلا الشاشتَين حتى
  // يُمنح يدويّاً، ويمسّ سجلَّ التكافؤ. وهو عينُ ما حُسم في «حسم القوالب».
  ScreenId.assetCategories: PermissionCodes.assetsView,
  ScreenId.assetLocations: PermissionCodes.assetsView,
  // «سند قيد» على `settings_view` كأختِها «اليومية العامة» — وهو **عينُ**
  // ما يبلغ القيدَ اليدويَّ اليوم. و`accounting_journal` تُفحَص عند الحفظ:
  // ربطُ الشاشة بها كان يسحبها من كلّ دورٍ قائمٍ لأنّها ليست في
  // `RoleGrantMatrix.defaultGrants` أصلاً.
  ScreenId.journalVoucher: 'settings_view',
  // سندا القبض والصرف على `treasury_view` — عينُ ما يبلغ حوارَيهما اليوم.
  // و`treasury_receipts_create`/`treasury_payments_create` **غيرُ ممنوحَين
  // لأيّ دور** في `RoleGrantMatrix.defaultGrants`، فربطُ الشاشتَين بهما
  // كان يسحبهما من الجميع — وتغييرُ **مَن يُنشئ سنداً** قرارُ مالكٍ مستقلّ.
  ScreenId.receiptVoucher: 'treasury_view',
  ScreenId.paymentVoucher: 'treasury_view',
  ScreenId.chequeBooks: 'treasury_view',
  // المشتريات الخارجيّة — عينُ صلاحيّةِ «فواتير المشتريات».
  ScreenId.importPurchases: 'purchases_create',
  // مصمّمُ القاعة — عينُ صلاحيّةِ «إدارةِ الطاولات» لا صلاحيّةٌ جديدة.
  ScreenId.floorPlanDesigner: 'tables_manage',
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
