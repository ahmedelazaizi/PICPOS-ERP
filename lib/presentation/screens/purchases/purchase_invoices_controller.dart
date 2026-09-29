import 'package:ural_erp/core/i18n/tr.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/app_config.dart';
import '../../../core/config/business_profile_provider.dart';
import '../../../core/navigation/screen_id.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/entities/invoice_entity.dart';
import '../../../domain/models/purchase_doc.dart';

/// إجمالياتُ **الفترة السابقة** لفواتير المشتريات — نافذةٌ بنفس الطول تسبق
/// المدى المختار مباشرةً وتُقاس بنفس المرشِّحات.
///
/// ‏`null` تعني «لا مقارنةَ متاحة» لا «صفر». ونظيرُها في المبيعات
/// `SalesPreviousPeriod` — والفرقُ الوحيدُ أن «المدفوع» هنا لا يضمّ سنداتِ
/// صرفٍ لأن الشاشةَ لا تحملها أصلاً في الفترة الحاليّة، فالطرفان يُقاسان
/// بنفس التعريف.
class PurchasePreviousPeriod {
  const PurchasePreviousPeriod({
    required this.totalAmount,
    required this.totalPaid,
    required this.totalRemaining,
    required this.totalReturns,
    required this.invoiceCount,
  });

  final double totalAmount;
  final double totalPaid;
  final double totalRemaining;
  final double totalReturns;
  final int invoiceCount;
}

class PurchaseInvoicesScreenState {
  final List<InvoiceEntity> allInvoices;
  final List<InvoiceEntity> filteredInvoices;
  final Map<int, String> supplierNames;
  final Map<int, String> warehouseNames;
  final Map<int, int?> warehouseBranchId; // warehouseId → branchId
  final Map<int, String> branchNames;
  final Map<int, String> costCenterNames;
  final bool isLoading;
  final DateTimeRange? dateRange;
  final String statusFilter;
  final String searchQuery;
  final int? selectedWarehouseId;
  final int? selectedBranchId;
  final int? selectedCostCenterId;
  final Set<int> selectedInvoices;

  // returnedAmounts[invoiceId] = total purchase-return value (computed
  // from stock_movements with reference_type='purchase_return'). Used
  // to adjust each row's remaining and to surface "إجمالي المرتجعات".
  final Map<int, double> returnedAmounts;

  // Summaries
  final double totalAmount;
  final double totalPaid;
  final double totalRemaining;
  final double totalReturns;
  final int invoiceCount;

  /// عدّاداتُ شرائحِ الحالة — `paid`/`partial`/`unpaid` — من تجميعِ SQL.
  ///
  /// فارغةٌ حتى يصل التجميع، والشريحةُ لا تعرض عدّاداً حينئذٍ: «‏0» كان
  /// سيعني «لا فواتيرَ بهذه الحالة» وهو ما لم يُقَس بعد.
  final Map<String, int> statusCounts;

  /// أوامرُ الشراء المحمّلة — **فارغةٌ خارجَ نطاق `unified`**، فشاشةُ
  /// أوامر الشراء ليست في أيّ نطاقٍ آخر (`ScreenRegistry`).
  final List<PurchaseOrderRow> allOrders;

  /// المستنداتُ المعروضةُ مدموجةً ومرتّبةً بالأحدث.
  final List<PurchaseDoc> filteredDocs;

  /// مرشِّحُ «نوع المستند» — قرارُ المالك 2026-09-18.
  final PurchaseDocTypeFilter docTypeFilter;

  /// معرّفاتُ الفواتير التي **لها قيدٌ مُرحَّلٌ فعلاً** في الأستاذ.
  ///
  /// ⚠️ **و`null` ليست «لا شيء مُرحَّل» بل «لم يُعرَف بعد».**
  /// الاستعلامُ يصل بعد التحميل الأوّل وقد يُخفق؛ ومجموعةٌ فارغةٌ
  /// في الحالتين كانت ستكتب «غير مُرحَّل» حمراء على **كلّ** فاتورة،
  /// وهو إنذارٌ ماليٌّ كاذبٌ أسوأُ من لا شيء. فالعمودُ يرسم «—»
  /// حتّى يصل جوابٌ.
  final Set<int>? postedInvoiceIds;

  /// إجمالياتُ الفترة السابقة — `null` ⇒ لا شارةَ اتّجاه.

  final PurchasePreviousPeriod? previousPeriod;

  final int displayLimit;
  final bool hasMore;

  PurchaseInvoicesScreenState({
    this.allInvoices = const [],
    this.filteredInvoices = const [],
    this.supplierNames = const {},
    this.warehouseNames = const {},
    this.warehouseBranchId = const {},
    this.branchNames = const {},
    this.costCenterNames = const {},
    this.returnedAmounts = const {},
    this.isLoading = true,
    this.dateRange,
    this.statusFilter = 'all',
    this.searchQuery = '',
    this.selectedWarehouseId,
    this.selectedBranchId,
    this.selectedCostCenterId,
    this.selectedInvoices = const {},
    this.totalAmount = 0,
    this.totalPaid = 0,
    this.totalRemaining = 0,
    this.totalReturns = 0,
    this.invoiceCount = 0,
    this.statusCounts = const {},
    this.postedInvoiceIds,
    this.allOrders = const [],
    this.filteredDocs = const [],
    this.docTypeFilter = PurchaseDocTypeFilter.all,

    this.previousPeriod,
    this.displayLimit = 50,
    this.hasMore = false,
  });

  PurchaseInvoicesScreenState copyWith({
    List<InvoiceEntity>? allInvoices,
    List<InvoiceEntity>? filteredInvoices,
    Map<int, String>? supplierNames,
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
    String? statusFilter,
    String? searchQuery,
    int? selectedWarehouseId,
    bool clearWarehouse = false,
    int? selectedBranchId,
    bool clearBranch = false,
    int? selectedCostCenterId,
    bool clearCostCenter = false,
    Set<int>? selectedInvoices,
    double? totalAmount,
    double? totalPaid,
    double? totalRemaining,
    double? totalReturns,
    int? invoiceCount,
    Map<String, int>? statusCounts,
    Set<int>? postedInvoiceIds,
    List<PurchaseOrderRow>? allOrders,
    List<PurchaseDoc>? filteredDocs,
    PurchaseDocTypeFilter? docTypeFilter,
    bool clearPostedInvoiceIds = false,

    PurchasePreviousPeriod? previousPeriod,
    bool clearPreviousPeriod = false,
    int? displayLimit,
    bool? hasMore,
  }) {
    return PurchaseInvoicesScreenState(
      allInvoices: allInvoices ?? this.allInvoices,
      filteredInvoices: filteredInvoices ?? this.filteredInvoices,
      supplierNames: supplierNames ?? this.supplierNames,
      warehouseNames: warehouseNames ?? this.warehouseNames,
      warehouseBranchId: warehouseBranchId ?? this.warehouseBranchId,
      branchNames: branchNames ?? this.branchNames,
      costCenterNames: costCenterNames ?? this.costCenterNames,
      returnedAmounts: returnedAmounts ?? this.returnedAmounts,
      isLoading: isLoading ?? this.isLoading,
      dateRange: clearDateRange ? null : (dateRange ?? this.dateRange),
      statusFilter: statusFilter ?? this.statusFilter,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedWarehouseId: clearWarehouse ? null : (selectedWarehouseId ?? this.selectedWarehouseId),
      selectedBranchId: clearBranch ? null : (selectedBranchId ?? this.selectedBranchId),
      selectedCostCenterId: clearCostCenter ? null : (selectedCostCenterId ?? this.selectedCostCenterId),
      selectedInvoices: selectedInvoices ?? this.selectedInvoices,
      totalAmount: totalAmount ?? this.totalAmount,
      totalPaid: totalPaid ?? this.totalPaid,
      totalRemaining: totalRemaining ?? this.totalRemaining,
      totalReturns: totalReturns ?? this.totalReturns,
      invoiceCount: invoiceCount ?? this.invoiceCount,
      statusCounts: statusCounts ?? this.statusCounts,
      allOrders: allOrders ?? this.allOrders,
      filteredDocs: filteredDocs ?? this.filteredDocs,
      docTypeFilter: docTypeFilter ?? this.docTypeFilter,
      postedInvoiceIds: clearPostedInvoiceIds
          ? null
          : (postedInvoiceIds ?? this.postedInvoiceIds),

      previousPeriod: clearPreviousPeriod
          ? null
          : (previousPeriod ?? this.previousPeriod),
      displayLimit: displayLimit ?? this.displayLimit,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}

class PurchaseInvoicesController extends Notifier<PurchaseInvoicesScreenState> {
  Timer? _debounce;
  bool _disposed = false;

  @override
  PurchaseInvoicesScreenState build() {
    _disposed = false;

    // Drift .watch() path — fires on local inserts and on server inserts
    // via markTablesUpdated. Debounced so bursty signals coalesce.
    ref.listen(purchaseInvoicesChangeProvider, (_, _) {
      if (_disposed) return;
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 150), () {
        if (!_disposed) _refreshInvoices();
      });
    });

    // Belt-and-suspenders: also listen to the API broadcast stream so the
    // server's UI refreshes even if drift_postgres .watch() drops a signal
    // (observed in practice when a client posts a purchase). The 150ms
    // debounce coalesces any duplicate triggers with the Drift path above.
    ref.listen(serverDataChangeProvider, (_, next) {
      if (_disposed) return;
      next.whenData((table) {
        if (table != 'purchases') return;
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 150), () {
          if (!_disposed) _refreshInvoices();
        });
      });
    });

    ref.onDispose(() {
      _disposed = true;
      _debounce?.cancel();
    });

    _initData();
    return PurchaseInvoicesScreenState();
  }

  void _initData() async {
    final partiesRepo = ref.read(partiesRepositoryProvider);
    final db = ref.read(databaseProvider);
    final accRepo = ref.read(accountingRepositoryProvider);

    // Load supplier names
    final suppliers = await partiesRepo.watchSuppliers().first;
    final names = <int, String>{};
    for (final s in suppliers) {
      names[s.id] = s.name;
    }

    // Load warehouse → name + branchId mapping so the table can show
    // "branch / warehouse" without N+1 lookups per row.
    final warehouses = await db.select(db.warehouses).get();
    final whNames = <int, String>{};
    final whToBranch = <int, int?>{};
    for (final w in warehouses) {
      whNames[w.id] = w.name;
      whToBranch[w.id] = w.branchId;
    }

    // Load branch names for display + filter dropdown
    final branches = await db.watchBranches().first;
    final brNames = <int, String>{
      for (final b in branches) b.id: b.name,
    };

    // Load cost center names for display + filter dropdown
    final costCenters = await accRepo.getCostCenters();
    final ccNames = <int, String>{
      for (final c in costCenters) c.id: c.name,
    };

    if (_disposed) return;
    state = state.copyWith(
      supplierNames: names,
      warehouseNames: whNames,
      warehouseBranchId: whToBranch,
      branchNames: brNames,
      costCenterNames: ccNames,
    );

    await _refreshInvoices();
  }

  /// One-shot fetch of purchase invoices — always hits the DB directly so a
  /// single Drift `.watch()` subscription never becomes a single point of
  /// failure. Triggered by both table-change and server-broadcast listeners.
  Future<void> _refreshInvoices() async {
    try {
      final purchasesRepo = ref.read(purchasesRepositoryProvider);
      var invoices = await purchasesRepo.watchInvoices().first;
      if (_disposed) return;
      // Phase 5C.2 (Issue 4) — branch-scope guard. Mirrors the sales
      // controller pattern in 5C.1: the repository may return rows from
      // branches the current user shouldn't see (legacy data, an
      // unscoped path, or an in-flight migration). Filter at the
      // controller layer so the auth boundary is enforced regardless of
      // where the row came from. Admin (BranchScope.fullAccess) skips.
      final scope = await ref.read(branchScopeProvider.future);
      if (!scope.hasFullAccess) {
        final before = invoices.length;
        invoices = invoices.where((inv) => scope.isAllowed(inv.branchId)).toList();
        if (before != invoices.length) {
          debugPrint('[PurchaseInvoices] BranchScope dropped '
              '${before - invoices.length} cross-branch rows');
        }
      }
      state = state.copyWith(
        allInvoices: invoices,
        isLoading: false,
        // صفحةٌ جديدةٌ ⇒ جوابٌ جديد، وإبقاءُ القديم يرسم حالةَ
        // فواتيرَ أخرى على هذه.
        clearPostedInvoiceIds: true,
      );

      // Pull purchase-return amounts for every loaded invoice. Source is
      // stock_movements with reference_type='purchase_return' (see
      // PurchaseDao.getPurchaseReturnedAmountsForInvoices). Done after
      // the main load so the table renders quickly even on slow disks;
      // the second setState retriggers _applyFilters with the new map.
      try {
        final ids = invoices
            .where((inv) => inv.id != null)
            .map((inv) => inv.id!)
            .toList();
        if (ids.isNotEmpty) {
          final db = ref.read(databaseProvider);
          final returned =
              await db.getPurchaseReturnedAmountsForInvoices(ids);
          if (!_disposed) {
            state = state.copyWith(returnedAmounts: returned);
          }
        }
      } catch (e) {
        // Non-fatal — list still works, just without returns adjustment.
      }

      // وحالةُ الترحيل: تُقرأ من **الأستاذ نفسِه** لا من `isLocked` التي
      // تكذب في ثلاث حالات — راجع [postedPurchaseInvoiceIds].
      //
      // ⚠️ والإخفاقُ يُبقيها `null` («لم يُعرَف») لا مجموعةً فارغةً
      // («لا شيء مُرحَّل»): الثانيةُ تصبغ كلَّ الصفوف بإنذارٍ كاذب.
      try {
        final ids = invoices
            .where((inv) => inv.id != null)
            .map((inv) => inv.id!)
            .toList();
        final db = ref.read(databaseProvider);
        final posted = await db.postedPurchaseInvoiceIds(ids);
        if (!_disposed) {
          state = state.copyWith(postedInvoiceIds: posted);
        }
      } catch (_) {
        // يبقى `null` ⇒ العمودُ يرسم «—» ولا يدّعي علماً.
      }

      await _loadPurchaseOrders();

      _applyFilters();
    } catch (_) {
      if (!_disposed) state = state.copyWith(isLoading: false);
    }
  }

  /// أوامرُ الشراء — **ولا تُحمَّل خارجَ نطاقِها**.
  ///
  /// ⚠️ `ScreenId.purchaseOrders` في `ScreenRegistry.unified` **وحدَه**. ففي
  /// بقيّة الأنماط لا وجودَ للمستند أصلاً، وقراءتُه هناك تملأ قائمةً
  /// بمستنداتٍ لا شاشةَ لها ولا مرشِّحَ يستثنيها.
  Future<void> _loadPurchaseOrders() async {
    if (!AppConfig.allowedScreenIds.contains(ScreenId.purchaseOrders)) {
      return;
    }
    try {
      final repo = ref.read(purchaseOrdersRepositoryProvider);
      final rows = await repo.watchPurchaseOrders().first;
      if (_disposed) return;
      state = state.copyWith(
        allOrders: [
          for (final o in rows)
            PurchaseOrderRow(
              id: o.id,
              orderNumber: o.orderNumber,
              supplierId: o.supplierId,
              orderDate: o.orderDate,
              total: o.total,
              status: o.status,
              warehouseId: o.warehouseId,
              costCenterId: o.costCenterId,
              convertedToInvoiceId: o.convertedToInvoiceId,
            ),
        ],
      );
      _applyFilters();
    } catch (_) {
      // القائمةُ تعمل بالفواتير وحدَها.
    }
  }

  void _applyFilters() {

    var filtered = state.allInvoices.toList();

    // Text search
    final query = state.searchQuery.toLowerCase();
    if (query.isNotEmpty) {
      filtered = filtered.where((InvoiceEntity inv) {
        final invoiceMatch = inv.invoiceNumber.toLowerCase().contains(query);
        final supplierName = inv.partyId != null
            ? (state.supplierNames[inv.partyId]?.toLowerCase() ?? '')
            : '';
        final supplierMatch = supplierName.contains(query);
        return invoiceMatch || supplierMatch;
      }).toList();
    }

    // Date range
    if (state.dateRange != null) {
      filtered = filtered
          .where(
            (InvoiceEntity inv) =>
                inv.invoiceDate.isAfter(
                  state.dateRange!.start.subtract(const Duration(days: 1)),
                ) &&
                inv.invoiceDate.isBefore(
                  state.dateRange!.end.add(const Duration(days: 1)),
                ),
          )
          .toList();
    }

    // Warehouse filter
    if (state.selectedWarehouseId != null) {
      filtered = filtered.where((InvoiceEntity inv) => inv.warehouseId == state.selectedWarehouseId).toList();
    }

    // Branch filter — direct match on invoice.branchId (L3) with fallback
    // to warehouse → branch lookup for legacy rows.
    if (state.selectedBranchId != null) {
      filtered = filtered.where((InvoiceEntity inv) {
        if (inv.branchId == state.selectedBranchId) return true;
        final whId = inv.warehouseId;
        if (whId == null) return false;
        return state.warehouseBranchId[whId] == state.selectedBranchId;
      }).toList();
    }

    // Cost center filter — direct match on invoice.costCenterId
    if (state.selectedCostCenterId != null) {
      filtered = filtered.where((InvoiceEntity inv) =>
          inv.costCenterId == state.selectedCostCenterId).toList();
    }

    // Status filter
    if (state.statusFilter == 'paid') {
      filtered = filtered.where((InvoiceEntity inv) => inv.status == InvoiceStatus.paid).toList();
    } else if (state.statusFilter == 'partial') {
      filtered = filtered.where((InvoiceEntity inv) => inv.status == InvoiceStatus.partial).toList();
    } else if (state.statusFilter == 'unpaid') {
      filtered = filtered.where((InvoiceEntity inv) => inv.status == InvoiceStatus.pending).toList();
    }

    // Calculate summaries — subtract any purchase-return amount from
    // each invoice's remaining so the dashboard total reflects refunds
    // received, not just payments made.
    final totalAmount = filtered.fold(0.0, (double sum, InvoiceEntity inv) => sum + inv.total);
    final totalPaid = filtered.fold(0.0, (double sum, InvoiceEntity inv) => sum + inv.paid);
    final totalReturned = filtered.fold(
      0.0,
      (double sum, InvoiceEntity inv) =>
          sum + (state.returnedAmounts[inv.id] ?? 0.0),
    );
    final totalRemaining = totalAmount - totalPaid - totalReturned;
    final invoiceCount = filtered.length;

    // القائمةُ المعروضةُ: فواتيرُ وأوامرُ معاً مرتّبةً بالأحدث.
    //
    // ⚠️ **والإجماليّاتُ محسوبةٌ قبلَ هذا ومن `filtered` وحدَها.**
    // أمرُ الشراء التزامٌ لم يُستلَم ولم يُرحَّل؛ وضمُّه إلى «إجمالي
    // المشتريات» يعدُّ المبلغَ **مرّتَين** عند تحويله إلى فاتورة.
    final docs = mergePurchaseDocs(
      invoices: filtered,
      orders: _ordersMatchingFilters(),
      typeFilter: state.docTypeFilter,
    );

    state = state.copyWith(
      filteredInvoices: filtered.take(state.displayLimit).toList(),
      filteredDocs: docs.take(state.displayLimit).toList(),
      totalAmount: totalAmount,
      totalPaid: totalPaid,
      totalRemaining: totalRemaining,
      totalReturns: totalReturned,
      invoiceCount: invoiceCount,
      hasMore: filtered.length > state.displayLimit,
    );

    // الطيُّ أعلاه يمرّ على صفحةٍ سقفُها ٥٠٠ صفّ (`watchAllPurchases`)، فهو
    // رسمةٌ أولى لا رقمٌ نهائيّ. تُعاد الاشتقاقُ من تجميعِ SQL على **كلّ**
    // الصفوف المطابِقة — بلا انتظارٍ كي يبقى الترشيحُ سريعاً، والبطاقاتُ
    // تتحدّث عند أوّل إشعارٍ بعد وصولِ النتيجة.
    unawaited(_refreshSummaryTotals());
  }

  /// الأوامرُ المطابِقةُ للمرشِّحات التي **تنطبق عليها**.
  ///
  /// ⚠️ وليست كلُّ مرشِّحات الفواتير تنطبق: لا فرعَ مختوماً على أمر
  /// الشراء ولا حالةَ سدادٍ له. وإسقاطُ الأوامر عند ترشيحٍ لا معنى
  /// له عندها أصدقُ من إبقائها: من يرشّح بـ«غير مدفوع» يسأل عن
  /// ذمّةٍ، والأمرُ لا ذمّةَ له.
  List<PurchaseOrderRow> _ordersMatchingFilters() {
    if (state.allOrders.isEmpty) return const [];
    var rows = state.allOrders;

    final query = state.searchQuery.toLowerCase();
    if (query.isNotEmpty) {
      rows = rows.where((o) {
        final supplier =
            state.supplierNames[o.supplierId]?.toLowerCase() ?? '';
        return o.orderNumber.toLowerCase().contains(query) ||
            supplier.contains(query);
      }).toList();
    }
    final range = state.dateRange;
    if (range != null) {
      rows = rows
          .where((o) =>
              o.orderDate
                  .isAfter(range.start.subtract(const Duration(days: 1))) &&
              o.orderDate.isBefore(range.end.add(const Duration(days: 1))))
          .toList();
    }
    if (state.selectedWarehouseId != null) {
      rows = rows
          .where((o) => o.warehouseId == state.selectedWarehouseId)
          .toList();
    }
    if (state.selectedCostCenterId != null) {
      rows = rows
          .where((o) => o.costCenterId == state.selectedCostCenterId)
          .toList();
    }
    if (state.selectedBranchId != null || state.statusFilter != 'all') {
      return const [];
    }
    return rows;
  }

  /// هل ثمّةَ مرشِّحٌ فعّالٌ الآن؟ — تُميّز «لا فواتيرَ إطلاقاً» من «المرشِّحاتُ
  /// ضيّقت النتيجةَ إلى الصفر»، فتُعرَض إعادةُ التعيين في الحالة الثانية فقط.
  bool get hasActiveFilters =>
      state.searchQuery.trim().isNotEmpty ||
      state.dateRange != null ||
      state.statusFilter != 'all' ||
      state.selectedWarehouseId != null ||
      state.selectedBranchId != null ||
      state.selectedCostCenterId != null ||
      state.docTypeFilter != PurchaseDocTypeFilter.all;

  /// إعادةُ تعيين كلّ المرشِّحات دفعةً واحدة — تطبيقٌ واحدٌ لا ستّة.
  void clearAllFilters() {
    state = state.copyWith(
      searchQuery: '',
      clearDateRange: true,
      statusFilter: 'all',
      clearWarehouse: true,
      clearBranch: true,
      clearCostCenter: true,
      docTypeFilter: PurchaseDocTypeFilter.all,
    );
    _applyFilters();
  }

  /// إجمالياتُ البطاقات من SQL — لا من الصفحة المحمَّلة.
  ///
  /// لا تعمل إلّا مع مدىً تاريخيٍّ مختار: بلا مدىً كان التجميعُ سيمسح الجدولَ
  /// كلَّه مع كلّ تغييرِ مرشِّح، والعرضُ غيرُ المحدَّد بمدىً هو عرضُ «كلّ شيء»
  /// الذي يكفيه طيُّ الصفحة. ومع مدىً فعّالٍ — وهو بالضبط حين يقرأ المشغّلُ
  /// الأرقام — قد ينحرف طيُّ الصفحة بمقدارٍ غيرِ محدود.
  ///
  /// ولا تُربَط بصندوق البحث عمداً: البحثُ تضييقٌ للمعروض، وإعادةُ الاستعلام
  /// مع كلّ حرفٍ كانت استعلاماً لكلّ ضغطةِ مفتاح.
  Future<void> _refreshSummaryTotals() async {
    if (_disposed) return;
    final range = state.dateRange;
    if (range == null) return;
    if (state.searchQuery.trim().isNotEmpty) return;
    try {
      final db = ref.read(databaseProvider);
      final summary = await db.getPurchaseInvoiceSummary(
        from: range.start,
        to: range.end,
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
      unawaited(_refreshPreviousPeriod(range));
    } catch (e) {
      // يُترَك طيُّ الصفحة مكانَه بدل تفريغ البطاقات — ويُقال ذلك صراحةً،
      // فالسقوطُ الصامتُ إلى رقمٍ مبتورٍ هو العطبُ عينُه.
      debugPrint(
          '[PurchaseInvoices] SQL summary failed, showing paged totals: $e');
    }
  }

  /// إجمالياتُ الفترة السابقة — نافذةٌ **بنفس الطول** تسبق المدى المختار
  /// مباشرةً وبنفس المرشِّحات، كي تكون المقارنةُ على المقدار لا على المدى.
  ///
  /// وأيُّ إخفاقٍ يمسح المقارنةَ إلى `null` ولا يُبقي رقمَ مدىً قديمٍ معلَّقاً:
  /// شارةُ اتّجاهٍ تقارن فترةً بفترةٍ أخرى هي الكذبةُ المحذَّرُ منها، لا غيابُ
  /// الشارة.
  Future<void> _refreshPreviousPeriod(DateTimeRange range) async {
    if (_disposed) return;
    try {
      final startDay =
          DateTime(range.start.year, range.start.month, range.start.day);
      final endExclusive =
          DateTime(range.end.year, range.end.month, range.end.day + 1);
      final lengthDays = endExclusive.difference(startDay).inDays;
      if (lengthDays <= 0) {
        if (state.previousPeriod != null) {
          state = state.copyWith(clearPreviousPeriod: true);
        }
        return;
      }
      final prevStart = startDay.subtract(Duration(days: lengthDays));
      // نفسُ اصطلاحِ النداء الحاليّ: `to` يومٌ داخلَ النافذة لا بعدَها.
      final prevTo = startDay.subtract(const Duration(days: 1));

      final db = ref.read(databaseProvider);
      final summary = await db.getPurchaseInvoiceSummary(
        from: prevStart,
        to: prevTo,
        warehouseIds: state.selectedWarehouseId != null
            ? [state.selectedWarehouseId!]
            : null,
        branchId: state.selectedBranchId,
        costCenterId: state.selectedCostCenterId,
      );
      if (_disposed) return;
      state = state.copyWith(
        previousPeriod: PurchasePreviousPeriod(
          totalAmount: summary.totalAmount,
          totalPaid: summary.totalPaid,
          totalRemaining: summary.totalRemaining,
          totalReturns: summary.totalReturns,
          invoiceCount: summary.invoiceCount,
        ),
      );
    } catch (e) {
      debugPrint('[PurchaseInvoices] previous-period summary failed: $e');
      if (!_disposed && state.previousPeriod != null) {
        state = state.copyWith(clearPreviousPeriod: true);
      }
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

  void updateStatusFilter(String status) {
    state = state.copyWith(statusFilter: status);
    _applyFilters();
  }

  void updateWarehouseFilter(int? warehouseId) {
    if (warehouseId == null) {
      state = state.copyWith(clearWarehouse: true);
    } else {
      state = state.copyWith(selectedWarehouseId: warehouseId);
    }
    _applyFilters();
  }

  void updateBranchFilter(int? branchId) {
    if (branchId == null) {
      state = state.copyWith(clearBranch: true);
    } else {
      state = state.copyWith(selectedBranchId: branchId);
    }
    _applyFilters();
  }

  /// يبدّل مرشِّحَ «نوع المستند».
  void updateDocTypeFilter(PurchaseDocTypeFilter value) {
    state = state.copyWith(docTypeFilter: value);
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

  Future<List<Party>> getSuppliers() async {
    final repo = ref.read(partiesRepositoryProvider);
    return repo.watchSuppliers().first;
  }

  Future<List<Product>> getProducts() async {
    final repo = ref.read(productRepositoryProvider);
    return repo.getAllProducts();
  }

  Future<List<Category>> getCategories() async {
    final repo = ref.read(productRepositoryProvider);
    return repo.getCategories();
  }

  Future<List<PurchaseInvoiceItemWithProduct>> getInvoiceItems(
    int invoiceId,
  ) async {
    final purchasesRepo = ref.read(purchasesRepositoryProvider);
    return purchasesRepo.getInvoiceItemsWithProduct(invoiceId);
  }

  Future<Party?> getSupplierById(int supplierId) async {
    final repo = ref.read(partiesRepositoryProvider);
    return repo.getPartyById(supplierId);
  }

  Future<String?> getCompanyName() async {
    final repo = ref.read(settingsRepositoryProvider);
    return repo.getSetting('company_name');
  }

  Future<void> deleteInvoice(
    int invoiceId,
    String invoiceNumber,
    double total,
  ) async {
    final repo = ref.read(purchasesRepositoryProvider);
    await repo.deleteInvoice(invoiceId);

    final auth = ref.read(authProvider);
    final activityLogRepo = ref.read(activityLogRepositoryProvider);
    await activityLogRepo.logActivity(
      userId: auth.user?.id,
      userName: auth.user?.displayName ?? 'Admin',
      action: 'delete_purchase',
      entityType: 'purchase_invoice',
      entityId: invoiceId,
      description: tr('حذف فاتورة مشتريات {invoiceNumber}', {'invoiceNumber': invoiceNumber}),
      amount: total,
    );
  }

  /// تحقّقٌ من إذن الحذف: كلمةُ مرور المدير **أو** مستخدمٌ مديرٌ بكلمته.
  /// نظيرُ [SalesInvoicesController.verifyAdminPassword] — وعلّتُه نفسُها:
  /// كلمةُ المدير لم تعد تُسلَّم إلى العملاء، فبلا الاحتياطيِّ يصير الحذفُ
  /// مستحيلاً على كلِّ عميلٍ جديد.
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

final purchaseInvoicesControllerProvider =
    NotifierProvider<PurchaseInvoicesController, PurchaseInvoicesScreenState>(
      () {
        return PurchaseInvoicesController();
      },
    );
