// D-PERF-2 — treasury report analytics pushed into SQL aggregates.
//
// getTreasuryReportAnalytics / getPerUserTreasurySummary used to load every
// date-ranged safe_transaction (joined to users) into Dart and sum in a loop.
// This characterization test pins the exact numbers — receipts/payments only
// ('receipt'/'payment'), neutral types (withdrawal/transfer/closing) excluded
// from sums but counted in the per-user txn count, soft-deleted + out-of-range
// rows excluded — so the SQL rewrite provably preserves behavior.

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int safeId;
  late int userA;
  late int userB;

  final start = DateTime(2026, 1, 1);
  final end = DateTime(2026, 1, 31);

  setUp(() async {
    db = AppDatabase.forTesting();
    safeId = (await db.getDefaultSafeByType('cash'))!.id;
    final role = await db.into(db.roles).insert(
        RolesCompanion.insert(name: 'موظف خزينة', isSystemRole: const Value(false)));
    userA = await db.createUser(
        username: 'user_a', password: 'pass123', displayName: 'User A', roleId: role);
    userB = await db.createUser(
        // مغايرةٌ عن `user_a` — `createUser` يرفض تكرارَ كلمة المرور (§١).
        username: 'user_b', password: 'pass123-b', displayName: 'User B', roleId: role);

    Future<void> tx(String type, double amount, int uid,
        {DateTime? at, bool deleted = false}) async {
      await db.into(db.safeTransactions).insert(SafeTransactionsCompanion.insert(
            voucherNumber: 'V',
            safeId: safeId,
            transactionType: type,
            category: 'c',
            amount: amount,
            balanceAfter: 0,
            userId: Value(uid),
            createdAt: Value(at ?? DateTime(2026, 1, 15)),
            deletedAt: Value(deleted ? DateTime(2026, 1, 16) : null),
          ));
    }

    await tx('receipt', 100, userA);
    await tx('payment', 40, userA);
    await tx('withdrawal', 500, userA); // neutral: excluded from sums
    await tx('receipt', 200, userB);
    await tx('payment', 60, userB);
    await tx('transfer', 300, userB); // neutral: excluded from sums
    await tx('receipt', 999, userA, deleted: true); // soft-deleted → excluded
    await tx('receipt', 888, userA, at: DateTime(2025, 12, 1)); // out of range
  });

  tearDown(() async => db.close());

  test('getTreasuryReportAnalytics sums only receipts/payments in range',
      () async {
    final a = await db.getTreasuryReportAnalytics(start, end);
    expect(a.totalReceipts, 300);
    expect(a.totalPayments, 100);
    expect(a.netFlow, 200);
  });

  test('getPerUserTreasurySummary groups per user, counts neutral rows',
      () async {
    final rows = await db.getPerUserTreasurySummary(start, end);
    final a = rows.firstWhere((r) => r.userId == userA);
    final b = rows.firstWhere((r) => r.userId == userB);

    expect(a.totalReceipts, 100);
    expect(a.totalPayments, 40);
    expect(a.transactionCount, 3); // receipt + payment + withdrawal

    expect(b.totalReceipts, 200);
    expect(b.totalPayments, 60);
    expect(b.transactionCount, 3); // receipt + payment + transfer
  });
}
