import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  tearDown(() => db.close());

  test(
    'synthetic large-data aggregates remain correct across branch and warehouse scopes',
    () async {
      db = AppDatabase.forTesting();
      final userId = (await db.select(db.users).get()).first.id;
      final branchA = await db
          .into(db.branches)
          .insert(BranchesCompanion.insert(name: 'Scale branch A'));
      final branchB = await db
          .into(db.branches)
          .insert(BranchesCompanion.insert(name: 'Scale branch B'));
      final warehouses = [
        await db
            .into(db.warehouses)
            .insert(
              WarehousesCompanion.insert(
                name: 'Scale A1',
                branchId: Value(branchA),
              ),
            ),
        await db
            .into(db.warehouses)
            .insert(
              WarehousesCompanion.insert(
                name: 'Scale A2',
                branchId: Value(branchA),
              ),
            ),
        await db
            .into(db.warehouses)
            .insert(
              WarehousesCompanion.insert(
                name: 'Scale B1',
                branchId: Value(branchB),
              ),
            ),
        await db
            .into(db.warehouses)
            .insert(
              WarehousesCompanion.insert(
                name: 'Scale B2',
                branchId: Value(branchB),
              ),
            ),
      ];
      final categoryNames = [
        'Scale category 0',
        'Scale category 1',
        'Scale category 2',
      ];
      final categoryIds = <int>[];
      for (final name in categoryNames) {
        categoryIds.add(
          await db
              .into(db.categories)
              .insert(CategoriesCompanion.insert(name: name)),
        );
      }
      final productIds = <int>[];
      for (var i = 0; i < categoryIds.length; i++) {
        productIds.add(
          await db
              .into(db.products)
              .insert(
                ProductsCompanion.insert(
                  code: 'SCALE-P$i',
                  name: 'Scale product $i',
                  categoryId: Value(categoryIds[i]),
                  trackInventory: const Value(false),
                ),
              ),
        );
      }

      final existingInvoiceMax = await db
          .customSelect(
            'SELECT COALESCE(MAX(id), 0) AS max_id FROM sales_invoices',
          )
          .getSingle();
      final existingItemMax = await db
          .customSelect(
            'SELECT COALESCE(MAX(id), 0) AS max_id FROM sales_invoice_items',
          )
          .getSingle();
      final invoiceStart =
          (existingInvoiceMax.data['max_id'] as num).toInt() + 1;
      var itemId = (existingItemMax.data['max_id'] as num).toInt() + 1;

      final allCategories = <String, List<double>>{};
      final branchACategories = <String, List<double>>{};
      final warehouseA2Categories = <String, List<double>>{};
      final allTypes = <String, List<double>>{};
      final branchATypes = <String, List<double>>{};
      final warehouseA2Types = <String, List<double>>{};

      void addCategory(
        Map<String, List<double>> target,
        String name,
        double quantity,
        double total,
      ) {
        final values = target.putIfAbsent(name, () => [0, 0]);
        values[0] += quantity;
        values[1] += total;
      }

      void addType(
        Map<String, List<double>> target,
        String type,
        double total,
      ) {
        final values = target.putIfAbsent(type, () => [0, 0]);
        values[0]++;
        values[1] += total;
      }

      final invoiceRows = <SalesInvoicesCompanion>[];
      final itemRows = <SalesInvoiceItemsCompanion>[];
      const inRangeInvoices = 2048;
      const totalInvoices = 2080;
      final saleTypes = ['default', 'talabat', 'careem'];
      for (var i = 0; i < totalInvoices; i++) {
        final inRange = i < inRangeInvoices;
        final warehouseIndex = i % warehouses.length;
        final warehouseId = warehouses[warehouseIndex];
        final branchId = warehouseIndex < 2 ? branchA : branchB;
        final invoiceId = invoiceStart + i;
        final firstQuantity = (i % 4 + 1).toDouble();
        final secondQuantity = (i % 3 + 2).toDouble();
        final firstTotal = firstQuantity * (10 + i % 5);
        final secondTotal = secondQuantity * (20 + i % 7);
        final invoiceTotal = firstTotal + secondTotal;
        final type = saleTypes[i % saleTypes.length];
        final date = inRange
            ? DateTime(2026, 1, 1 + i % 28)
            : DateTime(2025, 12, 31);

        invoiceRows.add(
          SalesInvoicesCompanion.insert(
            id: Value(invoiceId),
            invoiceNumber: 'SCALE-$i',
            warehouseId: warehouseId,
            userId: userId,
            invoiceDate: date,
            branchId: Value(branchId),
            subtotal: Value(invoiceTotal),
            total: Value(invoiceTotal),
            paid: Value(invoiceTotal),
            saleType: Value(type),
          ),
        );
        itemRows.addAll([
          SalesInvoiceItemsCompanion.insert(
            id: Value(itemId++),
            invoiceId: invoiceId,
            productId: productIds[i % productIds.length],
            quantity: firstQuantity,
            unitPrice: 10 + i % 5,
            total: firstTotal,
          ),
          SalesInvoiceItemsCompanion.insert(
            id: Value(itemId++),
            invoiceId: invoiceId,
            productId: productIds[(i + 1) % productIds.length],
            quantity: secondQuantity,
            unitPrice: 20 + i % 7,
            total: secondTotal,
          ),
        ]);

        if (!inRange) continue;
        final firstCategory = categoryNames[i % categoryNames.length];
        final secondCategory = categoryNames[(i + 1) % categoryNames.length];
        addCategory(allCategories, firstCategory, firstQuantity, firstTotal);
        addCategory(allCategories, secondCategory, secondQuantity, secondTotal);
        addType(allTypes, type, invoiceTotal);
        if (branchId == branchA) {
          addCategory(
            branchACategories,
            firstCategory,
            firstQuantity,
            firstTotal,
          );
          addCategory(
            branchACategories,
            secondCategory,
            secondQuantity,
            secondTotal,
          );
          addType(branchATypes, type, invoiceTotal);
        }
        if (warehouseId == warehouses[1]) {
          addCategory(
            warehouseA2Categories,
            firstCategory,
            firstQuantity,
            firstTotal,
          );
          addCategory(
            warehouseA2Categories,
            secondCategory,
            secondQuantity,
            secondTotal,
          );
          addType(warehouseA2Types, type, invoiceTotal);
        }
      }

      await db.transaction(() async {
        await db.batch((batch) {
          batch.insertAll(db.salesInvoices, invoiceRows);
          batch.insertAll(db.salesInvoiceItems, itemRows);
        });
      });

      final from = DateTime(2026, 1, 1);
      final to = DateTime(2026, 1, 31);
      // Synthetic in-memory data exercises aggregation correctness only; this test
      // intentionally makes no claim about production schema or query timing.
      final allCategoryRows = await db.getSalesByCategory(from: from, to: to);
      final allTypeRows = await db.getSalesBySaleType(from: from, to: to);

      void expectCategories(
        List<SalesByCategoryRow> actual,
        Map<String, List<double>> expected,
      ) {
        expect(
          actual.map((row) => row.category).toSet(),
          expected.keys.toSet(),
        );
        for (final row in actual) {
          expect(row.quantity, closeTo(expected[row.category]![0], 0.001));
          expect(row.total, closeTo(expected[row.category]![1], 0.001));
        }
      }

      void expectTypes(
        List<SalesBySaleTypeRow> actual,
        Map<String, List<double>> expected,
      ) {
        expect(actual.map((row) => row.type).toSet(), expected.keys.toSet());
        for (final row in actual) {
          expect(row.count, expected[row.type]![0].toInt());
          expect(row.total, closeTo(expected[row.type]![1], 0.001));
        }
      }

      expectCategories(allCategoryRows, allCategories);
      expectTypes(allTypeRows, allTypes);

      final branchCategoryRows = await db.getSalesByCategory(
        from: from,
        to: to,
        allowedBranchIds: {branchA},
      );
      final branchTypeRows = await db.getSalesBySaleType(
        from: from,
        to: to,
        allowedBranchIds: {branchA},
      );
      expectCategories(branchCategoryRows, branchACategories);
      expectTypes(branchTypeRows, branchATypes);

      final warehouseCategoryRows = await db.getSalesByCategory(
        from: from,
        to: to,
        warehouseIds: [warehouses[1]],
      );
      final warehouseTypeRows = await db.getSalesBySaleType(
        from: from,
        to: to,
        warehouseIds: [warehouses[1]],
      );
      expectCategories(warehouseCategoryRows, warehouseA2Categories);
      expectTypes(warehouseTypeRows, warehouseA2Types);
    },
  );
}
