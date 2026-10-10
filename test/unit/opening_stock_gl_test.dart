// ═══════════════════════════════════════════════════════════════════════════
// P0-06 — Opening Stock GL Entry Tests
// ═══════════════════════════════════════════════════════════════════════════
//
// Verifies that calling adjustStock(movementType: 'opening_stock') posts
// a balanced GL entry: Dr Inventory / Cr Opening Equity.
//
// Audit ref: 02_accounting_correctness.md — complements P1-03 backfill.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await _clearDatabase(db);
    await _seedAccounts(db);
    await _seedFiscalYear(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('P0-06 — Opening Stock GL Entry', () {
    test('opening_stock adjustStock posts Dr Inventory / Cr Opening Equity', () async {
      // Seed product and warehouse
      final warehouseId = await db.into(db.warehouses).insert(
        WarehousesCompanion.insert(
          name: 'Main',
          isActive: const Value(true),
          isDefault: const Value(true),
        ),
      );
      final productId = await db.into(db.products).insert(
        ProductsCompanion.insert(
          code: 'P001',
          name: 'Test Product',
          salePrice: const Value(100.0),
          costPrice: const Value(50.0),
          trackInventory: const Value(true),
        ),
      );

      // Call adjustStock with opening_stock movement
      await db.adjustStock(
        productId: productId,
        warehouseId: warehouseId,
        quantity: 10.0,
        type: 'opening_stock',
        unitCost: 50.0,
      );

      // Verify exactly one journal entry was created
      final entries = await db.select(db.journalEntries).get();
      expect(entries.length, 1,
          reason: 'Expected one JE for opening_stock movement');

      final entry = entries.first;
      expect(entry.referenceType, 'opening_balance');
      expect(entry.referenceId, productId);
      expect(entry.isAutoPosted, true);

      // Verify lines: Dr Inventory 500, Cr Opening Equity 500
      final lines = await (db.select(db.journalEntryLines)
            ..where((l) => l.entryId.equals(entry.id)))
          .get();
      expect(lines.length, 2);

      final debitLine = lines.firstWhere((l) => l.debit > 0);
      final creditLine = lines.firstWhere((l) => l.credit > 0);

      expect(debitLine.debit, closeTo(500.0, 0.001),
          reason: '10 units × 50.0 cost = 500 debit');
      expect(creditLine.credit, closeTo(500.0, 0.001),
          reason: 'Balancing credit must equal debit');
    });

    test('opening_stock with zero cost skips GL entry', () async {
      final warehouseId = await db.into(db.warehouses).insert(
        WarehousesCompanion.insert(
          name: 'Warehouse B',
          isActive: const Value(true),
          isDefault: const Value(false),
        ),
      );
      final productId = await db.into(db.products).insert(
        ProductsCompanion.insert(
          code: 'P002',
          name: 'Zero Cost Product',
          salePrice: const Value(10.0),
          costPrice: const Value(0.0),
          trackInventory: const Value(true),
        ),
      );

      await db.adjustStock(
        productId: productId,
        warehouseId: warehouseId,
        quantity: 5.0,
        type: 'opening_stock',
        // no unitCost → falls back to product.costPrice = 0
      );

      // No JE should be created when cost is zero
      final entries = await db.select(db.journalEntries).get();
      expect(entries.length, 0,
          reason: 'Zero-cost opening stock must not create a JE');
    });

    test('non-opening_stock movement does NOT use opening_balance referenceType', () async {
      final warehouseId = await db.into(db.warehouses).insert(
        WarehousesCompanion.insert(
          name: 'Warehouse C',
          isActive: const Value(true),
          isDefault: const Value(false),
        ),
      );
      final productId = await db.into(db.products).insert(
        ProductsCompanion.insert(
          code: 'P003',
          name: 'Adjustment Product',
          salePrice: const Value(20.0),
          costPrice: const Value(10.0),
          trackInventory: const Value(true),
        ),
      );

      await db.adjustStock(
        productId: productId,
        warehouseId: warehouseId,
        quantity: 5.0,
        type: 'adjustment',
        unitCost: 10.0,
      );

      // JE from adjustment should use 'stock_adjustment', not 'opening_balance'
      final entries = await db.select(db.journalEntries).get();
      if (entries.isNotEmpty) {
        expect(
          entries.every((e) => e.referenceType != 'opening_balance'),
          isTrue,
          reason: 'Adjustment movement must not use opening_balance referenceType',
        );
      }
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────────────────────

Future<void> _clearDatabase(AppDatabase db) async {
  await db.delete(db.journalEntryLines).go();
  await db.delete(db.journalEntries).go();
  await db.delete(db.stockMovements).go();
  await db.delete(db.inventoryBalances).go();
  await db.delete(db.products).go();
  // v195 — المواقعُ (`warehouse_locations`) ومخزونُها (`location_stock`) جدولان
  // خام تابعان للمخزن؛ الـbackfill يزرع «DEFAULT bin» لكلّ مخزنٍ عند الفتح،
  // فمسحُ `warehouses` قبل أبنائه يسقط بـ`FOREIGN KEY constraint failed (787)`.
  await db.customStatement('DELETE FROM location_stock');
  await db.customStatement('DELETE FROM warehouse_locations');
  await db.delete(db.warehouses).go();
  await db.delete(db.accountingPeriods).go();
  await db.delete(db.fiscalYears).go();
  await db.delete(db.accountMappings).go();
  // §٣-ب — الخزائنُ صارت مشدودةً إلى الدليل (`safes.linkedAccountId`)، فمسحُ
  // `accounts` بلا فكِّ الشدّ يسقط بـ`FOREIGN KEY constraint failed (787)`.
  // وفكُّ الربط جزءٌ من مسح الدليل لا التفافٌ عليه: لا ربطَ يبقى صحيحاً بعد
  // محو ما يشير إليه. والخزائنُ نفسُها تبقى — هذا الاختبارُ لا يمسّها.
  await db
      .update(db.safes)
      .write(const SafesCompanion(linkedAccountId: Value(null)));
  // J3 — والأطرافُ النظاميّة («عميل نقدي»/«مورد نقدي») مشدودةٌ كذلك.
  await db.update(db.parties).write(const PartiesCompanion(accountId: Value(null)));
  await db.delete(db.accounts).go();
}

Future<void> _seedAccounts(AppDatabase db) async {
  // Codes must match AccountingDao.accountPurposes:
  // 'inventory' → '1136', 'opening_equity' → '313' (same as retained_earnings)
  final accounts = [
    {'code': '1136', 'name': 'مخزون البضاعة للبيع', 'type': 'asset'},       // inventory
    {'code': '313',  'name': 'الأرصدة الافتتاحية', 'type': 'equity'},        // opening_equity
    // Needed by adjustment movement type in the same DAO:
    {'code': '4317', 'name': 'فائض مخزون', 'type': 'revenue'},               // inventory_surplus
    {'code': '5311', 'name': 'عجز مخزون', 'type': 'expense'},                // inventory_shrinkage
  ];

  for (final a in accounts) {
    await db.into(db.accounts).insert(
      AccountsCompanion.insert(
        code: a['code']!,
        name: a['name']!,
        accountType: a['type']!,
        balance: const Value(0.0),
      ),
    );
  }
}

Future<void> _seedFiscalYear(AppDatabase db) async {
  await db.into(db.fiscalYears).insert(
    FiscalYearsCompanion.insert(
      id: const Value(1),
      name: '2026',
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 12, 31, 23, 59, 59),
    ),
  );
}
