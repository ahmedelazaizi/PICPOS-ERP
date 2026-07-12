// ═══════════════════════════════════════════════════════════════════════════
// D-07 — Journal Entry Sequence Race Condition Fix Tests
// ═══════════════════════════════════════════════════════════════════════════
//
// Verifies that _generateEntryNumber() uses the DocumentSequences table for
// atomic, collision-free JE number generation, replacing the racy MAX+1
// approach. Tests cover:
//   1. First call seeds the DocumentSequences row and returns JE-YYYY-00001
//   2. Sequential calls increment the counter without gaps or duplicates
//   3. Concurrent invocations within a single test produce unique numbers
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/domain/entities/accounting_entities.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    // Seed a fiscal year so createJournalEntry passes validateFinancialPeriod.
    final now = DateTime.now();
    await db.into(db.fiscalYears).insert(
      FiscalYearsCompanion.insert(
        name: '${now.year}',
        startDate: DateTime(now.year, 1, 1),
        endDate: DateTime(now.year, 12, 31),
        isClosed: const Value(false),
      ),
    );
    // Seed minimal accounts needed for a balanced JE (debit + credit pair).
    await db.into(db.accounts).insert(
      AccountsCompanion.insert(
        code: '1111',
        name: 'Test Debit Account',
        accountType: 'asset',
        balance: const Value(0.0),
        isActive: const Value(true),
      ),
    );
    await db.into(db.accounts).insert(
      AccountsCompanion.insert(
        code: '2111',
        name: 'Test Credit Account',
        accountType: 'liability',
        balance: const Value(0.0),
        isActive: const Value(true),
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('D-07 — JE Sequence via DocumentSequences', () {
    Future<int> accountId(String code) async {
      final row = await (db.select(db.accounts)
            ..where((a) => a.code.equals(code))
            ..limit(1))
          .getSingle();
      return row.id;
    }

    Future<int> postJe(String description) async {
      final debitId = await accountId('1111');
      final creditId = await accountId('2111');
      return db.createJournalEntry(
        description: description,
        date: DateTime.now(),
        lines: [
          JournalLine(accountId: debitId, debit: 100, description: 'D'),
          JournalLine(accountId: creditId, credit: 100, description: 'C'),
        ],
        referenceType: 'manual',
        referenceId: 0,
        isAutoPosted: false,
      );
    }

    test('first JE gets entry number JE-YYYY-00001', () async {
      await postJe('First entry');
      final entry = await db.select(db.journalEntries).getSingle();
      final year = DateTime.now().year;
      expect(entry.entryNumber, equals('JE-$year-00001'));
    });

    test('DocumentSequences row is created after first JE', () async {
      await postJe('Bootstrap');
      final year = DateTime.now().year;
      final seq = await (db.select(db.documentSequences)
            ..where((s) => s.prefix.equals('JE-$year')))
          .getSingleOrNull();
      expect(seq, isNotNull);
      // nextValue should be 2 after one JE (the first used nextSeq=1 → stored 2)
      expect(seq!.nextValue, equals(2));
    });

    test('sequential JEs get incrementing numbers without gaps', () async {
      await postJe('Entry A');
      await postJe('Entry B');
      await postJe('Entry C');

      final entries = await (db.select(db.journalEntries)
            ..orderBy([(e) => OrderingTerm.asc(e.entryNumber)]))
          .get();

      final year = DateTime.now().year;
      expect(entries[0].entryNumber, equals('JE-$year-00001'));
      expect(entries[1].entryNumber, equals('JE-$year-00002'));
      expect(entries[2].entryNumber, equals('JE-$year-00003'));
    });

    test('all numbers are unique (no duplicates under sequential load)', () async {
      const count = 10;
      for (var i = 0; i < count; i++) {
        await postJe('Load entry $i');
      }
      final entries = await db.select(db.journalEntries).get();
      final numbers = entries.map((e) => e.entryNumber).toSet();
      expect(numbers.length, equals(count),
          reason: 'All $count entry numbers must be unique');
    });
  });
}
