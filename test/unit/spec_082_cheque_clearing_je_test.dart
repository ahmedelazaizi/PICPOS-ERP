// ═══════════════════════════════════════════════════════════════════════════
// SPEC 082 — Cheque clearing JE: per-transition null-check, no silent skip
// ═══════════════════════════════════════════════════════════════════════════
//
// Pre-fix: `_autoPostPaperStatusChange` had a single
//   `if (cashAccount == null || bankAccount == null) return;`
// guard that aborted the ENTIRE JE generation whenever either the `cash` or
// the `bank` purpose mapping was missing, even if the specific transition
// only needed one of the two. The status row + safe side-effects still ran,
// so the books and the treasury drifted silently apart with NO log signal.
//
// Post-fix: per switch arm guards. When the required mapping is missing,
// we emit a `CP-AUTOPOST-WARN` diagnostic line and skip the JE for that
// transition only — the status update + balance side-effects still happen
// (preserving the pre-fix observable end-state) but the issue is now
// surfaced in the diagnostic log instead of being silently swallowed.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/logging/diagnostic_logger.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  group('Spec 082 — issued cheque pending → cashed', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting();
      await _clearDatabase(db);
      await _seedFiscalYear(db);
      await _seedDefaultSafe(db, balance: 10000.0);
      await _seedSupplier(db, id: 1, balance: 0.0);
      DiagnosticLogger.enableTestMode();
    });

    tearDown(() async {
      await db.close();
    });

    test('AC-1 happy path: bank mapped → 1 clearing JE '
        '(Dr أوراق دفع / Cr البنك)', () async {
      await _seedAllAccounts(db);

      final paperId = await db.createCommercialPaper(
        paperNumber: 'CHK-001',
        type: 'cheque',
        direction: 'issued',
        partyId: 1,
        amount: 500.0,
        issueDate: DateTime(2026, 6, 1),
        dueDate: DateTime(2026, 6, 15),
      );

      // pending → cashed
      await db.changePaperStatus(
        paperId: paperId,
        newStatus: 'cashed',
        changedBy: 1,
      );

      final jes = await db.select(db.journalEntries).get();
      // Two JEs: one for `pending` (issuance), one for `cashed` (clearing).
      expect(jes.length, 2,
          reason: 'Issuance + clearing should produce exactly 2 JEs');
      final clearingJe = jes.firstWhere(
        (j) => (j.description ?? '').contains('صرف شيك'),
        orElse: () => throw Exception('Clearing JE not found'),
      );

      final lines = await (db.select(db.journalEntryLines)
            ..where((l) => l.entryId.equals(clearingJe.id)))
          .get();
      expect(lines.length, 2,
          reason: 'Clearing JE must have Dr أوراق دفع / Cr البنك (2 lines)');

      final debitLine = lines.firstWhere((l) => l.debit > 0);
      final creditLine = lines.firstWhere((l) => l.credit > 0);
      expect(debitLine.debit, 500.0);
      expect(creditLine.credit, 500.0);
      // Debit leg → notes payable (أوراق دفع). Its line text still carries the
      // control-account label, so the substring check holds.
      expect(debitLine.description, contains('أوراق دفع'));
      // Credit leg → bank. Spec 136 (commit 1529189) made the line text
      // cheque-centric ('صرف شيك …') and dropped the 'البنك' label, so pin the
      // credit leg to the bank account itself (code 1113 = the seeded 'البنك')
      // — verifies the same economic posting without the moved Arabic text.
      final bankAccount = await db.getAccountByCode('1113');
      expect(bankAccount, isNotNull, reason: 'seeded bank account 1113');
      expect(creditLine.accountId, bankAccount!.id,
          reason: 'clearing credit must land on the bank account');
    });

    test('AC-2 bank missing: clearing transition throws fail-loud, '
        'CP-AUTOPOST-WARN logged, status NOT flipped (rollback)', () async {
      // Seed COA *without* the bank account (code 1113).
      await _seedAccountsExcludingBank(db);

      final paperId = await db.createCommercialPaper(
        paperNumber: 'CHK-002',
        type: 'cheque',
        direction: 'issued',
        partyId: 1,
        amount: 300.0,
        issueDate: DateTime(2026, 6, 1),
        dueDate: DateTime(2026, 6, 15),
      );

      // The issuance JE posts cleanly — pending arm only needs notesPayable +
      // payables, both seeded — so we start from exactly 1 JE.
      final pendingJes = await db.select(db.journalEntries).get();
      expect(pendingJes.length, 1,
          reason: 'Issuance JE should post even when bank mapping is missing '
              '— pending arm only needs notesPayable + payables');

      // Spec 135 silent-drift (a): `warnMissing` is now FAIL-LOUD. The
      // issued/cashed clearing leg needs the bank account; with it unmapped,
      // `warnMissing('bank', ...)` THROWS, and since the whole
      // changePaperStatus runs inside transaction(), the status update, the
      // JE, and the balance side-effects all roll back together — no more
      // silent books-vs-treasury drift.
      await expectLater(
        db.changePaperStatus(
          paperId: paperId,
          newStatus: 'cashed',
          changedBy: 1,
        ),
        throwsA(isA<Exception>()),
        reason: 'a missing bank mapping must fail loud, not silently skip '
            'the clearing JE',
      );

      // Rollback: no second (clearing) JE was committed.
      final allJes = await db.select(db.journalEntries).get();
      expect(allJes.length, 1,
          reason: 'transaction rolled back — only the issuance JE remains');

      // The diagnostic log must carry the warning so support can surface it.
      final warnings = DiagnosticLogger.testLog
          .where((l) => l.contains('CP-AUTOPOST-WARN'))
          .toList();
      expect(warnings, isNotEmpty,
          reason: 'A CP-AUTOPOST-WARN line must be emitted when the bank '
              'mapping is missing so support can spot misconfigured COA '
              'instead of guessing why GL is short');
      expect(warnings.first, contains('(bank)'),
          reason: 'the warn line names the unmapped purpose');
      expect(warnings.first, contains('issued/cashed'),
          reason: 'the warn line names the blocked transition');

      // Rollback: status did NOT flip — it is still pending.
      final paper = await (db.select(db.commercialPapers)
            ..where((p) => p.id.equals(paperId)))
          .getSingle();
      expect(paper.status, 'pending',
          reason: 'fail-loud rolled the status change back — must stay pending '
              'so the books and the status never drift apart');
    });

    test('AC-3 cash missing, bank present: issued/cashed STILL posts the JE',
        () async {
      // Seed *without* the cash account (1111). Pre-fix the outer guard
      // tripped because cashAccount==null, even though issued/cashed only
      // needs bankAccount. Post-fix: clearing JE posts.
      await _seedAccountsExcludingCash(db);

      final paperId = await db.createCommercialPaper(
        paperNumber: 'CHK-003',
        type: 'cheque',
        direction: 'issued',
        partyId: 1,
        amount: 250.0,
        issueDate: DateTime(2026, 6, 1),
        dueDate: DateTime(2026, 6, 15),
      );

      await db.changePaperStatus(
        paperId: paperId,
        newStatus: 'cashed',
        changedBy: 1,
      );

      final jes = await db.select(db.journalEntries).get();
      expect(jes.length, 2,
          reason: 'Issuance + clearing should post — cash mapping is not '
              'needed for either transition (pending needs notesPayable + '
              'payables; cashed needs notesPayable + bank)');

      // And no spurious warning for `cash` — only the transitions that need
      // cash should warn, and issued/cashed does NOT.
      final cashWarnings = DiagnosticLogger.testLog
          .where((l) => l.contains('CP-AUTOPOST-WARN') &&
              l.contains('purpose=cash') &&
              l.contains('issued/'))
          .toList();
      expect(cashWarnings, isEmpty,
          reason: 'No spurious cash-mapping warning for issued/cashed — '
              'that transition does not consume the cash account');
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────────────────────

Future<void> _clearDatabase(AppDatabase db) async {
  await db.delete(db.paperStatusHistory).go();
  await db.delete(db.commercialPapers).go();
  await db.delete(db.safeTransactions).go();
  await db.delete(db.journalEntryLines).go();
  await db.delete(db.journalEntries).go();
  await db.delete(db.accountingPeriods).go();
  await db.delete(db.fiscalYears).go();
  await db.delete(db.accountMappings).go();
  // §٣-ب — الخزائنُ صارت مشدودةً إلى الدليل (`safes.linkedAccountId`)، فحذفُها
  // **بعد** `accounts` صار يسقط بـ`FOREIGN KEY constraint failed (787)`.
  // الترتيبُ هو الإصلاح: المشدودُ يُحذف قبل المشدودِ إليه. و`safeTransactions`
  // مُزالةٌ فوق سلفاً فلا شيءَ يشدّ الخزائن.
  await db.delete(db.safes).go();
  // J3 — الأطرافُ (والنظاميّةُ منها مبذورة) مشدودةٌ إلى حساباتها: قبلَ الدليل.
  await db.delete(db.parties).go();
  await db.delete(db.accounts).go();
}

Future<void> _insertAccount(
    AppDatabase db, String code, String name, String type) async {
  await db.into(db.accounts).insert(
        AccountsCompanion.insert(
          code: code,
          name: name,
          accountType: type,
          balance: const Value(0.0),
        ),
      );
}

Future<void> _seedAllAccounts(AppDatabase db) async {
  await _insertAccount(db, '1111', 'الصندوق', 'asset');
  await _insertAccount(db, '1113', 'البنك', 'asset');
  await _insertAccount(db, '1121', 'ذمم مدينة', 'asset');
  await _insertAccount(db, '1123', 'أوراق قبض', 'asset');
  await _insertAccount(db, '2111', 'ذمم دائنة', 'liability');
  await _insertAccount(db, '2113', 'أوراق دفع', 'liability');
}

Future<void> _seedAccountsExcludingBank(AppDatabase db) async {
  // Same as _seedAllAccounts but skip code '1113' (bank).
  await _insertAccount(db, '1111', 'الصندوق', 'asset');
  await _insertAccount(db, '1121', 'ذمم مدينة', 'asset');
  await _insertAccount(db, '1123', 'أوراق قبض', 'asset');
  await _insertAccount(db, '2111', 'ذمم دائنة', 'liability');
  await _insertAccount(db, '2113', 'أوراق دفع', 'liability');
}

Future<void> _seedAccountsExcludingCash(AppDatabase db) async {
  // Skip code '1111' (cash). Bank present.
  await _insertAccount(db, '1113', 'البنك', 'asset');
  await _insertAccount(db, '1121', 'ذمم مدينة', 'asset');
  await _insertAccount(db, '1123', 'أوراق قبض', 'asset');
  await _insertAccount(db, '2111', 'ذمم دائنة', 'liability');
  await _insertAccount(db, '2113', 'أوراق دفع', 'liability');
}

Future<void> _seedFiscalYear(AppDatabase db) async {
  await db.into(db.fiscalYears).insert(
        FiscalYearsCompanion.insert(
          id: const Value(1),
          name: '2026',
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 12, 31),
        ),
      );
  for (int m = 1; m <= 12; m++) {
    await db.into(db.accountingPeriods).insert(
          AccountingPeriodsCompanion.insert(
            fiscalYearId: 1,
            name: 'شهر $m - 2026',
            month: m,
            year: 2026,
            startDate: DateTime(2026, m, 1),
            endDate: DateTime(2026, m + 1, 0, 23, 59, 59),
          ),
        );
  }
}

Future<void> _seedDefaultSafe(AppDatabase db, {required double balance}) async {
  await db.into(db.safes).insert(
        SafesCompanion.insert(
          id: const Value(1),
          name: 'خزينة تجريبية',
          safeType: const Value('cash'),
          balance: Value(balance),
          isDefault: const Value(true),
          isActive: const Value(true),
        ),
      );
  // Issued cheques clear through the BANK (_cpDebitSafeForPaper(bank: true)),
  // which resolves a bank-type safe; without one the side-effect throws
  // "لا يوجد صندوق بنكي مسجل" before the JE assertions run.
  await db.into(db.safes).insert(
        SafesCompanion.insert(
          id: const Value(2),
          name: 'بنك تجريبي',
          safeType: const Value('bank'),
          balance: Value(balance),
          isDefault: const Value(true),
          isActive: const Value(true),
        ),
      );
}

Future<void> _seedSupplier(AppDatabase db,
    {required int id, required double balance}) async {
  await db.into(db.parties).insert(
        PartiesCompanion.insert(
          id: Value(id),
          name: 'مورد تجريبي',
          isCustomer: const Value(false),
          isSupplier: const Value(true),
          balance: Value(balance),
        ),
      );
}
