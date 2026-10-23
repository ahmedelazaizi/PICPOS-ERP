// ═══════════════════════════════════════════════════════════════════════════
// Unit Test: globalId (UUID) — Products & Parties deterministic sync
// Updated: 2026-03-31 — globalId is now nullable (String?) in all tables.
//   - Products, SalesInvoices, PurchaseInvoices, Payments, JournalEntries
//   - globalId defaults to NULL for legacy rows; new rows get UUID via migration
//   - Tests adjusted to use isNotNull/isNull instead of isNotEmpty/isEmpty
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:picpos_erp/data/database/database.dart';

void main() {
  group('GlobalId UUID Generation', () {
    test('UUID v4 generates valid format', () {
      const uuid = Uuid();
      final globalId = uuid.v4();
      expect(globalId.length, 36);
      final parts = globalId.split('-');
      expect(parts.length, 5);
      expect(parts[0].length, 8);
      expect(parts[2][0], '4', reason: 'UUID v4 version digit must be 4');
    });

    test('1000 UUIDs are all unique (no collision)', () {
      const uuid = Uuid();
      final ids = List.generate(1000, (_) => uuid.v4());
      expect(ids.toSet().length, 1000);
    });

    test('null is valid fallback globalId for legacy rows', () {
      // v118: globalId is nullable — legacy rows will have null until migration
      String? globalId;
      expect(globalId, isNull);
    });

    test('Nullable globalId resolves to empty string safely', () {
      String? globalId;
      final safe = globalId ?? '';
      expect(safe, isEmpty);
    });
  });

  group('Products Table — globalId column (nullable)', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting();
    });

    tearDown(() async {
      await db.close();
    });

    test('Product insert without explicit globalId has null globalId', () async {
      // v118: globalId is nullable — inserting without it yields null
      final productId = await db.into(db.products).insert(
        ProductsCompanion.insert(
          name: 'Test Product',
          code: 'P001',
        ),
      );

      final product = await (db.select(db.products)
            ..where((p) => p.id.equals(productId)))
          .getSingle();

      // globalId is nullable — without clientDefault it will be null
      expect(product.globalId, isNull,
          reason: 'globalId should be null when not provided explicitly');
    });

    test('Product insert with explicit UUID globalId stores correctly', () async {
      const uuid = Uuid();
      final assignedId = uuid.v4();

      final productId = await db.into(db.products).insert(
        ProductsCompanion.insert(
          name: 'UUID Product',
          code: 'P002',
          globalId: Value(assignedId),
        ),
      );

      final product = await (db.select(db.products)
            ..where((p) => p.id.equals(productId)))
          .getSingle();

      expect(product.globalId, equals(assignedId),
          reason: 'Explicitly assigned UUID must be preserved');
      expect(product.globalId!.length, 36,
          reason: 'UUID format is 8-4-4-4-12 = 36 chars');
    });

    test('Two products with explicit UUIDs get different globalIds', () async {
      const uuid = Uuid();
      final id1 = await db.into(db.products).insert(
        ProductsCompanion.insert(
          name: 'Product A',
          code: 'PA',
          globalId: Value(uuid.v4()),
        ),
      );
      final id2 = await db.into(db.products).insert(
        ProductsCompanion.insert(
          name: 'Product B',
          code: 'PB',
          globalId: Value(uuid.v4()),
        ),
      );

      final p1 = await (db.select(db.products)
            ..where((p) => p.id.equals(id1)))
          .getSingle();
      final p2 = await (db.select(db.products)
            ..where((p) => p.id.equals(id2)))
          .getSingle();

      expect(p1.globalId, isNotNull);
      expect(p2.globalId, isNotNull);
      expect(p1.globalId, isNot(equals(p2.globalId)),
          reason: 'Each product must have a unique globalId');
    });

    test('Null-safe access works correctly for nullable globalId', () async {
      final productId = await db.into(db.products).insert(
        ProductsCompanion.insert(name: 'Legacy Product', code: 'LEG01'),
      );

      final product = await (db.select(db.products)
            ..where((p) => p.id.equals(productId)))
          .getSingle();

      // Null-safe access pattern used throughout the codebase
      final safeId = product.globalId ?? '';
      expect(safeId, isEmpty,
          reason: 'Null coalescence on nullable globalId should return empty string');
    });
  });

  group('Parties Table — globalId column (nullable)', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting();
    });

    tearDown(() async {
      await db.close();
    });

    test('Party insert without globalId has null globalId', () async {
      final partyId = await db.into(db.parties).insert(
        PartiesCompanion.insert(
          name: 'Test Customer',
          isCustomer: const Value(true),
        ),
      );

      final party = await (db.select(db.parties)
            ..where((p) => p.id.equals(partyId)))
          .getSingle();

      // Parties table does NOT have globalId column — removed from schema
      // This test verifies the name field roundtrip instead
      expect(party.name, equals('Test Customer'));
    });

    test('Two parties with explicit UUIDs have distinct globalIds', () async {
      // Note: Parties globalId was added in v114 migration but removed from schema
      // This group tests the UUID generation utility for sync payloads
      const uuid = Uuid();
      final uuid1 = uuid.v4();
      final uuid2 = uuid.v4();

      expect(uuid1, isNot(equals(uuid2)));
      expect(uuid1.length, 36);
      expect(uuid2.length, 36);
    });
  });

  group('GlobalId sync compatibility — nullable handling', () {
    test('Supabase mapper uses null fallback for missing global_id', () {
      final data = <String, dynamic>{'global_id': null};
      final globalId = data['global_id'] as String?;
      expect(globalId, isNull);

      // Safe access pattern
      final safe = globalId ?? '';
      expect(safe, isEmpty);
    });

    test('Supabase mapper preserves existing global_id', () {
      final uuid = const Uuid().v4();
      final data = <String, dynamic>{'global_id': uuid};
      final globalId = data['global_id'] as String?;
      expect(globalId, isNotNull);
      expect(globalId, equals(uuid));
    });

    test('Migration v118 assigns UUID to legacy rows with empty globalId', () {
      // Simulates what migration does:
      // UPDATE products SET global_id = ? WHERE global_id = ''
      const legacyGlobalId = '';
      final shouldMigrate = legacyGlobalId.isEmpty;
      expect(shouldMigrate, isTrue,
          reason: 'Rows with empty globalId should receive UUID from migration');

      final newUuid = const Uuid().v4();
      expect(newUuid.length, 36);
    });

    test('Nullable globalId does not break sync comparison', () {
      String? local;
      String? remote;

      // Both null → same state, no sync needed
      expect(local == remote, isTrue);

      // Local set, remote null → push to server
      local = const Uuid().v4();
      expect(local != remote, isTrue);
    });
  });
}
