// ═══════════════════════════════════════════════════════════════════════════
// Spec 151 · Wave C · D-04 (MINOR) — the sales «المحصّل» receipt-vouchers KPI
// must honour the caller's branch scope (cross-branch receipts leak).
// ═══════════════════════════════════════════════════════════════════════════
//
// Pre-fix: getReceiptVouchersTotal summed EVERY branch's collected receipts
// whenever `branchId` was null (a branch-restricted user with no branch picked
// saw the company-wide total in the sales screen's «المحصّل» card). Fix adds an
// authoritative `allowedBranchIds` cap, reusing the same _buildAuthScopeFilter
// subquery + fail-closed semantics as D-01/D-02:
//   null  = company-wide (admin / financial-manager / userId=1) — no cap
//   {}    = fail-closed (no receipts leak)
//   {ids} = safes in those branches OR NULL-branch (shared / head-office) safes
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int branchAId;
  late int branchBId;
  late int safeAId;
  late int safeBId;

  final from = DateTime(2025, 5, 1);
  final to = DateTime(2025, 5, 31);
  final at = DateTime(2025, 5, 10, 12, 0, 0);

  Future<void> insertTxn({
    required String voucher,
    required int safeId,
    required String type, // receipt | payment
    required double amount,
  }) async {
    await db.into(db.safeTransactions).insert(
          SafeTransactionsCompanion.insert(
            voucherNumber: voucher,
            safeId: safeId,
            transactionType: type,
            category: 'other',
            amount: amount,
            balanceAfter: 0,
            userId: const Value(7),
            createdAt: Value(at),
          ),
        );
  }

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();

    branchAId = await db.into(db.branches).insert(BranchesCompanion.insert(
        name: 'فرع A', globalId: const Value('gid-br-d04-a')));
    branchBId = await db.into(db.branches).insert(BranchesCompanion.insert(
        name: 'فرع B', globalId: const Value('gid-br-d04-b')));

    safeAId = await db.into(db.safes).insert(SafesCompanion.insert(
        name: 'صندوق A',
        branchId: Value(branchAId),
        globalId: const Value('gid-safe-d04-a')));
    safeBId = await db.into(db.safes).insert(SafesCompanion.insert(
        name: 'صندوق B',
        branchId: Value(branchBId),
        globalId: const Value('gid-safe-d04-b')));

    // Branch A: one 100 receipt. Branch B: one 250 receipt + a 999 PAYMENT
    // (payments must never enter the receipts total, regardless of scope).
    await insertTxn(voucher: 'A-R', safeId: safeAId, type: 'receipt', amount: 100);
    await insertTxn(voucher: 'B-R', safeId: safeBId, type: 'receipt', amount: 250);
    await insertTxn(voucher: 'B-P', safeId: safeBId, type: 'payment', amount: 999);
  });

  tearDown(() => db.close());

  test('allowedBranchIds={A} excludes branch-B receipts', () async {
    final total = await db.getReceiptVouchersTotal(
        from: from, to: to, allowedBranchIds: {branchAId});
    expect(total, closeTo(100, 0.001),
        reason: 'only branch-A receipt 100; branch-B receipt 250 must not leak');
  });

  test('allowedBranchIds=null is company-wide (both branches)', () async {
    final total = await db.getReceiptVouchersTotal(from: from, to: to);
    expect(total, closeTo(350, 0.001),
        reason: '100 (A) + 250 (B); the 999 payment is not a receipt');
  });

  test('allowedBranchIds={} fails closed (0, no receipts leak)', () async {
    final total = await db.getReceiptVouchersTotal(
        from: from, to: to, allowedBranchIds: <int>{});
    expect(total, 0.0, reason: 'no branch access → no receipts shown');
  });

  // Sanity: prove branch B genuinely holds a receipt (so the {A} exclusion
  // above is a real filter, not an empty-data false pass).
  test('allowedBranchIds={B} returns only branch-B receipt (control)', () async {
    final total = await db.getReceiptVouchersTotal(
        from: from, to: to, allowedBranchIds: {branchBId});
    expect(total, closeTo(250, 0.001));
  });
}
