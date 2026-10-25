// ═══════════════════════════════════════════════════════════════════════════
// USER DAO - User Management and Authentication Operations
// ═══════════════════════════════════════════════════════════════════════════
//
// This file contains all user-related database operations.
// ═══════════════════════════════════════════════════════════════════════════

part of '../database.dart';

/// Data class to hold user and their associated role
class UserWithRole {
  final User user;
  final Role? role;

  UserWithRole({required this.user, this.role});
}

/// تُرمى حين تُكتب كلمةُ مرورٍ يحملها سلفاً مستخدمٌ **نشطٌ غيرُ مقفول**.
///
/// المنعُ عند الكتابة لا عند القراءة، لأن القراءة لا تملك علاجاً:
/// [AppDatabase.authenticateByPasswordOrCard] يرجع **أوّلَ** من يتحقّق هاشُه
/// بلا `orderBy`، فالثاني لا يصادق إطلاقاً، وحوارُ موافقة المدير ينسب
/// الموافقةَ لغير صاحبها. راجع
/// `test/unit/duplicate_password_blocked_test.dart` للسبب كاملاً.
class DuplicatePasswordException implements Exception {
  const DuplicatePasswordException(this.conflictingUsername);

  /// اسمُ المستخدم الذي يحمل الكلمةَ سلفاً. المسارُ إداريٌّ محضٌ خلف صلاحيات
  /// إدارة المستخدمين — ومن يستطيع إنشاءَ مستخدمٍ يرى قائمةَ المستخدمين
  /// كلَّها أصلاً، فالتسميةُ لا تكشف ما هو محجوب، وبدونها لا يعرف المديرُ
  /// أيَّ كلمةٍ يبدّل.
  final String conflictingUsername;

  @override
  String toString() =>
      'كلمةُ المرور هذه مستعملةٌ سلفاً للمستخدم «$conflictingUsername». '
      'اختر كلمةً مختلفة — كلمتان متطابقتان تمنعان أحدَ صاحبَيهما من '
      'الدخول وتنسبان موافقاتِ المدير لغير صاحبها.';
}

/// Spec 151 P1-8b — constant-time-ish user-enumeration defense.
///
/// A fixed, valid Argon2id PHC string used ONLY as the target of a throwaway
/// `verifyPasswordFull` call on the "no matching user" login path. Without it,
/// a missing/inactive/locked username returns *before* the expensive Argon2id
/// key-derivation runs, while an existing username with a wrong password pays
/// the full derivation cost. That timing delta lets a caller enumerate valid
/// usernames. Running one dummy verify on the no-user path evens the two paths
/// out. This is NOT a real credential — its salt/hash are deterministic
/// non-secret throwaway bytes and the verify result is always discarded.
/// (SEC-010: verification derives with the m/t/p embedded below, so keep
/// them equal to SecurityService's CURRENT parameters.)
const String _dummyArgon2idPhcForTimingDefense =
    r'$argon2id$v=19$m=19456,t=2,p=1$Wd/BX+ZdcKR0osjKbW4xrQ==$yucY7iYoN/U8em4xt5hX/9+Gt0L0jYNC6T+6G84pmVc=';

/// Extension for User-related database operations
extension UserDao on AppDatabase {
  // ═══════════════════════════════════════════════════════════════════════
  // USER CRUD OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════

  /// Watch all users with their roles.
  ///
  /// HIDES soft-deleted users (those that have BOTH `isActive=false` AND
  /// `isLocked=true` — the two flags `_deleteUser()` sets together).
  /// Individually-disabled (`isActive=false`, `isLocked=false`) and
  /// individually-locked (`isActive=true`, `isLocked=true`) users are
  /// still shown so the admin can re-enable / unlock them.
  Stream<List<UserWithRole>> watchAllUsers() {
    final query = select(
      users,
    ).join([leftOuterJoin(roles, roles.id.equalsExp(users.roleId))]);
    // Exclude records that are both inactive and locked — those are deleted.
    query.where(users.isActive.equals(true) | users.isLocked.equals(false));
    query.orderBy([OrderingTerm.asc(users.displayName)]);

    return query.watch().map((rows) {
      return rows.map((row) {
        return UserWithRole(
          user: row.readTable(users),
          role: row.readTableOrNull(roles),
        );
      }).toList();
    });
  }

  /// لقطةُ المستخدمين — نظيرُ [watchAllUsers] بلا مجرى، بنفسِ الترشيح
  /// والترتيب حرفيّاً.
  ///
  /// ⚠️ **التقريرُ يريد صورةَ لحظةٍ لا بثّاً.** و`watchAllUsers().first` بديلٌ
  /// يبدو مكافئاً وليس كذلك: مجرى drift لا يستقرّ في المنطقة الوهميّة
  /// لاختبارات الودجت، فتعلّق الشاشةُ على دوّارةٍ لا تنتهي و`pumpAndSettle`
  /// تنفد مهلتُها. وقع ذلك فعلاً في «نشاط المستخدمين» وأمسكه اختبارُ
  /// التركيب وحدَه — لا التحليلُ ولا اختبارُ الوحدة.
  Future<List<UserWithRole>> getAllUsersWithRoles() async {
    final query = select(
      users,
    ).join([leftOuterJoin(roles, roles.id.equalsExp(users.roleId))]);
    query.where(users.isActive.equals(true) | users.isLocked.equals(false));
    query.orderBy([OrderingTerm.asc(users.displayName)]);

    final rows = await query.get();
    return rows
        .map((row) => UserWithRole(
              user: row.readTable(users),
              role: row.readTableOrNull(roles),
            ))
        .toList();
  }

  /// Get user by ID with role
  Future<UserWithRole?> getUserById(int id) async {
    final query = select(users).join([
      leftOuterJoin(roles, roles.id.equalsExp(users.roleId)),
    ])..where(users.id.equals(id));

    final row = await query.getSingleOrNull();
    if (row == null) return null;

    return UserWithRole(
      user: row.readTable(users),
      role: row.readTableOrNull(roles),
    );
  }

  /// Get user by username with role.
  /// Uses get() + firstOrNull to handle duplicate username rows gracefully
  /// (can happen during client/server ID divergence before sync deduplication).
  Future<UserWithRole?> getUserByUsername(String username) async {
    final query = select(users).join([
      leftOuterJoin(roles, roles.id.equalsExp(users.roleId)),
    ])..where(users.username.equals(username) & users.isActive.equals(true));

    final rows = await query.get();
    if (rows.isEmpty) return null;

    final row = rows.first;
    return UserWithRole(
      user: row.readTable(users),
      role: row.readTableOrNull(roles),
    );
  }

  /// Create a new user with secure password.
  /// [id] — if provided (server-authoritative ID from client mode), the user
  /// will be stored with that explicit ID so client and server stay in sync.
  Future<int> createUser({
    int? id,
    required String username,
    required String password,
    required String displayName,
    int? roleId,
    double? maxDiscountPercent,
    bool discountLimitIsPercent = true,
    String? cardCode,
    String? defaultScreen,
    bool forcePasswordChange = false,
    // UUID-First (Phase 1): callers on the server side (API handler) may
    // pass a client-supplied globalId so client and server rows share
    // identity after sync. If omitted, we mint a fresh v7 UUID.
    String? globalId,
  }) async {
    // ⚠️ `PIR-08` كان أزال فحصَ التفرّد وسمّاه «نمطاً أمنياً مضادّاً»، وأُعيد
    // هنا بعد قياسِ ما يكلّفه غيابُه. والحكمان لا يتناقضان: منعُ التكرار على
    // بوّابة دخولٍ عامّةٍ يكشف كلماتِ الغير، وهذا مسارٌ إداريٌّ محضٌ خلف
    // صلاحيات إدارة المستخدمين. والبديلُ عنه ليس خصوصيةً بل
    // **مصادقةٌ مكسورة**: `authenticateByPasswordOrCard` يرجع أوّلَ مطابقةٍ
    // بلا `orderBy`، فصاحبُ الكلمة المكرَّرة الثاني لا يدخل أبداً، وحوارُ
    // موافقةِ المدير يوقّع باسم الأوّل. راجع
    // `test/unit/duplicate_password_blocked_test.dart`.
    //
    // والفحصُ **قبل** الإدراج: لو أُدرج الصفُّ ثم رُمي الاستثناءُ لبقي في
    // القاعدة مستخدمٌ لا يقدر يصادق — العطبُ نفسُه الذي نمنعه.
    final clash = await _usernameHoldingPassword(password);
    if (clash != null) throw DuplicatePasswordException(clash);

    // Week-8: New users always get Argon2id hashes. The legacy passwordSalt
    // column is stored empty — Argon2id embeds the salt inside the PHC string.

    final passwordHash = await SecurityService.hashPasswordArgon2(password);
    final effectiveGlobalId =
        (globalId != null && globalId.isNotEmpty) ? globalId : UuidV7.generate();

    final newUserId = await into(users).insert(
      UsersCompanion.insert(
        username: username,
        passwordHash: passwordHash,
        displayName: displayName,
      ).copyWith(
        id: id != null ? Value(id) : const Value.absent(),
        passwordSalt: const Value(''), // salt is embedded in Argon2id PHC string
        roleId: Value(roleId),
        maxDiscountPercent: Value(maxDiscountPercent),
        discountLimitIsPercent: Value(discountLimitIsPercent),
        cardCode: Value(cardCode),
        defaultScreen: Value(defaultScreen ?? 'pos'),
        forcePasswordChange: Value(forcePasswordChange),
        globalId: Value(effectiveGlobalId),
      ),
    );

    // Feature 004 (US2, FR-009/FR-010): fire the cross-branch password
    // collision scanner asynchronously. The scanner self-gates on
    // NetworkService.isClient → no-op on paired clients; on server / standalone
    // it scans every user in branches OTHER THAN this user's branches.
    // For brand-new users the branch set is empty until setUserBranchAccess
    // runs, in which case the scanner exits early — a known minor limitation
    // documented in the implementation. The save path never blocks.
    PasswordCollisionScanner.scanAfterCreate(this, newUserId, password);

    return newUserId;
  }

  /// Update user information (not password).
  ///
  /// Issue 7 (Feature 018): added optional [username] so the edit dialog can
  /// rename a user without going through a separate code path. Pass `null`
  /// (the default) to leave it unchanged — preserves the previous contract.
  Future<void> updateUserInfo({
    required int userId,
    required String displayName,
    int? roleId,
    double? maxDiscountPercent,
    bool discountLimitIsPercent = true,
    String? cardCode,
    String? defaultScreen,
    bool? forcePasswordChange,
    String? username,
  }) async {
    // Spec 061 (D1-003): refuse role change for bootstrap admin.
    if (isBootstrapAdmin(userId) && roleId != null) {
      final admin = await (select(users)..where((u) => u.id.equals(1)))
          .getSingleOrNull();
      if (admin != null && roleId != admin.roleId) {
        unawaited(DiagnosticLogger.log('ADMIN-GUARD',
            'reason=role-change caller=local-ui userId=$userId newRoleId=$roleId'));
        throw StateError(bootstrapAdminRoleGuardMessage);
      }
    }
    await (update(users)..where((u) => u.id.equals(userId))).write(
      UsersCompanion(
        displayName: Value(displayName),
        roleId: Value(roleId),
        maxDiscountPercent: Value(maxDiscountPercent),
        discountLimitIsPercent: Value(discountLimitIsPercent),
        cardCode: Value(cardCode),
        defaultScreen: Value(defaultScreen ?? ''),
        forcePasswordChange: forcePasswordChange != null
            ? Value(forcePasswordChange)
            : const Value.absent(),
        username: username != null ? Value(username) : const Value.absent(),
      ),
    );
  }

  /// Update user password with new salt
  Future<void> updateUserPassword({
    required int userId,
    required String newPassword,
  }) async {
    // Capture the OLD hash + salt BEFORE the write, so the collision scanner
    // can perform an FR-017 self-equality check (skip the scan when the new
    // plaintext is identical to the existing password — no real change).
    final oldUser = await (select(users)..where((row) => row.id.equals(userId)))
        .getSingleOrNull();

    // نفسُ منع §١، مع استثناء صاحبِ الصفّ: بدونه يصير كلُّ حفظٍ لا يغيّر
    // الكلمةَ رفضاً — فيحبس المستخدمُ نفسَه عن تعديل اسمه أو دورِه.
    final clash =
        await _usernameHoldingPassword(newPassword, excludeUserId: userId);
    if (clash != null) throw DuplicatePasswordException(clash);

    // Week-8: All password changes now use Argon2id.
    // Legacy passwordSalt column is cleared — salt lives inside the PHC string.
    final passwordHash = await SecurityService.hashPasswordArgon2(newPassword);
    await (update(users)..where((u) => u.id.equals(userId))).write(
      UsersCompanion(
        passwordHash: Value(passwordHash),
        passwordSalt: const Value(''), // salt embedded in Argon2id PHC string
        forcePasswordChange: const Value(false),
      ),
    );

    // Feature 004 (US2): clear stale collision warnings involving this user
    // first (the old password was the source; the new one may resolve them
    // entirely), then trigger a fresh scan. The scanner self-gates on
    // NetworkService.isClient and on the FR-017 self-equality check, so
    // updates that didn't change the password produce no warning at all.
    PasswordCollisionScanner.scanAfterPasswordChange(
        this, userId, newPassword, oldUser);

    // If the operator just changed the built-in `admin` user's password,
    // raise the `admin_password_customized` sentinel so the startup
    // self-heal stops auto-resetting the hash to admin/admin on every
    // boot. Without this, a real customer-chosen password would be
    // silently reverted to the default on the next app launch.
    try {
      if (oldUser?.username == 'admin') {
        await setSetting('admin_password_customized', 'true');
      }
    } catch (_) {}
  }

  /// Toggle user active status.
  ///
  /// Spec 061 (D1-003): refuses to deactivate the bootstrap admin row.
  /// Setting `isActive=true` (re-enable) is always allowed.
  Future<void> toggleUserActive({
    required int userId,
    required bool isActive,
  }) async {
    if (isBootstrapAdmin(userId) && !isActive) {
      unawaited(DiagnosticLogger.log(
          'ADMIN-GUARD', 'reason=disable caller=local-ui userId=$userId'));
      throw StateError(bootstrapAdminGuardMessage);
    }
    await (update(users)..where((u) => u.id.equals(userId))).write(
      UsersCompanion(isActive: Value(isActive)),
    );
  }

  /// Authenticate user with username and password.
  /// Uses get() (not getSingleOrNull) to gracefully handle the rare case where
  /// client/server ID divergence leaves a duplicate username row after a fullSync.
  /// In that case, we try the password against each matching row.
  Future<UserWithRole?> authenticateUser(
    String username,
    String password,
  ) async {
    // Block login for: inactive (isActive=false), locked (isLocked=true),
    // or soft-deleted accounts. Previously only `isActive` was checked, so
    // users with `isLocked=true` could still sign in — this bypassed the
    // admin's "قفل المستخدم" action entirely.
    final query = select(users).join([
      leftOuterJoin(roles, roles.id.equalsExp(users.roleId)),
    ])..where(
        users.username.equals(username) &
            users.isActive.equals(true) &
            users.isLocked.equals(false),
      );

    final rows = await query.get();
    if (rows.isEmpty) {
      // Spec 151 P1-8b — constant-time-ish user-enumeration defense.
      // Run a DUMMY Argon2id verify so this "no matching user" path costs
      // ~the same as the wrong-password path below (which pays the full
      // key-derivation). Prevents timing-based username enumeration. The
      // result is intentionally ignored.
      await SecurityService.verifyPasswordFull(
        password,
        '',
        _dummyArgon2idPhcForTimingDefense,
      );
      debugPrint('[AUTH] authenticateUser: user "$username" not found, '
          'inactive, or locked');
      return null;
    }

    // Sort: prefer rows with non-empty passwordHash first so we try a valid hash
    rows.sort((a, b) {
      final ha = a.readTable(users).passwordHash;
      final hb = b.readTable(users).passwordHash;
      if (ha.isNotEmpty && hb.isEmpty) return -1;
      if (ha.isEmpty && hb.isNotEmpty) return 1;
      return 0;
    });

    for (final row in rows) {
      final user = row.readTable(users);
      if (kDebugMode) {
        debugPrint('[AUTH] authenticateUser: user="${user.username}" id=${user.id} '
            'isArgon2=${SecurityService.isArgon2Hash(user.passwordHash)}');
      }

      final result = await SecurityService.verifyPasswordFull(
        password,
        user.passwordSalt,
        user.passwordHash,
      );

      if (result.verified) {
        if (kDebugMode) {
          debugPrint('[AUTH] ✅ Password verified for "${user.username}" (id=${user.id})');
        }
        // Week-8: transparently rehash old PBKDF2-SHA256 hashes to Argon2id.
        // Fire-and-forget — login is not blocked by the rehash write.
        if (result.needsRehash) {
          unawaited(_rehashToArgon2(user.id, password));
          if (kDebugMode) {
            debugPrint('[AUTH] 🔄 Scheduled Argon2id rehash for "${user.username}"');
          }
        }
        return UserWithRole(user: user, role: row.readTableOrNull(roles));
      }
    }
    if (kDebugMode) {
      debugPrint('[AUTH] ❌ Password FAILED for "$username" (tried ${rows.length} row(s))');
    }
    return null;
  }

  /// PBKDF2 → Argon2id after login; never on client/mirror (the main owns the hash).
  Future<void> _rehashToArgon2(int userId, String plainPassword) async {
    if (SyncInterceptor.isClientMode) return;
    try {
      final newHash = await SecurityService.hashPasswordArgon2(plainPassword);
      await (update(users)..where((u) => u.id.equals(userId))).write(
        UsersCompanion(
          // Argon2id embeds salt in the PHC string — legacy salt column is cleared
          passwordHash: Value(newHash),
          passwordSalt: const Value(''), // no longer needed for Argon2id
        ),
      );
      if (kDebugMode) {
        debugPrint('[AUTH] ✅ Argon2id rehash complete for userId=$userId');
      }
    } catch (e) {
      // Non-fatal — user will be re-migrated on the next login
      if (kDebugMode) {
        debugPrint('[AUTH] ⚠️ Argon2id rehash failed for userId=$userId: $e');
      }
    }
  }

  /// Authenticate user by MSR card code. Respects isActive AND isLocked.
  Future<UserWithRole?> authenticateByCardCode(String cardCode) async {
    final query = select(users).join([
      leftOuterJoin(roles, roles.id.equalsExp(users.roleId)),
    ])..where(
        users.cardCode.equals(cardCode) &
            users.isActive.equals(true) &
            users.isLocked.equals(false),
      );

    final row = await query.getSingleOrNull();
    if (row == null) return null;

    return UserWithRole(
      user: row.readTable(users),
      role: row.readTableOrNull(roles),
    );
  }

  /// PIR-07: Unified authentication — tries password against all active
  /// non-locked users, then falls back to card code lookup.
  /// Replaces the old deprecated authenticateByPassword() method.
  Future<UserWithRole?> authenticateByPasswordOrCard(String input) async {
    // Step 1: Try matching password against all active, non-locked users
    final row = await _firstActiveUserVerifying(input, rehashOnMatch: true);
    if (row != null) {
      final user = row.readTable(users);
      debugPrint('[AUTH] ✅ Password matched for "${user.username}" via unified auth');
      return UserWithRole(user: user, role: row.readTableOrNull(roles));
    }

    // Step 2: Fall back to card code lookup
    debugPrint('[AUTH] Password didn\'t match any user, trying card code...');
    return authenticateByCardCode(input);
  }

  /// الحلقةُ الواحدةُ التي تجرّب نصّاً على كلّ مستخدمٍ نشطٍ غيرِ مقفول.
  ///
  /// مشتركةٌ عن قصدٍ بين المصادقة و[_usernameHoldingPassword]: **نفسُ
  /// المجموعة** هي التي تُنتج العطبَ وهي التي تُفحص. ولو انحرف الفحصُ عن
  /// المصادقة — بمُرشِّحٍ يزيد أو ينقص — لعاد التصادمُ من بابٍ لا يحرسه أحد:
  /// مستخدمٌ يُقبل إنشاؤه ثم يبتلع مصادقةَ غيره.
  ///
  /// ولا يمكن الفحصُ بمقارنة الهاش: لكلّ صفٍّ ملحُه (وArgon2id يخبّئه داخل
  /// سلسلة PHC)، فهاشا كلمتين متطابقتين مختلفان. التجريبُ واحداً واحداً هو
  /// الفحصُ الوحيدُ الممكن — وكلفتُه `n × ~40ms`.
  Future<TypedResult?> _firstActiveUserVerifying(
    String input, {
    int? excludeUserId,
    bool rehashOnMatch = false,
  }) async {
    final query = select(users).join([
      leftOuterJoin(roles, roles.id.equalsExp(users.roleId)),
    ])..where(users.isActive.equals(true) & users.isLocked.equals(false));

    for (final row in await query.get()) {
      final user = row.readTable(users);
      if (excludeUserId != null && user.id == excludeUserId) continue;
      // Week-8: support both Argon2id (new) and PBKDF2-SHA256 (legacy) hashes.
      final authResult = await SecurityService.verifyPasswordFull(
        input,
        user.passwordSalt,
        user.passwordHash,
      );
      if (authResult.verified) {
        if (rehashOnMatch && authResult.needsRehash) {
          unawaited(_rehashToArgon2(user.id, input));
        }
        return row;
      }
    }
    return null;
  }

  /// اسمُ المستخدم الذي يحمل [password] سلفاً، أو `null` إن كانت فريدة.
  Future<String?> _usernameHoldingPassword(
    String password, {
    int? excludeUserId,
  }) async {
    final row = await _firstActiveUserVerifying(
      password,
      excludeUserId: excludeUserId,
    );
    return row?.readTable(users).username;
  }

  /// Check if username exists
  Future<bool> usernameExists(String username) async {
    final user = await getUserByUsername(username);
    return user != null;
  }

  /// Get user by username (Simple)
  Future<User?> getUserByUsernameRaw(String username) async {
    final rows = await (select(users)
          ..where((u) => u.username.equals(username) & u.isActive.equals(true)))
        .get();
    return rows.isEmpty ? null : rows.first;
  }

  /// Get user by email/username and password (Raw)
  Future<User?> getUserByEmailAndPassword(String email, String password) async {
    final rows = await (select(users)
          ..where((u) => u.username.equals(email) & u.isActive.equals(true)))
        .get();
    final user = rows.isEmpty ? null : rows.first;
    if (user != null) {
      // Week-8: support both Argon2id (new) and PBKDF2-SHA256 (legacy) hashes.
      final authResult = await SecurityService.verifyPasswordFull(
        password,
        user.passwordSalt,
        user.passwordHash,
      );
      if (authResult.verified) {
        if (authResult.needsRehash) {
          unawaited(_rehashToArgon2(user.id, password));
        }
        return user;
      }
    }
    return null;
  }

  /// Get user by ID (Raw)
  Future<User?> getUserByIdRaw(int id) {
    return (select(users)..where((u) => u.id.equals(id))).getSingleOrNull();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // N3/N4: BRANCH & WAREHOUSE ACCESS CONTROL
  // ═══════════════════════════════════════════════════════════════════════

  /// Spec 151 residual #2 (D-06 fail-open) — single source of truth for the
  /// "unrestricted / all-branches" privilege rule. Returns true ONLY for the
  /// program owner (userId==1) or the system-admin / financial-manager roles.
  ///
  /// Callers use this to disambiguate the two meanings of an empty branch list
  /// from [getUserAccessibleBranchIds]: `[]` because the user is privileged
  /// (full access) vs `[]` because a non-privileged user was mis-provisioned
  /// with zero branch assignments — the latter must fail CLOSED, not open.
  Future<bool> isFullBranchAccessUser(int userId) async {
    // N4: Admin and Financial Manager bypass.
    if (userId == 1) return true;
    final user = await getUserById(userId);
    final roleName = user?.role?.name;
    return roleName == 'مدير النظام' || roleName == 'مدير مالي';
  }

  /// Get branch IDs accessible by a user.
  /// Returns empty list if user has no restrictions (= full access).
  /// Admin (userId=1) always returns empty (= full access).
  Future<List<int>> getUserAccessibleBranchIds(int userId) async {
    // N4: Admin and Financial Manager bypass — single-sourced via
    // isFullBranchAccessUser so the role rule never drifts from the sentinel
    // check in _extractBranchId (Spec 151 residual #2 (D-06 fail-open)).
    if (await isFullBranchAccessUser(userId)) return [];

    final rows = await (select(userBranchAccess)
          ..where((a) => a.userId.equals(userId)))
        .get();
    final directIds = rows.map((r) => r.branchId).toList();
    final regionBranchIds = await getBranchIdsForUserRegionAccess(userId);
    return {...directIds, ...regionBranchIds}.toList();
  }

  /// Phase 6 (T4) — raw branch assignments for a user, without the
  /// "admin / financial manager → empty list = full access" semantics
  /// baked into [getUserAccessibleBranchIds]. Used by the login gate so
  /// that a "مدير نظام" assigned to a specific branch (the user's directive
  /// "مدير نظام لهذا الفرع وليس صاحب البرنامج") is still rejected when
  /// trying to log in from another branch's device. Includes inherited
  /// access from `user_region_access` (a region grant covers all of its
  /// branches), same as the helper above.
  ///
  /// Excludes only `userId == 1` (the program owner / "صاحب البرنامج").
  /// Callers must handle the program-owner case before calling this.
  Future<List<int>> getRawUserBranchAssignments(int userId) async {
    final rows = await (select(userBranchAccess)
          ..where((a) => a.userId.equals(userId)))
        .get();
    final directIds = rows.map((r) => r.branchId).toList();
    final regionBranchIds = await getBranchIdsForUserRegionAccess(userId);
    return {...directIds, ...regionBranchIds}.toList();
  }

  /// حصر المخازن للمستخدم — بعقد **لا يخلط** «بلا حصر» بـ«بلا وصول».
  ///
  ///   `null`   ⇒ مميّز (صاحب البرنامج / مدير النظام / مدير مالي) — بلا حصر.
  ///   `{}`     ⇒ غير مميّز ومحدش خصّصله مخازن — **مفيش وصول**.
  ///   `{ids}`  ⇒ محصور على المخازن دي.
  ///
  /// ── ليه نوع جديد بدل تصليح `getUserAccessibleWarehouseIds` ────────────────
  /// القديمة بترجّع `List<int>` وتوثيقها بيقول إن الفاضية = «بلا حصر». فالقيمة
  /// الفاضية بتحمل معنيين متضادين، وأقلّ مستخدم صلاحيةً وأعلاه بياخدوا **نفس
  /// النتيجة**. النوع نفسه هنا بيفصل المعنيين، فمفيش مُنادٍ يقدر ينسى التفرقة —
  /// وده كان بالظبط نمط الفشل. نفس علاج توأم الفروع في Spec 151 Track-3.
  ///
  /// معيار الامتياز single-sourced من [isFullBranchAccessUser] عشان القاعدة
  /// ما تنحرفش بين الفروع والمخازن.
  ///
  /// ⚠️ **القرار «مفيش وصول» مش بيتنفّذ هنا** — الدالة بتقول الحقيقة بس.
  ///    مين بيفشل مقفولاً ومين لأ قرار عرض، شوف `allWarehousesProvider`.
  Future<Set<int>?> getWarehouseScopeForUser(int userId) async {
    if (await isFullBranchAccessUser(userId)) return null;

    final rows = await (select(userWarehouseAccess)
          ..where((a) => a.userId.equals(userId)))
        .get();
    return rows.map((r) => r.warehouseId).toSet();
  }

  /// Get warehouse IDs accessible by a user.
  /// Returns empty list if user has no restrictions (= full access).
  /// Admin (userId=1) always returns empty (= full access).
  Future<List<int>> getUserAccessibleWarehouseIds(int userId) async {
    // N4: Admin and Financial Manager bypass
    if (userId == 1) return [];
    final user = await getUserById(userId);
    if (user?.role?.name == 'مدير النظام' || user?.role?.name == 'مدير مالي') return [];

    final rows = await (select(userWarehouseAccess)
          ..where((a) => a.userId.equals(userId)))
        .get();
    return rows.map((r) => r.warehouseId).toList();
  }

  /// Set the branches a user can access (replaces existing)
  Future<void> setUserBranchAccess(int userId, List<int> branchIds) async {
    await transaction(() async {
      await (delete(userBranchAccess)
            ..where((a) => a.userId.equals(userId)))
          .go();
      for (final branchId in branchIds) {
        await into(userBranchAccess).insert(
          UserBranchAccessCompanion.insert(
            userId: userId,
            branchId: branchId,
          ),
        );
      }
    });
  }

  /// Set the warehouses a user can access (replaces existing)
  Future<void> setUserWarehouseAccess(int userId, List<int> warehouseIds) async {
    await transaction(() async {
      await (delete(userWarehouseAccess)
            ..where((a) => a.userId.equals(userId)))
          .go();
      for (final warehouseId in warehouseIds) {
        await into(userWarehouseAccess).insert(
          UserWarehouseAccessCompanion.insert(
            userId: userId,
            warehouseId: warehouseId,
          ),
        );
      }
    });
  }

  /// Apply a server-side sync patch to a local user row.
  ///
  /// Called from `LoginScreen` after a successful server login so the local
  /// row reflects the server's current `defaultScreen`, `roleId`, and
  /// `displayName` without leaking Drift `Companion` types into the
  /// presentation layer (Day 6A — Direct DB Access refactor).
  Future<void> applyServerSync({
    required int userId,
    required String defaultScreen,
    int? roleId,
    required String displayName,
  }) async {
    await (update(users)..where((u) => u.id.equals(userId))).write(
      UsersCompanion(
        defaultScreen: Value(defaultScreen),
        roleId: Value(roleId),
        displayName: Value(displayName),
      ),
    );
  }
}
