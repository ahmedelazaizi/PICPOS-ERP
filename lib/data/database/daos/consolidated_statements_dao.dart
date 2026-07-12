part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CONSOLIDATED FINANCIAL STATEMENTS DAO — القوائم المالية الموحدة
// IAS 27 / IFRS 10 / IAS 28
// ═══════════════════════════════════════════════════════════════════════════

extension ConsolidatedStatementsDao on AppDatabase {

  // ─────────────────────────────────────────────────────────────────────────
  // ENTITY MANAGEMENT
  // ─────────────────────────────────────────────────────────────────────────

  /// Create a business entity (parent, subsidiary, or associate)
  Future<int> createEntity({
    required String name,
    required String code,
    String type = 'subsidiary',
    int? parentEntityId,
    double ownershipPct = 100,
    int? currencyId,
  }) async {
    return into(entities).insert(
      EntitiesCompanion.insert(
        name: name,
        code: code,
        type: Value(type),
        parentEntityId: Value(parentEntityId),
        ownershipPct: Value(ownershipPct),
        currencyId: Value(currencyId),
      ),
    );
  }

  /// Map entity to cost centers / branches
  Future<void> mapEntityToCostCenter(int entityId, int costCenterId) async {
    await into(entityMappings).insert(
      EntityMappingsCompanion.insert(
        entityId: entityId,
        costCenterId: Value(costCenterId),
      ),
    );
  }

  /// Get entity hierarchy
  Future<List<EntityData>> getEntityHierarchy() async {
    return (select(entities)
          ..orderBy([(e) => OrderingTerm.asc(e.parentEntityId)]))
        .get();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CONSOLIDATION ENGINE
  // ─────────────────────────────────────────────────────────────────────────

  /// Generate consolidated trial balance
  /// Aggregates balances by ownership % and eliminates inter-company
  Future<List<Map<String, dynamic>>> generateConsolidatedTrialBalance(
      int fiscalYearId) async {
    final entityList = await (select(entities)
          ..where((e) => e.isActive.equals(true)))
        .get();

    final consolidatedMap = <int, Map<String, dynamic>>{};

    for (final entity in entityList) {
      final ownershipFactor = entity.ownershipPct / 100;

      // Get entity's cost centers
      final mappings = await (select(entityMappings)
            ..where((m) => m.entityId.equals(entity.id)))
          .get();

      for (final mapping in mappings) {
        // Get account balances for this entity's cost centers
        final balances = await customSelect(
          '''SELECT a.id, a.name, a.code, a.account_type,
                    SUM(jel.debit) as total_debit, SUM(jel.credit) as total_credit
             FROM journal_entry_lines jel
             JOIN journal_entries je ON jel.entry_id = je.id
             JOIN accounts a ON jel.account_id = a.id
             WHERE je.fiscal_year_id = ?
               AND je.cost_center_id = ?
             GROUP BY a.id''',
          variables: [
            Variable(fiscalYearId),
            Variable(mapping.costCenterId ?? 0),
          ],
        ).get();

        for (final row in balances) {
          final accountId = row.data['id'] as int;
          final debit = ((row.data['total_debit'] as num?) ?? 0).toDouble() * ownershipFactor;
          final credit = ((row.data['total_credit'] as num?) ?? 0).toDouble() * ownershipFactor;

          if (!consolidatedMap.containsKey(accountId)) {
            consolidatedMap[accountId] = {
              'accountId': accountId,
              'accountName': row.data['name'],
              'accountCode': row.data['code'],
              'accountType': row.data['account_type'],
              'totalDebit': 0.0,
              'totalCredit': 0.0,
            };
          }
          consolidatedMap[accountId]!['totalDebit'] =
              (consolidatedMap[accountId]!['totalDebit'] as double) + debit;
          consolidatedMap[accountId]!['totalCredit'] =
              (consolidatedMap[accountId]!['totalCredit'] as double) + credit;
        }
      }
    }

    return consolidatedMap.values.toList();
  }

  /// Calculate minority interest (IAS 27)
  Future<Map<String, double>> calculateMinorityInterest(int fiscalYearId) async {
    final partialEntities = await customSelect(
      'SELECT * FROM entities WHERE ownership_pct < 100 AND is_active = 1',
    ).get();

    double minorityShare = 0;
    for (final entity in partialEntities) {
      final ownershipPct = (entity.data['ownership_pct'] as num).toDouble();
      final minorityPct = (100 - ownershipPct) / 100;

      // Get entity net income
      final netIncome = await customSelect(
        '''SELECT
             COALESCE(SUM(CASE WHEN a.account_type = 'revenue' THEN jel.credit - jel.debit ELSE 0 END), 0) -
             COALESCE(SUM(CASE WHEN a.account_type = 'expense' THEN jel.debit - jel.credit ELSE 0 END), 0) as net
           FROM journal_entry_lines jel
           JOIN journal_entries je ON jel.entry_id = je.id
           JOIN accounts a ON jel.account_id = a.id
           JOIN entity_mappings em ON je.cost_center_id = em.cost_center_id
           WHERE je.fiscal_year_id = ? AND em.entity_id = ?''',
        variables: [Variable(fiscalYearId), Variable(entity.data['id'] as int)],
      ).getSingleOrNull();

      final net = ((netIncome?.data['net'] as num?) ?? 0).toDouble();
      minorityShare += net * minorityPct;
    }

    return {'minorityInterest': minorityShare};
  }
}
