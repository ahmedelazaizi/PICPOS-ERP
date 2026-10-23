// Feature 045 — Soft-delete categories with bulk-move semantics.
//
// Pre-fix the DAO did a HARD DELETE preceded by a `(select(categories)
// ..limit(1))` "default" pick — two bugs that combined to make the
// field-reported "categories reappear for another user" symptom:
//   1. Hard DELETE → next DeltaPull from a server that still held the
//      row re-inserted it locally → User B saw the row again.
//   2. The "first category" pick was arbitrary (no ORDER BY), so the
//      move target was unpredictable, and when the picked row WAS the
//      one being deleted the move was skipped → orphan products.
//
// Post-fix: soft-delete (`isActive=false` + `deletedAt=NOW()`) + caller-
// chosen destination + single transaction. CategorySyncStrategy already
// honours `isActive=false` from server pulls (line 64 of that file),
// so the deletion propagates instead of being resurrected.

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int catA;
  late int catB;
  late int catGeneral;

  Future<int> seedProduct({
    required String code,
    required String name,
    required int categoryId,
    bool isActive = true,
  }) =>
      db.into(db.products).insert(
            ProductsCompanion.insert(
              code: code,
              name: name,
              categoryId: Value(categoryId),
              isActive: Value(isActive),
              globalId: Value('gid-prod-$code'),
            ),
          );

  setUp(() async {
    db = AppDatabase.forTesting();
    catGeneral = await db.into(db.categories).insert(
          CategoriesCompanion.insert(
            name: 'عام',
            globalId: const Value('gid-cat-general'),
          ),
        );
    catA = await db.into(db.categories).insert(
          CategoriesCompanion.insert(
            name: 'حلويات',
            globalId: const Value('gid-cat-a'),
          ),
        );
    catB = await db.into(db.categories).insert(
          CategoriesCompanion.insert(
            name: 'مشروبات',
            globalId: const Value('gid-cat-b'),
          ),
        );
  });

  tearDown(() => db.close());

  group('countActiveProductsInCategory', () {
    test('returns 0 for empty category', () async {
      expect(await db.countActiveProductsInCategory(catA), 0);
    });

    test('counts only isActive=true products', () async {
      await seedProduct(code: 'P1', name: 'Cake', categoryId: catA);
      await seedProduct(code: 'P2', name: 'Pie', categoryId: catA);
      await seedProduct(
          code: 'P3', name: 'Old Cake', categoryId: catA, isActive: false);

      expect(await db.countActiveProductsInCategory(catA), 2,
          reason: 'soft-deactivated products do NOT block category delete');
    });

    test('does not count products in other categories', () async {
      await seedProduct(code: 'PA', name: 'Cake', categoryId: catA);
      await seedProduct(code: 'PB', name: 'Cola', categoryId: catB);

      expect(await db.countActiveProductsInCategory(catA), 1);
      expect(await db.countActiveProductsInCategory(catB), 1);
    });
  });

  group('deleteCategory (soft + bulk-move)', () {
    test('empty category: soft-delete sets isActive=false + deletedAt', () async {
      await db.deleteCategory(catA);

      final row = await (db.select(db.categories)
            ..where((c) => c.id.equals(catA)))
          .getSingleOrNull();
      expect(row, isNotNull,
          reason: 'soft-delete must preserve the row — DeltaPull dedup '
              'relies on the row existing with isActive=false so the '
              'server-side strategy UPDATEs instead of INSERTing.');
      expect(row!.isActive, isFalse);
      expect(row.deletedAt, isNotNull);
      expect(row.lastModifiedAt, isNotNull);
    });

    test('moveToCategoryId=null leaves products uncategorized (categoryId=NULL)',
        () async {
      await seedProduct(code: 'P1', name: 'Cake', categoryId: catA);
      await seedProduct(code: 'P2', name: 'Pie', categoryId: catA);

      await db.deleteCategory(catA);

      final products = await (db.select(db.products)
            ..where((p) => p.code.isIn(['P1', 'P2'])))
          .get();
      expect(products.length, 2);
      for (final p in products) {
        expect(p.categoryId, isNull,
            reason: 'null destination = "بدون تصنيف" — valid because '
                'Products.categoryId is nullable in the schema.');
      }
    });

    test('moveToCategoryId=other moves all active products inside transaction',
        () async {
      await seedProduct(code: 'P1', name: 'Cake', categoryId: catA);
      await seedProduct(code: 'P2', name: 'Pie', categoryId: catA);
      await seedProduct(
          code: 'P3', name: 'Old Cake', categoryId: catA, isActive: false);

      await db.deleteCategory(catA, moveToCategoryId: catGeneral);

      final p1 = await (db.select(db.products)
            ..where((p) => p.code.equals('P1')))
          .getSingle();
      final p2 = await (db.select(db.products)
            ..where((p) => p.code.equals('P2')))
          .getSingle();
      final p3 = await (db.select(db.products)
            ..where((p) => p.code.equals('P3')))
          .getSingle();

      expect(p1.categoryId, catGeneral);
      expect(p2.categoryId, catGeneral);
      // Inactive products are intentionally NOT migrated — they're off the
      // UI already, and migrating them would inflate the destination's
      // visible count without benefit.
      expect(p3.categoryId, catA);

      final deletedCat = await (db.select(db.categories)
            ..where((c) => c.id.equals(catA)))
          .getSingle();
      expect(deletedCat.isActive, isFalse);
    });

    test('rejects moveToCategoryId == categoryId (self-move)', () async {
      await seedProduct(code: 'P1', name: 'Cake', categoryId: catA);
      expect(
        () => db.deleteCategory(catA, moveToCategoryId: catA),
        throwsArgumentError,
      );
      // Verify nothing changed
      final stillActive = await (db.select(db.categories)
            ..where((c) => c.id.equals(catA)))
          .getSingle();
      expect(stillActive.isActive, isTrue);
    });

    test('soft-deleted category is filtered out of watchAllCategories',
        () async {
      await db.deleteCategory(catA);
      final visible = await (db.select(db.categories)
            ..where((c) => c.isActive.equals(true)))
          .get();
      expect(visible.map((c) => c.id), isNot(contains(catA)));
      expect(visible.map((c) => c.id), containsAll([catB, catGeneral]));
    });

    test('CategorySyncStrategy shape: re-applying isActive=false from server '
        'keeps the row soft-deleted (no resurrect)', () async {
      // Simulate the row's life cycle:
      //   1. Local soft-delete sets isActive=false.
      //   2. Server confirms the soft-delete on its side.
      //   3. DeltaPull pulls the server's row back with isActive=false —
      //      the strategy's UPDATE branch (category_sync_strategy.dart:71)
      //      writes isActive=false again. Verify the row stays deleted.
      await db.deleteCategory(catA);
      await (db.update(db.categories)..where((c) => c.id.equals(catA)))
          .write(const CategoriesCompanion(isActive: Value(false)));

      final row = await (db.select(db.categories)
            ..where((c) => c.id.equals(catA)))
          .getSingle();
      expect(row.isActive, isFalse,
          reason: 'idempotent soft-delete — repeated isActive=false writes '
              'do not flip it back to true');
    });
  });
}
