// Group C — startup performance. The stock_movements.unit_cost and sales COGS
// backfills gate behind one-shot settings flags: once no improvable row remains
// the flag is set and later boots skip the scan (returns -1 when short-circuited).
//
// fixLegacyDateTimeStrings is NOT one-shot (F-DB-1): a permanent flag would
// disable the corruption guard forever after the first clean boot, so a text
// date injected later (manual DB edit) would re-crash boot. It runs a cheap
// per-table probe every boot and repairs only tables that actually hold a text
// date — keeping the fast clean path AND the self-heal.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/database/extensions/sales_cogs_backfill_extension.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting());
  tearDown(() async => db.close());

  test('C-PERF-1/F-DB-1 fixLegacyDateTimeStrings probes every boot (no permanent skip)',
      () async {
    expect(await db.fixLegacyDateTimeStrings(), 0,
        reason: 'clean DB: cheap probe finds no text-typed dates to fix');
    // Must NOT arm a permanent one-shot flag: the corruption guard has to keep
    // running so a text date injected on a LATER boot still self-heals instead
    // of crashing Drift's int cast at boot.
    expect(await db.fixLegacyDateTimeStrings(), 0,
        reason: 'still probes on the next boot — no one-shot disable');
    expect(await db.getSettingValue('startup_fix_datetime_done'), isNull,
        reason: 'F-DB-1: the permanent skip flag must no longer be set');
  });

  test('C-PERF-2 backfillStockMovementUnitCost is one-shot on a clean DB',
      () async {
    await db.setSetting('startup_unit_cost_backfill_done', 'no');
    expect(await db.backfillStockMovementUnitCost(), 0);
    expect(await db.getSettingValue('startup_unit_cost_backfill_done'), 'true');
    expect(await db.backfillStockMovementUnitCost(), -1);
  });

  test('C-PERF-3 backfillSalesItemCostPriceOnce is one-shot on a clean DB',
      () async {
    await db.setSetting('cogs_backfill_done', 'no');
    expect(await db.backfillSalesItemCostPriceOnce(), 0);
    expect(await db.getSettingValue('cogs_backfill_done'), 'true');
    expect(await db.backfillSalesItemCostPriceOnce(), -1);
  });
}
