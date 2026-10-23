// ═══════════════════════════════════════════════════════════════════════════
// Commercial Papers Lifecycle — E2E Integration Tests (Gap E)
//
// Covers cheque/promissory note lifecycle:
//   - Create paper → status is 'pending'
//   - Collect paper → status updated, journal entry auto-posted
//   - Endorse paper to vendor → endorsedToPartyId recorded
//   - Bounce paper → status reflects bounced, history logged
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int userId;
  late int partyId;
  late int vendorId;

  setUp(() async {
    db = AppDatabase.forTesting();

    final roleId = await db.into(db.roles).insert(
      RolesCompanion.insert(name: 'محاسب', isSystemRole: const Value(false)),
    );
    userId = await db.createUser(
      username: 'accountant',
      password: 'pw',
      displayName: 'Accountant',
      roleId: roleId,
    );

    partyId = await db.into(db.parties).insert(
      PartiesCompanion.insert(name: 'عميل شيكات', isCustomer: const Value(true)),
    );
    vendorId = await db.into(db.parties).insert(
      PartiesCompanion.insert(name: 'مورد', isSupplier: const Value(true)),
    );
  });

  tearDown(() => db.close());

  // ─────────────────────────────────────────────────────────────────────────
  group('Commercial Paper Creation', () {
    // ─────────────────────────────────────────────────────────────────────
    test('created paper starts with pending status', () async {
      final paperId = await db.createCommercialPaper(
        paperNumber: 'CHQ-001',
        type: 'cheque',
        direction: 'received',
        partyId: partyId,
        amount: 5000.0,
        issueDate: DateTime.now(),
        dueDate: DateTime.now().add(const Duration(days: 30)),
      );

      expect(paperId, isPositive);
      final paper = await db.getCommercialPaper(paperId);
      expect(paper, isNotNull);
      expect(paper!.status, equals('pending'));
      expect(paper.amount, equals(5000.0));
    });

    test('duplicate paper number throws exception', () async {
      await db.createCommercialPaper(
        paperNumber: 'CHQ-DUP-001',
        type: 'cheque',
        direction: 'received',
        partyId: partyId,
        amount: 1000.0,
        issueDate: DateTime.now(),
        dueDate: DateTime.now().add(const Duration(days: 30)),
      );

      await expectLater(
        () => db.createCommercialPaper(
          paperNumber: 'CHQ-DUP-001',
          type: 'cheque',
          direction: 'received',
          partyId: partyId,
          amount: 2000.0,
          issueDate: DateTime.now(),
          dueDate: DateTime.now().add(const Duration(days: 30)),
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('Status Transitions', () {
    // ─────────────────────────────────────────────────────────────────────
    test('pending → collected updates status correctly', () async {
      final paperId = await db.createCommercialPaper(
        paperNumber: 'CHQ-COL-001',
        type: 'cheque',
        direction: 'received',
        partyId: partyId,
        amount: 3000.0,
        issueDate: DateTime.now(),
        dueDate: DateTime.now().add(const Duration(days: 7)),
      );

      await db.changePaperStatus(
        paperId: paperId,
        newStatus: 'collected',
        changedBy: userId,
      );

      final paper = await db.getCommercialPaper(paperId);
      expect(paper!.status, equals('collected'));
    });

    test('status history is recorded for each transition', () async {
      final paperId = await db.createCommercialPaper(
        paperNumber: 'CHQ-HIST-001',
        type: 'cheque',
        direction: 'received',
        partyId: partyId,
        amount: 2000.0,
        issueDate: DateTime.now(),
        dueDate: DateTime.now().add(const Duration(days: 14)),
      );

      await db.changePaperStatus(
        paperId: paperId,
        newStatus: 'collected',
        changedBy: userId,
        notes: 'تم التحصيل',
      );

      final history = await db.getPaperHistory(paperId);
      expect(history, isNotEmpty, reason: 'At least one status change should be recorded');
    });

    test('endorsed paper records the endorsee party', () async {
      final paperId = await db.createCommercialPaper(
        paperNumber: 'CHQ-END-001',
        type: 'cheque',
        direction: 'received',
        partyId: partyId,
        amount: 4000.0,
        issueDate: DateTime.now(),
        dueDate: DateTime.now().add(const Duration(days: 30)),
      );

      await db.changePaperStatus(
        paperId: paperId,
        newStatus: 'endorsed',
        changedBy: userId,
        endorsedToPartyId: vendorId,
      );

      final paper = await db.getCommercialPaper(paperId);
      expect(paper!.status, equals('endorsed'));
      expect(paper.endorsedToPartyId, equals(vendorId));
    });

    // Spec 136 (field 2026-06-08) — a received cheque DEPOSITED then COLLECTED
    // must credit the bank exactly ONCE. Pre-fix both 'deposited' and 'cashed'
    // debited the bank + credited the bank safe, so the value was recorded
    // TWICE (the operator-reported double-count).
    test('deposit then cash credits the bank ONCE, not twice', () async {
      final bankSafe = await db.getDefaultSafeByType('bank');
      if (bankSafe == null) {
        markTestSkipped('no default bank safe seeded in this test DB');
        return;
      }
      final before = bankSafe.balance;

      final paperId = await db.createCommercialPaper(
        paperNumber: 'CHQ-DEP-CASH-1',
        type: 'cheque',
        direction: 'received',
        partyId: partyId,
        amount: 5000.0,
        issueDate: DateTime.now(),
        dueDate: DateTime.now().add(const Duration(days: 30)),
      );

      // إيداع برسم التحصيل — intermediate, must NOT touch the bank.
      await db.changePaperStatus(
        paperId: paperId, newStatus: 'deposited', changedBy: userId);
      final afterDeposit = (await db.getDefaultSafeByType('bank'))!.balance;
      expect(afterDeposit, closeTo(before, 0.01),
          reason: 'deposit is intermediate — must NOT add money to the bank safe');

      // تحصيل — the bank is credited once.
      await db.changePaperStatus(
        paperId: paperId, newStatus: 'cashed', changedBy: userId);
      final afterCash = (await db.getDefaultSafeByType('bank'))!.balance;
      expect(afterCash - before, closeTo(5000.0, 0.01),
          reason: 'cheque value must hit the bank EXACTLY once '
              '(deposit+cash = 5000, not 10000)');

      // All JEs balanced → global trial balance zero.
      final tb = await db.customSelect(
        'SELECT COALESCE(SUM(debit),0) as d, COALESCE(SUM(credit),0) as c '
        'FROM journal_entry_lines',
        readsFrom: {db.journalEntryLines},
      ).getSingle();
      expect(((tb.data['d'] as num) - (tb.data['c'] as num)).abs(), lessThan(0.01),
          reason: 'trial balance must stay zero across the cheque lifecycle');
    });

    test('bounced paper updates status to bounced', () async {
      final paperId = await db.createCommercialPaper(
        paperNumber: 'CHQ-BOUNCE-001',
        type: 'cheque',
        direction: 'received',
        partyId: partyId,
        amount: 1500.0,
        issueDate: DateTime.now(),
        dueDate: DateTime.now().add(const Duration(days: 10)),
      );

      await db.changePaperStatus(
        paperId: paperId,
        newStatus: 'bounced',
        changedBy: userId,
        notes: 'رُفض الشيك لعدم كفاية الرصيد',
      );

      final paper = await db.getCommercialPaper(paperId);
      expect(paper!.status, equals('bounced'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('Commercial Papers Summary', () {
    // ─────────────────────────────────────────────────────────────────────
    test('summary totals include all created papers', () async {
      await db.createCommercialPaper(
        paperNumber: 'CHQ-SUM-001',
        type: 'cheque',
        direction: 'received',
        partyId: partyId,
        amount: 1000.0,
        issueDate: DateTime.now(),
        dueDate: DateTime.now().add(const Duration(days: 30)),
      );
      await db.createCommercialPaper(
        paperNumber: 'CHQ-SUM-002',
        type: 'cheque',
        direction: 'received',
        partyId: partyId,
        amount: 2000.0,
        issueDate: DateTime.now(),
        dueDate: DateTime.now().add(const Duration(days: 60)),
      );

      final summary = await db.getCommercialPapersSummary();
      expect(summary, isNotNull);
      final pendingReceived = (summary['received'] as Map)['pending'] as double;
      expect(pendingReceived, greaterThanOrEqualTo(3000.0),
          reason: 'Two pending papers (1000 + 2000) = 3000 total');
    });
  });
}
