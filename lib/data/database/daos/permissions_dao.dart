part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PERMISSIONS DAO EXTENSION
// ═══════════════════════════════════════════════════════════════════════════

extension PermissionsDao on AppDatabase {
  // ─────────────────────────────────────────────────────────────────────────
  // ROLES CRUD
  // ─────────────────────────────────────────────────────────────────────────

  /// Get all roles
  Future<List<Role>> getAllRoles() {
    return (select(roles)..orderBy([(r) => OrderingTerm.asc(r.name)])).get();
  }

  /// Watch all roles
  Stream<List<Role>> watchRoles() {
    return (select(roles)..orderBy([(r) => OrderingTerm.asc(r.name)])).watch();
  }

  /// Get role by ID
  Future<Role?> getRoleById(int id) {
    return (select(roles)..where((r) => r.id.equals(id))).getSingleOrNull();
  }

  /// Insert new role
  Future<int> insertRole({
    required String name,
    String? description,
    bool isSystemRole = false,
  }) {
    return into(roles).insert(
      RolesCompanion.insert(
        name: name,
        description: Value(description),
        isSystemRole: Value(isSystemRole),
        // UUID-First Phase 1 Slice 3: stable identity so role-permission
        // links stay consistent across client/server.
        globalId: Value(UuidV7.generate()),
      ),
    );
  }

  /// Update role
  Future<bool> updateRole({
    required int id,
    required String name,
    String? description,
  }) async {
    return (update(roles)..where((r) => r.id.equals(id)))
        .write(
          RolesCompanion(name: Value(name), description: Value(description)),
        )
        .then((count) => count > 0);
  }

  /// Delete role (only non-system roles)
  Future<bool> deleteRole(int id) async {
    // Check if it's a system role
    final role = await getRoleById(id);
    if (role == null || role.isSystemRole) return false;

    // Delete role-permission mappings first
    await (delete(rolePermissions)..where((rp) => rp.roleId.equals(id))).go();

    // Delete the role
    return (delete(
      roles,
    )..where((r) => r.id.equals(id))).go().then((count) => count > 0);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PERMISSIONS CRUD
  // ─────────────────────────────────────────────────────────────────────────

  /// Get all permissions
  Future<List<Permission>> getAllPermissions() {
    return (select(permissions)..orderBy([
          (p) => OrderingTerm.asc(p.category),
          (p) => OrderingTerm.asc(p.name),
        ]))
        .get();
  }

  /// Get permissions by category
  Future<List<Permission>> getPermissionsByCategory(String category) {
    return (select(permissions)
          ..where((p) => p.category.equals(category))
          ..orderBy([(p) => OrderingTerm.asc(p.name)]))
        .get();
  }

  /// Get all permission categories
  Future<List<String>> getPermissionCategories() async {
    final allPerms = await getAllPermissions();
    return allPerms.map((p) => p.category).toSet().toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ROLE-PERMISSION MAPPINGS
  // ─────────────────────────────────────────────────────────────────────────

  /// Get permissions for a role
  Future<List<Permission>> getPermissionsForRole(int roleId) async {
    final mappings = await (select(
      rolePermissions,
    )..where((rp) => rp.roleId.equals(roleId))).get();

    final permIds = mappings.map((m) => m.permissionId).toList();
    if (permIds.isEmpty) return [];

    return (select(permissions)..where((p) => p.id.isIn(permIds))).get();
  }

  /// Check if role has permission
  Future<bool> roleHasPermission(int roleId, String permissionCode) async {
    final perm = await (select(
      permissions,
    )..where((p) => p.code.equals(permissionCode))).getSingleOrNull();
    if (perm == null) return false;

    final mapping =
        await (select(rolePermissions)..where(
              (rp) =>
                  rp.roleId.equals(roleId) & rp.permissionId.equals(perm.id),
            ))
            .getSingleOrNull();

    return mapping != null;
  }

  /// Add permission to role.
  ///
  /// Uses an explicit pre-existence check instead of `InsertMode.insertOrIgnore`
  /// because `drift_postgres` does not reliably translate that mode to an
  /// `ON CONFLICT DO NOTHING` clause for the composite (roleId, permissionId)
  /// primary key — a failed insert would abort the surrounding transaction
  /// with error 25P02.
  Future<void> addPermissionToRole(int roleId, int permissionId) async {
    final existing = await (select(rolePermissions)
          ..where((rp) =>
              rp.roleId.equals(roleId) &
              rp.permissionId.equals(permissionId)))
        .getSingleOrNull();
    if (existing != null) return;
    await into(rolePermissions).insert(
      RolePermissionsCompanion.insert(
        roleId: roleId,
        permissionId: permissionId,
      ),
    );
  }

  /// Remove permission from role
  Future<void> removePermissionFromRole(int roleId, int permissionId) async {
    await (delete(rolePermissions)..where(
          (rp) =>
              rp.roleId.equals(roleId) & rp.permissionId.equals(permissionId),
        ))
        .go();
  }

  /// أنماطُ منح الدور — معرِّفُ الصلاحية → `allow` أو `conditional`.
  ///
  /// لا يحوي إلّا الصلاحياتِ الممنوحةَ فعلاً (‏لها صفٌّ)، فالغائبُ ممنوعٌ
  /// ولا نمطَ له.
  Future<Map<int, String>> getRolePermissionModes(int roleId) async {
    final rows = await (select(
      rolePermissions,
    )..where((rp) => rp.roleId.equals(roleId))).get();
    return {for (final r in rows) r.permissionId: r.grantMode};
  }

  /// Set permissions for role (replace all)
  ///
  /// [modes] معرِّفُ الصلاحية → نمطُ المنح. وما لا مدخلَ له فيها يُكتَب
  /// `allow` — فالمُستدعي القديمُ الذي لا يعرف الأنماطَ يبقى صحيحاً.
  Future<void> setRolePermissions(
    int roleId,
    List<int> permissionIds, {
    Map<int, String>? modes,
  }) async {
    await transaction(() async {
      // Remove existing permissions
      await (delete(
        rolePermissions,
      )..where((rp) => rp.roleId.equals(roleId))).go();

      // Add new permissions
      for (final permId in permissionIds) {
        await into(rolePermissions).insert(
          RolePermissionsCompanion.insert(
            roleId: roleId,
            permissionId: permId,
            grantMode: Value(
              modes?[permId] == PermissionCodes.grantConditional
                  ? PermissionCodes.grantConditional
                  : PermissionCodes.grantAllow,
            ),
          ),
        );
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // USER PERMISSIONS
  // ─────────────────────────────────────────────────────────────────────────

  /// Only مدير النظام gets the all-permissions admin bypass.
  /// Other system roles (كاشير, مخزني, etc.) use their explicit permissions.
  bool _isAdminRole(Role role) {
    return role.isSystemRole && role.name == 'مدير النظام';
  }

  /// Check if user has permission
  Future<bool> userHasPermission(int userId, String permissionCode) async {
    final user = await (select(
      users,
    )..where((u) => u.id.equals(userId))).getSingleOrNull();
    if (user == null) {
      debugPrint('[PERM] ❌ userHasPermission($userId, $permissionCode): user NOT FOUND');
      return false;
    }

    debugPrint('[PERM] user ${user.username} roleId=${user.roleId}');

    // Check new role-based permissions
    if (user.roleId != null && user.roleId != 0) {
      // Special case: Only مدير النظام (system admin) role has all permissions
      // EXCEPT critical financial operations which require explicit assignment
      final role = await getRoleById(user.roleId!);
      debugPrint('[PERM] role lookup for roleId=${user.roleId}: ${role?.name ?? "NULL"} isSystemRole=${role?.isSystemRole}');
      if (role != null && _isAdminRole(role)) {
        // Critical financial ops require explicit permission even for system admin
        if (PermissionCodes.criticalFinancialOps.contains(permissionCode)) {
          debugPrint('[PERM] ⚠️ Critical financial op "$permissionCode" — checking explicit permission for system admin');
          return roleHasPermission(user.roleId!, permissionCode);
        }
        return true;
      }
      return roleHasPermission(user.roleId!, permissionCode);
    }

    debugPrint('[PERM] ❌ user ${user.username} has no valid roleId (${user.roleId})');
    return false;
  }

  /// Get all permissions for user
  Future<List<String>> getUserPermissionCodes(int userId) async {
    final user = await (select(
      users,
    )..where((u) => u.id.equals(userId))).getSingleOrNull();
    if (user == null) return [];

    // Check new role-based permissions
    if (user.roleId != null) {
      // Special case: Only مدير النظام (system admin) role has all permissions
      // EXCEPT critical financial operations which require explicit assignment
      final role = await getRoleById(user.roleId!);
      if (role != null && _isAdminRole(role)) {
        final allPerms = await getAllPermissions();
        // Get explicitly assigned permissions for this role
        final assignedPerms = await getPermissionsForRole(user.roleId!);
        final assignedCodes = assignedPerms.map((p) => p.code).toSet();
        // Grant all non-critical permissions automatically;
        // for critical financial ops, only include if explicitly assigned
        final grantedCodes = allPerms
            .map((p) => p.code)
            .where((code) =>
                !PermissionCodes.criticalFinancialOps.contains(code) ||
                assignedCodes.contains(code))
            .toList();
        // Add system_admin marker for PermissionGuard bypass
        //
        // ⚠️ **والمشروطُ يُعلَّم حتّى لمدير النظام**: التجاوزُ يمنحه كلَّ
        //    غيرِ الحرج تلقائيّاً، لكنّ صفّاً مسنَداً صراحةً قد يكون
        //    مشروطاً — وإسقاطُ علامته هنا يعني أنّ أخطرَ دورٍ في النظام هو
        //    الوحيدُ الذي لا يمرّ بالموافقة.
        return [
          'system_admin',
          ...grantedCodes,
          ...await _conditionalMarkers(user.roleId!),
        ];
      }

      final perms = await getPermissionsForRole(user.roleId!);
      return [
        ...perms.map((p) => p.code),
        ...await _conditionalMarkers(user.roleId!),
      ];
    }

    return [];
  }

  /// علاماتُ `cond:<code>` لصلاحيات الدور المشروطة.
  ///
  /// تُحمَل داخلَ **نفس** قائمة الأكواد لا في مزوِّدٍ ثانٍ — والسببُ مكتوبٌ
  /// عند [PermissionCodes.conditionalPrefix]: مزوِّدٌ ثانٍ يعني موضعَ إبطالٍ
  /// ثانياً في كلّ موضعٍ يُبطِل الأكواد، ونسيانُ واحدٍ يعني صلاحيةً مشروطةً
  /// تُنفَّذ بلا موافقة.
  Future<List<String>> _conditionalMarkers(int roleId) async {
    final modes = await getRolePermissionModes(roleId);
    final condIds = modes.entries
        .where((e) => e.value == PermissionCodes.grantConditional)
        .map((e) => e.key)
        .toList();
    if (condIds.isEmpty) return const [];
    final perms =
        await (select(permissions)..where((p) => p.id.isIn(condIds))).get();
    return perms.map((p) => PermissionCodes.conditionalMarker(p.code)).toList();
  }

  /// Assign role to user.
  ///
  /// Spec 061 (D1-003): refuses to change the bootstrap admin's role.
  /// Admin's role assignment is immutable.
  Future<bool> assignRoleToUser(int userId, int? roleId) async {
    if (isBootstrapAdmin(userId)) {
      // Look up admin's current role; allow no-op (same role) but block
      // any switch to a different role.
      final admin = await (select(users)..where((u) => u.id.equals(1)))
          .getSingleOrNull();
      if (admin != null && roleId != admin.roleId) {
        unawaited(DiagnosticLogger.log('ADMIN-GUARD',
            'reason=role-change caller=local-ui userId=$userId newRoleId=$roleId'));
        throw StateError(bootstrapAdminRoleGuardMessage);
      }
    }
    return (update(users)..where((u) => u.id.equals(userId)))
        .write(UsersCompanion(roleId: Value(roleId)))
        .then((count) => count > 0);
  }

  /// Update user PIN — hashed with Argon2id (B11).
  ///
  /// Was PBKDF2-SHA256 keyed on `user.passwordSalt`. That salt is shipped to
  /// every LAN bearer by `GET /api/users` alongside the PIN itself, and a PIN
  /// is only 4-6 digits — so the whole keyspace fell offline in under a
  /// second. Argon2id's PHC string carries its own random 16-byte salt, so
  /// `passwordSalt` is no longer the PIN's salt at all, and each guess now
  /// costs 4 MB + 3 passes instead of one SHA256 round.
  ///
  /// No schema change: the PHC string fits the existing nullable `pin` column.
  Future<bool> updateUserPin(int userId, String? pin) async {
    if (pin == null) {
      return (update(users)..where((u) => u.id.equals(userId)))
          .write(const UsersCompanion(pin: Value(null)))
          .then((count) => count > 0);
    }

    // Existence check kept: callers rely on `false` for an unknown user.
    final user = await (select(
      users,
    )..where((u) => u.id.equals(userId))).getSingleOrNull();
    if (user == null) return false;

    final hashedPin = await SecurityService.hashPasswordArgon2(pin);

    return (update(users)..where((u) => u.id.equals(userId)))
        .write(UsersCompanion(pin: Value(hashedPin)))
        .then((count) => count > 0);
  }

  /// Verify user PIN (Supports hashed and legacy plain-text)
  Future<bool> verifyUserPin(int userId, String pin) async {
    final user = await (select(
      users,
    )..where((u) => u.id.equals(userId))).getSingleOrNull();
    if (user == null || user.pin == null) return false;

    // Handle legacy plain-text PINs
    if (SecurityService.isLegacyPin(user.pin)) {
      // PIR-09: Log warning for audit trail — plaintext PIN should have been migrated at startup
      debugPrint('[SECURITY_AUDIT] Legacy plaintext PIN detected for user $userId — auto-migrating');
      if (user.pin == pin) {
        // Auto-migrate to secure hash on success
        await updateUserPin(userId, pin);
        return true;
      }
      return false;
    }

    // Argon2id (new) or PBKDF2-SHA256 (legacy) — verifyPasswordFull dispatches
    // on the stored hash's own format. Legacy hashes still arrive over sync
    // from servers that have not been upgraded yet, so they must keep working.
    final result = await SecurityService.verifyPasswordFull(
      pin,
      user.passwordSalt,
      user.pin!,
    );
    if (!result.verified) return false;

    // Transparent upgrade — only ever on a CORRECT PIN, so a wrong guess can
    // never overwrite the stored hash.
    if (result.needsRehash) {
      await updateUserPin(userId, pin);
    }
    return true;
  }

  /// PIR-09: Force-migrate ALL legacy plaintext PINs to hashed format at startup.
  /// Should be called from database_startup.dart during app initialization.
  /// This ensures no plaintext PINs persist beyond the first app launch after update.
  Future<int> migrateLegacyPlaintextPins() async {
    final allUsers = await select(users).get();
    int migratedCount = 0;

    for (final user in allUsers) {
      if (user.pin != null && SecurityService.isLegacyPin(user.pin)) {
        // B11: Argon2id, NOT the leaked-salt KDF — see updateUserPin.
        final hashedPin = await SecurityService.hashPasswordArgon2(user.pin!);
        await (update(users)..where((u) => u.id.equals(user.id))).write(
          UsersCompanion(pin: Value(hashedPin)),
        );
        migratedCount++;
        debugPrint('[PIR-09] Migrated plaintext PIN for user ${user.username} (ID: ${user.id})');
      }
    }

    if (migratedCount > 0) {
      debugPrint('[PIR-09] ✅ Migrated $migratedCount legacy plaintext PINs to secure hash');
    }
    return migratedCount;
  }

  /// Lock/Unlock user.
  ///
  /// Spec 061 (D1-003): refuses to lock the bootstrap admin row.
  /// Unlocking (`isLocked=false`) is always allowed.
  Future<bool> setUserLocked(int userId, bool isLocked) async {
    if (isBootstrapAdmin(userId) && isLocked) {
      unawaited(DiagnosticLogger.log(
          'ADMIN-GUARD', 'reason=lock caller=local-ui userId=$userId'));
      throw StateError(bootstrapAdminGuardMessage);
    }
    return (update(users)..where((u) => u.id.equals(userId)))
        .write(UsersCompanion(isLocked: Value(isLocked)))
        .then((count) => count > 0);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // RUNTIME PERMISSION SYNC (beforeOpen)
  // ─────────────────────────────────────────────────────────────────────────

  /// Ensures ALL permission codes from [PermissionCodes.masterList] exist in
  /// the database. Runs at every app startup via `beforeOpen`.
  /// Uses explicit pre-existence checks (NOT `InsertMode.insertOrIgnore`)
  /// because `drift_postgres` does not reliably translate insertOrIgnore to
  /// `ON CONFLICT DO NOTHING` for every case — a failed insert would abort
  /// the enclosing transaction with a 25P02 cascade error.
  /// Also auto-assigns any newly added permissions to the admin role.
  Future<void> syncAllPermissions() async {
    final masterList = PermissionCodes.masterList;

    // Get existing codes for fast lookup
    final existingPerms = await getAllPermissions();
    final existingCodes = existingPerms.map((p) => p.code).toSet();
    final posCount = masterList.where((p) => p['category'] == 'pos').length;
    debugPrint(
      '[PERM_DEBUG] masterList total: ${masterList.length}, POS count: $posCount, existing in DB: ${existingPerms.length}, existing POS: ${existingPerms.where((p) => p.code.startsWith("pos_") || p.code == "view_daily_closing_details").length}',
    );

    // Track newly inserted permission codes
    final newPermCodes = <String>[];

    for (final perm in masterList) {
      if (existingCodes.contains(perm['code'])) continue;
      // Raw SQL with `ON CONFLICT (code) DO NOTHING` is required because
      // this method runs inside a deferred `Future.microtask` scheduled by
      // `beforeOpen` Phase 4 and can race with the Setup Wizard's call to
      // `seedInitialDataPostgresAtomic()`. Both paths pre-check, both see
      // the row missing, both try to INSERT — one wins, the other hits
      // `23505 permissions_code_key` and aborts the whole transaction.
      // `ON CONFLICT DO NOTHING` makes the INSERT safe under any race.
      await customStatement(
        'INSERT INTO permissions (code, name, category) VALUES (?, ?, ?) '
        'ON CONFLICT (code) DO NOTHING',
        [perm['code']!, perm['name']!, perm['category']!],
      );
      newPermCodes.add(perm['code']!);
    }

    // Auto-assign new permissions to the admin role (مدير النظام)
    //
    // `roles` has NO unique constraint on `name` (only PK(id) + UNIQUE(global_id)),
    // so duplicate role names are a legal state on both dialects — and the seeder
    // can produce them, because it mints a fresh globalId per call so its
    // `insertOrIgnore` has no constraint to conflict against. Without `limit(1)`
    // this is `getSingleOrNull` → `list.single` → StateError, and the caller
    // swallows it, so new permission codes silently never reach admin.
    // Ordered by id so the survivor is deterministically the original row.
    final adminRole = await (select(roles)
          ..where((r) => r.name.equals('مدير النظام'))
          ..orderBy([(r) => OrderingTerm.asc(r.id)])
          ..limit(1))
        .getSingleOrNull();
    if (adminRole != null) {
      // Build the set of (roleId, permissionId) pairs admin already has so we
      // can skip existing entries explicitly rather than relying on
      // `insertOrIgnore`, which misbehaves on PostgreSQL.
      final existingRolePerms = await getPermissionsForRole(adminRole.id);
      final existingRolePermIds = existingRolePerms.map((p) => p.id).toSet();
      final allPerms = await getAllPermissions();

      for (final p in allPerms) {
        if (existingRolePermIds.contains(p.id)) continue;
        // 062 (D1-004): segregation of duties — admin must not auto-receive
        // criticalFinancialOps codes. Operator must explicitly assign each.
        // Existing installs that already granted these are unaffected
        // (existingRolePermIds skip already-granted rows).
        if (PermissionCodes.criticalFinancialOps.contains(p.code)) {
          continue;
        }
        // Bare `ON CONFLICT DO NOTHING` (no target). Targeting the
        // composite PK raised 42P10 on some PG installs where the PK
        // was not emitted exactly as drift_postgres expected. Bare form
        // matches ANY constraint and is supported on both PG and SQLite 3.24+.
        await customStatement(
          'INSERT INTO role_permissions (role_id, permission_id) VALUES (?, ?) '
          'ON CONFLICT DO NOTHING',
          [adminRole.id, p.id],
        );
        existingRolePermIds.add(p.id); // keep local view in sync
      }
    }

    if (kDebugMode && newPermCodes.isNotEmpty) {
      debugPrint(
        '🔒 Permission sync: added ${newPermCodes.length} new permissions',
      );
    }
  }
}
