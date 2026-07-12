// ═══════════════════════════════════════════════════════════════════════════
// Spec 149 pre-deploy batch B12-5 — FIL-2 branch-scope on the aggregate
// analytics KPI methods (sales_analytics_dao.dart / purchase_reports_dao.dart)
// ═══════════════════════════════════════════════════════════════════════════
//
// B12-1 scoped the accounting-report methods and B12-4 scoped the invoice-
// DETAIL report tables, but the KPI-card aggregates (getSalesAnalytics et al.)
// were left open — a branch-restricted user (limited via user_branch_access)
// could still read company-wide KPI totals through these methods. B12-5a
// threads a new `allowedBranchIds` param through them (backend only; screens
// are wired separately in B12-5b, so with no caller passing the param
// behaviour is unchanged). Contract mirrors B12-1's `_buildAuthScopeFilter`
// (see BranchScope in lib/data/providers/branch_scope_provider.dart):
//   allowedBranchIds == null  → no restriction (full access)
//   allowedBranchIds == {}    → match NOTHING (fail-closed)
//   allowedBranchIds == {ids} → branch_id IN (ids) OR branch_id IS NULL
//
// This test exercises getSalesAnalytics as the representative site (it's the
// most complex of the batch — TWO customSelect queries, main + COGS
// subquery, sharing one variables list).

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  final from = DateTime(2026, 3, 1);
  final to = DateTime(2026, 3, 31);

  setUp(() async {
    db = AppDatabase.forTesting();
    // FK is off in the in-memory test DB (NativeDatabase.memory sets no
    // foreign_keys pragma), so bare invoice rows suffice — mirrors the setup
    // in spec_149_b12_detail_table_scope_test.dart.
    await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
          invoiceNumber: 'SI-BR1-B12-5',
          warehouseId: 1,
          userId: 1,
          invoiceDate: DateTime(2026, 3, 5),
          branchId: const Value(1),
          total: const Value(100),
        ));
    await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
          invoiceNumber: 'SI-BR2-B12-5',
          warehouseId: 1,
          userId: 1,
          invoiceDate: DateTime(2026, 3, 6),
          branchId: const Value(2),
          total: const Value(200),
        ));
    // Global (NULL-branch) invoice — must stay visible under every
    // restricted (non-empty) scope.
    await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
          invoiceNumber: 'SI-GLOBAL-B12-5',
          warehouseId: 1,
          userId: 1,
          invoiceDate: DateTime(2026, 3, 7),
          total: const Value(50),
        ));
  });

  tearDown(() => db.close());

  group('Spec 149 B12-5 analytics KPI branch scope', () {
    test('allowedBranchIds: null → full access, totalSales reflects ALL three',
        () async {
      final result = await db.getSalesAnalytics(from, to);
      expect(result.totalSales, 350.0); // 100 + 200 + 50
      expect(result.salesCount, 3);
    });

    test(
        'allowedBranchIds: {1} → branch-1 + NULL-branch only '
        '(branch-2 excluded)', () async {
      final result =
          await db.getSalesAnalytics(from, to, allowedBranchIds: {1});
      expect(result.totalSales, 150.0); // 100 + 50, branch-2's 200 excluded
      expect(result.salesCount, 2);
    });

    test('allowedBranchIds: <int>{} (empty) → fail-closed, total is zero',
        () async {
      final result =
          await db.getSalesAnalytics(from, to, allowedBranchIds: <int>{});
      expect(result.totalSales, 0.0,
          reason: 'an empty allowedBranchIds set must match nothing — '
              'defensive fail-closed for a misconfigured zero-scope user');
      expect(result.salesCount, 0);
    });
  });
}
