import 'dart:async';
import 'package:ural_erp/core/constants/app_constants.dart';
import 'package:ural_erp/core/errors/app_exceptions.dart';
import 'package:ural_erp/core/utils/financial_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/providers/providers.dart';
import '../../domain/entities/product_entity.dart';

/// State for the Sales Return flow
class SalesReturnState {
  final List<SalesInvoiceData> invoices;
  /// Pre-loaded customer names keyed by customerId — eliminates N+1 FutureBuilder in list.
  final Map<int, String> customerNames;
  final SalesInvoiceData? selectedInvoice;
  final List<SalesInvoiceItem> invoiceItems;
  final Map<int, double> returnQuantities;
  final Map<int, double> previouslyReturnedQty;
  final Map<int, ProductEntity> productCache;
  final bool isFullReturn;
  final bool isExchangeMode;
  final bool isDamaged;
  final ProductEntity? exchangeProduct;
  final double exchangeQuantity;
  final bool isLoading;
  final bool isProcessing;
  final DateTime fromDate;
  final DateTime toDate;
  final String? error;

  SalesReturnState({
    this.invoices = const [],
    this.customerNames = const {},
    this.selectedInvoice,
    this.invoiceItems = const [],
    this.returnQuantities = const {},
    this.previouslyReturnedQty = const {},
    this.productCache = const {},
    this.isFullReturn = false,
    this.isExchangeMode = false,
    this.isDamaged = false,
    this.exchangeProduct,
    this.exchangeQuantity = 1.0,
    this.isLoading = false,
    this.isProcessing = false,
    required this.fromDate,
    required this.toDate,
    this.error,
  });

  SalesReturnState copyWith({
    List<SalesInvoiceData>? invoices,
    Map<int, String>? customerNames,
    SalesInvoiceData? selectedInvoice,
    List<SalesInvoiceItem>? invoiceItems,
    Map<int, double>? returnQuantities,
    Map<int, double>? previouslyReturnedQty,
    Map<int, ProductEntity>? productCache,
    bool? isFullReturn,
    bool? isExchangeMode,
    bool? isDamaged,
    ProductEntity? exchangeProduct,
    double? exchangeQuantity,
    bool? isLoading,
    bool? isProcessing,
    DateTime? fromDate,
    DateTime? toDate,
    String? error,
    bool clearSelected = false,
  }) {
    return SalesReturnState(
      invoices: invoices ?? this.invoices,
      customerNames: customerNames ?? this.customerNames,
      selectedInvoice: clearSelected
          ? null
          : (selectedInvoice ?? this.selectedInvoice),
      invoiceItems: clearSelected
          ? const []
          : (invoiceItems ?? this.invoiceItems),
      returnQuantities: clearSelected
          ? const {}
          : (returnQuantities ?? this.returnQuantities),
      previouslyReturnedQty: clearSelected
          ? const {}
          : (previouslyReturnedQty ?? this.previouslyReturnedQty),
      productCache: clearSelected
          ? const {}
          : (productCache ?? this.productCache),
      isFullReturn: isFullReturn ?? this.isFullReturn,
      isExchangeMode: isExchangeMode ?? this.isExchangeMode,
      isDamaged: isDamaged ?? this.isDamaged,
      exchangeProduct: exchangeProduct ?? this.exchangeProduct,
      exchangeQuantity: exchangeQuantity ?? this.exchangeQuantity,
      isLoading: isLoading ?? this.isLoading,
      isProcessing: isProcessing ?? this.isProcessing,
      fromDate: fromDate ?? this.fromDate,
      toDate: toDate ?? this.toDate,
      error: error ?? this.error,
    );
  }
}

/// Sales Return Notifier - Replaces logic in sales_returns_screen.dart
class SalesReturnNotifier extends Notifier<SalesReturnState> {
  Timer? _debounce;
  bool _disposed = false;

  @override
  SalesReturnState build() {
    _disposed = false;
    // ISS-06: Watch salesInvoices table via provider instead of direct DB access.
    // When the table changes, refresh the returnable-invoices list so the screen
    // stays in sync without requiring a manual refresh or exit/re-enter.
    ref.listen(salesInvoicesChangeProvider, (_, _) {
      if (_disposed) return;
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 400), () {
        if (!_disposed) loadInvoices();
      });
    });
    // Belt-and-suspenders: also refresh on server API broadcasts so the
    // screen updates when a CLIENT posts a sale/return to this server —
    // drift_postgres .watch() has been observed to drop markTablesUpdated
    // signals, and the broadcast channel is a reliable secondary trigger.
    ref.listen(serverDataChangeProvider, (_, next) {
      if (_disposed) return;
      next.whenData((table) {
        if (table != 'sales') return;
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 400), () {
          if (!_disposed) loadInvoices();
        });
      });
    });
    ref.onDispose(() {
      _disposed = true;
      _debounce?.cancel();
    });

    return SalesReturnState(
      fromDate: DateTime.now().subtract(const Duration(days: 30)),
      toDate: DateTime.now(),
    );
  }

  Future<void> setFromDate(DateTime date) async {
    state = state.copyWith(fromDate: date);
    await loadInvoices();
  }

  Future<void> setToDate(DateTime date) async {
    state = state.copyWith(toDate: date);
    await loadInvoices();
  }

  Future<void> loadInvoices() async {
    state = state.copyWith(isLoading: true);
    try {
      final repository = ref.read(returnsRepositoryProvider);
      // مواصفة 2026-08-18 §٣‑١٢: يرى الكاشيرُ فواتيرَ فرعِه وحدَها. بدون
      // القصّ كان يرتجع فاتورةَ فرعٍ آخر، فيعود المخزونُ لمخزنِ ذاك الفرع
      // بينما يخرج النقدُ من درجِ فرعِه هو — مخزونٌ هنا ونقدٌ هناك.
      // `null` = وصولٌ كامل (مديرُ نظام)، وإخفاقُ القراءة يُبقي السلوكَ
      // السابقَ بدل أن يُفرِغ الشاشةَ على الكاشير.
      Set<int>? scopeIds;
      try {
        scopeIds = (await ref.read(branchScopeProvider.future)).allowedBranchIds;
      } catch (_) {}

      final filtered = await repository.getInvoicesForReturn(
        fromDate: state.fromDate,
        toDate: state.toDate,
        allowedBranchIds: scopeIds,
      );

      // Batch-load customer names in ONE query — eliminates N+1 FutureBuilder in list.
      final customerIds = filtered
          .where((inv) => inv.customerId != null)
          .map((inv) => inv.customerId!)
          .toSet()
          .toList();
      // ISS-06: Route through partyNamesMapProvider instead of direct DB access
      final namesMap = await ref.read(partyNamesMapProvider(customerIds).future);

      state = state.copyWith(
        invoices: filtered,
        customerNames: namesMap,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> selectInvoice(SalesInvoiceData invoice) async {
    if (invoice.status == 'returned') {
      state = state.copyWith(error: 'هذه الفاتورة تم إرجاعها بالكامل سابقاً');
      return;
    }

    if (invoice.deliveryStatus != null && invoice.deliveryStatus!.isNotEmpty) {
      state = state.copyWith(error: 'لا يمكن إرجاع فواتير التوصيل');
      return;
    }

    state = state.copyWith(isLoading: true, selectedInvoice: invoice);

    try {
      final returnsRepo = ref.read(returnsRepositoryProvider);
      final productRepo = ref.read(productRepositoryProvider);

      // ── 1. Fetch all invoice items (1 query) ──
      final items = await returnsRepo.getSalesInvoiceItems(invoice.id);

      if (items.isEmpty) {
        state = state.copyWith(
          invoiceItems: const [],
          productCache: const {},
          previouslyReturnedQty: const {},
          returnQuantities: const {},
          isLoading: false,
        );
        return;
      }

      // ── 2. Fetch products + returned quantities in PARALLEL (2 queries total) ──
      // Previous implementation did N sequential per-item queries (products) and
      // N full-table-scan queries (returned qty), causing a UI freeze of
      // 5-100+ seconds on invoices with many items. Now:
      //   • products: one WHERE id IN (...) query
      //   • returned qty: one GROUP BY query using the invoice id
      final productIds = items.map((it) => it.productId).toSet().toList();
      final results = await Future.wait([
        productRepo.getProductsByIds(productIds),
        returnsRepo.getReturnedQuantitiesForInvoice(invoice.id),
      ]);
      final products = results[0] as List<ProductEntity>;
      final returnedByProduct = results[1] as Map<int, double>;

      // ── 3. Build in-memory maps (O(N) no DB I/O) ──
      final productCache = <int, ProductEntity>{
        for (final p in products) p.id: p,
      };
      final previouslyReturned = <int, double>{};
      final returnQuantities = <int, double>{};
      for (final item in items) {
        final returnedQty = returnedByProduct[item.productId] ?? 0;
        previouslyReturned[item.id] = returnedQty;
        returnQuantities[item.id] = state.isFullReturn
            ? (item.quantity - returnedQty)
            : 0;
      }

      state = state.copyWith(
        invoiceItems: items,
        productCache: productCache,
        previouslyReturnedQty: previouslyReturned,
        returnQuantities: returnQuantities,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void updateReturnQuantity(int itemId, double quantity) {
    final newQuantities = Map<int, double>.from(state.returnQuantities);
    newQuantities[itemId] = quantity;
    state = state.copyWith(returnQuantities: newQuantities);
  }

  void toggleFullReturn(bool value) {
    final newQuantities = <int, double>{};
    for (final item in state.invoiceItems) {
      final available =
          item.quantity - (state.previouslyReturnedQty[item.id] ?? 0);
      newQuantities[item.id] = value ? available : 0;
    }
    state = state.copyWith(
      isFullReturn: value,
      returnQuantities: newQuantities,
    );
  }

  void toggleExchangeMode(bool value) {
    state = state.copyWith(
      isExchangeMode: value,
      exchangeProduct: value ? state.exchangeProduct : null,
      exchangeQuantity: value ? state.exchangeQuantity : 1.0,
    );
  }

  void toggleDamagedMode(bool value) {
    state = state.copyWith(isDamaged: value);
  }

  void setExchangeProduct(ProductEntity product) {
    state = state.copyWith(exchangeProduct: product);
  }

  void updateExchangeQuantity(double quantity) {
    state = state.copyWith(exchangeQuantity: quantity);
  }

  double calculateReturnTotal() {
    if (state.selectedInvoice == null) return 0;

    final invoice = state.selectedInvoice!;
    final items = state.invoiceItems;

    // 1. Calculate the total of all items as stored in the DB (includes item discounts and taxes)
    double sumItemTotals = 0;
    for (final item in items) {
      sumItemTotals += item.total;
    }

    // 2. Identify the global discount ratio
    // Factor = (invoice.total - deliveryFee) / sumItemTotals
    double factor = 1.0;
    if (sumItemTotals > 0) {
      factor = (invoice.total - invoice.deliveryFee) / sumItemTotals;
    }

    double refundTotal = 0;
    for (final item in items) {
      final qty = state.returnQuantities[item.id] ?? 0;
      if (qty <= 0) continue;

      // refund per unit = (item.total / item.quantity) * factor
      final netUnitPrice = (item.total / item.quantity) * factor;
      refundTotal += qty * netUnitPrice;
    }

    // BUG-M01: round at financial precision (3dp JOD) via the central helper.
    return FinancialUtils.round(refundTotal);
  }

  double calculateItemRefundTotal(int itemId, double returnQty) {
    if (state.selectedInvoice == null || returnQty <= 0) return 0;

    final invoice = state.selectedInvoice!;
    final item = state.invoiceItems.where((i) => i.id == itemId).firstOrNull;
    if (item == null) return 0;

    // Replication of the global discount factor logic
    double sumItemTotals = state.invoiceItems.fold(
      0,
      (sum, i) => sum + i.total,
    );
    double factor = sumItemTotals > 0
        ? (invoice.total - invoice.deliveryFee) / sumItemTotals
        : 1.0;

    final netUnitPrice = (item.total / item.quantity) * factor;
    return FinancialUtils.round(returnQty * netUnitPrice);
  }

  double calculateExchangeTotal() {
    if (!state.isExchangeMode || state.exchangeProduct == null) return 0;
    // BUG-M02: include the replacement product's tax so the exchange
    // difference is computed on a like-for-like (tax-inclusive) basis with the
    // return refund, which already carries the original line tax. Exempt
    // products (taxRate == 0) add nothing.
    final product = state.exchangeProduct!;
    final lineTotal = product.salePrice * state.exchangeQuantity;
    final tax =
        product.taxRate > 0 ? lineTotal * (product.taxRate / 100) : 0.0;
    return FinancialUtils.round(lineTotal + tax);
  }

  double calculateExchangeDifference() {
    return calculateExchangeTotal() - calculateReturnTotal();
  }

  Future<bool> processReturn(String reason) async {
    if (state.selectedInvoice == null) return false;

    state = state.copyWith(isProcessing: true);

    try {
      final repository = ref.read(returnsRepositoryProvider);
      final auth = ref.read(authProvider);

      final success = await repository.processSalesReturn(
        invoice: state.selectedInvoice!,
        returnQuantities: state.returnQuantities,
        productCache: state.productCache,
        reason: reason,
        userId: auth.user?.id ?? 1,
        userName: auth.user?.displayName ?? 'User',
        isFullReturn: state.isFullReturn,
        isDamaged: state.isDamaged,
      );

      state = state.copyWith(isProcessing: false, clearSelected: true);
      // Refresh the invoice list immediately so the returned invoice disappears
      // from the screen without waiting for the Drift stream debounce.
      await loadInvoices();
      return success;
    } on ShiftRequiredException {
      // ليس عطلاً بل طلبَ إجراء: الواجهةُ تعرض فتحَ ورديّةٍ وتعيد المحاولة.
      // ابتلاعُه في `error` نصّاً كان يحوّله إلى رسالةٍ حمراءَ لا مخرجَ منها،
      // ويُفقِد النوعَ الذي بُني عليه (‏مواصفة 2026-08-18 ح‑١).
      state = state.copyWith(isProcessing: false);
      rethrow;
    } catch (e) {
      state = state.copyWith(isProcessing: false, error: e.toString());
      return false;
    }
  }

  void clearError() => state = state.copyWith(error: null);
}

final salesReturnProvider =
    NotifierProvider<SalesReturnNotifier, SalesReturnState>(() {
      return SalesReturnNotifier();
    });
