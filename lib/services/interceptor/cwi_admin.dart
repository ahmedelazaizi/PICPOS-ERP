part of '../client_write_interceptor.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Admin module — Feature 006 / MM.C
//
// CRUD methods that previously had no client→server route because they were
// considered "server-only" admin operations (branches, safes, accounts,
// account mappings, cost centers, etc.). Mirror mode lets an HQ admin
// perform these operations from a remote laptop, so they need to flow
// through the interceptor like any other write.
//
// Each method follows the same shape as the existing _CwiCommerce /
// _CwiCatalog modules:
//   1. Early-out when the interceptor is not active (standalone / server
//      mode → falls through to the local DAO write at the call site).
//   2. Mint a globalId if the caller didn't provide one.
//   3. Hand off to ClientWriteInterceptor._tryOrQueue, which transparently
//      stamps mirror admin attribution and skips the outbox in mirror mode.
// ═══════════════════════════════════════════════════════════════════════════

class _CwiAdmin {
  _CwiAdmin._();

  // ── Branches ──────────────────────────────────────────────────────────────

  static Future<int?> createBranch({
    required String name,
    String? code,
    String? address,
    String? phone,
    int? costCenterId,
    int? regionId,
    String? globalId,
  }) async {
    if (!SyncInterceptor.isClientMode) return null;
    debugPrint('[ClientInterceptor] Routing branch create to server');
    final gid = (globalId == null || globalId.isEmpty)
        ? const Uuid().v7()
        : globalId;
    return ClientWriteInterceptor._tryOrQueue(
      tableName: 'branches',
      operation: 'insert',
      payload: {
        'name': name,
        'code': code,
        'address': address,
        'phone': phone,
        'costCenterId': costCenterId,
        'regionId': regionId,
        'globalId': gid,
      },
      serverCall: (idem) => ClientWriteInterceptor._proxy.createBranch(
        {
          'name': name,
          'code': code,
          'address': address,
          'phone': phone,
          'costCenterId': costCenterId,
          'regionId': regionId,
          'globalId': gid,
        },
        idempotencyKey: idem,
      ),
    );
  }

  static Future<bool> updateBranch(int id, Map<String, dynamic> data) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing branch update to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'branches',
      operation: 'update',
      payload: {'id': id, ...data},
      serverCall: (idem) =>
          ClientWriteInterceptor._proxy.updateBranch(id, data, idempotencyKey: idem),
    );
  }

  static Future<bool> deleteBranch(int id, {int? reassignUsersToBranchId}) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing branch delete to server '
        '(reassignTo=${reassignUsersToBranchId ?? "null"})');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'branches',
      operation: 'delete',
      payload: {
        'id': id,
        // Feature 049 (v131) — caller-chosen destination for moving
        // user_branch_access rows. Null = no reassign; server throws
        // the same FK-prevention Arabic error so the dialog can route
        // back to the bulk-reassign flow.
        'reassignUsersToBranchId': reassignUsersToBranchId,
      },
      serverCall: (idem) => ClientWriteInterceptor._proxy.deleteBranch(
        id,
        reassignUsersToBranchId: reassignUsersToBranchId,
        idempotencyKey: idem,
      ),
    );
  }

  // ── Safes ─────────────────────────────────────────────────────────────────

  static Future<int?> createSafe({
    required String name,
    required String safeType,
    String? bankName,
    String? accountNumber,
    int? costCenterId,
    int? branchId,
    String? globalId,
  }) async {
    if (!SyncInterceptor.isClientMode) return null;
    debugPrint('[ClientInterceptor] Routing safe create to server');
    final gid = (globalId == null || globalId.isEmpty)
        ? const Uuid().v7()
        : globalId;
    final payload = <String, dynamic>{
      'name': name,
      'safeType': safeType,
      'bankName': bankName,
      'accountNumber': accountNumber,
      'costCenterId': costCenterId,
      'branchId': branchId,
      'globalId': gid,
    };
    return ClientWriteInterceptor._tryOrQueue(
      tableName: 'safes',
      operation: 'insert',
      payload: payload,
      serverCall: (idem) =>
          ClientWriteInterceptor._proxy.createSafe(payload, idempotencyKey: idem),
    );
  }

  static Future<bool> updateSafe(int id, Map<String, dynamic> data) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing safe update to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'safes',
      operation: 'update',
      payload: {'id': id, ...data},
      serverCall: (idem) =>
          ClientWriteInterceptor._proxy.updateSafe(id, data, idempotencyKey: idem),
    );
  }

  static Future<bool> deleteSafe(int id) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing safe delete to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'safes',
      operation: 'delete',
      payload: {'id': id},
      serverCall: (idem) =>
          ClientWriteInterceptor._proxy.deleteSafe(id, idempotencyKey: idem),
    );
  }

  // ── Accounts (Chart of Accounts) ──────────────────────────────────────────

  static Future<int?> createAccount({
    required String code,
    required String name,
    required String accountType,
    int? parentId,
    String? globalId,
  }) async {
    if (!SyncInterceptor.isClientMode) return null;
    debugPrint('[ClientInterceptor] Routing account create to server');
    final gid = (globalId == null || globalId.isEmpty)
        ? const Uuid().v7()
        : globalId;
    final payload = <String, dynamic>{
      'code': code,
      'name': name,
      'accountType': accountType,
      'parentId': parentId,
      'globalId': gid,
    };
    return ClientWriteInterceptor._tryOrQueue(
      tableName: 'accounts',
      operation: 'insert',
      payload: payload,
      serverCall: (idem) => ClientWriteInterceptor._proxy.createAccount(
        payload,
        idempotencyKey: idem,
      ),
    );
  }

  static Future<bool> updateAccount(int id, Map<String, dynamic> data) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing account update to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'accounts',
      operation: 'update',
      payload: {'id': id, ...data},
      serverCall: (idem) => ClientWriteInterceptor._proxy.updateAccount(
        id,
        data,
        idempotencyKey: idem,
      ),
    );
  }

  static Future<bool> deleteAccount(int id) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing account delete to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'accounts',
      operation: 'delete',
      payload: {'id': id},
      serverCall: (idem) =>
          ClientWriteInterceptor._proxy.deleteAccount(id, idempotencyKey: idem),
    );
  }

  // ── Account Mappings (purpose → account) ─────────────────────────────────

  static Future<bool> setAccountMapping({
    required String purpose,
    required int accountId,
    int? costCenterId,
  }) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing account-mapping upsert to server');
    final payload = <String, dynamic>{
      'purpose': purpose,
      'accountId': accountId,
      'costCenterId': costCenterId,
    };
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'account_mappings',
      operation: 'upsert',
      payload: payload,
      serverCall: (idem) => ClientWriteInterceptor._proxy.setAccountMapping(
        payload,
        idempotencyKey: idem,
      ),
    );
  }

  static Future<bool> deleteAccountMapping({
    required String purpose,
    int? costCenterId,
  }) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing account-mapping delete to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'account_mappings',
      operation: 'delete',
      payload: {'purpose': purpose, 'costCenterId': costCenterId},
      serverCall: (idem) => ClientWriteInterceptor._proxy.deleteAccountMapping(
        purpose: purpose,
        costCenterId: costCenterId,
        idempotencyKey: idem,
      ),
    );
  }

  // ── Cost Centers ──────────────────────────────────────────────────────────

  static Future<int?> createCostCenter({
    required String code,
    required String name,
    int? parentId,
    String? globalId,
  }) async {
    if (!SyncInterceptor.isClientMode) return null;
    debugPrint('[ClientInterceptor] Routing cost-center create to server');
    final gid = (globalId == null || globalId.isEmpty)
        ? const Uuid().v7()
        : globalId;
    final payload = <String, dynamic>{
      'code': code,
      'name': name,
      'parentId': parentId,
      'globalId': gid,
    };
    return ClientWriteInterceptor._tryOrQueue(
      tableName: 'cost_centers',
      operation: 'insert',
      payload: payload,
      serverCall: (idem) => ClientWriteInterceptor._proxy.createCostCenter(
        payload,
        idempotencyKey: idem,
      ),
    );
  }

  static Future<bool> updateCostCenter(
      int id, Map<String, dynamic> data) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing cost-center update to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'cost_centers',
      operation: 'update',
      payload: {'id': id, ...data},
      serverCall: (idem) => ClientWriteInterceptor._proxy.updateCostCenter(
        id,
        data,
        idempotencyKey: idem,
      ),
    );
  }

  static Future<bool> deleteCostCenter(int id) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing cost-center delete to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'cost_centers',
      operation: 'delete',
      payload: {'id': id},
      serverCall: (idem) => ClientWriteInterceptor._proxy.deleteCostCenter(
        id,
        idempotencyKey: idem,
      ),
    );
  }

  // ── User Region Access (F3) ──────────────────────────────────────────────

  static Future<bool> setUserRegionAccess(
    int userId,
    List<int> regionIds,
  ) async {
    if (!SyncInterceptor.isClientMode) return false;
    debugPrint('[ClientInterceptor] Routing user-region-access to server');
    return ClientWriteInterceptor._tryOrQueueVoid(
      tableName: 'user_region_access',
      operation: 'upsert',
      payload: {'userId': userId, 'regionIds': regionIds},
      serverCall: (idem) => ClientWriteInterceptor._proxy.setUserRegionAccess(
        userId,
        regionIds,
        idempotencyKey: idem,
      ),
    );
  }
}
