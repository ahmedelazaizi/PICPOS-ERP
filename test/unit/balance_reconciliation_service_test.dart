// ═══════════════════════════════════════════════════════════════════════════
// BalanceReconciliationService — Unit + Integration Tests (ISS-FIN-06)
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' as drift;
import 'package:picpos_erp/core/errors/app_error.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/balance_reconciliation_service.dart';

void main() {
  late AppDatabase db;
  late BalanceReconciliationService service;

  setUp(() {
    db = AppDatabase.forTesting();
    service = BalanceReconciliationService(db);
  });

  tearDown(() => db.close());

  // ── Helpers ─────────────────────────────────────────────────────────────────

  Future<int> insertDetailAccount({
    required String code,
    required String name,
    double balance = 0.0,
  }) =>
      db.into(db.accounts).insert(AccountsCompanion.insert(
        code: code,
        name: name,
        accountType: 'asset',
        accountNature: const drift.Value('detail'),
        isActive: const drift.Value(true),
        balance: drift.Value(balance),
      ));

  Future<int> insertViewAccount(String code, String name) =>
      db.into(db.accounts).insert(AccountsCompanion.insert(
        code: code,
        name: name,
        accountType: 'asset',
        accountNature: const drift.Value('view'),
        isActive: const drift.Value(true),
      ));

  Future<int> insertPostedJournalEntry() =>
      db.into(db.journalEntries).insert(JournalEntriesCompanion.insert(
        entryNumber: 'JE-${DateTime.now().millisecondsSinceEpoch}',
        entryDate: DateTime.now(),
        description: const drift.Value('Test entry'),
        isPosted: const drift.Value(true),
      ));

  Future<int> insertUnpostedJournalEntry() =>
      db.into(db.journalEntries).insert(JournalEntriesCompanion.insert(
        entryNumber: 'DRAFT-${DateTime.now().millisecondsSinceEpoch}',
        entryDate: DateTime.now(),
        description: const drift.Value('Draft entry'),
        isPosted: const drift.Value(false),
      ));

  Future<void> insertJournalLine({
    required int entryId,
    required int accountId,
    double debit = 0.0,
    double credit = 0.0,
  }) =>
      db.into(db.journalEntryLines).insert(JournalEntryLinesCompanion.insert(
        entryId: entryId,
        accountId: accountId,
        debit: drift.Value(debit),
        credit: drift.Value(credit),
      ));

  // ══════════════════════════════════════════════════════════════════════════
  group('ReconciliationResult model', () {
    test('isClean returns true when errors list is empty', () {
      const result = ReconciliationResult(
        errors: [],
        accountsChecked: 10,
        accountsCorrected: 0,
      );
      expect(result.isClean, isTrue);
    });

    test('isClean returns false when errors exist', () {
      final result = ReconciliationResult(
        errors: [
          ReconciliationError(
            entityType: 'account',
            entityId: 1,
            cachedValue: 100,
            calculatedValue: 90,
          ),
        ],
        accountsChecked: 1,
        accountsCorrected: 0,
      );
      expect(result.isClean, isFalse);
      expect(result.errors.length, 1);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('reconcile() — no journal entries', () {
    test('returns clean result when no posted JELs exist for any account', () async {
      // The seeded COA accounts all have balance = 0 and no JELs,
      // so computed balance = 0 = stored balance → no discrepancies.
      final result = await service.reconcile();
      expect(result.isClean, isTrue);
      expect(result.accountsCorrected, 0);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('reconcile() — view accounts are ignored', () {
    test('view accounts (parent nodes) are not counted', () async {
      final before = await service.reconcile();
      final beforeCount = before.accountsChecked;

      await insertViewAccount('TEST-VIEW-9999', 'Assets (view)');

      final after = await service.reconcile();
      // Adding a view account must NOT increase the checked count
      expect(after.accountsChecked, beforeCount);
      // And the overall result must remain clean (no JELs exist for seeded accounts)
      expect(after.isClean, isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('reconcile() — balanced account', () {
    test('no error when stored balance matches posted JELs', () async {
      final accId = await insertDetailAccount(
        code: 'TEST-1100',
        name: 'Test Cash',
        balance: 500.0,
      );
      final jeId = await insertPostedJournalEntry();
      await insertJournalLine(entryId: jeId, accountId: accId, debit: 500.0);

      final result = await service.reconcile();
      // No error for our test account
      expect(result.errors.where((e) => e.entityId == accId), isEmpty);
      expect(result.isClean, isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('reconcile() — detects mismatch', () {
    test('flags account when stored balance differs from computed', () async {
      // Stored balance = 1000, but posted JELs sum to 700
      final accId = await insertDetailAccount(
        code: 'TEST-1100',
        name: 'Test Cash',
        balance: 1000.0,
      );
      final jeId = await insertPostedJournalEntry();
      await insertJournalLine(entryId: jeId, accountId: accId, debit: 700.0);

      final result = await service.reconcile();
      // Our test account must appear in the errors
      final errs = result.errors.where((e) => e.entityId == accId).toList();
      expect(errs.length, 1);

      final err = errs.first;
      expect(err.entityType, 'account');
      expect(err.cachedValue, 1000.0);
      expect(err.calculatedValue, 700.0);
    });

    test('ignores unposted journal entries in balance calculation', () async {
      // Stored balance = 0 (correct — only unposted JEL exists)
      final accId = await insertDetailAccount(
        code: '1100',
        name: 'Cash',
        balance: 0.0,
      );
      final draftId = await insertUnpostedJournalEntry();
      await insertJournalLine(
          entryId: draftId, accountId: accId, debit: 500.0);

      final result = await service.reconcile();
      // Unposted entries must NOT affect computed balance
      expect(result.isClean, isTrue);
    });

    test('respects tolerance — small diff below threshold is not flagged', () async {
      final accId = await insertDetailAccount(
        code: '1100',
        name: 'Cash',
        balance: 100.005,
      );
      final jeId = await insertPostedJournalEntry();
      await insertJournalLine(entryId: jeId, accountId: accId, debit: 100.0);

      // Default tolerance = 0.01; difference = 0.005 → should be clean
      final result = await service.reconcile(tolerance: 0.01);
      expect(result.isClean, isTrue);
    });

    test('flags diff exactly at custom tolerance boundary', () async {
      final accId = await insertDetailAccount(
        code: '1100',
        name: 'Cash',
        balance: 100.02,
      );
      final jeId = await insertPostedJournalEntry();
      await insertJournalLine(entryId: jeId, accountId: accId, debit: 100.0);

      // diff = 0.02, tolerance = 0.01 → should be flagged
      final result = await service.reconcile(tolerance: 0.01);
      expect(result.errors.length, 1);
      expect(result.errors.first.entityId, accId);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('reconcile() — multiple accounts', () {
    test('reports only the mismatched account when mix of ok and bad', () async {
      final goodId = await insertDetailAccount(
        code: 'TEST-1100',
        name: 'Test Cash',
        balance: 200.0,
      );
      final badId = await insertDetailAccount(
        code: 'TEST-1200',
        name: 'Test Receivables',
        balance: 999.0,
      );

      final jeId = await insertPostedJournalEntry();
      // Good account: JEL matches stored balance exactly
      await insertJournalLine(entryId: jeId, accountId: goodId, debit: 200.0);
      // Bad account: JEL gives 500, stored is 999
      await insertJournalLine(entryId: jeId, accountId: badId, debit: 500.0);

      final result = await service.reconcile();
      // Only badId should appear in errors (goodId must NOT appear)
      expect(result.errors.where((e) => e.entityId == goodId), isEmpty);
      expect(result.errors.where((e) => e.entityId == badId).length, 1);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('reconcile(autoCorrect: true)', () {
    test('auto-corrects mismatch and updates stored balance', () async {
      final accId = await insertDetailAccount(
        code: 'TEST-AC-1',
        name: 'Test Cash',
        balance: 1000.0,
      );
      final jeId = await insertPostedJournalEntry();
      await insertJournalLine(entryId: jeId, accountId: accId, debit: 750.0);

      final result = await service.reconcile(autoCorrect: true);
      // Our account must be in errors and corrected
      expect(result.errors.where((e) => e.entityId == accId).length, 1);
      expect(result.accountsCorrected, greaterThanOrEqualTo(1));

      // Verify DB was updated
      final updated =
          await (db.select(db.accounts)..where((a) => a.id.equals(accId)))
              .getSingle();
      expect(updated.balance, closeTo(750.0, 0.001));
    });

    test('does not correct when autoCorrect is false (default)', () async {
      final accId = await insertDetailAccount(
        code: 'TEST-AC-2',
        name: 'Test Cash',
        balance: 1000.0,
      );
      final jeId = await insertPostedJournalEntry();
      await insertJournalLine(entryId: jeId, accountId: accId, debit: 750.0);

      final result = await service.reconcile(autoCorrect: false);
      expect(result.errors.where((e) => e.entityId == accId).length, 1);
      expect(result.accountsCorrected, 0);

      // Balance should remain unchanged
      final unchanged =
          await (db.select(db.accounts)..where((a) => a.id.equals(accId)))
              .getSingle();
      expect(unchanged.balance, 1000.0);
    });

    test('corrects multiple mismatched accounts in one pass', () async {
      final acc1 = await insertDetailAccount(
          code: 'TEST-AC-3', name: 'Test Cash', balance: 999.0);
      final acc2 = await insertDetailAccount(
          code: 'TEST-AC-4', name: 'Test Bank', balance: 555.0);

      final je1 = await insertPostedJournalEntry();
      final je2 = await insertPostedJournalEntry();
      await insertJournalLine(entryId: je1, accountId: acc1, debit: 300.0);
      await insertJournalLine(entryId: je2, accountId: acc2, debit: 400.0);

      final result = await service.reconcile(autoCorrect: true);
      expect(result.errors.where((e) => e.entityId == acc1).length, 1);
      expect(result.errors.where((e) => e.entityId == acc2).length, 1);
      expect(result.accountsCorrected, greaterThanOrEqualTo(2));

      final a1 = await (db.select(db.accounts)..where((a) => a.id.equals(acc1)))
          .getSingle();
      final a2 = await (db.select(db.accounts)..where((a) => a.id.equals(acc2)))
          .getSingle();
      expect(a1.balance, closeTo(300.0, 0.001));
      expect(a2.balance, closeTo(400.0, 0.001));
    });
  });
}
