// ═══════════════════════════════════════════════════════════════════════════
// Feature 004 (Multi-Branch Governance, US1) — Fixed Assets DAO atomic linkage tests
// ═══════════════════════════════════════════════════════════════════════════
//
// Covers spec.md FRs:
//   FR-002  — FixedAsset + per-asset CoA sub-account in same db.transaction()
//   FR-003  — sub-account placed under asset_categories.accountId with
//             deterministic '{parentCode}-{NNNNN}' suffix
//   FR-004  — both rows carry UUIDv7 globalId; fixed_assets.linkedAccountId
//             points at the new sub-account
//   FR-005  — MissingCategoryAccountException rolls back the whole save
//   FR-006  — renaming an asset propagates to its linked account name
//   FR-007  — deleting an asset with GL movements is rejected
//
//   **CONSTITUTION I (Behavior Preservation)**: the acquisition JE continues
//   to debit the CATEGORY's account, NOT the new per-asset sub-account.
//   This is asserted explicitly below.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int categoryId;
  late int categoryAccountId; // the parent under which sub-accounts mint
  late DateTime fixedDate;

  setUp(() async {
    db = AppDatabase.forTesting();
    // syncDefaultAccounts() also runs inside createFixedAsset, but seeding it
    // up-front lets us fetch IDs for asserts before we exercise the method.
    await db.syncDefaultAccounts();
    final vehicles = await (db.select(db.accounts)
          ..where((a) => a.code.equals('1213')))
        .getSingle();
    categoryAccountId = vehicles.id;

    categoryId = await db.into(db.assetCategories).insert(
          AssetCategoriesCompanion.insert(
            name: 'مركبات',
            accountId: Value(categoryAccountId),
          ),
        );
    fixedDate = DateTime(2026, 5, 2);
  });

  tearDown(() async {
    await db.close();
  });

  group('createFixedAsset — happy path', () {
    test('creates per-asset sub-account under category account, atomically', () async {
      final assetId = await db.createFixedAsset(
        code: 'V-001',
        name: 'سيارة شركة 001',
        categoryId: categoryId,
        purchasePrice: 100000,
        purchaseDate: fixedDate,
        usefulLifeYears: 5,
      );
      expect(assetId, greaterThan(0));

      final asset = await (db.select(db.fixedAssets)
            ..where((a) => a.id.equals(assetId)))
          .getSingle();
      expect(asset.linkedAccountId, isNotNull);
      expect(asset.globalId, isNotNull);

      final subAccount = await (db.select(db.accounts)
            ..where((a) => a.id.equals(asset.linkedAccountId!)))
          .getSingle();
      expect(subAccount.parentId, categoryAccountId);
      expect(subAccount.name, 'سيارة شركة 001');
      expect(subAccount.code, startsWith('1213-'));
      expect(subAccount.code.split('-').last.length, 5);
      expect(subAccount.globalId, isNotNull);
      expect(subAccount.globalId, isNot(equals(asset.globalId)));
    });
  });

  group('createFixedAsset — Constitution I (Behavior Preservation)', () {
    test('acquisition JE debits CATEGORY account, NOT the new sub-account', () async {
      final assetId = await db.createFixedAsset(
        code: 'V-002',
        name: 'سيارة 002',
        categoryId: categoryId,
        purchasePrice: 50000,
        purchaseDate: fixedDate,
        usefulLifeYears: 5,
      );
      final asset = await (db.select(db.fixedAssets)
            ..where((a) => a.id.equals(assetId)))
          .getSingle();
      final perAssetAccountId = asset.linkedAccountId!;

      // Locate the acquisition JE (referenceType='fixed_asset', referenceId=assetId).
      final je = await (db.select(db.journalEntries)
            ..where((j) =>
                j.referenceType.equals('fixed_asset') &
                j.referenceId.equals(assetId)))
          .getSingle();

      // All lines for that JE.
      final lines = await (db.select(db.journalEntryLines)
            ..where((l) => l.entryId.equals(je.id)))
          .get();
      expect(lines.length, 2);

      final debitLine = lines.firstWhere((l) => l.debit > 0);
      final creditLine = lines.firstWhere((l) => l.credit > 0);

      // ✅ The debit lands on the CATEGORY account (1213), preserving v1
      // behavior. The per-asset sub-account holds zero entries.
      expect(debitLine.accountId, categoryAccountId);
      expect(debitLine.accountId, isNot(equals(perAssetAccountId)));
      expect(debitLine.debit, 50000);

      // The credit goes to the contra account (default 1111 in this test).
      expect(creditLine.credit, 50000);
      expect(creditLine.accountId, isNot(equals(perAssetAccountId)));

      // The per-asset sub-account has NO journal-entry lines whatsoever.
      final perAssetMovementCount = await (db.selectOnly(db.journalEntryLines)
            ..addColumns([db.journalEntryLines.id.count()])
            ..where(db.journalEntryLines.accountId.equals(perAssetAccountId)))
          .map((row) => row.read(db.journalEntryLines.id.count()))
          .getSingle();
      expect(perAssetMovementCount, 0);
    });
  });

  group('createFixedAsset — failure paths', () {
    test('throws MissingCategoryAccountException when category.accountId is null', () async {
      // Create a category WITHOUT a linked accountId.
      final orphanCategoryId = await db.into(db.assetCategories).insert(
            AssetCategoriesCompanion.insert(name: 'فئة بدون حساب'),
          );

      expect(
        () => db.createFixedAsset(
          code: 'X-001',
          name: 'orphan asset',
          categoryId: orphanCategoryId,
          purchasePrice: 1000,
          purchaseDate: fixedDate,
          usefulLifeYears: 3,
        ),
        throwsA(isA<MissingCategoryAccountException>()),
      );

      // No asset row was persisted.
      final assets = await (db.select(db.fixedAssets)
            ..where((a) => a.code.equals('X-001')))
          .get();
      expect(assets, isEmpty);
    });
  });

  group('FR-006 — rename propagates', () {
    test('updateFixedAsset(name: ...) renames the linked sub-account', () async {
      final assetId = await db.createFixedAsset(
        code: 'V-003',
        name: 'الاسم الأصلى',
        categoryId: categoryId,
        purchasePrice: 1000,
        purchaseDate: fixedDate,
        usefulLifeYears: 3,
      );
      final original = await (db.select(db.fixedAssets)
            ..where((a) => a.id.equals(assetId)))
          .getSingle();

      await db.updateFixedAsset(assetId, name: 'الاسم الجديد');

      final renamed = await (db.select(db.fixedAssets)
            ..where((a) => a.id.equals(assetId)))
          .getSingle();
      final account = await (db.select(db.accounts)
            ..where((a) => a.id.equals(original.linkedAccountId!)))
          .getSingle();

      expect(renamed.name, 'الاسم الجديد');
      expect(account.name, 'الاسم الجديد');
    });

    test('updating other fields without changing name does NOT touch the account name', () async {
      final assetId = await db.createFixedAsset(
        code: 'V-004',
        name: 'لا يتغير',
        categoryId: categoryId,
        purchasePrice: 1000,
        purchaseDate: fixedDate,
        usefulLifeYears: 3,
      );
      final original = await (db.select(db.fixedAssets)
            ..where((a) => a.id.equals(assetId)))
          .getSingle();

      await db.updateFixedAsset(assetId, location: 'فرع الشرق');

      final account = await (db.select(db.accounts)
            ..where((a) => a.id.equals(original.linkedAccountId!)))
          .getSingle();
      expect(account.name, 'لا يتغير');
    });
  });

  group('FR-007 — delete-guard', () {
    test('rejects deletion when the per-asset sub-account has GL movements', () async {
      final assetId = await db.createFixedAsset(
        code: 'V-005',
        name: 'أصل به حركات',
        categoryId: categoryId,
        purchasePrice: 1000,
        purchaseDate: fixedDate,
        usefulLifeYears: 3,
      );
      final asset = await (db.select(db.fixedAssets)
            ..where((a) => a.id.equals(assetId)))
          .getSingle();

      // Inject a movement against the per-asset sub-account (simulating a
      // future per-asset depreciation entry).
      final jeId = await db.into(db.journalEntries).insert(
            JournalEntriesCompanion.insert(
              entryNumber: 'JE-DEP-001',
              entryDate: fixedDate,
              description: const Value('simulated future depreciation'),
            ),
          );
      await db.into(db.journalEntryLines).insert(
            JournalEntryLinesCompanion.insert(
              entryId: jeId,
              accountId: asset.linkedAccountId!,
              debit: const Value(0),
              credit: const Value(50),
            ),
          );

      expect(
        () => db.deleteFixedAsset(assetId),
        throwsA(isA<Exception>()),
      );

      final stillThere = await (db.select(db.fixedAssets)
            ..where((a) => a.id.equals(assetId)))
          .getSingleOrNull();
      expect(stillThere, isNotNull);
    });

    test('allows deletion when the per-asset sub-account has no movements', () async {
      // Note: the acquisition JE debits the CATEGORY account, NOT the per-asset
      // sub-account, so a freshly-created asset is delete-able.
      final assetId = await db.createFixedAsset(
        code: 'V-006',
        name: 'أصل بدون حركات على حسابه الفرعى',
        categoryId: categoryId,
        purchasePrice: 1000,
        purchaseDate: fixedDate,
        usefulLifeYears: 3,
      );

      final n = await db.deleteFixedAsset(assetId);
      expect(n, 1);

      final gone = await (db.select(db.fixedAssets)
            ..where((a) => a.id.equals(assetId)))
          .getSingleOrNull();
      expect(gone, isNull);
    });
  });
}
