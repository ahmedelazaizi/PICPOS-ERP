// ═══════════════════════════════════════════════════════════════════════════
// Spec 151 · Wave A · D-01 (BLOCKER) — Treasury report must honour the caller's
// branch scope (cross-branch financial leak).
// ═══════════════════════════════════════════════════════════════════════════
//
// Pre-fix: getTransactionsByDateRange / getTreasuryReportAnalytics /
// getPerUserTreasurySummary accepted only safeId/costCenterId/safeIds. The
// treasury report screen seeded `_selectedBranchId` but NOT `_branchSafeIds`
// (it was only populated when the user manually picked a branch), so on first
// load safeIds was null and EVERY branch's vouchers were aggregated — a
// branch-scoped manager holding reportsTreasury saw every branch's voucher
// detail + period totals.
//
// Fix: an authoritative `allowedBranchIds` cap threaded screen → repo → DAO,
// reusing the canonical _buildAuthScopeFilter (safe_transactions has no
// branch_id; branch is reachable via safe_id → safes.branch_id). Semantics
// match D-02 / the accounting KPIs exactly:
//   null  = company-wide (admin / userId=1 / mirror / elevated) — no cap
//   {}    = fail-closed (no rows leak)
//   {ids} = those branches OR NULL-branch shared (head-office) safes
//
// The screen reads transactions through ReportingRepositoryImpl (which builds
// its OWN query — it does NOT delegate to the DAO), so that path is tested here
// too, not just the DAO analytics helpers.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/repositories/reporting_repository_impl.dart';

void main() {
  late AppDatabase db;
  late ReportingRepositoryImpl repo;
  late int branchAId;
  late int branchBId;
  late int safeAId; // branch A
  late int safeBId; // branch B
  late int safeSharedId; // NULL branch (head-office / legacy)

  final from = DateTime(2025, 5, 1);
  final to = DateTime(2025, 5, 31);
  final at = DateTime(2025, 5, 10, 12, 0, 0);

  Future<void> insertTxn({
    required String voucher,
    required int safeId,
    required String type, // receipt | payment
    required double amount,
    int userId = 7,
  }) async {
    await db.into(db.safeTransactions).insert(
          SafeTransactionsCompanion.insert(
            voucherNumber: voucher,
            safeId: safeId,
            transactionType: type,
            category: 'other',
            amount: amount,
            balanceAfter: 0,
            userId: Value(userId),
            createdAt: Value(at),
          ),
        );
  }

  setUp(() async {
    db = AppDatabase.forTesting();
    repo = ReportingRepositoryImpl(db);

    branchAId = await db.into(db.branches).insert(
        BranchesCompanion.insert(name: 'فرع A', globalId: const Value('gid-br-d01-a')));
    branchBId = await db.into(db.branches).insert(
        BranchesCompanion.insert(name: 'فرع B', globalId: const Value('gid-br-d01-b')));

    safeAId = await db.into(db.safes).insert(SafesCompanion.insert(
        name: 'صندوق A',
        branchId: Value(branchAId),
        balance: const Value(1000), // cash
        globalId: const Value('gid-safe-d01-a')));
    safeBId = await db.into(db.safes).insert(SafesCompanion.insert(
        name: 'صندوق B',
        branchId: Value(branchBId),
        balance: const Value(5000), // cash
        globalId: const Value('gid-safe-d01-b')));
    safeSharedId = await db.into(db.safes).insert(SafesCompanion.insert(
        name: 'صندوق مشترك',
        balance: const Value(200), // cash, branchId NULL (shared)
        globalId: const Value('gid-safe-d01-shared')));

    // safe_transactions.user_id FKs to users — seed the two actors the per-user
    // summary asserts on (only the admin user 1 is seeded). FK is enforced in
    // tests now (mirrors production).
    for (final uid in [11, 22]) {
      await db.into(db.users).insert(UsersCompanion.insert(
          id: Value(uid),
          username: 'usr$uid',
          passwordHash: 'x',
          displayName: 'U$uid'));
    }

    // Branch A: receipt 100. Branch B: receipt 250 + payment 40. Shared: 30.
    await insertTxn(voucher: 'A-R', safeId: safeAId, type: 'receipt', amount: 100, userId: 11);
    await insertTxn(voucher: 'B-R', safeId: safeBId, type: 'receipt', amount: 250, userId: 22);
    await insertTxn(voucher: 'B-P', safeId: safeBId, type: 'payment', amount: 40, userId: 22);
    await insertTxn(voucher: 'S-R', safeId: safeSharedId, type: 'receipt', amount: 30, userId: 11);
  });

  tearDown(() => db.close());

  group('getTransactionsByDateRange (screen path via ReportingRepositoryImpl)', () {
    test('scope={A} returns branch-A + NULL-branch shared, excludes branch-B', () async {
      final rows = await repo.getTransactionsByDateRange(from, to, allowedBranchIds: {branchAId});
      final safeIds = rows.map((r) => r.safeId).toSet();
      expect(safeIds, containsAll(<int>[safeAId, safeSharedId]));
      expect(safeIds.contains(safeBId), isFalse,
          reason: 'branch-B vouchers must not leak into a branch-A scope');
      expect(rows.length, 2);
    });

    test('scope=null returns every branch (unchanged company-wide behaviour)', () async {
      final rows = await repo.getTransactionsByDateRange(from, to);
      expect(rows.length, 4);
    });

    test('scope={} fails closed (no voucher leak)', () async {
      final rows = await repo.getTransactionsByDateRange(from, to, allowedBranchIds: <int>{});
      expect(rows, isEmpty);
    });
  });

  group('getTreasuryReportAnalytics honours allowedBranchIds', () {
    test('scope={A}: only branch-A + shared receipts (250/40 branch-B excluded)', () async {
      final a = await db.getTreasuryReportAnalytics(from, to, allowedBranchIds: {branchAId});
      expect(a.periodIncome, 130, reason: '100 (A) + 30 (shared); 250 (B) excluded');
      expect(a.periodExpense, 0, reason: '40 payment is branch-B → excluded');
      // Summary balance cards are scoped too (safe A 1000 + shared 200; B 5000 excluded).
      expect(a.cashBalance, 1200, reason: 'branch-B safe balance 5000 must not show');
    });

    test('scope=null: company-wide', () async {
      final a = await db.getTreasuryReportAnalytics(from, to);
      expect(a.periodIncome, 380, reason: '100 + 250 + 30');
      expect(a.periodExpense, 40);
      expect(a.cashBalance, 6200, reason: '1000 + 5000 + 200');
    });

    test('scope={} fails closed', () async {
      final a = await db.getTreasuryReportAnalytics(from, to, allowedBranchIds: <int>{});
      expect(a.periodIncome, 0);
      expect(a.periodExpense, 0);
      expect(a.cashBalance, 0, reason: 'no branch access → no balance shown');
    });
  });

  group('getPerUserTreasurySummary honours allowedBranchIds', () {
    test('scope={A}: user 22 (branch-B only) absent; user 11 present', () async {
      final rows = await db.getPerUserTreasurySummary(from, to, allowedBranchIds: {branchAId});
      final userIds = rows.map((r) => r.userId).toSet();
      expect(userIds.contains(22), isFalse, reason: 'user 22 only transacted on branch-B');
      expect(userIds.contains(11), isTrue);
      final u11 = rows.firstWhere((r) => r.userId == 11);
      expect(u11.totalReceipts, 130, reason: 'A 100 + shared 30');
    });

    test('scope={} fails closed', () async {
      final rows = await db.getPerUserTreasurySummary(from, to, allowedBranchIds: <int>{});
      expect(rows, isEmpty);
    });
  });
}
