// ═══════════════════════════════════════════════════════════════════════════
// Spec 136 ISS-9 — bounded, DB-filtered inventory query + aggregate summary
// ═══════════════════════════════════════════════════════════════════════════
//
// The inventory screen used to watch the unbounded watchAllProducts(), which
// loaded + mapped every active product (762ms stall on a 57978-row catalog).
// watchInventoryProducts() pushes the filters + a row LIMIT into SQL, and
// watchInventorySummary() computes the cards via a cheap aggregate so the
// totals stay accurate over the whole catalog regardless of the LIMIT.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int catA;
  late int catB;

  Future<int> seedProduct(
    String name,
    String code, {
    required double stock,
    required double minStock,
    required double cost,
    int? categoryId,
    bool active = true,
    bool track = true,
    String? barcode,
  }) {
    return db.into(db.products).insert(
          ProductsCompanion.insert(
            name: name,
            code: code,
            barcode: Value(barcode),
            categoryId: Value(categoryId),
            currentStock: Value(stock),
            minStock: Value(minStock),
            costPrice: Value(cost),
            isActive: Value(active),
            trackInventory: Value(track),
          ),
        );
  }

  setUp(() async {
    db = AppDatabase.forTesting();
    catA = await db.into(db.categories).insert(
          CategoriesCompanion.insert(name: 'A'),
        );
    catB = await db.into(db.categories).insert(
          CategoriesCompanion.insert(name: 'B'),
        );
  });

  tearDown(() => db.close());

  test('watchInventoryProducts respects the LIMIT', () async {
    for (var i = 0; i < 20; i++) {
      await seedProduct('P$i', 'C$i',
          stock: 10, minStock: 1, cost: 1, categoryId: catA);
    }
    final rows = await db.watchInventoryProducts(limit: 5).first;
    expect(rows, hasLength(5));
  });

  test('watchInventoryProducts filters by category, low-stock, and search',
      () async {
    await seedProduct('Apple', 'APL',
        stock: 0, minStock: 5, cost: 2, categoryId: catA, barcode: '111');
    await seedProduct('Banana', 'BAN',
        stock: 50, minStock: 5, cost: 2, categoryId: catA);
    await seedProduct('Cherry', 'CHR',
        stock: 1, minStock: 5, cost: 2, categoryId: catB);
    // inactive must never appear
    await seedProduct('Dead', 'DED',
        stock: 0, minStock: 5, cost: 2, categoryId: catA, active: false);

    // category A only
    final byCat = await db.watchInventoryProducts(categoryId: catA).first;
    expect(byCat.map((p) => p.code).toSet(), {'APL', 'BAN'});

    // low-stock only (currentStock <= minStock): Apple(0<=5), Cherry(1<=5)
    final low = await db.watchInventoryProducts(lowStockOnly: true).first;
    expect(low.map((p) => p.code).toSet(), {'APL', 'CHR'});

    // search by name
    final byName = await db.watchInventoryProducts(search: 'ban').first;
    expect(byName.map((p) => p.code).toSet(), {'BAN'});

    // search by barcode (primary column)
    final byBarcode = await db.watchInventoryProducts(search: '111').first;
    expect(byBarcode.map((p) => p.code).toSet(), {'APL'});

    // restrictToIds scopes to a given product set
    final apl = byCat.firstWhere((p) => p.code == 'APL');
    final restricted =
        await db.watchInventoryProducts(restrictToIds: [apl.id]).first;
    expect(restricted.map((p) => p.code).toSet(), {'APL'});

    // empty restriction → no rows (never "all")
    final none =
        await db.watchInventoryProducts(restrictToIds: const <int>[]).first;
    expect(none, isEmpty);
  });

  test('getInventoryProductsPage paginates by offset (no overlap, full cover)',
      () async {
    for (var i = 0; i < 25; i++) {
      // zero-padded code so the sortOrder/name ordering is deterministic
      final n = i.toString().padLeft(2, '0');
      await seedProduct('P$n', 'C$n',
          stock: 10, minStock: 1, cost: 1, categoryId: catA);
    }
    final page1 =
        await db.getInventoryProductsPage(limit: 10, offset: 0);
    final page2 =
        await db.getInventoryProductsPage(limit: 10, offset: 10);
    final page3 =
        await db.getInventoryProductsPage(limit: 10, offset: 20);
    expect(page1, hasLength(10));
    expect(page2, hasLength(10));
    expect(page3, hasLength(5)); // 25 total
    final all = [...page1, ...page2, ...page3].map((p) => p.code).toList();
    expect(all.toSet(), hasLength(25), reason: 'pages must not overlap');
  });

  test('getInventoryProductsPage honours filters + restrictToIds', () async {
    await seedProduct('Apple', 'APL',
        stock: 0, minStock: 5, cost: 2, categoryId: catA);
    await seedProduct('Banana', 'BAN',
        stock: 9, minStock: 5, cost: 2, categoryId: catB);
    final low = await db.getInventoryProductsPage(
        limit: 50, offset: 0, lowStockOnly: true);
    expect(low.map((p) => p.code).toSet(), {'APL'});
    final none = await db.getInventoryProductsPage(
        limit: 50, offset: 0, restrictToIds: const <int>[]);
    expect(none, isEmpty);
  });

  test('watchInventorySummary aggregates counts + value accurately', () async {
    // 2 trackable, 1 low-stock among them, value = stock*cost summed over
    // trackable.
    await seedProduct('Apple', 'APL',
        stock: 0, minStock: 5, cost: 2, track: true); // low, value 0
    await seedProduct('Banana', 'BAN',
        stock: 10, minStock: 5, cost: 3, track: true); // ok, value 30
    // non-trackable: counts toward activeCount but NOT low-stock/value
    await seedProduct('Service', 'SVC',
        stock: 0, minStock: 99, cost: 7, track: false);
    // inactive: excluded entirely
    await seedProduct('Dead', 'DED',
        stock: 0, minStock: 5, cost: 9, track: true, active: false);

    final s = await db.watchInventorySummary().first;
    expect(s.activeCount, 3, reason: '3 active (incl. non-trackable service)');
    expect(s.lowStockCount, 1, reason: 'only Apple is trackable + low');
    expect(s.totalValue, closeTo(30.0, 0.001),
        reason: 'value over trackable: 0*2 + 10*3 = 30');
  });
}
