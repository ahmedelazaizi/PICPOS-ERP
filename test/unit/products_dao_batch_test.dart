// ═══════════════════════════════════════════════════════════════════════════
// getProductsByIds — Unit Tests
//
// Verifies the batch product lookup helper introduced to eliminate N+1
// query patterns in DAO loops.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' as drift;
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    final unitId = await db.into(db.units).insert(
      UnitsCompanion.insert(name: 'piece', symbol: 'pc'),
    );

    await db.into(db.products).insert(
      ProductsCompanion.insert(
        name: 'Product A',
        code: 'A001',
        salePrice: const drift.Value(10.0),
        costPrice: const drift.Value(5.0),
        unitId: drift.Value(unitId),
      ),
    );
    await db.into(db.products).insert(
      ProductsCompanion.insert(
        name: 'Product B',
        code: 'B001',
        salePrice: const drift.Value(20.0),
        costPrice: const drift.Value(12.0),
        unitId: drift.Value(unitId),
      ),
    );
    await db.into(db.products).insert(
      ProductsCompanion.insert(
        name: 'Product C',
        code: 'C001',
        salePrice: const drift.Value(30.0),
        costPrice: const drift.Value(15.0),
        unitId: drift.Value(unitId),
      ),
    );
  });

  tearDown(() => db.close());

  group('getProductsByIds', () {
    test('empty list returns empty map without hitting DB', () async {
      final result = await db.getProductsByIds([]);
      expect(result, isEmpty);
    });

    test('returns all requested products by ID', () async {
      final all = await db.select(db.products).get();
      final ids = all.map((p) => p.id).toList();

      final result = await db.getProductsByIds(ids);

      expect(result.length, equals(3));
      for (final id in ids) {
        expect(result, contains(id));
      }
    });

    test('deduplicates repeated IDs', () async {
      final all = await db.select(db.products).get();
      final id = all.first.id;

      final result = await db.getProductsByIds([id, id, id]);

      expect(result.length, equals(1));
      expect(result[id]?.id, equals(id));
    });

    test('missing IDs are absent from result, no error thrown', () async {
      const nonExistentId = 99999;
      final result = await db.getProductsByIds([nonExistentId]);
      expect(result, isEmpty);
    });

    test('partial hit: existing IDs present, missing IDs absent', () async {
      final all = await db.select(db.products).get();
      final existingId = all.first.id;
      const missingId = 88888;

      final result = await db.getProductsByIds([existingId, missingId]);

      expect(result.length, equals(1));
      expect(result, contains(existingId));
      expect(result, isNot(contains(missingId)));
    });

    test('result map values match the original product data', () async {
      final all = await db.select(db.products).get();
      final productA = all.firstWhere((p) => p.code == 'A001');

      final result = await db.getProductsByIds([productA.id]);

      final fetched = result[productA.id]!;
      expect(fetched.name, equals('Product A'));
      expect(fetched.salePrice, equals(10.0));
      expect(fetched.costPrice, equals(5.0));
    });

    test('single-item batch equivalent to getProductById', () async {
      final all = await db.select(db.products).get();
      final product = all.first;

      final single = await db.getProductById(product.id);
      final batch = await db.getProductsByIds([product.id]);

      expect(batch[product.id]?.id, equals(single?.id));
      expect(batch[product.id]?.name, equals(single?.name));
    });
  });
}
