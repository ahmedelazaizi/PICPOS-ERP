// ═══════════════════════════════════════════════════════════════════════════
// Spec 151 residual #2 (D-06 fail-open) — a NON-privileged user who was
// mis-provisioned with ZERO branch assignments makes getUserAccessibleBranchIds
// return `[]`, which the D-06 fix originally treated as "full access". That is a
// fail-OPEN: such a user read EVERY branch. This suite locks the fix closed.
//
// Two independent fail-open layers had to be shut (see residuals-map §2.3):
//   Step B — _extractBranchId now splits the ambiguous `[]`: privileged users
//            (admin / financial-manager / userId==1) keep full access, a
//            mis-provisioned non-privileged user is scoped to the impossible
//            sentinel branch (-1).
//   Step C — _resolveBranchWarehouseIds / _resolveBranchSafeIds now return the
//            sentinel `[-1]` (not `[]`) for a branch with no children, so the
//            six consumers' `if (ids.isNotEmpty)` guard can no longer DROP the
//            filter and return every row. The five transactional endpoints
//            (sales / purchases / stock-movements / inventory-balances /
//            safe-transactions) regress-test Step C; journals tests Step B alone.
//
// buildRouter() does NOT wire ApiAuthMiddleware, so — exactly like the D-06
// suite — the userId is injected DIRECTLY on the request context.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/api/api_handler.dart';
import 'package:picpos_erp/services/api/api_user_context.dart';

void main() {
  late AppDatabase db;
  late ApiHandler handler;
  late int branchAId;
  late int branchBId;
  late int whAId;
  late int whBId;
  late int safeAId;
  late int safeBId;
  late int ccAId; // cost center linked to branch A (branches.costCenterId)
  late int ccBId; // cost center linked to branch B
  late int shiftAId; // shift owned by the branch-A user
  late int shiftBId; // shift owned by the branch-B (non-system) user
  late int restrictedUserId; // access to branch A only (regression guard)
  late int branchBUserId; // non-system, branch-B only — owns the branch-B shift
  late int misProvisionedUserId; // non-system role, NO branch access (the fix)

  setUp(() async {
    db = AppDatabase.forTesting();
    handler = ApiHandler(db);

    branchAId = await db.into(db.branches).insert(BranchesCompanion.insert(
        name: 'فرع A', globalId: const Value('gid-br-r2-a')));
    branchBId = await db.into(db.branches).insert(BranchesCompanion.insert(
        name: 'فرع B', globalId: const Value('gid-br-r2-b')));

    // A warehouse + safe per branch.
    whAId = await db.into(db.warehouses).insert(WarehousesCompanion.insert(
        name: 'مخزن A',
        branchId: Value(branchAId),
        globalId: const Value('gid-wh-r2-a')));
    whBId = await db.into(db.warehouses).insert(WarehousesCompanion.insert(
        name: 'مخزن B',
        branchId: Value(branchBId),
        globalId: const Value('gid-wh-r2-b')));
    safeAId = await db.into(db.safes).insert(SafesCompanion.insert(
        name: 'صندوق A',
        branchId: Value(branchAId),
        globalId: const Value('gid-safe-r2-a')));
    safeBId = await db.into(db.safes).insert(SafesCompanion.insert(
        name: 'صندوق B',
        branchId: Value(branchBId),
        globalId: const Value('gid-safe-r2-b')));

    // Cost centers — one per branch, linked back via branches.costCenterId so a
    // branch-A read resolves to cost center A (see _getCostCenters). Seeding a
    // branch-B cost center is what makes the mis-provisioned "zero rows"
    // assertion non-vacuous.
    ccAId = await db.into(db.costCenters).insert(CostCentersCompanion.insert(
        code: 'CC-A', name: 'مركز تكلفة A', globalId: const Value('gid-cc-r2-a')));
    ccBId = await db.into(db.costCenters).insert(CostCentersCompanion.insert(
        code: 'CC-B', name: 'مركز تكلفة B', globalId: const Value('gid-cc-r2-b')));
    await (db.update(db.branches)..where((b) => b.id.equals(branchAId)))
        .write(BranchesCompanion(costCenterId: Value(ccAId)));
    await (db.update(db.branches)..where((b) => b.id.equals(branchBId)))
        .write(BranchesCompanion(costCenterId: Value(ccBId)));

    // ── Seed one row per branch across ALL six scoped endpoints. Seeding a
    //    branch-B row is what makes the "zero rows" assertions non-vacuous:
    //    without the fix these rows LEAK to the mis-provisioned user.

    // Journals (Step B — direct branchId filter).
    await db.into(db.journalEntries).insert(JournalEntriesCompanion.insert(
        entryNumber: 'JE-R2-A',
        entryDate: DateTime(2025, 5, 10),
        branchId: Value(branchAId),
        globalId: const Value('gid-je-r2-a')));
    await db.into(db.journalEntries).insert(JournalEntriesCompanion.insert(
        entryNumber: 'JE-R2-B',
        entryDate: DateTime(2025, 5, 11),
        branchId: Value(branchBId),
        globalId: const Value('gid-je-r2-b')));

    // Sales invoices (Step C — warehouse-resolve).
    await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
        invoiceNumber: 'SI-R2-A',
        warehouseId: whAId,
        userId: 1,
        invoiceDate: DateTime(2025, 5, 10),
        branchId: Value(branchAId),
        total: const Value(100)));
    await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
        invoiceNumber: 'SI-R2-B',
        warehouseId: whBId,
        userId: 1,
        invoiceDate: DateTime(2025, 5, 11),
        branchId: Value(branchBId),
        total: const Value(200)));

    // Purchase invoices (Step C — warehouse-resolve).
    await db.into(db.purchaseInvoices).insert(PurchaseInvoicesCompanion.insert(
        invoiceNumber: 'PI-R2-A',
        supplierId: 1,
        warehouseId: whAId,
        invoiceDate: DateTime(2025, 5, 10),
        total: const Value(100)));
    await db.into(db.purchaseInvoices).insert(PurchaseInvoicesCompanion.insert(
        invoiceNumber: 'PI-R2-B',
        supplierId: 1,
        warehouseId: whBId,
        invoiceDate: DateTime(2025, 5, 11),
        total: const Value(200)));

    // products is empty in a fresh DB — seed the product the stock/inventory
    // rows below FK to (FK is enforced in tests now, mirroring production).
    final prodId = await db.into(db.products).insert(
        ProductsCompanion.insert(code: 'P-R2', name: 'صنف R2'));

    // Stock movements (Step C — warehouse-resolve).
    await db.into(db.stockMovements).insert(StockMovementsCompanion.insert(
        productId: prodId,
        warehouseId: whAId,
        quantity: 5.0,
        movementType: 'adjustment',
        balanceAfter: 5.0));
    await db.into(db.stockMovements).insert(StockMovementsCompanion.insert(
        productId: prodId,
        warehouseId: whBId,
        quantity: 7.0,
        movementType: 'adjustment',
        balanceAfter: 7.0));

    // Inventory balances (Step C — warehouse-resolve).
    await db.into(db.inventoryBalances).insert(InventoryBalancesCompanion.insert(
        productId: prodId, warehouseId: whAId, quantity: const Value(5)));
    await db.into(db.inventoryBalances).insert(InventoryBalancesCompanion.insert(
        productId: prodId, warehouseId: whBId, quantity: const Value(7)));

    // Safe transactions (Step C — safe-resolve).
    await db.into(db.safeTransactions).insert(SafeTransactionsCompanion.insert(
        safeId: safeAId,
        transactionType: 'receipt',
        voucherNumber: 'RV-R2-A',
        amount: 100.0,
        balanceAfter: 100.0,
        category: 'sales'));
    await db.into(db.safeTransactions).insert(SafeTransactionsCompanion.insert(
        safeId: safeBId,
        transactionType: 'receipt',
        voucherNumber: 'RV-R2-B',
        amount: 200.0,
        balanceAfter: 200.0,
        category: 'sales'));

    // ── Restricted (non-admin) user WITH a single branch-A grant → regression.
    final restrictedRoleId = await db.into(db.roles).insert(
          RolesCompanion.insert(
              name: 'كاشير R2', isSystemRole: const Value(false)),
        );
    restrictedUserId = await db.createUser(
      username: 'r2_cashier',
      password: 'test',
      displayName: 'R2 Cashier',
      roleId: restrictedRoleId,
    );
    await db.setUserBranchAccess(restrictedUserId, [branchAId]);

    // ── Mis-provisioned user: a NON-system role and NO setUserBranchAccess
    //    call (and no region grant). getUserAccessibleBranchIds therefore
    //    returns [] via the "no assignment" path (b), NOT the privileged
    //    early-return (a). This is the exact victim of the fail-open.
    final misRoleId = await db.into(db.roles).insert(
          RolesCompanion.insert(
              name: 'كاشير غير معيّن', isSystemRole: const Value(false)),
        );
    misProvisionedUserId = await db.createUser(
      username: 'r2_unassigned',
      // كلماتٌ متمايزة: `createUser` صار يرفض التكرار (§١). والتمايزُ لا يمسّ
      // نيّةَ الاختبار — نطاقُ الفرع يُقاس بالانتماء لا بكلمة المرور.
      password: 'test-unassigned',
      displayName: 'R2 Unassigned',
      roleId: misRoleId,
    );
    // NOTE: intentionally NO db.setUserBranchAccess(misProvisionedUserId, ...).

    // ── A branch-B-only NON-system user to OWN the branch-B shift. Because
    //    _resolveScopedUserIds ALWAYS folds in every system-role user, a shift
    //    owned by a system user would still be visible to a branch-A read — so
    //    the branch-B shift must belong to a plain (non-system) branch-B user to
    //    be genuinely out of branch A's scope; otherwise the branch-A shift
    //    regression guard would be vacuous.
    final branchBRoleId = await db.into(db.roles).insert(
          RolesCompanion.insert(
              name: 'كاشير B', isSystemRole: const Value(false)),
        );
    branchBUserId = await db.createUser(
      username: 'r2_cashier_b',
      password: 'test-cashier-b',
      displayName: 'R2 Cashier B',
      roleId: branchBRoleId,
    );
    await db.setUserBranchAccess(branchBUserId, [branchBId]);

    // Shifts (_getShifts scopes by userId via _resolveScopedUserIds). One owned
    // by the branch-A user (in scope for a branch-A read), one by the branch-B
    // user (out of scope). The branch-B row makes the mis-provisioned "zero
    // rows" assertion non-vacuous and the branch-A regression meaningful.
    shiftAId = await db.into(db.shifts).insert(ShiftsCompanion.insert(
        startTime: DateTime(2025, 5, 10, 8),
        userId: restrictedUserId,
        status: 'closed',
        branchId: Value(branchAId),
        globalId: const Value('gid-shift-r2-a')));
    shiftBId = await db.into(db.shifts).insert(ShiftsCompanion.insert(
        startTime: DateTime(2025, 5, 11, 8),
        userId: branchBUserId,
        status: 'closed',
        branchId: Value(branchBId),
        globalId: const Value('gid-shift-r2-b')));
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

  /// Every scoped endpoint returns a uniform `count` field.
  Future<int> count(String path, {int? userId}) async =>
      (await getJson(path, userId: userId))['count'] as int;

  Set<int?> journalBranchIds(Map<String, dynamic> body) =>
      (body['journals'] as List)
          .map((j) => (j as Map<String, dynamic>)['branchId'] as int?)
          .toSet();

  // The six branch-scoped read endpoints. journals verifies Step B; the other
  // five verify Step C (the resolve-helper empty-list-drops-filter hazard).
  const endpoints = <String>[
    '/api/journals',
    '/api/sales',
    '/api/purchases',
    '/api/stock-movements',
    '/api/inventory-balances',
    '/api/safe-transactions',
  ];

  // ── Precondition — proves the test is NOT vacuous: the mis-provisioned user
  //    is genuinely non-privileged and reaches [] via the "no assignment" path.
  test(
      'precondition: mis-provisioned user is non-privileged with an EMPTY '
      'accessible-branch list (path b, not the privileged early-return)',
      () async {
    expect(await db.isFullBranchAccessUser(misProvisionedUserId), isFalse,
        reason: 'a plain كاشير role must NOT be treated as full-access');
    expect(await db.getUserAccessibleBranchIds(misProvisionedUserId), isEmpty,
        reason: 'no branch grant → [] via the mis-provisioned path, which is '
            'indistinguishable from the privileged [] without the helper');
  });

  // ── THE FIX — a mis-provisioned user must read ZERO rows on ALL six
  //    endpoints (journals = Step B; the other five = Step C).
  for (final path in endpoints) {
    test('mis-provisioned user reads ZERO rows from $path (fail-closed)',
        () async {
      expect(await count(path, userId: misProvisionedUserId), 0,
          reason: '$path must return no rows for a zero-assignment '
              'non-privileged user — not the whole table');
    });
  }

  // ── THE FIX (two additional fail-open endpoints found by the committee).
  //    A mis-provisioned user must read ZERO rows from cost-centers and shifts.
  test('mis-provisioned user reads ZERO cost centers from /api/cost_centers '
      '(fail-closed)', () async {
    // _getCostCenters filters `id == -1` for the sentinel branch → matches
    // nothing (autoincrement ids start at 1). There is NO NULL-branch/shared
    // carve-out in the handler, so the exact semantics are an empty table.
    final body =
        await getJson('/api/cost_centers', userId: misProvisionedUserId);
    expect(body['count'], 0,
        reason: '/api/cost_centers must return no rows for a zero-assignment '
            'non-privileged user — not the whole table');
    final ids = (body['cost_centers'] as List)
        .map((c) => (c as Map<String, dynamic>)['id'] as int)
        .toSet();
    expect(ids.contains(ccBId), isFalse,
        reason: "branch-B's cost center must never leak to a mis-provisioned "
            'user');
  });

  test('mis-provisioned user reads ZERO shifts from /api/shifts (fail-closed)',
      () async {
    // _resolveScopedUserIds returns [-1] for the sentinel → `userId IN (-1)`
    // matches nothing, so no system-role user's shift cash/variance leaks.
    expect(await count('/api/shifts', userId: misProvisionedUserId), 0,
        reason: "/api/shifts must return no rows for a zero-assignment "
            "non-privileged user — not every system user's shift");
  });

  // ── Regression guard #0b: the two new fail-closed branches must not
  //    over-restrict a privileged admin (userId==1) — full access is preserved.
  test('regression: admin (userId=1) still sees cost centers and shifts',
      () async {
    final ccBody = await getJson('/api/cost_centers', userId: 1);
    final ccIds = (ccBody['cost_centers'] as List)
        .map((c) => (c as Map<String, dynamic>)['id'] as int)
        .toSet();
    expect(ccIds.containsAll({ccAId, ccBId}), isTrue,
        reason: "admin has full access → both branches' cost centers visible");

    final shBody = await getJson('/api/shifts', userId: 1);
    final shIds = (shBody['shifts'] as List)
        .map((s) => (s as Map<String, dynamic>)['id'] as int)
        .toSet();
    expect(shIds.containsAll({shiftAId, shiftBId}), isTrue,
        reason: 'admin has full access → shifts from both branches visible');
  });

  // ── Regression guard #0c: a legit branch-A user still sees branch-A's cost
  //    center and shift (must NOT over-restrict a branch that HAS a cost center
  //    / scoped users), and never branch-B's.
  test('regression: legit branch-A user sees branch-A cost center & shift only',
      () async {
    final ccBody = await getJson('/api/cost_centers', userId: restrictedUserId);
    final ccIds = (ccBody['cost_centers'] as List)
        .map((c) => (c as Map<String, dynamic>)['id'] as int)
        .toSet();
    expect(ccIds, {ccAId},
        reason: 'branch A resolves to cost center A only — never B, never all');

    final shBody = await getJson('/api/shifts', userId: restrictedUserId);
    final shUserIds = (shBody['shifts'] as List)
        .map((s) => (s as Map<String, dynamic>)['userId'] as int)
        .toSet();
    expect(shUserIds, {restrictedUserId},
        reason: 'branch-A scope = branch-A users (+ system) → the branch-A '
            "shift is visible, the branch-B user's shift is scoped out");
  });

  // ── Regression guard #1: privileged admin (userId==1) keeps full access.
  test('regression: admin (userId=1) still sees every branch (full access)',
      () async {
    final body = await getJson('/api/journals?branch_id=$branchBId', userId: 1);
    expect(journalBranchIds(body).contains(branchBId), isTrue,
        reason: 'admin has [] == full access → requested branch B honored');
    // No branch_id → no cap → both branches visible across a Step-C endpoint.
    expect(await count('/api/sales', userId: 1), 2,
        reason: 'full-access user (branchId==null) sees all sales, unscoped');
  });

  // ── Regression guard #2: a legit branch-A user still sees branch-A rows
  //    (Step C must not over-restrict a user whose branch HAS warehouses/safes).
  test('regression: legit branch-A user still sees branch-A rows only',
      () async {
    final journals = await getJson('/api/journals', userId: restrictedUserId);
    expect(journalBranchIds(journals), {branchAId},
        reason: 'clamped to branch A → only the A journal, never B');

    final sales = await getJson('/api/sales', userId: restrictedUserId);
    final saleWarehouses = (sales['sales'] as List)
        .map((s) => (s as Map<String, dynamic>)['warehouseId'] as int?)
        .toSet();
    expect(saleWarehouses, {whAId},
        reason: 'Step C resolves branch A → [whA] (non-empty, untouched) → '
            'A sales visible, B sales scoped out');
  });
}
