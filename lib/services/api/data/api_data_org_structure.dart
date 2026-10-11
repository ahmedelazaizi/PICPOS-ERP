// ApiDataHandler - warehouses, cost centers, branches and regions admin endpoints.
part of '../api_data_handler.dart';

/// Organisation-structure endpoints of [ApiDataHandler].
extension ApiDataOrgStructureRoutes on ApiDataHandler {
  // ═══════════════════════════════════════════════════════════════
  // Warehouses (Admin CRUD)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postWarehouse(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.warehousesManage);
      if (perm != null) return perm;
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;

      // UUID-First (Phase 1): idempotent lookup by globalId.
      final incomingGlobalId = data['globalId'] as String?;
      if (incomingGlobalId != null && incomingGlobalId.isNotEmpty) {
        final existing = await (db.select(db.warehouses)
              ..where((w) => w.globalId.equals(incomingGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          return jsonResponse(
              {'success': true, 'id': existing.id, 'duplicate': true});
        }
      }

      final id = await db
          .into(db.warehouses)
          .insert(
            WarehousesCompanion.insert(
              name: data['name'] as String,
              branchId: Value(parseIntNullable(data['branchId'])),
              costCenterId: Value(parseIntNullable(data['costCenterId'])),
              globalId: Value(incomingGlobalId),
            ),
          );
      broadcast('warehouses');
      return jsonResponse({'success': true, 'id': id});
    } catch (e) {
      debugPrint('[API] postWarehouse error: $e');
      return ApiErrors.fail(e, 'Failed to create warehouse');
    }
  }

  Future<Response> putWarehouse(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.warehousesManage);
      if (perm != null) return perm;
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      final warehouseId = int.parse(id);
      if (data['setDefault'] == true) {
        // Per-branch: only reset defaults within the same branch
        final wh = await (db.select(db.warehouses)..where((w) => w.id.equals(warehouseId))).getSingleOrNull();
        if (wh != null) {
          await (db.update(db.warehouses)..where((w) => w.branchId.equalsNullable(wh.branchId)))
              .write(const WarehousesCompanion(isDefault: Value(false)));
        }
        await (db.update(db.warehouses)
              ..where((w) => w.id.equals(warehouseId)))
            .write(const WarehousesCompanion(isDefault: Value(true)));
      } else if (data['unsetDefault'] == true) {
        await (db.update(db.warehouses)
              ..where((w) => w.id.equals(warehouseId)))
            .write(const WarehousesCompanion(isDefault: Value(false)));
      } else {
        await (db.update(db.warehouses)
              ..where((w) => w.id.equals(warehouseId)))
            .write(
          WarehousesCompanion(
            name: data.containsKey('name')
                ? Value(data['name'] as String)
                : const Value.absent(),
            branchId: data.containsKey('branchId')
                ? Value(parseIntNullable(data['branchId']))
                : const Value.absent(),
            costCenterId: data.containsKey('costCenterId')
                ? Value(parseIntNullable(data['costCenterId']))
                : const Value.absent(),
          ),
        );
      }
      broadcast('warehouses');
      return jsonResponse({'success': true});
    } catch (e) {
      debugPrint('[API] putWarehouse error: $e');
      return ApiErrors.fail(e, 'Failed to update warehouse');
    }
  }

  Future<Response> deleteWarehouse(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.warehousesManage);
      if (perm != null) return perm;
      final whId = int.parse(id);
      await (db.delete(db.warehouses)..where((w) => w.id.equals(whId))).go();
      broadcast('warehouses');
      broadcastRecordDeleted('warehouses', whId);
      return jsonResponse({'success': true});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to delete warehouse');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Cost Centers (Admin CRUD) — Feature 006 / MM.C
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postCostCenter(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.accountingManage);
      if (perm != null) return perm;
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;

      final incomingGlobalId = data['globalId'] as String?;
      if (incomingGlobalId != null && incomingGlobalId.isNotEmpty) {
        final existing = await (db.select(db.costCenters)
              ..where((c) => c.globalId.equals(incomingGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          return jsonResponse(
              {'success': true, 'id': existing.id, 'duplicate': true});
        }
      }

      final id = await db.createCostCenter(
        code: data['code'] as String,
        name: data['name'] as String,
        parentId: parseIntNullable(data['parentId']),
      );
      if (incomingGlobalId != null && incomingGlobalId.isNotEmpty) {
        await (db.update(db.costCenters)..where((c) => c.id.equals(id)))
            .write(CostCentersCompanion(globalId: Value(incomingGlobalId)));
      }
      broadcast('cost_centers');
      return jsonResponse({'success': true, 'id': id});
    } catch (e) {
      debugPrint('[API] postCostCenter error: $e');
      return ApiErrors.fail(e, 'Failed to create cost center');
    }
  }

  Future<Response> putCostCenter(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.accountingManage);
      if (perm != null) return perm;
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      final ccId = int.parse(id);
      await db.updateCostCenter(
        ccId,
        code: data.containsKey('code') ? data['code'] as String? : null,
        name: data.containsKey('name') ? data['name'] as String? : null,
        parentId: data.containsKey('parentId')
            ? parseIntNullable(data['parentId'])
            : null,
        isActive: data.containsKey('isActive')
            ? parseBool(data['isActive'], true)
            : null,
      );
      broadcast('cost_centers');
      return jsonResponse({'success': true});
    } catch (e) {
      debugPrint('[API] putCostCenter error: $e');
      return ApiErrors.fail(e, 'Failed to update cost center');
    }
  }

  Future<Response> deleteCostCenter(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.accountingManage);
      if (perm != null) return perm;
      final ccId = int.parse(id);
      await db.deactivateCostCenter(ccId);
      broadcast('cost_centers');
      broadcastRecordDeleted('cost_centers', ccId);
      return jsonResponse({'success': true});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to delete cost center');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Branches (Admin CRUD) — Feature 006 / MM.C
  //
  // Mirror-mode admin can create / rename / soft-deactivate branches
  // from a remote laptop. Endpoints stay UUID-First (idempotent on
  // globalId) so a retry after a network blip cannot duplicate a branch
  // on HQ.
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postBranch(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.branchesManage);
      if (perm != null) return perm;
      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'postBranch',
        tables: const {'branches'},
        body: () async {
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;

      // Tier 1 — globalId dedup (UUID-First contract). The historical
      // dedup path: a retried POST with the same globalId returns the
      // existing row instead of creating a duplicate.
      final incomingGlobalId = data['globalId'] as String?;
      if (incomingGlobalId != null && incomingGlobalId.isNotEmpty) {
        final existing = await (db.select(db.branches)
              ..where((b) => b.globalId.equals(incomingGlobalId))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          return jsonResponse(
              {'success': true, 'id': existing.id, 'duplicate': true});
        }
      }

      // Feature 011 / Issue 7+8 — name+isActive dedup.
      // Diagnostic logs from a beta restaurant showed 9 rows on the server
      // all named "الفرع الرئيسي", all with globalId=null. Root cause:
      // the legacy path skipped the globalId-dedup branch above when the
      // caller didn't supply a globalId, then inserted blindly with no
      // name check. Every client/mirror that POSTed a branch without a
      // globalId — e.g. a client first-sync echo, a default-branch
      // placeholder write — created a NEW row.
      //
      // Fix: when no incoming globalId, check by (name, is_active=true)
      // before inserting. If an active row with the same name exists,
      // return it AND backfill the globalId on the matched row so future
      // syncs hit the Tier 1 path instead of falling here repeatedly.
      final name = data['name'] as String?;
      if (name == null || name.trim().isEmpty) {
        return errorResponse('Branch name is required');
      }
      final trimmedName = name.trim();

      // Spec 136 ISS-1 — name-collision dedup. This runs whenever the Tier-1
      // globalId lookup above did NOT return early: either no gid was sent, OR
      // a gid was sent but matched no server row. Pre-fix this check was gated
      // on `incomingGlobalId == null`, so a client posting an EXISTING branch
      // name with its OWN divergent (non-null) gid skipped the check entirely
      // and fell through to the blind insert below — creating a DUPLICATE
      // "الفرع الرئيسي" row. That is the field ISS-1 root cause (the server
      // accumulating multiple main branches, then sync skipping the duplicate
      // to stay stable). Now any active row with the same name short-circuits
      // the insert regardless of the incoming gid.
      final byName = await (db.select(db.branches)
            ..where((b) =>
                b.name.equals(trimmedName) & b.isActive.equals(true))
            ..orderBy([(b) => OrderingTerm.asc(b.id)])
            ..limit(1))
          .getSingleOrNull();
      if (byName != null) {
        // Converge the matched row's gid ONLY when it is currently NULL
        // (Spec 132 FR-011 — never overwrite an existing gid; a divergent
        // non-null gid converges via the sync push-down, not here). Prefer
        // the client's incoming gid so that client's future syncs hit Tier-1;
        // otherwise mint one so the row stops falling here on every POST.
        if (byName.globalId == null || byName.globalId!.isEmpty) {
          final backfillGid =
              (incomingGlobalId != null && incomingGlobalId.isNotEmpty)
                  ? incomingGlobalId
                  : UuidV7.generate();
          await (db.update(db.branches)..where((b) => b.id.equals(byName.id)))
              .write(BranchesCompanion(globalId: Value(backfillGid)));
          debugPrint('[API] postBranch: name dedup + globalId backfill — '
              'name="$trimmedName" id=${byName.id} gid=$backfillGid '
              'incoming=$incomingGlobalId');
        } else {
          debugPrint('[API] postBranch: name dedup (no overwrite) — '
              'name="$trimmedName" id=${byName.id} '
              'existingGlobalId=${byName.globalId} incoming=$incomingGlobalId');
        }
        return jsonResponse(
            {'success': true, 'id': byName.id, 'duplicate': true});
      }

      // No dedup hit — create a new branch. Always mint a globalId
      // server-side if the caller didn't send one, so the row never lands
      // with null globalId (the pre-fix state that caused the duplicate
      // pile-up — null globalIds are not unique against each other in
      // SQLite/PG, so the unique constraint allowed unlimited NULL rows).
      final globalIdToPersist =
          (incomingGlobalId != null && incomingGlobalId.isNotEmpty)
              ? incomingGlobalId
              : UuidV7.generate();

      final id = await db.into(db.branches).insert(
            BranchesCompanion.insert(
              name: trimmedName,
              code: Value(data['code'] as String?),
              address: Value(data['address'] as String?),
              phone: Value(data['phone'] as String?),
              costCenterId: Value(parseIntNullable(data['costCenterId'])),
              regionId: Value(parseIntNullable(data['regionId'])),
              globalId: Value(globalIdToPersist),
            ),
          );
      return jsonResponse(
          {'success': true, 'id': id, 'globalId': globalIdToPersist});
        },
      );
    } catch (e) {
      debugPrint('[API] postBranch error: $e');
      return ApiErrors.fail(e, 'Failed to create branch');
    }
  }

  Future<Response> putBranch(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.branchesManage);
      if (perm != null) return perm;
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      final branchId = int.parse(id);
      await (db.update(db.branches)..where((b) => b.id.equals(branchId)))
          .write(
        BranchesCompanion(
          name: data.containsKey('name')
              ? Value(data['name'] as String)
              : const Value.absent(),
          code: data.containsKey('code')
              ? Value(data['code'] as String?)
              : const Value.absent(),
          address: data.containsKey('address')
              ? Value(data['address'] as String?)
              : const Value.absent(),
          phone: data.containsKey('phone')
              ? Value(data['phone'] as String?)
              : const Value.absent(),
          costCenterId: data.containsKey('costCenterId')
              ? Value(parseIntNullable(data['costCenterId']))
              : const Value.absent(),
          regionId: data.containsKey('regionId')
              ? Value(parseIntNullable(data['regionId']))
              : const Value.absent(),
          isActive: data.containsKey('isActive')
              ? Value(parseBool(data['isActive'], true))
              : const Value.absent(),
        ),
      );
      broadcast('branches');
      return jsonResponse({'success': true});
    } catch (e) {
      debugPrint('[API] putBranch error: $e');
      return ApiErrors.fail(e, 'Failed to update branch');
    }
  }

  Future<Response> deleteBranch(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.branchesManage);
      if (perm != null) return perm;
      final branchId = int.parse(id);

      // Feature 049 (v131) — accept `reassignUsersToBranchId` from the
      // query string (server_proxy ships it that way) or the body.
      // Routes through the new DAO `deleteBranch` which soft-deletes +
      // reassigns user_branch_access rows inside a single transaction.
      // Without this v131 wiring, the mirror's dedup-duplicate-branch
      // workflow throws the same FK violation 23503 the server's own
      // admin hit on 2026-05-13.
      int? reassignTo;
      final qpRaw =
          request.requestedUri.queryParameters['reassignUsersToBranchId'];
      if (qpRaw != null && qpRaw.isNotEmpty) {
        reassignTo = int.tryParse(qpRaw);
      }
      if (reassignTo == null) {
        try {
          final body = await request.readAsString();
          if (body.isNotEmpty) {
            final data = json.decode(body);
            if (data is Map && data['reassignUsersToBranchId'] != null) {
              reassignTo =
                  parseIntNullable(data['reassignUsersToBranchId']);
            }
          }
        } catch (_) {/* DELETE bodies optional; silent ignore */}
      }

      await db.deleteBranch(branchId, reassignUsersToBranchId: reassignTo);
      broadcast('branches');
      broadcastRecordDeleted('branches', branchId);
      return jsonResponse({'success': true});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to delete branch');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Regions (Admin CRUD)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postRegion(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.branchesManage);
      if (perm != null) return perm;
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      final id = await db.createRegion(
        name: data['name'] as String,
        address: data['address'] as String?,
        phone: data['phone'] as String?,
        costCenterId: parseIntNullable(data['costCenterId']),
      );
      broadcast('regions');
      return jsonResponse({'success': true, 'id': id});
    } catch (e) {
      debugPrint('[API] postRegion error: $e');
      return ApiErrors.fail(e, 'Failed to create region');
    }
  }

  Future<Response> putRegion(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.branchesManage);
      if (perm != null) return perm;
      final regionId = int.parse(id);
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      final existing = await db.getRegionById(regionId);
      if (existing == null) {
        return Response.notFound(
          json.encode({'error': 'Region not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      await db.updateRegion(existing.copyWith(
        name: data['name'] as String? ?? existing.name,
        address: Value(data['address'] as String?),
        phone: Value(data['phone'] as String?),
        costCenterId: Value(parseIntNullable(data['costCenterId'])),
      ));
      broadcast('regions');
      return jsonResponse({'success': true});
    } catch (e) {
      debugPrint('[API] putRegion error: $e');
      return ApiErrors.fail(e, 'Failed to update region');
    }
  }

  Future<Response> deleteRegion(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.branchesManage);
      if (perm != null) return perm;
      final regionId = int.parse(id);
      await db.deactivateRegion(regionId);
      broadcast('regions');
      broadcastRecordDeleted('regions', regionId);
      return jsonResponse({'success': true});
    } catch (e) {
      debugPrint('[API] deleteRegion error: $e');
      return ApiErrors.fail(e, 'Failed to deactivate region', statusCode: 400);
    }
  }

  Future<Response> postUserRegionAccess(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.usersManage);
      if (perm != null) return perm;
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      final userId = parseInt(data['userId']);
      final regionIds = (data['regionIds'] as List).cast<int>();
      await db.setUserRegionAccess(userId, regionIds);
      broadcast('user_region_access');
      return jsonResponse({'success': true});
    } catch (e) {
      debugPrint('[API] postUserRegionAccess error: $e');
      return ApiErrors.fail(e, 'Failed to set user region access');
    }
  }
}
