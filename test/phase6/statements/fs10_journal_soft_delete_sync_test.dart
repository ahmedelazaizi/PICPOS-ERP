import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/services/delta_pull_service.dart';
import 'package:picpos_erp/data/repositories/drift_accounting_repository.dart';
import 'package:picpos_erp/domain/entities/accounting_entities.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    DeltaPullService.instance.initialize(db);
    await db.syncDefaultAccounts();
  });

  tearDown(() => db.close());

  test('incoming journal soft-delete recalculates affected stored balances',
      () async {
    final expense = (await db.getAccountByCode('6213'))!;
    final accumulatedDepreciation = (await db.getAccountByCode('1219'))!;
    final entryId = await db.createJournalEntry(
      description: 'FS-10 inbound soft-delete reconciliation',
      date: DateTime.now(),
      referenceType: 'depreciation',
      lines: [
        JournalLine(accountId: expense.id, debit: 100),
        JournalLine(accountId: accumulatedDepreciation.id, credit: 100),
      ],
    );
    expect((await db.getAccountByCode('6213'))!.balance, closeTo(100, 0.005));

    await DeltaPullService.instance.upsertRowForTest(
      'journal_entries',
      {
        'id': entryId,
        'deleted_at': DateTime.now().millisecondsSinceEpoch,
      },
    );

    final storedEntry = await (db.select(db.journalEntries)
          ..where((entry) => entry.id.equals(entryId)))
        .getSingle();
    expect(storedEntry.isDeleted, isTrue);
    expect((await db.getAccountByCode('6213'))!.balance, closeTo(0, 0.005));
    expect(
      await DriftAccountingRepository(db).getCalculatedAccountBalance(expense.id),
      closeTo(0, 0.005),
    );
  });
}
