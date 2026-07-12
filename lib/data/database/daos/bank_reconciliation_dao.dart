part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// BANK RECONCILIATION DAO — المطابقة البنكية الآلية
// ═══════════════════════════════════════════════════════════════════════════

extension BankReconciliationDao on AppDatabase {

  // ─────────────────────────────────────────────────────────────────────────
  // BANK STATEMENT IMPORT — استيراد كشوف البنك
  // ─────────────────────────────────────────────────────────────────────────

  /// Import bank statement lines from parsed CSV data
  Future<int> importBankStatementLines({
    required int bankAccountId,
    required List<Map<String, dynamic>> lines,
    required String batchId,
  }) async {
    int imported = 0;
    await transaction(() async {
      for (final line in lines) {
        await into(bankStatementLines).insert(
          BankStatementLinesCompanion.insert(
            bankAccountId: bankAccountId,
            transactionDate: line['date'] as DateTime,
            reference: Value(line['reference'] as String?),
            description: Value(line['description'] as String?),
            debitAmount: Value(
              (line['debit'] as num?)?.toDouble() ?? 0,
            ),
            creditAmount: Value(
              (line['credit'] as num?)?.toDouble() ?? 0,
            ),
            runningBalance: Value(
              (line['balance'] as num?)?.toDouble() ?? 0,
            ),
            importBatch: Value(batchId),
          ),
        );
        imported++;
      }
    });
    return imported;
  }

  /// Get unmatched bank statement lines for a bank account
  Future<List<BankStatementLine>> getUnmatchedStatementLines(
    int bankAccountId,
  ) {
    return (select(bankStatementLines)
          ..where((l) => l.bankAccountId.equals(bankAccountId))
          ..where((l) => l.isMatched.equals(false))
          ..orderBy([(l) => OrderingTerm.asc(l.transactionDate)]))
        .get();
  }

  /// Get all statement lines for a period
  Future<List<BankStatementLine>> getStatementLines({
    required int bankAccountId,
    required DateTime from,
    required DateTime to,
  }) {
    return (select(bankStatementLines)
          ..where((l) => l.bankAccountId.equals(bankAccountId))
          ..where((l) => l.transactionDate.isBiggerOrEqualValue(from))
          ..where((l) => l.transactionDate.isSmallerOrEqualValue(to))
          ..orderBy([(l) => OrderingTerm.asc(l.transactionDate)]))
        .get();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // AUTO-MATCH ENGINE — محرك المطابقة الآلية
  // ─────────────────────────────────────────────────────────────────────────

  /// Auto-match bank statement lines with journal entry lines
  /// Matches by: amount + date proximity (±3 days)
  Future<int> autoMatchStatementLines(int bankAccountId) async {
    int matched = 0;
    final unmatched = await getUnmatchedStatementLines(bankAccountId);

    for (final stmt in unmatched) {
      // Determine if this is a debit or credit from bank's perspective
      final amount = stmt.debitAmount > 0
          ? stmt.debitAmount
          : stmt.creditAmount;
      final isDebit = stmt.debitAmount > 0;

      // Search for matching journal entry lines
      // Bank debit (money out) = credit in our books
      // Bank credit (money in) = debit in our books
      // Drift stores DateTime as epoch seconds on both SQLite and Postgres.
      // `julianday()` expects a text date — using it on an integer epoch
      // returns NULL on SQLite and fails on Postgres. Compare directly in
      // seconds instead (3 days = 259200 seconds).
      const threeDaysInSeconds = 3 * 24 * 60 * 60;
      final matchQuery = await customSelect(
        '''SELECT l.id, l.debit, l.credit, e.entry_date, e.description
           FROM journal_entry_lines l
           JOIN journal_entries e ON l.entry_id = e.id
           WHERE l.account_id = ?
           AND ABS(${isDebit ? 'l.credit' : 'l.debit'} - ?) < 0.01
           AND ABS(e.entry_date - ?) <= ?
           AND l.id NOT IN (
             SELECT matched_journal_line_id FROM bank_statement_lines
             WHERE matched_journal_line_id IS NOT NULL
           )
           LIMIT 1''',
        variables: [
          Variable(bankAccountId),
          Variable(amount),
          dateVar(stmt.transactionDate),
          const Variable<int>(threeDaysInSeconds),
        ],
      ).getSingleOrNull();

      if (matchQuery != null) {
        final journalLineId = matchQuery.data['id'] as int;
        await (update(bankStatementLines)
              ..where((l) => l.id.equals(stmt.id)))
            .write(BankStatementLinesCompanion(
          isMatched: const Value(true),
          matchedJournalLineId: Value(journalLineId),
          matchType: const Value('auto'),
        ));
        matched++;
      }
    }
    return matched;
  }

  /// Manually match a statement line to a journal entry line
  Future<void> manualMatchStatement({
    required int statementLineId,
    required int journalLineId,
  }) async {
    await (update(bankStatementLines)
          ..where((l) => l.id.equals(statementLineId)))
        .write(BankStatementLinesCompanion(
      isMatched: const Value(true),
      matchedJournalLineId: Value(journalLineId),
      matchType: const Value('manual'),
    ));
  }

  /// Unmatch a statement line
  Future<void> unmatchStatement(int statementLineId) async {
    await (update(bankStatementLines)
          ..where((l) => l.id.equals(statementLineId)))
        .write(const BankStatementLinesCompanion(
      isMatched: Value(false),
      matchedJournalLineId: Value(null),
      matchType: Value(null),
    ));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // RECONCILIATION SESSION — جلسة المطابقة
  // ─────────────────────────────────────────────────────────────────────────

  /// Create a new reconciliation session
  Future<int> createReconciliation({
    required int bankAccountId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required double statementBalance,
    int? userId,
  }) async {
    // Calculate book balance from GL
    final bookResult = await customSelect(
      '''SELECT COALESCE(SUM(debit - credit), 0) as balance
         FROM journal_entry_lines l
         JOIN journal_entries e ON l.entry_id = e.id
         WHERE l.account_id = ? AND e.entry_date <= ?''',
      variables: [Variable(bankAccountId), Variable(periodEnd)],
    ).getSingle();
    final bookBalance = (bookResult.data['balance'] as num?)?.toDouble() ?? 0;

    // Count matched/unmatched
    final matchStats = await customSelect(
      '''SELECT
          SUM(CASE WHEN is_matched = 1 THEN 1 ELSE 0 END) as matched,
          SUM(CASE WHEN is_matched = 0 THEN 1 ELSE 0 END) as unmatched
         FROM bank_statement_lines
         WHERE bank_account_id = ?
         AND transaction_date BETWEEN ? AND ?''',
      variables: [
        Variable(bankAccountId),
        Variable(periodStart),
        Variable(periodEnd),
      ],
    ).getSingle();

    return into(bankReconciliations).insert(
      BankReconciliationsCompanion.insert(
        bankAccountId: bankAccountId,
        periodStart: periodStart,
        periodEnd: periodEnd,
        statementBalance: statementBalance,
        bookBalance: bookBalance,
        difference: Value(statementBalance - bookBalance),
        totalMatched: Value(
          (matchStats.data['matched'] as int?) ?? 0,
        ),
        totalUnmatched: Value(
          (matchStats.data['unmatched'] as int?) ?? 0,
        ),
        preparedBy: Value(userId),
      ),
    );
  }

  /// Complete a reconciliation (mark as finished)
  Future<void> completeReconciliation(int reconciliationId) async {
    await (update(bankReconciliations)
          ..where((r) => r.id.equals(reconciliationId)))
        .write(BankReconciliationsCompanion(
      status: const Value('completed'),
      completedAt: Value(DateTime.now()),
    ));
  }

  /// Watch all reconciliations
  Stream<List<BankReconciliationData>> watchReconciliations() {
    return (select(bankReconciliations)
          ..orderBy([(r) => OrderingTerm.desc(r.createdAt)]))
        .watch();
  }

  /// Get reconciliation report data
  Future<Map<String, dynamic>> getReconciliationReport(
    int reconciliationId,
  ) async {
    final recon = await (select(bankReconciliations)
          ..where((r) => r.id.equals(reconciliationId)))
        .getSingle();

    final matchedLines = await (select(bankStatementLines)
          ..where((l) => l.bankAccountId.equals(recon.bankAccountId))
          ..where((l) => l.transactionDate.isBiggerOrEqualValue(recon.periodStart))
          ..where((l) => l.transactionDate.isSmallerOrEqualValue(recon.periodEnd))
          ..where((l) => l.isMatched.equals(true)))
        .get();

    final unmatchedLines = await (select(bankStatementLines)
          ..where((l) => l.bankAccountId.equals(recon.bankAccountId))
          ..where((l) => l.transactionDate.isBiggerOrEqualValue(recon.periodStart))
          ..where((l) => l.transactionDate.isSmallerOrEqualValue(recon.periodEnd))
          ..where((l) => l.isMatched.equals(false)))
        .get();

    // Outstanding JE lines (in books, not in bank)
    final outstandingJE = await customSelect(
      '''SELECT l.*, e.entry_date, e.description as entry_desc
         FROM journal_entry_lines l
         JOIN journal_entries e ON l.entry_id = e.id
         WHERE l.account_id = ?
         AND e.entry_date BETWEEN ? AND ?
         AND l.id NOT IN (
           SELECT matched_journal_line_id FROM bank_statement_lines
           WHERE matched_journal_line_id IS NOT NULL
         )''',
      variables: [
        Variable(recon.bankAccountId),
        Variable(recon.periodStart),
        Variable(recon.periodEnd),
      ],
    ).get();

    return {
      'reconciliation': recon,
      'statementBalance': recon.statementBalance,
      'bookBalance': recon.bookBalance,
      'difference': recon.difference,
      'matchedCount': matchedLines.length,
      'unmatchedCount': unmatchedLines.length,
      'matchedLines': matchedLines,
      'unmatchedBankLines': unmatchedLines,
      'outstandingBookEntries': outstandingJE,
    };
  }
}
