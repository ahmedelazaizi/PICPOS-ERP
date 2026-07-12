part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// MULTI-CURRENCY DAO — العملات المتعددة وأسعار الصرف
// ═══════════════════════════════════════════════════════════════════════════

extension MultiCurrencyDao on AppDatabase {

  /// Get active currencies
  Future<List<Currency>> getActiveCurrencies() {
    return (select(currencies)..where((c) => c.isActive.equals(true))).get();
  }

  /// Get default (base) currency
  Future<Currency?> getBaseCurrency() {
    return (select(currencies)..where((c) => c.isDefault.equals(true)))
        .getSingleOrNull();
  }

  /// Get exchange rate for a currency on a given date
  Future<double> getExchangeRate(int currencyId, {DateTime? date}) async {
    final d = date ?? DateTime.now();
    // Get the most recent rate on or before the given date
    final result = await customSelect(
      '''SELECT rate FROM exchange_rate_history
         WHERE currency_id = ? AND effective_date <= ?
         ORDER BY effective_date DESC LIMIT 1''',
      variables: [Variable(currencyId), Variable(d)],
    ).getSingleOrNull();

    if (result != null) {
      return (result.data['rate'] as num?)?.toDouble() ?? 1.0;
    }

    // Fallback to currency table rate
    final currency = await (select(currencies)
          ..where((c) => c.id.equals(currencyId)))
        .getSingleOrNull();
    return currency?.exchangeRate ?? 1.0;
  }

  /// Record a new exchange rate
  Future<int> recordExchangeRate({
    required int currencyId,
    required double rate,
    DateTime? effectiveDate,
  }) async {
    // Update the currency table current rate
    await (update(currencies)..where((c) => c.id.equals(currencyId))).write(
      CurrenciesCompanion(exchangeRate: Value(rate)),
    );
    // Insert history record
    return into(exchangeRateHistory).insert(
      ExchangeRateHistoryCompanion.insert(
        currencyId: currencyId,
        rate: rate,
        effectiveDate: effectiveDate ?? DateTime.now(),
      ),
    );
  }

  /// Convert amount from one currency to base currency
  Future<double> convertToBase(double amount, int fromCurrencyId, {DateTime? date}) async {
    final rate = await getExchangeRate(fromCurrencyId, date: date);
    return amount * rate;
  }

  /// Convert amount from base currency to another
  Future<double> convertFromBase(double amount, int toCurrencyId, {DateTime? date}) async {
    final rate = await getExchangeRate(toCurrencyId, date: date);
    return rate > 0 ? amount / rate : amount;
  }

  /// FX Revaluation: calculate unrealized gains/losses at period end
  /// IAS 21: Monetary items must be retranslated at closing rate
  Future<Map<String, double>> calculateFxRevaluation({
    required int currencyId,
    required DateTime periodEnd,
  }) async {
    final currentRate = await getExchangeRate(currencyId, date: periodEnd);

    // Get all journal lines in this currency
    final result = await customSelect(
      '''SELECT
          COALESCE(SUM(CASE WHEN debit > 0 THEN debit ELSE 0 END), 0) as total_debit,
          COALESCE(SUM(CASE WHEN credit > 0 THEN credit ELSE 0 END), 0) as total_credit
         FROM journal_entry_lines l
         JOIN journal_entries e ON l.entry_id = e.id
         WHERE e.currency_id = ? AND e.entry_date <= ?''',
      variables: [Variable(currencyId), Variable(periodEnd)],
    ).getSingle();

    final totalDebit = (result.data['total_debit'] as num?)?.toDouble() ?? 0;
    final totalCredit = (result.data['total_credit'] as num?)?.toDouble() ?? 0;
    final netForeign = totalDebit - totalCredit;
    final revaluedBase = netForeign * currentRate;

    return {
      'netForeignBalance': netForeign,
      'currentRate': currentRate,
      'revaluedBaseAmount': revaluedBase,
    };
  }

  /// Seed default currencies (called in migration)
  Future<void> seedDefaultCurrencies() async {
    final count =
        await (selectOnly(currencies)..addColumns([currencies.id.count()]))
            .map((row) => row.read(currencies.id.count()))
            .getSingle();

    if ((count ?? 0) > 0) return;

    // Seed Jordanian Dinar (JOD) as primary
    await into(currencies).insert(
      CurrenciesCompanion.insert(
        code: 'JOD',
        name: 'دينار أردني',
        symbol: 'د.أ',
        isDefault: const Value(true),
        exchangeRate: const Value(1.0),
        // UUID-First Phase 1 Slice 3: seeded currencies need stable UUID
        // so every install reconciles to the same base currency row.
        globalId: Value(UuidV7.generate()),
      ),
    );

    // Seed Egyptian Pound (EGP) as inactive
    await into(currencies).insert(
      CurrenciesCompanion.insert(
        code: 'EGP',
        name: 'جنيه مصري',
        symbol: 'ج.م',
        isDefault: const Value(false),
        isActive: const Value(false),
        exchangeRate: const Value(0.02), // Relative to JOD
        globalId: Value(UuidV7.generate()),
      ),
    );
  }
}
