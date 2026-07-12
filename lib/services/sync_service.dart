import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/database/database.dart';
import '../domain/entities/sync_dtos.dart';
import 'delta_pull_service.dart';
import 'server_proxy.dart';
import 'network_service.dart';
import 'sync/sync_strategy.dart';
import 'sync/strategies/category_sync_strategy.dart';
import 'sync/strategies/unit_sync_strategy.dart';
import 'sync/strategies/product_sync_strategy.dart';
import 'sync/strategies/party_sync_strategy.dart';
import 'sync/strategies/branch_sync_strategy.dart';
import 'sync/strategies/warehouse_sync_strategy.dart';
import 'sync/strategies/user_sync_strategy.dart';
import 'sync/strategies/setting_sync_strategy.dart';
import 'sync/strategies/role_sync_strategy.dart';
import 'sync/strategies/permission_sync_strategy.dart';
import 'sync/strategies/role_permission_sync_strategy.dart';
import 'sync/strategies/safe_sync_strategy.dart';
import 'sync/strategies/shift_sync_strategy.dart';
import 'sync/strategies/sales_sync_strategy.dart';
import 'sync/strategies/cost_center_sync_strategy.dart';
import 'sync/strategies/account_sync_strategy.dart';
import 'sync/strategies/journal_sync_strategy.dart';
import 'sync/strategies/safe_transaction_sync_strategy.dart';
import 'sync/strategies/purchase_sync_strategy.dart';
import 'sync/strategies/stock_movement_sync_strategy.dart';
import 'sync/strategies/commercial_paper_sync_strategy.dart';
import 'sync/strategies/account_mapping_sync_strategy.dart';
import 'sync/strategies/inventory_balance_sync_strategy.dart';
import 'sync/strategies/product_barcode_sync_strategy.dart';
import 'sync/strategies/user_branch_access_sync_strategy.dart';
import 'sync/strategies/user_warehouse_access_sync_strategy.dart';
import 'sync/strategies/sales_held_orders_sync_strategy.dart';
import 'sync/strategies/sales_held_order_items_sync_strategy.dart';
import 'sync/strategies/region_sync_strategy.dart';
import 'sync/strategies/user_region_access_sync_strategy.dart';
import 'sync/strategies/offers_sync_strategy.dart';
import 'sync/strategies/product_unit_sync_strategy.dart';
import 'sync/strategies/document_sequence_sync_strategy.dart';
import 'sync/strategies/fiscal_year_sync_strategy.dart';
import 'sync/strategies/accounting_period_sync_strategy.dart';
import 'sync/strategies/product_batch_sync_strategy.dart';
import 'sync/strategies/payment_sync_strategy.dart';
import 'sync/strategies/payment_allocation_sync_strategy.dart';
import 'sync/strategies/sales_order_sync_strategy.dart';
import 'sync/strategies/purchase_order_sync_strategy.dart';
// Feature 009 / T012b + T012c — Auto-Deplete BOM consumption log + POS terminals
import 'sync/strategies/sale_bom_consumption_sync_strategy.dart';
import 'sync/strategies/pos_terminal_sync_strategy.dart';

/// Client-side sync engine for pulling data from the server
/// and caching it in the local SQLite database.
class SyncService {
  final String serverUrl;
  final AppDatabase localDb;

  /// Static instance — set when created in main_desktop or checkout_controller
  static SyncService? _instance;
  static SyncService? get instance => _instance;
  static bool get hasInstance => _instance != null;

  /// Clear the static instance (call when switching away from client mode)
  static void clearInstance() {
    _instance?.dispose();
    _instance = null;
  }

  DateTime? _lastSyncTime;
  bool _isSyncing = false;
  Timer? _heartbeatTimer;
  Timer? _autoSyncTimer;
  final _clientId = 'client_${DateTime.now().millisecondsSinceEpoch}';

  /// Registry of table-specific sync strategies (flat — used by syncTable
  /// lookups). Construction order is FK-safe and is preserved from the
  /// original sequential implementation.
  late final List<SyncStrategy> _strategies;

  /// Same registry grouped by FK-dependency tier. fullSync runs each tier
  /// in parallel via `Future.wait`, then waits for the tier to complete
  /// before starting the next. Issue 7 — turns ~30 sequential network
  /// round-trips into 4 parallel batches and removes the per-strategy
  /// `Future.delayed(100ms)` yield.
  late final List<List<SyncStrategy>> _tieredStrategies;

  // Prefs key
  static const _prefLastSync = 'sync_last_sync_time';

  /// Whether the app is truly in client mode — delegates to NetworkService
  /// as the single source of truth (not just checking serverUrl).
  bool get isClient => NetworkService.instance.isClient;
  String get clientId => _clientId;

  /// Cached branch ID for this client (read from SharedPreferences)
  int? _clientBranchId;

  /// Phase 6 (T1) — when `false` (the default on a paired client), `fullSync`
  /// skips Tier 3 (transactional tables). The client manages its own
  /// sales/purchases/journals/safe_transactions/shifts locally and only
  /// pushes them out via the outbox; it does not pull other branches'
  /// transactions back from the server. Set to `true` via the
  /// `client_pulls_transactional_enabled` setting to revert at runtime.
  /// Server mode is unaffected because the gate in `fullSync` checks
  /// `isClient` before consulting this flag.
  bool _clientPullsTransactionalEnabled = false;
  bool get clientPullsTransactionalEnabled => _clientPullsTransactionalEnabled;

  /// API endpoints that should be scoped by branch_id when in client mode.
  /// Endpoints NOT in this set receive all data (global config).
  static const _scopedEndpoints = <String>{
    '/api/warehouses',
    '/api/safes',
    '/api/sales',
    '/api/purchases',
    '/api/stock-movements',
    '/api/inventory-balances',
    '/api/journals',
    '/api/safe-transactions',
    '/api/products',
    '/api/users',
    '/api/parties',
    '/api/branches',
    '/api/cost_centers',
    '/api/accounts',
    '/api/product-barcodes',
    '/api/user-branch-access',
    '/api/sales/held',
    '/api/sales/held-items',
    '/api/payments',
    '/api/payment-allocations',
    '/api/product-batches',
    '/api/sales-orders',
    '/api/purchase-orders',
  };

  SyncService({required this.serverUrl, required this.localDb}) {
    _instance = this;
    // H-1 FIX: Ordered by FK dependencies (parents before children).
    // Each inner list is a tier — runnable in parallel within the tier;
    // the next tier waits for the previous to complete (FK invariant).
    _tieredStrategies = [
      // ── Tier 0: No FK dependencies ──
      [
        RegionSyncStrategy(localDb),
        CostCenterSyncStrategy(localDb),
        AccountSyncStrategy(localDb),
        CategorySyncStrategy(localDb),
        UnitSyncStrategy(localDb),
        SettingSyncStrategy(localDb),
        RoleSyncStrategy(localDb),
        PermissionSyncStrategy(localDb),
        FiscalYearSyncStrategy(localDb),
        DocumentSequenceSyncStrategy(localDb),
        AccountingPeriodSyncStrategy(localDb), // → FiscalYears
      ],
      // ── Tier 1: Depend on Tier 0 ──
      [
        BranchSyncStrategy(localDb),         // → Regions, CostCenters
        WarehouseSyncStrategy(localDb),      // → Branches
        SafeSyncStrategy(localDb),           // → Branches, Accounts, CostCenters
        RolePermissionSyncStrategy(localDb), // → Roles, Permissions
        UserSyncStrategy(localDb),           // → Roles
        AccountMappingSyncStrategy(localDb), // → Accounts
        PosTerminalSyncStrategy(localDb),    // → Branches  (T012c, FR-034)
      ],
      // ── Tier 2: Depend on Tier 1 ──
      [
        UserBranchAccessSyncStrategy(localDb),    // → Users, Branches
        UserWarehouseAccessSyncStrategy(localDb), // → Users, Warehouses
        UserRegionAccessSyncStrategy(localDb),    // → Users, Regions
        ProductSyncStrategy(localDb),          // → Categories, Units
        ProductBarcodeSyncStrategy(localDb),   // → Products
        ProductUnitSyncStrategy(localDb),      // → Products
        ProductBatchSyncStrategy(localDb),     // → Products, Warehouses
        PartySyncStrategy(localDb),            // → Accounts
        OffersSyncStrategy(localDb),           // → Products
      ],
      // ── Tier 3: Transactional data ──
      [
        ShiftSyncStrategy(localDb),
        SalesSyncStrategy(localDb),
        PurchaseSyncStrategy(localDb),
        JournalSyncStrategy(localDb),
        SafeTransactionSyncStrategy(localDb),
        StockMovementSyncStrategy(localDb),
        InventoryBalanceSyncStrategy(localDb),
        CommercialPaperSyncStrategy(localDb),
        SalesHeldOrdersSyncStrategy(localDb),
        SalesHeldOrderItemsSyncStrategy(localDb),
        PaymentSyncStrategy(localDb),              // → Parties, Safes
        PaymentAllocationSyncStrategy(localDb),    // → Payments
        SalesOrderSyncStrategy(localDb),           // → Parties, Products, Warehouses
        PurchaseOrderSyncStrategy(localDb),        // → Parties, Products, Warehouses
        // T012b: server-authored consumption log for auto-deplete sales.
        // FK: sales_invoices, sales_invoice_items (synced earlier in this
        // tier), bill_of_materials (master sync TBD with T015), products,
        // warehouses, branches.
        SaleBomConsumptionSyncStrategy(localDb),
      ],
    ];
    _strategies = [for (final tier in _tieredStrategies) ...tier];
  }

  /// Initialize sync service — load branch ID from prefs
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _clientBranchId = prefs.getInt('client_branch_id');
    final flagRaw = await localDb.getSettingValue('client_pulls_transactional_enabled');
    _clientPullsTransactionalEnabled = flagRaw == 'true';
    debugPrint('[Sync] Initialized, clientBranchId=$_clientBranchId, '
        'clientPullsTransactionalEnabled=$_clientPullsTransactionalEnabled');
  }

  // ... (getters)

  /// Full sync — pull all data from server into local DB
  Future<SyncResult> fullSync() async {
    if (_isSyncing) {
      return SyncResult(success: false, message: 'Sync already in progress');
    }
    _isSyncing = true;

    try {
      debugPrint('[Sync] Starting modular full sync from $serverUrl');
      final wallStart = DateTime.now();
      int totalSynced = 0;
      int totalFailed = 0;

      // Issue 7 — tier-parallel sync. Strategies within a tier are
      // independent (no cross-FK), so we run them with `Future.wait`
      // and only block at tier boundaries. Removes the previous
      // `Future.delayed(100ms)` yield between every strategy (which
      // alone added ~3 s to a 30-strategy run on a typical client).
      //
      // Phase 6 (T2) — branch-isolation gate. On a paired client with the
      // default `client_pulls_transactional_enabled=false`, Tier 3
      // (transactional tables) is skipped entirely. The client owns its
      // sales/purchases/journals/safe_transactions/shifts; pushes via the
      // outbox still ferry every write to the server tagged with branch_id.
      // Server mode (isClient==false) is unaffected and runs all four tiers.
      final skipTier3 = isClient && !_clientPullsTransactionalEnabled;
      for (var tierIdx = 0; tierIdx < _tieredStrategies.length; tierIdx++) {
        if (tierIdx == 3 && skipTier3) {
          debugPrint('[Sync] Tier 3 skipped — client-isolated mode '
              '(client_pulls_transactional_enabled=false)');
          continue;
        }
        final tier = _tieredStrategies[tierIdx];
        final tierStart = DateTime.now();
        final results = await Future.wait(tier.map((strategy) async {
          // Spec 151 P1-8b — skip a branch-scoped transactional table when
          // this device holds no session token. The server fail-closes it to
          // zero rows tokenless; pulling it would poison its watermark. Return
          // `false` (neither synced nor failed) so the skip never counts as a
          // failure that aborts first-sync — DeltaPull backfills the table
          // after login, scoped to the user's branch. Reference/master tables
          // are never in this set, so a fresh client's first-sync still
          // populates them fully (never bricked).
          if (_branchScopedFullSyncEndpoints.contains(strategy.apiEndpoint) &&
              !ServerProxy.instance.hasSessionToken()) {
            debugPrint('[Sync] ${strategy.tableName} skipped — no session '
                'token (branch-scoped; backfills after login)');
            return false;
          }
          try {
            debugPrint('[Sync] Syncing table: ${strategy.tableName}');
            final result = await _fetchJson(strategy.apiEndpoint);
            if (result != null) {
              await strategy.syncFromJson(result);
              return true;
            }
            return false;
          } catch (e) {
            debugPrint('[Sync] Error syncing table ${strategy.tableName}: $e');
            return null; // null = error (distinct from "no data")
          }
        }));
        for (final r in results) {
          if (r == true) totalSynced++;
          if (r == null) totalFailed++;
        }
        debugPrint(
            '[SYNC-PERF] Tier $tierIdx: ${tier.length} strategies in '
            '${DateTime.now().difference(tierStart).inMilliseconds} ms');
      }
      debugPrint('[SYNC-PERF] fullSync wall time: '
          '${DateTime.now().difference(wallStart).inMilliseconds} ms '
          '($totalSynced synced, $totalFailed failed)');

      // H-2 FIX: Only update last sync time if ALL strategies succeeded.
      // Otherwise, failed data would be permanently skipped by incremental sync.
      if (totalFailed == 0) {
        // Use server clock to avoid clock-skew between client devices.
        // If the fetch fails, fall back to local time (safe: next delta will
        // re-pull any records the client clock would over-shoot).
        final serverEpoch = await ServerProxy.instance.fetchServerTime();
        _lastSyncTime = serverEpoch != null
            ? DateTime.fromMillisecondsSinceEpoch(serverEpoch * 1000, isUtc: true)
            : DateTime.now().toUtc();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefLastSync, _lastSyncTime!.toIso8601String());

        // Seed DeltaPullService watermarks with the same server timestamp so
        // the next DeltaPull cycle only asks for rows modified AFTER this sync
        // instead of redundantly re-pulling everything.
        if (serverEpoch != null) {
          await DeltaPullService.instance.seedWatermarks(serverEpoch);
        }
      } else {
        debugPrint('[Sync] ⚠ $totalFailed strategies failed — _lastSyncTime NOT updated to force retry');
      }

      _isSyncing = false;
      return SyncResult(
        success: true,
        message: 'تمت المزامنة بنجاح',
        itemsSynced: totalSynced,
      );
    } catch (e) {
      _isSyncing = false;
      debugPrint('[Sync] Full sync failed: $e');
      return SyncResult(success: false, message: 'فشلت المزامنة: $e');
    }
  }

  /// Tier 3 (transactional) table names. Mirrors `_tieredStrategies[3]` —
  /// kept as a const set so `syncTable` (WebSocket-triggered single-table
  /// pulls) can short-circuit without instantiating strategies. Edit both
  /// lists together when a strategy moves between tiers.
  static const _tier3TableNames = <String>{
    'shifts',
    'sales_invoices',
    'purchase_invoices',
    'journals',
    'safe_transactions',
    'stock_movements',
    'inventory_balances',
    'commercial_papers',
    'sales_held_orders',
    'sales_held_order_items',
    'payments',
    'payment_allocations',
    'sales_orders',
    'purchase_orders',
  };

  /// Spec 151 P1-8b — GET endpoints the server fail-closes to ZERO rows when
  /// the request carries no `X-Session-Token` (the transactional set in
  /// `api_handler` §3.1). A full-sync/single-table pull for one of these MUST
  /// be skipped while this device holds no session token: pulling would return
  /// nothing and — via `seedWatermarks` — poison the watermark, so the
  /// post-login DeltaPull would never backfill the pre-login backlog. Matched
  /// on `strategy.apiEndpoint` (unambiguous — the strategies use three
  /// different `tableName` conventions). Reference/master endpoints are absent
  /// here and pull fully tokenless (so a fresh client is never bricked).
  static const _branchScopedFullSyncEndpoints = <String>{
    '/api/sales',              // sales_invoices  → _getSalesInvoices
    '/api/purchases',          // purchase_invoices → _getPurchaseInvoices
    '/api/journals',           // journal_entries → _getJournalEntries
    '/api/stock-movements',    // stock_movements → _getStockMovements
    '/api/safe-transactions',  // safe_transactions → _getSafeTransactions
    '/api/inventory-balances', // inventory_balances → _getInventoryBalances
    '/api/shifts',             // shifts → _getShifts
    '/api/sales/held',         // held_orders → _getHeldOrders
    // Spec 151 residual #1 — the remaining transactional GETs now also
    // fail-close to zero rows tokenless (branch-scoped server-side). Skip them
    // on a tokenless fullSync / WebSocket nudge for the same reason as above:
    // a zero-row pull followed by seedWatermarks would poison their watermark
    // and strand the pre-login backlog. DeltaPull backfills 6 of them post-login
    // (they are in `pullTables`); product_batches is not a DeltaPull table, so
    // it is healed by an explicit post-login syncTable — see
    // AuthRepositoryImpl._acquireServerSession.
    '/api/payments',            // payments → _getPayments
    '/api/payment-allocations', // payment_allocations → _getPaymentAllocations
    '/api/product-batches',     // product_batches → _getProductBatches
    '/api/sales-orders',        // sales_orders → _getSalesOrders
    '/api/purchase-orders',     // purchase_orders → _getPurchaseOrders
    '/api/commercial-papers',   // commercial_papers → _getCommercialPapers
    '/api/sales/held-items',    // held_order_items → _getHeldOrderItems
  };

  /// Sync a specific table triggered by WebSocket data_changed event
  Future<void> syncTable(String? table) async {
    if (_isSyncing) return;
    debugPrint('[Sync] Initializing modular sync for table: $table');

    // Phase 6 (T2) — branch-isolation gate also applies to per-table syncs
    // triggered by WebSocket data_changed events. A paired client should
    // not pull other branches' transactions even when nudged by the server.
    if (table != null
        && isClient
        && !_clientPullsTransactionalEnabled
        && _tier3TableNames.contains(table)) {
      debugPrint('[Sync] syncTable("$table") skipped — client-isolated mode');
      return;
    }

    try {
      // 1. Handle composite / alias triggers
      //
      // The server broadcasts generic event names (e.g. 'treasury', 'accounting')
      // but our strategies use specific table names (e.g. 'safe_transactions', 'journals').
      // Map aliases to the actual strategy names and sync them all.
      const tableAliases = <String, List<String>>{
        'treasury': ['safe_transactions'],
        'accounting': ['journals'],
        'inventory': ['products'],
        'held_orders': ['products'],
      };

      if (tableAliases.containsKey(table)) {
        debugPrint('[Sync] Alias "$table" → syncing ${tableAliases[table]}');
        for (final alias in tableAliases[table]!) {
          await syncTable(alias);
        }
        // Also try direct match (in case there's a strategy named 'treasury' too)
      }

      // 2. Resolve strategy from registry
      final strategy = _strategies.cast<SyncStrategy?>().firstWhere(
            (s) => s?.tableName == table,
            orElse: () => null,
          );

      if (strategy != null) {
        // Spec 151 P1-8b — same branch-scoped gate as fullSync: a WebSocket
        // data_changed nudge for a transactional table must not pull it
        // tokenless (server fail-closes to zero rows + watermark poison).
        // DeltaPull backfills it after login.
        if (_branchScopedFullSyncEndpoints.contains(strategy.apiEndpoint) &&
            !ServerProxy.instance.hasSessionToken()) {
          debugPrint('[Sync] syncTable("$table") skipped — no session token '
              '(branch-scoped; backfills after login)');
          return;
        }
        final result = await _fetchJson(strategy.apiEndpoint);
        if (result != null) {
          await strategy.syncFromJson(result);
          debugPrint('[Sync] Modular sync complete for ${strategy.tableName}');
        }
      } else if (!(tableAliases.containsKey(table))) {
        debugPrint(
          '[Sync] ⚠️ No strategy found for table "$table" — skipping',
        );
      }
    } catch (e) {
      debugPrint('[Sync] Modular syncTable($table) failed: $e');
    }
  }

  /// Incremental sync — pull only updated items since last sync across all tables.
  /// Uses the same API endpoints with a `?since=` query parameter.
  /// The server returns only records modified after that timestamp.
  /// Data is then piped through the existing `syncFromJson` parsers.
  Future<SyncResult> incrementalSync() async {
    if (_lastSyncTime == null) {
      return fullSync(); // First time → do full sync
    }
    if (_isSyncing) {
      return SyncResult(success: false, message: 'Sync in progress');
    }
    _isSyncing = true;

    try {
      int totalUpdated = 0;
      final since = _lastSyncTime!;
      final sinceParam = since.toUtc().toIso8601String();

      for (final strategy in _strategies) {
        try {
          // Fetch only records updated since last sync
          final endpoint = '${strategy.apiEndpoint}?since=$sinceParam';
          final result = await _fetchJson(endpoint);
          if (result != null) {
            await strategy.syncFromJson(result);
            // Count is approximate — we count a sync if the server returned data
            final dataList = result.values.firstWhere(
              (v) => v is List,
              orElse: () => <dynamic>[],
            ) as List;
            totalUpdated += dataList.length;
          }
          // Yield to event loop to prevent UI freezing 
          await Future.delayed(const Duration(milliseconds: 100));
        } catch (e) {
          debugPrint('[Sync] Incremental sync error for ${strategy.tableName}: $e');
        }
      }

      final serverEpoch = await ServerProxy.instance.fetchServerTime();
      _lastSyncTime = serverEpoch != null
          ? DateTime.fromMillisecondsSinceEpoch(serverEpoch * 1000, isUtc: true)
          : DateTime.now().toUtc();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefLastSync, _lastSyncTime!.toIso8601String());

      _isSyncing = false;
      return SyncResult(
        success: true,
        message: 'تم تحديث $totalUpdated عنصر',
        itemsSynced: totalUpdated,
      );
    } catch (e) {
      _isSyncing = false;
      debugPrint('[Sync] Incremental sync failed: $e');
      return SyncResult(success: false, message: 'Sync failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // M5: Auto-sync polling — 30-second delta pull in client mode
  // ═══════════════════════════════════════════════════════════════

  /// Default polling fallback when no interval is configured. WebSocket
  /// pushes (`data_changed`) drive most sync; this timer is the safety net
  /// for missed events / WS down. Lowered from 30 s → 5 s so a degraded-WS
  /// client still feels near-real-time on a multi-branch deployment.
  static const Duration _defaultAutoSyncInterval = Duration(seconds: 5);

  /// Settings key that overrides [_defaultAutoSyncInterval]. Stored as int
  /// seconds; clamped to [1, 300]. Letting an admin tune this matters on
  /// flaky branch links where 5 s polling stacks up timeouts.
  static const String _autoSyncIntervalKey = 'auto_sync_interval_seconds';

  /// Start background auto-sync. Safe to call multiple times — idempotent.
  /// Reads the interval from `settings.auto_sync_interval_seconds` (seconds);
  /// falls back to 5 s when unset/invalid. WebSocket `data_changed` events
  /// still drive immediate per-table pulls — this timer just covers the gap
  /// when WebSocket is disconnected.
  Future<void> startAutoSync() async {
    if (!isClient) return;
    if (_autoSyncTimer?.isActive == true) return; // already running
    final interval = await _resolveAutoSyncInterval();
    _autoSyncTimer = Timer.periodic(interval, (_) async {
      if (!isClient) {
        stopAutoSync();
        return;
      }
      try {
        await DeltaPullService.instance.pullAll();
      } catch (e) {
        debugPrint('[AutoSync] delta pull failed (non-fatal): $e');
      }
    });
    debugPrint('[AutoSync] Started polling every ${interval.inSeconds}s');
  }

  Future<Duration> _resolveAutoSyncInterval() async {
    try {
      final raw = await localDb.getSettingValue(_autoSyncIntervalKey);
      final parsed = int.tryParse(raw?.trim() ?? '');
      if (parsed != null && parsed >= 1 && parsed <= 300) {
        return Duration(seconds: parsed);
      }
    } catch (e) {
      debugPrint('[AutoSync] Failed to read $_autoSyncIntervalKey: $e');
    }
    return _defaultAutoSyncInterval;
  }

  /// Stop auto-sync polling.
  void stopAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
    debugPrint('[AutoSync] Stopped');
  }

  // TODO(multi-branch): Activate via Timer.periodic when branch sync is enabled
  /// Send heartbeat to server
  // ignore: unused_element
  Future<void> _sendHeartbeat() async {
    try {
      await _postJson('/api/sync/heartbeat', {'clientId': _clientId});
    } catch (e) {
      debugPrint('[Sync] Heartbeat failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // HTTP Helpers
  // ═══════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>?> _fetchJson(String path) async {
    try {
      final ns = NetworkService.instance;
      final addr = ns.serverAddress;
      if (addr == null || addr.trim().isEmpty) {
        debugPrint('[Sync] Aborted GET $path: server address empty');
        return null;
      }

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      client.badCertificateCallback = (cert, host, port) => true;
      final liveUrl = _currentUrl;

      // Apply branch scope for scoped endpoints.
      //
      // Phase 6 (T5) — removed the prior `_clientBranchId! > 1` carve-out.
      // It treated a client paired to branch 1 as an unscoped "mirror" of
      // the whole install, leaking other branches' rows into that client's
      // POS/treasury/GL screens. Per the user's directive ("each client =
      // one independent branch") branch 1 is now an ordinary branch like
      // any other; the install-wide view belongs to the server-mode app
      // (`isClient == false`, which short-circuits this scope block since
      // `_clientBranchId` is null in server mode). Operators who want a
      // panoramic view should run the server UI, not a paired client.
      String resolvedPath = path;
      if (_clientBranchId != null) {
        // Strip query params from path to check against scoped set
        final basePath = path.contains('?') ? path.substring(0, path.indexOf('?')) : path;
        if (_scopedEndpoints.contains(basePath)) {
          final separator = path.contains('?') ? '&' : '?';
          resolvedPath = '$path${separator}branch_id=$_clientBranchId';
        }
      }

      final request = await client.getUrl(Uri.parse('$liveUrl$resolvedPath'));

      // Include API auth token for authenticated endpoints
      final token = ServerProxy.instance.apiToken;
      if (token != null) {
        request.headers.set('Authorization', 'Bearer $token');
      }
      // Spec 151 P1-8b — stamp the signed per-user session token so the server
      // can derive the acting identity and honour branch-scoped
      // (transactional) endpoints. This raw-HttpClient path bypasses
      // ServerProxy._authHeaders, so without it every transactional GET (and
      // inventory_balances) fail-closes to zero rows even for a logged-in
      // user. Omitted when no token is cached (pre-login); those endpoints are
      // gated out upstream in fullSync/syncTable/DeltaPull anyway.
      final sessionToken = ServerProxy.instance.sessionTokenForCurrentUser();
      if (sessionToken != null) {
        request.headers.set('X-Session-Token', sessionToken);
      }
      // Skip ngrok interstitial page
      request.headers.set('ngrok-skip-browser-warning', 'true');
      request.headers.set('User-Agent', 'UralCash-Client');

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();

      if (response.statusCode == 200) {
        return json.decode(body) as Map<String, dynamic>;
      }
      print('[Sync] GET $path → ${response.statusCode}');
      return null;
    } catch (e) {
      print('[Sync] GET $path failed: $e');
      return null;
    }
  }

  /// Always use the LIVE URL from NetworkService (not stale constructor value)
  String get _currentUrl => NetworkService.instance.buildServerUrl();

  /// Write a diagnostic line to sync_diagnostic.txt
  void _diagLog(String msg) {
    try {
      final f = File('sync_diagnostic.txt');
      f.writeAsStringSync('[${DateTime.now().toIso8601String()}] $msg\n', mode: FileMode.append);
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _postJson(
    String path,
    Map<String, dynamic> data,
  ) async {
    final ns = NetworkService.instance;
    final addr = ns.serverAddress;
    if (addr == null || addr.trim().isEmpty) {
      debugPrint('[Sync] Aborted POST $path: server address empty');
      return null;
    }

    final liveUrl = _currentUrl;
    final fullUrl = '$liveUrl$path';
    print('[Sync] POST → $fullUrl');
    _diagLog('POST → $fullUrl');
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      client.badCertificateCallback = (cert, host, port) => true;
      final request = await client.postUrl(Uri.parse(fullUrl));
      request.headers.contentType = ContentType.json;

      // Include API auth token for authenticated endpoints
      final token = ServerProxy.instance.apiToken;
      if (token != null) {
        request.headers.set('Authorization', 'Bearer $token');
      } else {
        print('[Sync] ⚠️ WARNING: No API token! POST will likely fail auth');
      }
      // Skip ngrok interstitial page
      request.headers.set('ngrok-skip-browser-warning', 'true');
      request.headers.set('User-Agent', 'UralCash-Client');

      request.write(json.encode(data));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();

      print('[Sync] POST $path → status=${response.statusCode}');
      _diagLog('POST $path → status=${response.statusCode}, bodyLen=${body.length}');
      if (response.statusCode == 200) {
        return json.decode(body) as Map<String, dynamic>;
      }
      print('[Sync] POST $path FAILED: status=${response.statusCode}, body=$body');
      _diagLog('POST FAILED: status=${response.statusCode}, body=$body');
      return null;
    } catch (e) {
      print('[Sync] POST $fullUrl EXCEPTION: $e');
      _diagLog('POST EXCEPTION: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // SALES SUBMISSION (Phase 2)
  // ═══════════════════════════════════════════════════════════════════

  /// Submit a completed sale to the server using typed DTO.
  /// Returns the full server response map on success, null on failure.
  Future<Map<String, dynamic>?> submitSale(SyncSaleRequest request) async {
    final payload = request.toJson();
    _diagLog('submitSale: invoiceNumber=${request.invoiceNumber}, payloadKeys=${payload.keys.toList()}');

    final result = await _postJson('/api/sales', payload);
    if (result != null && result['success'] == true) {
      final serverId = result['serverId'] as int?;
      final isDuplicate = result['duplicate'] == true;
      print('[Sync] Sale submitted: serverId=$serverId duplicate=$isDuplicate');
      _diagLog('submitSale SUCCESS: serverId=$serverId');
      return result;
    }
    print('[Sync] Sale submission failed for ${request.invoiceNumber}, result=$result');
    _diagLog('submitSale FAILED: result=$result');
    return null;
  }

  /// PHASE-10: Force a complete re-sync by clearing last sync time.
  /// Useful when branch data is stale or corrupted.
  Future<SyncResult> forceFullResync() async {
    debugPrint('[Sync] 🔄 Force full resync requested — clearing sync history');
    _lastSyncTime = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefLastSync);
    return fullSync();
  }

  /// PHASE-8: Get dead letter count for diagnostics
  Future<int> getDeadLetterCount() async {
    try {
      return await localDb.getDeadLetterCount();
    } catch (_) {
      return 0;
    }
  }

  /// Dispose resources
  void dispose() {
    _heartbeatTimer?.cancel();
    _autoSyncTimer?.cancel();
  }
}

/// Result of a sync operation
class SyncResult {
  final bool success;
  final String message;
  final int itemsSynced;

  SyncResult({
    required this.success,
    required this.message,
    this.itemsSynced = 0,
  });
}
