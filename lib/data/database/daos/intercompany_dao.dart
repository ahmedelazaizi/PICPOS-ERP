part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// INTER-COMPANY ACCOUNTING DAO — محاسبة بين الشركات
// IFRS 10 — Elimination of inter-company transactions
// ═══════════════════════════════════════════════════════════════════════════

extension IntercompanyDao on AppDatabase {

  /// Record an inter-company transaction
  Future<int> recordIntercompanyTransaction({
    required int fromEntityId,
    required int toEntityId,
    required String transactionType,
    required double amount,
    required DateTime transactionDate,
    int? currencyId,
    double exchangeRate = 1.0,
    String? description,
  }) async {
    return into(intercompanyTransactions).insert(
      IntercompanyTransactionsCompanion.insert(
        fromEntityId: fromEntityId,
        toEntityId: toEntityId,
        transactionType: transactionType,
        amount: amount,
        transactionDate: transactionDate,
        currencyId: Value(currencyId),
        exchangeRate: Value(exchangeRate),
        description: Value(description),
      ),
    );
  }

  /// Confirm an inter-company transaction (both sides agree)
  Future<void> confirmIntercompanyTransaction(int transactionId) async {
    await (update(intercompanyTransactions)
          ..where((t) => t.id.equals(transactionId)))
        .write(const IntercompanyTransactionsCompanion(
      status: Value('confirmed'),
    ));
  }

  /// Eliminate inter-company transactions for consolidation
  /// Returns list of eliminated amounts by pair
  Future<List<Map<String, dynamic>>> eliminateForConsolidation(int fiscalYearId) async {
    // Find all confirmed inter-company transactions in the period
    final transactions = await customSelect(
      '''SELECT ict.*, fy.start_date, fy.end_date
         FROM intercompany_transactions ict
         JOIN fiscal_years fy ON fy.id = ?
         WHERE ict.status = 'confirmed'
           AND ict.transaction_date >= fy.start_date
           AND ict.transaction_date <= fy.end_date''',
      variables: [Variable(fiscalYearId)],
    ).get();

    final eliminations = <Map<String, dynamic>>[];

    for (final tx in transactions) {
      final amount = (tx.data['amount'] as num).toDouble();
      final fromEntity = tx.data['from_entity_id'] as int;
      final toEntity = tx.data['to_entity_id'] as int;
      final txType = tx.data['transaction_type'] as String;

      eliminations.add({
        'fromEntityId': fromEntity,
        'toEntityId': toEntity,
        'transactionType': txType,
        'amount': amount,
        'eliminationDescription': 'استبعاد $txType بين كيان #$fromEntity وكيان #$toEntity',
      });

      // Mark as eliminated
      await customStatement(
        'UPDATE intercompany_transactions SET status = ? WHERE id = ?',
        ['eliminated', tx.data['id'] as int],
      );
    }

    return eliminations;
  }

  /// Get inter-company balance report (a/r and a/p between entities)
  Future<List<Map<String, dynamic>>> getIntercompanyBalances() async {
    final result = await customSelect(
      '''SELECT from_entity_id, to_entity_id,
              SUM(CASE WHEN status != 'eliminated' THEN amount ELSE 0 END) as outstanding,
              COUNT(*) as tx_count
         FROM intercompany_transactions
         WHERE status IN ('pending', 'confirmed')
         GROUP BY from_entity_id, to_entity_id''',
    ).get();

    return result
        .map((r) => {
              'fromEntityId': r.data['from_entity_id'],
              'toEntityId': r.data['to_entity_id'],
              'outstanding': r.data['outstanding'],
              'transactionCount': r.data['tx_count'],
            })
        .toList();
  }

  /// Reconcile inter-company balances
  Future<Map<String, dynamic>> reconcileEntities(int entity1Id, int entity2Id) async {
    final fromTo = await customSelect(
      'SELECT SUM(amount) as total FROM intercompany_transactions WHERE from_entity_id = ? AND to_entity_id = ? AND status = \'confirmed\'',
      variables: [Variable(entity1Id), Variable(entity2Id)],
    ).getSingleOrNull();

    final toFrom = await customSelect(
      'SELECT SUM(amount) as total FROM intercompany_transactions WHERE from_entity_id = ? AND to_entity_id = ? AND status = \'confirmed\'',
      variables: [Variable(entity2Id), Variable(entity1Id)],
    ).getSingleOrNull();

    final balance1 = ((fromTo?.data['total'] as num?) ?? 0).toDouble();
    final balance2 = ((toFrom?.data['total'] as num?) ?? 0).toDouble();

    return {
      'entity1Owes': balance1,
      'entity2Owes': balance2,
      'netBalance': balance1 - balance2,
      'isReconciled': (balance1 - balance2).abs() < 0.01,
    };
  }
}
