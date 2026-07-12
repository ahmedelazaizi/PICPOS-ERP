// ═══════════════════════════════════════════════════════════════════════════
// Spec 136 ISS-10 — user_branch_access branchId remap (server → local id)
// ═══════════════════════════════════════════════════════════════════════════
//
// The login guard (_verifyBranchAccess) checks `assignments.contains(
// client_branch_id)`, where client_branch_id is this device's LOCAL branch id.
// But the sync stored the SERVER's branch id verbatim, so when local↔server
// ids drift (BranchSync's name-match keeps the local id) the assigned user was
// wrongly denied with "ليس لديك صلاحية الدخول لهذا الفرع".
//
// Fix: the server now sends branchGlobalId per row, and the strategy remaps it
// to the LOCAL branch id via the globalId so the stored id matches the local
// branches table (and therefore client_branch_id).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/sync/strategies/user_branch_access_sync_strategy.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
  });

  tearDown(() => db.close());

  test('remaps the server branchId to the LOCAL branch id via globalId',
      () async {
    // Local branch carries LOCAL id 5 but the server's (shared) globalId — the
    // exact drift case (server calls the same branch id 1).
    final localId = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'الفرع الرئيسي',
            globalId: const Value('gid-main-branch'),
          ),
        );
    expect(localId, isNot(1),
        reason: 'force a local id that differs from the server id (1)');

    final strategy = UserBranchAccessSyncStrategy(db);
    await strategy.syncFromJson({
      'user_branch_access': [
        {
          'userId': 10,
          'branchId': 1, // SERVER id — must NOT be stored verbatim
          'branchGlobalId': 'gid-main-branch',
        },
      ],
    });

    final rows = await db.select(db.userBranchAccess).get();
    expect(rows, hasLength(1));
    expect(rows.single.branchId, localId,
        reason: 'branchId must be remapped to the local branches.id');
    expect(rows.single.userId, 10);
  });

  test('falls back to the raw server branchId when no globalId is sent '
      '(legacy server)', () async {
    final strategy = UserBranchAccessSyncStrategy(db);
    await strategy.syncFromJson({
      'user_branch_access': [
        {'userId': 7, 'branchId': 3}, // no branchGlobalId
      ],
    });
    final rows = await db.select(db.userBranchAccess).get();
    expect(rows.single.branchId, 3);
  });

  test('server-side deletion still propagates after remap', () async {
    final localId = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'فرع',
            globalId: const Value('gid-x'),
          ),
        );
    final strategy = UserBranchAccessSyncStrategy(db);
    // First pull: user 10 assigned.
    await strategy.syncFromJson({
      'user_branch_access': [
        {'userId': 10, 'branchId': 99, 'branchGlobalId': 'gid-x'},
      ],
    });
    expect(await db.select(db.userBranchAccess).get(), hasLength(1));
    // Second pull: server removed the assignment → local row dropped.
    await strategy.syncFromJson({'user_branch_access': <dynamic>[]});
    expect(await db.select(db.userBranchAccess).get(), isEmpty);
    // (localId referenced to silence unused; the remap used gid-x → localId.)
    expect(localId, greaterThan(0));
  });
}
