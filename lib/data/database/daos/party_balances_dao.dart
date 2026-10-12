// Party balances: atomic adjustPartyBalance, outstanding/total balances, summary, hard delete.
part of '../database.dart';

extension PartyBalancesDao on AppDatabase {
  /// Adjust party balance with atomic read-modify-write.
  /// Wrapped in transaction to prevent Lost Update race condition.
  /// PIR P1-02: Logs balance changes to field_audit_logs for financial audit trail.
  Future<void> adjustPartyBalance(
    int partyId,
    double amount, {
    int changedBy = 0,
    String changedByName = 'SYSTEM',
    String? changeReason,
  }) async {
    return transaction(() async {
      // Read old balance for audit trail
      final party = await (select(parties)
            ..where((p) => p.id.equals(partyId)))
          .getSingleOrNull();

      if (party != null) {
        final oldBalance = party.balance;
        final newBalance = oldBalance + amount;

        // CRITICAL: Atomic balance update using SQL-level arithmetic
        // to prevent Lost Update race condition between concurrent transactions.
        await customStatement(
          'UPDATE parties SET balance = balance + ? WHERE id = ?',
          [amount, partyId],
        );

        User? actor;
        if (changedBy > 0) {
          actor = await (select(users)
                ..where((u) => u.id.equals(changedBy))
                ..limit(1))
              .getSingleOrNull();
        }
        actor ??= await (select(users)
              ..where((u) => u.id.equals(1) | u.username.equals('admin'))
              ..limit(1))
            .getSingleOrNull();
        // field_audit_logs has a required FK. Passing 0 intentionally skips the
        // audit row when even the bootstrap actor is absent, instead of aborting
        // the balance adjustment with a foreign-key violation.
        final actorId = actor?.id ?? 0;
        await logFieldChange(
          entityType: 'party',
          entityId: partyId,
          fieldName: 'رصيد الطرف',
          fieldKey: 'balance',
          oldValue: oldBalance.toStringAsFixed(4),
          newValue: newBalance.toStringAsFixed(4),
          changedBy: actorId,
          changedByName: changedBy > 0 && actor?.id == changedBy
               ? changedByName
               : 'SYSTEM',
          changeReason: changeReason,
          transactionId: 'balance-adj-$partyId-${DateTime.now().millisecondsSinceEpoch}',
        );
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PARTY REPORTS
  // ═══════════════════════════════════════════════════════════════════════

  /// Get parties with outstanding balances.
  /// PIR P1-05: Paginated to prevent loading all AR/AP records at once.
  Future<List<Party>> getPartiesWithBalance({
    bool? isCustomer,
    int limit = AppConstants.defaultPageSize,
    int offset = 0,
  }) async {
    var query = select(parties)
      ..where(
        (p) => p.isActive.equals(true) & p.balance.isBiggerThan(const Variable(0)),
      );

    if (isCustomer != null) {
      if (isCustomer) {
        query = query..where((p) => p.isCustomer.equals(true));
      } else {
        query = query..where((p) => p.isSupplier.equals(true));
      }
    }

    return (query
          ..orderBy([(p) => OrderingTerm.desc(p.balance)])
          ..limit(limit, offset: offset))
        .get();
  }

  /// Get total receivables (customer balances)
  Future<double> getTotalReceivables() async {
    final result = await customSelect(
      '''
      SELECT COALESCE(SUM(balance), 0) as total 
      FROM parties 
      WHERE is_active = ${sqlBool(true)} AND balance > 0 AND is_customer = ${sqlBool(true)}
      ''',
      readsFrom: {parties},
    ).getSingle();
    return result.data['total'] as double? ?? 0;
  }

  /// Get total payables (supplier balances)
  Future<double> getTotalPayables() async {
    final result = await customSelect(
      '''
      SELECT COALESCE(SUM(balance), 0) as total 
      FROM parties 
      WHERE is_active = ${sqlBool(true)} AND balance > 0 AND is_supplier = ${sqlBool(true)}
      ''',
      readsFrom: {parties},
    ).getSingle();
    return result.data['total'] as double? ?? 0;
  }

  /// Get total balance owed by all customers (Legacy Support)
  Future<double> getTotalCustomersBalance() => getTotalReceivables();

  /// Get total balance owed to all suppliers (Legacy Support)
  Future<double> getTotalSuppliersBalance() => getTotalPayables();

  /// Get party summary with totals
  Future<PartySummary> getPartySummary(int partyId) async {
    final party = await getPartyById(partyId);
    if (party == null) {
      throw Exception('Party not found');
    }

    double totalInvoices = 0;
    double totalPayments = 0;
    int invoiceCount = 0;
    int paymentCount = 0;

    // Get purchase invoices for supplier
    if (party.isSupplier) {
      final purchases = await (select(
        purchaseInvoices,
      )..where((p) => p.supplierId.equals(partyId))).get();

      for (final p in purchases) {
        totalInvoices += p.total;
      }
      invoiceCount = purchases.length;
    }

    // Get sales invoices for customer
    if (party.isCustomer) {
      final sales = await (select(
        salesInvoices,
      )..where((s) => s.customerId.equals(partyId))).get();

      for (final s in sales) {
        totalInvoices += s.total;
      }
      invoiceCount = sales.length;
    }

    // Get payments/receipts
    final transactions = await (select(
      safeTransactions,
    )..where((t) => t.partyId.equals(partyId))).get();

    for (final t in transactions) {
      totalPayments += t.amount;
    }
    paymentCount = transactions.length;

    return PartySummary(
      partyId: partyId,
      partyName: party.name,
      isCustomer: party.isCustomer,
      isSupplier: party.isSupplier,
      currentBalance: party.balance,
      totalInvoices: totalInvoices,
      totalPayments: totalPayments,
      invoiceCount: invoiceCount,
      paymentCount: paymentCount,
    );
  }

  /// Get party by name (Unique to db.dart)
  Future<Party?> getPartyByName(String name, bool isSupplier) {
    return (select(parties)..where(
          (p) =>
              p.name.equals(name) &
              p.isSupplier.equals(isSupplier) &
              p.isActive.equals(true),
        ))
        .getSingleOrNull();
  }

  /// Hard delete a party (PROTECTED - only for parties without transaction history)
  Future<int> hardDeleteParty(int partyId) async {
    // Check for transaction history before allowing hard deletion
    final hasTransactions = await partyHasTransactions(partyId);
    if (hasTransactions) {
      throw Exception(
        'لا يمكن حذف هذا العميل/المورد نهائياً - يوجد سجل معاملات مرتبط به.',
      );
    }
    return (delete(parties)..where((p) => p.id.equals(partyId))).go();
  }
}
