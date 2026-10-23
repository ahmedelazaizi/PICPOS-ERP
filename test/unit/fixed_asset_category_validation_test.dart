// Feature 050 (v132) — Fixed-asset category creation validation.
//
// The "أصل ثابت جديد" dialog used to throw
// `MissingCategoryAccountException` at the end of a long form when the
// chosen category had `accountId == null`. The user lost everything
// they typed. The fix is two-layered:
//
//   1. `createAssetCategory` rejects null accountId / depreciationAccountId
//      at the source — no broken row can be inserted.
//   2. The asset-creation dialog filters categories with null accountId
//      out of its dropdown (UI test, not covered here).
//
// These tests cover Layer 1 only. The UI gate is exercised through
// manual testing per the spec.

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int assetAcctId;
  late int deprecAcctId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    // Use the seeded vehicles asset account + accumulated-depreciation
    // account so the tests run against realistic GL ids without having
    // to invent ad-hoc accounts.
    assetAcctId = (await (db.select(db.accounts)
              ..where((a) => a.code.equals('1213')))
            .getSingle())
        .id;
    // Any second account will do for the deprec slot — pick anything
    // existing rather than minting one (keeps the test independent of
    // CoA seed details).
    deprecAcctId = (await (db.select(db.accounts)..limit(1)).getSingle()).id;
  });

  tearDown(() async {
    await db.close();
  });

  group('createAssetCategory — Feature 050 guard', () {
    test('rejects null accountId with Arabic message', () async {
      Object? thrown;
      try {
        await db.createAssetCategory(
          name: 'مركبات بدون حساب',
          accountId: null,
          depreciationAccountId: deprecAcctId,
        );
      } catch (e) {
        thrown = e;
      }
      expect(thrown, isNotNull,
          reason: 'the DAO must refuse to insert a row that can never '
              'back a fixed-asset creation');
      expect(thrown.toString(), contains('حساب الأصل'),
          reason: 'the operator needs to see WHICH field they missed');

      // And nothing landed in the table.
      final rows = await db.select(db.assetCategories).get();
      expect(rows, isEmpty);
    });

    test('rejects null depreciationAccountId — symmetric', () async {
      Object? thrown;
      try {
        await db.createAssetCategory(
          name: 'مركبات بدون مجمع',
          accountId: assetAcctId,
          depreciationAccountId: null,
        );
      } catch (e) {
        thrown = e;
      }
      expect(thrown, isNotNull);
      expect(thrown.toString(), contains('مجمع الإهلاك'));

      final rows = await db.select(db.assetCategories).get();
      expect(rows, isEmpty);
    });

    test('rejects when BOTH are null', () async {
      Object? thrown;
      try {
        await db.createAssetCategory(name: 'فئة فارغة');
      } catch (e) {
        thrown = e;
      }
      expect(thrown, isNotNull);
      final rows = await db.select(db.assetCategories).get();
      expect(rows, isEmpty);
    });

    test('accepts when both accounts are supplied — happy path', () async {
      final id = await db.createAssetCategory(
        name: 'مركبات',
        accountId: assetAcctId,
        depreciationAccountId: deprecAcctId,
        defaultUsefulLife: 5,
      );
      expect(id, greaterThan(0));

      final row = await (db.select(db.assetCategories)
            ..where((c) => c.id.equals(id)))
          .getSingle();
      expect(row.accountId, assetAcctId);
      expect(row.depreciationAccountId, deprecAcctId);
      expect(row.name, 'مركبات');
    });
  });

  group('updateAssetCategoryById — preserves existing semantics', () {
    test('passing accountId=null keeps the previous accountId '
        '(Value.absent semantics preserved)', () async {
      final id = await db.createAssetCategory(
        name: 'مركبات',
        accountId: assetAcctId,
        depreciationAccountId: deprecAcctId,
      );

      // Caller is renaming only — should not zero out the GL link.
      await db.updateAssetCategoryById(
        id,
        name: 'مركبات (معدلة)',
        accountId: null,
        depreciationAccountId: null,
      );

      final row = await (db.select(db.assetCategories)
            ..where((c) => c.id.equals(id)))
          .getSingle();
      expect(row.name, 'مركبات (معدلة)');
      expect(row.accountId, assetAcctId,
          reason: 'rename-only flow must not strip the asset account');
      expect(row.depreciationAccountId, deprecAcctId,
          reason: 'rename-only flow must not strip the deprec account');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Feature 052 (v132) — updateAssetCategoryById now also accepts
  // defaultUsefulLife + defaultDepreciationMethod. The edit-category dialog
  // surfaces these so the user can correct them without re-creating the
  // category. Only seeds defaults for new assets — does NOT touch past
  // assets' depreciation schedules.
  // ─────────────────────────────────────────────────────────────────────────
  group('updateAssetCategoryById — Feature 052 useful life / method', () {
    test('updates defaultUsefulLife when supplied', () async {
      final id = await db.createAssetCategory(
        name: 'مركبات',
        accountId: assetAcctId,
        depreciationAccountId: deprecAcctId,
        defaultUsefulLife: 5,
      );

      await db.updateAssetCategoryById(
        id,
        name: 'مركبات',
        defaultUsefulLife: 7,
      );

      final row = await (db.select(db.assetCategories)
            ..where((c) => c.id.equals(id)))
          .getSingle();
      expect(row.defaultUsefulLife, 7);
    });

    test('updates defaultDepreciationMethod when supplied', () async {
      final id = await db.createAssetCategory(
        name: 'مركبات',
        accountId: assetAcctId,
        depreciationAccountId: deprecAcctId,
      );
      expect(
          (await (db.select(db.assetCategories)
                    ..where((c) => c.id.equals(id)))
                  .getSingle())
              .defaultDepreciationMethod,
          'straight_line',
          reason: 'create defaults to straight_line');

      await db.updateAssetCategoryById(
        id,
        name: 'مركبات',
        defaultDepreciationMethod: 'declining_balance',
      );

      final row = await (db.select(db.assetCategories)
            ..where((c) => c.id.equals(id)))
          .getSingle();
      expect(row.defaultDepreciationMethod, 'declining_balance');
    });

    test('null defaultUsefulLife + null method leave existing values alone '
        '(Value.absent semantics extend to the new fields)', () async {
      final id = await db.createAssetCategory(
        name: 'مركبات',
        accountId: assetAcctId,
        depreciationAccountId: deprecAcctId,
        defaultUsefulLife: 5,
        defaultDepreciationMethod: 'declining_balance',
      );

      // Rename-only: should not zero out the defaults.
      await db.updateAssetCategoryById(
        id,
        name: 'مركبات (معدلة)',
        defaultUsefulLife: null,
        defaultDepreciationMethod: null,
      );

      final row = await (db.select(db.assetCategories)
            ..where((c) => c.id.equals(id)))
          .getSingle();
      expect(row.name, 'مركبات (معدلة)');
      expect(row.defaultUsefulLife, 5,
          reason: 'rename-only must preserve useful life');
      expect(row.defaultDepreciationMethod, 'declining_balance',
          reason: 'rename-only must preserve depreciation method');
    });
  });
}
