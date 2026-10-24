// ApiDataHandler - users and roles admin endpoints.
part of '../api_data_handler.dart';

/// User and role admin endpoints of [ApiDataHandler].
extension ApiDataUsersRolesRoutes on ApiDataHandler {
  // ═══════════════════════════════════════════════════════════════
  // Users (Admin CRUD)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postUser(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.usersManage);
      if (perm != null) return perm;
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;

      // UUID-First (Phase 1): idempotent lookup by globalId.
      final incomingGlobalId = data['globalId'] as String?;
      if (incomingGlobalId != null && incomingGlobalId.isNotEmpty) {
        final existing = await (db.select(db.users)
              ..where((u) => u.globalId.equals(incomingGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          return jsonResponse(
              {'success': true, 'id': existing.id, 'duplicate': true});
        }
      }

      final id = await db.createUser(
        username: data['username'] as String,
        password: data['password'] as String,
        displayName: data['displayName'] as String,
        roleId: parseIntNullable(data['roleId']),
        maxDiscountPercent: parseDoubleNullable(data['maxDiscountPercent']),
        discountLimitIsPercent: parseBool(data['discountLimitIsPercent'], true),
        cardCode: data['cardCode'] as String?,
        defaultScreen: data['defaultScreen'] as String?,
        forcePasswordChange: parseBool(data['forcePasswordChange'], false),
        globalId: incomingGlobalId,
      );
      
      final dynamic branchIdsList = data['branchIds'];
      if (branchIdsList is List && branchIdsList.isNotEmpty) {
        await db.setUserBranchAccess(id, branchIdsList.cast<int>());
        broadcast('user_branch_access'); // Notify clients to pull access table
      }

      final dynamic warehouseIdsList = data['warehouseIds'];
      if (warehouseIdsList is List && warehouseIdsList.isNotEmpty) {
        await db.setUserWarehouseAccess(id, warehouseIdsList.cast<int>());
        broadcast('user_warehouse_access'); // Notify clients to pull access table
      }

      broadcast('users');
      return jsonResponse({'success': true, 'id': id});
    } catch (e) {
      debugPrint('[API] postUser error: $e');
      return ApiErrors.fail(e, 'Failed to create user');
    }
  }

  Future<Response> putUser(Request request, String id) async {
    try {
      // 060 (D1-001): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.usersManage);
      if (perm != null) return perm;

      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      final userId = int.parse(id);

      // Spec 061 (D1-002): guard the bootstrap admin row from demotion /
      // deactivation / lock. Other fields (displayName, username, cardCode,
      // maxDiscount, branchIds, warehouseIds) stay editable.
      final existing = await (db.select(db.users)
            ..where((u) => u.id.equals(userId)))
          .getSingleOrNull();
      if (existing != null &&
          isBootstrapAdmin(userId, username: existing.username)) {
        final caller =
            request.headers['x-forwarded-for'] ?? request.headers['host'] ?? 'unknown';
        if (data.containsKey('roleId')) {
          final newRoleId = parseIntNullable(data['roleId']);
          if (newRoleId != null && newRoleId != existing.roleId) {
            unawaited(DiagnosticLogger.log('ADMIN-GUARD',
                'reason=role-change caller=$caller userId=$userId newRoleId=$newRoleId'));
            return errorResponse(bootstrapAdminRoleGuardMessage,
                statusCode: 403);
          }
        }
        if (data.containsKey('isActive') && parseBool(data['isActive']) == false) {
          unawaited(DiagnosticLogger.log('ADMIN-GUARD',
              'reason=disable caller=$caller userId=$userId'));
          return errorResponse(bootstrapAdminGuardMessage, statusCode: 403);
        }
        if (data.containsKey('isLocked') && parseBool(data['isLocked']) == true) {
          unawaited(DiagnosticLogger.log('ADMIN-GUARD',
              'reason=lock caller=$caller userId=$userId'));
          return errorResponse(bootstrapAdminGuardMessage, statusCode: 403);
        }
      }

      // RESET-001: a password in the body used to be IGNORED while the call
      // answered success. It is applied here, under the same users_manage gate
      // as POST /api/users/<id>/password; a refusal answers honestly and leaves
      // the row untouched. forcePasswordChange (set AFTER the password, since
      // a password write clears it) propagates the forced-change flag.
      final reset = await _applyPasswordReset(userId, data);
      if (reset != null) return reset;

      final companion = UsersCompanion(
        roleId: data.containsKey('roleId')
            ? Value(parseIntNullable(data['roleId']))
            : const Value.absent(),
        defaultScreen: data.containsKey('defaultScreen')
            ? Value(data['defaultScreen'] as String)
            : const Value.absent(),
        maxDiscountPercent: data.containsKey('maxDiscountPercent')
            ? Value(parseDoubleNullable(data['maxDiscountPercent']))
            : const Value.absent(),
        isActive: data.containsKey('isActive')
            ? Value(parseBool(data['isActive']))
            : const Value.absent(),
        isLocked: data.containsKey('isLocked')
            ? Value(parseBool(data['isLocked']))
            : const Value.absent(),
        displayName: data.containsKey('displayName')
            ? Value(data['displayName'] as String)
            : const Value.absent(),
        forcePasswordChange: data.containsKey('forcePasswordChange')
            ? Value(parseBool(data['forcePasswordChange']))
            : const Value.absent(),
        // Issue 7 (Feature 018): admins can rename a user (display_name +
        // username) and reassign their MSR card from the edit dialog.
        username: data.containsKey('username')
            ? Value(data['username'] as String)
            : const Value.absent(),
        cardCode: data.containsKey('cardCode')
            ? Value(data['cardCode'] as String?)
            : const Value.absent(),
      );
      await (db.update(db.users)..where((u) => u.id.equals(userId)))
          .write(companion);
      WebSessionGuard.userChanged(
        userId,
        revokeSessions: (data.containsKey('isActive') &&
                parseBool(data['isActive']) == false) ||
            (data.containsKey('isLocked') && parseBool(data['isLocked']) == true),
      );

      if (data.containsKey('branchIds')) {
        final dynamic branchIdsList = data['branchIds'];
        if (branchIdsList is List) {
          await db.setUserBranchAccess(userId, branchIdsList.cast<int>());
          broadcast('user_branch_access'); // Notify clients to pull access table
        }
      }

      if (data.containsKey('warehouseIds')) {
        final dynamic warehouseIdsList = data['warehouseIds'];
        if (warehouseIdsList is List) {
          await db.setUserWarehouseAccess(userId, warehouseIdsList.cast<int>());
          broadcast('user_warehouse_access'); // Notify clients to pull access table
        }
      }

      broadcast('users');
      return jsonResponse({'success': true});
    } catch (e) {
      debugPrint('[API] putUser error: $e');
      return ApiErrors.fail(e, 'Failed to update user');
    }
  }

  /// DELETE /api/users/`<id>` — soft-delete a user account.
  ///
  /// We don't hard-delete because users are referenced from many places
  /// (invoices, journal entries, activity logs). A hard DELETE would
  /// cascade-delete those records or fail on FK constraints. Instead we
  /// mark the user as `isActive=false` and `isLocked=true`, which has the
  /// same end-user effect: they can't log in, they're hidden from pickers,
  /// and existing transactions still reference them by ID.
  ///
  /// The client should refresh its user list after this call to hide the
  /// deleted user from the management UI.
  Future<Response> deleteUser(Request request, String id) async {
    try {
      // 060 (D1-001): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.usersManage);
      if (perm != null) return perm;

      final userId = int.parse(id);
      // Protect the super admin from accidental deletion.
      final existing = await (db.select(db.users)
            ..where((u) => u.id.equals(userId)))
          .getSingleOrNull();
      if (existing == null) {
        return errorResponse('User not found', statusCode: 404);
      }
      // Spec 061 (D1-002): refuse to delete the bootstrap admin row. The
      // predicate covers BOTH id==1 AND username=='admin' so a renamed
      // username (or shifted id, if a future migration changed seeding)
      // can't bypass the protection.
      if (isBootstrapAdmin(userId, username: existing.username)) {
        final caller =
            request.headers['x-forwarded-for'] ?? request.headers['host'] ?? 'unknown';
        unawaited(DiagnosticLogger.log('ADMIN-GUARD',
            'reason=delete caller=$caller userId=$userId'));
        return errorResponse(bootstrapAdminGuardMessage, statusCode: 403);
      }
      await (db.update(db.users)..where((u) => u.id.equals(userId))).write(
        const UsersCompanion(
          isActive: Value(false),
          isLocked: Value(true),
        ),
      );
      WebSessionGuard.userChanged(userId, revokeSessions: true);
      broadcast('users');
      broadcastRecordDeleted('users', userId);
      return jsonResponse({'success': true, 'soft_deleted': userId});
    } catch (e) {
      debugPrint('[API] deleteUser error: $e');
      return ApiErrors.fail(e, 'Failed to delete user');
    }
  }

  Future<Response> postUserPassword(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.usersManage);
      if (perm != null) return perm;
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      if (data['password'] is! String || (data['password'] as String).isEmpty) {
        return _passwordFail(400, 'password required', 'invalid_request');
      }
      final reset = await _applyPasswordReset(int.parse(id), data);
      if (reset != null) return reset;
      broadcast('users');
      return jsonResponse({'success': true});
    } catch (e) {
      debugPrint('[API] postUserPassword error: $e');
      return ApiErrors.fail(e, 'Failed to update password');
    }
  }

  Response _passwordFail(int status, String error, String code) =>
      jsonResponse({'error': error, 'code': code}, statusCode: status);

  /// Applies `password` (and then `forcePasswordChange`) from an ADMIN request
  /// body to user [userId]; `null` = nothing to refuse (also when the body has
  /// no `password`). Revokes the user's sessions after a real password change.
  Future<Response?> _applyPasswordReset(
      int userId, Map<String, dynamic> data) async {
    if (!data.containsKey('password')) return null;
    final password = data['password'];
    if (password is! String || password.isEmpty) {
      return _passwordFail(400, 'password must be a non-empty string', 'invalid_request');
    }
    try {
      await db.updateUserPassword(userId: userId, newPassword: password);
    } on DuplicatePasswordException {
      return _passwordFail(409, 'password rejected', 'password_rejected');
    }
    if (data.containsKey('forcePasswordChange') && parseBool(data['forcePasswordChange'])) {
      await (db.update(db.users)..where((u) => u.id.equals(userId))).write(
          const UsersCompanion(forcePasswordChange: Value(true)));
    }
    WebSessionGuard.userChanged(userId, revokeSessions: true);
    return null;
  }

  Future<Response> postUserPin(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.usersManage);
      if (perm != null) return perm;
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      await db.updateUserPin(int.parse(id), data['pin'] as String?);
      broadcast('users');
      return jsonResponse({'success': true});
    } catch (e) {
      debugPrint('[API] postUserPin error: $e');
      return ApiErrors.fail(e, 'Failed to update PIN');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Roles (Admin CRUD)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> createRole(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.rolesManage);
      if (perm != null) return perm;
      final data = json.decode(await request.readAsString()) as Map<String, dynamic>;
      final name = (data['name'] as String?)?.trim();
      if (name == null || name.isEmpty) {
        return errorResponse('اسم الدور مطلوب', statusCode: 400);
      }
      final id = await db.insertRole(
        name: name,
        description: data['description'] as String?,
        isSystemRole: parseBool(data['isSystemRole'], false),
      );
      broadcast('roles');
      return jsonResponse({'id': id, 'success': true});
    } catch (e) {
      debugPrint('[API] createRole error: $e');
      return ApiErrors.fail(e, 'Failed to create role');
    }
  }

  /// Set permissions for a role (called by client nodes).
  Future<Response> setRolePermissions(Request request, String id) async {
    try {
      // 060 (D1-001): per-user permission gate. Highest-risk write —
      // setting role permissions is the privilege-escalation path.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.rolesManage);
      if (perm != null) return perm;

      final roleId = int.parse(id);
      final data = json.decode(await request.readAsString()) as Map<String, dynamic>;
      final codes = (data['permissionCodes'] as List).cast<String>();

      // Spec 136 ISS-15: resolve the role by globalId first. A role created on
      // a mirror/client lives only in that node's local db (insertRole never
      // pushes), so the server may know it by neither the drifted local id nor
      // its globalId — without this, db.setRolePermissions throws FK 23503
      // (role_permissions_role_id_fkey). resolveRoleId creates a placeholder
      // preserving the UUID so the link resolves and DeltaPull reconciles later.
      final resolvedRoleId = await resolveRoleId(
            clientRoleId: roleId,
            roleGlobalId: data['roleGlobalId'] as String?,
            fallbackName: data['roleName'] as String?,
          ) ??
          roleId;

      // Spec 061 (D1-002): if the target role is the bootstrap admin's role,
      // refuse any payload that does NOT include the two minimal recovery
      // codes (rolesManage + usersManage). Otherwise a paired client with the
      // API token could POST `[]` and brick the system.
      final admin = await (db.select(db.users)..where((u) => u.id.equals(1)))
          .getSingleOrNull();
      if (admin != null && admin.roleId == resolvedRoleId) {
        if (!codes.contains('rolesManage') || !codes.contains('usersManage')) {
          final caller =
              request.headers['x-forwarded-for'] ?? request.headers['host'] ?? 'unknown';
          unawaited(DiagnosticLogger.log('ADMIN-GUARD',
              'reason=strip-permissions caller=$caller roleId=$roleId codes=${codes.length}'));
          return errorResponse(
              bootstrapAdminRolePermissionsGuardMessage,
              statusCode: 403);
        }
      }

      // Resolve permission codes → IDs
      final allPerms = await db.getAllPermissions();
      final codeToId = <String, int>{
        for (final p in allPerms) p.code: p.id,
      };
      final permIds = <int>[];
      for (final code in codes) {
        final pid = codeToId[code];
        if (pid != null) permIds.add(pid);
      }

      await db.setRolePermissions(resolvedRoleId, permIds);
      broadcast('role_permissions');
      return jsonResponse({'success': true});
    } catch (e) {
      debugPrint('[API] setRolePermissions error: $e');
      return ApiErrors.fail(e, 'Failed to set role permissions');
    }
  }
}
