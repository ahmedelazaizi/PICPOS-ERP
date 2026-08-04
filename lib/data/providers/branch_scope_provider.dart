import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/logging/diagnostic_logger.dart';
import '../../services/mirror_state.dart';
import '../../services/network_service.dart';
import '../../services/sync_service.dart';
import 'providers.dart';

/// Snapshot of the branches the current user is allowed to see.
///
/// `allowedBranchIds == null` means full access (system admin / financial
/// manager / userId=1) — listings should not apply any branch filter and
/// should fall back to the global query path. A non-null set is the
/// closed list of branch IDs the user can read; queries must restrict
/// rows to those IDs and treat any other branch as out-of-scope.
///
/// `primaryBranchId` is the user's "home" branch — the first row in
/// `user_branch_access`, mirroring the legacy `getUserBranchId` semantics.
/// Used by screens that need a single branch context (POS, current shift,
/// default-safe lookup) rather than a multi-branch filter.
class BranchScope {
  final Set<int>? allowedBranchIds;
  final int? primaryBranchId;

  const BranchScope({
    required this.allowedBranchIds,
    required this.primaryBranchId,
  });

  /// Convenience for admins / unauthenticated paths — no filter applied.
  const BranchScope.fullAccess()
      : allowedBranchIds = null,
        primaryBranchId = null;

  bool get hasFullAccess => allowedBranchIds == null;

  /// True when [branchId] is visible under this scope. Null branchId is
  /// always allowed (legacy rows without a branch link must remain visible
  /// rather than disappear from a restricted user's lists).
  bool isAllowed(int? branchId) =>
      hasFullAccess || branchId == null || allowedBranchIds!.contains(branchId);

  // Spec 115 — value equality so Riverpod's identity check doesn't
  // re-emit a "new" scope every time branchScopeProvider re-runs.
  // Without this, downstream StreamProviders (allPartiesProvider et al.)
  // see a fresh BranchScope instance each tick → recreate their Drift
  // streams → loading→data flicker → IconButton instances rebuild every
  // frame → taps never land. The flicker was a *symptom* of provider
  // re-emission; equating the scope by content stops the cascade.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! BranchScope) return false;
    if (primaryBranchId != other.primaryBranchId) return false;
    final a = allowedBranchIds;
    final b = other.allowedBranchIds;
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }

  @override
  int get hashCode {
    final ids = allowedBranchIds;
    final idsHash = ids == null
        ? 0
        : ids.fold<int>(0, (acc, id) => acc ^ id.hashCode);
    return Object.hash(primaryBranchId, idsHash);
  }
}

/// المرحلة ١ / FR-2 — الحدّ الذي تُقاس عليه «الصفوف الغريبة» في أداة
/// التنظيف (`BranchScopeCleanupExtension`).
///
/// كانت الواجهة تمرّر `<int>{}` كلما كان [BranchScope.hasFullAccess]، وحارس
/// المجموعة الفارغة يترجم ذلك إلى «لا صفوف غريبة بالتعريف». لكن **مدير
/// النظام** على جهاز عميل مربوط يكون `isCrossBranchElevated` ⇒ صلاحية
/// كاملة ⇒ الفحص يقول «لا توجد صفوف» على جهاز مليء بصفوف فروع أخرى، وهو
/// بالضبط المشغّل الذي تطلب منه ملاحظات الإصدار تشغيل الأداة.
///
/// على جهاز عميل، «الغريب» يحدّده **ربط الجهاز** (`client_branch_id` الذي
/// يكتبه معالج الإعداد) لا نطاق صلاحية المستخدم: الصلاحية تقول ماذا يحقّ
/// له أن يرى، والربط يقول أي بيانات يُفترض أن تسكن هذا القرص.
///
/// تبقى المجموعة فارغة — فيُبطِل الحارس الأداة — في حالتين فقط، وكلتاهما
/// مقصودة: سياق غير محصور فعلاً (سيرفر · مستقل · مرآة، فلا «فرع للجهاز»
/// أصلاً وقاعدة السيرفر هي الأصل)، وجهاز عميل لم يُربَط بفرع قط (لا نحذف
/// بناءً على حدّ مجهول).
Future<Set<int>> resolveForeignRowScope(BranchScope scope) async {
  if (!scope.hasFullAccess) return scope.allowedBranchIds!;
  if (!NetworkService.instance.isClient) return const <int>{};
  final prefs = await SharedPreferences.getInstance();
  final deviceBranchId = prefs.getInt('client_branch_id');
  return deviceBranchId == null ? const <int>{} : <int>{deviceBranchId};
}

/// Record which arm of [branchScopeProvider] produced the scope.
///
/// An empty (non-null) `allowedBranchIds` silently hides EVERY branch-tagged
/// row from the user — invoice lists, reports and POS lookups all come back
/// empty with no error surfaced. Without this line the only trace was a
/// `debugPrint`, which never reaches the on-disk log a field operator can
/// send back, so the failure was indistinguishable from "there is no data".
Future<BranchScope> _loggedScope(
  int? userId,
  String source,
  BranchScope scope,
) async {
  await DiagnosticLogger.log(
    'BRANCH-SCOPE',
    'userId=$userId source=$source '
    'allowed=${scope.allowedBranchIds == null ? "ALL" : scope.allowedBranchIds!.toList()} '
    'primary=${scope.primaryBranchId}'
    '${scope.allowedBranchIds != null && scope.allowedBranchIds!.isEmpty ? " ⚠ EMPTY SCOPE — every branch-tagged row will be hidden" : ""}',
  );
  return scope;
}

/// Resolved branch scope for the currently logged-in user.
///
/// Backed by [getUserAccessibleBranchIds] so it honours both direct
/// per-user assignments and region-grant inheritance. Empty access list
/// is mapped to [BranchScope.fullAccess] to match the existing DAO
/// convention (admin/financial manager bypass already returns `[]`).
///
/// Phase 6 (T6) — on a paired client device with the branch-isolation
/// flag on (the default), every user (admins included) is narrowed to
/// the device's branch. Defense-in-depth: even if Tier 3 sync ever leaks
/// foreign rows (legacy DB, flag flipped temporarily, etc.), the UI
/// won't surface them. The narrowing is bypassed when the operator
/// flips `client_pulls_transactional_enabled` to true (they explicitly
/// asked to revert to pre-Phase-6 cross-branch behaviour).
final branchScopeProvider = FutureProvider<BranchScope>((ref) async {
  // Spec 135 silent-drift (e) — watch ONLY the two fields this provider
  // actually uses, not the whole AuthState. The auth notifier emits a new
  // AuthState on every heartbeat (copyWith(lastActivity: now)); since
  // AuthState has no value equality, watching it whole re-ran this provider
  // every tick → branchScope re-emitted → allPartiesProvider et al. recreated
  // their Drift streams (the parties rebuild storm, Spec 115's residual). A
  // record select compares structurally, so this only re-runs when the user
  // id or cross-branch elevation actually changes.
  final (userId, isCrossBranchElevated) = ref.watch(
    authProvider.select((s) => (s.user?.id, s.isCrossBranchElevated)),
  );
  if (userId == null) {
    return _loggedScope(null, 'no-user', const BranchScope.fullAccess());
  }

  final db = ref.read(databaseProvider);
  final accessIds = await db.getUserAccessibleBranchIds(userId);

  // Feature 006 (MM.B) — Mirror mode: this device is acting as the HQ
  // admin console. Mirror is a *device-level* assertion (the operator
  // paired the laptop in the wizard, captured in `MirrorState`), so it
  // takes precedence over session-level elevation. Placed FIRST so any
  // future change to `isCrossBranchElevated` semantics doesn't accidentally
  // strip mirror's *device* scope — the mirror caches every branch, so the
  // client-pairing narrowing below must never fire here.
  //
  // 2026-08-04 (بطلب المالك، خارج نطاق المرحلة ١) — «المرآة تعرض كل الفروع»
  // كان يعني: ارمِ `accessIds` وأرجِع صلاحية كاملة بلا شرط. المقصود هو أن
  // الجهاز غير محصور، لا أن **المستخدم** غير محصور — فمدير مخصَّص له فرعان
  // كان يرى كل الفروع. والخادم بعد FR-1 يقصّ نفس المستدعي على
  // `IN (allowed)`، فكانت الواجهة تعلن نطاقاً أوسع مما يسلّمه الخادم.
  if (NetworkService.instance.isMirror &&
      MirrorState.instance.isConfigured) {
    if (accessIds.isNotEmpty) {
      // `primaryBranchId` = getUserBranchId لا `accessIds.first`:
      // getUserAccessibleBranchIds تبني مجموعة من صفوف بلا `orderBy` ثم
      // تدمج فروع المناطق، فترتيبها غير مضمون — وهو بعينه العطل الذي
      // يوثّقه getUserBranchId (أرقام فواتير تتأرجح بين بادئتي فرعين).
      final primary = await db.getUserBranchId(userId);
      return _loggedScope(
        userId,
        'mirror-device-scoped',
        BranchScope(
          allowedBranchIds: accessIds.toSet(),
          primaryBranchId: primary,
        ),
      );
    }
    // القائمة الفارغة غامضة (انظر ذراع `accessIds.isEmpty` أدناه): مستخدم
    // مميّز ⇒ وصول كامل حقيقي، وغير مميّز ⇒ سيّئ التزويد. نفرّق بنفس
    // السنتينل الذي تستخدمه بقية المسارات كي لا تصير المرآة ثغرة تلتفّ
    // على الفشل المقفول.
    final privileged = await db.isFullBranchAccessUser(userId);
    return _loggedScope(
      userId,
      privileged ? 'mirror-device-full' : 'mirror-device-fail-closed',
      privileged
          ? const BranchScope.fullAccess()
          : const BranchScope(allowedBranchIds: <int>{}, primaryBranchId: null),
    );
  }

  // Feature 004 (US3, FR-021/FR-024) — System Admin elevated on a paired
  // client device with the server connection live. Bypass the Phase 6
  // narrowing below and grant the same all-branches scope server mode
  // produces. Inserted ABOVE the existing block so the narrowing logic
  // for non-elevated users remains untouched.
  if (isCrossBranchElevated) {
    return _loggedScope(
        userId, 'cross-branch-elevated', const BranchScope.fullAccess());
  }

  if (NetworkService.instance.isClient) {
    final isolated = SyncService.instance?.clientPullsTransactionalEnabled == false;
    if (isolated) {
      final prefs = await SharedPreferences.getInstance();
      final clientBranchId = prefs.getInt('client_branch_id');
      if (clientBranchId != null) {
        return _loggedScope(
          userId,
          'client-branch-isolation',
          BranchScope(
            allowedBranchIds: {clientBranchId},
            primaryBranchId: clientBranchId,
          ),
        );
      }
      // Branch isolation is ON but the device was never stamped with its
      // branch during pairing. We fall through to the user-assignment path
      // below; record it, because the fall-through is otherwise invisible
      // and changes which branches the operator can see.
      await DiagnosticLogger.log('BRANCH-SCOPE',
          'userId=$userId ⚠ isolation enabled but client_branch_id pref is '
          'missing — falling through to user assignments');
    }
  }

  if (accessIds.isEmpty) {
    // Spec 151 Track-3 (client twin of residual #2 / D-06 fail-open):
    // getUserAccessibleBranchIds returns `[]` for TWO different users — a
    // privileged one (admin / financial manager / userId=1 → genuine full
    // access) AND a non-privileged one mis-provisioned with zero branch/region
    // assignments. The latter must fail CLOSED (see nothing), not inherit
    // company-wide access — otherwise every branch-scope cap downstream
    // (reports, POS, parties) becomes a no-op for that user. isFullBranchAccessUser
    // is the same sentinel the server-side fix (_extractBranchId) uses.
    final privileged = await db.isFullBranchAccessUser(userId);
    return _loggedScope(
      userId,
      privileged ? 'no-assignments-privileged' : 'no-assignments-fail-closed',
      privileged
          ? const BranchScope.fullAccess()
          : const BranchScope(allowedBranchIds: <int>{}, primaryBranchId: null),
    );
  }

  final primary = await db.getUserBranchId(userId);
  return _loggedScope(
    userId,
    'user-assignments',
    BranchScope(
      allowedBranchIds: accessIds.toSet(),
      primaryBranchId: primary,
    ),
  );
});
