// Audit B ACC-001 / ACC-002 — straight-line depreciation stops at the
// depreciable amount; a missing GL mapping fails closed (no register advance).
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/domain/models/depreciation_math.dart';

void main() {
  late AppDatabase db;
  late int categoryId;
  late int contra;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    await db.into(db.fiscalYears).insert(FiscalYearsCompanion.insert(
        name: '2026', startDate: DateTime(2026, 1, 1), endDate: DateTime(2026, 12, 31)));
    final assetAcc = (await db.getAccountByCode('1213'))!;
    final accum = (await db.getAccountByCode('1219'))!;
    categoryId = await db.createAssetCategory(
        name: 'cat', accountId: assetAcc.id, depreciationAccountId: accum.id);
    contra = (await db.getAccountByCode('2111'))!.id;
  });
  tearDown(() => db.close());

  Future<int> asset({double salvage = 0, double price = 1200, double years = 1}) =>
      db.createFixedAsset(
        code: 'FA-${DateTime.now().microsecondsSinceEpoch}',
        name: 'a',
        categoryId: categoryId,
        purchasePrice: price,
        purchaseDate: DateTime(2026, 1, 1),
        usefulLifeYears: years,
        salvageValue: salvage,
        contraAccountId: contra,
      );

  Future<FixedAssetData> card(int id) => (db.select(db.fixedAssets)
        ..where((a) => a.id.equals(id)))
      .getSingle();

  test('math: straight-line is capped at the remaining depreciable amount', () {
    expect(
        monthlyDepreciation(
            purchasePrice: 1200,
            salvageValue: 0,
            usefulLifeYears: 1,
            depreciationMethod: kStraightLine,
            accumulatedDepreciation: 1200),
        0);
    expect(
        monthlyDepreciation(
            purchasePrice: 1200,
            salvageValue: 100,
            usefulLifeYears: 1,
            depreciationMethod: kStraightLine,
            accumulatedDepreciation: 1050),
        50);
  });

  test('asset imported at end of life posts nothing and is marked depreciated',
      () async {
    final id = await asset();
    await (db.update(db.fixedAssets)..where((a) => a.id.equals(id)))
        .write(const FixedAssetsCompanion(accumulatedDepreciation: Value(1200)));
    final n = await db.runMonthlyDepreciation(DateTime(2026, 3, 28));
    expect(n, 0);
    expect((await card(id)).accumulatedDepreciation, 1200);
    expect(await db.select(db.assetDepreciations).get(), isEmpty);
  });

  test('salvage value is never depreciated below; final partial month capped',
      () async {
    final id = await asset(salvage: 100, years: 1); // 1100 over 12 months
    for (var m = 1; m <= 14; m++) {
      await db.runMonthlyDepreciation(DateTime(2026, 1 + m - 1 > 12 ? 12 : m, 28));
    }
    final c = await card(id);
    expect(c.accumulatedDepreciation, closeTo(1100, 0.005));
    expect(c.purchasePrice - c.accumulatedDepreciation, closeTo(100, 0.005));
  });

  test('ACC-003: a second run in the same month on a different day posts nothing',
      () async {
    final id = await asset();
    await db.runMonthlyDepreciation(DateTime(2026, 3, 28));
    final again = await db.runMonthlyDepreciation(DateTime(2026, 3, 1));
    expect(again, 0);
    expect(await db.select(db.assetDepreciations).get(), hasLength(1));
    expect((await card(id)).accumulatedDepreciation, closeTo(100, 0.005));
  });

  test('ACC-002: a posting failure (no fiscal year) leaves the register untouched and is reported',
      () async {
    final id = await asset();
    final failures = <String>[];
    final n = await db.runMonthlyDepreciation(DateTime(2030, 3, 28), failures: failures);
    expect(n, 0);
    expect(await db.select(db.assetDepreciations).get(), isEmpty);
    expect((await card(id)).accumulatedDepreciation, 0);
    expect(failures, hasLength(1));
  });
}
