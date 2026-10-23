// ═══════════════════════════════════════════════════════════════════════════
// Spec 106 — Treasury report aggregations exclude soft-deleted rows
// ═══════════════════════════════════════════════════════════════════════════
//
// Pre-fix: getTreasurySummary, getTreasuryAnalytics, and
// getTreasuryStatsByCategory used raw SQL aggregates without the
// `deleted_at IS NULL` clause, so a sales receipt that was later voided by
// the admin still counted toward totalReceipts. The transaction list view
// hid the row, but the totals card kept showing it — confusing the daily
// cash reconciliation.
//
// These tests pin the post-Spec-106 behaviour: deleted rows are excluded
// from every aggregate.

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int safeId;
  late int userId;

  Future<int> insertTxn({
    required String voucherNumber,
    required String type,
    required double amount,
    String category = 'sale',
    DateTime? at,
    bool deleted = false,
  }) async {
    final id = await db.into(db.safeTransactions).insert(
          SafeTransactionsCompanion.insert(
            voucherNumber: voucherNumber,
            safeId: safeId,
            transactionType: type,
            category: category,
            amount: amount,
            balanceAfter: 0,
            userId: Value(userId),
            createdAt: Value(at ?? DateTime(2025, 1, 15, 10, 0, 0)),
            deletedAt:
                deleted ? Value(DateTime(2025, 1, 15, 11, 0, 0)) : const Value.absent(),
          ),
        );
    return id;
  }

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();

    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(
            name: 'cashier-106-filters',
            isSystemRole: const Value(false),
          ),
        );
    userId = await db.createUser(
      username: 'cashier_106_filters',
      password: 'pw',
      displayName: 'F106F',
      roleId: roleId,
    );
    safeId = await db.into(db.safes).insert(
          SafesCompanion.insert(
            name: 'cash-106-f',
            safeType: const Value('cash'),
            balance: const Value(0),
            globalId: const Value('gid-safe-106-f'),
          ),
        );
  });

  tearDown(() => db.close());

  test('getTreasurySummary excludes soft-deleted rows', () async {
    await insertTxn(voucherNumber: 'KEEP-100', type: 'receipt', amount: 100);
    await insertTxn(
        voucherNumber: 'DEL-50', type: 'receipt', amount: 50, deleted: true);
    await insertTxn(voucherNumber: 'PAY-30', type: 'payment', amount: 30);
    await insertTxn(
        voucherNumber: 'DEL-PAY-20',
        type: 'payment',
        amount: 20,
        deleted: true);

    final summary = await db.getTreasurySummary(
      fromDate: DateTime(2025, 1, 15),
      toDate: DateTime(2025, 1, 16),
    );

    expect(summary.totalReceipts, 100,
        reason: 'KEEP-100 only; DEL-50 must be excluded');
    expect(summary.totalPayments, 30,
        reason: 'PAY-30 only; DEL-PAY-20 must be excluded');
  });

  test('getTreasuryAnalytics excludes soft-deleted rows', () async {
    await insertTxn(voucherNumber: 'KEEP-200', type: 'receipt', amount: 200);
    await insertTxn(
        voucherNumber: 'DEL-300', type: 'receipt', amount: 300, deleted: true);

    final analytics = await db.getTreasuryAnalytics();

    expect(analytics.totalReceipts, 200,
        reason: 'DEL-300 must be excluded from analytics');
    expect(analytics.periodIncome, 200);
  });

  test('getTreasuryStatsByCategory excludes soft-deleted rows', () async {
    await insertTxn(
        voucherNumber: 'KEEP-A', type: 'receipt', amount: 100, category: 'sale');
    await insertTxn(
        voucherNumber: 'DEL-A',
        type: 'receipt',
        amount: 50,
        category: 'sale',
        deleted: true);
    await insertTxn(
        voucherNumber: 'KEEP-B',
        type: 'payment',
        amount: 25,
        category: 'expense');

    final byCat = await db.getTreasuryStatsByCategory();

    expect(byCat['sale'], 100,
        reason: 'sale category sums KEEP-A only (50 was deleted)');
    expect(byCat['expense'], 25);
  });

  test('Spec 106 — withdrawal / transfer / closing are NEUTRAL in '
      'getTreasuryReportAnalytics (not counted as payments)', () async {
    await insertTxn(voucherNumber: 'RCT-1', type: 'receipt', amount: 100);
    await insertTxn(voucherNumber: 'PAY-1', type: 'payment', amount: 40);
    // Audit-only types that pre-Spec-106 leaked into totalPayments:
    await insertTxn(
        voucherNumber: 'WDR-1',
        type: 'withdrawal',
        amount: 200,
        category: 'shift_closing');
    await insertTxn(voucherNumber: 'TR-1', type: 'transfer', amount: 80);
    await insertTxn(
        voucherNumber: 'CLO-1', type: 'closing', amount: 150);

    final analytics = await db.getTreasuryReportAnalytics(
      DateTime(2025, 1, 15),
      DateTime(2025, 1, 16),
    );

    expect(analytics.totalReceipts, 100, reason: 'only receipt counts');
    expect(analytics.totalPayments, 40,
        reason: 'withdrawal+transfer+closing must NOT inflate payments');
  });
}
