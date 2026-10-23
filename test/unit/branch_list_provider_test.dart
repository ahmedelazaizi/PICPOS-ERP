// Spec 079 / Batch 1 — Regression guard for branchListProvider.
//
// The provider was emitting EVERY branch row, including soft-deleted
// (deletedAt IS NOT NULL) and inactive (isActive=false). Field
// symptom: a renamed/deleted branch ("الفرع الرئيسي") still appeared
// in every report's filter dropdown after the operator replaced it.
//
// This test seeds 3 branches (active+undeleted / inactive / deleted)
// and asserts only the first one is emitted.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:picpos_erp/data/providers/manufacturing_providers.dart';
import 'package:picpos_erp/data/providers/providers.dart';

void main() {
  group('branchListProvider (Spec 079 B2 guard)', () {
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() async {
      db = AppDatabase.forTesting();
      // Override the providers' database dependency to use our test DB.
      container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
      ]);
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    Future<int> insertBranch({
      required String name,
      bool isActive = true,
      DateTime? deletedAt,
    }) async {
      await db.into(db.branches).insert(BranchesCompanion.insert(
            name: name,
            isActive: Value(isActive),
            deletedAt: Value(deletedAt),
            globalId: Value('test-${name.hashCode}'),
          ));
      return (await (db.select(db.branches)
                ..where((b) => b.name.equals(name)))
              .getSingle())
          .id;
    }

    test('emits only active+undeleted branches', () async {
      // Seeder already inserts the bootstrap "الفرع الرئيسي" — bookmark
      // the baseline so the test is independent of seed state.
      final baseline = await container.read(branchListProvider.future);
      final baselineNames = baseline.map((b) => b.name).toSet();

      await insertBranch(name: 'فرع نشط حديث');
      await insertBranch(name: 'فرع غير نشط', isActive: false);
      await insertBranch(name: 'فرع محذوف', deletedAt: DateTime.now());

      container.invalidate(branchListProvider);
      final after = await container.read(branchListProvider.future);
      final afterNames = after.map((b) => b.name).toSet();
      final added = afterNames.difference(baselineNames);

      expect(added, contains('فرع نشط حديث'),
          reason: 'Active+undeleted branch must appear');
      expect(added, isNot(contains('فرع غير نشط')),
          reason: 'Inactive branch must be hidden');
      expect(added, isNot(contains('فرع محذوف')),
          reason: 'Soft-deleted branch must be hidden');
    });

    test('an active branch that becomes deleted disappears on next read',
        () async {
      final id = await insertBranch(name: 'فرع يتم حذفه');

      var list = await container.read(branchListProvider.future);
      expect(list.map((b) => b.name), contains('فرع يتم حذفه'));

      await (db.update(db.branches)..where((b) => b.id.equals(id)))
          .write(BranchesCompanion(deletedAt: Value(DateTime.now())));

      container.invalidate(branchListProvider);
      list = await container.read(branchListProvider.future);
      expect(list.map((b) => b.name), isNot(contains('فرع يتم حذفه')));
    });
  });
}
