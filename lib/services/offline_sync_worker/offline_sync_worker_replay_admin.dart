// OfflineSyncWorker - per-table replay dispatch, part 3: security and organisation master data.
part of '../offline_sync_worker.dart';

/// Tail of the `_replayOperation` switch: roles, users, regions, price lists, branches, accounts, warehouses, safes and the fail-loud default.
extension OfflineSyncWorkerReplayAdmin on OfflineSyncWorker {
  Future<dynamic> _replayOperationAdmin(
    String table,
    String operation,
    Map<String, dynamic> payload,
    ServerProxy proxy,
    String idempotencyKey,
  ) async {
    switch (table) {
      case 'roles':
        if (operation == 'insert') {
          return proxy.createRole(
            name: payload['name'] as String,
            description: payload['description'] as String?,
            isSystemRole: payload['isSystemRole'] as bool? ?? false,
          );
        }
        break;

      case 'role_permissions':
        // Replay a queued role-permission save. The payload was stored by
        // cwi_sync.setRolePermissions when the server was unreachable; we
        // forward it as-is. The same idempotency key is reused so the
        // server can dedupe a request that succeeded but whose response
        // never reached us.
        if (operation == 'set') {
          await proxy.setRolePermissions(
            payload['roleId'] as int,
            (payload['permissionCodes'] as List).cast<String>(),
            idempotencyKey: idempotencyKey,
            // Spec 136 ISS-15: replay the role identity so an offline-queued
            // save still lets the server resolve/create the role.
            roleGlobalId: payload['roleGlobalId'] as String?,
            roleName: payload['roleName'] as String?,
          );
        }
        break;

      case 'users':
        if (operation == 'insert') {
          return proxy.createUser(
            username: payload['username'] as String,
            password: payload['password'] as String,
            displayName: payload['displayName'] as String,
            roleId: payload['roleId'] as int?,
            branchIds: (payload['branchIds'] as List?)?.cast<int>(),
            globalId: payload['globalId'] as String?,
          );
        } else if (operation == 'update') {
          final id = payload['id'] as int;
          // Three possible shapes from ClientWriteInterceptor: full field update,
          // password-only update, or pin-only update. Dispatch by which key is
          // the sole payload field after stripping 'id'.
          final fields = Map<String, dynamic>.from(payload)..remove('id');
          if (fields.length == 1 && fields.containsKey('password')) {
            await proxy.updateUserPassword(id, fields['password'] as String,
                idempotencyKey: idempotencyKey);
          } else if (fields.length == 1 && fields.containsKey('pin')) {
            await proxy.updateUserPin(id, fields['pin'] as String?,
                idempotencyKey: idempotencyKey);
          } else {
            await proxy.updateUser(id, fields, idempotencyKey: idempotencyKey);
          }
        }
        break;

      case 'regions':
        if (operation == 'insert') {
          return proxy.createRegion(
            name: payload['name'] as String,
            address: payload['address'] as String?,
            phone: payload['phone'] as String?,
            costCenterId: payload['costCenterId'] as int?,
          );
        } else if (operation == 'update') {
          await proxy.updateRegion(
            id: payload['id'] as int,
            name: payload['name'] as String,
            address: payload['address'] as String?,
            phone: payload['phone'] as String?,
            costCenterId: payload['costCenterId'] as int?,
          );
        }
        break;

      case 'party_groups':
        if (operation == 'insert') {
          return proxy.createPartyGroup(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'update') {
          final id = payload['id'] as int;
          final data = Map<String, dynamic>.from(payload)..remove('id');
          await proxy.updatePartyGroup(id, data, idempotencyKey: idempotencyKey);
        } else if (operation == 'delete') {
          await proxy.deletePartyGroup(payload['id'] as int, idempotencyKey: idempotencyKey);
        }
        break;

      case 'purchase_orders':
        if (operation == 'insert') {
          return proxy.createPurchaseOrder(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'update') {
          await proxy.updatePurchaseOrderStatus(
            payload['id'] as int,
            payload['status'] as String,
            idempotencyKey: idempotencyKey,
          );
        } else if (operation == 'delete') {
          await proxy.deletePurchaseOrder(payload['id'] as int, idempotencyKey: idempotencyKey);
        }
        break;

      case 'sales_orders':
        if (operation == 'insert') {
          return proxy.createSalesOrder(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'update') {
          await proxy.updateSalesOrderStatus(
            payload['id'] as int,
            payload['status'] as String,
            idempotencyKey: idempotencyKey,
          );
        } else if (operation == 'delete') {
          await proxy.deleteSalesOrder(payload['id'] as int, idempotencyKey: idempotencyKey);
        }
        break;

      case 'price_lists':
        if (operation == 'insert') {
          return proxy.createPriceList(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'update') {
          final id = payload['id'] as int;
          final data = Map<String, dynamic>.from(payload)..remove('id');
          await proxy.updatePriceList(id, data, idempotencyKey: idempotencyKey);
        }
        break;

      case 'price_list_items':
        if (operation == 'upsert') {
          await proxy.setPriceListItem(payload, idempotencyKey: idempotencyKey);
        }
        break;

      case 'printers':
        if (operation == 'insert') {
          return proxy.createPrinter(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'update') {
          final id = payload['id'] as int;
          final data = Map<String, dynamic>.from(payload)..remove('id');
          await proxy.updatePrinter(id, data, idempotencyKey: idempotencyKey);
        } else if (operation == 'delete') {
          await proxy.deletePrinter(payload['id'] as int, idempotencyKey: idempotencyKey);
        }
        break;

      case 'inventory_bonds':
        if (operation == 'insert') {
          return proxy.submitInventoryBond(payload, idempotencyKey: idempotencyKey);
        }
        break;

      // ── Admin / structural tables ────────────────────────────────────────
      // These seven had NO case at all, so every queued operation fell to the
      // `default:` StateError → isPermanentError → markAsSyncDeadLetter. The
      // "retry all" button flips dead-letter rows back to pending with
      // attempts=0, they hit the same StateError, and dead-letter again —
      // an endless loop the admin can never clear. Eighteen enqueue sites
      // across cwi_admin/cwi_catalog/cwi_sync fed it.
      //
      // Every operation below already has a tested method on ServerProxy (the
      // same one the online path calls) and every payload already carries what
      // that method needs, so this is dispatch-table plumbing, not new
      // behaviour. NOTE: mirror mode never reaches here — it throws
      // MirrorOfflineException instead of queueing — so this is a client-mode
      // fix exclusively.

      case 'branches':
        if (operation == 'insert') {
          await proxy.createBranch(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'update') {
          await proxy.updateBranch(
            payload['id'] as int,
            OfflineSyncWorker._withoutId(payload),
            idempotencyKey: idempotencyKey,
          );
        } else if (operation == 'delete') {
          await proxy.deleteBranch(
            payload['id'] as int,
            reassignUsersToBranchId: payload['reassignUsersToBranchId'] as int?,
            idempotencyKey: idempotencyKey,
          );
        } else {
          throw StateError('Unhandled op $operation for table $table');
        }
        break;

      case 'accounts':
        if (operation == 'insert') {
          await proxy.createAccount(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'update') {
          await proxy.updateAccount(
            payload['id'] as int,
            OfflineSyncWorker._withoutId(payload),
            idempotencyKey: idempotencyKey,
          );
        } else if (operation == 'delete') {
          await proxy.deleteAccount(payload['id'] as int,
              idempotencyKey: idempotencyKey);
        } else {
          throw StateError('Unhandled op $operation for table $table');
        }
        break;

      case 'account_mappings':
        if (operation == 'upsert') {
          await proxy.setAccountMapping(payload,
              idempotencyKey: idempotencyKey);
        } else if (operation == 'delete') {
          await proxy.deleteAccountMapping(
            purpose: payload['purpose'] as String,
            costCenterId: payload['costCenterId'] as int?,
            idempotencyKey: idempotencyKey,
          );
        } else {
          throw StateError('Unhandled op $operation for table $table');
        }
        break;

      case 'cost_centers':
        if (operation == 'insert') {
          await proxy.createCostCenter(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'update') {
          await proxy.updateCostCenter(
            payload['id'] as int,
            OfflineSyncWorker._withoutId(payload),
            idempotencyKey: idempotencyKey,
          );
        } else if (operation == 'delete') {
          await proxy.deleteCostCenter(payload['id'] as int,
              idempotencyKey: idempotencyKey);
        } else {
          throw StateError('Unhandled op $operation for table $table');
        }
        break;

      case 'user_region_access':
        if (operation == 'upsert') {
          await proxy.setUserRegionAccess(
            payload['userId'] as int,
            (payload['regionIds'] as List).map((e) => e as int).toList(),
            idempotencyKey: idempotencyKey,
          );
        } else {
          throw StateError('Unhandled op $operation for table $table');
        }
        break;

      case 'warehouses':
        if (operation == 'insert') {
          return proxy.createWarehouse(
            name: payload['name'] as String,
            branchId: payload['branchId'] as int?,
            globalId: payload['globalId'] as String?,
          );
        } else if (operation == 'update') {
          // Three distinct enqueue sites share operation='update' and are
          // told apart by these flags (cwi_catalog setDefault/unsetDefault).
          // Replaying the wrong one silently re-points the POS's default
          // warehouse, so the discrimination has to match the producer.
          if (payload['setDefault'] == true) {
            await proxy.setDefaultWarehouse(payload['id'] as int,
                idempotencyKey: idempotencyKey);
          } else if (payload['unsetDefault'] == true) {
            await proxy.unsetDefaultWarehouse(payload['id'] as int,
                idempotencyKey: idempotencyKey);
          } else {
            await proxy.updateWarehouse(
              payload['id'] as int,
              OfflineSyncWorker._withoutId(payload),
              idempotencyKey: idempotencyKey,
            );
          }
        } else if (operation == 'delete') {
          await proxy.deleteWarehouse(payload['id'] as int,
              idempotencyKey: idempotencyKey);
        } else {
          throw StateError('Unhandled op $operation for table $table');
        }
        break;

      case 'activity_logs':
        if (operation == 'insert') {
          await proxy.pushActivityLog(payload,
              idempotencyKey: idempotencyKey);
        } else {
          throw StateError('Unhandled op $operation for table $table');
        }
        break;

      case 'safes':
        if (operation == 'close') {
          // Spec 135: forward the cached amounts + closeEventGid so a deferred
          // replay re-sends the SAME deterministic closing-JE id and the same
          // split (older entries without these keys replay as null — pre-135
          // behaviour). The DAO's gid guard + balance<=0 check keep replay
          // idempotent.
          await proxy.closeSafe(
            payload['safeId'] as int,
            userId: payload['userId'] as int?,
            cashAmount: (payload['cashAmount'] as num?)?.toDouble(),
            bankAmount: (payload['bankAmount'] as num?)?.toDouble(),
            notes: payload['notes'] as String?,
            closeEventGid: payload['closeEventGid'] as String?,
            idempotencyKey: idempotencyKey,
          );
        } else if (operation == 'insert') {
          await proxy.createSafe(payload, idempotencyKey: idempotencyKey);
        } else if (operation == 'delete') {
          await proxy.deleteSafe(payload['id'] as int,
              idempotencyKey: idempotencyKey);
        } else if (operation == 'update') {
          // ClientWriteInterceptor.submitSetDefaultSafe queues this shape.
          if (payload['isDefault'] == true) {
            await proxy.submitSetDefaultSafe(
              safeId: payload['id'] as int,
              idempotencyKey: idempotencyKey,
            );
          } else {
            // A generic safe edit (rename / bank details / isActive). Falling
            // through to `break` here returned null, which drainOutbox reads
            // as SUCCESS and clears the row — the edit vanished with no
            // dead-letter, no log, no trace. That is strictly worse than the
            // dead-letter loop the seven tables above suffered: at least a
            // dead-letter is visible.
            await proxy.updateSafe(
              payload['id'] as int,
              OfflineSyncWorker._withoutId(payload),
              idempotencyKey: idempotencyKey,
            );
          }
        } else {
          throw StateError('Unhandled op $operation for table $table');
        }
        break;

      default:
        // BLOCKER C-01 (Spec 151) — FAIL-LOUD. Previously this debugPrint'd and
        // returned null, so the drain loop marked the item as a sync SUCCESS
        // and cleared it from the outbox — silently DROPPING the write (an
        // offline journal_entries GL row was the field repro). Throwing routes
        // the item through the permanent-error classifier in drainOutbox →
        // markAsSyncDeadLetter + SYNC-WARN, turning a silent drop into a
        // visible dead-letter the admin can see (and manually retry once a code
        // fix adds the missing case). NEVER return null here.
        throw StateError('Unknown sync table: $table (op=$operation)');
    }
  }
}
