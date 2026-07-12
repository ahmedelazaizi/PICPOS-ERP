import 'dart:async';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import '../data/database/database.dart';
import '../data/database/pg_config.dart';
import '../data/database/connection_io.dart'
    show openPostgresConnection, testPostgresConnection;

/// Progress state for the offline→PostgreSQL sync process.
class SyncProgress {
  final String currentTable;
  final int tablesCompleted;
  final int tablesTotal;
  final int rowsSynced;
  final String? error;
  final bool isDone;

  const SyncProgress({
    this.currentTable = '',
    this.tablesCompleted = 0,
    this.tablesTotal = 0,
    this.rowsSynced = 0,
    this.error,
    this.isDone = false,
  });

  double get progress =>
      tablesTotal > 0 ? tablesCompleted / tablesTotal : 0.0;

  String get statusText {
    if (isDone) return error != null ? 'فشلت المزامنة' : 'تمت المزامنة بنجاح';
    if (currentTable.isEmpty) return 'جاري الاتصال...';
    return 'مزامنة $currentTable ($tablesCompleted/$tablesTotal)';
  }
}

/// Service that copies data created during offline fallback (SQLite)
/// back to the PostgreSQL server when the connection is restored.
///
/// Uses raw SQL to read rows from the local SQLite database where
/// `created_at >= offlineFallbackStart`, then upserts them into
/// a temporary PostgreSQL-backed AppDatabase.
class OfflineFallbackSyncService {
  OfflineFallbackSyncService._();
  static final OfflineFallbackSyncService instance =
      OfflineFallbackSyncService._();

  /// Progress notifier for UI
  final ValueNotifier<SyncProgress> progress =
      ValueNotifier(const SyncProgress());

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  Timer? _autoSyncTimer;

  /// Tables to sync, ordered by dependency (parents before children).
  /// Names MUST match the actual Drift-generated SQLite table names.
  static const _syncTables = [
    // ── Master / Reference data ──
    'settings',
    'regions',
    'branches',
    'warehouses',
    'units',
    'categories',
    'parties',
    'products',
    'product_barcodes',
    'product_units',
    'product_batches',
    'inventory_balances',
    'warehouse_prices',
    'safes',
    // ── Accounting structure ──
    'cost_centers',
    'fiscal_years',
    'accounting_periods',
    'accounts',
    'account_mappings',
    // ── Document sequences (counter continuity) ──
    'document_sequences',
    // ── Shifts ──
    'shifts',
    // ── Sales (invoices + items) ──
    'sales_invoices',
    'sales_invoice_items',
    // ── Purchases (invoices + items) ──
    'purchase_invoices',
    'purchase_invoice_items',
    // ── Treasury / Safe transactions ──
    'safe_transactions',
    // ── Inventory movements ──
    'stock_movements',
    'inventory_bonds',
    'inventory_bond_items',
    // ── Stock audits ──
    'stock_audits',
    'stock_audit_items',
    // ── Accounting entries ──
    'journal_entries',
    'journal_entry_lines',
    // ── Commercial Papers ──
    'commercial_papers',
    'paper_status_history',
    // ── HR ──
    'employees',
    'employee_transactions',
    'salary_payments',
    'employee_attendance',
    // ── Kitchen / Restaurant ──
    'work_orders',
    'work_order_items',
    'restaurant_tables',
    'table_orders',
    'table_order_items',
    // ── Held orders ──
    'held_orders',
    'held_order_items',
    // ── Offers ──
    'offers',
    'offer_items',
    // ── Quotations ──
    'quotations',
    'quotation_items',
    // ── Audit trail ──
    'activity_logs',
    // ── Region access control ──
    'user_region_access',
  ];

  /// Start a periodic auto-sync timer that attempts to push offline data
  /// to PostgreSQL every 60 seconds when in offline fallback mode.
  void startAutoSync(AppDatabase localDb) {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      if (!PostgresConfig.isOfflineFallback || _isSyncing) return;

      // Quick connectivity check before attempting full sync
      try {
        final pgConfig = await PostgresConfig.load();
        final error = await testPostgresConnection(pgConfig);
        if (error == null) {
          debugPrint('[OfflineSync] Auto-sync: server reachable, starting sync...');
          final success = await syncToPostgres(localDb);
          if (success) {
            debugPrint('[OfflineSync] Auto-sync completed successfully!');
          }
        }
      } catch (e) {
        debugPrint('[OfflineSync] Auto-sync check failed: $e');
      }
    });
    debugPrint('[OfflineSync] Auto-sync timer started (60s interval)');
  }

  /// Stop the auto-sync timer
  void stopAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
  }

  /// Run the full sync from local SQLite to PostgreSQL.
  ///
  /// Returns true if all data was synced successfully.
  /// The [localDb] should be the current active SQLite database.
  Future<bool> syncToPostgres(AppDatabase localDb) async {
    if (_isSyncing) return false;
    _isSyncing = true;

    final offlineStart = PostgresConfig.offlineFallbackStart;
    if (offlineStart == null) {
      debugPrint('[OfflineSync] No offline start timestamp — nothing to sync');
      _isSyncing = false;
      return true;
    }

    AppDatabase? pgDb;
    int totalRowsSynced = 0;

    try {
      // 1. Test connectivity
      progress.value = const SyncProgress(currentTable: 'اختبار الاتصال...');
      final pgConfig = await PostgresConfig.load();
      final error = await testPostgresConnection(pgConfig);
      if (error != null) {
        progress.value = SyncProgress(
          error: 'السيرفر غير متاح: $error',
          isDone: true,
        );
        _isSyncing = false;
        return false;
      }

      // 2. Open temporary PostgreSQL database
      pgDb = AppDatabase.withExecutor(
        openPostgresConnection(pgConfig),
        isPostgres: true,
      );

      // 3. Sync each table
      const tables = _syncTables;
      final totalTables = tables.length;

      for (int i = 0; i < tables.length; i++) {
        final tableName = tables[i];
        progress.value = SyncProgress(
          currentTable: tableName,
          tablesCompleted: i,
          tablesTotal: totalTables,
          rowsSynced: totalRowsSynced,
        );

        try {
          final count = await _syncTable(localDb, pgDb, tableName, offlineStart);
          totalRowsSynced += count;
          if (count > 0) {
            debugPrint('[OfflineSync] ✅ $tableName: $count rows synced');
          }
        } catch (e) {
          // Log but continue with next table — don't abort for non-critical tables
          debugPrint('[OfflineSync] ⚠️ $tableName failed: $e');
        }
      }

      // 4. Mark sync complete
      await PostgresConfig.setOfflineFallback(false);
      stopAutoSync();
      progress.value = SyncProgress(
        tablesCompleted: totalTables,
        tablesTotal: totalTables,
        rowsSynced: totalRowsSynced,
        isDone: true,
      );
      debugPrint('[OfflineSync] ✅ Sync complete: $totalRowsSynced total rows');
      _isSyncing = false;
      return true;
    } catch (e) {
      debugPrint('[OfflineSync] ❌ Sync failed: $e');
      progress.value = SyncProgress(
        error: e.toString(),
        isDone: true,
        rowsSynced: totalRowsSynced,
      );
      _isSyncing = false;
      return false;
    } finally {
      // Close the temporary PostgreSQL connection
      try {
        await pgDb?.close();
      } catch (_) {}
    }
  }

  /// Sync a single table: SELECT from SQLite WHERE created_at >= offlineStart,
  /// then UPSERT into PostgreSQL using batch operations inside a single transaction.
  Future<int> _syncTable(
    AppDatabase localDb,
    AppDatabase pgDb,
    String tableName,
    DateTime offlineStart,
  ) async {
    // 1. Quick existence check — skip if table doesn't exist in SQLite
    final tableCheck = await localDb.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      variables: [Variable.withString(tableName)],
    ).get();
    if (tableCheck.isEmpty) return 0;

    // 2. Get column metadata
    final pragma = await localDb.customSelect(
      'PRAGMA table_info($tableName)',
    ).get();
    if (pragma.isEmpty) return 0;

    final columns = pragma.map((r) => r.read<String>('name')).toList();
    final hasCreatedAt = columns.contains('created_at');
    final columnList = columns.join(', ');

    // 3. COUNT-first check — skip tables with 0 new rows (instant)
    final epochSeconds = offlineStart.millisecondsSinceEpoch ~/ 1000;
    final hasUpdatedAt = columns.contains('updated_at');

    if (hasCreatedAt) {
      String countSql = 'SELECT COUNT(*) as cnt FROM $tableName WHERE created_at >= ?';
      if (hasUpdatedAt) {
        countSql += ' OR updated_at >= ?';
      }
      final countVars = hasUpdatedAt
          ? [Variable.withInt(epochSeconds), Variable.withInt(epochSeconds)]
          : [Variable.withInt(epochSeconds)];

      final countResult = await localDb.customSelect(
        countSql,
        variables: countVars,
      ).getSingle();

      if ((countResult.read<int>('cnt')) == 0) return 0;
    }

    // 4. Fetch the rows to sync
    List<QueryRow> rows;
    if (hasCreatedAt) {
      String fetchSql = 'SELECT $columnList FROM $tableName WHERE created_at >= ?';
      if (hasUpdatedAt) {
        fetchSql += ' OR updated_at >= ?';
      }
      final fetchVars = hasUpdatedAt
          ? [Variable.withInt(epochSeconds), Variable.withInt(epochSeconds)]
          : [Variable.withInt(epochSeconds)];

      rows = await localDb.customSelect(
        fetchSql,
        variables: fetchVars,
      ).get();
    } else {
      // For tables without created_at (settings, document_sequences)
      rows = await localDb.customSelect(
        'SELECT $columnList FROM $tableName',
      ).get();
    }
    if (rows.isEmpty) return 0;

    // 5. Build UPSERT template once (reused for all rows)
    final hasId = columns.contains('id');
    final isDocSequence = tableName == 'document_sequences';
    final isSettings = tableName == 'settings';

    // Determine conflict clause
    String conflictClause;
    if (isDocSequence) {
      conflictClause = 'ON CONFLICT (prefix) DO UPDATE SET next_value = '
          'GREATEST($tableName.next_value, EXCLUDED.next_value)';
    } else if (isSettings) {
      // Settings uses key as PK
      final updateCols = columns.where((c) => c != 'key').map((c) => '$c = EXCLUDED.$c').join(', ');
      conflictClause = 'ON CONFLICT (key) DO UPDATE SET $updateCols';
    } else if (hasId) {
      final updateCols = columns.where((c) => c != 'id').map((c) => '$c = EXCLUDED.$c').join(', ');
      conflictClause = 'ON CONFLICT (id) DO UPDATE SET $updateCols';
    } else {
      conflictClause = 'ON CONFLICT DO NOTHING';
    }

    // 6. Execute all upserts inside a single PostgreSQL transaction
    int synced = 0;
    await pgDb.transaction(() async {
      for (final row in rows) {
        final values = <String>[];
        final variables = <Variable>[];

        for (final col in columns) {
          final val = row.data[col];
          if (val == null) {
            values.add('NULL');
          } else if (val is int) {
            values.add('?');
            variables.add(Variable.withInt(val));
          } else if (val is double) {
            values.add('?');
            variables.add(Variable.withReal(val));
          } else if (val is String) {
            values.add('?');
            variables.add(Variable.withString(val));
          } else {
            values.add('?');
            variables.add(Variable.withString(val.toString()));
          }
        }

        final placeholders = values.join(', ');
        final sql = 'INSERT INTO $tableName ($columnList) '
            'VALUES ($placeholders) $conflictClause';

        try {
          await pgDb.customStatement(sql, variables);
          synced++;
        } catch (e) {
          debugPrint('[OfflineSync] Row error in $tableName: $e');
        }
      }
    });

    return synced;
  }
}

