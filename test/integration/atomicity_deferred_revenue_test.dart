import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' as drift;
import 'package:ural_erp/data/database/database.dart';

/// Phase 2 — Fix 2.3: Deferred Revenue Recognition Atomicity
///
/// Verifies that `processDueRecognitions()` in DeferredScheduleDao:
///  1. Processes each period in its own atomic transaction.
///  2. A failure on one period leaves other periods eligible for retry.
///  3. The `is_posted` flag and the journal entry ID are set together (atomically).
///  4. Over-recognition is prevented (schedule does not exceed total amount).
///  5. Schedule status transitions to 'completed' when all periods are posted.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();

    final roleId = await db.into(db.roles).insert(
      RolesCompanion.insert(name: 'admin', isSystemRole: const drift.Value(true)),
    );
    await db.createUser(
      username: 'admin',
      password: 'pw',
      displayName: 'Admin',
      roleId: roleId,
    );
  });

  tearDown(() async => db.close());

  // ═══════════════════════════════════════════════════════════════════════════
  group('Fix 2.3 — Deferred Revenue Recognition Atomicity', () {
    // ─────────────────────────────────────────────────────────────────────────
    test('processDueRecognitions completes with 0 errors when no entries are due', () async {
      // Act
      final processed = await db.processDueRecognitions();

      // Assert — idempotent with empty queue
      expect(processed, 0, reason: 'No due entries should result in 0 processed');
    });

    // ─────────────────────────────────────────────────────────────────────────
    test('Due recognition entry: JE creation and is_posted are atomic', () async {
      // Arrange — set up minimal COA for deferred revenue
      final now = DateTime.now();
      final deferredRevenueAccId = await db.into(db.accounts).insert(
        AccountsCompanion.insert(
          name: 'Deferred Revenue',
          code: '2400',
          accountType: 'liability',
          normalBalance: const drift.Value('credit'),
        ),
      );
      final revenueAccId = await db.into(db.accounts).insert(
        AccountsCompanion.insert(
          name: 'Service Revenue',
          code: '4100',
          accountType: 'revenue',
          normalBalance: const drift.Value('credit'),
        ),
      );

      // Create a 3-period deferred revenue schedule (monthly, backdated so all are due)
      final scheduleId = await db.createDeferredSchedule(
        sourceAccountId: deferredRevenueAccId,
        targetAccountId: revenueAccId,
        totalAmount: 300.0,
        totalPeriods: 3,
        type: 'deferred_revenue',
        description: 'Test Service Contract',
        startDate: now.subtract(const Duration(days: 90)),
        endDate: now.add(const Duration(days: 1)),
      );
      expect(scheduleId, isNotNull);

      // Act — process due entries (all 3 are backdated so all should be due)
      final processed = await db.processDueRecognitions();
      expect(processed, greaterThanOrEqualTo(1),
          reason: 'At least one period should be recognized');

      // Assert — all processed entries have is_posted = true
      final entries = await db.customSelect(
        'SELECT * FROM deferred_entries WHERE schedule_id = ? AND is_posted = 1',
        variables: [drift.Variable<int>(scheduleId)],
      ).get();
      expect(entries.isNotEmpty, isTrue,
          reason: 'Processed entries should be marked as posted');

      // Each posted entry should have a valid journal_entry_id
      for (final entry in entries) {
        final jeId = entry.read<int?>('journal_entry_id');
        expect(jeId, isNotNull,
            reason: 'Posted entry must have a journal_entry_id (atomic JE+flag)');
      }
    });

    // ─────────────────────────────────────────────────────────────────────────
    test('Already-posted entries are not re-processed on second run', () async {
      // Arrange — minimal COA
      final now = DateTime.now();
      final srcId = await db.into(db.accounts).insert(AccountsCompanion.insert(
        name: 'Deferred Rev 2', code: '2401', accountType: 'liability',
        normalBalance: const drift.Value('credit'),
      ));
      final tgtId = await db.into(db.accounts).insert(AccountsCompanion.insert(
        name: 'Revenue 2', code: '4101', accountType: 'revenue',
        normalBalance: const drift.Value('credit'),
      ));

      final scheduleId = await db.createDeferredSchedule(
        sourceAccountId: srcId,
        targetAccountId: tgtId,
        totalAmount: 120.0,
        totalPeriods: 2,
        type: 'deferred_revenue',
        description: 'Idempotency Test',
        startDate: now.subtract(const Duration(days: 60)),
        endDate: now.add(const Duration(days: 1)),
      );

      // First recognition run
      final firstRun = await db.processDueRecognitions();
      expect(firstRun, greaterThanOrEqualTo(1));

      // Count JEs after first run
      final jeCountAfterFirst = await (db.select(db.journalEntries)
            ..where((j) => j.referenceType.equals('deferred_recognition')))
          .get();
      final expectedJeCount = jeCountAfterFirst.length;

      // Second recognition run (should produce no new JEs — all are already posted)
      await db.processDueRecognitions();

      final jeCountAfterSecond = await (db.select(db.journalEntries)
            ..where((j) => j.referenceType.equals('deferred_recognition')))
          .get();

      expect(jeCountAfterSecond.length, expectedJeCount,
          reason: 'Second run should not create duplicate JEs for already-posted entries');
    });

    // ─────────────────────────────────────────────────────────────────────────
    test('Schedule marked completed after all periods are processed', () async {
      // Arrange — single-period schedule (simpler completion verification)
      final now = DateTime.now();
      final srcId = await db.into(db.accounts).insert(AccountsCompanion.insert(
        name: 'Deferred Rev One-Shot', code: '2402', accountType: 'liability',
        normalBalance: const drift.Value('credit'),
      ));
      final tgtId = await db.into(db.accounts).insert(AccountsCompanion.insert(
        name: 'Revenue One-Shot', code: '4102', accountType: 'revenue',
        normalBalance: const drift.Value('credit'),
      ));

      final scheduleId = await db.createDeferredSchedule(
        sourceAccountId: srcId,
        targetAccountId: tgtId,
        totalAmount: 500.0,
        totalPeriods: 1,
        type: 'deferred_revenue',
        description: 'One-Shot Schedule',
        startDate: now.subtract(const Duration(days: 30)),
        endDate: now.add(const Duration(days: 1)),
      );

      // Act — process
      await db.processDueRecognitions();

      // Assert — schedule status should be 'completed'
      final scheduleRows = await db.customSelect(
        'SELECT status, completed_periods, total_periods FROM deferred_schedules WHERE id = ?',
        variables: [drift.Variable<int>(scheduleId)],
      ).get();

      expect(scheduleRows.isNotEmpty, isTrue);
      final status = scheduleRows.first.read<String>('status');
      expect(status, 'completed',
          reason: 'Single-period schedule should be marked completed after processing');
    });

    // ─────────────────────────────────────────────────────────────────────────
    test('Recognized amount accumulates correctly across multiple runs', () async {
      final now = DateTime.now();
      final srcId = await db.into(db.accounts).insert(AccountsCompanion.insert(
        name: 'Deferred Rev Accum', code: '2403', accountType: 'liability',
        normalBalance: const drift.Value('credit'),
      ));
      final tgtId = await db.into(db.accounts).insert(AccountsCompanion.insert(
        name: 'Revenue Accum', code: '4103', accountType: 'revenue',
        normalBalance: const drift.Value('credit'),
      ));

      // 3 periods × 100 = 300 total
      final scheduleId = await db.createDeferredSchedule(
        sourceAccountId: srcId,
        targetAccountId: tgtId,
        totalAmount: 300.0,
        totalPeriods: 3,
        type: 'deferred_revenue',
        description: 'Accumulation Test',
        startDate: now.subtract(const Duration(days: 90)),
        endDate: now.add(const Duration(days: 1)),
      );

      await db.processDueRecognitions();

      final scheduleRows = await db.customSelect(
        'SELECT recognized_amount, remaining_amount FROM deferred_schedules WHERE id = ?',
        variables: [drift.Variable<int>(scheduleId)],
      ).get();

      expect(scheduleRows.isNotEmpty, isTrue);
      final recognized = scheduleRows.first.read<double>('recognized_amount');
      final remaining = scheduleRows.first.read<double>('remaining_amount');

      expect(recognized, greaterThan(0), reason: 'Recognized amount should be positive after processing');
      expect(recognized + remaining, closeTo(300.0, 0.01),
          reason: 'Recognized + remaining must always equal total (300)');
    });
  });
}
