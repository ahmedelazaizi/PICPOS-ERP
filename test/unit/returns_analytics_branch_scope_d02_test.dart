// ═══════════════════════════════════════════════════════════════════════════
// Spec 151 · Wave 2 · D-02 — Returns analytics must honour allowedBranchIds
// ═══════════════════════════════════════════════════════════════════════════
//
// Pre-fix: getSalesReturnsAnalytics / getPurchaseReturnsAnalytics read
// `FROM safe_transactions st` with no branch scope. safe_transactions has no
// branch_id column, so a branch-restricted user saw COMPANY-WIDE return totals
// beside branch-scoped sales KPIs — an inflated / misleading return rate.
//
// Fix (D-02): branch is reachable via safe_transactions.safe_id → safes.branch_id.
// When `allowedBranchIds` is passed, JOIN safes and apply the standard auth-scope
// filter (null = company-wide/userId=1; {} = fail-closed; {ids} = that branch set
// OR NULL-branch head-office safes). These tests pin that behaviour: branch-B
// returns must not leak into a branch-A scope.

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int branchAId;
  late int branchBId;
  late int safeAId;
  late int safeBId;

  final from = DateTime(2025, 3, 1);
  final to = DateTime(2025, 3, 31);
  final at = DateTime(2025, 3, 10, 12, 0, 0);

  Future<void> insertReturnTxn({
    required String voucher,
    required int safeId,
    required String referenceType,
    required int referenceId,
    required double amount,
    String category = 'return',
  }) async {
    await db.into(db.safeTransactions).insert(
          SafeTransactionsCompanion.insert(
            voucherNumber: voucher,
            safeId: safeId,
            transactionType: 'payment',
            category: category,
            amount: amount,
            balanceAfter: 0,
            referenceType: Value(referenceType),
            referenceId: Value(referenceId),
            createdAt: Value(at),
          ),
        );
  }

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();

    branchAId = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'فرع A',
            globalId: const Value('gid-br-d02-a'),
          ),
        );
    branchBId = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'فرع B',
            globalId: const Value('gid-br-d02-b'),
          ),
        );

    safeAId = await db.into(db.safes).insert(
          SafesCompanion.insert(
            name: 'صندوق A',
            branchId: Value(branchAId),
            globalId: const Value('gid-safe-d02-a'),
          ),
        );
    safeBId = await db.into(db.safes).insert(
          SafesCompanion.insert(
            name: 'صندوق B',
            branchId: Value(branchBId),
            globalId: const Value('gid-safe-d02-b'),
          ),
        );
  });

  tearDown(() => db.close());

  group('D-02 getSalesReturnsAnalytics honours allowedBranchIds', () {
    setUp(() async {
      // Branch A: one returns-screen return (100).
      await insertReturnTxn(
        voucher: 'SR-A-1',
        safeId: safeAId,
        referenceType: 'sales_return',
        referenceId: 5001,
        amount: 100,
      );
      // Branch B: one returns-screen return (250) + one POS-invoice return (50).
      await insertReturnTxn(
        voucher: 'SR-B-1',
        safeId: safeBId,
        referenceType: 'sales_return',
        referenceId: 6001,
        amount: 250,
      );
      await insertReturnTxn(
        voucher: 'SR-B-2',
        safeId: safeBId,
        referenceType: 'sales_invoice',
        referenceId: 6002,
        amount: 50,
        category: 'return',
      );
    });

    test('scope={A} counts only branch-A returns (branch-B excluded)',
        () async {
      final res = await db.getSalesReturnsAnalytics(
        from: from,
        to: to,
        allowedBranchIds: {branchAId},
      );
      expect(res.total, 100,
          reason: 'only صندوق A returns; branch-B 250+50 must be excluded');
      expect(res.count, 1);
    });

    test('scope=null is company-wide (unchanged behaviour)', () async {
      final res = await db.getSalesReturnsAnalytics(from: from, to: to);
      expect(res.total, 400, reason: '100 + 250 + 50 across all branches');
      expect(res.count, 3);
    });

    test('scope={} fails closed (no returns leak)', () async {
      final res = await db.getSalesReturnsAnalytics(
        from: from,
        to: to,
        allowedBranchIds: <int>{},
      );
      expect(res.total, 0);
      expect(res.count, 0);
    });
  });

  group('D-02 getPurchaseReturnsAnalytics honours allowedBranchIds', () {
    setUp(() async {
      await insertReturnTxn(
        voucher: 'PR-A-1',
        safeId: safeAId,
        referenceType: 'purchase_return',
        referenceId: 7001,
        amount: 80,
      );
      await insertReturnTxn(
        voucher: 'PR-B-1',
        safeId: safeBId,
        referenceType: 'purchase_return',
        referenceId: 8001,
        amount: 300,
      );
    });

    test('scope={A} counts only branch-A purchase returns', () async {
      final res = await db.getPurchaseReturnsAnalytics(
        from: from,
        to: to,
        allowedBranchIds: {branchAId},
      );
      expect(res.total, 80, reason: 'branch-B 300 must be excluded');
      expect(res.count, 1);
    });

    test('scope=null is company-wide (unchanged behaviour)', () async {
      final res = await db.getPurchaseReturnsAnalytics(from: from, to: to);
      expect(res.total, 380);
      expect(res.count, 2);
    });

    test('scope={} fails closed', () async {
      final res = await db.getPurchaseReturnsAnalytics(
        from: from,
        to: to,
        allowedBranchIds: <int>{},
      );
      expect(res.total, 0);
      expect(res.count, 0);
    });
  });
}
