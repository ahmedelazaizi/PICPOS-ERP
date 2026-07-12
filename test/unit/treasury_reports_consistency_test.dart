// ═══════════════════════════════════════════════════════════════════════════
// Spec 106 — Treasury report aggregations are mutually consistent
// ═══════════════════════════════════════════════════════════════════════════
//
// Field complaint: opening the same date range from three different report
// screens showed three different total-receipts numbers. Root cause:
//
//   • getTreasurySummary           used SQL CASE WHEN 'receipt'/'payment'
//   • getTreasuryAnalytics         used the same SQL pattern
//   • getTreasuryReportAnalytics   used Dart fold that treated EVERY
//                                  non-receipt as payment (including
//                                  withdrawal/transfer/closing)
//
// Result: a shift close with 200 withdrawal pushed
// getTreasuryReportAnalytics.totalPayments 200 higher than the other two.
//
// This test pins the post-Spec-106 invariant: for any input, the three
// functions agree on totalReceipts and totalPayments to within 0.001.

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int safeId;
  late int userId;

  Future<void> insertTxn(
    String voucher,
    String type,
    double amount, {
    String category = 'sale',
    DateTime? at,
    bool deleted = false,
  }) async {
    await db.into(db.safeTransactions).insert(
          SafeTransactionsCompanion.insert(
            voucherNumber: voucher,
            safeId: safeId,
            transactionType: type,
            category: category,
            amount: amount,
            balanceAfter: 0,
            userId: Value(userId),
            createdAt: Value(at ?? DateTime(2025, 1, 15, 10, 0, 0)),
            deletedAt: deleted
                ? Value(DateTime(2025, 1, 15, 11, 0, 0))
                : const Value.absent(),
          ),
        );
  }

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();

    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(
            name: 'cashier-106-c',
            isSystemRole: const Value(false),
          ),
        );
    userId = await db.createUser(
      username: 'cashier_106_c',
      password: 'pw',
      displayName: 'F106C',
      roleId: roleId,
    );
    safeId = await db.into(db.safes).insert(
          SafesCompanion.insert(
            name: 'cash-106-c',
            safeType: const Value('cash'),
            balance: const Value(0),
            globalId: const Value('gid-safe-106-c'),
          ),
        );
  });

  tearDown(() => db.close());

  test('three report functions return identical totals for the same range',
      () async {
    // Build a representative mix:
    //   - 2 receipts (one normal, one deleted)
    //   - 2 payments (one normal, one deleted)
    //   - 1 withdrawal (shift close)
    //   - 1 transfer
    //   - 1 closing audit row
    await insertTxn('R-1', 'receipt', 100);
    await insertTxn('R-DEL', 'receipt', 50, deleted: true);
    await insertTxn('P-1', 'payment', 30);
    await insertTxn('P-DEL', 'payment', 20, deleted: true);
    await insertTxn('W-1', 'withdrawal', 200, category: 'shift_closing');
    await insertTxn('T-1', 'transfer', 80);
    await insertTxn('C-1', 'closing', 150);

    final from = DateTime(2025, 1, 15);
    final to = DateTime(2025, 1, 16);

    final summary = await db.getTreasurySummary(fromDate: from, toDate: to);
    final analytics = await db.getTreasuryAnalytics();
    final report =
        await db.getTreasuryReportAnalytics(from, to, safeId: safeId);

    // Expected after Spec 106:
    //   totalReceipts = 100 (only R-1; R-DEL excluded)
    //   totalPayments = 30  (only P-1; P-DEL excluded; W/T/C neutral)
    expect(summary.totalReceipts, closeTo(100, 0.001));
    expect(summary.totalPayments, closeTo(30, 0.001));

    expect(analytics.totalReceipts, closeTo(100, 0.001));
    expect(analytics.totalPayments, closeTo(30, 0.001));

    expect(report.totalReceipts, closeTo(100, 0.001));
    expect(report.totalPayments, closeTo(30, 0.001));

    // Cross-function equality (the actual Spec 106 invariant).
    expect(summary.totalReceipts, analytics.totalReceipts);
    expect(summary.totalReceipts, report.totalReceipts);
    expect(summary.totalPayments, analytics.totalPayments);
    expect(summary.totalPayments, report.totalPayments);
  });

  test('shift-close withdrawal does NOT show as a period expense', () async {
    // The original field-reported bug: closing a shift posted a 200
    // withdrawal, then the treasury report showed it under "مصروفات الفترة".
    await insertTxn('RCT-100', 'receipt', 100);
    await insertTxn('WDR-200', 'withdrawal', 200, category: 'shift_closing');

    final report = await db.getTreasuryReportAnalytics(
      DateTime(2025, 1, 15),
      DateTime(2025, 1, 16),
    );

    expect(report.periodExpense, 0,
        reason: 'shift_closing withdrawal must not inflate periodExpense');
    expect(report.totalReceipts, 100);
  });
}
