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
    return (select(fiscalYears)
          ..where((f) => f.isCurrent.equals(true) & f.deletedAt.isNull())
          ..limit(1))
        .getSingleOrNull();
  }

  /// Watch visible fiscal years only; soft-disabled years are excluded.
  Stream<List<FiscalYearData>> watchFiscalYears() {
    return (select(fiscalYears)
          ..where((f) => f.deletedAt.isNull())
          ..orderBy([(f) => OrderingTerm.desc(f.startDate)]))
        .watch();
  }

  DateTime _fiscalDayStart(DateTime date) => DateTime(date.year, date.month, date.day);

  DateTime _fiscalDayEnd(DateTime date) =>
      DateTime(date.year, date.month, date.day, 23, 59, 59, 999);

  Future<FiscalYearData?> _findEnabledOverlap(
    DateTime startDate,
    DateTime endDate,
  ) {
    final startDay = _fiscalDayStart(startDate);
    final endDay = _fiscalDayStart(endDate);
    return (select(fiscalYears)
          ..where((f) =>
              f.deletedAt.isNull() &
              f.isClosed.equals(false) &
              f.startDate.isSmallerOrEqual(Variable(_fiscalDayEnd(endDay))) &
              f.endDate.isBiggerOrEqual(Variable(startDay)))
          ..orderBy([(f) => OrderingTerm.desc(f.isCurrent)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// Return a matching existing year for automatic setup/startup, else create it.
  Future<int> ensureFiscalYear({
    required String name,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    return transaction(() async {
      final overlap = await _findEnabledOverlap(startDate, endDate);
      if (overlap != null) return overlap.id;
      return _insertFiscalYear(name, startDate, endDate);
    });
  }

  /// Create a new fiscal year; manual overlapping creation is rejected.
  Future<int> createFiscalYear({
    required String name,
    required DateTime startDate,
    required DateTime endDate,
    String? globalId,
  }) async {
    return transaction(() async {
      final overlap = await _findEnabledOverlap(startDate, endDate);
      if (overlap != null) {
        throw Exception('لا يمكن إنشاء السنة المالية: تتداخل مع السنة المفعّلة "${overlap.name}"');
      }
      return _insertFiscalYear(name, startDate, endDate, globalId: globalId);
    });
  }

  Future<int> _insertFiscalYear(
    String name,
    DateTime startDate,
    DateTime endDate, {
    String? globalId,
  }) async {
    final fullDayEnd = _fiscalDayEnd(endDate);
    await (update(fiscalYears)..where((f) => f.deletedAt.isNull()))
        .write(const FiscalYearsCompanion(isCurrent: Value(false)));
    return into(fiscalYears).insert(FiscalYearsCompanion.insert(
      name: name,
      startDate: startDate,
      endDate: fullDayEnd,
      isCurrent: const Value(true),
      globalId: Value(globalId ?? UuidV7.deriveFiscalYearGlobalId(
        name: name, startDate: startDate, endDate: fullDayEnd,
      )),
    ));
  }

  /// Get a visible fiscal year covering any time on the specified date.
  Future<FiscalYearData?> getFiscalYearByDate(DateTime date) {
    final dayStart = _fiscalDayStart(date);
    final dayEnd = _fiscalDayEnd(date);
    return (select(fiscalYears)
          ..where((f) => f.deletedAt.isNull() &
              f.startDate.isSmallerOrEqual(Variable(dayEnd)) &
              f.endDate.isBiggerOrEqual(Variable(dayStart)))
          ..orderBy([(f) => OrderingTerm.desc(f.isCurrent)])
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
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
    final periodRow = await customSelect(
      '''SELECT 1 FROM accounting_periods
         WHERE start_date <= ? AND end_date >= ?
         AND is_closed = $boolTrue
         LIMIT 1''',
      variables: [Variable(dayEnd), Variable(dayStart)],
      readsFrom: {accountingPeriods},
    ).getSingleOrNull();
    return periodRow != null;
  }

  /// Close a fiscal year (إقفال السنة المالية)
  Future<void> closeFiscalYear(int yearId, int userId) async {
    if (!await userHasPermission(userId, FiscalPermissionCodes.fiscalYearClose)) {
      throw Exception('ليس لديك صلاحية إقفال السنة المالية');
    }
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

      // 1. Calculate P&L (Profit/Loss) through the final calendar day.
      final fiscalEndOfDay = DateTime(
        fy.endDate.year, fy.endDate.month, fy.endDate.day, 23, 59, 59, 999,
      );
      final pl = await getIncomeStatement(fy.startDate, fiscalEndOfDay);
      final netProfit = pl['netProfit'] as double;

      // 2. Create closing entry: Close Revenue & Expense accounts → Retained Earnings
      final allAccs = await select(accounts).get();
      final closingLines = <JournalLine>[];
      final retainedEarnings = await accountingDao.getAccountByPurpose('retained_earnings');

      if (retainedEarnings == null) {
        throw Exception('لا يمكن إقفال السنة المالية: حساب الأرباح المحتجزة غير مربوط');
      }

      for (var acc in allAccs) {
        if (acc.accountType == 'revenue' || acc.accountType == 'expense' || acc.accountType == 'contra_revenue') {
          // Calculate balance for this fiscal year
          final movement = await customSelect(
            "SELECT SUM(l.debit - l.credit) as net FROM journal_entry_lines l JOIN journal_entries e ON l.entry_id = e.id WHERE l.account_id = ? AND e.entry_date BETWEEN ? AND ? AND e.is_posted = $boolTrue AND e.is_deleted = ${sqlBool(false)} AND COALESCE(e.reference_type, '') <> 'fiscal_close'",
            variables: [
              Variable(acc.id),
              Variable(fy.startDate),
              Variable(fiscalEndOfDay),
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
      final closingUser = await (select(users)..where((u) => u.id.equals(userId)))
          .getSingleOrNull();
      await logActivity(
        userId: userId,
        userName: closingUser?.username ?? 'user:$userId',
        action: 'close',
        entityType: 'fiscal_year',
        entityId: yearId,
        description: 'إقفال السنة المالية ${fy.name}',
      );

      // 4. Auto-create next fiscal year + opening balances
      final nextStart = DateTime(fy.endDate.year, fy.endDate.month, fy.endDate.day + 1);
      final nextEnd = DateTime(nextStart.year, 12, 31, 23, 59, 59, 999);
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

      // 5. ── قيد الأرصدة الافتتاحية اتشال ────────────────────────────────────
      //
      // كان بيمدين/يدائن كل حساب ميزانية برصيده التراكمي كما في `fy.endDate`،
      // بتاريخ بداية السنة الجديدة. بس الأستاذ في النظام ده **مستمر ومش
      // بيتقفل**: `getBalanceSheet` (`accounting_reports_dao.dart:477`)
      // بتجمّع `entry_date <= ?` من بداية التاريخ، و`getTrialBalance` بتحسب
      // الافتتاحي = كل الحركة قبل `from`، ومفيش أي تقرير بيستثني
      // `reference_type = 'opening_balance'`.
      //
      // فالقيد كان **بيتضاف فوق** الأرصدة الموجودة أصلاً: نقدية حقيقية ١٢٠٠
      // بتبقى ٢٤٠٠ ورأس مال ١٠٠٠ بيبقى ٢٠٠٠. والميزانية بتفضل «متوازنة» لأن
      // الطرفين اتضاعفوا مع بعض — عشان كده `isBalanced` عمره ما مسك ده.
      //
      // البديل (الاحتفاظ بالقيد واستثناؤه من كل تجميعة تراكمية) بيتطلب تعديل
      // `getBalanceSheet` و`getTrialBalance` و`getIncomeStatement` وأي تقرير
      // جاي — وأول واحد يتنسي بيرجّع الباج. في أستاذ مستمر الأرصدة بتترحّل
      // تلقائياً، فالقيد نفسه هو الزيادة.
      //
      // قيد إقفال النتيجة (خطوة ٣) **ما اتلمسش** — هو الجزء الصح: بيقفل
      // الإيرادات والمصروفات في الأرباح المبقاة.
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
    if (!await userHasPermission(userId, FiscalPermissionCodes.fiscalPeriodClose)) {
      throw Exception('ليس لديك صلاحية إقفال الفترة المحاسبية');
    }
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
      final closingUser = await (select(users)..where((u) => u.id.equals(userId)))
          .getSingleOrNull();
      await logActivity(
        userId: userId,
        userName: closingUser?.username ?? 'user:$userId',
        action: 'close',
        entityType: 'accounting_period',
        entityId: periodId,
        description: 'إقفال الفترة المحاسبية ${period.name}',
      );
    });
  }

  /// Re-open an accounting period
  Future<void> reopenAccountingPeriod(int periodId, int userId) async {
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
      final reopeningUser = await (select(users)..where((u) => u.id.equals(userId)))
          .getSingleOrNull();
      await logActivity(
        userId: userId,
        userName: reopeningUser?.username ?? 'user:$userId',
        action: 'reopen',
        entityType: 'accounting_period',
        entityId: periodId,
        description: 'إعادة فتح الفترة المحاسبية ${period.name}',
      );
    });
  }

  /// Auto-generate 12 monthly periods for a fiscal year
  Future<void> generatePeriodsForYear(int fiscalYearId, DateTime startDate, DateTime endDate) async {
    final monthNames = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];

    final fullDayEnd = DateTime(
      endDate.year, endDate.month, endDate.day, 23, 59, 59, 999,
    );
    DateTime current = DateTime(startDate.year, startDate.month, 1);
    while (current.isBefore(fullDayEnd) || current.month == fullDayEnd.month && current.year == fullDayEnd.year) {
      final monthEnd = DateTime(current.year, current.month + 1, 0, 23, 59, 59, 999);
      final periodEnd = monthEnd.isAfter(fullDayEnd) ? fullDayEnd : monthEnd;

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
        // Bare `ON CONFLICT DO NOTHING` rather than `mode: insertOrIgnore`:
        // drift drops that mode on postgres, so the `{month, year}` unique key
        // would raise 23505. This runs under the atomic PG seeder, which is
        // explicitly documented as having no try/catch so it can roll back —
        // meaning one 23505 here discards the entire seed.
        onConflict: DoNothing(target: []),
      );

      current = DateTime(current.year, current.month + 1, 1);
    }
  }

  /// Get fiscal year summary (total revenue, expenses, net profit)
  Future<Map<String, double>> getYearSummary(int fiscalYearId) async {
    final fy = await (select(fiscalYears)..where((f) => f.id.equals(fiscalYearId))).getSingle();

    final boolTrue = sqlBool(true);
    final fiscalEndOfDay = DateTime(
      fy.endDate.year, fy.endDate.month, fy.endDate.day, 23, 59, 59, 999,
    );
    final revenueResult = await customSelect(
      '''SELECT COALESCE(SUM(l.credit - l.debit), 0) as total 
         FROM journal_entry_lines l 
         JOIN journal_entries e ON l.entry_id = e.id 
         JOIN accounts a ON l.account_id = a.id 
         WHERE a.account_type = 'revenue' AND e.entry_date BETWEEN ? AND ? AND e.is_posted = $boolTrue''',
      variables: [Variable(fy.startDate), Variable(fiscalEndOfDay)],
      readsFrom: {journalEntryLines, journalEntries, accounts},
    ).getSingle();

    final expenseResult = await customSelect(
      '''SELECT COALESCE(SUM(l.debit - l.credit), 0) as total 
         FROM journal_entry_lines l 
         JOIN journal_entries e ON l.entry_id = e.id 
         JOIN accounts a ON l.account_id = a.id 
         WHERE a.account_type = 'expense' AND e.entry_date BETWEEN ? AND ? AND e.is_posted = $boolTrue''',
      variables: [Variable(fy.startDate), Variable(fiscalEndOfDay)],
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
    return (select(fiscalYears)
          ..where((f) => f.deletedAt.isNull())
          ..orderBy([(f) => OrderingTerm.desc(f.startDate)]))
        .get();
  }

  Future<double> _sumPriorUnclosedFiscalProfit(
    DateTime currentStart, {
    int? costCenterId,
    int? branchId,
    List<int>? branchIds,
    Set<int>? allowedBranchIds,
  }) async {
    double total = 0;
    final years = await getFiscalYears();
    String rangeKey(FiscalYearData year) =>
        '${year.startDate.year}-${year.startDate.month}-${year.startDate.day}:'
        '${year.endDate.year}-${year.endDate.month}-${year.endDate.day}';
    final closedRanges = years.where((year) => year.isClosed).map(rangeKey).toSet();
    for (final year in years) {
      if (year.isClosed || closedRanges.contains(rangeKey(year)) ||
          !year.startDate.isBefore(currentStart)) continue;
      final end = DateTime(year.endDate.year, year.endDate.month,
          year.endDate.day, 23, 59, 59, 999);
      final result = await getIncomeStatement(year.startDate, end,
          costCenterId: costCenterId, branchId: branchId, branchIds: branchIds,
          allowedBranchIds: allowedBranchIds);
      total += result['netProfit'] as double;
    }
    return total;
  }
}
