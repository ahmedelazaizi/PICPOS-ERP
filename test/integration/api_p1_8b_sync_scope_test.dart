// ═══════════════════════════════════════════════════════════════════════════
// Spec 151 · P1-8b — token-OMISSION closure on the sync/read path.
//
// P1-8 (Track 1) closed the FORGERY vector: identity now comes only from a
// signed session token, so a bearer holder can no longer forge uid=1. It did
// NOT close OMISSION: a tokenless caller (no verified identity) still read the
// requested/full set. P1-8b closes omission for TRANSACTIONAL reads while
// keeping REFERENCE/master reads open (the tokenless provisioning path —
// ClientFirstSyncService / boot delta-pull, pre-login — must read shared master
// data to seed a new client, or setup bricks).
//
// This suite proves that split on BOTH surfaces:
//   • GET /api/sync/pull?table=X  — transactional tables (incl. the
//     column-agnostic safe_transactions) return empty + serverTime:null with no
//     identity; reference tables (branches/products) still return in full.
//   • the individual transactional GETs (/api/journals, /api/sales) return zero
//     rows with no identity; the reference GET (/api/branches) stays full; a
//     restricted uid is clamped to its own branch (D-06 carry-over).
//
// Harness modeled on api_branch_scope_d06_test / api_branch_scope_residual2_test:
// buildRouter() does NOT wire ApiAuthMiddleware, so the userId is injected
// DIRECTLY on the request context. NO userId injected == "no verified identity"
// (the omission case). An admin (userId==1 → full access) or a restricted uid is
// injected for the positive cases.
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
  late int restrictedUserId; // access to branch A only

  setUp(() async {
    db = AppDatabase.forTesting();
    handler = ApiHandler(db);

    branchAId = await db.into(db.branches).insert(BranchesCompanion.insert(
        name: 'فرع A', globalId: const Value('gid-br-p18b-a')));
    branchBId = await db.into(db.branches).insert(BranchesCompanion.insert(
        name: 'فرع B', globalId: const Value('gid-br-p18b-b')));

    // A warehouse + safe per branch.
    whAId = await db.into(db.warehouses).insert(WarehousesCompanion.insert(
        name: 'مخزن A',
        branchId: Value(branchAId),
        globalId: const Value('gid-wh-p18b-a')));
    whBId = await db.into(db.warehouses).insert(WarehousesCompanion.insert(
        name: 'مخزن B',
        branchId: Value(branchBId),
        globalId: const Value('gid-wh-p18b-b')));
    safeAId = await db.into(db.safes).insert(SafesCompanion.insert(
        name: 'صندوق A',
        branchId: Value(branchAId),
        globalId: const Value('gid-safe-p18b-a')));
    safeBId = await db.into(db.safes).insert(SafesCompanion.insert(
        name: 'صندوق B',
        branchId: Value(branchBId),
        globalId: const Value('gid-safe-p18b-b')));

    // NULL-branch reference master data — every paired client needs this
    // regardless of branch, so it must survive the tokenless deny (anti-brick).
    await db.into(db.products).insert(ProductsCompanion.insert(
        code: 'P-P18B-1', name: 'منتج تجريبي'));

    // One TRANSACTIONAL row per branch across the endpoints under test. Seeding a
    // branch-B row is what makes the "no identity → empty" assertions non-vacuous
    // — without the deny these rows would LEAK to a tokenless caller.
    await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
        invoiceNumber: 'SI-P18B-A',
        warehouseId: whAId,
        userId: 1,
        invoiceDate: DateTime(2025, 5, 10),
        branchId: Value(branchAId),
        total: const Value(100)));
    await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
        invoiceNumber: 'SI-P18B-B',
        warehouseId: whBId,
        userId: 1,
        invoiceDate: DateTime(2025, 5, 11),
        branchId: Value(branchBId),
        total: const Value(200)));

    await db.into(db.journalEntries).insert(JournalEntriesCompanion.insert(
        entryNumber: 'JE-P18B-A',
        entryDate: DateTime(2025, 5, 10),
        branchId: Value(branchAId),
        globalId: const Value('gid-je-p18b-a')));
    await db.into(db.journalEntries).insert(JournalEntriesCompanion.insert(
        entryNumber: 'JE-P18B-B',
        entryDate: DateTime(2025, 5, 11),
        branchId: Value(branchBId),
        globalId: const Value('gid-je-p18b-b')));

    // safe_transactions has NO branch column — its sync-pull deny cannot rely on
    // per-column scoping, only on the transactional-table identity gate. THE key
    // column-agnostic case.
    await db.into(db.safeTransactions).insert(SafeTransactionsCompanion.insert(
        safeId: safeAId,
        transactionType: 'receipt',
        voucherNumber: 'RV-P18B-A',
        amount: 100.0,
        balanceAfter: 100.0,
        category: 'sales'));
    await db.into(db.safeTransactions).insert(SafeTransactionsCompanion.insert(
        safeId: safeBId,
        transactionType: 'receipt',
        voucherNumber: 'RV-P18B-B',
        amount: 200.0,
        balanceAfter: 200.0,
        category: 'sales'));

    // A held order (also branch-column-less, also on the transactional denylist).
    await db.into(db.heldOrders).insert(HeldOrdersCompanion.insert(
        holdNumber: 'HOLD-P18B-1'));

    // Restricted (non-admin) user with a single branch-A access grant (D-06).
    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(
              name: 'كاشير P18B', isSystemRole: const Value(false)),
        );
    restrictedUserId = await db.createUser(
      username: 'p18b_cashier',
      password: 'test',
      displayName: 'P18B Cashier',
      roleId: roleId,
    );
    await db.setUserBranchAccess(restrictedUserId, [branchAId]);
  });

  tearDown(() => db.close());

  /// GET /api/sync/pull?table=[table] through the real router, optionally
  /// injecting a validated userId (no auth middleware in buildRouter).
  Future<Map<String, dynamic>> pull(String table, {int? userId}) async {
    final resp = await handler.buildRouter().call(shelf.Request(
          'GET',
          Uri.parse('http://localhost/api/sync/pull?table=$table'),
          context: userId != null ? {ApiUserCtx.userIdKey: userId} : const {},
        ));
    final body = await resp.readAsString();
    expect(resp.statusCode, 200, reason: 'pull $table failed: $body');
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// GET any JSON endpoint through the real router.
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

  List<dynamic> rowsOf(Map<String, dynamic> body) => body['rows'] as List;

  // ── Delta pull · TRANSACTIONAL · NO identity → empty + serverTime null ──────

  test(
      'sync/pull sales_invoices with NO identity → empty rows, serverTime null',
      () async {
    final body = await pull('sales_invoices');
    expect(rowsOf(body), isEmpty,
        reason: 'a tokenless caller must not read any transactional rows');
    expect(body['count'], 0);
    expect(body['serverTime'], isNull,
        reason: 'no forward serverTime → a client ignoring the skip cannot '
            'advance its watermark and strand its post-login backfill');
  });

  test(
      'sync/pull safe_transactions (NO branch column) with NO identity → empty '
      '— the column-agnostic deny',
      () async {
    // safe_transactions has no branch_id, so per-column scoping cannot protect
    // it; only the transactional-table identity gate can. This is the key case.
    final body = await pull('safe_transactions');
    expect(rowsOf(body), isEmpty,
        reason: 'safe_transactions must be denied by the transactional gate, '
            'not by a (nonexistent) branch column');
    expect(body['count'], 0);
    expect(body['serverTime'], isNull);
  });

  test('sync/pull journal_entries with NO identity → empty', () async {
    final body = await pull('journal_entries');
    expect(rowsOf(body), isEmpty);
    expect(body['count'], 0);
    expect(body['serverTime'], isNull);
  });

  test('sync/pull held_orders (NO branch column) with NO identity → empty',
      () async {
    final body = await pull('held_orders');
    expect(rowsOf(body), isEmpty,
        reason: 'held_orders is on the transactional denylist despite having '
            'no branch column');
    expect(body['count'], 0);
    expect(body['serverTime'], isNull);
  });

  // ── Delta pull · REFERENCE · NO identity → full (anti-brick) ────────────────

  test(
      'sync/pull branches with NO identity → FULL rows (anti-brick: tokenless '
      'provisioning must read master data)',
      () async {
    final body = await pull('branches');
    expect(rowsOf(body).length, greaterThanOrEqualTo(2),
        reason: 'reference/master tables must stay readable so a new client can '
            'seed itself before any user logs in');
    expect(body['serverTime'], isNotNull,
        reason: 'a real dump advances the watermark normally');
  });

  test('sync/pull products with NO identity → FULL rows (anti-brick)',
      () async {
    final body = await pull('products');
    expect(rowsOf(body), isNotEmpty,
        reason: 'products is universal master data — not gated by identity');
  });

  // ── Delta pull · TRANSACTIONAL · WITH admin identity → rows returned ────────
  //    Proves the "no identity → empty" result above is a genuine DENY, not an
  //    empty table.

  test('sync/pull sales_invoices WITH admin identity → non-empty', () async {
    final body = await pull('sales_invoices', userId: 1);
    expect(rowsOf(body), isNotEmpty,
        reason: 'an admin (full access) pulls the seeded transactional rows — '
            'so the tokenless empty result was a deny, not an empty table');
    expect(body['serverTime'], isNotNull);
  });

  test('sync/pull safe_transactions WITH admin identity → non-empty', () async {
    final body = await pull('safe_transactions', userId: 1);
    expect(rowsOf(body), isNotEmpty,
        reason: 'confirms the column-agnostic table really holds rows that the '
            'tokenless deny suppressed');
  });

  // ── Individual endpoints ───────────────────────────────────────────────────

  test('individual /api/journals with NO identity → zero rows', () async {
    final body = await getJson('/api/journals');
    expect(body['count'], 0,
        reason: 'transactional individual GET fails closed with no identity');
    expect((body['journals'] as List), isEmpty);
  });

  test('individual /api/sales with NO identity → zero rows', () async {
    final body = await getJson('/api/sales');
    expect(body['count'], 0,
        reason: 'no identity → sentinel branch → warehouseId IN (-1) → nothing');
    expect((body['sales'] as List), isEmpty);
  });

  test(
      'individual /api/branches with NO identity → FULL (reference endpoint, '
      'anti-brick)',
      () async {
    final body = await getJson('/api/branches');
    expect(body['count'], greaterThanOrEqualTo(2),
        reason: 'a reference endpoint stays open for tokenless provisioning');
    final ids = (body['branches'] as List)
        .map((b) => (b as Map<String, dynamic>)['id'] as int)
        .toSet();
    expect(ids.containsAll({branchAId, branchBId}), isTrue);
  });

  test(
      'individual /api/journals with a RESTRICTED uid → clamped to their branch '
      '(D-06 carry-over)',
      () async {
    final body = await getJson('/api/journals', userId: restrictedUserId);
    final branchIds = (body['journals'] as List)
        .map((j) => (j as Map<String, dynamic>)['branchId'] as int?)
        .toSet();
    expect(branchIds.contains(branchAId), isTrue,
        reason: 'the branch-A user sees the branch-A journal');
    expect(branchIds.contains(branchBId), isFalse,
        reason: 'and never the foreign branch-B journal');
  });
}
