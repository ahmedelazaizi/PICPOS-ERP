// ApiHandler - users listing and bootstrap-admin self-heal (GET).
part of '../api_handler.dart';

/// users listing and bootstrap-admin self-heal (GET) (see [ApiHandler]).
extension ApiHandlerUserGets on ApiHandler {
  Future<Response> _getUsers(Request request) async {
    try {
      await _ensureBootstrapAdminOnce();

      // ── من يستحقُّ صفوفَ المستخدمين، ومتى تُشحَن اعتماداتُهم ────────────
      // كان `failClosedOnNoIdentity` هنا على افتراضه `false` — وحدَه بين
      // مسارات البيانات الحسّاسة (‏١٥ مساراً ماليّاً تمرّرها `true`). فمستدعٍ
      // بلا جلسةٍ ولا `branch_id` يُرجَع له النطاقُ `null`، فيسقط شرطُ الفرع
      // بالكامل ويُسلَّم **كلُّ** صفوف المستخدمين ومعها الهاشُ والملح.
      //
      // ولا يصحّ إغلاقُه بإطلاق: الدخولُ **محلّيٌّ أوّلاً**
      // (`AuthRepositoryImpl.authenticateUser` → `db.authenticateUser`) بلا
      // أيِّ ارتدادٍ إلى الخادم، فطرفيّةٌ جديدةٌ لا تدخل أصلاً قبل أن تصلها
      // الصفوفُ بهاشاتها.
      //
      // فالحارسُ **نافذةُ الاقتران** — وهي الآليّةُ نفسُها التي يُسلَّم بها
      // توكنُ الـAPI عبر `/api/health`، أي نفسُ فئةِ السرّ ونفسُ الحارس:
      // يفتحها المشغِّلُ عمداً ولوقتٍ محدود، فيُزوَّد الجهازُ الجديدُ فيها،
      // ثمّ تُغلَق فيعود المسارُ مغلقاً على من لا جلسةَ له.
      final pairingOpen = ApiAuthMiddleware.isPairingOpen;
      final hasIdentity = ApiUserCtx.userIdOf(request) != null;
      // رمزُ جلسة الويب لا يستحقّ الاعتمادات أبداً (WebSessionGuard).
      final serveCredentials = WebSessionGuard.mayServeUserCredentials(
        request,
        pairingOpen: pairingOpen,
        hasIdentity: hasIdentity,
      );

      final branchId = await _extractBranchId(
        request,
        failClosedOnNoIdentity: !pairingOpen,
      );
      final query = _db.select(_db.users);

      if (branchId != null) {
        // Spec 029 / US3 Bug A — materialize the union of allowed user
        // IDs as a Dart Set<int> instead of relying on SQL OR-of-isIn
        // semantics. Two production hypotheses motivated this rewrite:
        //   1. `userIds.toList()` could be empty when the requesting
        //      client's branch has no userBranchAccess rows for the
        //      admin; on `drift_postgres` an `id IN ()` clause is a
        //      defensive minefield (versions vary).
        //   2. `roleId.isIn(systemRoleIds)` similarly returns nothing
        //      when no role is flagged isSystemRole=true (which has
        //      been observed in the field after a corrupt sync).
        // By computing the concrete set of allowed user IDs in Dart
        // and then doing ONE `id IN (concrete-list)` against `users`,
        // we eliminate both empty-IN-list edge cases. The set ALWAYS
        // contains 1 (admin), so even an otherwise empty union still
        // returns at least the admin row.
        final accessibleUserIds = await (_db.select(_db.userBranchAccess)
              ..where((a) => a.branchId.equals(branchId)))
            .get();

        final systemRoles = await (_db.select(_db.roles)
              ..where((r) => r.isSystemRole.equals(true)))
            .get();
        final systemRoleIds = systemRoles.map((r) => r.id).toList();

        // Enumerate users whose role is a system role. We do this in
        // Dart to keep one consistent IN-list shape for the final query.
        final usersInSystemRoles = systemRoleIds.isEmpty
            ? <User>[]
            : await (_db.select(_db.users)
                  ..where((u) => u.roleId.isIn(systemRoleIds)))
                .get();

        // The bootstrap admin is NOT guaranteed to live at id=1. Since the
        // 2026-05-10 corrective patch, `_ensureBootstrapAdminOnce` inserts a
        // restored admin without forcing an id — forcing 1 is what
        // drift_postgres rejected against an already-advanced sequence. So a
        // literal `1` here is not the guarantee it looks like: an admin at
        // id≠1 that has no userBranchAccess row for this branch and whose role
        // is not flagged isSystemRole falls out of the set entirely, which is
        // Feature 011 / Issue 9 — the exact bug this materialize-set exists to
        // prevent. Resolve the row by username so the guarantee follows the
        // admin wherever it actually is, and keep the literal as a fallback
        // for the window where no admin row exists at all.
        final bootstrapAdmin = await (_db.select(_db.users)
              ..where((u) => u.username.equals('admin'))
              ..limit(1))
            .getSingleOrNull();

        final allowedIds = <int>{
          ...accessibleUserIds.map((a) => a.userId),
          ...usersInSystemRoles.map((u) => u.id),
          if (bootstrapAdmin != null) bootstrapAdmin.id,
          1, // bootstrap admin — always included (Feature 011 / Issue 9)
        };

        query.where((u) => u.id.isIn(allowedIds.toList()));
      }

      final users = await query.get();
      final jsonList = users
          .map(
            (u) => <String, dynamic>{
              'id': u.id,
              'username': u.username,
              'displayName': u.displayName,
              'roleId': u.roleId,
              'defaultScreen': u.defaultScreen,
              'isLocked': u.isLocked,
              'isActive': u.isActive,
              'maxDiscountPercent': u.maxDiscountPercent,
              'discountLimitIsPercent': u.discountLimitIsPercent,
              // cardCode = اعتمادُ دخولٍ كاملٌ (POST /api/auth/session يقبله وحده)
              // فيُعامَل كالهاش: لا يخرج إلا لعميل LAN مصادَق (مستهلكه الوحيد:
              // UserSyncStrategy لدخول البطاقة دون اتصال)، ولا لرمز ويب أبداً.
              if (serveCredentials) 'cardCode': u.cardCode,
              // Include hashed credentials so clients can authenticate
              // locally while offline. الهاش دلوقتي Argon2id (ذاكرة-صعب،
              // وملحه جوّه سلسلة الـPHC) — وده اللي بيخلّي إرساله على الشبكة
              // المحلية مقبولاً. التعليق القديم كان بيقول «PBKDF2 — safe over
              // LAN» وده **ما كانش صحيحاً**: PBKDF2 بالملح المرفَق بيتكسر رخيص.
              //
              // ⚠️ «مقبولاً» ليست «بلا حارس»: Argon2id هنا بـm=4096KB وهو
              // دون تدرّج OWASP، فالهاشُ الواصلُ إلى مهاجمٍ يُكسَر دون اتّصال.
              // فلا يُشحَن إلّا لمن يستحقّه: جلسةٌ متحقَّقة، أو جهازٌ يُقتَرن
              // في نافذةٍ فتحها المشغِّلُ عمداً. وغيرُهما يقرأ الصفَّ بلا
              // اعتماد — فتبقى قوائمُ المستخدمين تعمل ولا يخرج السرّ.
              if (serveCredentials) 'passwordHash': u.passwordHash,
              // باقٍ للتوافق مع أي هاش قديم واصل عبر المزامنة؛ لصفوف Argon2id
              // بقى بلا قيمة أمنية لأن الملح الحقيقي جوّه الـPHC.
              if (serveCredentials) 'passwordSalt': u.passwordSalt,
              // ⛔ الـPIN **مايخرجش**. ٤-٦ أرقام = ١٫١ مليون احتمال على
              //    الأكثر، فأي KDF بيتكسر offline في وقت معقول لو الهاش وصل
              //    للمهاجم. ومحدش بيصادق بالـPIN أصلاً (`verifyUserPin` بلا
              //    مُنادٍ إنتاجي)، فالحقل كان بيتبعت بلا أي مستهلك.
              //    الـPIN بقى سرّاً محلياً: بيتظبط عبر
              //    `POST /api/users/<id>/pin` وبيتحقق محلياً.
            },
          )
          .toList();
      return _json({'users': jsonList, 'count': jsonList.length});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to fetch users');
    }
  }

  /// Spec 029 / US3 Bug A — restore the bootstrap admin if missing or
  /// corrupted. Idempotent and runs at most ONCE per process lifetime
  /// (gated by `_adminSelfHealRan`). Three corruption modes are covered:
  ///
  ///   1. Row at `id=1` does not exist — INSERT a fresh admin row.
  ///   2. Row at `id=1` has `username='__dup_1_admin'` — UPDATE back
  ///      to canonical `username='admin'`. The Issue 9 chain failure
  ///      leaves the row in this state on the CLIENT side; the same
  ///      taint can flow back to a SERVER if a careless cleanup runs.
  ///   3. Row at `id=1` has `isActive=false` paired with
  ///      `username='__dup_1_admin'` — same fix as (2) plus reactivate.
  ///
  /// On a healthy install this method does no work after the first
  /// call. The `[SYNC-WARN]` line is emitted only when corruption was
  /// detected, so the diagnostic log stays clean otherwise.
  ///
  /// See specs/029-sync-regression-hardening/contracts/bug-a-admin-self-heal.md.
  Future<void> _ensureBootstrapAdminOnce() async {
    if (_adminSelfHealRan) return;
    _adminSelfHealRan = true;

    // Spec 029 / US3 Bug A — corrective patch: the original
    // implementation looked up admin by `id=1` only. On a beta server
    // where the bootstrap admin lives at a different id (e.g. id=2 —
    // observed 2026-05-10 when the PG seed sequence advanced before
    // the admin row was created), the id=1 lookup returned null,
    // `missing=true` evaluated, and we tried to INSERT with explicit
    // `id: Value(1)` — which `drift_postgres` rejected against the
    // existing autoincrement sequence on `users.id`. Every `/api/users`
    // request then failed (the exception bubbled up); clients
    // pulse-retried the endpoint, masquerading as products/inventory
    // screen lag.
    //
    // Corrected logic:
    //   1. Look up admin BY USERNAME first. If `username='admin'`
    //      exists at ANY id, no heal is needed — return.
    //   2. Otherwise check id=1 specifically for the `__dup_1_admin`
    //      rename case (Issue 9 chain failure on the client side).
    //      If found, rename it back to canonical 'admin'.
    //   3. Otherwise, INSERT a fresh admin row. Do NOT force id=1 —
    //      let the autoincrement sequence assign one. Forcing id=1
    //      is what crashed in production; the bootstrap admin's id
    //      is not load-bearing in any other code path (clients sync
    //      by username/role and the materialize-set in `_getUsers`
    //      always includes id=1 by literal — irrelevant when the row
    //      lives elsewhere because the response comes back via the
    //      `id IN (concrete-list)` clause regardless).
    //   4. The whole block is wrapped in try/catch so a worst-case
    //      failure logs a SYNC-WARN line but does NOT break
    //      `/api/users` — the materialize-set clause already pulls
    //      the (possibly different-id) admin into the response.
    try {
      final adminByName = await (_db.select(_db.users)
            ..where((u) => u.username.equals('admin'))
            ..limit(1))
          .getSingleOrNull();

      if (adminByName != null) {
        // Admin exists by username at some id. Healthy install.
        return;
      }

      final id1Row = await (_db.select(_db.users)
            ..where((u) => u.id.equals(1))
            ..limit(1))
          .getSingleOrNull();

      final renamed =
          id1Row != null && id1Row.username == '__dup_1_admin';

      if (renamed) {
        // Renamed case: preserve the existing password hash/salt;
        // only restore the username + isActive flag. The operator's
        // existing password keeps working.
        await (_db.update(_db.users)..where((u) => u.id.equals(1))).write(
          const UsersCompanion(
            username: Value('admin'),
            isActive: Value(true),
          ),
        );
        await DiagnosticLogger.log(
          'SYNC-WARN',
          'admin-self-heal triggered: renamed __dup_1_admin → admin',
        );
        return;
      }

      // Genuinely missing — INSERT without forcing an id, letting the
      // autoincrement sequence assign one. The default password is
      // 'admin' so the operator can log in and rotate.
      final salt = SecurityService.generateSalt();
      final passwordHash = await SecurityService.hashPasswordArgon2('admin');
      await _db.into(_db.users).insertOnConflictUpdate(
            UsersCompanion.insert(
              username: 'admin',
              passwordHash: passwordHash,
              passwordSalt: Value(salt),
              displayName: 'مدير النظام',
              roleId: const Value(1),
              isActive: const Value(true),
              isLocked: const Value(false),
              // S-04: known password => must be rotated at first login.
              forcePasswordChange: const Value(true),
              defaultScreen: const Value('pos'),
            ),
          );
      await DiagnosticLogger.log(
        'SYNC-WARN',
        'admin-self-heal triggered: inserted fresh admin row '
            '(autoincrement id; no explicit id=1)',
      );
    } catch (e, stack) {
      // Worst case: log + continue. The materialize-set clause in
      // `_getUsers` will still pull whatever admin row exists.
      // Without this catch a single PG failure would break every
      // `/api/users` response — that was the regression observed
      // 2026-05-10 (held_orders branch_id failure plus this one
      // double-bagged the lag).
      await DiagnosticLogger.log(
        'SYNC-WARN',
        'admin-self-heal FAILED: $e\n$stack',
      );
    }
  }

}
