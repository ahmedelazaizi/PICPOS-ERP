import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/migrations/fiscal_year_overlap_repair.dart';
import 'package:picpos_erp/domain/entities/accounting_entities.dart';
import '../../audit_repro/financial_statements/_fs_world.dart';

void main() {
  late ScenarioWorld world;
  setUp(() async => world = await ScenarioWorld.create());
  tearDown(() => world.dispose());

  test('automatic ensure repeated twice reuses a single year', () async {
    final before = (await world.db.getFiscalYears()).length;
    final start = DateTime(2032, 1, 1);
    final end = DateTime(2032, 12, 31);
    final first = await world.db.ensureFiscalYear(
      name: 'السنة المالية 2032', startDate: start, endDate: end,
    );
    final second = await world.db.ensureFiscalYear(
      name: '2032', startDate: start, endDate: end,
    );
    expect(second, first);
    expect((await world.db.getFiscalYears()).length, before + 1);
  });

  test('disables an unreferenced duplicate id=2 and is idempotent', () async {
    await world.db.into(world.db.fiscalYears).insert(FiscalYearsCompanion.insert(
      name: '2026', startDate: DateTime(2026), endDate: DateTime(2026, 12, 31),
      isCurrent: const Value(false),
    ));
    final beforePeriods = await world.db.select(world.db.accountingPeriods).get();
    final beforeEntries = await world.db.select(world.db.journalEntries).get();
    final first = await repairFiscalYearOverlap(world.db);
    final target = await (world.db.select(world.db.fiscalYears)
      ..where((year) => year.id.equals(2))).getSingle();
    expect(first.changed, isTrue);
    expect(target.deletedAt, isNotNull);
    expect(target.isCurrent, isFalse);
    expect((await world.db.select(world.db.accountingPeriods).get()).length,
        beforePeriods.length);
    expect((await world.db.select(world.db.journalEntries).get()).length,
        beforeEntries.length);
    expect(first.journalEntryCountAfter, first.journalEntryCountBefore);
    expect(first.accountBalancesAfter, first.accountBalancesBefore);
    expect((await world.db.getFiscalYears()).any((year) => year.id == 2), isFalse);
    expect(await world.db.getIncomeStatement(DateTime(2026),
        DateTime(2026, 12, 31, 23, 59, 59, 999)), isNotEmpty);
    expect(await world.db.getBalanceSheet(DateTime(2026, 12, 31)), isNotEmpty);

    final second = await repairFiscalYearOverlap(world.db);
    expect(second.changed, isFalse);
    expect(second.journalEntryCountAfter, first.journalEntryCountAfter);
    expect(second.accountBalancesAfter, first.accountBalancesAfter);
  });

  test('does not disable id=2 when a journal entry references it', () async {
    final duplicateId = await world.db.into(world.db.fiscalYears).insert(
      FiscalYearsCompanion.insert(name: 'linked duplicate',
        startDate: DateTime(2026), endDate: DateTime(2026, 12, 31),
        isCurrent: const Value(false)),
    );
    expect(duplicateId, 2);
    final cash = (await world.db.getAccountByCode('1111'))!;
    final revenue = (await world.db.getAccountByCode('4121'))!;
    final entryId = await world.db.createJournalEntry(
      description: 'linked duplicate check',
      date: DateTime(2026, 6, 1),
      referenceType: 'opening_balance',
      lines: [
        JournalLine(accountId: cash.id, debit: 5),
        JournalLine(accountId: revenue.id, credit: 5),
      ],
    );
    expect(entryId, greaterThan(0));
    await (world.db.update(world.db.journalEntries)
      ..where((row) => row.id.equals(entryId))).write(
        JournalEntriesCompanion(fiscalYearId: Value(duplicateId)),
      );
    await expectLater(repairFiscalYearOverlap(world.db),
        throwsA(predicate((error) => error.toString().contains('مرتبطة'))));
    final year = await (world.db.select(world.db.fiscalYears)
      ..where((row) => row.id.equals(duplicateId))).getSingle();
    expect(year.deletedAt, isNull);
  });

  test('rejects a manually-created fiscal year overlapping an enabled year', () async {
    await world.db.createFiscalYear(
      name: 'السنة الأولى',
      startDate: DateTime(2030),
      endDate: DateTime(2030, 12, 31),
    );

    final countBefore = (await world.db.getFiscalYears()).length;
    await expectLater(
      world.db.createFiscalYear(
        name: 'السنة المتداخلة',
        startDate: DateTime(2030, 1, 1, 12),
        endDate: DateTime(2031, 1, 1),
      ),
      throwsA(predicate((error) => error.toString().contains('تتداخل'))),
    );
    expect((await world.db.getFiscalYears()).length, countBefore);
  });
}
