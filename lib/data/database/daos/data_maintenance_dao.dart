part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// DATA MAINTENANCE DAO — صيانة البيانات والأرشفة
// ═══════════════════════════════════════════════════════════════════════════

extension DataMaintenanceDao on AppDatabase {

  // ─────────────────────────────────────────────────────────────────────────
  // ACTIVITY LOG PURGE — تنظيف سجلات الأنشطة القديمة
  // ─────────────────────────────────────────────────────────────────────────

  /// Purge activity logs older than [retentionDays] days
  /// Returns the number of deleted records
  Future<int> purgeOldActivityLogs({int retentionDays = 365}) async {
    final cutoff = DateTime.now().subtract(Duration(days: retentionDays));
    final count = await customSelect(
      'SELECT COUNT(*) as cnt FROM activity_logs WHERE created_at < ?',
      variables: [dateVar(cutoff)],
    ).getSingle();
    final toDelete = (count.data['cnt'] as int?) ?? 0;

    if (toDelete > 0) {
      await customUpdate(
        'DELETE FROM activity_logs WHERE created_at < ?',
        variables: [dateVar(cutoff)],
        updates: {activityLogs},
        updateKind: UpdateKind.delete,
      );
      debugPrint('[MAINTENANCE] Purged $toDelete activity logs older than $retentionDays days');
    }
    return toDelete;
  }

  /// Get activity log statistics for maintenance dashboard
  Future<Map<String, dynamic>> getActivityLogStats() async {
    final total = await customSelect(
      'SELECT COUNT(*) as cnt FROM activity_logs',
    ).getSingle();
    final oldest = await customSelect(
      'SELECT MIN(created_at) as oldest FROM activity_logs',
    ).getSingle();
    final sizeResult = await customSelect(
      "SELECT SUM(LENGTH(description) + LENGTH(COALESCE(old_value,'')) + LENGTH(COALESCE(new_value,''))) as bytes FROM activity_logs",
    ).getSingle();

    return {
      'totalRecords': (total.data['cnt'] as int?) ?? 0,
      'oldestRecord': oldest.data['oldest'],
      'estimatedBytes': (sizeResult.data['bytes'] as int?) ?? 0,
    };
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DATA ARCHIVAL — أرشفة البيانات القديمة
  // ─────────────────────────────────────────────────────────────────────────

  /// Archive old safe transactions (move to summary, delete detail)
  /// Keeps transactions newer than [retentionMonths] months
  Future<int> archiveOldSafeTransactions({int retentionMonths = 24}) async {
    final cutoff = DateTime.now().subtract(Duration(days: retentionMonths * 30));
    final count = await customSelect(
      'SELECT COUNT(*) as cnt FROM safe_transactions WHERE created_at < ?',
      variables: [dateVar(cutoff)],
    ).getSingle();
    final toArchive = (count.data['cnt'] as int?) ?? 0;

    if (toArchive > 0) {
      // Archive by deleting old detail transactions
      // (Summary data is preserved in journal entries)
      await customUpdate(
        'DELETE FROM safe_transactions WHERE created_at < ?',
        variables: [dateVar(cutoff)],
        updates: {safeTransactions},
        updateKind: UpdateKind.delete,
      );
      debugPrint('[MAINTENANCE] Archived $toArchive safe transactions older than $retentionMonths months');
    }
    return toArchive;
  }

  /// Archive old stock movements (detail preserved in inventory_balances)
  ///
  /// ⚠️ العمودُ `created_at` لا `movement_date`: جدولُ `StockMovements` يعرِّف
  /// `createdAt` فقط، ولا وجودَ لـ`movement_date` في المخطَّط المولَّد. وكان
  /// الاسمُ الخاطئُ يرمي «no such column» في كلِّ نداءٍ لهذه الدالّة.
  /// والربطُ عبر [AppDatabase.dateVar] في الموضعين معاً — ثوانيَ الحقبة —
  /// وإلّا اختلف ما يعدُّه `SELECT` عمّا يحذفه `DELETE` على PostgreSQL.
  Future<int> archiveOldStockMovements({int retentionMonths = 24}) async {
    final cutoff = DateTime.now().subtract(Duration(days: retentionMonths * 30));
    final count = await customSelect(
      'SELECT COUNT(*) as cnt FROM stock_movements WHERE created_at < ?',
      variables: [dateVar(cutoff)],
    ).getSingle();
    final toArchive = (count.data['cnt'] as int?) ?? 0;

    if (toArchive > 0) {
      await customUpdate(
        'DELETE FROM stock_movements WHERE created_at < ?',
        variables: [dateVar(cutoff)],
        updates: {stockMovements},
        updateKind: UpdateKind.delete,
      );
      debugPrint('[MAINTENANCE] Archived $toArchive stock movements older than $retentionMonths months');
    }
    return toArchive;
  }

  /// Get data retention summary (sizes and counts per table)
  Future<Map<String, int>> getDataRetentionSummary() async {
    final tables = [
      'activity_logs',
      'safe_transactions',
      'stock_movements',
      'journal_entry_lines',
      'sales_invoices',
      'purchase_invoices',
    ];
    final summary = <String, int>{};
    for (final table in tables) {
      try {
        final result = await customSelect(
          'SELECT COUNT(*) as cnt FROM $table',
        ).getSingle();
        summary[table] = (result.data['cnt'] as int?) ?? 0;
      } catch (_) {
        summary[table] = 0;
      }
    }
    return summary;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DATABASE COMPACTION — ضغط قاعدة البيانات
  // ─────────────────────────────────────────────────────────────────────────

  /// Run VACUUM to reclaim disk space after archival
  /// WARNING: This locks the database during execution
  Future<void> compactDatabase() async {
    debugPrint('[MAINTENANCE] Starting database VACUUM...');
    await customStatement('VACUUM');
    debugPrint('[MAINTENANCE] Database VACUUM complete');
  }

  /// Run ANALYZE to update SQLite query planner statistics
  Future<void> optimizeQueryPlanner() async {
    debugPrint('[MAINTENANCE] Running ANALYZE...');
    await customStatement('ANALYZE');
    debugPrint('[MAINTENANCE] ANALYZE complete');
  }

  /// Run integrity check
  Future<bool> checkDatabaseIntegrity() async {
    final result = await customSelect('PRAGMA integrity_check').getSingle();
    final status = result.data['integrity_check'] as String?;
    final isOk = status == 'ok';
    debugPrint('[MAINTENANCE] Integrity check: $status');
    return isOk;
  }

  /// Get database file size in bytes
  Future<int> getDatabaseSizeBytes() async {
    final result = await customSelect(
      'SELECT page_count * page_size as size FROM pragma_page_count(), pragma_page_size()',
    ).getSingle();
    return (result.data['size'] as int?) ?? 0;
  }

  /// Full maintenance run: purge + archive + compact
  Future<Map<String, dynamic>> runFullMaintenance({
    int logRetentionDays = 365,
    int transactionRetentionMonths = 24,
  }) async {
    final results = <String, dynamic>{};

    // 1. Purge old activity logs
    results['purgedLogs'] = await purgeOldActivityLogs(retentionDays: logRetentionDays);

    // 2. Archive old transactions
    results['archivedSafeTransactions'] = await archiveOldSafeTransactions(
      retentionMonths: transactionRetentionMonths,
    );
    results['archivedStockMovements'] = await archiveOldStockMovements(
      retentionMonths: transactionRetentionMonths,
    );

    // 3. Optimize
    await optimizeQueryPlanner();

    // 4. Compact
    await compactDatabase();

    // 5. Verify
    results['integrityOk'] = await checkDatabaseIntegrity();
    results['dbSizeBytes'] = await getDatabaseSizeBytes();

    debugPrint('[MAINTENANCE] Full maintenance complete: $results');
    return results;
  }
}
