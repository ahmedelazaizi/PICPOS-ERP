// ═══════════════════════════════════════════════════════════════════════════
// Pre-deploy batch B1 — MJE-1 / MJE-2: reverse-by-primary-key journal entry
// ═══════════════════════════════════════════════════════════════════════════
//
// journal_entries_screen.dart's «عكس القيد» handler used to call
// reverseTransaction(referenceType: entry.referenceType ?? 'manual',
// referenceId: entry.id) — passing the entry's OWN id as a *referenceId*
// lookup key. That DAO method matches `WHERE reference_type=? AND
// reference_id=?`, so:
//   MJE-1: a manual JE (reference_id IS NULL) matches nothing → silent
//          no-op that still reports success.
//   MJE-2: an auto-posted JE whose row id happens to equal some UNRELATED
//          entry's reference_id gets that unrelated entry reversed instead,
//          corrupting its GL.
//
// reverseJournalEntryById(entryId) fixes both by loading the entry by its
// own primary key. This suite pins:
//   (a) manual JE (reference_id NULL) IS reversed, exactly once, balanced,
//       and nets the affected account balances to zero.
//   (b) calling it again on the same id is a no-op (idempotent — no dup).
//   (c) an unrelated auto-posted JE whose reference_id coincides with the
//       target's id is left completely untouched (the MJE-2 collision).
//
// Harness mirrors test/unit/je_deterministic_balancing_test.dart (in-memory
// AppDatabase.forTesting + explicit seed of exactly what the writer needs),
// with a fiscal year keyed off DateTime.now().year (test/unit/
// journal_entry_sequence_test.dart's pattern) since reverseJournalEntryById
// posts the reversal with date: DateTime.now().

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/domain/entities/accounting_entities.dart';
import 'package:ural_erp/services/network_service.dart';

void main() {
  late AppDatabase db;
  late int cashId; // asset, debit side
  late int salesId; // revenue, credit side
  late int bankId; // asset, debit side — B's unrelated leg

  setUp(() async {
    db = AppDatabase.forTesting();
    await _clearDatabase(db);
    await _seedFiscalYear(db);
    cashId = await _seedAccount(db, '1111', 'الصندوق', 'asset');
    salesId = await _seedAccount(db, '4111', 'المبيعات', 'revenue');
    bankId = await _seedAccount(db, '1121', 'البنك', 'asset');
    // Standalone → no client/server sync attempt inside createJournalEntry.
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
  });

  tearDown(() async {
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    await db.close();
  });

  group('MJE-1 — manual JE (reference_id NULL) IS reversed', () {
    test('reverseJournalEntryById creates exactly one balanced reversal and '
        'nets both account balances to zero', () async {
      final manualId = await db.createJournalEntry(
        description: 'قيد يدوي اختبار',
        date: DateTime.now(),
        lines: [
          JournalLine(accountId: cashId, debit: 100),
          JournalLine(accountId: salesId, credit: 100),
        ],
        // No referenceType/referenceId — this is exactly the MJE-1 shape
        // (reference_id IS NULL).
      );

      final beforeCount = (await db.select(db.journalEntries).get()).length;
      expect(beforeCount, 1);

      final reversalId = await db.reverseJournalEntryById(entryId: manualId);
      expect(reversalId, greaterThan(0));

      final allEntries = await db.select(db.journalEntries).get();
      expect(allEntries, hasLength(2),
          reason: 'exactly one reversal JE was created, no silent no-op');

      final reversalLines = await (db.select(db.journalEntryLines)
            ..where((l) => l.entryId.equals(reversalId)))
          .get();
      final d = reversalLines.fold<double>(0, (s, l) => s + l.debit);
      final c = reversalLines.fold<double>(0, (s, l) => s + l.credit);
      expect(d, closeTo(c, 1e-9), reason: 'the reversal entry itself balances');
      expect(d, closeTo(100, 1e-9));

      // Debit/credit swapped relative to the original.
      final cashLine = reversalLines.firstWhere((l) => l.accountId == cashId);
      final salesLine = reversalLines.firstWhere((l) => l.accountId == salesId);
      expect(cashLine.debit, 0);
      expect(cashLine.credit, closeTo(100, 1e-9));
      expect(salesLine.credit, 0);
      expect(salesLine.debit, closeTo(100, 1e-9));

      // Original + reversal net both accounts back to zero.
      final cash = await (db.select(db.accounts)..where((a) => a.id.equals(cashId)))
          .getSingle();
      final sales = await (db.select(db.accounts)..where((a) => a.id.equals(salesId)))
          .getSingle();
      expect(cash.balance, closeTo(0, 1e-9));
      expect(sales.balance, closeTo(0, 1e-9));
    });

    test('audit failure rolls back the reversal journal entry', () async {
      final manualId = await db.createJournalEntry(
        description: 'قيد يدوي لاختبار التراجع',
        date: DateTime.now(),
        lines: [
          JournalLine(accountId: cashId, debit: 25),
          JournalLine(accountId: salesId, credit: 25),
        ],
      );
      await db.customStatement('''
        CREATE TRIGGER fail_journal_audit
        BEFORE INSERT ON activity_logs
        BEGIN
          SELECT RAISE(ABORT, 'forced audit failure');
        END
      ''');

      await expectLater(
        db.reverseJournalEntryById(entryId: manualId),
        throwsA(anything),
      );

      final entries = await db.select(db.journalEntries).get();
      expect(entries, hasLength(1),
          reason: 'the reversal JE must roll back with its audit row');
      final lines = await db.select(db.journalEntryLines).get();
      expect(lines, hasLength(2),
          reason: 'reversal lines must roll back with the JE');
    });

    test('reversing the same entry twice is idempotent — no duplicate reversal',
        () async {
      final manualId = await db.createJournalEntry(
        description: 'قيد يدوي اختبار',
        date: DateTime.now(),
        lines: [
          JournalLine(accountId: cashId, debit: 50),
          JournalLine(accountId: salesId, credit: 50),
        ],
      );

      final first = await db.reverseJournalEntryById(entryId: manualId);
      expect(first, greaterThan(0));

      final second = await db.reverseJournalEntryById(entryId: manualId);
      expect(second, 0, reason: 'already reversed — must not create a duplicate');

      final allEntries = await db.select(db.journalEntries).get();
      expect(allEntries, hasLength(2),
          reason: 'still just the original + the one reversal from the first call');
    });
  });

  group('MJE-2 — collision guard: unrelated auto-posted JE is untouched', () {
    test('reversing A by id never touches B, even when B.referenceId == A.id',
        () async {
      // A: manual-shaped JE, reference_id NULL (mirrors MJE-1's target).
      final aId = await db.createJournalEntry(
        description: 'قيد A',
        date: DateTime.now(),
        lines: [
          JournalLine(accountId: cashId, debit: 30),
          JournalLine(accountId: salesId, credit: 30),
        ],
      );

      // B: an UNRELATED auto-posted JE whose referenceId coincidentally
      // equals A's own primary key — the exact shape the old
      // reverseTransaction(referenceType: ..., referenceId: entry.id) call
      // would have accidentally matched and reversed (MJE-2).
      final bId = await db.createJournalEntry(
        description: 'قيد B غير مرتبط',
        date: DateTime.now(),
        lines: [
          JournalLine(accountId: bankId, debit: 75),
          JournalLine(accountId: salesId, credit: 75),
        ],
        referenceType: 'sales_invoice',
        referenceId: aId, // coincidence: equals A's PK
        isAutoPosted: true,
      );

      final reversalId = await db.reverseJournalEntryById(entryId: aId);
      expect(reversalId, greaterThan(0));

      // B is completely untouched: still exactly its original two lines,
      // and no reversal of B was created.
      final bLines = await (db.select(db.journalEntryLines)
            ..where((l) => l.entryId.equals(bId)))
          .get();
      expect(bLines, hasLength(2));
      final bBank = bLines.firstWhere((l) => l.accountId == bankId);
      final bSales = bLines.firstWhere((l) => l.accountId == salesId);
      expect(bBank.debit, closeTo(75, 1e-9));
      expect(bBank.credit, 0);
      expect(bSales.credit, closeTo(75, 1e-9));
      expect(bSales.debit, 0);

      final matchingB = await (db.select(db.journalEntries)
            ..where((e) =>
                e.referenceType.equals('sales_invoice') &
                e.referenceId.equalsNullable(aId)))
          .get();
      expect(matchingB, hasLength(1),
          reason: 'only the original B — no reversal was posted against it');
      expect(matchingB.single.id, bId);
    });

    test('two auto-posted JEs sharing the SAME referenceId but DIFFERENT '
        'referenceType both reverse into two distinct rows (dedup-collision '
        'regression)', () async {
      // The exact defect the reversal must NOT reintroduce: if the reversal
      // were keyed on original.referenceId, then a sale#5 and a purchase#5
      // would both collapse to createJournalEntry's autopost-dedup key
      // (reversal, 5, true) and the second reversal would be silently
      // deduped against the first. Keying on the JE's own PK avoids this.
      final saleJe = await db.createJournalEntry(
        description: 'قيد بيع #5',
        date: DateTime.now(),
        lines: [
          JournalLine(accountId: cashId, debit: 40),
          JournalLine(accountId: salesId, credit: 40),
        ],
        referenceType: 'sale',
        referenceId: 5,
        isAutoPosted: true,
      );
      final purchaseJe = await db.createJournalEntry(
        description: 'قيد شراء #5',
        date: DateTime.now(),
        lines: [
          JournalLine(accountId: bankId, debit: 60),
          JournalLine(accountId: salesId, credit: 60),
        ],
        referenceType: 'purchase',
        referenceId: 5, // SAME numeric referenceId, DIFFERENT referenceType
        isAutoPosted: true,
      );
      expect(saleJe, isNot(purchaseJe));

      final rev1 = await db.reverseJournalEntryById(entryId: saleJe);
      final rev2 = await db.reverseJournalEntryById(entryId: purchaseJe);
      expect(rev1, greaterThan(0));
      expect(rev2, greaterThan(0),
          reason: 'the second reversal must NOT be deduped away');
      expect(rev1, isNot(rev2), reason: 'two distinct reversal rows');

      // Two distinct reversal JEs (referenceType='reversal') exist.
      final reversals = await (db.select(db.journalEntries)
            ..where((e) => e.referenceType.equals('reversal')))
          .get();
      expect(reversals, hasLength(2));
      expect(reversals.map((e) => e.id).toSet(), {rev1, rev2});
      // Each reversal is keyed on its source JE's own PK (unique), not the
      // shared source-doc referenceId of 5.
      expect(reversals.map((e) => e.referenceId).toSet(), {saleJe, purchaseJe});

      // Both source JEs' affected account balances net back to zero.
      final cash = await (db.select(db.accounts)..where((a) => a.id.equals(cashId)))
          .getSingle();
      final bank = await (db.select(db.accounts)..where((a) => a.id.equals(bankId)))
          .getSingle();
      final sales = await (db.select(db.accounts)..where((a) => a.id.equals(salesId)))
          .getSingle();
      expect(cash.balance, closeTo(0, 1e-9));
      expect(bank.balance, closeTo(0, 1e-9));
      expect(sales.balance, closeTo(0, 1e-9),
          reason: 'both 40-credit and 60-credit sales legs fully reversed');
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────────────────────

Future<int> _seedAccount(AppDatabase db, String code, String name, String type) {
  return db.into(db.accounts).insert(
        AccountsCompanion.insert(
          code: code,
          name: name,
          accountType: type,
          balance: const Value(0.0),
          isActive: const Value(true),
        ),
      );
}

Future<void> _clearDatabase(AppDatabase db) async {
  // forTesting() runs the full startup seed; wipe to a known baseline.
  await db.delete(db.journalEntryLines).go();
  await db.delete(db.journalEntries).go();
  await db.delete(db.accountingPeriods).go();
  await db.delete(db.fiscalYears).go();
  await db.delete(db.accountMappings).go();
  // §٣-ب — الخزائنُ صارت مشدودةً إلى الدليل (`safes.linkedAccountId`)، فمسحُ
  // `accounts` بلا فكِّ الشدّ يسقط بـ`FOREIGN KEY constraint failed (787)`.
  // وفكُّ الربط جزءٌ من مسح الدليل لا التفافٌ عليه: لا ربطَ يبقى صحيحاً بعد
  // محو ما يشير إليه. والعكسُ هنا يقيّد بمعرّفاتٍ صريحةٍ فلا تمسّه خزنة.
  await db
      .update(db.safes)
      .write(const SafesCompanion(linkedAccountId: Value(null)));
  // J3 — والأطرافُ النظاميّة («عميل نقدي»/«مورد نقدي») مشدودةٌ كذلك.
  await db.update(db.parties).write(const PartiesCompanion(accountId: Value(null)));
  await db.delete(db.accounts).go();
  await db.delete(db.settings).go();
}

/// Fiscal year keyed off DateTime.now().year — reverseJournalEntryById posts
/// the reversal with date: DateTime.now(), so the seeded year must cover
/// "today" whenever this suite runs (mirrors journal_entry_sequence_test.dart).
Future<void> _seedFiscalYear(AppDatabase db) async {
  final now = DateTime.now();
  await db.into(db.fiscalYears).insert(
        FiscalYearsCompanion.insert(
          name: '${now.year}',
          startDate: DateTime(now.year, 1, 1),
          endDate: DateTime(now.year, 12, 31),
          isClosed: const Value(false),
        ),
      );
}
