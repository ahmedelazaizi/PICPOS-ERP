// ═══════════════════════════════════════════════════════════════════════════
// Feature 006 #4 — activeWarehouseIdProvider per-branch resolution
// ═══════════════════════════════════════════════════════════════════════════
//
// Resolution order (post-006):
//   1. Manual override (activeWarehouseOverrideProvider)
//   2. Per-branch setting `pos_default_warehouse_branch_<branchId>`
//   3. Global setting `pos_default_warehouse_id`
//   4. Active branch warehouse
//   5. Repository default warehouse
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/providers.dart';

void main() {
  late AppDatabase db;
  late int branchA;
  late int branchB;
  late int defaultWh;
  late int whAlt;
  late int whBranchSpecific;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();

    branchA = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'A',
            globalId: const Value('gid-br-A'),
          ),
        );
    branchB = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'B',
            globalId: const Value('gid-br-B'),
          ),
        );

    // forTesting() pre-seeds a default warehouse — read it instead of
    // creating a second "default" (which would lose to the seeded one
    // when getDefaultWarehouse() picks the first match).
    final seededDefault = await db.getDefaultWarehouse();
    defaultWh = seededDefault?.id ??
        await db.into(db.warehouses).insert(
              WarehousesCompanion.insert(
                name: 'default-wh',
                isDefault: const Value(true),
                globalId: const Value('gid-wh-default'),
              ),
            );
    whAlt = await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(
            name: 'alt-wh',
            globalId: const Value('gid-wh-alt'),
          ),
        );
    whBranchSpecific = await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(
            name: 'branch-A-wh',
            branchId: Value(branchA),
            globalId: const Value('gid-wh-branchA'),
          ),
        );
  });

  tearDown(() => db.close());

  /// Builds a container that overrides the database + active branch so the
  /// resolver runs against the in-memory DB instead of touching the
  /// platform-specific encrypted SQLite stack.
  ProviderContainer makeContainer({int? activeBranchId}) {
    return ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      activeBranchIdProvider.overrideWith((_) async => activeBranchId),
    ]);
  }

  test('falls back to repository default warehouse when no settings present',
      () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    final resolved = await container.read(activeWarehouseIdProvider.future);
    expect(resolved, defaultWh);
  });

  test('falls back to the active branch warehouse before global repository default',
      () async {
    final container = makeContainer(activeBranchId: branchA);
    addTearDown(container.dispose);

    final resolved = await container.read(activeWarehouseIdProvider.future);
    expect(resolved, whBranchSpecific);
  });

  test('uses global pos_default_warehouse_id when no per-branch override',
      () async {
    await db.setSetting('pos_default_warehouse_id', whAlt.toString());
    final container = makeContainer(activeBranchId: branchA);
    addTearDown(container.dispose);

    expect(
      await container.read(activeWarehouseIdProvider.future),
      whAlt,
      reason: 'global setting wins over the repository default',
    );
  });

  test('per-branch setting beats the global one', () async {
    await db.setSetting('pos_default_warehouse_id', whAlt.toString());
    await db.setSetting(
      'pos_default_warehouse_branch_$branchA',
      whBranchSpecific.toString(),
    );

    final container = makeContainer(activeBranchId: branchA);
    addTearDown(container.dispose);

    expect(
      await container.read(activeWarehouseIdProvider.future),
      whBranchSpecific,
      reason: 'per-branch override is the whole point of #4',
    );
  });

  test('per-branch setting only applies to the matching branch', () async {
    await db.setSetting('pos_default_warehouse_id', whAlt.toString());
    await db.setSetting(
      'pos_default_warehouse_branch_$branchA',
      whBranchSpecific.toString(),
    );

    final container = makeContainer(activeBranchId: branchB);
    addTearDown(container.dispose);

    expect(
      await container.read(activeWarehouseIdProvider.future),
      whAlt,
      reason: 'branchB has no per-branch setting → falls back to global',
    );
  });

  test('manual override wins over every setting', () async {
    await db.setSetting('pos_default_warehouse_id', whAlt.toString());
    await db.setSetting(
      'pos_default_warehouse_branch_$branchA',
      whBranchSpecific.toString(),
    );

    final container = makeContainer(activeBranchId: branchA);
    addTearDown(container.dispose);

    container
        .read(activeWarehouseOverrideProvider.notifier)
        .set(defaultWh);

    expect(
      await container.read(activeWarehouseIdProvider.future),
      defaultWh,
      reason: 'explicit override is the highest priority',
    );
  });

  test('empty per-branch setting falls through to global, not zero',
      () async {
    await db.setSetting('pos_default_warehouse_id', whAlt.toString());
    // The settings UI writes an empty string when the user clears the
    // per-branch picker. Resolver must treat that as "no override".
    await db.setSetting('pos_default_warehouse_branch_$branchA', '');

    final container = makeContainer(activeBranchId: branchA);
    addTearDown(container.dispose);

    expect(await container.read(activeWarehouseIdProvider.future), whAlt);
  });
}
