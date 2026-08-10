// ═══════════════════════════════════════════════════════════════════════════
// TREASURY REPORTS & ANALYTICS DAO
// Extracted from treasury_dao.dart — Sprint 12 God File Splitting
// ═══════════════════════════════════════════════════════════════════════════

part of '../database.dart';

// ═════════════════════════════════════════════════════════════════════════
// Spec 106 — Centralized transactionType classification.
//
// One source of truth so SQL queries, Dart aggregations, and per-user
// summaries cannot drift apart. Used by:
//   • getTreasuryReportAnalytics
//   • getPerUserTreasurySummary
//   • (SQL queries hand-encode the same mapping, kept in sync by tests)
//
// `receipt`     → increases totalReceipts
// `payment`     → increases totalPayments
// `withdrawal`  → audit transfer (e.g. shift close) → neutral
// `transfer`    → between-safe transfer → neutral
// `closing`     → audit-only marker → neutral
//
// D-PERF-2: the classification now lives entirely in the SQL CASE expressions
// (receipt/payment summed, neutral excluded); the Dart predicate helpers were
// removed with the in-Dart loops.
// ═════════════════════════════════════════════════════════════════════════

/// Extension for Treasury Reports & Analytics
extension TreasuryReportsDao on AppDatabase {
  // ═══════════════════════════════════════════════════════════════════════
  // TREASURY REPORTS
  // ═══════════════════════════════════════════════════════════════════════

  /// Get treasury summary for a date range
  Future<TreasurySummaryData> getTreasurySummary({
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    fromDate ??= DateTime(2020);
    toDate ??= DateTime.now().add(const Duration(days: 1));

    // Spec 106 — central classification:
    //   receipt  → totalReceipts
    //   payment  → totalPayments
    //   withdrawal / transfer / closing → neutral (NOT counted)
    // Soft-deleted rows excluded.
    final result = await customSelect(
      'SELECT '
      "COALESCE(SUM(CASE WHEN transaction_type = 'receipt' THEN amount ELSE 0 END), 0) as receipts, "
      "COALESCE(SUM(CASE WHEN transaction_type = 'payment' THEN amount ELSE 0 END), 0) as payments "
      'FROM safe_transactions '
      'WHERE created_at BETWEEN ? AND ? '
      '  AND deleted_at IS NULL',
      variables: [dateVar(fromDate), dateVar(toDate)],
      readsFrom: {safeTransactions},
    ).getSingle();

    final totalReceipts = (result.data['receipts'] as num?)?.toDouble() ?? 0.0;
    final totalPayments = (result.data['payments'] as num?)?.toDouble() ?? 0.0;

    final safe = await getDefaultSafe();
    final currentBalance = safe?.balance ?? 0;

    return TreasurySummaryData(
      totalReceipts: totalReceipts,
      totalPayments: totalPayments,
      netBalance: totalReceipts - totalPayments,
      currentBalance: currentBalance,
    );
  }

  /// Issue 10 — sum of receipt vouchers in a date range, optionally scoped
  /// to a branch / cost-center. Used by the sales screen's "المحصّل" KPI
  /// card so standalone receipts (cash collected outside any specific
  /// invoice — common for delivery-company settlements) appear alongside
  /// invoice-side `paid` totals. Excludes soft-deleted rows.
  Future<double> getReceiptVouchersTotal({
    required DateTime from,
    required DateTime to,
    int? branchId,
    int? costCenterId,
    // Spec 151 D-04: authoritative branch-scope cap (mirrors D-01's
    // _dateRangeWhere / getTransactionsByDateRange). null = company-wide (no
    // cap); {} = fail-closed (no rows); {ids} = those branches OR NULL-branch
    // (shared / head-office) safes.
    Set<int>? allowedBranchIds,
  }) async {
    final branchClause =
        branchId != null ? 'AND s.branch_id = $branchId' : '';
    final costCenterClause =
        costCenterId != null ? 'AND st.cost_center_id = $costCenterId' : '';
    // Spec 151 D-04: without this cap, `branchId == null` returned the
    // COMPANY-WIDE collected-receipts total — so a branch-restricted user with
    // no branch selected saw every branch's receipts in the sales «المحصّل»
    // KPI. Scope receipts to safes the caller may read, using the SAME
    // subquery shape and fail-closed ({} → 0) semantics as _dateRangeWhere.
    final scope = _buildAuthScopeFilter(allowedBranchIds, tableAlias: 'sc');
    final scopeClause = allowedBranchIds != null
        ? 'AND st.safe_id IN (SELECT id FROM safes sc WHERE 1 = 1${scope.filter})'
        : '';
    final result = await customSelect(
      "SELECT COALESCE(SUM(st.amount), 0) AS total "
      "FROM safe_transactions st "
      "LEFT JOIN safes s ON s.id = st.safe_id "
      "WHERE st.transaction_type = 'receipt' "
      "  AND st.deleted_at IS NULL "
      "  AND st.created_at >= ? AND st.created_at < ? "
      "  $branchClause "
      "  $costCenterClause "
      "  $scopeClause",
      variables: [
        dateVar(DateUtils.startOfDay(from)),
        dateVar(DateUtils.startOfNextDay(to)),
        ...scope.vars,
      ],
      readsFrom: {safeTransactions, safes},
    ).getSingle();
    return (result.data['total'] as num?)?.toDouble() ?? 0.0;
  }

  /// Get treasury statistics by category
  ///
  /// Spec 106 — excludes soft-deleted rows.
  Future<Map<String, double>> getTreasuryStatsByCategory() async {
    final results = await customSelect(
      'SELECT category, SUM(amount) as total FROM safe_transactions '
      'WHERE deleted_at IS NULL '
      'GROUP BY category',
      readsFrom: {safeTransactions},
    ).get();

    return {
      for (final row in results)
        row.data['category'] as String: row.data['total'] as double? ?? 0,
    };
  }

  /// Get simplified treasury analytics for reports (Moved from database.dart)
  Future<TreasuryAnalytics> getTreasuryAnalytics() async {
    final balancesByType = await getSafesBalancesByType();
    final cashBalance = balancesByType['cash'] ?? 0.0;
    final bankBalance = balancesByType['bank'] ?? 0.0;
    final totalBalance = cashBalance + bankBalance;

    // Spec 106 — same classification as getTreasurySummary; soft-deleted
    // rows excluded and only `receipt` / `payment` types contribute.
    final result = await customSelect(
      'SELECT '
      'COUNT(*) as total_count, '
      "COALESCE(SUM(CASE WHEN transaction_type = 'receipt' THEN amount ELSE 0 END), 0) as receipts, "
      "COALESCE(SUM(CASE WHEN transaction_type = 'payment' THEN amount ELSE 0 END), 0) as payments "
      'FROM safe_transactions '
      'WHERE deleted_at IS NULL',
      readsFrom: {safeTransactions},
    ).getSingle();

    final totalReceipts = (result.data['receipts'] as num?)?.toDouble() ?? 0.0;
    final totalPayments = (result.data['payments'] as num?)?.toDouble() ?? 0.0;
    // transactionCount unused — ignoring for now

    return TreasuryAnalytics(
      cashBalance: cashBalance,
      bankBalance: bankBalance,
      totalBalance: totalBalance,
      periodIncome: totalReceipts,
      periodExpense: totalPayments,
      netFlow: totalReceipts - totalPayments,
      openingBalance: 0,
      totalIn: totalReceipts,
      totalOut: totalPayments,
      closingBalance: totalBalance,
      totalReceipts: totalReceipts,
      totalPayments: totalPayments,
    );
  }

  /// Get treasury transactions by date range with user name
  Future<List<_TransactionWithUser>> getTransactionsByDateRange(
    DateTime start,
    DateTime end, {
    int? userId,
    int? safeId,
    int? costCenterId,
    List<int>? safeIds,
    Set<int>? allowedBranchIds,
  }) async {
    final query = select(
      safeTransactions,
    ).join([leftOuterJoin(users, users.id.equalsExp(safeTransactions.userId))]);

    // Half-open day window — see DateUtils.startOfNextDay. `end` may arrive as
    // midnight (sales convention) or 23:59:59.999 (normalizeRange); snapping
    // to the day boundary first yields the same window for both.
    query.where(
      safeTransactions.createdAt
              .isBiggerOrEqualValue(DateUtils.startOfDay(start)) &
          safeTransactions.createdAt
              .isSmallerThanValue(DateUtils.startOfNextDay(end)),
    );

    // Hide soft-deleted rows — admin may have removed an expense on the
    // server, pull-sync replicates the `deletedAt` timestamp to the client,
    // and the list views should honor it.
    query.where(safeTransactions.deletedAt.isNull());

    if (userId != null) {
      query.where(safeTransactions.userId.equals(userId));
    }

    if (safeId != null) {
      query.where(safeTransactions.safeId.equals(safeId));
    }

    // Branch-level safe filtering: restrict to a set of safe IDs
    if (safeIds != null && safeIds.isNotEmpty) {
      query.where(safeTransactions.safeId.isIn(safeIds));
    }

    if (costCenterId != null) {
      // Filter by safe's cost center via subquery
      final safeIdsQuery = selectOnly(safes)
        ..addColumns([safes.id])
        ..where(safes.costCenterId.equals(costCenterId));
      query.where(safeTransactions.safeId.isInQuery(safeIdsQuery));
    }

    // Spec 151 D-01: authoritative branch-scope cap (see _dateRangeWhere).
    // Same semantics: null = no cap; {} = fail-closed; {ids} = those branches
    // OR NULL-branch shared safes. Enforced here so a branch-scoped user never
    // sees another branch's voucher rows even when safeIds is null (first load).
    if (allowedBranchIds != null) {
      if (allowedBranchIds.isEmpty) {
        query.where(const Constant(false)); // no branch access → no rows
      } else {
        final scopedSafes = selectOnly(safes)
          ..addColumns([safes.id])
          ..where(safes.branchId.isIn(allowedBranchIds) | safes.branchId.isNull());
        query.where(safeTransactions.safeId.isInQuery(scopedSafes));
      }
    }

    query.orderBy([OrderingTerm.desc(safeTransactions.createdAt)]);

    final rows = await query.get();
    return rows.map((row) {
      final tx = row.readTable(safeTransactions);
      final user = row.readTableOrNull(users);

      // Create a dynamic object that looks like SafeTransactionData but has userName
      // This is a quick fix to avoid breaking the UI layout that expects .userName
      return _TransactionWithUser(tx, user?.displayName ?? 'مستخدم');
    }).toList();
  }

  /// Delete an expense/payment transaction and reverse its balance effect.
  ///
  /// Uses SOFT delete (sets `deletedAt`) rather than hard-delete so that the
  /// full-sync pull endpoint still returns the row — with `deletedAt`
  /// populated — letting connected clients replicate the deletion state.
  /// Hard-deleting on the server made the row simply vanish from the pull
  /// response, so clients that didn't catch the real-time WS broadcast
  /// (offline at the moment of delete, then reconnected) never learned the
  /// row had been removed and kept showing it indefinitely.
  Future<void> deleteExpenseTransaction(int transactionId) async {
    return transaction(() async {
      final tx = await (select(
        safeTransactions,
      )..where((t) => t.id.equals(transactionId) & t.deletedAt.isNull())).getSingleOrNull();
      if (tx == null) return;

      // 071 (D5-004): period-lock gate. Without this, deleting a
      // closed-period voucher would silently bypass the period seal and
      // post the reversal JE in the current open period — leaving the
      // closed period's trial balance unbalanced. Mirrors the
      // validateFinancialPeriod call in voidSalesInvoice (sales_actions_dao
      // line 27) and voidPurchaseInvoice (purchase_dao line 1126).
      await accountingDao.validateFinancialPeriod(
        tx.createdAt,
        operation: tx.transactionType == 'receipt'
            ? 'حذف سند قبض'
            : 'حذف سند صرف',
      );

      // Get current safe balance
      final safe = await (select(
        safes,
      )..where((s) => s.id.equals(tx.safeId))).getSingleOrNull();
      if (safe != null) {
        // Reverse: payment reduced balance, so add it back.
        // 069 (D5-003): atomic delta update — no read-then-write.
        await adjustSafeBalance(safe.id, tx.amount);
      }

      // Accounting integrity: post a mirror-image reversal JE so the
      // trial balance / general ledger reflect the deletion. The original
      // auto-posted JE stays intact (audit trail). Deterministic globalId
      // `<safeTxnGid>-<refType>-rev` ensures client + server converge to ONE
      // reversal row after the delta-sync loop, since both sides run this
      // same code and compute the same UUID from the shared [tx.globalId].
      //
      // Spec 151 A-04 — reverse by the referenceType(s) that actually match
      // how the voucher's JE was posted. A voucher's auto-posted JE lands
      // under EITHER of two referenceTypes depending on which posting path
      // ran:
      //   • AutoPostingService / batchPostTreasury / purchase autopost →
      //     'receipt' (autoPostReceipt) / 'payment' (autoPostPayment)
      //   • inline _createVoucherJournalEntry (treasury_dao) →
      //     'receipt_voucher' / 'payment_voucher'
      // The old code reversed ONLY 'payment_voucher', so deleting a receipt
      // voucher — OR a payment voucher whose JE came from the autopost path
      // ('payment') — reversed nothing and left the original JE live on the
      // books. Resolve the pair from the voucher kind and reverse BOTH
      // candidate types (the non-matching one simply reverses 0 rows).
      if (tx.globalId != null && tx.globalId!.isNotEmpty) {
        final isReceipt = tx.transactionType == 'receipt';
        final candidateTypes = isReceipt
            ? const ['receipt', 'receipt_voucher']
            : const ['payment', 'payment_voucher'];
        final voucherLabel = isReceipt ? 'حذف سند قبض' : 'حذف سند صرف';

        // Spec 151 A-04 — FAIL LOUD. The previous code swallowed a failed
        // reversal (debugPrint only) and still soft-deleted the voucher,
        // while the safe balance had ALREADY been rolled back above → the
        // original receipt/payment JE stayed posted and GL silently diverged
        // from `safes.balance`. Do NOT catch: let any failure propagate so
        // the enclosing transaction() rolls back the ENTIRE delete (R3
        // atomicity + balanced-GL invariant). Never delete a voucher whose
        // GL could not be reversed.
        for (final refType in candidateTypes) {
          await reverseAutoPostedJournalEntriesFor(
            referenceType: refType,
            referenceId: transactionId,
            voidReferenceType: '${refType}_void',
            // Type-qualified deterministic source-gid so the (at most two)
            // reversal gids can never collide on the shared '<gid>-rev'
            // suffix if a voucher defensively carried a JE under both types.
            sourceGlobalId: '${tx.globalId!}-$refType',
            description: 'قيد عكسى — $voucherLabel ${tx.voucherNumber}',
            costCenterId: tx.costCenterId,
            branchId: safe?.branchId,
            // Spec 151 A04-1 — the PRIMARY (interactive UI) voucher path posts
            // its JE via _createVoucherJournalEntry with isAutoPosted=FALSE
            // under 'receipt_voucher'/'payment_voucher'. The default
            // (requireAutoPosted:true) filter would exclude it → nothing
            // reversed while the safe was already rolled back → GL drift (the
            // exact A-04 bug on the main path). Relax the flag for THIS call
            // only; the match stays keyed on (refType, referenceId=unique
            // safe-txn id) so it reverses exactly this voucher's JE.
            requireAutoPosted: false,
          );
        }
      } else {
        debugPrint('[TREASURY] Skipping reversal JE for voucher '
            '#$transactionId — safe_transaction has no globalId (legacy row)');
      }

      // Soft-delete: set deletedAt so downstream pulls can replicate state.
      await (update(safeTransactions)
            ..where((t) => t.id.equals(transactionId)))
          .write(SafeTransactionsCompanion(
        deletedAt: Value(DateTime.now()),
      ));
    });
  }

  /// Get consolidated treasury report analytics
  Future<TreasuryAnalytics> getTreasuryReportAnalytics(
    DateTime start,
    DateTime end, {
    /// H12 · نفسُ فلتر الجدول (`getTransactionsByDateRange`) — بدونه تتحرّك
    /// الصفوفُ وتبقى البطاقاتُ على إجمالي كلّ المستخدمين.
    int? userId,
    int? safeId,
    int? costCenterId,
    List<int>? safeIds,
    Set<int>? allowedBranchIds,
  }) async {
    final balancesByType =
        await getSafesBalancesByType(allowedBranchIds: allowedBranchIds);
    final cashBalance = balancesByType['cash'] ?? 0.0;
    final bankBalance = balancesByType['bank'] ?? 0.0;
    final totalBalance = cashBalance + bankBalance;

    // D-PERF-2: sum receipts/payments in SQL instead of loading every row (and
    // a wasted user join) into Dart. Filters mirror getTransactionsByDateRange
    // exactly. Neutral types (withdrawal/transfer/closing) are excluded by the
    // CASE, matching the prior Dart classification.
    final where = _dateRangeWhere(start, end,
        userId: userId,
        safeId: safeId, costCenterId: costCenterId, safeIds: safeIds,
        allowedBranchIds: allowedBranchIds);
    final row = await customSelect(
      'SELECT '
      "COALESCE(SUM(CASE WHEN transaction_type = 'receipt' THEN amount ELSE 0 END), 0) AS receipts, "
      "COALESCE(SUM(CASE WHEN transaction_type = 'payment' THEN amount ELSE 0 END), 0) AS payments "
      'FROM safe_transactions WHERE ${where.sql}',
      variables: where.vars,
      readsFrom: {safeTransactions, safes},
    ).getSingle();
    final totalReceipts = (row.data['receipts'] as num?)?.toDouble() ?? 0.0;
    final totalPayments = (row.data['payments'] as num?)?.toDouble() ?? 0.0;

    return TreasuryAnalytics(
      cashBalance: cashBalance,
      bankBalance: bankBalance,
      totalBalance: totalBalance,
      periodIncome: totalReceipts,
      periodExpense: totalPayments,
      netFlow: totalReceipts - totalPayments,
      openingBalance: 0,
      totalIn: totalReceipts,
      totalOut: totalPayments,
      closingBalance: totalBalance,
      totalReceipts: totalReceipts,
      totalPayments: totalPayments,
    );
  }

  /// Get transactions by category
  Future<List<SafeTransactionData>> getTransactionsByCategory(String category) {
    return (select(
      safeTransactions,
    )..where((t) => t.category.equals(category))).get();
  }

  /// Get transactions by type (receipt/payment)
  Future<List<SafeTransactionData>> getTransactionsByType(String type) {
    return (select(
      safeTransactions,
    )..where((t) => t.transactionType.equals(type))).get();
  }

  /// Get per-user treasury summary for a date range
  Future<List<UserTreasurySummary>> getPerUserTreasurySummary(
    DateTime start,
    DateTime end, {
    int? safeId,
    int? costCenterId,
    List<int>? safeIds,
    Set<int>? allowedBranchIds,
  }) async {
    // D-PERF-2: group + sum in SQL. Neutral rows are excluded from the sums by
    // the CASE but still counted (COUNT(*)) toward transactionCount, matching
    // the prior Dart accumulator.
    final where = _dateRangeWhere(start, end,
        safeId: safeId, costCenterId: costCenterId, safeIds: safeIds,
        allowedBranchIds: allowedBranchIds);
    final rows = await customSelect(
      'SELECT user_id, '
      "COALESCE(SUM(CASE WHEN transaction_type = 'receipt' THEN amount ELSE 0 END), 0) AS receipts, "
      "COALESCE(SUM(CASE WHEN transaction_type = 'payment' THEN amount ELSE 0 END), 0) AS payments, "
      'COUNT(*) AS cnt '
      'FROM safe_transactions WHERE ${where.sql} GROUP BY user_id',
      variables: where.vars,
      readsFrom: {safeTransactions, safes},
    ).get();

    return rows.map((r) {
      final receipts = (r.data['receipts'] as num?)?.toDouble() ?? 0.0;
      final payments = (r.data['payments'] as num?)?.toDouble() ?? 0.0;
      return UserTreasurySummary(
        userId: r.data['user_id'] as int?,
        totalReceipts: receipts,
        totalPayments: payments,
        netFlow: receipts - payments,
        transactionCount: r.data['cnt'] as int,
      );
    }).toList()
      ..sort(
        (a, b) => (b.totalReceipts + b.totalPayments).compareTo(
          a.totalReceipts + a.totalPayments,
        ),
      );
  }

  /// D-PERF-2: shared date-range + optional safe/cost-center filter, matching
  /// getTransactionsByDateRange's WHERE exactly: soft-deleted excluded,
  /// created_at ∈ [startOfDay(start), startOfNextDay(end)).
  ///
  /// «matching exactly» was an aspiration, not a fact: the screen reads its
  /// rows from ReportingRepositoryImpl.getTransactionsByDateRange — a SEPARATE
  /// query that had no soft-delete guard, so the KPI card and the table below
  /// it disagreed. Both sides are now covered by
  /// test/unit/treasury_report_row_hygiene_test.dart.
  ({String sql, List<Variable> vars}) _dateRangeWhere(
    DateTime start,
    DateTime end, {
    int? userId,
    int? safeId,
    int? costCenterId,
    List<int>? safeIds,
    Set<int>? allowedBranchIds,
  }) {
    // Half-open day window — see DateUtils.startOfNextDay.
    final vars = <Variable>[
      dateVar(DateUtils.startOfDay(start)),
      dateVar(DateUtils.startOfNextDay(end)),
    ];
    final sql = StringBuffer(
        'deleted_at IS NULL AND created_at >= ? AND created_at < ?');
    // H12 · فلترُ المستخدم كان يُطبَّق على الجدول (`getTransactionsByDateRange`)
    // ولا يصل البطاقاتِ إطلاقاً، فتقول البطاقةُ ١٬٤٠٠ والجدولُ تحتها ١٬٠٠٠
    // على نفس الشاشة وبنفس الفلتر.
    if (userId != null) {
      sql.write(' AND user_id = ?');
      vars.add(Variable(userId));
    }
    if (safeId != null) {
      sql.write(' AND safe_id = ?');
      vars.add(Variable(safeId));
    }
    // null = every safe; [] = none. The old `&& safeIds.isNotEmpty` skipped the
    // filter for a branch with no safes, so it saw EVERY safe — the inverse of
    // the intent (convention: sales_analytics_dao.dart:182, inventory_dao.dart:1219).
    if (safeIds != null) {
      if (safeIds.isEmpty) {
        sql.write(' AND 1 = 0');
      } else {
        sql.write(' AND safe_id IN (${List.filled(safeIds.length, '?').join(', ')})');
        vars.addAll(safeIds.map((e) => Variable(e)));
      }
    }
    if (costCenterId != null) {
      sql.write(' AND safe_id IN (SELECT id FROM safes WHERE cost_center_id = ?)');
      vars.add(Variable(costCenterId));
    }
    // Spec 151 D-01: authoritative branch-scope cap. Reuse the canonical
    // _buildAuthScopeFilter so treasury matches the accounting KPIs and the
    // D-02 returns analytics EXACTLY: null = company-wide (we simply don't
    // enter here); {} = fail-closed (` AND 1 = 0` → the safe-id subquery yields
    // nothing → no rows leak); {ids} = those branches OR NULL-branch shared
    // safes. Enforced in the DAO so it holds even if the screen forgets to seed
    // the safe-id filter (the D-01 bug: _branchSafeIds stayed null on first
    // load → every branch's vouchers aggregated for a branch-scoped manager).
    if (allowedBranchIds != null) {
      final az = _buildAuthScopeFilter(allowedBranchIds, tableAlias: 's');
      sql.write(' AND safe_id IN (SELECT id FROM safes s WHERE 1 = 1${az.filter})');
      vars.addAll(az.vars);
    }
    return (sql: sql.toString(), vars: vars);
  }

  // Spec 151 D-01 — auth-scope fragment. Each reporting DAO extension keeps its
  // own private copy (SalesAnalyticsDao / AccountingReportsDao already do); a
  // shared one would be an ambiguous extension member. Semantics are identical:
  // null = no filter; {} = fail-closed; {ids} = those branches OR NULL-branch
  // (shared / head-office) rows.
  ({String filter, List<Variable> vars}) _buildAuthScopeFilter(
    Set<int>? allowedBranchIds, {
    String tableAlias = 's',
  }) {
    if (allowedBranchIds == null) return (filter: '', vars: <Variable>[]);
    if (allowedBranchIds.isEmpty) {
      return (filter: ' AND 1 = 0', vars: <Variable>[]);
    }
    final placeholders = allowedBranchIds.map((_) => '?').join(', ');
    return (
      filter:
          ' AND ($tableAlias.branch_id IN ($placeholders) OR $tableAlias.branch_id IS NULL)',
      vars: allowedBranchIds.map<Variable>((id) => Variable<int>(id)).toList(),
    );
  }
}

/// Per-user treasury summary
class UserTreasurySummary {
  final int? userId;
  final double totalReceipts;
  final double totalPayments;
  final double netFlow;
  final int transactionCount;

  UserTreasurySummary({
    required this.userId,
    required this.totalReceipts,
    required this.totalPayments,
    required this.netFlow,
    required this.transactionCount,
  });
}

class _TransactionWithUser {
  final SafeTransactionData _tx;
  final String userName;

  _TransactionWithUser(this._tx, this.userName);

  int get id => _tx.id;
  String get voucherNumber => _tx.voucherNumber;
  double get amount => _tx.amount;
  double get discount => _tx.discount;
  double get balanceAfter => _tx.balanceAfter;
  String? get description => _tx.description;
  String? get category => _tx.category;
  String get transactionType => _tx.transactionType;
  DateTime get createdAt => _tx.createdAt;
  int get safeId => _tx.safeId;
  int? get partyId => _tx.partyId;
  int? get userId => _tx.userId;
  SafeTransactionData get tx => _tx;
}
