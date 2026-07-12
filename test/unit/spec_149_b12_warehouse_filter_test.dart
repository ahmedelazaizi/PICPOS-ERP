// ═══════════════════════════════════════════════════════════════════════════
// Spec 149 pre-deploy batch B12-2 — FIL-3 warehouse-filter empty-list flip
// ═══════════════════════════════════════════════════════════════════════════
//
// ~20 warehouse-scope query sites across sales_analytics_dao.dart,
// sales_dao.dart, purchase_dao.dart, purchase_reports_dao.dart,
// delivery_dao.dart, and accounting_reports_dao.dart's getTaxReport treated
// an empty `warehouseIds` list as "show ALL warehouses" — the inverted
// convention. Flipped to the contract already used by
// sales_analytics_dao.dart's getSalesAnalytics (the reference template):
//   warehouseIds == null       → no filter added (ALL warehouses)
//   warehouseIds == <int>[]    → match NOTHING (AND 1 = 0 / Drift isIn([])
//                                 already yields Constant(false))
//   warehouseIds == [ids]      → warehouse_id IN (ids)
//
// This test exercises getSalesByDateRange (sales_dao.dart) as a
// representative, easy-to-seed site. Every other flipped site follows the
// same null/empty/else shape — see the DAO files above for the full list.

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  final from = DateTime(2026, 3, 1);
  final to = DateTime(2026, 3, 31);

  setUp(() async {
    db = AppDatabase.forTesting();
    // FK is off in the in-memory test DB (NativeDatabase.memory sets no
    // foreign_keys pragma), so bare invoice rows suffice — mirrors the setup
    // in spec_149_b12_branch_scope_leak_test.dart.
    await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
          invoiceNumber: 'SI-WH1-B12',
          warehouseId: 1,
          userId: 1,
          invoiceDate: DateTime(2026, 3, 5),
          total: const Value(100),
        ));
    await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
          invoiceNumber: 'SI-WH2-B12',
          warehouseId: 2,
          userId: 1,
          invoiceDate: DateTime(2026, 3, 6),
          total: const Value(200),
        ));
  });

  tearDown(() => db.close());

  group('Spec 149 B12 FIL-3 warehouse empty-list flip', () {
    test('warehouseIds: null → ALL warehouses (both rows counted)', () async {
      final rows = await db.getSalesByDateRange(from, to);
      expect(rows.length, 2);
    });

    test(
        'warehouseIds: <int>[] (empty) → matches NOTHING — the '
        'security-relevant flip', () async {
      final rows =
          await db.getSalesByDateRange(from, to, warehouseIds: <int>[]);
      expect(rows, isEmpty,
          reason: 'an empty warehouseIds list must match nothing; previously '
              'it silently fell back to showing every warehouse (the '
              'inverted convention this batch fixes)');
    });

    test('warehouseIds: [wh1] → only warehouse 1\'s row', () async {
      final rows =
          await db.getSalesByDateRange(from, to, warehouseIds: [1]);
      expect(rows.length, 1);
      expect(rows.single.invoiceNumber, 'SI-WH1-B12');
    });
  });
}
