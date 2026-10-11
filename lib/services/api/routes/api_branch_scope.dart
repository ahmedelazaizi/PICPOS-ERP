// ApiHandler - branch scope resolution (fail-closed sentinel + helpers).
part of '../api_handler.dart';

/// Spec 151 residual #2 (D-06 fail-open) — impossible branch id used as a
/// fail-CLOSED sentinel. A mis-provisioned (non-privileged, zero-assignment)
/// user, and any branch that resolves to no warehouses/safes, are scoped to
/// this so `col IN (-1)` matches nothing instead of leaking every row.
const int _kNoBranchAccess = -1;

/// آخر عدد **سُجِّل** لكل جدول — خانق السجلّ لعدّاد `[BRANCH-SCOPE-NULL]`.
///
/// القاعدة: نكتب سطراً فقط حين **يتغيّر** العدد عن آخر ما سُجِّل لهذا
/// الجدول. السبب: DeltaPull يسحب بلا توقّف، فسطر لكل سحب لكل جدول يغرق
/// الملف بآلاف السطور المتطابقة ويُتلف المراجعة نفسها التي وُجد السجلّ
/// من أجلها. الاستقرار ⇒ سطر واحد، لا آلاف.
///
/// الغياب من الخريطة يعني «لم يُقَس بعد» لا «صفر»، فتعرّض جديد حقيقي
/// (٠ ⇒ N) يُنتج سطراً دائماً ولا يبتلعه الخانق؛ والانخفاض إلى صفر بعد
/// تعرّض سابق يُسجَّل أيضاً حتى يظهر أثر التنظيف في نفس الملف.
///
/// المراجعة النهائية / FR-3 — **وأول قياس بصفر يُسجَّل أيضاً**. كان
/// مشروطاً بـ`nullRows > 0`، فغياب السطر بعد أسبوع تشغيل يعني «نظيف» أو
/// «لم يُقَس بلا حصر قط» ولا سبيل للمالك للتفريق. العدّاد وُجد ليُبنى عليه
/// قرار تشديد بالأرقام، والمواصفة §٦ تقول حرفياً إن صفر سطور ليس دليلاً.
/// الخانق باقٍ: الاستقرار على نفس العدد ⇒ لا سطر جديد.
final Map<String, int> _lastLoggedNullBranchRows = <String, int>{};

/// Branch-scope helpers (see [ApiHandler]).
extension ApiHandlerBranchScope on ApiHandler {
  // ═══════════════════════════════════════════════════════════════
  // Branch Scope Helpers
  // ═══════════════════════════════════════════════════════════════

  /// Raw parse of `?branch_id=` (unchanged behavior, kept private).
  /// Spec 151 D-06 — split out of the old `_extractBranchId` so the async
  /// clamp below can reuse the pure query-param read.
  int? _rawBranchId(Request request) {
    final param = request.requestedUri.queryParameters['branch_id'];
    if (param == null || param.isEmpty) return null;
    return int.tryParse(param);
  }

  /// Spec 151 D-06 — resolve the EFFECTIVE branch scope for a read request,
  /// binding the client-supplied `?branch_id=` to the CALLING USER's
  /// accessible branches (server-side). Stops a per-branch client from
  /// reading another branch by passing a foreign branch_id.
  ///
  /// - No verified session identity (token absent) → requested honored. This
  ///   path is REQUIRED by the tokenless sync machinery: `ClientFirstSyncService`
  ///   and the boot-time delta pull run BEFORE any user logs in and must read
  ///   the full master + transaction set to seed/replicate the local DB. Since
  ///   they carry no session token, fail-closing here would brick new-client
  ///   provisioning and silently poison delta watermarks. See below.
  /// - Full-access user (admin / financial-manager / userId==1 → allowed==[])
  ///   → requested honored (null = all branches).
  /// - Restricted user: requested ∈ allowed → honored; null or foreign
  ///   → clamp to the user's home branch (getUserBranchId, else allowed.first).
  ///   Never returns a branch outside `allowed`.
  ///
  /// Spec 151 (P1-8): the FORGERY/IMPERSONATION vector is CLOSED — `userId` is
  /// derived server-side from an HMAC-signed session token bound to a credential
  /// check ([ApiSessionToken]), so a holder of the shared bearer can no longer
  /// forge `uid=1` (admin) nor assert any other user's identity to bypass the
  /// clamp. A legit restricted user always sends a valid token → is clamped to
  /// their branches.
  ///
  /// RESIDUAL (deferred, documented): a bearer holder that OMITS the session
  /// token gets `requested` (broad reads) — the pre-existing "shared bearer =
  /// read trust" model. Closing omission for transactional reads requires an
  /// AUTHENTICATED-SYNC redesign (a device/service session minted at pairing,
  /// persisted for boot, and threaded through ClientFirstSyncService /
  /// SyncService._fetchJson / DeltaPull) so the sync path is never tokenless —
  /// otherwise fail-closing here breaks provisioning. Tracked as the P1-8
  /// follow-up; compensating controls: trusted LAN, TLS, guarded bearer token.
  Future<int?> _extractBranchId(Request request,
      {bool failClosedOnNoIdentity = false}) async {
    final scope = await _resolveBranchScope(request,
        failClosedOnNoIdentity: failClosedOnNoIdentity);
    // The head of the list is always the value the pre-FR-1 single-branch
    // resolution produced (the honoured request, the sentinel, or the clamped
    // home). Every single-branch caller therefore behaves EXACTLY as before;
    // only `/api/sync/pull`, which consumes the whole list, widens.
    return scope?.first;
  }

  /// المراجعة النهائية / FR-1 — النطاق **الكامل** لمستدعي القراءة، لا قيمة
  /// واحدة. `null` تعني «بلا حصر»؛ `[-1]` تعني «صفر صفوف».
  ///
  /// الفرق الوحيد عن [_extractBranchId]: مستدعٍ **لا يرسل `branch_id`** ومعه
  /// أكثر من فرع مسموح يُعيد فروعه كلها بدل أن يُقصّ على فرع واحد.
  ///
  /// هذا هو مسار **المرآة** بالضبط: `_branchScopeQueryParam` يعفيها فلا ترسل
  /// المُعامل، و«مدير فروع» عليها ليس `isFullBranchAccessUser`، فكان الخادم
  /// يقصّه على فرعه الأصلي؛ ومعه توكن جلسة فـ`shouldWithholdWatermark` كاذبة
  /// ⇒ العلامة المائية تتقدّم فوق استجابة مقصوصة وبقية فروعه تتجمّد بصمت.
  ///
  /// ⚠️ ثلاثة مسارات **لا** تتّسع هنا، وكلٌّ منها حدّ قائم بذاته:
  ///  * انعدام الهوية مع `failClosedOnNoIdentity` ⇒ السنتينل `-1` قبل أي
  ///    استعلام عن الفروع (Spec 151 P1-8b) — الاتّساع لا يلمسه إطلاقاً.
  ///  * جهاز العميل يرسل `branch_id` دائماً (`server_proxy:1738-1745` يرسل
  ///    السنتينل حتى حين لا يكون مربوطاً)، فـ`requested != null` وسلوكه
  ///    كما كان بلا حرف واحد يتغيّر.
  ///  * طلب فرع **خارج** النطاق يظل مقصوصاً على فرع واحد: من طلب فرعاً
  ///    بعينه لا يُكافأ بالنطاق كاملاً.
  Future<List<int>?> _resolveBranchScope(Request request,
      {bool failClosedOnNoIdentity = false}) async {
    final requested = _rawBranchId(request);
    final userId = ApiUserCtx.userIdOf(request);
    if (userId == null) {
      // Spec 151 P1-8b: TRANSACTIONAL endpoints pass failClosedOnNoIdentity:true
      // → no verified identity yields the impossible sentinel (zero rows),
      // closing the omission vector. REFERENCE endpoints keep the default
      // (false) → honor `requested`, because the tokenless provisioning path
      // (ClientFirstSyncService / boot delta-pull, pre-login) must read shared
      // master data to seed a new client — fail-closing it would brick setup.
      if (failClosedOnNoIdentity) return const <int>[_kNoBranchAccess];
      return requested == null ? null : <int>[requested];
    }
    final allowed = await _db.getUserAccessibleBranchIds(userId);
    if (allowed.isEmpty) {
      // Spec 151 residual #2 (D-06 fail-open): an empty list is ambiguous — it
      // means full access for a privileged user, but "no assignment" for a
      // mis-provisioned non-privileged user. Split so the latter fails CLOSED
      // (scoped to the impossible sentinel) instead of reading every branch.
      if (await _db.isFullBranchAccessUser(userId)) {
        // (a) privileged → full access (null = all branches)
        return requested == null ? null : <int>[requested];
      }
      return const <int>[_kNoBranchAccess]; // (b) mis-provisioned → empty scope
    }
    if (requested != null && allowed.contains(requested)) {
      return <int>[requested];
    }
    final home = await _db.getUserBranchId(userId); // clamp foreign/null to home
    final clamped =
        (home != null && allowed.contains(home)) ? home : allowed.first;
    if (requested != null || allowed.length == 1) return <int>[clamped];
    // FR-1 — بلا طلب صريح ومعه أكثر من فرع. الفرع المقصوص يتصدّر القائمة
    // عمداً: [_extractBranchId] تقرأ `first`، فيبقى كل مستدعٍ أحادي القيمة
    // على سلوكه السابق حرفياً.
    return <int>[clamped, ...allowed.where((b) => b != clamped)];
  }

  /// Resolve branch → warehouse IDs from database.
  Future<List<int>> _resolveBranchWarehouseIds(int branchId) async {
    final warehouses = await (_db.select(_db.warehouses)
          ..where((w) => w.branchId.equals(branchId)))
        .get();
    final ids = warehouses.map((w) => w.id).toList();
    // Spec 151 residual #2 (D-06 fail-open): every consumer guards on
    // `if (ids.isNotEmpty)` and DROPS the branch filter when the list is empty
    // (an empty list ends up meaning ALL rows). Return the sentinel so a scoped
    // read of the sentinel branch — or a real branch with no warehouses — yields
    // ZERO rows via `warehouseId IN (-1)`, never the whole table.
    return ids.isEmpty ? const [_kNoBranchAccess] : ids;
  }

  /// المرحلة ١ / G1 — مراكز تكلفة الفرع، مشتقّة **عكسياً**.
  ///
  /// `CostCenters` لا تملك `branchId` (accounting_tables.dart:107) وإضافته
  /// تتطلّب `build_runner` المتجمّد في بيئة الوكيل. لكن الربط العكسي قائم:
  /// الفرع ومخازنه وخزائنه يشير كلٌّ منها إلى مركز تكلفته. هذا نفس ما
  /// يحسبه `clientScopeProvider:47-56` على الواجهة.
  ///
  /// تُعيد مجموعة فارغة عندما لا يرتبط الفرع بأي مركز — والمستدعي يترجم
  /// ذلك إلى سنتينل «صفر صفوف»، لا إلى «بلا حصر».
  Future<List<int>> _resolveBranchCostCenterIds(int branchId) async {
    final ids = <int>{};

    final branch = await (_db.select(_db.branches)
          ..where((b) => b.id.equals(branchId)))
        .getSingleOrNull();
    if (branch?.costCenterId != null) ids.add(branch!.costCenterId!);

    final warehouses = await (_db.select(_db.warehouses)
          ..where((w) => w.branchId.equals(branchId)))
        .get();
    for (final w in warehouses) {
      if (w.costCenterId != null) ids.add(w.costCenterId!);
    }

    final safes = await (_db.select(_db.safes)
          ..where((s) => s.branchId.equals(branchId)))
        .get();
    for (final s in safes) {
      if (s.costCenterId != null) ids.add(s.costCenterId!);
    }

    return ids.toList();
  }

  /// المراجعة النهائية / FR-1 — اتّحاد مراكز تكلفة عدة فروع.
  ///
  /// `cost_centers` يسلك مسار المجموعة المشتقّة لا مسار العمود، فلو بقي على
  /// فرع واحد بينما اتّسعت `warehouses`/`safes` لكل النطاق، لرأى المستخدم
  /// مخازن ثلاثة فروع ومراكز تكلفة فرع واحد — نصف إصلاح يُنتج تقارير عرجاء.
  Future<List<int>> _resolveBranchesCostCenterIds(List<int> branchIds) async {
    final ids = <int>{};
    for (final branchId in branchIds) {
      ids.addAll(await _resolveBranchCostCenterIds(branchId));
    }
    return ids.toList();
  }

  /// Resolve branch → user IDs that have access to this branch.
  Future<List<int>> _resolveScopedUserIds(int branchId) async {
    // Spec 151 residual #2 (D-06 fail-open): the -1 sentinel means "no branch
    // access" — return it directly. Otherwise the always-added system-role users
    // below would leak admin/FM shift cash/variance to a mis-provisioned user
    // (shifts.userId IN (system ids)). With [-1], the filter matches nothing.
    if (branchId == _kNoBranchAccess) return const [_kNoBranchAccess];
    final accessibleUserIds = await (_db.select(_db.userBranchAccess)
          ..where((a) => a.branchId.equals(branchId)))
        .get();
    final userIds = accessibleUserIds.map((a) => a.userId).toSet();
    
    final systemRoles = await (_db.select(_db.roles)
          ..where((r) => r.isSystemRole.equals(true)))
        .get();
    final systemRoleIds = systemRoles.map((r) => r.id).toList();

    if (systemRoleIds.isNotEmpty) {
      final systemUsers = await (_db.select(_db.users)
            ..where((u) => u.roleId.isIn(systemRoleIds)))
          .get();
      userIds.addAll(systemUsers.map((u) => u.id));
    }
    return userIds.toList();
  }

  /// Resolve branch → safe IDs from database.
  Future<List<int>> _resolveBranchSafeIds(int branchId) async {
    final safes = await (_db.select(_db.safes)
          ..where((s) => s.branchId.equals(branchId)))
        .get();
    final ids = safes.map((s) => s.id).toList();
    // Spec 151 residual #2 (D-06 fail-open): same empty-list-drops-filter
    // hazard as _resolveBranchWarehouseIds — the sentinel keeps the scope
    // closed so `safeId IN (-1)` returns zero rows instead of every safe txn.
    return ids.isEmpty ? const [_kNoBranchAccess] : ids;
  }

}
