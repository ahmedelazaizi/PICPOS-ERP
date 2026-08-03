import 'dart:async';
import 'package:drift/drift.dart' show TableUpdate, UpdateKind, Variable;
import 'package:flutter/foundation.dart';
import '../data/database/database.dart';
import '../core/logging/diagnostic_logger.dart';
import 'conflict_resolution_service.dart';
import 'id_namespace_service.dart';
import 'security_service.dart';
import 'server_proxy.dart';
import 'sync_event_bus.dart';

/// P3.1 + P4.3 — Delta Pull Service
///
/// Pulls master-data changes from the server since the last recorded watermark
/// and upserts them into local SQLite. Transaction tables (invoices, payments)
/// are owned by the client's outbox and are NOT pulled here.
///
/// After each successful table pull:
///  - emits [SyncTablePulled] on [SyncEventBus] for UI widgets
///  - calls [AppDatabase.notifyUpdates] so Drift watch() queries react
///
/// Watermarks are stored in the settings table as epoch-second strings under
/// keys of the form `_watermark__<tableName>`.
class DeltaPullService {
  DeltaPullService._();
  static final DeltaPullService instance = DeltaPullService._();

  AppDatabase? _db;
  bool _isPulling = false;

  /// All sync-hardened tables are pulled via delta. Order matters: parents
  /// must appear before their children so that FK references resolve on the
  /// client during upsert. The list mirrors the FK dependency graph that
  /// `SyncService._strategies` uses for ordered fullSync.
  ///
  /// Mirrors the server's `_syncPullTables` allowlist in api_handler.dart.
  static const List<String> pullTables = [
    // ── Tier 0: no FK dependencies ──
    'fiscal_years',
    'cost_centers',
    'accounts',
    'roles',
    'currencies',
    'categories',
    'units',
    'regions',
    'party_groups',
    'safes',
    'printers',

    // ── Tier 1: depend on Tier 0 ──
    'accounting_periods',   // → fiscal_years
    'branches',             // → regions, cost_centers
    'warehouses',           // → branches
    'price_lists',          // → currencies
    'users',                // → roles
    'shifts',
    'activity_logs',        // → users; central audit trail from all clients

    // ── Tier 2: depend on Tier 1 ──
    'parties',              // → accounts, party_groups
    'products',             // → categories, units
    'price_list_items',     // → price_lists, products
    'product_barcodes',     // → products
    'product_units',        // → products, units

    // ── Tier 3: transactional headers ──
    'sales_invoices',       // → parties, warehouses
    'purchase_invoices',    // → parties, warehouses
    'held_orders',          // → parties
    'sales_orders',         // → parties, warehouses
    'purchase_orders',      // → parties, warehouses
    'quotations',           // → parties
    'payments',             // → parties, safes
    'journal_entries',      // → accounts
    'safe_transactions',    // → safes
    'commercial_papers',    // → parties
    'stock_movements',      // → products, warehouses

    // ── Tier 4: transactional items ──
    'sales_invoice_items',     // → sales_invoices, products
    'purchase_invoice_items',  // → purchase_invoices, products
    'held_order_items',        // → held_orders, products
    'sales_order_items',       // → sales_orders, products
    'purchase_order_items',    // → purchase_orders, products
    'quotation_items',         // → quotations, products
    'payment_allocations',     // → payments
  ];

  /// Spec 151 P1-8b — the TRANSACTIONAL delta-pull tables (Tier 3 + Tier 4 +
  /// shift/audit movement tables). The server's `/api/sync/pull` denies every
  /// one of these to a caller with no `X-Session-Token` (see
  /// `_transactionalPullTables` in api_handler.dart — kept in sync with THIS
  /// set). A tokenless client (pre-login) therefore SKIPs them: pulling would
  /// return nothing AND — worse — seeding/advancing their watermark to "now"
  /// would make the post-login pull ask only for rows after now and silently
  /// drop the entire pre-login backlog (the reverted BLOCKER). Left unpulled
  /// and unseeded, DeltaPull backfills them from `since = null` (a full dump)
  /// once a token exists (post-login, scoped to the user's branch; a mirror
  /// mints an admin token at pairing → full). Master/reference tables are
  /// unaffected and provision normally tokenless.
  static const Set<String> branchScopedPullTables = {
    'sales_invoices', 'purchase_invoices', 'held_orders', 'sales_orders',
    'purchase_orders', 'quotations', 'payments', 'journal_entries',
    'safe_transactions', 'commercial_papers', 'stock_movements', 'shifts',
    'activity_logs', 'sales_invoice_items', 'purchase_invoice_items',
    'held_order_items', 'sales_order_items', 'purchase_order_items',
    'quotation_items', 'payment_allocations',
  };

  /// المرحلة ١ (W1) — الجداول الأساسية التي صار الخادم يقصّها على الفرع
  /// (`api_handler._syncPullBranchColumn` + الاشتقاق العكسي لمراكز
  /// التكلفة).
  ///
  /// **منفصلة عمداً عن [branchScopedPullTables]،** فتلك تصف عقداً آخر —
  /// قائمة منع الـtokenless التعاملية، ويثبّتها اختبار تساوٍ صارم مع
  /// نظيرتها على الخادم. خلط المجموعتين يكسر ذلك العقد.
  ///
  /// الفرق في الأثر: الجداول التعاملية **تُتخطّى** كلياً قبل الدخول،
  /// أما هذه فتُسحَب عادياً — التزويد يعتمد عليها — ويُمنع فقط **تقديم
  /// الـwatermark**. لولا ذلك: الخادم يقصّ الرد على سنتينل `-1` للمستدعي
  /// بلا هوية، والعميل يحفظ watermark على رد مقصوص، فيسأل بعد الدخول
  /// عمّا هو أحدث منه فقط وتضيع الصفوف الأقدم نهائياً. وهذا يتكرر عند
  /// **كل إقلاع**، لا عند التزويد الأوّلي فحسب.
  static const Set<String> branchScopedMasterPullTables = {
    'branches', 'warehouses', 'safes', 'cost_centers',
  };

  /// Single source of truth for the watermark guard's decision (used by
  /// [pullTable] below). Extracted so a test can pin the actual *behaviour* —
  /// not just the contents of the two sets it reads — without mocking the
  /// whole pull. A tokenless caller must withhold the watermark for both the
  /// transactional denylist AND the branch-scoped master tables (W1); a
  /// caller with a token, or a table in neither set, never withholds.
  @visibleForTesting
  static bool shouldWithholdWatermark(String table,
          {required bool hasSessionToken}) =>
      !hasSessionToken &&
      (branchScopedPullTables.contains(table) ||
          branchScopedMasterPullTables.contains(table));

  void initialize(AppDatabase db) {
    _db = db;
    ConflictResolutionService.instance.initialize(db);
  }

  /// Test-only entry to the otherwise-private inbound upsert path, so an
  /// integration test can exercise DeltaPull row handling (notably the
  /// server→local party-FK remap) without standing up a server / ServerProxy.
  /// Production code never calls this — use [pullTable] / [pullAll].
  @visibleForTesting
  Future<void> upsertRowForTest(String table, Map<String, dynamic> row) =>
      _upsertRow(table, row);

  /// Pull all [pullTables] sequentially. No-op if already pulling.
  Future<void> pullAll() async {
    if (_isPulling || _db == null) return;
    _isPulling = true;
    SyncEventBus.instance.isPulling.value = true;
    SyncEventBus.instance.emit(const SyncPullStarted());
    int totalRows = 0;
    try {
      for (final table in pullTables) {
        totalRows += await pullTable(table);
      }
    } finally {
      _isPulling = false;
      SyncEventBus.instance.isPulling.value = false;
      SyncEventBus.instance.emit(SyncPullCompleted(totalRows));
    }
  }

  /// Pull a specific list of tables sequentially.
  /// Used by shift-close pre-flight to sync the tables that affect
  /// closing aggregates before the report is calculated.
  Future<void> pullMultiple(List<String> tables) async {
    for (final table in tables) {
      await pullTable(table);
    }
  }

  /// Pull a single table. Returns the number of rows applied.
  /// Safe to call directly (e.g. from WebSocket data_changed).
  Future<int> pullTable(String table) async {
    // Spec 151 P1-8b — a branch-scoped transactional table can't be pulled
    // without a session token: the server fail-closes it to zero rows. Skip
    // it entirely (do NOT fetch, do NOT advance its watermark) until a token
    // exists post-login, so DeltaPull backfills the full backlog then.
    if (branchScopedPullTables.contains(table) &&
        !ServerProxy.instance.hasSessionToken()) {
      debugPrint('[DeltaPull] $table skipped — no session token '
          '(branch-scoped; will backfill after login)');
      return 0;
    }
    try {
      final since = await _loadWatermark(table);

      // ── Paged drain ─────────────────────────────────────────────────────
      // The server now bounds every /api/sync/pull response (it used to
      // return the whole table, which froze both ends). Loop pages with a
      // keyset cursor and only advance the watermark AFTER the last page
      // lands — if the loop is interrupted the watermark stays put and the
      // next pull safely re-fetches from the same point (upserts are
      // idempotent).
      var totalApplied = 0;
      int? cursorTs;
      int? cursorId;
      int? serverTime;
      var pages = 0;
      // Only a loop that reached the server's last page may advance the
      // watermark. Any other exit — page cap, network failure, or a row we
      // cannot build a cursor from — must leave it untouched, or the rows we
      // never fetched would be skipped forever.
      var drainedFully = false;

      while (true) {
        if (pages >= _maxPagesPerPull) {
          // Leave the watermark unadvanced so the remainder is picked up on
          // the next cycle rather than silently dropped.
          debugPrint('[DeltaPull] $table: hit page cap ($_maxPagesPerPull) — '
              'remainder deferred to next pull');
          unawaited(DiagnosticLogger.log(
            'DELTA-PULL-CAP',
            'table=$table pages=$pages applied=$totalApplied '
                '— watermark NOT advanced, remainder deferred',
          ));
          return totalApplied;
        }
        pages++;

        final result = await ServerProxy.instance.fetchDelta(
          table,
          since: since,
          limit: _pullPageSize,
          cursorTs: cursorTs,
          cursorId: cursorId,
        );
        // Network/HTTP failure — do NOT advance the watermark.
        if (result == null) return totalApplied;

        final rows =
            (result['rows'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        // Take the clock from the FIRST page. Rows modified while we page
        // through are then re-fetched next cycle instead of being skipped.
        serverTime ??= result['serverTime'] as int?;

        if (rows.isNotEmpty) {
          await _applyRowsChunked(table, rows);
          totalApplied += rows.length;

          // Notify Drift watch() streams so reactive queries re-fire
          // automatically.
          _db!.notifyUpdates({
            TableUpdate(table, kind: UpdateKind.insert),
            TableUpdate(table, kind: UpdateKind.update),
          });
          // Broadcast to SyncEventBus for higher-level UI subscribers
          SyncEventBus.instance.emit(SyncTablePulled(table, rows.length));
          debugPrint('[DeltaPull] $table: applied ${rows.length} rows '
              '(page $pages)');

          // Defensive numeric reads: the wire type varies by server backend
          // (SQLite hands back an int, Postgres can surface a num), and a hard
          // `as int` cast on the wrong one would throw mid-drain.
          final last = rows.last;
          cursorTs = _asInt(last['last_modified_at']) ?? 0;
          cursorId = _asInt(last['id']);
        }

        final hasMore = result['hasMore'] == true;
        if (!hasMore || rows.isEmpty) {
          drainedFully = true;
          break;
        }
        if (cursorId == null) {
          // The server says there is more, but the last row carries no usable
          // id, so the next page cannot be addressed. Stop WITHOUT advancing
          // the watermark so nothing is silently dropped.
          debugPrint('[DeltaPull] $table: hasMore but no cursor id — '
              'watermark NOT advanced');
          unawaited(DiagnosticLogger.log(
            'DELTA-PULL-CURSOR',
            'table=$table hasMore=true but last row had no int id — '
                'watermark NOT advanced, remainder deferred',
          ));
          break;
        }
      }

      if (serverTime != null && drainedFully) {
        // Spec 151 P1-8b watermark guard (defense-in-depth). The early skip
        // above already prevents a branch-scoped tokenless pull from reaching
        // here, but re-check so a future caller that bypasses the skip can
        // never advance a branch-scoped table's watermark on a tokenless pull
        // (which returned zero rows) and strand its backlog.
        //
        // المرحلة ١ (W1) — وُسِّع ليشمل الجداول الأساسية المحصورة. تلك
        // لا تُتخطّى مبكراً (التزويد يحتاجها)، فهذا الحارس هو دفاعها
        // **الوحيد**: بلا هوية يقصّها الخادم على سنتينل `-1`، فحفظ
        // watermark على ذلك الرد يُسقِط الصفوف الأقدم نهائياً.
        //
        // القرار نفسه مُستخرَج في [shouldWithholdWatermark] — تعبير واحد
        // فقط عن القاعدة، ومختبَر مباشرة بدل تخمينه من محتوى المجموعتين.
        final withhold = shouldWithholdWatermark(table,
            hasSessionToken: ServerProxy.instance.hasSessionToken());
        if (!withhold) {
          await _saveWatermark(table, serverTime);
        }
      }
      return totalApplied;
    } catch (e) {
      debugPrint('[DeltaPull] $table error: $e');
      return 0;
    }
  }

  /// Lenient int read for wire values that may arrive as `int`, `num` or a
  /// numeric `String` depending on the server's database backend.
  static int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  /// Rows requested per `/api/sync/pull` page.
  static const int _pullPageSize = 500;

  /// Rows applied per local write transaction. The whole page used to land in
  /// ONE `transaction()`, so a large pull held a write lock and blocked the
  /// UI isolate for the entire batch — the visible "client freeze". Chunking
  /// plus an event-loop yield between chunks keeps the app responsive while a
  /// backlog drains.
  static const int _applyChunkSize = 100;

  /// Safety valve on the paging loop so a server that always answers
  /// `hasMore: true` (bad clock, cursor bug) cannot spin forever. At the
  /// default page size this still drains 100k rows per pull.
  static const int _maxPagesPerPull = 200;

  /// Apply [rows] in bounded transactions, yielding to the event loop between
  /// chunks so Drift stream listeners and the UI get a turn.
  Future<void> _applyRowsChunked(
    String table,
    List<Map<String, dynamic>> rows,
  ) async {
    for (var start = 0; start < rows.length; start += _applyChunkSize) {
      final end = (start + _applyChunkSize) > rows.length
          ? rows.length
          : start + _applyChunkSize;
      final chunk = rows.sublist(start, end);
      await _db!.transaction(() async {
        for (final row in chunk) {
          await _upsertRow(table, row);
        }
      });
      // Hand the event loop back between chunks.
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> _upsertRow(String table, Map<String, dynamic> row) async {
    // Feature 006 / MM.E hot-fix: journal_entries arrives with its child
    // lines embedded under `lines`. Pop them out BEFORE the generic
    // INSERT OR REPLACE so the column list doesn't see a non-column key,
    // then replay them into journal_entry_lines after the header lands.
    // journal_entry_lines has no last_modified_at column of its own and
    // can't ride the generic delta-pull path — without this, the GL
    // screen on mirror / client showed entry headers with empty
    // debit/credit columns.
    final List? embeddedJournalLines =
        (table == 'journal_entries' && row['lines'] is List)
            ? row.remove('lines') as List
            : null;

    final serverId = row['id'] is int ? row['id'] as int : null;
    final globalId = row['global_id'] is String ? row['global_id'] as String : null;

    // Resolve the local id for this server row. For master tables the client
    // adopts the server id directly (local_id == server_id). For rows this
    // client originally created offline, the outbox replay assigned a server
    // id that differs from the local id — we must find the local row via its
    // stable UUID (`global_id`) so that dependent FKs remain intact.
    int? localId = serverId;
    bool foundByGlobalId = false;
    if (globalId != null && globalId.isNotEmpty && serverId != null) {
      try {
        final existing = await _db!.customSelect(
          'SELECT id FROM $table WHERE global_id = ? LIMIT 1',
          variables: [Variable.withString(globalId)],
        ).getSingleOrNull();
        final existingLocalId = existing?.read<int?>('id');
        if (existingLocalId != null) {
          foundByGlobalId = true;
          if (existingLocalId != serverId) {
            localId = existingLocalId;
            // Persist the mapping so FK references in outbox payloads resolve
            // consistently on the next replay.
            await _db!.storeFkMapping(
              tableName: table,
              localId: existingLocalId,
              remoteId: serverId,
              globalId: globalId,
            );
          }
        }
      } catch (e) {
        // Table may not carry `global_id`, or query may fail for other
        // reasons — fall back to id-based upsert below.
        debugPrint('[DeltaPull] global_id lookup $table failed (will fall back): $e');
      }
    }

    // ── Natural-key fallback ───────────────────────────────────────────
    // When a server row's globalId doesn't match any local row, the next
    // line would INSERT OR REPLACE by id — creating a duplicate if the
    // client already has a row with the same natural key (code/barcode
    // for products, phone+name for parties, name for branches/warehouses)
    // but a NULL or different globalId. That duplicate is the root cause
    // of the 3× كيلو ريش bug (and, for branches/warehouses, of BUG 5b's
    // duplicate "الفرع الرئيسي"/"المخزن الرئيسي"). Resolve by adopting
    // the server's globalId onto the existing local row so the
    // subsequent UPDATE merges cleanly.
    if (!foundByGlobalId && serverId != null && globalId != null && globalId.isNotEmpty) {
      try {
        int? naturalLocalId;
        if (table == 'products') {
          final code = row['code'] is String ? row['code'] as String : null;
          final barcode = row['barcode'] is String ? row['barcode'] as String : null;
          if (code != null && code.trim().isNotEmpty) {
            final hit = await _db!.customSelect(
              'SELECT id FROM products WHERE code = ? LIMIT 1',
              variables: [Variable.withString(code.trim())],
            ).getSingleOrNull();
            naturalLocalId = hit?.read<int?>('id');
          }
          if (naturalLocalId == null && barcode != null && barcode.trim().isNotEmpty) {
            final hit = await _db!.customSelect(
              'SELECT id FROM products WHERE barcode = ? LIMIT 1',
              variables: [Variable.withString(barcode.trim())],
            ).getSingleOrNull();
            naturalLocalId = hit?.read<int?>('id');
          }
        } else if (table == 'parties') {
          final code = row['code'] is String ? row['code'] as String : null;
          final name = row['name'] is String ? row['name'] as String : null;
          final phone = row['phone'] is String ? row['phone'] as String : null;
          if (code != null && code.trim().isNotEmpty) {
            final hit = await _db!.customSelect(
              'SELECT id FROM parties WHERE code = ? LIMIT 1',
              variables: [Variable.withString(code.trim())],
            ).getSingleOrNull();
            naturalLocalId = hit?.read<int?>('id');
          }
          if (naturalLocalId == null &&
              name != null && name.trim().isNotEmpty &&
              phone != null && phone.trim().isNotEmpty) {
            final hit = await _db!.customSelect(
              'SELECT id FROM parties WHERE name = ? AND phone = ? LIMIT 1',
              variables: [Variable.withString(name.trim()), Variable.withString(phone.trim())],
            ).getSingleOrNull();
            naturalLocalId = hit?.read<int?>('id');
          }
        } else if (table == 'branches') {
          // Spec 150 / BUG 5b — branches have no code/barcode, so the
          // (trimmed) name is the only natural key. Without this arm a
          // server-origin "الفرع الرئيسي" with a non-deterministic
          // globalId falls straight through to INSERT OR REPLACE and
          // duplicates the locally-seeded row of the same name.
          final name = row['name'] is String ? row['name'] as String : null;
          if (name != null && name.trim().isNotEmpty) {
            final hit = await _db!.customSelect(
              'SELECT id FROM branches WHERE name = ? LIMIT 1',
              variables: [Variable.withString(name.trim())],
            ).getSingleOrNull();
            naturalLocalId = hit?.read<int?>('id');
          }
        } else if (table == 'warehouses') {
          // Spec 150 / BUG 5b — same natural-key gap as branches, for
          // "المخزن الرئيسي".
          final name = row['name'] is String ? row['name'] as String : null;
          if (name != null && name.trim().isNotEmpty) {
            final hit = await _db!.customSelect(
              'SELECT id FROM warehouses WHERE name = ? LIMIT 1',
              variables: [Variable.withString(name.trim())],
            ).getSingleOrNull();
            naturalLocalId = hit?.read<int?>('id');
          }
        }
        if (naturalLocalId != null) {
          // Adopt the server's globalId onto this local row, then treat
          // it as the target of the upsert.
          await _db!.customStatement(
            'UPDATE $table SET global_id = ? WHERE id = ?',
            [globalId, naturalLocalId],
          );
          localId = naturalLocalId;
          await _db!.storeFkMapping(
            tableName: table,
            localId: naturalLocalId,
            remoteId: serverId,
            globalId: globalId,
          );
          debugPrint('[DeltaPull] natural-key merge $table: '
              'adopted globalId=$globalId onto localId=$naturalLocalId '
              '(serverId=$serverId) — prevented duplicate insert.');
        }
      } catch (e) {
        debugPrint('[DeltaPull] natural-key fallback $table failed: $e');
      }
    }

    // Soft-delete: server marks rows with deleted_at instead of hard-deleting
    if (row['deleted_at'] != null) {
      try {
        await _db!.customStatement(
          'UPDATE $table SET deleted_at = ? WHERE id = ?',
          [row['deleted_at'], localId],
        );
      } catch (_) {}
      return;
    }

    // Conflict check: skip if the local row is newer than the server row.
    // C-04: resolve the per-table policy instead of the blanket newerWins
    // default — server is SoT on client/mirror (R4), so server-authoritative
    // rows must serverWins-heal past a locally-bumped row_version.
    final apply = await ConflictResolutionService.instance.shouldApplyServerRow(
      table,
      row,
      policy: ConflictResolutionService.instance.policyForTable(table),
    );
    if (!apply) return;

    // Spec 136 (field 2026-06-14): remap server party FK → LOCAL party id on the
    // mirror's REAL inbound path. The SyncStrategy-layer party remap
    // (purchase/safe_transaction strategies) is DEAD CODE for client/mirror —
    // Tier-3 strategies are skipped and DeltaPull is the path that actually
    // runs. Writing the server's customer_id/supplier_id/party_id raw made
    // getPartyStatement (filters by LOCAL partyId) return nothing → supplier &
    // customer statements empty on the mirror, and clobbered the cwi_commerce
    // local cash-receipt cache row's local partyId on the server echo. Resolve
    // via the parties FK mappings DeltaPull already records (storeFkMapping,
    // ~line 197/269). Falls through unchanged when the party kept the server id.
    const partyFkByTable = {
      'sales_invoices': 'customer_id',
      'purchase_invoices': 'supplier_id',
      'safe_transactions': 'party_id',
    };
    final partyFkCol = partyFkByTable[table];
    if (partyFkCol != null && row[partyFkCol] is int) {
      final serverPartyId = row[partyFkCol] as int;
      final directHit = await _db!.customSelect(
        'SELECT 1 FROM parties WHERE id = ? LIMIT 1',
        variables: [Variable.withInt(serverPartyId)],
      ).getSingleOrNull();
      if (directHit == null) {
        final mapped = await _db!.customSelect(
          "SELECT local_id FROM remote_id_mappings "
          "WHERE table_name = 'parties' AND remote_id = ? LIMIT 1",
          variables: [Variable.withInt(serverPartyId)],
        ).getSingleOrNull();
        final localPartyId = mapped?.read<int?>('local_id');
        if (localPartyId != null && localPartyId != serverPartyId) {
          row = Map.of(row);
          row[partyFkCol] = localPartyId;
          debugPrint('[DeltaPull] $table.$partyFkCol remap server '
              '$serverPartyId → local $localPartyId');
        } else {
          unawaited(DiagnosticLogger.log(
            'SYNC-WARN',
            '$table $partyFkCol=$serverPartyId pulled with no local party '
            'mapping — statement for this party may be incomplete until its '
            'parties row syncs (DeltaPull party-FK remap).',
          ));
        }
      }
    }

    // If the local row exists with a different id (client-originated record
    // that now carries a server id), UPDATE in place — preserving the local
    // primary key and all FK references to it.
    if (localId != null && serverId != null && localId != serverId) {
      final updateCols = row.keys.where((k) => k != 'id').toList();
      if (updateCols.isEmpty) return;
      final setClause = updateCols.map((c) => '$c = ?').join(', ');
      final values = updateCols.map((c) => row[c]).toList()..add(localId);
      try {
        await _db!.customStatement(
          'UPDATE $table SET $setClause WHERE id = ?',
          values,
        );
      } catch (e) {
        debugPrint('[DeltaPull] in-place update $table local=$localId server=$serverId: $e');
      }
      return;
    }

    // Collision guard — server's numeric id is already occupied locally
    // by a row with a different global_id. Blindly INSERT OR REPLACE would
    // overwrite the user's own offline-created row (the exact symptom the
    // user reported as "لا يرضى يرحل بياناتهم" / "I can't change the id").
    // Renumber the local row into the safe >=1B range, cascading every FK
    // reference, then let the server row take its natural id.
    if (serverId != null) {
      try {
        final collision = await _db!.customSelect(
          'SELECT global_id FROM "$table" WHERE id = ? LIMIT 1',
          variables: [Variable.withInt(serverId)],
        ).getSingleOrNull();
        final existingGid = collision?.read<String?>('global_id');
        if (collision != null &&
            existingGid != null &&
            existingGid.isNotEmpty &&
            existingGid != globalId) {
          await IdNamespaceService.instance.renumberLocalRow(
            _db!,
            table,
            serverId,
          );
        }
      } catch (e) {
        debugPrint('[DeltaPull] collision check $table id=$serverId: $e');
      }
    }

    // ── Users table: preserve local password credentials and roleId ──────────
    // The server's users delta may carry password_hash with an empty
    // password_salt (e.g. when the server stores bcrypt with an embedded salt
    // rather than PBKDF2 with a separate salt column). A bare INSERT OR REPLACE
    // would overwrite the client's good salt with "", breaking every subsequent
    // login until the boot-heal runs.
    //
    // Additionally, if the server's user id=N belongs to a *different* person
    // than the client's local user id=N (created offline before sync assigned
    // server IDs), the raw upsert would silently change the local user's roleId,
    // causing mid-session permission escalation (nav expansion bug).
    //
    // Fix: for the users table, detect an absent/empty server salt and fall
    // back to the existing local credentials so the row is otherwise updated
    // (display name, isActive, defaultScreen, …) without clobbering passwords.
    if (table == 'users') {
      final serveSalt = row['password_salt'];
      final serveHash = row['password_hash'];
      final hashStr = serveHash is String ? serveHash : '';
      final saltStr = serveSalt is String ? serveSalt : '';
      final hashOk = hashStr.isNotEmpty;
      // Argon2id PHC hashes embed their salt in the hash string (format:
      // $argon2id$v=19$m=...,t=...,p=...$saltB64$hashB64). When the server's
      // user has been rehashed to Argon2 (Week-8 upgrade in user_dao.dart),
      // password_salt becomes "" by design. Treat that as a VALID credential
      // form — otherwise the previous "preserve local credentials" branch
      // would silently overwrite the server's authoritative Argon2 hash with
      // a stale local PBKDF2 'admin' hash, blocking the user from logging in
      // with their real password (and triggering the boot-heal loop the
      // operator observed in ${Brand.dbPrefix}_startup_log.txt).
      final isArgon2 = hashStr.startsWith(r'$argon2');
      final saltOk = saltStr.isNotEmpty || isArgon2;

      if (!saltOk || !hashOk) {
        // Server sent incomplete credentials — three cases to handle:
        //   1. Local row exists with valid credentials → preserve them
        //      (existing user; admin's PBKDF2 hash mustn't be overwritten by
        //      the server's bcrypt-style "99-char hash, empty salt" form).
        //   2. Local row exists but is also broken (salt="") → mint a fresh
        //      temp password locally so the user can log in via reset flow.
        //   3. NEW user row from server with no local match → mint a temp
        //      password keyed off the username and force a password change.
        //      Without this, the row lands with salt="" and every login
        //      attempt fails (PBKDF2 verifyPassword bails on empty salt) —
        //      the symptom the user reported as "الكاشير القديم مش راضى يدخل
        //      على النظام من جهاز مرتبط".
        final username = row['username'] as String?;
        try {
          final localRow = await _db!.customSelect(
            'SELECT password_hash, password_salt, role_id '
            'FROM users WHERE id = ? LIMIT 1',
            variables: [Variable.withInt(localId ?? (row['id'] as int? ?? 0))],
          ).getSingleOrNull();

          String? hashToUse;
          String? saltToUse;

          if (localRow != null) {
            final localHash = localRow.read<String?>('password_hash') ?? '';
            final localSalt = localRow.read<String?>('password_salt') ?? '';
            if (localHash.isNotEmpty && localSalt.isNotEmpty) {
              hashToUse = localHash;
              saltToUse = localSalt;
              debugPrint('[DeltaPull] users id=${row['id']}: '
                  'server sent empty salt — preserved local credentials');
            }
          }

          // No usable local credentials — generate a temp password so login
          // is possible. Username + "123" matches the convention used by
          // UserSyncStrategy for the same scenario, keeping behavior
          // consistent across the two sync paths.
          if (hashToUse == null &&
              username != null &&
              username.isNotEmpty &&
              !username.startsWith('__dup_')) {
            final tempPassword = '${username}123';
            saltToUse = SecurityService.generateSalt();
            hashToUse = SecurityService.hashPassword(tempPassword, saltToUse);
            debugPrint('[DeltaPull] users id=${row['id']} '
                'username="$username": no usable credentials — minted temp '
                'password "${username}123" + forcePasswordChange=true');
          }

          if (hashToUse != null && saltToUse != null) {
            row = Map.of(row); // make mutable copy before patching
            row['password_hash'] = hashToUse;
            row['password_salt'] = saltToUse;
            // Force the user to change the temp password on first login when
            // we minted credentials. Preserved local credentials don't need
            // this flag — only newly-minted ones do.
            if (localRow == null ||
                (localRow.read<String?>('password_salt') ?? '').isEmpty) {
              row['force_password_change'] = 1;
            }
          }
        } catch (e) {
          debugPrint('[DeltaPull] users credential handling failed: $e');
        }
      }
    }

    // Normal path: server row wins — INSERT OR REPLACE by id.
    final cols = row.keys.join(', ');
    final placeholders = List.filled(row.length, '?').join(', ');
    try {
      await _db!.customStatement(
        'INSERT OR REPLACE INTO $table ($cols) VALUES ($placeholders)',
        row.values.toList(),
      );
    } catch (e) {
      debugPrint('[DeltaPull] upsert $table id=${row['id']}: $e');
    }

    // Replay embedded journal_entry_lines now that the parent header
    // exists. We DELETE-then-INSERT per entry so a server-side line
    // edit (rare — most entries are auto-posted from invoices) takes
    // effect locally instead of leaving stale lines behind. The
    // journal_entry_lines.entry_id FK has ON DELETE CASCADE on the
    // header, but NOT vice-versa, so deleting just the lines for this
    // entry is safe.
    if (embeddedJournalLines != null && serverId != null) {
      try {
        await _db!.customStatement(
          'DELETE FROM journal_entry_lines WHERE entry_id = ?',
          [serverId],
        );
        for (final raw in embeddedJournalLines) {
          if (raw is! Map) continue;
          final lineRow = Map<String, dynamic>.from(raw);
          // Force entry_id to the server's id (which the header upsert
          // above adopted as the local id). Defensive against a server
          // payload accidentally omitting it.
          lineRow['entry_id'] = serverId;
          final lineCols = lineRow.keys.join(', ');
          final linePlaceholders =
              List.filled(lineRow.length, '?').join(', ');
          await _db!.customStatement(
            'INSERT OR REPLACE INTO journal_entry_lines '
            '($lineCols) VALUES ($linePlaceholders)',
            lineRow.values.toList(),
          );
        }
        if (embeddedJournalLines.isNotEmpty) {
          _db!.notifyUpdates({
            const TableUpdate('journal_entry_lines',
                kind: UpdateKind.insert),
            const TableUpdate('journal_entry_lines',
                kind: UpdateKind.update),
          });
        }
      } catch (e) {
        debugPrint(
          '[DeltaPull] journal_entry_lines replay for entry=$serverId: $e',
        );
      }
    }
  }

  // ─── Watermark helpers ───────────────────────────────────────────────────

  Future<DateTime?> _loadWatermark(String table) async {
    final val = await _db!.getSettingValue('_watermark__$table');
    if (val == null || val.isEmpty) return null;
    final epoch = int.tryParse(val);
    return epoch != null
        ? DateTime.fromMillisecondsSinceEpoch(epoch * 1000)
        : null;
  }

  Future<void> _saveWatermark(String table, int epochSeconds) async {
    await _db!.setSetting('_watermark__$table', '$epochSeconds');
  }

  /// Returns the current watermark for every pull table (null = never pulled).
  Future<Map<String, DateTime?>> getAllWatermarks() async {
    final result = <String, DateTime?>{};
    for (final table in pullTables) {
      result[table] = await _loadWatermark(table);
    }
    return result;
  }

  /// Clears all watermarks, forcing a full re-sync on the next [pullAll] call.
  Future<void> resetWatermarks() async {
    for (final table in pullTables) {
      await _db!.setSetting('_watermark__$table', '');
    }
    debugPrint('[DeltaPull] All watermarks reset — next pull will be a full sync');
  }

  /// Seeds every watermark to [epochSeconds] — typically the moment a
  /// bootstrap fullSync finished, so the next [pullAll] cycle only asks for
  /// rows modified *after* the bootstrap instead of redundantly re-pulling
  /// everything the strategies already downloaded.
  Future<void> seedWatermarks(int epochSeconds) async {
    if (_db == null) return;
    // Spec 151 P1-8b — when the bootstrap ran WITHOUT a session token it could
    // not pull the branch-scoped transactional tables (the server fail-closed
    // them), so their watermarks must stay unseeded; otherwise the post-login
    // DeltaPull would ask only for rows after `epochSeconds` and permanently
    // skip the pre-login backlog (the reverted BLOCKER). With a token present
    // (e.g. a mirror that minted an admin token at pairing) the bootstrap
    // pulled everything, so seed all tables as before.
    final hasToken = ServerProxy.instance.hasSessionToken();
    var seeded = 0;
    for (final table in pullTables) {
      if (!hasToken && branchScopedPullTables.contains(table)) continue;
      await _saveWatermark(table, epochSeconds);
      seeded++;
    }
    debugPrint('[DeltaPull] Seeded $seeded/${pullTables.length} watermarks to '
        '$epochSeconds (hasToken=$hasToken)');
  }

  /// True when at least one watermark has been persisted — used by startup to
  /// pick between full bootstrap and incremental delta pull.
  Future<bool> hasAnyWatermark() async {
    if (_db == null) return false;
    for (final table in pullTables) {
      final val = await _db!.getSettingValue('_watermark__$table');
      if (val != null && val.isNotEmpty) return true;
    }
    return false;
  }
}
