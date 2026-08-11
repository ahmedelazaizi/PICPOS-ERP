// ═══════════════════════════════════════════════════════════════════════════
// COMMERCIAL PAPERS STATE MACHINE — Unit Tests
// ═══════════════════════════════════════════════════════════════════════════
//
// Verifies business logic guards, status transitions, and auto-posting
// for received and issued commercial papers.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/repositories/commercial_papers_repository_impl.dart';

void main() {
  late AppDatabase db;
  late CommercialPapersRepositoryImpl repo;

  setUp(() async {
    db = AppDatabase.forTesting();
    repo = CommercialPapersRepositoryImpl(db);

    // Clear auto-seeded data to avoid UNIQUE constraint conflicts
    await _clearDatabase(db);

    // Seed required accounts for auto-posting
    await _seedAccounts(db);
    // Seed a fiscal year (required by periods)
    await _seedFiscalYear(db);
    // Seed a default party
    await _seedParty(db, 'عميل تجريبي', id: 1);
    await _seedParty(db, 'مورد تجريبي', id: 2);
    // paper_status_history.changed_by FKs to users — the repo defaults changedBy
    // to 0 when omitted; seed that placeholder actor so the FK resolves (the
    // DAO's _ensureValidActor guard rejects an actor with no matching user).
    await db.into(db.users).insert(UsersCompanion.insert(
        id: const Value(0), username: 'usr0', passwordHash: 'x', displayName: 'U0'));
  });

  tearDown(() async {
    await db.close();
  });

  group('Commercial Papers — Transition Guards', () {
    test('Cannot renew a cashed paper', () async {
      final paperId = await _createPaper(repo, direction: 'received', status: 'pending');
      await repo.updatePaperStatus(paperId, 'cashed');

      expect(
        () => repo.renewPaper(paperId, DateTime.now().add(const Duration(days: 30))),
        throwsException,
      );
    });

    test('Cannot partial-collect a cashed paper', () async {
      final paperId = await _createPaper(repo, direction: 'received', status: 'pending');
      await repo.updatePaperStatus(paperId, 'cashed');

      expect(
        () => repo.partialCollection(paperId, 1000),
        throwsException,
      );
    });

    test('Reissue fails if status is not pending or in_portfolio', () async {
      final paperId = await _createPaper(repo, direction: 'received', status: 'pending');
      await repo.updatePaperStatus(paperId, 'deposited');

      expect(
        () => repo.reissuePaper(paperId, 2),
        throwsException,
      );
    });
  });

  group('Commercial Papers — Financial Period Gating', () {
    test('Status change fails if period is closed', () async {
      final paperId = await _createPaper(repo, direction: 'received', status: 'pending');

      // Close the current period (seeded in setUp)
      final now = DateTime.now();
      await (db.update(db.accountingPeriods)
            ..where((p) => p.month.equals(now.month) & p.year.equals(now.year)))
          .write(const AccountingPeriodsCompanion(isClosed: Value(true)));

      expect(
        () => repo.updatePaperStatus(paperId, 'cashed'),
        throwsException,
      );
    });
  });

  group('Commercial Papers — Auto-Posting Verification', () {
    test('Received paper creation -> pending posts DEBIT Notes Receivable, CREDIT Receivables', () async {
      final paperId = await _createPaper(repo, direction: 'received', status: 'pending');

      final entries = await db.select(db.journalEntries).get();
      expect(entries.length, 1);

      final lines = await (db.select(db.journalEntryLines)..where((l) => l.entryId.equals(entries.first.id))).get();
      // Spec 136 (commit 1529189) made the LINE descriptions cheque-centric
      // ('أوراق قبض - استلام شيك …' / 'استلام شيك …'), so we assert on the
      // economic posting itself — accountId + amount — instead of the moved
      // Arabic control-account names.
      final notesReceivableId = await _accountIdForPurpose(db, 'notes_receivable');
      final receivablesId = await _accountIdForPurpose(db, 'receivables');
      expect(lines.any((l) => l.debit == 5000 && l.accountId == notesReceivableId), isTrue,
          reason: 'DEBIT أوراق قبض (notes_receivable, 1123) by 5000');
      expect(lines.any((l) => l.credit == 5000 && l.accountId == receivablesId), isTrue,
          reason: 'CREDIT ذمم مدينة (receivables control, 1121) by 5000');
    });

    test('Received paper cashed posts DEBIT Cash, CREDIT Notes Receivable', () async {
      // First create it (this creates the first JE)
      final paperId = await _createPaper(repo, direction: 'received', status: 'pending');
      
      // Now cash it (this should create the second JE)
      await repo.updatePaperStatus(paperId, 'cashed');

      final entries = await db.select(db.journalEntries).get();
      expect(entries.length, 2);

      final secondEntry = entries.last;
      final lines = await (db.select(db.journalEntryLines)..where((l) => l.entryId.equals(secondEntry.id))).get();

      // Spec 136 (commit cf13866): a cheque collected DIRECTLY (pending→cashed,
      // no deposit) clears to CASH; the line descriptions are now cheque-centric
      // ('تحصيل شيك … نقداً'). Assert accountId + amount, not the moved text.
      final cashId = await _accountIdForPurpose(db, 'cash');
      final notesReceivableId = await _accountIdForPurpose(db, 'notes_receivable');
      expect(lines.any((l) => l.debit == 5000 && l.accountId == cashId), isTrue,
          reason: 'DEBIT الصندوق (cash, 1111) by 5000 — direct counter collection');
      expect(lines.any((l) => l.credit == 5000 && l.accountId == notesReceivableId), isTrue,
          reason: 'CREDIT أوراق قبض (notes_receivable, 1123) by 5000');
    });

    test('Issued paper creation -> pending posts DEBIT Payables, CREDIT Notes Payable', () async {
      final paperId = await _createPaper(repo, direction: 'issued', status: 'pending');

      final entries = await db.select(db.journalEntries).get();
      expect(entries.length, 1);

      final lines = await (db.select(db.journalEntryLines)..where((l) => l.entryId.equals(entries.first.id))).get();
      // Spec 136 (commit 1529189): line descriptions are now cheque-centric
      // ('إصدار شيك …' / 'أوراق دفع - إصدار شيك …'). Assert accountId + amount.
      final payablesId = await _accountIdForPurpose(db, 'payables');
      final notesPayableId = await _accountIdForPurpose(db, 'notes_payable');
      expect(lines.any((l) => l.debit == 5000 && l.accountId == payablesId), isTrue,
          reason: 'DEBIT ذمم دائنة (payables control, 2111) by 5000');
      expect(lines.any((l) => l.credit == 5000 && l.accountId == notesPayableId), isTrue,
          reason: 'CREDIT أوراق دفع (notes_payable, 2113) by 5000');
    });
  });

  group('Commercial Papers — Partial Collection Logic', () {
    test('Partial collection updates amount and records history', () async {
      final paperId = await _createPaper(repo, amount: 10000);
      
      await repo.partialCollection(paperId, 4000);

      final paper = await repo.getPaperById(paperId);
      expect(paper!.amount, 6000);

      final history = await repo.getPaperHistory(paperId);
      expect(history.any((h) => h.toStatus == 'partial_collected'), isTrue);
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────────────────────

/// Resolve the account id the DAO would post to for a given purpose, using the
/// SAME purposes-map → code → account path the production code uses. Keeps these
/// tests pinned to the economic posting (accountId) rather than the moved,
/// cheque-centric Arabic line descriptions (Spec 136 commit 1529189/cf13866).
Future<int> _accountIdForPurpose(AppDatabase db, String purpose) async {
  final code = await db.accountingDao
      .getMappedAccountCode(purpose, AccountingDao.accountPurposes[purpose]!);
  final account = await db.getAccountByCode(code);
  return account!.id;
}

Future<void> _clearDatabase(AppDatabase db) async {
  // Order matters if FKs are enabled
  await db.delete(db.commercialPapers).go();
  await db.delete(db.journalEntryLines).go();
  await db.delete(db.journalEntries).go();
  await db.delete(db.accountingPeriods).go();
  await db.delete(db.fiscalYears).go();
  await db.delete(db.accountMappings).go();
  // §٣-ب — الخزائنُ صارت مشدودةً إلى الدليل (`safes.linkedAccountId`)، فمسحُ
  // `accounts` بلا فكِّ الشدّ يسقط بـ`FOREIGN KEY constraint failed (787)`.
  // وفكُّ الربط جزءٌ من مسح الدليل لا التفافٌ عليه: لا ربطَ يبقى صحيحاً بعد
  // محو ما يشير إليه.
  //
  // والخزائنُ **تبقى** هنا قصداً: تحصيلُ الورقة يحرّك خزنةً، ولا تُحذف كما في
  // `spec_082` لأن هذا الملفَّ لا يمسح `safe_transactions` فحذفُها يسقط بدوره.
  // وبلا ربطٍ يقع مدينُ النقدية على `1111` — وهو ما يؤكّده هذا الملفّ نصّاً.
  await db
      .update(db.safes)
      .write(const SafesCompanion(linkedAccountId: Value(null)));
  await db.delete(db.accounts).go();
  await db.delete(db.parties).go();
}

Future<void> _seedAccounts(AppDatabase db) async {
  // Codes MUST match AccountingDao.accountPurposes (accounting_dao_reads.dart).
  // The commercial papers DAO resolves accounts by purpose → code, so using
  // wrong codes (e.g. 1101 instead of 1111) means every getAccountByCode call
  // returns null and the journal entry is silently skipped.
  final accounts = [
    {'code': '1111', 'name': 'الصندوق', 'type': 'asset'},       // cash
    {'code': '1113', 'name': 'البنك', 'type': 'asset'},          // bank
    {'code': '1121', 'name': 'ذمم مدينة', 'type': 'asset'},      // receivables
    {'code': '1123', 'name': 'أوراق قبض', 'type': 'asset'},      // notes_receivable
    {'code': '2111', 'name': 'ذمم دائنة', 'type': 'liability'},  // payables
    {'code': '2113', 'name': 'أوراق دفع', 'type': 'liability'},  // notes_payable
  ];

  for (final a in accounts) {
    await db.into(db.accounts).insert(
          AccountsCompanion.insert(
            code: a['code']!,
            name: a['name']!,
            accountType: a['type']!,
            balance: const Value(0.0),
          ),
        );
  }
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

  // Seed all months to ensure current date is covered
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

Future<void> _seedParty(AppDatabase db, String name, {required int id}) async {
  await db.into(db.parties).insert(
        PartiesCompanion.insert(
          id: Value(id),
          name: name,
          isCustomer: const Value(true),
          isSupplier: const Value(false),
        ),
      );
}

Future<int> _createPaper(CommercialPapersRepositoryImpl repo, {
  String direction = 'received',
  String status = 'pending',
  double amount = 5000.0,
}) async {
  final id = await repo.createPaper(
    paperNumber: 'TEST-${DateTime.now().millisecondsSinceEpoch}',
    type: 'cheque',
    direction: direction,
    partyId: 1,
    amount: amount,
    issueDate: DateTime.now(),
    dueDate: DateTime.now().add(const Duration(days: 60)),
  );
  
  if (status != 'pending') {
    await repo.updatePaperStatus(id, status);
  }
  return id;
}
