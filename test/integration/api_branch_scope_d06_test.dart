// ═══════════════════════════════════════════════════════════════════════════
// Spec 151 · Wave C · D-06 (MINOR) — the embedded API's `?branch_id=` read
// scope must be bound to the CALLING USER's accessible branches, so a
// branch-restricted client can't read another branch by passing its id.
// ═══════════════════════════════════════════════════════════════════════════
//
// Pre-fix: _extractBranchId parsed `?branch_id=` with ZERO identity binding —
// a per-branch client could request any branch's id (or omit it) and read that
// branch's rows. Fix makes _extractBranchId async and clamps the requested
// branch to `getUserAccessibleBranchIds(userId)`:
//   - no verified identity         → FAIL CLOSED (sentinel scope, zero rows)
//   - full-access user (admin/[])  → requested honored
//   - restricted user, foreign/null→ clamped to home / allowed.first
//
// buildRouter() does NOT wire ApiAuthMiddleware, so — exactly like
// api_sales_handler_perm_gates_test — the userId is injected DIRECTLY on the
// request context (no header/middleware). Spec 151 P1-8 CLOSED the residual
// forgery gap: identity now comes only from a signed session token, and a
// request with no verified identity fails closed instead of honoring the
// requested branch (see the final test — flipped from the old "requested
// honored" residual).
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/api/api_handler.dart';
import 'package:ural_erp/services/api/api_user_context.dart';

void main() {
  late AppDatabase db;
  late ApiHandler handler;
  late int branchAId;
  late int branchBId;
  late int restrictedUserId; // access to branch A only

  setUp(() async {
    db = AppDatabase.forTesting();
    handler = ApiHandler(db);

    branchAId = await db.into(db.branches).insert(BranchesCompanion.insert(
        name: 'فرع A', globalId: const Value('gid-br-d06-a')));
    branchBId = await db.into(db.branches).insert(BranchesCompanion.insert(
        name: 'فرع B', globalId: const Value('gid-br-d06-b')));

    // Warehouse + safe per branch (map §6 scenario fidelity).
    await db.into(db.warehouses).insert(WarehousesCompanion.insert(
        name: 'مخزن A',
        branchId: Value(branchAId),
        globalId: const Value('gid-wh-d06-a')));
    await db.into(db.warehouses).insert(WarehousesCompanion.insert(
        name: 'مخزن B',
        branchId: Value(branchBId),
        globalId: const Value('gid-wh-d06-b')));
    await db.into(db.safes).insert(SafesCompanion.insert(
        name: 'صندوق A',
        branchId: Value(branchAId),
        globalId: const Value('gid-safe-d06-a')));
    await db.into(db.safes).insert(SafesCompanion.insert(
        name: 'صندوق B',
        branchId: Value(branchBId),
        globalId: const Value('gid-safe-d06-b')));

    // One journal entry per branch.
    await db.into(db.journalEntries).insert(JournalEntriesCompanion.insert(
        entryNumber: 'JE-D06-A',
        entryDate: DateTime(2025, 5, 10),
        branchId: Value(branchAId),
        globalId: const Value('gid-je-d06-a')));
    await db.into(db.journalEntries).insert(JournalEntriesCompanion.insert(
        entryNumber: 'JE-D06-B',
        entryDate: DateTime(2025, 5, 11),
        branchId: Value(branchBId),
        globalId: const Value('gid-je-d06-b')));

    // Restricted (non-admin) user with a single branch-A access grant.
    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(
              name: 'كاشير D06', isSystemRole: const Value(false)),
        );
    restrictedUserId = await db.createUser(
      username: 'd06_cashier',
      password: 'test',
      displayName: 'D06 Cashier',
      roleId: roleId,
    );
    await db.setUserBranchAccess(restrictedUserId, [branchAId]);
  });

  tearDown(() => db.close());

  /// GET a JSON endpoint through the real router, optionally injecting a
  /// validated userId on the request context (no auth middleware in buildRouter).
  Future<Map<String, dynamic>> getJson(String path, {int? userId}) async {
    final resp = await handler.buildRouter().call(shelf.Request(
          'GET',
          Uri.parse('http://localhost$path'),
          context: userId != null ? {ApiUserCtx.userIdKey: userId} : const {},
        ));
    final body = await resp.readAsString();
    expect(resp.statusCode, 200, reason: 'GET $path failed: $body');
    return jsonDecode(body) as Map<String, dynamic>;
  }

  Set<int?> branchIdsOf(Map<String, dynamic> body) => (body['journals'] as List)
      .map((j) => (j as Map<String, dynamic>)['branchId'] as int?)
      .toSet();

  test('restricted user asking for a FOREIGN branch_id is clamped (no leak)',
      () async {
    final body = await getJson('/api/journals?branch_id=$branchBId',
        userId: restrictedUserId);
    final branchIds = branchIdsOf(body);
    expect(branchIds.contains(branchBId), isFalse,
        reason: 'the foreign branch-B JE must NOT leak to a branch-A-only user');
    expect(branchIds.contains(branchAId), isTrue,
        reason: 'clamped to the caller\'s accessible branch A → A JE returned');
  });

  test('restricted user with NO branch_id is clamped to their branch, not all',
      () async {
    final body = await getJson('/api/journals', userId: restrictedUserId);
    final branchIds = branchIdsOf(body);
    expect(branchIds.contains(branchBId), isFalse,
        reason: 'null branch_id must clamp to A, not fall through to all');
    expect(branchIds.contains(branchAId), isTrue);
  });

  test('admin (userId=1) is honored — foreign branch_id returns that branch',
      () async {
    final body = await getJson('/api/journals?branch_id=$branchBId', userId: 1);
    final branchIds = branchIdsOf(body);
    expect(branchIds.contains(branchBId), isTrue,
        reason: 'admin has full access ([] = no cap) → requested B honored');
  });

  test(
      'own-branch request is honored unchanged (no over-restriction of A)',
      () async {
    final body = await getJson('/api/journals?branch_id=$branchAId',
        userId: restrictedUserId);
    final branchIds = branchIdsOf(body);
    expect(branchIds.contains(branchAId), isTrue);
    expect(branchIds.contains(branchBId), isFalse);
  });

  test(
      'Spec 151 P1-8b — no identity on a TRANSACTIONAL endpoint (journals) '
      'fails closed (omission CLOSED)', () async {
    // Track-1 closed FORGERY but left OMISSION open (this test then asserted
    // `requested` honored). P1-8b closes omission for the branch-scoped
    // TRANSACTIONAL surface: /api/journals now passes failClosedOnNoIdentity:
    // true, so a tokenless caller gets the -1 sentinel → ZERO rows, never
    // another branch's journal data. REFERENCE endpoints (/api/branches, …)
    // still honor `requested` so tokenless provisioning is not bricked — see
    // api_p1_8b_sync_scope_test for the reference-full + delta-deny coverage.
    final body = await getJson('/api/journals?branch_id=$branchBId');
    final branchIds = branchIdsOf(body);
    expect(body['journals'], isEmpty,
        reason: 'no verified identity → fail closed → zero transactional rows');
    expect(branchIds.contains(branchBId), isFalse,
        reason: 'the foreign branch-B journal must NOT leak to a tokenless '
            'caller (omission closed)');
  });
}
