part of '../database.dart';

/// A cycle-count item row joined with its product name/code + category name, for
/// the counting screen. Getters delegate to [item] so callers read the count
/// fields (expectedQty/countedQty/variance…) exactly as before.
class CycleCountItemView {
  final CycleCountItemData item;
  final String productName;
  final String? productCode;
  final String? categoryName;

  const CycleCountItemView({
    required this.item,
    required this.productName,
    this.productCode,
    this.categoryName,
  });

  int get id => item.id;
  int get productId => item.productId;
  double get expectedQty => item.expectedQty;
  double? get countedQty => item.countedQty;
  double? get variance => item.variance;
  double? get variancePercent => item.variancePercent;
}

// ═══════════════════════════════════════════════════════════════════════════
// CYCLE COUNT DAO — الجرد الدوري المستمر (Phase C4)
// ═══════════════════════════════════════════════════════════════════════════

extension CycleCountDao on AppDatabase {

  // ─────────────────────────────────────────────────────────────────────────
  // PLAN MANAGEMENT
  // ─────────────────────────────────────────────────────────────────────────

  /// Create a new cycle count plan
  Future<int> createCycleCountPlan({
    required String name,
    required int warehouseId,
    required String frequency,
    String abcClassification = 'all',
    int productsPerTask = 20,
    int? createdBy,
  }) async {
    final nextDue = _calculateNextDueDate(frequency);
    return into(cycleCountPlans).insert(
      CycleCountPlansCompanion.insert(
        name: name,
        warehouseId: warehouseId,
        frequency: Value(frequency),
        abcClassification: Value(abcClassification),
        productsPerTask: Value(productsPerTask),
        nextDueDate: Value(nextDue),
        createdBy: Value(createdBy),
      ),
    );
  }

  /// Get all active plans
  Future<List<CycleCountPlanData>> getActiveCycleCountPlans() {
    return (select(cycleCountPlans)
          ..where((p) => p.status.equals('active'))
          ..orderBy([(p) => OrderingTerm.asc(p.nextDueDate)]))
        .get();
  }

  /// Get all plans (with optional warehouse filter)
  Future<List<CycleCountPlanData>> getCycleCountPlans({int? warehouseId}) {
    final query = select(cycleCountPlans)
      ..orderBy([(p) => OrderingTerm.desc(p.createdAt)]);
    if (warehouseId != null) {
      query.where((p) => p.warehouseId.equals(warehouseId));
    }
    return query.get();
  }

  /// Update plan status
  Future<void> updatePlanStatus(int planId, String status) async {
    await (update(cycleCountPlans)..where((p) => p.id.equals(planId)))
        .write(CycleCountPlansCompanion(status: Value(status)));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TASK MANAGEMENT
  // ─────────────────────────────────────────────────────────────────────────

  /// Generate a new task for a plan
  Future<int> generateCycleCountTask({
    required int planId,
    required int warehouseId,
    required int productsPerTask,
    String? abcClassification,
    int? assignedTo,
  }) async {
    // Get products for this warehouse sorted by movement value (ABC)
    const productQuery = '''
      SELECT p.id, p.name,
        COALESCE(ib.quantity, 0) as expected_qty,
        COALESCE(
          (SELECT SUM(ABS(sm.quantity) * sm.unit_cost) 
           FROM stock_movements sm 
           WHERE sm.product_id = p.id AND sm.deleted_at IS NULL
             AND sm.warehouse_id = ?
             AND sm.created_at > ?),
          0
        ) as movement_value
      FROM products p
      LEFT JOIN inventory_balances ib ON ib.product_id = p.id AND ib.warehouse_id = ?
      WHERE p.is_active = 1 AND COALESCE(ib.quantity, 0) > 0
      ORDER BY movement_value DESC
      LIMIT ?
    ''';

    // نافذةُ الـ٩٠ يوماً تُربَط بثواني الحقبة عبر [AppDatabase.dateVar]، لا
    // بـ`datetime('now', '-90 days')`: drift يخزِّن `created_at` عدداً صحيحاً،
    // وترتيبُ الأنواع في SQLite يضع كلَّ عددٍ قبل أيِّ نصّ — فالشرطُ النصّيُّ
    // كان كاذباً دائماً، فتُصفَّر `movement_value` ويسقط ترتيبُ ABC صامتاً إلى
    // ترتيب rowid. (ولا وجودَ لـ`datetime()` على PostgreSQL أصلاً.)
    final movementWindowStart =
        DateTime.now().subtract(const Duration(days: 90));

    final results = await customSelect(
      productQuery,
      variables: [
        Variable(warehouseId),
        dateVar(movementWindowStart),
        Variable(warehouseId),
        Variable(productsPerTask),
      ],
    ).get();

    if (results.isEmpty) return -1;

    return transaction(() async {
      final taskId = await into(cycleCountTasks).insert(
        CycleCountTasksCompanion.insert(
          planId: planId,
          taskDate: DateTime.now(),
          assignedTo: Value(assignedTo),
          productCount: Value(results.length),
        ),
      );

      // Create count items
      for (final row in results) {
        await into(cycleCountItems).insert(
          CycleCountItemsCompanion.insert(
            taskId: taskId,
            productId: row.data['id'] as int,
            expectedQty: (row.data['expected_qty'] as num).toDouble(),
          ),
        );
      }

      // Update plan next due date
      final plan = await (select(cycleCountPlans)
            ..where((p) => p.id.equals(planId)))
          .getSingle();
      final nextDue = _calculateNextDueDate(plan.frequency);
      await (update(cycleCountPlans)..where((p) => p.id.equals(planId)))
          .write(CycleCountPlansCompanion(nextDueDate: Value(nextDue)));

      return taskId;
    });
  }

  /// Get tasks for a specific date range
  Future<List<CycleCountTaskData>> getCycleCountTasks({
    DateTime? fromDate,
    DateTime? toDate,
    int? assignedTo,
    String? status,
  }) {
    final query = select(cycleCountTasks)
      ..orderBy([(t) => OrderingTerm.desc(t.taskDate)]);

    if (fromDate != null) {
      query.where((t) => t.taskDate.isBiggerOrEqual(Variable(fromDate)));
    }
    if (toDate != null) {
      query.where((t) => t.taskDate.isSmallerOrEqual(Variable(toDate)));
    }
    if (assignedTo != null) {
      query.where((t) => t.assignedTo.equals(assignedTo));
    }
    if (status != null) {
      query.where((t) => t.status.equals(status));
    }

    return query.get();
  }

  /// Get items for a task
  Future<List<CycleCountItemData>> getCycleCountItems(int taskId) {
    return (select(cycleCountItems)
          ..where((i) => i.taskId.equals(taskId))
          ..orderBy([(i) => OrderingTerm.asc(i.id)]))
        .get();
  }

  /// Get items for a task WITH the product name/code and category name resolved.
  /// The counting screen needs these; [getCycleCountItems] returns only the raw
  /// item row (product_id), which the screen used to render as a bare id label.
  Future<List<CycleCountItemView>> getCycleCountItemsWithProduct(int taskId) async {
    final items = await getCycleCountItems(taskId);
    if (items.isEmpty) return const [];

    final ids = items.map((i) => i.productId).toSet().toList();
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await customSelect(
      'SELECT p.id AS pid, p.name AS pname, p.code AS pcode, c.name AS cname '
      'FROM products p '
      'LEFT JOIN categories c ON c.id = p.category_id '
      'WHERE p.id IN ($placeholders)',
      variables: ids.map((e) => Variable<int>(e)).toList(),
      readsFrom: {products, categories},
    ).get();

    final labels = {for (final r in rows) r.data['pid'] as int: r.data};
    return items.map((i) {
      final l = labels[i.productId];
      return CycleCountItemView(
        item: i,
        productName: (l?['pname'] as String?) ?? 'صنف #${i.productId}',
        productCode: l?['pcode'] as String?,
        categoryName: l?['cname'] as String?,
      );
    }).toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // COUNT SUBMISSION
  // ─────────────────────────────────────────────────────────────────────────

  /// Submit a count for one item
  Future<void> submitCount({
    required int itemId,
    required double countedQty,
    String? notes,
  }) async {
    final item = await (select(cycleCountItems)
          ..where((i) => i.id.equals(itemId)))
        .getSingle();

    final variance = countedQty - item.expectedQty;
    final variancePercent = item.expectedQty > 0
        ? (variance / item.expectedQty * 100)
        : 0.0;

    await (update(cycleCountItems)..where((i) => i.id.equals(itemId)))
        .write(CycleCountItemsCompanion(
      countedQty: Value(countedQty),
      variance: Value(variance),
      variancePercent: Value(variancePercent),
      notes: Value(notes),
      countedAt: Value(DateTime.now()),
    ));

    // Update task counted count
    final countedSoFar = await customSelect(
      'SELECT COUNT(*) as cnt FROM cycle_count_items WHERE task_id = ? AND counted_qty IS NOT NULL',
      variables: [Variable(item.taskId)],
    ).getSingle();
    final counted = (countedSoFar.data['cnt'] as int?) ?? 0;

    final varianceItems = await customSelect(
      'SELECT COUNT(*) as cnt FROM cycle_count_items WHERE task_id = ? AND variance IS NOT NULL AND ABS(variance) > 0.001',
      variables: [Variable(item.taskId)],
    ).getSingle();
    final variances = (varianceItems.data['cnt'] as int?) ?? 0;

    await (update(cycleCountTasks)..where((t) => t.id.equals(item.taskId)))
        .write(CycleCountTasksCompanion(
      countedCount: Value(counted),
      varianceCount: Value(variances),
    ));
  }

  /// Mark a task as started
  Future<void> startCycleCountTask(int taskId) async {
    await (update(cycleCountTasks)..where((t) => t.id.equals(taskId)))
        .write(CycleCountTasksCompanion(
      status: const Value('in_progress'),
      startedAt: Value(DateTime.now()),
    ));
  }

  /// Complete a task
  Future<void> completeCycleCountTask(int taskId) async {
    await (update(cycleCountTasks)..where((t) => t.id.equals(taskId)))
        .write(CycleCountTasksCompanion(
      status: const Value('completed'),
      completedAt: Value(DateTime.now()),
    ));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ANALYTICS
  // ─────────────────────────────────────────────────────────────────────────

  /// Get variance report for a date range
  Future<List<Map<String, dynamic>>> getVarianceReport({
    DateTime? fromDate,
    DateTime? toDate,
    int? warehouseId,
  }) async {
    var whereClause = "WHERE ci.variance IS NOT NULL AND ABS(ci.variance) > 0.001";
    final vars = <Variable>[];

    if (fromDate != null) {
      whereClause += " AND ci.counted_at >= ?";
      vars.add(Variable(fromDate));
    }
    if (toDate != null) {
      whereClause += " AND ci.counted_at <= ?";
      vars.add(Variable(toDate));
    }
    if (warehouseId != null) {
      whereClause += " AND ct.plan_id IN (SELECT id FROM cycle_count_plans WHERE warehouse_id = ?)";
      vars.add(Variable(warehouseId));
    }

    final results = await customSelect(
      '''SELECT p.name as product_name, p.code as product_code,
            ci.expected_qty, ci.counted_qty, ci.variance, ci.variance_percent,
            ci.counted_at, ct.task_date
         FROM cycle_count_items ci
         JOIN cycle_count_tasks ct ON ct.id = ci.task_id
         JOIN products p ON p.id = ci.product_id
         $whereClause
         ORDER BY ABS(ci.variance_percent) DESC''',
      variables: vars,
    ).get();

    return results.map((r) => r.data).toList();
  }

  /// Get counting accuracy percentage
  Future<double> getCountAccuracy({int? planId}) async {
    var query = '''
      SELECT 
        COUNT(*) as total,
        SUM(CASE WHEN ABS(COALESCE(ci.variance, 0)) < 0.001 THEN 1 ELSE 0 END) as accurate
      FROM cycle_count_items ci
      JOIN cycle_count_tasks ct ON ct.id = ci.task_id
      WHERE ci.counted_qty IS NOT NULL
    ''';
    final vars = <Variable>[];

    if (planId != null) {
      query += ' AND ct.plan_id = ?';
      vars.add(Variable(planId));
    }

    final result = await customSelect(query, variables: vars).getSingle();
    final total = (result.data['total'] as int?) ?? 0;
    final accurate = (result.data['accurate'] as int?) ?? 0;

    return total > 0 ? (accurate / total * 100) : 100.0;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // INVENTORY ADJUSTMENTS
  // ─────────────────────────────────────────────────────────────────────────

  /// Apply cycle count adjustments:
  /// - Update inventory_balances.quantity to the counted qty
  /// - Insert stock_movements for each adjusted item
  /// Returns {shortageValue, overageValue} for journal entry posting
  Future<Map<String, double>> applyCycleCountAdjustments(int taskId) async {
    final items = await getCycleCountItems(taskId);

    final taskRow = await customSelect(
      'SELECT plan_id FROM cycle_count_tasks WHERE id = ?',
      variables: [Variable(taskId)],
    ).getSingle();
    final planId = taskRow.data['plan_id'] as int;

    final planRow = await customSelect(
      'SELECT warehouse_id FROM cycle_count_plans WHERE id = ?',
      variables: [Variable(planId)],
    ).getSingle();
    final planWarehouseId = planRow.data['warehouse_id'] as int;

    double totalShortageValue = 0;
    double totalOverageValue = 0;

    await transaction(() async {
      for (final item in items) {
        if (item.countedQty == null) continue;
        final counted = item.countedQty!;

        // Spec 147 (S-COUNT): value at the APPROVED WAC (products.costPrice —
        // the single costing source, guide §0), NOT inventory_balances.
        // average_cost. Matches finalizeAudit → same variance settles to the
        // same value on both count subsystems.
        final product = await getProductById(item.productId);
        final unitCost = product?.costPrice ?? 0;

        // Spec 147 (S-COUNT): anchor the correction on the PHYSICAL count.
        // delta = counted − current on-hand (read FRESH), so the balance lands
        // exactly on the counted number (as the old raw `SET quantity=counted`
        // did) even if a sale moved stock since the count was planned — and it
        // never drives the balance below zero (result = counted ≥ 0), so a
        // shortage count can always be finalized. The GL settles on this SAME
        // delta, so the journal value == the actual stock change (interim sales
        // already carry their own COGS and must not be re-booked as shrinkage).
        // The stored cycle_count_items.variance stays the count-time snapshot
        // (FR-012) — it drives the variance REPORT, not the settlement.
        final curBal = await (select(inventoryBalances)
              ..where((b) =>
                  b.productId.equals(item.productId) &
                  b.warehouseId.equals(planWarehouseId)))
            .getSingleOrNull();
        final current = curBal?.quantity ?? 0.0;
        final delta = counted - current;
        if (delta.abs() < 0.0001) continue;

        if (delta < 0) {
          totalShortageValue += delta.abs() * unitCost;
        } else {
          totalOverageValue += delta * unitCost;
        }

        // Route through adjustStock instead of the old raw UPDATE + INSERT. One
        // call now ALSO updates products.currentStock (kills the drift the raw
        // UPDATE left) and mints a globalId on the movement (financial effect
        // reaches other installs via the standard sync path).
        // postAdjustmentJournal:false — the ONE aggregate settlement JE is
        // posted by finalizeCycleCountTask; letting adjustStock post per-item
        // here too would double-count the variance in the GL.
        await adjustStock(
          productId: item.productId,
          warehouseId: planWarehouseId,
          quantity: delta,
          type: 'cycle_count',
          referenceType: 'cycle_count',
          referenceId: taskId,
          unitCost: unitCost,
          notes: 'تعديل جرد دوري — ${delta > 0 ? "فائض" : "عجز"}: '
              '${delta.abs().toStringAsFixed(AppConstants.decimalPlaces)}',
          postAdjustmentJournal: false,
        );
        // WH-020: a shortage leaves the lots too (same issue order as a sale);
        // a surplus invents no lot - it has no number or expiry to record.
        if (delta < 0) {
          await shrinkBatchesForLoss(productId: item.productId, warehouseId: planWarehouseId, quantity: delta.abs());
        }
      }
    });

    return {
      'shortageValue': totalShortageValue,
      'overageValue': totalOverageValue,
    };
  }

  /// Spec 147 (S-COUNT): atomic finalize for a cycle-count task (R3).
  ///
  /// Collapses the old three non-atomic UI steps (completeCycleCountTask +
  /// applyCycleCountAdjustments + generateCycleCountEntry) into ONE
  /// transaction: mark the task completed → apply each variance (via
  /// adjustStock at costPrice) → post ONE aggregate settlement JE. A failure at
  /// any step rolls back all of it. Idempotent: a task already 'completed' is a
  /// no-op (belt-and-braces with the screen's saving guard against double-tap).
  Future<void> finalizeCycleCountTask(int taskId) async {
    await transaction(() async {
      final task = await (select(cycleCountTasks)
            ..where((t) => t.id.equals(taskId)))
          .getSingleOrNull();
      if (task == null) return;
      if (task.status == 'completed') return; // idempotent — already finalized

      // 1. Mark completed.
      await (update(cycleCountTasks)..where((t) => t.id.equals(taskId))).write(
        CycleCountTasksCompanion(
          status: const Value('completed'),
          completedAt: Value(DateTime.now()),
        ),
      );

      // 2. Apply stock corrections (adjustStock @ costPrice,
      //    postAdjustmentJournal:false) and collect the net shortage/surplus.
      final totals = await applyCycleCountAdjustments(taskId);
      final shortage = totals['shortageValue'] ?? 0;
      final surplus = totals['overageValue'] ?? 0;

      // 3. Post ONE aggregate settlement JE (guide §2 — "قيد واحد لكل مهمة").
      if (shortage <= 0 && surplus <= 0) return; // zero variance → no entry

      final planRow = await customSelect(
        'SELECT warehouse_id FROM cycle_count_plans WHERE id = ?',
        variables: [Variable(task.planId)],
      ).getSingle();
      final warehouseId = planRow.data['warehouse_id'] as int;
      final warehouse = await getWarehouseById(warehouseId);
      // Entry-level branch only — matches finalizeAudit. Line-level costCenterId
      // is intentionally NOT set: warehouse.branchId is a Branches id, NOT a
      // cost-center id (journal_entry_lines.costCenterId has no FK, so a wrong
      // id inserts silently and skews cost-center P&L). Letting createJournalEntry
      // resolve the cost center from branchId gives the same valid dimension the
      // audit path gets.
      final branchId = warehouse?.branchId;

      // FR-009: fail loud on a missing settlement account — never move stock
      // (already applied above) with no balanced GL counterpart; the throw
      // rolls the whole finalize back.
      final inventoryAcc = await accountingDao.getAccountByPurpose('inventory');
      if (inventoryAcc == null) {
        throw Exception('تعذّر ترحيل قيد تسوية الجرد الدوري #$taskId: حساب المخزون غير مربوط');
      }

      final lines = <JournalLine>[];
      if (shortage > 0) {
        final shortageAcc =
            await accountingDao.getAccountByPurpose('inventory_shrinkage') ??
                await accountingDao.getAccountByPurpose('misc_expense');
        if (shortageAcc == null) {
          throw Exception('تعذّر ترحيل قيد تسوية الجرد الدوري #$taskId: حساب عجز المخزون غير مربوط');
        }
        lines.add(JournalLine(accountId: shortageAcc.id, debit: shortage, description: 'عجز مخزون — جرد دوري #$taskId'));
        lines.add(JournalLine(accountId: inventoryAcc.id, credit: shortage, description: 'نقص مخزون — جرد دوري #$taskId'));
      }
      if (surplus > 0) {
        final surplusAcc =
            await accountingDao.getAccountByPurpose('inventory_surplus') ??
                await accountingDao.getAccountByPurpose('other_income');
        if (surplusAcc == null) {
          throw Exception('تعذّر ترحيل قيد تسوية الجرد الدوري #$taskId: حساب فائض المخزون غير مربوط');
        }
        lines.add(JournalLine(accountId: inventoryAcc.id, debit: surplus, description: 'زيادة مخزون — جرد دوري #$taskId'));
        lines.add(JournalLine(accountId: surplusAcc.id, credit: surplus, description: 'فائض مخزون — جرد دوري #$taskId'));
      }

      // Deterministic gid (R9). ponytail: keyed on the local taskId — see
      // JournalEntryGid.sourceInventoryCount for the multi-device caveat.
      final jeGid = JournalEntryGid.compute(
        sourceType: JournalEntryGid.sourceInventoryCount,
        sourceGid: 'cycle$taskId',
        verb: 'settle',
      );
      await accountingDao.createJournalEntry(
        description: 'قيد تعديل جرد دوري #$taskId',
        date: DateTime.now(),
        lines: lines,
        referenceType: 'cycle_count',
        referenceId: taskId,
        isAutoPosted: true,
        branchId: branchId,
        globalId: jeGid,
      );
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  DateTime _calculateNextDueDate(String frequency) {
    final now = DateTime.now();
    switch (frequency) {
      case 'daily':
        return now.add(const Duration(days: 1));
      case 'weekly':
        return now.add(const Duration(days: 7));
      case 'monthly':
        return DateTime(now.year, now.month + 1, now.day);
      case 'quarterly':
        return DateTime(now.year, now.month + 3, now.day);
      default:
        return now.add(const Duration(days: 7));
    }
  }
}
