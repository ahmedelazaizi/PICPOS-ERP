// ═══════════════════════════════════════════════════════════════════════════
// Spec 149 pre-deploy batch B12-4 — FIL-2 branch-scope read-leak on the
// invoice-DETAIL report tables
// ═══════════════════════════════════════════════════════════════════════════
//
// getSalesByDateRange (sales_dao.dart) and getPurchasesWithSupplierByDateRange
// (purchase_reports_dao.dart) are used directly by the tax/sales/purchases
// report screens and were NOT branch-scoped, unlike the accounting_reports_dao
// methods fixed in B12-1. A branch-restricted user (limited via
// user_branch_access) could read EVERY branch's invoices through those report
// screens. Fixed by threading a new `allowedBranchIds` param through both DAO
// methods (expressed with Drift query-builder expressions, since both methods
// use the builder, not raw SQL). Contract mirrors B12-1's
// `_buildAuthScopeFilter` (see BranchScope in
// lib/data/providers/branch_scope_provider.dart):
//   allowedBranchIds == null  → no restriction (full access)
//   allowedBranchIds == {}    → match NOTHING (fail-closed)
//   allowedBranchIds == {ids} → branch_id IN (ids) OR branch_id IS NULL
//
// This test exercises getSalesByDateRange as the representative site;
// getPurchasesWithSupplierByDateRange threads the identical param the same
// way — see purchase_reports_dao.dart.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  final from = DateTime(2026, 3, 1);
  final to = DateTime(2026, 3, 31);

  setUp(() async {
    db = AppDatabase.forTesting();
    // FK is enforced in tests now (mirrors production). The seeder creates only
    // branch 1, warehouse 1 and user 1 — seed branch 2 which the branch-scope
    // rows below reference.
    await db.into(db.branches).insert(BranchesCompanion.insert(name: 'فرع ٢'));
    await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
          invoiceNumber: 'SI-BR1-B12-4',
          warehouseId: 1,
          userId: 1,
          invoiceDate: DateTime(2026, 3, 5),
          branchId: const Value(1),
          total: const Value(100),
        ));
    await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
          invoiceNumber: 'SI-BR2-B12-4',
          warehouseId: 1,
          userId: 1,
          invoiceDate: DateTime(2026, 3, 6),
          branchId: const Value(2),
          total: const Value(200),
        ));
    // Global (NULL-branch) invoice — must stay visible under every
    // restricted (non-empty) scope.
    await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
          invoiceNumber: 'SI-GLOBAL-B12-4',
          warehouseId: 1,
          userId: 1,
          invoiceDate: DateTime(2026, 3, 7),
          total: const Value(50),
        ));
  });

  tearDown(() => db.close());

  group('Spec 149 B12-4 detail-table branch scope', () {
    test('allowedBranchIds: null → full access, all 3 rows', () async {
      final rows = await db.getSalesByDateRange(from, to);
      expect(rows.length, 3);
    });

    test(
        'allowedBranchIds: {1} → branch-1 + NULL-branch rows only '
        '(branch-2 excluded)', () async {
      final rows = await db.getSalesByDateRange(from, to, allowedBranchIds: {1});
      expect(rows.length, 2);
      final numbers = rows.map((r) => r.invoiceNumber).toSet();
      expect(numbers, contains('SI-BR1-B12-4'));
      expect(numbers, contains('SI-GLOBAL-B12-4'),
          reason: 'NULL-branch rows must stay visible under a restricted scope');
      expect(numbers, isNot(contains('SI-BR2-B12-4')),
          reason: "branch-2's invoice must NOT leak to a branch-1 user");
    });

    test(
        'allowedBranchIds: <int>{} (empty) → fail-closed, matches nothing',
        () async {
      final rows =
          await db.getSalesByDateRange(from, to, allowedBranchIds: <int>{});
      expect(rows, isEmpty,
          reason: 'an empty allowedBranchIds set must match nothing — '
              'defensive fail-closed for a misconfigured zero-scope user');
    });
  });
}
