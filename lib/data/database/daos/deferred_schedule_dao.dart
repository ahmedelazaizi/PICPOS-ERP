part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// DEFERRED REVENUE / EXPENSE DAO — الإيرادات والمصروفات المؤجلة
// IAS 18 (Revenue Recognition) / IAS 38 (Prepaid Expenses)
// ═══════════════════════════════════════════════════════════════════════════

extension DeferredScheduleDao on AppDatabase {

  /// Create a deferred schedule with auto-generated entries
  Future<int> createDeferredSchedule({
    required String type, // deferred_revenue, prepaid_expense
    required String description,
    required double totalAmount,
    required int sourceAccountId, // e.g. 2203 Deferred Revenue
    required int targetAccountId, // e.g. 4101 Revenue
    required DateTime startDate,
    required DateTime endDate,
    required int totalPeriods,
    String frequency = 'monthly',
    int? referenceId,
    String? referenceType,
  }) async {
    return transaction(() async {
      final scheduleId = await into(deferredSchedules).insert(
        DeferredSchedulesCompanion.insert(
          type: type,
          description: description,
          totalAmount: totalAmount,
          remainingAmount: Value(totalAmount),
          sourceAccountId: sourceAccountId,
          targetAccountId: targetAccountId,
          startDate: startDate,
          endDate: endDate,
          totalPeriods: totalPeriods,
          frequency: Value(frequency),
          referenceId: Value(referenceId),
          referenceType: Value(referenceType),
        ),
      );

      // Generate recognition entries
      final periodAmount = totalAmount / totalPeriods;
      for (int i = 0; i < totalPeriods; i++) {
        final recognitionDate = frequency == 'monthly'
            ? DateTime(startDate.year, startDate.month + i + 1, 0)
            : DateTime(startDate.year, startDate.month + (i + 1) * 3, 0);

        await into(deferredEntries).insert(
          DeferredEntriesCompanion.insert(
            scheduleId: scheduleId,
            periodNumber: i + 1,
            recognitionDate: recognitionDate,
            amount: periodAmount,
          ),
        );
      }

      return scheduleId;
    });
  }

  /// Process due deferred entries — post JE for each due period
  Future<int> processDueRecognitions({DateTime? asOfDate}) async {
    final cutoff = asOfDate ?? DateTime.now();
    int processed = 0;

    // Find all unposted entries that are due
    final boolFalse = sqlBool(false);
    final dueEntries = await customSelect(
      '''SELECT de.*, ds.source_account_id, ds.target_account_id, ds.type, ds.description as schedule_desc
         FROM deferred_entries de
         JOIN deferred_schedules ds ON de.schedule_id = ds.id
         WHERE de.is_posted = $boolFalse AND de.recognition_date <= ?
         AND ds.status = 'active'
         ORDER BY de.recognition_date''',
      variables: [Variable(cutoff)],
    ).get();

    for (final entry in dueEntries) {
      final entryId = entry.data['id'] as int;
      final scheduleId = entry.data['schedule_id'] as int;
      final periodNumber = entry.data['period_number'] as int;

      try {
        // PHASE-2 FIX: Each entry is processed in its own transaction.
        // This ensures the JE creation and the "mark as posted" flag are atomic.
        // A failure on one period does not block other periods in the same run.
        await transaction(() async {
          final amount = (entry.data['amount'] as num).toDouble();
          final sourceAccountId = entry.data['source_account_id'] as int;
          final targetAccountId = entry.data['target_account_id'] as int;
          final type = entry.data['type'] as String;
          final scheduleDesc = entry.data['schedule_desc'] as String;

          // Post JE: Dr Target (Revenue/Expense), Cr Source (Deferred)
          // For deferred revenue: Dr Deferred Revenue → Cr Revenue
          // For prepaid expense: Dr Expense → Cr Prepaid Expense
          final jeDescription = type == 'deferred_revenue'
              ? 'ترحيل إيراد مؤجل — $scheduleDesc (فترة $periodNumber)'
              : 'ترحيل مصروف مدفوع مقدماً — $scheduleDesc (فترة $periodNumber)';

          // Throws on GL failure → whole entry-level transaction rolls back
          final jeId = await accountingDao.createJournalEntry(
            description: jeDescription,
            date: DateTime.now(),
            lines: [
              JournalLine(
                accountId: targetAccountId,
                debit: amount,
                description: type == 'deferred_revenue'
                    ? 'استحقاق إيراد — فترة $periodNumber'
                    : 'استحقاق مصروف — فترة $periodNumber',
              ),
              JournalLine(
                accountId: sourceAccountId,
                credit: amount,
                description: type == 'deferred_revenue'
                    ? 'تخفيض إيراد مؤجل'
                    : 'تخفيض مصروف مدفوع مقدماً',
              ),
            ],
            referenceType: 'deferred_recognition',
            referenceId: scheduleId,
            isAutoPosted: true,
          );

          // Mark entry as posted (atomic with JE creation above)
          final boolTrue = sqlBool(true);
          await customStatement(
            'UPDATE deferred_entries SET is_posted = $boolTrue, posted_at = ?, journal_entry_id = ? WHERE id = ?',
            [DateTime.now().millisecondsSinceEpoch ~/ 1000, jeId, entryId],
          );

          // Update schedule counters (atomic with JE creation above)
          await customStatement(
            '''UPDATE deferred_schedules SET
               recognized_amount = recognized_amount + ?,
               remaining_amount = remaining_amount - ?,
               completed_periods = completed_periods + 1
               WHERE id = ?''',
            [amount, amount, scheduleId],
          );

          // Check if schedule is complete
          await customStatement(
            '''UPDATE deferred_schedules SET status = 'completed'
               WHERE id = ? AND completed_periods >= total_periods''',
            [scheduleId],
          );
        });

        processed++;
      } catch (e) {
        // PHASE-2 FIX: Dead-Letter pattern — log with entry ID so monitoring
        // systems can alert and the next scheduler run will retry this entry
        // (it's still marked is_posted=false so it will be picked up again).
        debugPrint('[DEFERRED][DLQ] Entry #$entryId (schedule #$scheduleId, period $periodNumber) failed: $e');
      }
    }

    return processed;
  }

  /// Get active deferred schedules
  Future<List<DeferredScheduleData>> getActiveSchedules() {
    return (select(deferredSchedules)
          ..where((s) => s.status.equals('active'))
          ..orderBy([(s) => OrderingTerm.asc(s.startDate)]))
        .get();
  }

  /// Get all entries for a schedule
  Future<List<DeferredEntryData>> getScheduleEntries(int scheduleId) {
    return (select(deferredEntries)
          ..where((e) => e.scheduleId.equals(scheduleId))
          ..orderBy([(e) => OrderingTerm.asc(e.periodNumber)]))
        .get();
  }
}
