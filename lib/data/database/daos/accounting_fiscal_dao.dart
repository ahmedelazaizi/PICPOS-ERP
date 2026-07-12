// =======================================================================
// ACCOUNTING FISCAL YEAR DAO
// Extracted from accounting_dao.dart — PIR Phase 2 God File Splitting
// =======================================================================

part of '../database.dart';

/// Extension for Fiscal Year lifecycle management
extension AccountingFiscalDao on AppDatabase {

  // -----------------------------------------------------------------------
  // FISCAL YEAR MANAGEMENT (السنوات المالية)
  // -----------------------------------------------------------------------

  /// Get the current (active) fiscal year
  Future<FiscalYearData?> getCurrentFiscalYear() async {
    return (select(
      fiscalYears,
    )..where((f) => f.isCurrent.equals(true))
     ..limit(1)).getSingleOrNull();
  }

  /// Watch all fiscal years
  Stream<List<FiscalYearData>> watchFiscalYears() {
    return (select(
      fiscalYears,
    )..orderBy([(f) => OrderingTerm.desc(f.startDate)])).watch();
  }

  /// Create a new fiscal year
  Future<int> createFiscalYear({
    required String name,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    return transaction(() async {
      // Deactivate all other fiscal years
      await (update(
        fiscalYears,
      )).write(const FiscalYearsCompanion(isCurrent: Value(false)));

      return into(fiscalYears).insert(
        FiscalYearsCompanion.insert(
          name: name,
          startDate: startDate,
          endDate: endDate,
          isCurrent: const Value(true),
          // Spec 136 ISS-2 — deterministic gid from the natural key so the
          // server and client converge on the sync Tier-1 globalId match
          // (was UuidV7.generate(), which diverged per install → NULL/name
          // fallback in the field).
          globalId: Value(UuidV7.deriveFiscalYearGlobalId(
              name: name, startDate: startDate, endDate: endDate)),
        ),
      );
    });
  }

  /// Get fiscal year covering a specific date
  Future<FiscalYearData?> getFiscalYearByDate(DateTime date) {
    return (select(fiscalYears)
          ..where(
            (f) =>
                f.startDate.isSmallerOrEqual(Variable(date)) &
                f.endDate.isBiggerOrEqual(Variable(date)),
          )
          ..limit(1))
        .getSingleOrNull();
  }

  /// Feature 014 / Issue 1 — true if `date` falls inside a CLOSED
  /// fiscal year OR a CLOSED monthly accounting period. Callers (purchase
  /// returns, sales returns, manual JE editing) gate destructive actions
  /// on this so once the operator presses "إقفال" no past data can be
  /// silently rewritten.
  Future<bool> isDateInClosedPeriod(DateTime date) async {
    final fy = await getFiscalYearByDate(date);
    if (fy != null && fy.isClosed) return true;
    final boolTrue = sqlBool(true);
    final periodRow = await customSelect(
      '''SELECT 1 FROM accounting_periods
         WHERE start_date <= ? AND end_date >= ?
         AND is_closed = $boolTrue
         LIMIT 1''',
      variables: [Variable(date), Variable(date)],
      readsFrom: {accountingPeriods},
    ).getSingleOrNull();
    return periodRow != null;
  }

  /// Close a fiscal year (إقفال السنة المالية)
  Future<void> closeFiscalYear(int yearId, int userId) async {
    await transaction(() async {
      final fy = await (select(
        fiscalYears,
      )..where((f) => f.id.equals(yearId))).getSingle();

      // Common SQL boolean values
      final boolFalse = sqlBool(false);
      final boolTrue = sqlBool(true);

      // P-03: SECURITY — Verify all monthly periods are closed before year-end
      final openPeriods = await customSelect(
        '''SELECT name FROM accounting_periods
           WHERE year BETWEEN ? AND ?
           AND is_closed = $boolFalse''',
        variables: [
          Variable(fy.startDate.year),
          Variable(fy.endDate.year),
        ],
      ).get();
      if (openPeriods.isNotEmpty) {
        final openNames = openPeriods.map((p) => p.data['name']).join(', ');
        throw Exception(
          'لا يمكن إقفال السنة المالية — فترات شهرية مفتوحة: $openNames',
        );
      }

      // H-05: Stock reconciliation check — verify global vs warehouse stock consistency
      final stockDiscrepancies = await customSelect(
        '''SELECT p.id, p.name, p.current_stock as global_stock,
                  COALESCE(SUM(ib.quantity), 0) as warehouse_stock
           FROM products p
           LEFT JOIN inventory_balances ib ON ib.product_id = p.id
           WHERE p.current_stock > 0 OR ib.quantity > 0
           GROUP BY p.id
           HAVING ABS(p.current_stock - COALESCE(SUM(ib.quantity), 0)) > 0.01''',
        variables: [],
        readsFrom: {products, inventoryBalances},
      ).get();
      if (stockDiscrepancies.isNotEmpty) {
        final discList = stockDiscrepancies
            .take(5)
            .map((d) => '${d.data['name']}: إجمالي=${(d.data['global_stock'] as num).toStringAsFixed(2)}, مخازن=${(d.data['warehouse_stock'] as num).toStringAsFixed(2)}')
            .join('\n');
        throw Exception(
          'يوجد فروقات في أرصدة المخزون (${stockDiscrepancies.length} صنف). '
          'يرجى إجراء جرد ومطابقة قبل الإقفال:\n$discList',
        );
      }

      // 1. Calculate P&L (Profit/Loss) for this fiscal year
      final pl = await getIncomeStatement(fy.startDate, fy.endDate);
      final netProfit = pl['netProfit'] as double;

      // 2. Create closing entry: Close Revenue & Expense accounts → Retained Earnings
      final allAccs = await select(accounts).get();
      final closingLines = <JournalLine>[];
      final retainedEarnings = await accountingDao.getAccountByPurpose('retained_earnings');

      if (retainedEarnings == null) return;

      for (var acc in allAccs) {
        if (acc.accountType == 'revenue' || acc.accountType == 'expense' || acc.accountType == 'contra_revenue') {
          // Calculate balance for this fiscal year
          final movement = await customSelect(
            'SELECT SUM(debit - credit) as net FROM journal_entry_lines l JOIN journal_entries e ON l.entry_id = e.id WHERE l.account_id = ? AND e.entry_date BETWEEN ? AND ? AND e.is_posted = $boolTrue',
            variables: [
              Variable(acc.id),
              Variable(fy.startDate),
              Variable(fy.endDate),
            ],
            readsFrom: {journalEntryLines, journalEntries},
          ).getSingle();

          final net = movement.data['net'] as double? ?? 0;
          if (net.abs() > 0.001) {
            // Reverse the account balance
            if (net > 0) {
              closingLines.add(
                JournalLine(
                  accountId: acc.id,
                  credit: net,
                  description: 'إقفال ${acc.name}',
                ),
              );
            } else {
              closingLines.add(
                JournalLine(
                  accountId: acc.id,
                  debit: net.abs(),
                  description: 'إقفال ${acc.name}',
                ),
              );
            }
          }
        }
      }

      // Balance to Retained Earnings
      if (netProfit > 0) {
        closingLines.add(
          JournalLine(
            accountId: retainedEarnings.id,
            credit: netProfit,
            description: 'صافي ربح الفترة',
          ),
        );
      } else if (netProfit < 0) {
        closingLines.add(
          JournalLine(
            accountId: retainedEarnings.id,
            debit: netProfit.abs(),
            description: 'صافي خسارة الفترة',
          ),
        );
      }

      if (closingLines.isNotEmpty) {
        await accountingDao.createJournalEntry(
          description: 'قيد إقفال السنة المالية ${fy.name}',
          date: fy.endDate,
          lines: closingLines,
          referenceType: 'fiscal_close',
          referenceId: yearId,
          isAutoPosted: true,
        );
      }

      // 3. Mark fiscal year as closed
      await (update(fiscalYears)..where((f) => f.id.equals(yearId))).write(
        FiscalYearsCompanion(
          isClosed: const Value(true),
          closedAt: Value(DateTime.now()),
          closedBy: Value(userId),
          isCurrent: const Value(false),
        ),
      );

      // 4. Auto-create next fiscal year + opening balances
      final nextStart = fy.endDate.add(const Duration(days: 1));
      final nextEnd = DateTime(nextStart.year, 12, 31);
      // Spec 136 review P1-1 — use the CANONICAL seeder name
      // ("السنة المالية YYYY"), not a bare "YYYY". Otherwise the next FY
      // created by closing a year on the server derives a different
      // deterministic gid (and a different Tier-2 name key) than the same
      // logical year auto-seeded on a fresh client → divergence + a possible
      // duplicate FY row. Aligning the name converges both creation paths.
      final nextName = 'السنة المالية ${nextStart.year}';

      // Check if next year already exists
      final existing = await (select(fiscalYears)
            ..where((f) => f.startDate.isSmallerOrEqualValue(nextStart)
                & f.endDate.isBiggerOrEqualValue(nextStart)))
          .getSingleOrNull();

      int nextYearId;
      if (existing != null) {
        nextYearId = existing.id;
      } else {
        nextYearId = await into(fiscalYears).insert(FiscalYearsCompanion(
          name: Value(nextName),
          startDate: Value(nextStart),
          endDate: Value(nextEnd),
          isCurrent: const Value(true),
          isClosed: const Value(false),
          // Spec 136 ISS-2 — deterministic gid (was unset → NULL).
          globalId: Value(UuidV7.deriveFiscalYearGlobalId(
              name: nextName, startDate: nextStart, endDate: nextEnd)),
        ));
        // Generate monthly periods
        await generatePeriodsForYear(nextYearId, nextStart, nextEnd);
      }

      // 5. Create opening balance journal entry for BS accounts
      // C-05: Include contra_asset (e.g., Accumulated Depreciation) in opening balances
      final bsAccounts = allAccs.where((a) =>
          a.accountType == 'asset' ||
          a.accountType == 'contra_asset' ||
          a.accountType == 'liability' ||
          a.accountType == 'equity');

      final openingLines = <JournalLine>[];
      for (var acc in bsAccounts) {
        final balResult = await customSelect(
          'SELECT SUM(debit) - SUM(credit) as net FROM journal_entry_lines l JOIN journal_entries e ON l.entry_id = e.id WHERE l.account_id = ? AND e.entry_date <= ? AND e.is_posted = $boolTrue',
          variables: [Variable(acc.id), Variable(fy.endDate)],
          readsFrom: {journalEntryLines, journalEntries},
        ).getSingle();
        final net = balResult.data['net'] as double? ?? 0;
        if (net.abs() > 0.001) {
          if (net > 0) {
            openingLines.add(JournalLine(
              accountId: acc.id,
              debit: net,
              description: 'رصيد افتتاحي — ${acc.name}',
            ));
          } else {
            openingLines.add(JournalLine(
              accountId: acc.id,
              credit: net.abs(),
              description: 'رصيد افتتاحي — ${acc.name}',
            ));
          }
        }
      }

      if (openingLines.isNotEmpty) {
        // F-07: Absorb floating-point rounding difference
        double obDebit = openingLines.fold(0.0, (s, l) => s + l.debit);
        double obCredit = openingLines.fold(0.0, (s, l) => s + l.credit);
        final roundingDiff = obDebit - obCredit;
        if (roundingDiff.abs() > 0.001) {
          final retainedEarnings = await accountingDao.getAccountByPurpose('retained_earnings');
          if (retainedEarnings != null) {
            if (roundingDiff > 0) {
              openingLines.add(JournalLine(
                accountId: retainedEarnings.id,
                credit: roundingDiff,
                description: 'فرق تقريب أرصدة افتتاحية',
              ));
            } else {
              openingLines.add(JournalLine(
                accountId: retainedEarnings.id,
                debit: roundingDiff.abs(),
                description: 'فرق تقريب أرصدة افتتاحية',
              ));
            }
          }
        }

        await accountingDao.createJournalEntry(
          description: 'قيد الأرصدة الافتتاحية — $nextName',
          date: nextStart,
          lines: openingLines,
          referenceType: 'opening_balance',
          referenceId: nextYearId,
          isAutoPosted: true,
        );
      }
    });
  }

  /// Watch accounting periods for a fiscal year
  Stream<List<AccountingPeriodData>> watchAccountingPeriods(int fiscalYearId) {
    return (select(accountingPeriods)
          ..where((p) => p.fiscalYearId.equals(fiscalYearId))
          ..orderBy([(p) => OrderingTerm.asc(p.month)]))
        .watch();
  }

  /// Close an accounting period (lock month)
  Future<void> closeAccountingPeriod(int periodId, int userId) async {
    await transaction(() async {
      final period = await (select(accountingPeriods)..where((p) => p.id.equals(periodId))).getSingle();
      final year = await (select(fiscalYears)..where((f) => f.id.equals(period.fiscalYearId))).getSingle();

      if (year.isClosed) {
        throw Exception('لا يمكن إقفال فترة في سنة مالية مقفلة بالفعل');
      }

      await (update(accountingPeriods)..where((p) => p.id.equals(periodId)))
          .write(AccountingPeriodsCompanion(
        isClosed: const Value(true),
        closedAt: Value(DateTime.now()),
        closedBy: Value(userId),
      ));
    });
  }

  /// Re-open an accounting period
  Future<void> reopenAccountingPeriod(int periodId) async {
    await transaction(() async {
      final period = await (select(accountingPeriods)..where((p) => p.id.equals(periodId))).getSingle();
      final year = await (select(fiscalYears)..where((f) => f.id.equals(period.fiscalYearId))).getSingle();

      if (year.isClosed) {
        throw Exception('لا يمكن إعادة فتح فترة في سنة مالية مقفلة. يرجى إعادة فتح السنة المالية أولاً.');
      }

      await (update(accountingPeriods)..where((p) => p.id.equals(periodId)))
          .write(const AccountingPeriodsCompanion(
        isClosed: Value(false),
        closedAt: Value.absent(),
        closedBy: Value.absent(),
      ));
    });
  }

  /// Auto-generate 12 monthly periods for a fiscal year
  Future<void> generatePeriodsForYear(int fiscalYearId, DateTime startDate, DateTime endDate) async {
    final monthNames = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];

    DateTime current = DateTime(startDate.year, startDate.month, 1);
    while (current.isBefore(endDate) || current.month == endDate.month && current.year == endDate.year) {
      final monthEnd = DateTime(current.year, current.month + 1, 0, 23, 59, 59);
      final periodEnd = monthEnd.isAfter(endDate) ? endDate : monthEnd;

      // FIX 2026-04-28: Use insertOrIgnore so re-running setup wizard on an
      // existing database doesn't fail with `accounting_periods_month_year_key`
      // unique constraint violation. Existing periods are kept untouched.
      await into(accountingPeriods).insert(
        AccountingPeriodsCompanion.insert(
          fiscalYearId: fiscalYearId,
          name: '${monthNames[current.month - 1]} ${current.year}',
          month: current.month,
          year: current.year,
          startDate: DateTime(current.year, current.month, 1),
          endDate: periodEnd,
          // UUID-First (Phase 1): stable cross-install identity for sync.
          globalId: Value(UuidV7.generate()),
        ),
        mode: InsertMode.insertOrIgnore,
      );

      current = DateTime(current.year, current.month + 1, 1);
    }
  }

  /// Get fiscal year summary (total revenue, expenses, net profit)
  Future<Map<String, double>> getYearSummary(int fiscalYearId) async {
    final fy = await (select(fiscalYears)..where((f) => f.id.equals(fiscalYearId))).getSingle();

    final boolTrue = sqlBool(true);
    final revenueResult = await customSelect(
      '''SELECT COALESCE(SUM(l.credit - l.debit), 0) as total 
         FROM journal_entry_lines l 
         JOIN journal_entries e ON l.entry_id = e.id 
         JOIN accounts a ON l.account_id = a.id 
         WHERE a.account_type = 'revenue' AND e.entry_date BETWEEN ? AND ? AND e.is_posted = $boolTrue''',
      variables: [Variable(fy.startDate), Variable(fy.endDate)],
      readsFrom: {journalEntryLines, journalEntries, accounts},
    ).getSingle();

    final expenseResult = await customSelect(
      '''SELECT COALESCE(SUM(l.debit - l.credit), 0) as total 
         FROM journal_entry_lines l 
         JOIN journal_entries e ON l.entry_id = e.id 
         JOIN accounts a ON l.account_id = a.id 
         WHERE a.account_type = 'expense' AND e.entry_date BETWEEN ? AND ? AND e.is_posted = $boolTrue''',
      variables: [Variable(fy.startDate), Variable(fy.endDate)],
      readsFrom: {journalEntryLines, journalEntries, accounts},
    ).getSingle();

    final revenue = revenueResult.data['total'] as double? ?? 0;
    final expenses = expenseResult.data['total'] as double? ?? 0;

    return {
      'revenue': revenue,
      'expenses': expenses,
      'netProfit': revenue - expenses,
    };
  }

  /// Get all fiscal years
  Future<List<FiscalYearData>> getFiscalYears() {
    return (select(fiscalYears)..orderBy([(f) => OrderingTerm.desc(f.startDate)])).get();
  }
}
