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
  // §٣‑٦ — الدفترُ الذي تُطابَق عليه: قيودٌ **مرحَّلةٌ غيرُ محذوفة**، وشجرةُ
  //        الحساب لا الحسابُ المفرد
  // ─────────────────────────────────────────────────────────────────────────

  /// شرطُ القيد الصالح للمطابقة — يُلحَق بكلّ ضمٍّ على `journal_entries`.
  ///
  /// 🔴 لم يكن في هذا الملفّ شرطٌ واحدٌ منهما، وثلاثةُ استعلاماتٍ تقرأ الأستاذَ:
  /// رصيدُ الدفتر، والمطابقةُ الآليّة، وقيودُ «في الدفتر لا في البنك». فكانت
  /// **المسوّدةُ غيرُ المرحَّلة والقيدُ المحذوفُ** يدخلان الثلاثةَ جميعاً:
  ///
  ///   • رصيدُ الدفتر يخالف الأستاذَ ⇒ فرقُ المطابقة رقمٌ مخترَع.
  ///   • والمطابقةُ الآليّةُ تُغلق سطرَ كشفٍ على قيدٍ **محذوف** — فيبدو مطابَقاً
  ///     وما له في الدفتر وجود.
  ///
  /// وهذه عينُ صيغةِ `accounting_reports_dao.dart` على نفس الجدول.
  static const _postedEntry = 'AND e.is_posted = 1 AND e.is_deleted = 0';

  /// حسابُ البنك **وفروعُه**.
  ///
  /// كان الحصرُ `account_id = ?` على حسابٍ مفرد. وشجرةُ الحسابات هنا تسمح
  /// بحسابٍ أبٍ للبنك تحته فرعيّاتٌ (حسابٌ لكلّ بنكٍ أو لكلّ فرع)، فمطابقةٌ
  /// على الأب كانت تقرأ **صفراً** من الحركة وتعلن الفرقَ كلَّه.
  /// وعلى حسابٍ ورقيٍّ (بلا أبناء) تعيد الدالّةُ نفسَه وحدَه — فلا تغيير.
  Future<({String clause, List<Variable> vars})> _bankAccountScope(
    int bankAccountId, {
    String alias = 'l',
  }) async {
    final ids = await accountSubtreeIds(bankAccountId);
    if (ids.isEmpty) ids.add(bankAccountId); // حسابٌ غيرُ موجودٍ ⇒ لا يطابق شيئاً
    final ph = ids.map((_) => '?').join(', ');
    return (
      clause: '$alias.account_id IN ($ph)',
      vars: ids.map<Variable>((id) => Variable<int>(id)).toList(),
    );
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
      final scope = await _bankAccountScope(bankAccountId);
      final matchQuery = await customSelect(
        '''SELECT l.id, l.debit, l.credit, e.entry_date, e.description
           FROM journal_entry_lines l
           JOIN journal_entries e ON l.entry_id = e.id
           WHERE ${scope.clause}
           $_postedEntry
           AND ABS(${isDebit ? 'l.credit' : 'l.debit'} - ?) < 0.01
           AND ABS(e.entry_date - ?) <= ?
           AND l.id NOT IN (
             SELECT matched_journal_line_id FROM bank_statement_lines
             WHERE matched_journal_line_id IS NOT NULL
           )
           ORDER BY
             CASE WHEN ? IS NOT NULL AND e.description LIKE '%' || ? || '%' THEN 0 ELSE 1 END,
             ABS(e.entry_date - ?) ASC,
             ABS(${isDebit ? 'l.credit' : 'l.debit'} - ?) ASC,
             l.id ASC
           LIMIT 1''',
        variables: [
          ...scope.vars,
          Variable(amount),
          dateVar(stmt.transactionDate),
          const Variable<int>(threeDaysInSeconds),
           Variable(stmt.reference),
           Variable(stmt.reference),
           dateVar(stmt.transactionDate),
           Variable(amount),
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
  ///
  /// 🔴 **قيدٌ واحدٌ لا يغطّي سطرَين.** المطابقةُ الآليّةُ تُقصي القيودَ
  /// المستعملةَ سلفاً (‏`l.id NOT IN (...)`)، واليدويّةُ كانت تكتب بلا فحصٍ
  /// إطلاقاً. فيمكن إسنادُ **نفسِ سطر القيد** إلى سطرَي كشفٍ مختلفَين: يُعَدّان
  /// مطابَقَين اثنَين، وينخفض «غيرُ المطابَق» بمقدارَين، وتبدو المطابقةُ تامّةً
  /// بينما حركةٌ بنكيّةٌ كاملةٌ بلا ما يقابلها في الدفتر. وهذا **يخفي** الفرقَ
  /// بدل أن يظهره — وإخفاءُ الفرق هو عينُ ما تقوم المطابقةُ لكشفه.
  ///
  /// والرمْيُ لا الابتلاعُ: مطابقةٌ لم تقع يجب أن تُقال للمحاسب. ولإعادة
  /// الإسناد يُنزَع الأوّلُ بـ[unmatchStatement].
  ///
  /// ⚠️ وهذا حارسُ تطبيقٍ لا قيدُ قاعدة: `matched_journal_line_id` عمودٌ بلا
  /// مفتاحٍ أجنبيٍّ ولا فهرسٍ فريد. وشدُّ قيدٍ على جدولٍ قائمٍ يمسّ الهجرات،
  /// فلم يُفعَل لمسارٍ بلا مُنادٍ اليوم.
  Future<void> manualMatchStatement({
    required int statementLineId,
    required int journalLineId,
  }) async {
    final taken = await (select(bankStatementLines)
          ..where((l) =>
              l.matchedJournalLineId.equals(journalLineId) &
              l.id.isNotValue(statementLineId))
          ..limit(1))
        .getSingleOrNull();

    if (taken != null) {
      throw StateError(
        'سطرُ القيد رقم $journalLineId مطابَقٌ سلفاً لسطر الكشف رقم '
        '${taken.id}. انزع المطابقةَ الأولى قبل إعادة الإسناد.',
      );
    }

    await (update(bankStatementLines)
          ..where((l) => l.id.equals(statementLineId)))
        .write(BankStatementLinesCompanion(
      isMatched: const Value(true),
      matchedJournalLineId: Value(journalLineId),
      matchType: const Value('manual'),
    ));
  }

  /// Unmatch a statement line
  /// A statement line has no reconciliation FK; membership is inferred from
  /// bank account plus the completed session's date range.
  Future<void> unmatchStatement(int statementLineId) async {
    final line = await (select(bankStatementLines)
          ..where((l) => l.id.equals(statementLineId)))
        .getSingle();
    final completed = await (select(bankReconciliations)
          ..where((r) => r.bankAccountId.equals(line.bankAccountId) &
              r.status.equals('completed') &
              r.periodStart.isSmallerOrEqualValue(line.transactionDate) &
              r.periodEnd.isBiggerOrEqualValue(line.transactionDate))
          ..limit(1))
        .getSingleOrNull();
    if (completed != null) {
      throw StateError('لا يمكن إلغاء مطابقة سطر كشف ضمن تسوية بنكية مكتملة.');
    }
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
    // §٣‑٦ — المرحَّلُ غيرُ المحذوف، وعلى شجرة الحساب. راجع [_postedEntry].
    final balanceScope = await _bankAccountScope(bankAccountId);
    final bookResult = await customSelect(
      '''SELECT COALESCE(SUM(l.debit - l.credit), 0) as balance
         FROM journal_entry_lines l
         JOIN journal_entries e ON l.entry_id = e.id
         WHERE ${balanceScope.clause}
         $_postedEntry
         AND e.entry_date <= ?''',
      variables: [...balanceScope.vars, dateVar(periodEnd)],
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
        dateVar(periodStart),
        dateVar(periodEnd),
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
  /// يُقفل الجلسةَ — **ويُحدّث العدّادين المحفوظَين قبل الختم**.
  ///
  /// 🔴 **كان يختم صفّاً يكذب.** `total_matched`/`total_unmatched` يُحسبان
  /// **لحظةَ الإنشاء** في [createReconciliation]، والشاشةُ تُلزم بإنشاء
  /// الجلسة **قبل** الاستيراد (المتنُ لا يظهر بلا جلسة). فالجلسةُ تُنشأ
  /// وأسطرُ الكشف صفر، ثمّ يُستورَد مئةُ سطرٍ ويُطابَق تسعون — ويبقى الصفُّ
  /// المحفوظُ يقول `0/0` إلى الأبد.
  ///
  /// ولم يكن يُرى: `getReconciliationReport` يحسب `matchedCount`
  /// و`unmatchedCount` **حيَّين** من الجدول، فالشاشةُ تعرض الصحيحَ بينما
  /// الأرشيفُ يحمل الكذب. ومن يقرأ `bank_reconciliations` لاحقاً — تقريرٌ
  /// أو تدقيقٌ أو تصديرٌ — يقرأ الصفرَ لا التسعين.
  ///
  /// ⚠️ **ولا يُعاد حسابُ `bookBalance` و`difference` هنا عن قصد**: هما
  /// **لقطةٌ** لحظةَ فتح الجلسة مقابلَ رصيد كشفٍ أدخله المحاسبُ لتلك اللحظة،
  /// وإعادةُ حسابهما عند الإقفال تُغيّر الرقمَ الذي رآه وأقرّه في حوار
  /// التأكيد. والمطابقةُ لا تُحرّك رصيدَ الدفتر أصلاً — تربط الأسطرَ فقط.
  Future<void> completeReconciliation(int reconciliationId, {int? adjustmentAccountId}) async {
    final recon = await (select(bankReconciliations)
          ..where((r) => r.id.equals(reconciliationId)))
        .getSingle();

    // نفسُ استعلامِ [createReconciliation] حرفاً — ولو افترقا لأعطى الإقفالُ
    // عدداً غيرَ الذي أعطاه الفتحُ على نفس البيانات.
    final matchStats = await customSelect(
      '''SELECT
          SUM(CASE WHEN is_matched = 1 THEN 1 ELSE 0 END) as matched,
          SUM(CASE WHEN is_matched = 0 THEN 1 ELSE 0 END) as unmatched
         FROM bank_statement_lines
         WHERE bank_account_id = ?
         AND transaction_date BETWEEN ? AND ?''',
      variables: [
        Variable(recon.bankAccountId),
        dateVar(recon.periodStart),
        dateVar(recon.periodEnd),
      ],
    ).getSingle();

    await transaction(() async {
      if (recon.difference.abs() > FinancialUtils.balanceTolerance &&
        adjustmentAccountId == null) {
      throw StateError('لا يمكن إكمال التسوية البنكية: يوجد فرق غير مسوّى.');
    }
    if (recon.difference.abs() > FinancialUtils.balanceTolerance) {
      await createJournalEntry(
        description: 'تسوية فرق بنكي #$reconciliationId',
        date: DateTime.now(),
        isAutoPosted: true,
        referenceType: 'bank_reconciliation',
        referenceId: reconciliationId,
        lines: [
          JournalLine(accountId: recon.bankAccountId, debit: recon.difference > 0 ? recon.difference.abs() : 0, credit: recon.difference < 0 ? recon.difference.abs() : 0, description: 'فرق التسوية البنكية'),
          JournalLine(accountId: adjustmentAccountId!, debit: recon.difference < 0 ? recon.difference.abs() : 0, credit: recon.difference > 0 ? recon.difference.abs() : 0, description: 'حساب تسوية الفرق'),
        ],
      );
    }

    await (update(bankReconciliations)
          ..where((r) => r.id.equals(reconciliationId)))
        .write(BankReconciliationsCompanion(
      status: const Value('completed'),
      completedAt: Value(DateTime.now()),
      totalMatched: Value((matchStats.data['matched'] as int?) ?? 0),
      totalUnmatched: Value((matchStats.data['unmatched'] as int?) ?? 0),
    ));
    });
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
    // §٣‑٦ — نفسُ شرطِ رصيد الدفتر: مسوّدةٌ غيرُ مرحَّلةٍ ليست «في الدفتر»،
    // وقيدٌ محذوفٌ ليس فيه أصلاً. وبدونهما كانت قائمةُ «لم تظهر في البنك»
    // تحمل ما لا وجودَ له فيبحث عنه المحاسبُ في الكشف.
    final outstandingScope = await _bankAccountScope(recon.bankAccountId);
    final outstandingJE = await customSelect(
      '''SELECT l.*, e.entry_date, e.description as entry_desc
         FROM journal_entry_lines l
         JOIN journal_entries e ON l.entry_id = e.id
         WHERE ${outstandingScope.clause}
         $_postedEntry
         AND e.entry_date BETWEEN ? AND ?
         AND l.id NOT IN (
           SELECT matched_journal_line_id FROM bank_statement_lines
           WHERE matched_journal_line_id IS NOT NULL
         )''',
      variables: [
        ...outstandingScope.vars,
        dateVar(recon.periodStart),
        dateVar(recon.periodEnd),
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
