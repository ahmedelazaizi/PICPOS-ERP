import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/utils/uuid_v7.dart';
import 'package:picpos_erp/data/database/migrations/fiscal_year_overlap_repair.dart';
import 'package:picpos_erp/data/repositories/drift_accounting_repository.dart';
import '../../scenarios/scenario_world.dart';

void main() {
  late ScenarioWorld world;
  late DriftAccountingRepository repo;

  setUp(() async {
    world = await ScenarioWorld.create();
    repo = DriftAccountingRepository(world.db);
  });
  tearDown(() => world.dispose());

  test('repository watch excludes the repaired duplicate fiscal year', () async {
    await world.db.into(world.db.fiscalYears).insert(
      FiscalYearsCompanion.insert(
        name: '2026',
        startDate: DateTime(2026),
        endDate: DateTime(2026, 12, 31),
        isCurrent: const Value(false),
      ),
    );

    await repairFiscalYearOverlap(world.db);

    expect(await repo.watchFiscalYears().first, hasLength(1));
  });

  test('repository rejects overlap with the established Arabic error', () async {
    await repo.createFiscalYear(
      name: 'السنة الأولى',
      startDate: DateTime(2030),
      endDate: DateTime(2030, 12, 31),
    );

    await expectLater(
      repo.createFiscalYear(
        name: 'السنة المتداخلة',
        startDate: DateTime(2030, 1, 1, 12),
        endDate: DateTime(2031),
      ),
      throwsA(predicate((error) => error.toString().contains(
          'لا يمكن إنشاء السنة المالية: تتداخل مع السنة المفعّلة "السنة الأولى"'))),
    );
  });

  test('automatic setup ensure remains idempotent', () async {
    final start = DateTime(2040, 1, 1);
    final end = DateTime(2040, 12, 31);
    final first = await world.db.ensureFiscalYear(
      name: 'السنة المالية 2040',
      startDate: start,
      endDate: end,
    );
    final second = await world.db.ensureFiscalYear(
      name: '2040',
      startDate: start,
      endDate: end,
    );

    expect(second, first);
  });

  test('repository normalizes end of day and retains the deterministic global id',
      () async {
    final start = DateTime(2035, 1, 1);
    final suppliedEnd = DateTime(2035, 12, 31);
    const name = 'السنة المالية 2035';
    final yearId = await repo.createFiscalYear(
      name: name,
      startDate: start,
      endDate: suppliedEnd,
    );

    final year = await (world.db.select(world.db.fiscalYears)
          ..where((row) => row.id.equals(yearId)))
        .getSingle();
    // SQLite's Drift datetime codec persists epoch seconds, so milliseconds
    // are not observable after reading even though the DAO supplies .999.
    expect(year.endDate, DateTime(2035, 12, 31, 23, 59, 59));
    expect(
      year.globalId,
      UuidV7.deriveFiscalYearGlobalId(
        name: name,
        startDate: start,
        endDate: suppliedEnd,
      ),
    );
  });
}
