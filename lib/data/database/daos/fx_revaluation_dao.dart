part of '../database.dart';

/// Result returned by the period-end foreign-currency revaluation operation.
class FxRevaluationPreview {
  final String periodKey;
  final double totalAdjustment;
  final int invoiceCount;
  final bool alreadyPosted;

  const FxRevaluationPreview({
    required this.periodKey,
    required this.totalAdjustment,
    required this.invoiceCount,
    required this.alreadyPosted,
  });
}

class FxRevaluationResult {
  final String periodKey;
  final double totalAdjustment;
  final int journalEntryId;
  final int reversalJournalEntryId;

  const FxRevaluationResult({
    required this.periodKey,
    required this.totalAdjustment,
    required this.journalEntryId,
    required this.reversalJournalEntryId,
  });
}

extension FxRevaluationDao on AppDatabase {
  static const _fxAccountCode = '6313';

  Future<Account?> _fxAccount() => accountingDao.getAccountByCode(_fxAccountCode);

  Future<Account?> _fxPartyAccount({
    required int partyId,
    required bool sales,
  }) async {
    final party = await (select(parties)..where((p) => p.id.equals(partyId)))
        .getSingleOrNull();
    if (party?.accountId != null) {
      final linked = await accountingDao.getAccountById(party!.accountId!);
      if (linked != null && linked.accountNature == 'detail') return linked;
    }
    final purpose = sales ? 'foreign_receivables' : 'foreign_payables';
    final fallback = await accountingDao.getAccountByCode(
      AccountingDao.accountPurposes[purpose]!,
    );
    if (fallback != null && fallback.accountNature == 'detail') return fallback;
    return accountingDao.getAccountByCode(
      AccountingDao.accountPurposes[sales ? 'receivables' : 'payables']!,
    );
  }

  Future<void> _postRealizedFxDifference({
    required String invoiceType,
    required int invoiceId,
    required String transactionId,
    required double foreignAmount,
    required double bookingRate,
    required double settlementRate,
    required int? partyId,
    required DateTime entryDate,
  }) async {
    if (partyId == null || foreignAmount <= 0 || bookingRate <= 0 || settlementRate <= 0) {
      return;
    }
    final difference = FinancialUtils.round(
      foreignAmount * (settlementRate - bookingRate),
    );
    if (difference.abs() < FinancialUtils.balanceTolerance) return;

    final partyAccount = await _fxPartyAccount(
      partyId: partyId,
      sales: invoiceType == 'sales',
    );
    final fxAccount = await _fxAccount();
    if (partyAccount == null || fxAccount == null) {
      throw StateError(
        'تعذّر ترحيل فرق الصرف: تأكّد من حساب الطرف وحساب فروق العملة 6313.',
      );
    }

    final sales = invoiceType == 'sales';
    final partyDebit = sales ? difference > 0 : difference < 0;
    final amount = difference.abs();
    final globalId = 'fx-realized:$invoiceType:$transactionId';
    await accountingDao.createJournalEntry(
      description: 'فرق صرف محقق — ${sales ? 'تحصيل مبيعات' : 'سداد مشتريات'} #$invoiceId',
      date: entryDate,
      lines: [
        JournalLine(
          accountId: partyAccount.id,
          debit: partyDebit ? amount : 0,
          credit: partyDebit ? 0 : amount,
          description: 'تصحيح ذمة الطرف بسعر التسوية',
        ),
        JournalLine(
          accountId: fxAccount.id,
          debit: partyDebit ? 0 : amount,
          credit: partyDebit ? amount : 0,
          description: 'فروق صرف محققة',
        ),
      ],
      referenceType: 'fx_realized_settlement',
      // Sales and purchase invoice IDs each start at 1; keep the side in the key.
      referenceId: invoiceType == 'sales' ? invoiceId : -invoiceId,
      isAutoPosted: true,
      allowRepost: true,
      globalId: globalId,
    );
  }

  Future<FxRevaluationPreview> previewOpenForeignBalances({
    required DateTime asOf,
    required Map<int, double> rates,
    required int userId,
  }) async {
    await PermissionEnforcer(userHasPermission).requireCriticalOp(
      userId: userId,
      code: PermissionCodes.accountingJournal,
      arabicReason: 'لا تملك صلاحية معاينة إعادة تقييم أرصدة العملات الأجنبية',
    );
    final monthEnd = DateTime(asOf.year, asOf.month + 1, 0);
    final periodKey = '${monthEnd.year}-${monthEnd.month.toString().padLeft(2, '0')}';
    final baseGlobalId = 'fx-revaluation:$periodKey';
    final base = await (select(journalEntries)
          ..where((e) => e.globalId.equals(baseGlobalId))
          ..limit(1))
        .getSingleOrNull();
    final reversal = await (select(journalEntries)
          ..where((e) => e.globalId.equals('$baseGlobalId-reversal'))
          ..limit(1))
        .getSingleOrNull();
    var total = 0.0;
    var count = 0;
    final sales = await (select(salesInvoices)
          ..where((i) => i.invoiceDate.isSmallerOrEqualValue(monthEnd)))
        .get();
    for (final invoice in sales) {
      final rate = invoice.currencyId == null ? null : rates[invoice.currencyId];
      final booking = invoice.exchangeRate;
      final outstanding = invoice.total - invoice.paid;
      if (invoice.isDeleted || invoice.saleType == 'return' ||
          invoice.currencyId == null || booking == null || booking <= 0 ||
          rate == null || rate <= 0 || outstanding <= 0 ||
          invoice.customerId == null) continue;
      final difference = FinancialUtils.round(
        outstanding / booking * (rate - booking),
      );
      if (difference.abs() < FinancialUtils.balanceTolerance) continue;
      total += difference;
      count++;
    }
    final purchases = await (select(purchaseInvoices)
          ..where((i) => i.invoiceDate.isSmallerOrEqualValue(monthEnd)))
        .get();
    for (final invoice in purchases) {
      final rate = invoice.currencyId == null ? null : rates[invoice.currencyId];
      final booking = invoice.exchangeRate;
      final outstanding = invoice.total - invoice.paid;
      if (invoice.isDeleted || invoice.currencyId == null || booking == null ||
          booking <= 0 || rate == null || rate <= 0 || outstanding <= 0) continue;
      final difference = FinancialUtils.round(
        outstanding / booking * (rate - booking),
      );
      if (difference.abs() < FinancialUtils.balanceTolerance) continue;
      total += difference;
      count++;
    }
    return FxRevaluationPreview(
      periodKey: periodKey,
      totalAdjustment: total,
      invoiceCount: count,
      alreadyPosted: base != null && reversal != null,
    );
  }

  /// Revalue all open foreign-currency receivables and payables at [asOf].
  /// The operation is idempotent per calendar month and creates a next-period
  /// reversal with the same deterministic identity on every retry.
  Future<FxRevaluationResult> revalueOpenForeignBalances({
    required DateTime asOf,
    required Map<int, double> rates,
    required int userId,
  }) async {
    await PermissionEnforcer(userHasPermission).requireCriticalOp(
      userId: userId,
      code: PermissionCodes.accountingJournal,
      arabicReason: 'لا تملك صلاحية إعادة تقييم أرصدة العملات الأجنبية',
    );

    final monthEnd = DateTime(asOf.year, asOf.month + 1, 0);
    final periodKey = '${monthEnd.year}-${monthEnd.month.toString().padLeft(2, '0')}';
    final baseGlobalId = 'fx-revaluation:$periodKey';
    final existing = await (select(journalEntries)
          ..where((e) => e.globalId.equals(baseGlobalId))
          ..limit(1))
        .getSingleOrNull();
    final existingReversal = await (select(journalEntries)
          ..where((e) => e.globalId.equals('$baseGlobalId-reversal'))
          ..limit(1))
        .getSingleOrNull();
    if (existing != null && existingReversal != null) {
      final lines = await (select(journalEntryLines)
            ..where((l) => l.entryId.equals(existing.id)))
          .get();
      return FxRevaluationResult(
        periodKey: periodKey,
        totalAdjustment: lines.fold(0, (s, l) => s + l.debit),
        journalEntryId: existing.id,
        reversalJournalEntryId: existingReversal.id,
      );
    }

    // Retry after a half-done run (main committed by an older build, reversal
    // missing): mirror the STORED main lines, never today's recomputed ones.
    if (existing != null) {
      final stored = await (select(journalEntryLines)
            ..where((l) => l.entryId.equals(existing.id)))
          .get();
      final mirrored = [
        for (final l in stored)
          JournalLine(accountId: l.accountId, debit: l.debit, credit: l.credit),
      ];
      final reversalId = await _postFxReversal(
        lines: mirrored,
        monthEnd: monthEnd,
        periodKey: periodKey,
        baseGlobalId: baseGlobalId,
        userId: userId,
      );
      return FxRevaluationResult(
        periodKey: periodKey,
        totalAdjustment: stored.fold<double>(0, (s, l) => s + l.debit),
        journalEntryId: existing.id,
        reversalJournalEntryId: reversalId,
      );
    }

    final accountAdjustments = <int, double>{};
    var totalFx = 0.0;
    var fxDebit = 0.0;
    var fxCredit = 0.0;
    final sales = await (select(salesInvoices)
          ..where((i) => i.invoiceDate.isSmallerOrEqualValue(monthEnd)))
        .get();
    for (final invoice in sales) {
      if (invoice.isDeleted || invoice.saleType == 'return') continue;
      final currencyId = invoice.currencyId;
      final bookingRate = invoice.exchangeRate;
      final currentRate = currencyId == null ? null : rates[currencyId];
      final outstanding = invoice.total - invoice.paid;
      if (currencyId == null || bookingRate == null || bookingRate <= 0 ||
          currentRate == null || currentRate <= 0 || outstanding <= 0 ||
          invoice.customerId == null) continue;
      final difference = FinancialUtils.round(
        (outstanding / bookingRate) * (currentRate - bookingRate),
      );
      if (difference.abs() < FinancialUtils.balanceTolerance) continue;
      final account = await _fxPartyAccount(
        partyId: invoice.customerId!,
        sales: true,
      );
      if (account == null) continue;
      accountAdjustments[account.id] = (accountAdjustments[account.id] ?? 0) + difference;
      totalFx += difference;
      if (difference > 0) {
        fxCredit += difference;
      } else {
        fxDebit += difference.abs();
      }
    }

    final purchases = await (select(purchaseInvoices)
          ..where((i) => i.invoiceDate.isSmallerOrEqualValue(monthEnd)))
        .get();
    for (final invoice in purchases) {
      if (invoice.isDeleted) continue;
      final currencyId = invoice.currencyId;
      final bookingRate = invoice.exchangeRate;
      final currentRate = currencyId == null ? null : rates[currencyId];
      final outstanding = invoice.total - invoice.paid;
      if (currencyId == null || bookingRate == null || bookingRate <= 0 ||
          currentRate == null || currentRate <= 0 || outstanding <= 0) continue;
      final difference = FinancialUtils.round(
        (outstanding / bookingRate) * (currentRate - bookingRate),
      );
      if (difference.abs() < FinancialUtils.balanceTolerance) continue;
      final account = await _fxPartyAccount(
        partyId: invoice.supplierId,
        sales: false,
      );
      if (account == null) continue;
      // A payable increase is a loss: the party leg is credit-normal.
      accountAdjustments[account.id] = (accountAdjustments[account.id] ?? 0) - difference;
      totalFx += difference;
      if (difference > 0) {
        fxDebit += difference;
      } else {
        fxCredit += difference.abs();
      }
    }

    final fxAccount = await _fxAccount();
    if (fxAccount == null) {
      throw StateError('حساب فروق العملة 6313 غير موجود في دليل الحسابات.');
    }
    final lines = <JournalLine>[];
    for (final entry in accountAdjustments.entries) {
      final amount = entry.value;
      if (amount.abs() < FinancialUtils.balanceTolerance) continue;
      lines.add(JournalLine(
        accountId: entry.key,
        debit: amount > 0 ? amount : 0,
        credit: amount < 0 ? amount.abs() : 0,
        description: 'إعادة تقييم ذمة عملة أجنبية',
      ));
    }
    if (fxDebit >= FinancialUtils.balanceTolerance ||
        fxCredit >= FinancialUtils.balanceTolerance) {
      lines.add(JournalLine(
        accountId: fxAccount.id,
        debit: fxDebit,
        credit: fxCredit,
        description: 'فروق صرف غير محققة — $periodKey',
      ));
    }
    if (lines.isEmpty) {
      throw StateError('لا توجد أرصدة أجنبية مفتوحة لإعادة تقييمها في الفترة المحددة.');
    }

    // ACC-005: main entry + reversal commit together or not at all.
    return transaction(() async {
      final entryId = existing?.id ?? await accountingDao.createJournalEntry(
        description: 'إعادة تقييم أرصدة العملات الأجنبية — $periodKey',
        date: monthEnd,
        lines: lines,
        referenceType: 'fx_revaluation',
        referenceId: monthEnd.year * 100 + monthEnd.month,
        isAutoPosted: true,
        allowRepost: true,
        createdBy: userId,
        globalId: baseGlobalId,
      );
      final reversalId = await _postFxReversal(
        lines: lines,
        monthEnd: monthEnd,
        periodKey: periodKey,
        baseGlobalId: baseGlobalId,
        userId: userId,
      );
      return FxRevaluationResult(
        periodKey: periodKey,
        totalAdjustment: totalFx,
        journalEntryId: entryId,
        reversalJournalEntryId: reversalId,
      );
    });
  }

  Future<int> _postFxReversal({
    required List<JournalLine> lines,
    required DateTime monthEnd,
    required String periodKey,
    required String baseGlobalId,
    required int userId,
  }) {
    final reversalLines = lines
        .map((line) => JournalLine(
              accountId: line.accountId,
              debit: line.credit,
              credit: line.debit,
              description: 'عكس إعادة تقييم $periodKey',
            ))
        .toList();
    return accountingDao.createJournalEntry(
      description: 'عكس إعادة تقييم العملات الأجنبية — $periodKey',
      date: DateTime(monthEnd.year, monthEnd.month + 1, 1),
      lines: reversalLines,
      referenceType: 'fx_revaluation_reversal',
      referenceId: monthEnd.year * 100 + monthEnd.month,
      isAutoPosted: true,
      allowRepost: true,
      createdBy: userId,
      globalId: '$baseGlobalId-reversal',
    );
  }
}
