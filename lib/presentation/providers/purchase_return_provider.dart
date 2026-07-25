import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/providers/providers.dart';
import '../../domain/repositories/purchases_repository.dart';

/// State for the Purchase Return flow
class PurchaseReturnState {
  final List<PurchaseInvoiceData> invoices;
  final PurchaseInvoiceData? selectedInvoice;
  final List<PurchaseInvoiceItemWithProduct> invoiceItems;
  final Map<int, double> returnQuantities;
  final bool isLoading;
  final bool isProcessing;
  final DateTime fromDate;
  final DateTime toDate;
  final String? error;

  /// البند 7 — فلاتر التتبّع: المورد · الصنف · رقم الفاتورة. كلها تُنفَّذ في
  /// SQL؛ لا يوجد أي ترشيح في الذاكرة بعد الآن.
  final int? supplierId;
  final int? productId;
  final String invoiceQuery;

  PurchaseReturnState({
    this.invoices = const [],
    this.selectedInvoice,
    this.invoiceItems = const [],
    this.returnQuantities = const {},
    this.isLoading = false,
    this.isProcessing = false,
    required this.fromDate,
    required this.toDate,
    this.error,
    this.supplierId,
    this.productId,
    this.invoiceQuery = '',
  });

  PurchaseReturnState copyWith({
    List<PurchaseInvoiceData>? invoices,
    PurchaseInvoiceData? selectedInvoice,
    List<PurchaseInvoiceItemWithProduct>? invoiceItems,
    Map<int, double>? returnQuantities,
    bool? isLoading,
    bool? isProcessing,
    DateTime? fromDate,
    DateTime? toDate,
    String? error,
    bool clearSelected = false,
    int? supplierId,
    int? productId,
    String? invoiceQuery,
    // الفلاتر اختيارية، فمسحها يحتاج علماً صريحاً — تمرير null وحده يعني
    // «لا تغيير» لا «امسح».
    bool clearSupplier = false,
    bool clearProduct = false,
  }) {
    return PurchaseReturnState(
      invoices: invoices ?? this.invoices,
      selectedInvoice: clearSelected ? null : (selectedInvoice ?? this.selectedInvoice),
      invoiceItems: clearSelected ? const [] : (invoiceItems ?? this.invoiceItems),
      returnQuantities: clearSelected ? const {} : (returnQuantities ?? this.returnQuantities),
      isLoading: isLoading ?? this.isLoading,
      isProcessing: isProcessing ?? this.isProcessing,
      fromDate: fromDate ?? this.fromDate,
      toDate: toDate ?? this.toDate,
      error: error ?? this.error,
      supplierId: clearSupplier ? null : (supplierId ?? this.supplierId),
      productId: clearProduct ? null : (productId ?? this.productId),
      invoiceQuery: invoiceQuery ?? this.invoiceQuery,
    );
  }
}

class PurchaseReturnNotifier extends Notifier<PurchaseReturnState> {
  Timer? _debounce;
  bool _disposed = false;

  @override
  PurchaseReturnState build() {
    _disposed = false;
    // ISS-06: Watch purchaseInvoices table via provider instead of direct DB access.
    // Triggers a refresh so the screen stays in sync across local, server, and
    // client modes without requiring manual reload.
    ref.listen(purchaseInvoicesChangeProvider, (_, _) {
      if (_disposed) return;
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 400), () {
        if (!_disposed) loadInvoices();
      });
    });
    // Belt-and-suspenders: server API broadcast as a secondary trigger for
    // when drift_postgres .watch() drops signals (observed under load).
    ref.listen(serverDataChangeProvider, (_, next) {
      if (_disposed) return;
      next.whenData((table) {
        if (table != 'purchases') return;
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

    return PurchaseReturnState(
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

  /// البند 7 — فلتر المورد.
  Future<void> setSupplierFilter(int? supplierId) async {
    state = state.copyWith(
      supplierId: supplierId,
      clearSupplier: supplierId == null,
    );
    await loadInvoices();
  }

  /// البند 7 — فلتر الصنف: «الصنف الموجود في جميع الفواتير».
  Future<void> setProductFilter(int? productId) async {
    state = state.copyWith(
      productId: productId,
      clearProduct: productId == null,
    );
    await loadInvoices();
  }

  /// البند 7 — البحث برقم الفاتورة. مؤجَّل 400ms لأن كل ضغطة مفتاح تصير
  /// استعلاماً الآن (البحث لم يعد في الذاكرة).
  void setInvoiceQuery(String query) {
    state = state.copyWith(invoiceQuery: query);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!_disposed) loadInvoices();
    });
  }

  Future<void> loadInvoices() async {
    state = state.copyWith(isLoading: true);
    try {
      final repository = ref.read(returnsRepositoryProvider);
      final filtered = await repository.getInvoicesForPurchaseReturn(
        fromDate: state.fromDate,
        toDate: state.toDate,
        supplierId: state.supplierId,
        productId: state.productId,
        invoiceNumberLike:
            state.invoiceQuery.trim().isEmpty ? null : state.invoiceQuery.trim(),
      );
      state = state.copyWith(invoices: filtered, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> selectInvoice(PurchaseInvoiceData invoice) async {
    state = state.copyWith(isLoading: true, selectedInvoice: invoice);
    try {
      final purchasesRepo = ref.read(purchasesRepositoryProvider);
      final items = await purchasesRepo.getInvoiceItemsWithProduct(invoice.id);
      
      final returnQuantities = <int, double>{};
      for (final item in items) {
        returnQuantities[item.item.id] = 0;
      }

      state = state.copyWith(
        invoiceItems: items,
        returnQuantities: returnQuantities,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void updateReturnQuantity(int itemId, double quantity) {
    // Clamp to original quantity to prevent returning more than purchased
    final item = state.invoiceItems.where((i) => i.item.id == itemId).firstOrNull;
    final maxQty = item?.item.quantity ?? 0.0;
    final clampedQty = quantity.clamp(0.0, maxQty);

    final newQuantities = Map<int, double>.from(state.returnQuantities);
    newQuantities[itemId] = clampedQty;
    state = state.copyWith(returnQuantities: newQuantities);
  }

  double calculateReturnTotal() {
    if (state.selectedInvoice == null) return 0;
    double total = 0;
    for (final item in state.invoiceItems) {
      final qty = state.returnQuantities[item.item.id] ?? 0;
      total += qty * item.item.unitCost;
    }
    return total;
  }

  Future<bool> processReturn() async {
    if (state.selectedInvoice == null) return false;
    state = state.copyWith(isProcessing: true);

    try {
      final purchasesRepo = ref.read(purchasesRepositoryProvider);

      final returnItems = state.returnQuantities.entries
          .where((e) => e.value > 0)
          .map((entry) {
        final item = state.invoiceItems.firstWhere((i) => i.item.id == entry.key);
        // Validate: return quantity must not exceed original quantity
        final maxQty = item.item.quantity;
        if (entry.value > maxQty + 0.001) {
          throw Exception(
            'كمية الإرجاع (${entry.value}) تتجاوز الكمية الأصلية ($maxQty) للصنف رقم ${item.item.productId}',
          );
        }
        return PurchaseReturnItem(
          itemId: item.item.id,
          productId: item.item.productId,
          returnQuantity: entry.value.clamp(0.0, maxQty),
          unitCost: item.item.unitCost,
          taxAmount: item.item.taxAmount,
          originalQuantity: item.item.quantity,
          quantityInBase: item.item.quantityInBase > 0 ? item.item.quantityInBase : 1.0, // B1: UOM
        );
      }).toList();

      await purchasesRepo.processPurchaseReturn(
        invoice: state.selectedInvoice!,
        returnItems: returnItems,
      );

      state = state.copyWith(isProcessing: false, clearSelected: true);
      await loadInvoices();
      return true;
    } catch (e) {
      state = state.copyWith(isProcessing: false, error: e.toString());
      return false;
    }
  }

  void clearError() => state = state.copyWith(error: null);
}

final purchaseReturnProvider = NotifierProvider<PurchaseReturnNotifier, PurchaseReturnState>(() {
  return PurchaseReturnNotifier();
});
