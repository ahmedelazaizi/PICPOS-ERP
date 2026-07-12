// ═══════════════════════════════════════════════════════════════════════════
// Spec 136 ISS-12 — bounded POS product grid query
// ═══════════════════════════════════════════════════════════════════════════
//
// The POS grid watched the unbounded watchAllProducts() — on a 57978-row
// catalog that took ~8s on POS entry and re-mapped the whole catalog on every
// sale (blocking the post-sale readback ~7s, readbackMs=7119 in the field).
// watchPosProducts scopes the query to the selected category (+ descendants)
// or the search term, DB-side + LIMIT.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int catFood;
  late int catDrinks;

  Future<void> seed(String name, String code,
      {required int categoryId, bool active = true, String? barcode}) async {
    await db.into(db.products).insert(
          ProductsCompanion.insert(
            name: name,
            code: code,
            barcode: Value(barcode),
            categoryId: Value(categoryId),
            isActive: Value(active),
          ),
        );
  }

  setUp(() async {
    db = AppDatabase.forTesting();
    catFood = await db.into(db.categories).insert(
          CategoriesCompanion.insert(name: 'طعام'),
        );
    catDrinks = await db.into(db.categories).insert(
          CategoriesCompanion.insert(name: 'مشروبات'),
        );
  });

  tearDown(() => db.close());

  test('scopes to the given category ids only', () async {
    await seed('Bread', 'F1', categoryId: catFood);
    await seed('Rice', 'F2', categoryId: catFood);
    await seed('Cola', 'D1', categoryId: catDrinks);
    await seed('Old', 'F3', categoryId: catFood, active: false);

    final food = await db.watchPosProducts(categoryIds: [catFood]).first;
    expect(food.map((p) => p.code).toSet(), {'F1', 'F2'},
        reason: 'only active products of the selected category');

    final drinks = await db.watchPosProducts(categoryIds: [catDrinks]).first;
    expect(drinks.map((p) => p.code).toSet(), {'D1'});
  });

  test('search overrides category and matches name/code/barcode', () async {
    await seed('Bread', 'F1', categoryId: catFood, barcode: '900');
    await seed('Cola', 'D1', categoryId: catDrinks);

    // search by name (no category) finds across categories
    final byName = await db.watchPosProducts(search: 'cola').first;
    expect(byName.map((p) => p.code).toSet(), {'D1'});

    // search by barcode
    final byBarcode = await db.watchPosProducts(search: '900').first;
    expect(byBarcode.map((p) => p.code).toSet(), {'F1'});

    // search wins even if a category is also passed
    final mixed =
        await db.watchPosProducts(categoryIds: [catDrinks], search: 'bread').first;
    expect(mixed.map((p) => p.code).toSet(), {'F1'});
  });

  test('honours the LIMIT', () async {
    for (var i = 0; i < 20; i++) {
      await seed('P${i.toString().padLeft(2, '0')}', 'C$i',
          categoryId: catFood);
    }
    final rows = await db.watchPosProducts(categoryIds: [catFood], limit: 5).first;
    expect(rows, hasLength(5));
  });
}
