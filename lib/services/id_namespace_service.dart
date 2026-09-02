import 'package:drift/drift.dart' show Variable;
import 'package:flutter/foundation.dart';
import '../core/logging/diagnostic_logger.dart';
import '../data/database/database.dart';

/// Client-side ID namespace separation.
///
/// Problem: In client mode, a fresh local SQLite DB starts `sqlite_sequence`
/// at zero for every auto-increment table. The moment the user creates a
/// row offline, SQLite picks `id = 1`. Meanwhile the server has its own
/// parties/products/... at the low end of the integer space. When DeltaPull
/// fetches them, `INSERT OR REPLACE INTO parties (id = 1, global_id = ...)`
/// clobbers the local offline row because the two shared the same numeric
/// id but carry different `global_id`s (different real-world entities).
///
/// Solution: client-originated rows are ALWAYS assigned ids at or above
/// [clientIdFloor] (1 billion). Server ids stay below. They cannot collide.
/// `global_id` (UUIDv7) remains the cross-install canonical identity; the
/// `remote_id_mappings` table bridges local <-> remote numeric ids for
/// outbox replay.
///
/// This file ships two pieces of the fix:
///   1. [ensureClientFloor] — at client-mode startup, bump `sqlite_sequence`
///      for every auto-increment table to `>= clientIdFloor`. New auto-id
///      inserts land in the safe range from now on.
///   2. [renumberLocalRow] — called on-demand by DeltaPull's upsert path
///      when a server row arrives with an id already occupied locally by
///      a row carrying a different `global_id`. The local row is moved to
///      a fresh high id and every FK pointing at it is cascaded, under
///      `defer_foreign_keys` in a transaction so intermediate states do
///      not trip constraints.
class IdNamespaceService {
  IdNamespaceService._();
  static final IdNamespaceService instance = IdNamespaceService._();

  /// Local auto-id lower bound for client mode. Chosen to leave the entire
  /// 32-bit positive range 1..~2.1B available for the server, and still
  /// keep ~1.1B ids per client before rolling over.
  static const int clientIdFloor = 1000000000; // 1 billion

  /// Tables whose `id` column is auto-incremented AND whose rows travel
  /// over the sync channel. Anything in this list gets its sequence
  /// bumped to [clientIdFloor] on client-mode boot.
  ///
  /// Mirrors the union of [DeltaPullService.pullTables] with a handful of
  /// local-only auto-id tables that nevertheless reach the server via
  /// outbox replay (shifts, held_orders, …).
  static const List<String> namespacedTables = [
    'fiscal_years', 'cost_centers', 'accounts', 'roles', 'currencies',
    'categories', 'units', 'regions', 'party_groups', 'safes', 'printers',
    'accounting_periods', 'branches', 'warehouses', 'price_lists', 'users',
    'shifts', 'parties', 'products', 'price_list_items', 'product_barcodes',
    'product_units',
    'sales_invoices', 'purchase_invoices', 'held_orders', 'sales_orders',
    'purchase_orders', 'quotations', 'payments', 'journal_entries',
    'safe_transactions', 'commercial_papers', 'stock_movements',
    'sales_invoice_items', 'purchase_invoice_items', 'held_order_items',
    'sales_order_items', 'purchase_order_items', 'quotation_items',
    'payment_allocations',
    // §٦‑٢ (v172) — مستندُ مرتجع الشراء. بلا أرضيّةِ ترقيمٍ يبدأ العميلُ من ١
    // فيصطدم صفُّه بصفِّ الخادم على نفس الرقم.
    'purchase_returns',

    // ── v166 / المرحلة ٢ — مستنداتُ الأثر المحاسبيّ ──
    //
    // ⚠️ هذه الكتلةُ **فاتت** المرحلةَ ٢: اثنا عشرَ جدولاً دخلت
    // `pullTables` ولم تدخل هنا، ومعها `activity_logs` من قبلها. والعقدُ
    // المعلَنُ في وثيقةِ القائمة أعلاه هو «اتّحادُ `pullTables` مع حفنةِ
    // جداولٍ محلّيّة» — فالفجوةُ انحرافٌ لا تصميم.
    //
    // وأثرُها ليس ضياعَ بيانات: حارسُ التصادم في `_upsertRow` عامٌّ لكلِّ
    // جدولٍ ويستدعي [renumberLocalRow] عند الحاجة. لكنّه علاجٌ **بعد**
    // وقوعِ التصادم، وثمنُه إعادةُ ترقيمٍ تُتابِع كلَّ مفتاحٍ يشير للصفّ
    // داخلَ معاملة. والأرضيّةُ تمنع التصادمَ أصلاً.
    'activity_logs',
    'asset_categories', 'op_expense_categories', 'bill_of_materials',
    'fixed_assets', 'manufacturing_orders', 'bom_components',
    'op_expenses', 'asset_depreciations', 'mfg_order_costs',
    'landed_cost_sheets', 'landed_cost_items', 'landed_cost_allocations',

    // ── v167 / المرحلة ٣ — الفئةُ التشغيليّة ──
    'employees',
    'table_sections', 'restaurant_tables', 'table_orders',
    'table_order_items', 'table_reservations', 'table_order_payments',
    'kitchen_stations', 'category_station_mappings',
    'work_orders', 'work_order_items',
    'booking_resources', 'booking_services', 'bookings', 'booking_reminders',
    'sales_routes', 'route_visits', 'sales_rep_targets',
    'sales_rep_collections',

    // ── v173 / المرحلة ٤ — السجلُّ الرقابيُّ والتشغيلُ العابر ──
    'loyalty_programs', 'delivery_companies', 'couriers',
    'customer_loyalty_points', 'loyalty_transactions',
    'warehouse_prices',
    'cycle_count_plans', 'cycle_count_tasks', 'cycle_count_items',
    'stock_audits', 'stock_audit_items',
    'stock_requisitions', 'stock_requisition_items',
    'bank_reconciliations', 'bank_statement_lines',
    'e_invoice_submissions', 'e_invoice_status_log',
    'field_audit_logs', 'failed_autoposts',
    'approval_workflows', 'approval_steps', 'approval_requests',
    'approval_decisions', 'sod_conflicts', 'sod_violations',
    'compliance_checks',
  ];

  /// Raise the `sqlite_sequence` row for every namespaced table to
  /// `MAX(current, clientIdFloor)`. Idempotent.
  ///
  /// Must run AFTER Drift opens the DB and BEFORE the first local write
  /// or DeltaPull cycle. Wire from `main.dart` right after
  /// `ClientWriteInterceptor.initialize(...)`.
  Future<void> ensureClientFloor(AppDatabase db) async {
    int bumped = 0;
    for (final table in namespacedTables) {
      try {
        final row = await db.customSelect(
          'SELECT seq FROM sqlite_sequence WHERE name = ? LIMIT 1',
          variables: [Variable.withString(table)],
        ).getSingleOrNull();
        final current = row?.read<int?>('seq') ?? 0;
        if (current >= clientIdFloor) continue;
        if (row == null) {
          await db.customStatement(
            'INSERT INTO sqlite_sequence (name, seq) VALUES (?, ?)',
            [table, clientIdFloor],
          );
        } else {
          await db.customStatement(
            'UPDATE sqlite_sequence SET seq = ? WHERE name = ?',
            [clientIdFloor, table],
          );
        }
        bumped++;
      } catch (e) {
        debugPrint('[IdNamespace] skip bump for $table: $e');
      }
    }
    debugPrint('[IdNamespace] floor=$clientIdFloor applied to $bumped/${namespacedTables.length} tables');

    // Spec 136 ISS-22 — surface the floor result (and the sales_invoices
    // sequence specifically) in the persistent log. If a fresh offline sale
    // still gets a low id, this line proves whether the floor was applied —
    // the field bug was offline invoices at ids 1,2,3… colliding with server
    // ids and getting clobbered on DeltaPull (→ vanished invoice + shift
    // variance).
    int? salesSeq;
    try {
      final r = await db.customSelect(
        "SELECT seq FROM sqlite_sequence WHERE name = 'sales_invoices' LIMIT 1",
      ).getSingleOrNull();
      salesSeq = r?.read<int?>('seq');
    } catch (_) {/* diagnostic only */}
    await DiagnosticLogger.log(
      'ID-FLOOR',
      'floor=$clientIdFloor bumped=$bumped/${namespacedTables.length} '
      'sales_invoices_seq=${salesSeq ?? '-'}',
    );
  }

  /// Move a local row from `oldId` to a fresh id in the safe range, then
  /// cascade the change through every FK column that references this
  /// table. Returns the new id.
  ///
  /// Runs inside a single transaction with `PRAGMA defer_foreign_keys`
  /// so that the parent row can be updated before its children without
  /// tripping the foreign-key constraint mid-transaction.
  Future<int> renumberLocalRow(AppDatabase db, String table, int oldId) async {
    final newId = await _pickFreeHighId(db, table, oldId);
    final fks = await _findReferencingFks(db, table);

    await db.transaction(() async {
      await db.customStatement('PRAGMA defer_foreign_keys = ON');
      await db.customStatement(
        'UPDATE "$table" SET id = ? WHERE id = ?',
        [newId, oldId],
      );
      for (final ref in fks) {
        await db.customStatement(
          'UPDATE "${ref.childTable}" SET "${ref.childColumn}" = ? '
          'WHERE "${ref.childColumn}" = ?',
          [newId, oldId],
        );
      }
    });

    debugPrint(
      '[IdNamespace] renumbered $table #$oldId → #$newId '
      '(cascaded ${fks.length} FK column${fks.length == 1 ? '' : 's'})',
    );
    return newId;
  }

  /// Return an unused id >= [clientIdFloor] for [table]. Starts from the
  /// current `MAX(id) + 1` (or the floor, whichever is larger) and scans
  /// upward for a gap so repeated renumbers don't stomp each other.
  Future<int> _pickFreeHighId(AppDatabase db, String table, int oldId) async {
    final maxRes = await db.customSelect(
      'SELECT COALESCE(MAX(id), 0) AS m FROM "$table"',
    ).getSingle();
    final currentMax = maxRes.read<int>('m');
    int candidate = currentMax >= clientIdFloor
        ? currentMax + 1
        : clientIdFloor + oldId;
    for (int attempt = 0; attempt < 10000; attempt++) {
      final taken = await db.customSelect(
        'SELECT 1 FROM "$table" WHERE id = ? LIMIT 1',
        variables: [Variable.withInt(candidate)],
      ).getSingleOrNull();
      if (taken == null) return candidate;
      candidate++;
    }
    // Extreme edge case — give up and use a very high number.
    return clientIdFloor + DateTime.now().microsecondsSinceEpoch % 1000000000;
  }

  Future<List<_FkRef>> _findReferencingFks(AppDatabase db, String parentTable) async {
    final refs = <_FkRef>[];
    try {
      final tables = await db.customSelect(
        "SELECT name FROM sqlite_master "
        "WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
      ).get();
      for (final row in tables) {
        final tname = row.read<String>('name');
        try {
          final fks = await db.customSelect(
            'PRAGMA foreign_key_list("$tname")',
          ).get();
          for (final fk in fks) {
            if (fk.read<String>('table') == parentTable) {
              refs.add(_FkRef(
                childTable: tname,
                childColumn: fk.read<String>('from'),
              ));
            }
          }
        } catch (_) {
          // Not a real user table (view, virtual, etc.) — skip.
        }
      }
    } catch (e) {
      debugPrint('[IdNamespace] FK introspection failed: $e');
    }
    return refs;
  }
}

class _FkRef {
  final String childTable;
  final String childColumn;
  _FkRef({required this.childTable, required this.childColumn});
}
