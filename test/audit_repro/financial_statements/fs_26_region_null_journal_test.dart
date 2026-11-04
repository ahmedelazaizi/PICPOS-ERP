import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/repositories/drift_accounting_repository.dart';

const _skip = 'audit repro — pending owner approval';

void main() {
  late AppDatabase db;
  late DriftAccountingRepository reports;
  late int cashId;
  late int revenueId;
  late int regionId;

  const amount = 10.0;
  final from = DateTime(2026, 1, 1);
  final to = DateTime(2026, 12, 31);

  setUp(() async {
    db = AppDatabase.forTesting();
    reports = DriftAccountingRepository(db);
    await db.syncDefaultAccounts();
    cashId = (await db.getAccountByCode('1111'))!.id;
    revenueId = (await db.getAccountByCode('4121'))!.id;
    regionId = await db.into(db.regions).insert(RegionsCompanion.insert(
      name: 'FS-26 audit region', globalId: const Value('fs26-region-1'),
    ));
    for (var i = 1; i <= 2; i++) {
      await db.into(db.branches).insert(BranchesCompanion.insert(
        name: 'FS-26 branch $i', code: Value('FS26-$i'),
        globalId: Value('fs26-branch-$i'), regionId: Value(regionId),
      ));
    }
    final entryId = await db.into(db.journalEntries).insert(
      JournalEntriesCompanion.insert(
        entryNumber: 'FS26-GLOBAL-1', entryDate: DateTime(2026, 6, 1),
        isPosted: const Value(true),
      ),
    );
    await db.into(db.journalEntryLines).insert(JournalEntryLinesCompanion.insert(
      entryId: entryId, accountId: cashId, debit: const Value(amount),
    ));
    await db.into(db.journalEntryLines).insert(JournalEntryLinesCompanion.insert(
      entryId: entryId, accountId: revenueId, credit: const Value(amount),
    ));
  });
  tearDown(() => db.close());

  test('FS-26 a region counts a NULL-branch journal once in all statements',
      skip: _skip, () async {
    final trialBalance = await reports.getTrialBalance(from, to, regionId: regionId);
    final cashRow = trialBalance.singleWhere((row) => row['code'] == '1111');
    final income = await reports.getIncomeStatement(from, to, regionId: regionId);
    final balance = await reports.getBalanceSheet(to, regionId: regionId);
    final actual = <String, double>{
      'trialBalance.cashMovementDebit': (cashRow['movementDebit'] as num).toDouble(),
      'incomeStatement.totalRevenue': (income['totalRevenue'] as num).toDouble(),
      'balanceSheet.totalAssets': (balance['totalAssets'] as num).toDouble(),
    };
    // ignore: avoid_print
    print('[AUDIT-FS-26] expectedEach=$amount actual=$actual');
    expect(actual, {
      'trialBalance.cashMovementDebit': amount,
      'incomeStatement.totalRevenue': amount,
      'balanceSheet.totalAssets': amount,
    });
  });
}
