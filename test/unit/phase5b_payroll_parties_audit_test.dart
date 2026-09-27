import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/database/extensions/hr_extensions.dart';
import 'package:ural_erp/domain/entities/accounting_entities.dart';
import 'package:ural_erp/services/audit_log_integrity_service.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
  });

  tearDown(() => db.close());

  test('monthly payroll accrual posts once on month end and is idempotent', () async {
    await db.into(db.employees).insert(EmployeesCompanion.insert(
      name: 'موظف استحقاق',
      salary: const Value(2500),
    ));

    final first = await db.accruePayrollForMonth(2026, 2, 1);
    final second = await db.accruePayrollForMonth(2026, 2, 1);
    final entries = await (db.select(db.journalEntries)
          ..where((entry) => entry.globalId.equals('payroll-accrual-2026-02')))
        .get();

    expect(first, greaterThan(0));
    expect(second, first);
    expect(entries, hasLength(1));
    expect(entries.single.entryDate, DateTime(2026, 2, 28));
  });

  test('payment after accrual settles payable and reversal permits repayment', () async {
    final employeeId = await db.into(db.employees).insert(EmployeesCompanion.insert(
      name: 'موظف تسوية',
      salary: const Value(1800),
    ));
    await db.accruePayrollForMonth(2026, 2, 1);
    final paymentId = await db.recordSalaryPayment(
      employeeId: employeeId,
      amount: 1800,
      period: '2026-02',
    );
    final paymentEntry = await (db.select(db.journalEntries)
          ..where((entry) => entry.referenceType.equals('salary_payment') &
              entry.referenceId.equals(paymentId)))
        .getSingle();
    final payableCode = AccountingDao.accountPurposes['accrued_salaries']!;
    final payableAccount = await db.getAccountByCode(payableCode);
    final payableLines = await (db.select(db.journalEntryLines)
          ..where((line) => line.entryId.equals(paymentEntry.id) &
              line.accountId.equals(payableAccount!.id)))
        .get();
    expect(payableLines.single.debit, 1800);

    await db.reverseSalaryPayment(paymentId, 1);
    final reversalCount = await (db.select(db.journalEntries)
          ..where((entry) => entry.referenceType.equals('reversal') &
              entry.referenceId.equals(paymentEntry.id)))
        .get();
    expect(reversalCount, hasLength(1));
    expect(await db.recordSalaryPayment(
      employeeId: employeeId,
      amount: 1800,
      period: '2026-02',
    ), greaterThan(0));
  });

  test('party mismatch repair restores the ledger balance', () async {
    final account = await (db.select(db.accounts)
          ..where((a) => a.accountNature.equals('detail'))
          ..limit(1))
        .getSingle();
    final partyId = await db.into(db.parties).insert(PartiesCompanion.insert(
      name: 'طرف اختبار',
      accountId: Value(account.id),
      balance: const Value(99),
    ));
    final mismatches = await db.getPartyBalanceMismatches();
    expect(mismatches.map((row) => row.partyId), contains(partyId));

    final repaired = await db.recalculatePartyBalancesFromLedger(1);
    final party = await (db.select(db.parties)..where((p) => p.id.equals(partyId)))
        .getSingle();
    expect(repaired, greaterThanOrEqualTo(1));
    expect(party.balance, 0);
  });

  test('approve and reverse write audit rows', () async {
    final accounts = await (db.select(db.accounts)
          ..where((a) => a.accountNature.equals('detail')))
        .get();
    final draftId = await db.createDraftJournalEntry(
      description: 'قيد تدقيق',
      date: DateTime.now(),
      lines: [
        JournalLine(accountId: accounts[0].id, debit: 10),
        JournalLine(accountId: accounts[1].id, credit: 10),
      ],
    );
    await db.approveJournalEntry(draftId, 1);
    final sourceId = await db.createJournalEntry(
      description: 'قيد عكس تدقيق',
      date: DateTime.now(),
      lines: [
        JournalLine(accountId: accounts[0].id, debit: 7),
        JournalLine(accountId: accounts[1].id, credit: 7),
      ],
      referenceType: 'phase5b_audit',
      referenceId: 1,
      isAutoPosted: true,
    );
    await db.reverseTransaction(
      referenceType: 'phase5b_audit',
      referenceId: 1,
      descriptionPrefix: 'عكس تدقيق',
      newReferenceType: 'phase5b_audit_reversal',
    );
    final auditRows = await (db.select(db.activityLogs)
          ..where((row) => row.entityId.equals(draftId) | row.entityId.equals(sourceId)))
        .get();
    expect(auditRows.map((row) => row.action), contains('journal_entry_approved'));
    expect(auditRows.map((row) => row.action), contains('journal_entry_reversal_requested'));
  });

  test('audit hash chain verifies and detects tampering', () {
    final firstTime = DateTime(2026, 2, 28);
    final firstHash = AuditLogIntegrityService.generateHash(
      previousHash: 'GENESIS',
      timestamp: firstTime,
      action: 'approve',
      data: 'entry=1',
      userId: 1,
    );
    final secondTime = DateTime(2026, 3, 1);
    final secondHash = AuditLogIntegrityService.generateHash(
      previousHash: firstHash,
      timestamp: secondTime,
      action: 'reverse',
      data: 'entry=1',
      userId: 1,
    );
    final entries = [
      AuditEntry(
        id: 1,
        timestamp: firstTime,
        action: 'approve',
        data: 'entry=1',
        userId: 1,
        integrityHash: firstHash,
      ),
      AuditEntry(
        id: 2,
        timestamp: secondTime,
        action: 'reverse',
        data: 'entry=1',
        userId: 1,
        integrityHash: secondHash,
      ),
    ];
    expect(AuditLogIntegrityService.verifyChain(entries), -1);
    expect(
      AuditLogIntegrityService.verifyChain([
        entries.first,
        AuditEntry(
          id: 2,
          timestamp: secondTime,
          action: 'tampered',
          data: 'entry=1',
          userId: 1,
          integrityHash: secondHash,
        ),
      ]),
      1,
    );
  });
}
