// Audit B ACC-007 / ACC-008 / ACC-009.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/domain/entities/accounting_entities.dart';

void main() {
  late AppDatabase db;
  late int cash;
  late int other;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    cash = (await db.getAccountByCode('1111'))!.id;
    other = (await db.getAccountByCode('4121'))!.id;
    await db.into(db.fiscalYears).insert(FiscalYearsCompanion.insert(
        name: '2025', startDate: DateTime(2025, 1, 1), endDate: DateTime(2025, 12, 31)));
    await db.into(db.fiscalYears).insert(FiscalYearsCompanion.insert(
        name: '2026', startDate: DateTime(2026, 1, 1), endDate: DateTime(2026, 12, 31)));
  });
  tearDown(() => db.close());

  List<JournalLine> lines(double a) => [
        JournalLine(accountId: cash, debit: a),
        JournalLine(accountId: other, credit: a),
      ];

  test('ACC-009: the entry number year follows the entry date, not today', () async {
    final id = await db.createJournalEntry(
        description: 'back-dated', date: DateTime(2025, 12, 28), lines: lines(10));
    final e = await (db.select(db.journalEntries)..where((x) => x.id.equals(id))).getSingle();
    expect(e.entryNumber, startsWith('JE-2025-'));
  });

  test('ACC-008: reverseTransaction reverses every entry of a reference, not just the first',
      () async {
    for (final a in [10.0, 20.0]) {
      await db.createJournalEntry(
          description: 'src $a',
          date: DateTime(2026, 3, 1),
          lines: lines(a),
          referenceType: 'asset_depreciation',
          referenceId: 7,
          isAutoPosted: true);
    }
    await db.reverseTransaction(
        referenceType: 'asset_depreciation',
        referenceId: 7,
        descriptionPrefix: 'rev',
        newReferenceType: 'asset_depreciation_reversal');
    final reversals = await (db.select(db.journalEntries)
          ..where((e) => e.referenceType.equals('asset_depreciation_reversal')))
        .get();
    expect(reversals, hasLength(2));
    expect(reversals.map((r) => r.referenceId).toSet().length, 2);
  });

  test('ACC-007: AR reconciliation counts deactivated customers too', () async {
    final id = await db.insertParty(PartiesCompanion.insert(
        name: 'old', isCustomer: const Value(true), balance: const Value(300)));
    await (db.update(db.parties)..where((p) => p.id.equals(id)))
        .write(const PartiesCompanion(isActive: Value(false)));
    final r = await db.getArReconciliation();
    expect(r, isNotNull);
    expect(r!.difference.abs(), lessThan(0.01),
        reason: 'the card (300) and its opening-balance JE must reconcile');
  });
}
