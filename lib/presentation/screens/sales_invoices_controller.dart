import 'package:picpos_erp/core/i18n/tr.dart';
import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/business_profile_provider.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/repositories/inventory_repository.dart';
import '../../../domain/entities/invoice_entity.dart';
import '../../core/logging/diagnostic_logger.dart';
import '../../services/network_service.dart';
import '../../services/offline_sync_worker.dart';

/// Cluster 025 / Issue 3: how the sales-invoices list is sorted.
/// `dateDesc` is the historical default — newest first by createdAt.
/// `byClientReceiveOrder` groups rows by `originClientId` and sorts
/// each group by `createdAt ASC` so the operator sees, per client,
/// the order in which the server received the invoices. This surfaces
/// gaps when one client's outbox is ahead of another's without needing
/// a new schema column (everything is already on the row).
enum SalesInvoiceSortMode {
  dateDesc,
  byClientReceiveOrder,
}

/// إجمالياتُ **الفترة السابقة** — نافذةٌ بنفس طولِ المدى المختار تسبقه
/// مباشرةً وتُقاس بنفس المرشِّحات (الفرع · مركز التكلفة · المخزن).
///
/// ‏`null` تعني «لا مقارنةَ متاحة» لا «صفر»: لا مدى تاريخٍ مختار، أو أخفق
/// الاستعلام. والفرقُ جوهريّ — شارةُ «‏0%» تدّعي ثباتاً لم يُقَس.
class SalesPreviousPeriod {
  const SalesPreviousPeriod({
    required this.totalAmount,
    required this.collected,
    required this.totalRemaining,
    required this.totalReturns,
    required this.invoiceCount,
  });

  final double totalAmount;

  /// بنفس تعريفِ الفترة الحاليّة: مدفوعاتُ الفواتير + سنداتُ القبض (‏Issue 10).
  /// وإسقاطُ السندات هنا وحدَها كان سيجعل المقارنةَ كاذبةً في اتّجاهٍ واحد.
  final double collected;

  final double totalRemaining;
  final double totalReturns;
  final int invoiceCount;
}

class SalesInvoicesScreenState {
  final List<InvoiceEntity> allInvoices;
  final List<InvoiceEntity> filteredInvoices;
  final Map<int, String> customerNames;
  final Map<int, String> warehouseNames;
  final Map<int, int?> warehouseBranchId;
  final Map<int, String> branchNames;
  final Map<int, String> costCenterNames;
  // returnedAmounts[invoiceId] = total returned for this invoice (sum of
  // safe_transactions tagged with referenceType='sales_return'). Used to
  // subtract the refund value from each row's "المتبقي" so a partially
  // returned invoice doesn't keep showing its original outstanding amount.
  final Map<int, double> returnedAmounts;
  final bool isLoading;
  final DateTimeRange? dateRange;
  // Issue 8 — multi-select status. Empty set == "all" (no filter applied).
  // Allowed values: 'paid', 'partial', 'unpaid'. The legacy single-string
  // field used 'all' to encode the same; storing it as an empty set makes
  // the "no filter" case unambiguous and lets the chip group do an OR.
  final Set<String> statusFilters;
  final String searchQuery;
  final int? selectedWarehouseId;
  final int? selectedBranchId;
  final int? selectedCostCenterId;
  final Set<int> selectedInvoices;
  final SalesInvoiceSortMode sortMode;

  // Summaries
  final double totalAmount;
  final double totalPaid;
  // Issue 10 — sum of standalone receipt vouchers (سندات قبض) within
  // the same filters. Surfaced as part of "المحصّل" so cash collected
  // outside any specific invoice — common for delivery-company
  // settlements — appears alongside invoice-side `paid` totals.
  final double receiptVouchersTotal;
  final double totalRemaining;
  final double totalReturns;
  final int invoiceCount;
  final int displayLimit;
  final bool hasMore;

  /// مقارنةُ الفترة السابقة — `null` = غيرُ متاحة، لا صفر.
  final SalesPreviousPeriod? previousPeriod;

  /// عدّاداتُ الحالة لشرائح الترشيح — `{'paid': n, 'partial': n, 'unpaid': n}`.
  ///
  /// مصدرُها تجميعُ SQL على **كلّ** المطابق لا على الصفحة المحمَّلة: العدُّ
  /// من `allInvoices` كان سيتوقّف عند سقف الصفحة (٥٠٠) فيعطي رقماً أقلَّ من
  /// الحقيقة بلا ما يشي بذلك. وفارغةٌ ⇒ لا عدّادَ يُعرض، لا صفر.
  final Map<String, int> statusCounts;

  SalesInvoicesScreenState({
    this.allInvoices = const [],
    this.filteredInvoices = const [],
    this.customerNames = const {},
    this.warehouseNames = const {},
    this.warehouseBranchId = const {},
    this.branchNames = const {},
    this.costCenterNames = const {},
    this.returnedAmounts = const {},
    this.isLoading = true,
    this.dateRange,
    this.statusFilters = const {},
    this.searchQuery = '',
    this.selectedWarehouseId,
    this.selectedBranchId,
    this.selectedCostCenterId,
    this.selectedInvoices = const {},
    this.sortMode = SalesInvoiceSortMode.dateDesc,
    this.totalAmount = 0,
    this.totalPaid = 0,
    this.receiptVouchersTotal = 0,
    this.totalRemaining = 0,
    this.totalReturns = 0,
    this.invoiceCount = 0,
    this.displayLimit = 50,
    this.hasMore = false,
    this.previousPeriod,
    this.statusCounts = const {},
  });

  SalesInvoicesScreenState copyWith({
    List<InvoiceEntity>? allInvoices,
    List<InvoiceEntity>? filteredInvoices,
    Map<int, String>? customerNames,
    Map<int, String>? warehouseNames,
    Map<int, int?>? warehouseBranchId,
    Map<int, String>? branchNames,
    Map<int, String>? costCenterNames,
    Map<int, double>? returnedAmounts,
    bool? isLoading,
    DateTimeRange? dateRange,
    /// ‏`true` ⇒ امسح المدى. وعَلَمٌ صريحٌ لا `null` لأن `null` في
    /// `copyWith` تعني «لا تغيّر» — فكان طلبُ المسح يُقرأ إغفالاً ويُبتلع
    /// صامتاً، وزرُّ «×» يُنقَر بلا أثر (‏invoice_filters_clear_date_test).
    bool clearDateRange = false,
    Set<String>? statusFilters,
    String? searchQuery,
    int? selectedWarehouseId,
    bool clearWarehouse = false,
    int? selectedBranchId,
    bool clearBranch = false,
    int? selectedCostCenterId,
    bool clearCostCenter = false,
    Set<int>? selectedInvoices,
    SalesInvoiceSortMode? sortMode,
    double? totalAmount,
    double? totalPaid,
    double? receiptVouchersTotal,
    double? totalRemaining,
    double? totalReturns,
    int? invoiceCount,
    int? displayLimit,
    bool? hasMore,
    SalesPreviousPeriod? previousPeriod,
    bool clearPreviousPeriod = false,
    Map<String, int>? statusCounts,
  }) {
    return SalesInvoicesScreenState(
      allInvoices: allInvoices ?? this.allInvoices,
      filteredInvoices: filteredInvoices ?? this.filteredInvoices,
      customerNames: customerNames ?? this.customerNames,
      warehouseNames: warehouseNames ?? this.warehouseNames,
      warehouseBranchId: warehouseBranchId ?? this.warehouseBranchId,
      branchNames: branchNames ?? this.branchNames,
      costCenterNames: costCenterNames ?? this.costCenterNames,
      returnedAmounts: returnedAmounts ?? this.returnedAmounts,
      isLoading: isLoading ?? this.isLoading,
      dateRange: clearDateRange ? null : (dateRange ?? this.dateRange),
      statusFilters: statusFilters ?? this.statusFilters,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedWarehouseId: clearWarehouse ? null : (selectedWarehouseId ?? this.selectedWarehouseId),
      selectedBranchId: clearBranch ? null : (selectedBranchId ?? this.selectedBranchId),
      selectedCostCenterId: clearCostCenter ? null : (selectedCostCenterId ?? this.selectedCostCenterId),
      selectedInvoices: selectedInvoices ?? this.selectedInvoices,
      sortMode: sortMode ?? this.sortMode,
      totalAmount: totalAmount ?? this.totalAmount,
      totalPaid: totalPaid ?? this.totalPaid,
      receiptVouchersTotal: receiptVouchersTotal ?? this.receiptVouchersTotal,
      totalRemaining: totalRemaining ?? this.totalRemaining,
      totalReturns: totalReturns ?? this.totalReturns,
      invoiceCount: invoiceCount ?? this.invoiceCount,
      displayLimit: displayLimit ?? this.displayLimit,
      hasMore: hasMore ?? this.hasMore,
      previousPeriod: clearPreviousPeriod
          ? null
          : (previousPeriod ?? this.previousPeriod),
      statusCounts: statusCounts ?? this.statusCounts,
    );
  }
}

/// ح-8 (متطلبات العميل 2026-07-25) — النافذة الزمنية القانونية لفلتر فواتير
/// المبيعات: **[بداية يوم البداية، بداية اليوم التالي للنهاية)**.
///
/// The predicate this replaces was
/// ```
/// isAfter(start − 1 day) && isBefore(end + 1 day)
/// ```
/// which leaked a full day at BOTH ends:
///   • `start` from the picker is midnight, so `start − 1 day` is midnight of
///     the PREVIOUS day and every invoice on that day passed `isAfter`;
///   • when the picker normalised `end` to 23:59:59, `end + 1 day` reached
///     into the day AFTER the range as well.
///
/// Normalising both bounds to day boundaries makes the window identical
/// whether the caller passes a midnight `end` or an end-of-day one, and lines
/// it up with `getReceiptVouchersTotal`'s own `[from, to + 1 day]` window so
/// «إجمالي المبيعات» and «المحصّل» finally answer the same question.
bool invoiceDateInRange(DateTime invoiceDate, DateTimeRange range) {
  final w = dayWindowFor(range);
  return !invoiceDate.isBefore(w.start) && invoiceDate.isBefore(w.endExclusive);
}

/// ح-8 — المصدر الوحيد لنافذة التاريخ في هذه الشاشة، تستعمله بطاقة «إجمالي
/// المبيعات» وبطاقة «المحصّل» معاً. Snaps both bounds to day boundaries so the
/// window is identical whether the caller hands over a midnight `end` or a
/// 23:59:59 one.
({DateTime start, DateTime endExclusive}) dayWindowFor(DateTimeRange range) => (
      start: DateTime(range.start.year, range.start.month, range.start.day),
      endExclusive: DateTime(range.end.year, range.end.month, range.end.day + 1),
    );

class SalesInvoicesController extends Notifier<SalesInvoicesScreenState> {
  Timer? _debounce;
  bool _disposed = false;
  // Cluster 025 / Issue 6: keep the customer-name lookup live so newly
  // pull-synced parties replace the "عميل #N" placeholder without the user
  // having to refresh. Previously the controller called `.first` once and
  // then never observed parties-table changes.
  StreamSubscription<List<Party>>? _customerNamesSub;
  // Field-bug fix (mirror refresh storm, 2026-05-07): under bursty WebSocket
  // broadcasts on a paired mirror, the two event sources below
  // (salesInvoicesChangeProvider + serverDataChangeProvider) fired in
  // separate ~150-300ms windows. Each pair → one refresh, but the legacy
  // debounce only coalesced events within a single 150ms window, so 42
  // incoming sales produced 60+ refreshes (16 in 5s observed). Adding
  // an in-flight guard caps concurrent refreshes at 1 with at most 1
  // queued for the next window — no matter how many events arrive.
  bool _refreshing = false;
  bool _refreshQueued = false;

  @override
  SalesInvoicesScreenState build() {
    _disposed = false;

    // Listen for table-level changes (same proven pattern as SalesReturnNotifier).
    // One always-on .watch() stream detects inserts from any source (local POS,
    // client sync via API, etc.). When it fires, we debounce and do a fresh .get().
    //
    // ⚠️ The provider is NOT autoDispose — an earlier version of this comment
    // said it was, and the two readings imply opposite lifetimes. See its own
    // doc in providers.dart: it is deliberately kept alive so an insert that
    // happens while this screen is dormant is still reflected on return.
    //
    // ⚠️ And it must emit a DISTINCT value per change. It used to be
    // StreamProvider<void>, so every emission compared equal and Riverpod
    // notified only once — the measured cause of "the list doesn't refresh
    // after save" (2026-08-23). Do not collapse it back to a constant.
    ref.listen(salesInvoicesChangeProvider, (_, _) {
      _scheduleRefresh();
    });

    // Belt-and-suspenders: also listen to the server's API broadcast stream.
    // When a CLIENT posts a sale to this server, postSale() calls
    // `broadcast('sales')` which feeds `serverDataChangeProvider`. The Drift
    // `.watch()` path above SHOULD also fire via `markTablesUpdated`, but on
    // drift_postgres that signal has been observed to drop under load, so we
    // subscribe to both for reliability. The shared scheduler coalesces both
    // sources through one in-flight guard.
    ref.listen(serverDataChangeProvider, (_, next) {
      next.whenData((table) {
        if (table != 'sales' && table != 'held_orders') return;
        _scheduleRefresh();
      });
    });

    ref.onDispose(() {
      _disposed = true;
      _debounce?.cancel();
      _customerNamesSub?.cancel();
    });

    Future.microtask(() => _initData());
    return SalesInvoicesScreenState();
  }

  /// Single shared entry-point for both event sources. Caps concurrent
  /// refreshes at 1 with at most 1 queued for the next window.
  void _scheduleRefresh() {
    if (_disposed) return;
    if (_refreshing) {
      // A refresh is already running — mark that another change happened
      // so we'll do one more pass once the current one completes. Do NOT
      // schedule a timer; that would just create another concurrent pass
      // when the current one finishes its async work.
      _refreshQueued = true;
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), _runRefresh);
  }

  Future<void> _runRefresh() async {
    if (_disposed || _refreshing) return;
    _refreshing = true;
    try {
      await _refreshInvoices();
    } finally {
      _refreshing = false;
      // If at least one event arrived while we were refreshing, schedule
      // exactly ONE follow-up pass. This keeps the data fresh without
      // letting bursty broadcasts queue an unbounded chain of refreshes.
      if (_refreshQueued && !_disposed) {
        _refreshQueued = false;
        _scheduleRefresh();
      }
    }
  }

  void _initData() async {
    await DiagnosticLogger.log('SALES-LIST', 'controller._initData started');
    try {
      // Don't let customer-name loading block invoice fetching — the two
      // are independent and invoice list is the critical path. If the
      // customer stream hangs (PG/sync issue), customer names stay empty
      // but invoices still show.
      unawaited(_loadCustomerNames().catchError((e) async {
        await DiagnosticLogger.log('SALES-LIST',
            'loadCustomerNames error (non-fatal): $e');
      }));
      await _refreshInvoices();
      await DiagnosticLogger.log('SALES-LIST', 'controller._initData done');
    } catch (e) {
      debugPrint('[SalesInvoices] Init error: $e');
      await DiagnosticLogger.log('SALES-LIST', '❌ init error: $e');
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> _loadCustomerNames() async {
    final partiesRepo = ref.read(partiesRepositoryProvider);
    // Spec 002 (B4): include inactive customers in the lookup map so
    // every FK on every existing invoice resolves. Active-only filtering
    // belongs in selectors, not in lookup maps.
    //
    // Cluster 025 / Issue 6: subscribe to the stream (not just `.first`) so
    // the map re-emits whenever a pull-sync inserts/updates a party row.
    // Cancel-and-resubscribe makes _initData re-entrant on hot-reload.
    await _customerNamesSub?.cancel();
    final completer = Completer<void>();
    _customerNamesSub = partiesRepo.watchAllCustomersForLookup().listen(
      (customers) {
        if (_disposed) return;
        final names = <int, String>{};
        for (final customer in customers) {
          names[customer.id] = customer.name;
        }
        state = state.copyWith(customerNames: names);
        if (!completer.isCompleted) completer.complete();
      },
      onError: (Object e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
    );
    // Wait for the first snapshot (or the existing 5s timeout) so the
    // caller's downstream branch/warehouse loading still runs predictably.
    await completer.future.timeout(const Duration(seconds: 5));

    // Load warehouse / branch / cost center maps in parallel so the
    // invoice list shows "branch / warehouse / cost center" without
    // N+1 lookups per row. Failures are non-fatal — invoices still show.
    try {
      final db = ref.read(databaseProvider);
      final accRepo = ref.read(accountingRepositoryProvider);
      final wh = await db.select(db.warehouses).get();
      final br = await db.watchBranches().first.timeout(const Duration(seconds: 5));
      final cc = await accRepo.getCostCenters();
      if (_disposed) return;
      state = state.copyWith(
        warehouseNames: {for (final w in wh) w.id: w.name},
        warehouseBranchId: {for (final w in wh) w.id: w.branchId},
        branchNames: {for (final b in br) b.id: b.name},
        costCenterNames: {for (final c in cc) c.id: c.name},
      );
    } catch (e) {
      debugPrint('[SalesInvoices] branch/warehouse/cost-center load failed (non-fatal): $e');
    }
  }

  /// Fetch invoices via one-shot .get() — always returns fresh data from DB.
  Future<void> _refreshInvoices() async {
    await DiagnosticLogger.log('SALES-LIST', '_refreshInvoices started');
    try {
      final salesRepo = ref.read(salesRepositoryProvider);
      List<InvoiceEntity> invoices;
      try {
        invoices = await salesRepo.getInvoicesPaged();
      } catch (fetchErr, st) {
        // Primary fetch failed — log the real reason AND attempt a
        // raw DB read as fallback so the user can still see their data.
        await DiagnosticLogger.log('SALES-LIST',
            '❌ getInvoicesPaged threw: $fetchErr');
        await DiagnosticLogger.log('SALES-LIST',
            'stack trace (first 300 chars): '
            '${st.toString().substring(0, st.toString().length.clamp(0, 300))}');
        try {
          // Day 6B: use repository method — no Drift types in presentation.
          invoices = await salesRepo.getRawInvoices();
          await DiagnosticLogger.log('SALES-LIST',
              '✓ raw DB fallback: ${invoices.length} invoices loaded');
        } catch (rawErr) {
          await DiagnosticLogger.log('SALES-LIST',
              '❌ raw DB fallback also failed: $rawErr');
          rethrow;
        }
      }
      debugPrint('[SalesInvoices] Fetched ${invoices.length} invoices');
      // Release-safe counter. "Nothing fetched" and "fetched then filtered
      // away by branch scope" look identical on screen (an empty list, no
      // error) but have completely different causes, so both numbers have to
      // reach the on-disk log — the kDebugMode diagnostics below never run on
      // a field build.
      await DiagnosticLogger.log(
          'SALES-LIST', 'fetched ${invoices.length} invoices (pre-scope)');

      // Phase 5C.1 (Issue 4) — branch-scope guard. The repository may
      // hand back rows from branches the current user shouldn't see
      // (legacy data on the device, an unscoped raw fallback, or a
      // race during the migration to the server-side scope from 5A.1).
      // Filter here so the auth boundary is enforced at the controller
      // layer regardless of where the row came from. Admin / financial-
      // manager hits BranchScope.fullAccess (allowedBranchIds == null)
      // and the filter is a no-op.
      final scope = await ref.read(branchScopeProvider.future);
      if (!scope.hasFullAccess) {
        final before = invoices.length;
        final seenBranchIds =
            invoices.map((inv) => inv.branchId).toSet().toList();
        invoices = invoices.where((inv) => scope.isAllowed(inv.branchId)).toList();
        if (before != invoices.length) {
          debugPrint('[SalesInvoices] BranchScope dropped '
              '${before - invoices.length} cross-branch rows '
              '(allowed=${scope.allowedBranchIds})');
          await DiagnosticLogger.log(
              'SALES-LIST',
              '⚠ BranchScope dropped ${before - invoices.length}/$before rows — '
              'allowed=${scope.allowedBranchIds!.toList()} '
              'invoiceBranchIds=$seenBranchIds');
        }
      }

      // ISS-ARCH-01: diagnostic DB sampling delegated to repository so no
      // Drift types leak into the presentation layer.
      if (kDebugMode && invoices.isEmpty) {
        try {
          final sample = await salesRepo.getDiagnosticSample();
          await DiagnosticLogger.log(
            'SALES-LIST',
            'EMPTY result. rawTotal=${sample.totalCount} '
            'undeleted=${sample.undeletedSample.length} — sample: '
            '${sample.sampleText.isEmpty ? "table is empty" : sample.sampleText}',
          );

          if (sample.undeletedSample.isNotEmpty) {
            await DiagnosticLogger.log('SALES-LIST',
                '⚠ filter mismatch — showing all ${sample.undeletedSample.length} '
                'undeleted rows regardless of saleType as safety fallback');
            state = state.copyWith(
              allInvoices: sample.undeletedSample,
              isLoading: false,
            );
            _applyFilters();
            return;
          }
        } catch (e) {
          await DiagnosticLogger.log('SALES-LIST', 'diagnostic error: $e');
        }
      } else if (kDebugMode) {
        await DiagnosticLogger.log('SALES-LIST',
            'loaded ${invoices.length} invoices '
            '(first: ${invoices.first.invoiceNumber})');
      }

      state = state.copyWith(
        allInvoices: invoices,
        isLoading: false,
      );

      // Pull returned amounts for ALL loaded invoices — not just those
      // with a returned/partial_return status. The original status flip
      // is best-effort (legacy data, late server flips, manual edits)
      // so an invoice can have refund records without the badge. The
      // DAO query is keyed on referenceId / notes so non-matching rows
      // simply return nothing and the cost stays low even with a long
      // history.
      try {
        final allIds = invoices
            .where((inv) => inv.id != null)
            .map((inv) => inv.id!)
            .toList();
        if (allIds.isNotEmpty) {
          final db = ref.read(databaseProvider);
          final returned = await db.getReturnedAmountsForInvoices(allIds);
          if (!_disposed) {
            state = state.copyWith(returnedAmounts: returned);
          }
        }
      } catch (e) {
        debugPrint('[SalesInvoices] returned amounts load failed (non-fatal): $e');
      }

      _applyFilters();
    } catch (e) {
      debugPrint('[SalesInvoices] Refresh error: $e');
      await DiagnosticLogger.log('SALES-LIST',
          '❌ outer refresh error: $e');
      state = state.copyWith(isLoading: false);
    }
  }

  /// Public refresh — called by refresh button or external triggers.
  ///
  /// In CLIENT mode: also triggers the offline sync outbox to drain any
  /// pending sales invoices that haven't reached the server yet. This is
  /// important when the server was temporarily rejecting invoices (e.g.
  /// due to user mapping issues now fixed) — tapping refresh on the screen
  /// after a server-side fix pushes the queued invoices through.
  ///
  /// On SERVER mode: also reruns one pass of sync from connected clients
  /// is NOT applicable (server is authoritative).
  void refresh() {
    state = state.copyWith(isLoading: true);
    if (NetworkService.instance.isClient) {
      // Fire-and-forget: drain queued outbox items in parallel with the
      // read refresh. The screen re-reads as the outbox entries clear.
      // ignore: unawaited_futures
      OfflineSyncWorker.instance.drainOutbox(force: true);
    }
    _refreshInvoices();
  }

  // Filter chain (Issue 8 — documented for future maintainers).
  // Order is intentional and AND-chained — each step shrinks the candidate
  // set further. The user-facing rule is: "show invoices that match every
  // active filter". `statusFilters` is OR'd internally (the multi-select
  // chips behave as "any of these statuses").
  //
  //   1. searchQuery      → invoiceNumber OR customerName contains query
  //   2. dateRange        → invoiceDate within [start, end]
  //   3. selectedWarehouseId → invoice.warehouseId == X
  //   4. selectedBranchId   → invoice.branchId == X (with warehouse fallback)
  //   5. selectedCostCenterId → invoice.costCenterId == X
  //   6. statusFilters    → invoice.status IN selected (empty = all)
  void _applyFilters() {
    var filtered = state.allInvoices.toList();

    // Text search
    final query = state.searchQuery.toLowerCase();
    if (query.isNotEmpty) {
      filtered = filtered.where((inv) {
        final invoiceMatch = inv.invoiceNumber.toLowerCase().contains(query);
        final customerName = inv.partyId != null
            ? (state.customerNames[inv.partyId]?.toLowerCase() ?? '')
            : tr('عميل نقدي');
        final customerMatch = customerName.contains(query);
        return invoiceMatch || customerMatch;
      }).toList();
    }

    // Date range
    if (state.dateRange != null) {
      filtered = filtered
          .where((inv) => invoiceDateInRange(inv.invoiceDate, state.dateRange!))
          .toList();
    }

    // Warehouse filter
    if (state.selectedWarehouseId != null) {
      filtered = filtered.where((inv) => inv.warehouseId == state.selectedWarehouseId).toList();
    }

    // Branch filter — direct match on invoice.branchId (L3) with fallback
    // to warehouse → branch lookup for old rows that haven't been backfilled.
    if (state.selectedBranchId != null) {
      filtered = filtered.where((inv) {
        if (inv.branchId == state.selectedBranchId) return true;
        // Backward-compat: rows created before v133 may have null branchId
        final whId = inv.warehouseId;
        if (whId == null) return false;
        return state.warehouseBranchId[whId] == state.selectedBranchId;
      }).toList();
    }

    // Cost center filter — direct match on invoice.costCenterId
    if (state.selectedCostCenterId != null) {
      filtered = filtered.where((inv) =>
          inv.costCenterId == state.selectedCostCenterId).toList();
    }

    // Status filter — multi-select OR. Empty set = no filter.
    if (state.statusFilters.isNotEmpty) {
      filtered = filtered.where((inv) {
        if (state.statusFilters.contains('paid') &&
            inv.status == InvoiceStatus.paid) return true;
        if (state.statusFilters.contains('partial') &&
            inv.status == InvoiceStatus.partial) return true;
        if (state.statusFilters.contains('unpaid') &&
            inv.status == InvoiceStatus.pending) return true;
        return false;
      }).toList();
    }

    // Cluster 025 / Issue 3: optional per-client receive-order sort.
    // Default `dateDesc` keeps the historical "newest first" behaviour
    // (DAO already returns rows ordered by `createdAt DESC` so we don't
    // need to re-sort). The alternative groups by client and walks each
    // client's invoices in the order the server received them.
    if (state.sortMode == SalesInvoiceSortMode.byClientReceiveOrder) {
      filtered.sort((a, b) {
        final ca = a.originClientId ?? '';
        final cb = b.originClientId ?? '';
        final clientCmp = ca.compareTo(cb);
        if (clientCmp != 0) return clientCmp;
        final ta = a.createdAt ?? a.invoiceDate;
        final tb = b.createdAt ?? b.invoiceDate;
        return ta.compareTo(tb);
      });
    }

    // Calculate summaries — subtract any returned amount from each invoice's
    // remaining so the dashboard total reflects refunds, not just payments.
    final totalAmount = filtered.fold(0.0, (sum, inv) => sum + inv.total);
    final totalPaid = filtered.fold(0.0, (sum, inv) => sum + inv.paid);
    final totalReturned = filtered.fold(
      0.0,
      (sum, inv) => sum + (state.returnedAmounts[inv.id] ?? 0.0),
    );
    // المتبقي = الإجمالي − المحصل من الفواتير − المرتجعات. Receipt vouchers
    // intentionally don't reduce المتبقي because they may not be linked to
    // a specific invoice in this filter — including them would over-credit.
    final totalRemaining = totalAmount - totalPaid - totalReturned;
    final invoiceCount = filtered.length;

    state = state.copyWith(
      filteredInvoices: filtered.take(state.displayLimit).toList(),
      totalAmount: totalAmount,
      totalPaid: totalPaid,
      totalRemaining: totalRemaining,
      totalReturns: totalReturned,
      invoiceCount: invoiceCount,
      hasMore: filtered.length > state.displayLimit,
    );

    // ح-2 — the in-memory folds above run over a page capped at 500 rows, so
    // they are only a first paint. Re-derive the cards from a SQL aggregate
    // over ALL matching rows. Fire-and-forget: the cards update on the next
    // notify, and the search box (which changes on every keystroke) does not
    // trigger it — see _refreshSummaryTotals.
    unawaited(_refreshSummaryTotals());

    // Issue 10 — refresh receipt-voucher total scoped to the same filters
    // (date range + branch + cost center). Async + fire-and-forget so the
    // sync filter loop above stays snappy; the KPI card updates on the
    // next state.notify when the future resolves.
    unawaited(_refreshReceiptVouchersTotal());
  }

  /// ح-2 — authoritative card totals from SQL.
  ///
  /// Only runs when a date range is active: without one the aggregate would
  /// scan the whole table on every filter change, and the un-ranged view is
  /// the "everything" view where the paged fold is close enough. With a range
  /// active — which is exactly when the operator is reading the numbers — the
  /// paged fold could be off by an unbounded amount, or read 0.00.
  ///
  /// Deliberately NOT keyed off the search box: the text filter is a
  /// client-side narrowing of what's displayed, and re-querying per keystroke
  /// would be a query per character.
  Future<void> _refreshSummaryTotals() async {
    if (_disposed) return;
    final range = state.dateRange;
    if (range == null) return;
    // A text search narrows the visible list only; keep the SQL totals aligned
    // with the structural filters so the cards stay stable while typing.
    if (state.searchQuery.trim().isNotEmpty) return;
    try {
      final db = ref.read(databaseProvider);
      final window = dayWindowFor(range);
      final summary = await db.getSalesInvoiceSummary(
        from: window.start,
        to: window.endExclusive.subtract(const Duration(days: 1)),
        warehouseIds: state.selectedWarehouseId != null
            ? [state.selectedWarehouseId!]
            : null,
        branchId: state.selectedBranchId,
        costCenterId: state.selectedCostCenterId,
      );
      if (_disposed) return;
      state = state.copyWith(
        totalAmount: summary.totalAmount,
        totalPaid: summary.totalPaid,
        totalReturns: summary.totalReturns,
        totalRemaining: summary.totalRemaining,
        invoiceCount: summary.invoiceCount,
        statusCounts: {
          'paid': summary.paidCount,
          'partial': summary.partialCount,
          'unpaid': summary.unpaidCount,
        },
      );
      unawaited(_refreshPreviousPeriod(window));
    } catch (e) {
      // Leave the paged fold in place rather than blanking the cards, but say
      // so — a silent fallback to a truncated number is what ح-2 was about.
      debugPrint('[SalesInvoices] SQL summary failed, showing paged totals: $e');
    }
  }

  /// إجمالياتُ الفترة السابقة — نافذةٌ **بنفس الطول** تسبق المدى المختار
  /// مباشرةً، وبنفس المرشِّحات كي تكون المقارنةُ على المقدار لا على المدى.
  ///
  /// مثال: ‏١–٢١ أغسطس (٢١ يوماً) ⇒ السابقةُ ‏١١–٣١ يوليو (٢١ يوماً).
  ///
  /// وأيُّ إخفاقٍ يمسح المقارنةَ إلى `null` ولا يُبقي رقمَ مدىً قديمٍ معلَّقاً:
  /// شارةُ اتّجاهٍ تقارن فترةَ اليوم بفترةِ الأمس هي **الكذبةُ** التي يُحذَر
  /// منها، لا غيابُ الشارة.
  Future<void> _refreshPreviousPeriod(
    ({DateTime start, DateTime endExclusive}) window,
  ) async {
    if (_disposed) return;
    try {
      final db = ref.read(databaseProvider);
      final lengthDays = window.endExclusive.difference(window.start).inDays;
      if (lengthDays <= 0) {
        if (state.previousPeriod != null) {
          state = state.copyWith(clearPreviousPeriod: true);
        }
        return;
      }
      final prevStart = window.start.subtract(Duration(days: lengthDays));
      // نفسُ اصطلاح النداء الحاليّ: `to` هو بدايةُ آخرِ يومٍ داخلَ النافذة.
      final prevTo = window.start.subtract(const Duration(days: 1));

      final summary = await db.getSalesInvoiceSummary(
        from: prevStart,
        to: prevTo,
        warehouseIds: state.selectedWarehouseId != null
            ? [state.selectedWarehouseId!]
            : null,
        branchId: state.selectedBranchId,
        costCenterId: state.selectedCostCenterId,
      );
      if (_disposed) return;

      // «المحصّل» يجب أن يُقاس بنفس تعريفه في الفترة الحاليّة — مدفوعاتٌ +
      // سنداتُ قبض. ولو قورنت مدفوعاتٌ وحدَها بمدفوعاتٍ وسنداتٍ لظهر هبوطٌ
      // وهميٌّ في كلّ فترةٍ فيها سندات.
      final scope = await ref.read(branchScopeProvider.future);
      if (_disposed) return;
      final prevVouchers = await db.getReceiptVouchersTotal(
        from: prevStart,
        to: prevTo,
        branchId: state.selectedBranchId,
        costCenterId: state.selectedCostCenterId,
        allowedBranchIds: scope.hasFullAccess ? null : scope.allowedBranchIds,
      );
      if (_disposed) return;

      state = state.copyWith(
        previousPeriod: SalesPreviousPeriod(
          totalAmount: summary.totalAmount,
          collected: summary.totalPaid + prevVouchers,
          totalRemaining: summary.totalRemaining,
          totalReturns: summary.totalReturns,
          invoiceCount: summary.invoiceCount,
        ),
      );
    } catch (e) {
      debugPrint('[SalesInvoices] previous-period summary failed: $e');
      if (!_disposed && state.previousPeriod != null) {
        state = state.copyWith(clearPreviousPeriod: true);
      }
    }
  }

  /// Issue 10 — pull the sum of receipt vouchers in the active date range
  /// + branch + cost-center filters. Used by `salesSummaryCards` to make
  /// "المحصّل" reflect *all* cash collected (invoice payments AND
  /// standalone vouchers), not just the invoice-side `paid` column.
  Future<void> _refreshReceiptVouchersTotal() async {
    if (_disposed) return;
    final range = state.dateRange;
    if (range == null) {
      // No date range → don't load (could be very large). The card falls
      // back to showing only invoice payments, same as before.
      if (state.receiptVouchersTotal != 0) {
        state = state.copyWith(receiptVouchersTotal: 0);
      }
      return;
    }
    try {
      final db = ref.read(databaseProvider);
      // Spec 151 D-04 — resolve the caller's branch scope and pass it so a
      // branch-restricted user with no branch selected doesn't get every
      // branch's receipt vouchers in the «المحصّل» total (a null branchId
      // otherwise means company-wide). Admin / financial-manager resolves to
      // fullAccess (null) → no cap, matching the invoice-list filter above.
      final scope = await ref.read(branchScopeProvider.future);
      if (_disposed) return;
      // ح-8: use the SAME day window as the invoice filter. Previously this
      // passed the raw picker bounds while the invoice list used
      // `start − 1 day … end + 1 day`, so «إجمالي المبيعات» and «المحصّل»
      // covered different periods. getReceiptVouchersTotal applies its own
      // `to + 1 day`, so hand it the START of the end day.
      final window = dayWindowFor(range);
      final total = await db.getReceiptVouchersTotal(
        from: window.start,
        to: window.endExclusive.subtract(const Duration(days: 1)),
        branchId: state.selectedBranchId,
        costCenterId: state.selectedCostCenterId,
        allowedBranchIds: scope.hasFullAccess ? null : scope.allowedBranchIds,
      );
      if (_disposed) return;
      state = state.copyWith(receiptVouchersTotal: total);
    } catch (e) {
      debugPrint('[SalesInvoices] receipt vouchers total failed: $e');
    }
  }

  void loadMore() {
    state = state.copyWith(displayLimit: state.displayLimit + 50);
    _applyFilters();
  }

  void updateSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
    _applyFilters();
  }

  void updateDateRange(DateTimeRange? range) {
    state = state.copyWith(dateRange: range, clearDateRange: range == null);
    _applyFilters();
  }

  /// Issue 8 — toggle a single status in/out of the multi-select set.
  /// `value=true` adds it, `value=false` removes it. Empty set == "all".
  void toggleStatusFilter(String status, bool value) {
    final next = Set<String>.from(state.statusFilters);
    if (value) {
      next.add(status);
    } else {
      next.remove(status);
    }
    state = state.copyWith(statusFilters: next);
    _applyFilters();
  }

  void clearStatusFilters() {
    state = state.copyWith(statusFilters: const {});
    _applyFilters();
  }

  /// Issue 8 — clearing every filter at once (used by the "no results"
  /// empty state's reset button so the user can recover from a mistakenly
  /// narrow filter combination without poking each chip individually).
  void clearAllFilters() {
    state = state.copyWith(
      statusFilters: const {},
      searchQuery: '',
      clearDateRange: true,
      clearWarehouse: true,
      clearBranch: true,
      clearCostCenter: true,
    );
    _applyFilters();
  }

  /// True iff at least one filter is narrowing the result set. Used by the
  /// table's empty-state to decide whether to show "no invoices" or "no
  /// results — reset filters?".
  bool get hasActiveFilters {
    final s = state;
    return s.statusFilters.isNotEmpty ||
        s.searchQuery.isNotEmpty ||
        s.dateRange != null ||
        s.selectedWarehouseId != null ||
        s.selectedBranchId != null ||
        s.selectedCostCenterId != null;
  }

  /// Issue 8 — picking a warehouse that belongs to a different branch than
  /// the active branch filter would silently produce zero results. Auto-clear
  /// the branch filter so the warehouse choice "wins" and the user sees rows.
  /// Returns true if the branch filter was cleared (UI shows a toast).
  bool updateWarehouseFilter(int? warehouseId, {int? warehouseBranchId}) {
    var clearedBranch = false;
    if (warehouseId == null) {
      state = state.copyWith(clearWarehouse: true);
    } else {
      final activeBranch = state.selectedBranchId;
      if (activeBranch != null &&
          warehouseBranchId != null &&
          warehouseBranchId != activeBranch) {
        state = state.copyWith(
          selectedWarehouseId: warehouseId,
          clearBranch: true,
        );
        clearedBranch = true;
      } else {
        state = state.copyWith(selectedWarehouseId: warehouseId);
      }
    }
    _applyFilters();
    return clearedBranch;
  }

  /// Issue 8 — symmetric to [updateWarehouseFilter]: switching to a branch
  /// that doesn't own the active warehouse clears the warehouse so the new
  /// branch's invoices actually appear. Returns true if the warehouse was
  /// auto-cleared (UI shows a toast).
  bool updateBranchFilter(int? branchId, {Map<int, int?> warehouseBranchMap = const {}}) {
    var clearedWarehouse = false;
    if (branchId == null) {
      state = state.copyWith(clearBranch: true);
    } else {
      final activeWh = state.selectedWarehouseId;
      if (activeWh != null && warehouseBranchMap[activeWh] != branchId) {
        state = state.copyWith(
          selectedBranchId: branchId,
          clearWarehouse: true,
        );
        clearedWarehouse = true;
      } else {
        state = state.copyWith(selectedBranchId: branchId);
      }
    }
    _applyFilters();
    return clearedWarehouse;
  }

  /// Cluster 025 / Issue 3: switch how the rows are ordered. Re-applies
  /// filters so the change shows up immediately without a re-fetch.
  void updateSortMode(SalesInvoiceSortMode mode) {
    if (mode == state.sortMode) return;
    state = state.copyWith(sortMode: mode);
    _applyFilters();
  }

  void updateCostCenterFilter(int? costCenterId) {
    if (costCenterId == null) {
      state = state.copyWith(clearCostCenter: true);
    } else {
      state = state.copyWith(selectedCostCenterId: costCenterId);
    }
    _applyFilters();
  }

  void toggleSelection(int invoiceId) {
    final newSelection = Set<int>.from(state.selectedInvoices);
    if (newSelection.contains(invoiceId)) {
      newSelection.remove(invoiceId);
    } else {
      newSelection.add(invoiceId);
    }
    state = state.copyWith(selectedInvoices: newSelection);
  }

  void toggleAllSelection() {
    if (state.selectedInvoices.length == state.filteredInvoices.length) {
      state = state.copyWith(selectedInvoices: {});
    } else {
      state = state.copyWith(
        selectedInvoices: Set.from(state.filteredInvoices.map((e) => e.id)),
      );
    }
  }

  void clearSelection() {
    state = state.copyWith(selectedInvoices: {});
  }

  Future<List<Party>> getCustomers() async {
    final partiesRepo = ref.read(partiesRepositoryProvider);
    return partiesRepo.watchCustomers().first;
  }

  Future<List<Product>> getProducts() async {
    final repo = ref.read(productRepositoryProvider);
    return repo.getAllProducts();
  }

  Future<List<Category>> getCategories() async {
    final repo = ref.read(productRepositoryProvider);
    return repo.getCategories();
  }

  Future<List<WarehouseData>> getActiveWarehouses() async {
    final repo = ref.read(inventoryRepositoryProvider);
    return repo.watchWarehouses().first;
  }

  Future<List<SalesInvoiceItemWithProduct>> getInvoiceItems(
    int invoiceId,
  ) async {
    final salesRepo = ref.read(salesRepositoryProvider);
    return salesRepo.getInvoiceItemsWithProduct(invoiceId);
  }

  Future<Party?> getCustomerById(int customerId) async {
    final partiesRepo = ref.read(partiesRepositoryProvider);
    return partiesRepo.getPartyById(customerId);
  }

  Future<String?> getCompanyName() async {
    final settingsRepo = ref.read(settingsRepositoryProvider);
    return settingsRepo.getSetting('company_name');
  }

  Future<void> updateInvoicePayment(
    int invoiceId,
    double newPaid,
    String paymentMethod,
    String invoiceNumber,
    double total,
  ) async {
    final salesRepo = ref.read(salesRepositoryProvider);
    final auth = ref.read(authProvider);
    // Spec 151 C-05: thread the acting user so the collection's receipt voucher
    // (and its JE) is attributable server-side and standalone.
    await salesRepo.recordPayment(invoiceId, newPaid, userId: auth.user?.id);

    final activityLogRepo = ref.read(activityLogRepositoryProvider);
    await activityLogRepo.logActivity(
      userId: auth.user?.id,
      userName: auth.user?.displayName ?? 'Admin',
      action: 'update_sale_payment',
      entityType: 'sales_invoice',
      entityId: invoiceId,
      description: tr('تعديل دفعة فاتورة مبيعات {invoiceNumber}', {'invoiceNumber': invoiceNumber}),
      amount: total,
    );
  }

  Future<void> deleteInvoice(
    int invoiceId,
    String invoiceNumber,
    double total,
  ) async {
    final salesRepo = ref.read(salesRepositoryProvider);
    final auth = ref.read(authProvider);
    // C-02/062: thread the acting user so the server's voidPaidInvoice
    // critical-op gate resolves a real userId (null → PermissionDenied →
    // silent void loss for fully-paid invoices).
    await salesRepo.cancelInvoice(invoiceId, userId: auth.user?.id);

    final activityLogRepo = ref.read(activityLogRepositoryProvider);
    await activityLogRepo.logActivity(
      userId: auth.user?.id,
      userName: auth.user?.displayName ?? 'Admin',
      action: 'delete_sale',
      entityType: 'sales_invoice',
      entityId: invoiceId,
      description: tr('حذف فاتورة مبيعات {invoiceNumber}', {'invoiceNumber': invoiceNumber}),
      amount: total,
    );
  }

  /// تحقّقٌ من إذن الحذف: كلمةُ مرور المدير **أو** مستخدمٌ مديرٌ بكلمته.
  ///
  /// 🔴 الاحتياطيُّ الثاني ليس ترفاً. كلمةُ مرور المدير تعيش في `settings`
  /// وقد توقّف تسليمُها إلى العملاء (`kServerSecretSettingKeys` على
  /// `GET /api/settings`) — وهو صوابٌ أمنيّاً. لكنّ الأثرَ الجانبيَّ أنّ
  /// **أيَّ عميلٍ جديدٍ لا يستلمها أبداً**، فيفشل هذا التحقّقُ دائماً
  /// ويصير حذفُ الفواتير مستحيلاً عليه — بلا رسالةٍ مفهومة، إذ تظهر
  /// «كلمة مرور خاطئة» على كلمةٍ صحيحة.
  ///
  /// وشاشةُ القفل (`app_main_screen`) وإغلاقُ الوردية
  /// (`pos_closing_controller`) تحملان هذا الاحتياطيَّ سلفاً — فهذا توحيدٌ
  /// لسلوكٍ قائمٍ لا توسيعٌ للسطح: من يفكّ قفلَ الجهاز يستطيع الحذف.
  Future<bool> verifyAdminPassword(String password) async {
    if (await ref.read(adminPasswordServiceProvider).verify(password)) {
      return true;
    }
    final user = await ref
        .read(authRepositoryProvider)
        .authenticateByPasswordOrCard(password.trim());
    if (user == null) return false;
    final roleName = user.role?.name.toLowerCase() ?? '';
    return (user.role?.isSystemRole ?? false) ||
        roleName.contains('admin') ||
        roleName.contains('مدير');
  }
}

final salesInvoicesControllerProvider =
    NotifierProvider<SalesInvoicesController, SalesInvoicesScreenState>(() {
      return SalesInvoicesController();
    });
