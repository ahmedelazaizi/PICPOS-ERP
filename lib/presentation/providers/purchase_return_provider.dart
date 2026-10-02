import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/errors/app_exceptions.dart';
import '../../data/providers/providers.dart';
import '../../domain/models/purchase_return_settlement.dart';
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

  /// المُرتجَعُ سابقاً من كلّ صنف — معرّفُ الصنف ↦ الكمّيّة بالوحدة
  /// الأساسيّة. يُقرأ عند اختيار الفاتورة من `stock_movements`.
  final Map<int, double> alreadyReturnedByProduct;

  /// سببُ المردود — قائمةٌ ثابتةٌ إلزاميّة (قرارُ المالك 2026-09-18).
  final String? returnReason;

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
    this.alreadyReturnedByProduct = const {},
    this.returnReason,
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
    Map<int, double>? alreadyReturnedByProduct,
    String? returnReason,
    // الفلاتر اختيارية، فمسحها يحتاج علماً صريحاً — تمرير null وحده يعني
    // «لا تغيير» لا «امسح».
    bool clearSupplier = false,
    bool clearProduct = false,
    // `error: null` وحده يعني «لا تغيير»، فكان `clearError()` لا يمسح شيئاً:
    // الخطأُ يبقى عالقاً، ورفضٌ ثانٍ بنفس النصّ لا يُطلق مستمعاً فيمرّ صامتاً.
    bool clearError = false,
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
      error: clearError ? null : (error ?? this.error),
      supplierId: clearSupplier ? null : (supplierId ?? this.supplierId),
      productId: clearProduct ? null : (productId ?? this.productId),
      invoiceQuery: invoiceQuery ?? this.invoiceQuery,
      // اختيارُ فاتورةٍ أخرى يُبطِل المرتجعَ السابقَ والسببَ معاً:
      // إبقاؤهما يرسم حدودَ فاتورةٍ على أخرى.
      alreadyReturnedByProduct: clearSelected
          ? const {}
          : (alreadyReturnedByProduct ?? this.alreadyReturnedByProduct),
      returnReason:
          clearSelected ? null : (returnReason ?? this.returnReason),
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

      // المُرتجَعُ سابقاً — قرارُ المالك: يُعرَض مع «المتاح حالياً».
      final alreadyReturned = await ref
          .read(databaseProvider)
          .getPurchaseReturnedQtyByProduct(invoice.id);

      state = state.copyWith(
        invoiceItems: items,
        returnQuantities: returnQuantities,
        alreadyReturnedByProduct: alreadyReturned,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// المتاحُ للإرجاع من صنفٍ = المشترى − المرتجَعُ سابقاً.
  ///
  /// ⚠️ **وطرحُ السابق ليس تجميلاً.** السقفُ كان الكمّيّةَ الأصليّةَ وحدَها،
  /// فردُّ خمسةٍ من خمسةٍ **مرّتَين** كان يمرّ: مخزونٌ يُخصَم مرّتَين،
  /// وذمّةُ موردٍ تُخفَّض مرّتَين، وقيدان في الأستاذ. وجانبُ المبيعات
  /// يطرحُه منذ زمن (`returns_repository_impl`) — والشراءُ لا.
  double maxReturnableFor(int itemId) {
    final item =
        state.invoiceItems.where((i) => i.item.id == itemId).firstOrNull;
    if (item == null) return 0;
    final already =
        state.alreadyReturnedByProduct[item.item.productId] ?? 0.0;
    final left = item.item.quantity - already;
    return left > 0 ? left : 0.0;
  }

  /// يبدّل سببَ المردود.
  void updateReturnReason(String? reason) {
    state = state.copyWith(returnReason: reason);
  }

  void updateReturnQuantity(int itemId, double quantity) {
    final maxQty = maxReturnableFor(itemId);
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

  /// ضريبةُ المردود — **مقسَّطةٌ بنسبة المرتجَع** من ضريبة السطر.
  ///
  /// ⚠️ والصيغةُ منسوخةٌ عن المحرّك حرفاً (`_processPurchaseReturnBody`):
  /// `taxAmount * (returnQty / originalQty)`. ونقلُ ضريبة السطر كاملةً في
  /// مرتجعٍ جزئيٍّ يعطي ضريبةً أكبرَ من قيمة المرتجَع نفسِه.
  double calculateReturnVat() {
    double vat = 0;
    for (final item in state.invoiceItems) {
      final qty = state.returnQuantities[item.item.id] ?? 0;
      if (qty <= 0) continue;
      if (item.item.taxAmount > 0 && item.item.quantity > 0) {
        vat += item.item.taxAmount * (qty / item.item.quantity);
      }
    }
    return vat;
  }

  /// تسويةُ المبلغ مع المورّد كما **سيقسمها المحرّك**.
  ///
  /// 🔴 **مرآةٌ مشتقّةٌ لا قائمةُ اختيار** — قرارُ المالك 2026-09-18.
  /// والقسمةُ من [resolvePurchaseReturnSettlement] عينِها التي ينفّذها
  /// المستودعُ ومعالجُ الـAPI، فما يُعرَض هو ما سيقع.
  ///
  /// ⚠️ **ولا تُبنى `PurchaseReturnSettlement` هنا بيدها.** طفرةٌ نجت من
  /// الحارس الأوّل لأنّها كتبت القسمةَ بـ`g < rem ? g : rem` بدل `clamp`
  /// — فالحارسُ صار يمنع البناءَ المباشرَ لا صياغةً بعينها.
  PurchaseReturnSettlement? get settlement {
    final invoice = state.selectedInvoice;
    if (invoice == null) return null;
    return resolvePurchaseReturnSettlement(
      returnNet: calculateReturnTotal(),
      returnVat: calculateReturnVat(),
      invoiceTotal: invoice.total,
      invoicePaid: invoice.paid,
    );
  }

  Future<bool> processReturn() async {

    if (state.selectedInvoice == null) return false;
    state = state.copyWith(isProcessing: true, clearError: true);

    try {
      final purchasesRepo = ref.read(purchasesRepositoryProvider);

      final returnItems = state.returnQuantities.entries
          .where((e) => e.value > 0)
          .map((entry) {
        final item = state.invoiceItems.firstWhere((i) => i.item.id == entry.key);
        // ⚠️ **والسقفُ هنا هو عينُه سقفُ الحقل** — المتاحُ لا الأصليّ.
        // حارسُ الواجهة يُقصُّ بالمعروض، وهذا يحرس من مسارٍ لا يمرّ به
        // (لصقٌ، أو حالةٌ قديمةٌ بقيت بعد مرتجعٍ في جهازٍ آخر).
        final maxQty = maxReturnableFor(entry.key);
        if (entry.value > maxQty + 0.001) {
          throw Exception(
            'كمية الإرجاع (${entry.value}) تتجاوز المتاح للإرجاع "$maxQty" '
            'للصنف رقم ${item.item.productId} — المرتجَعُ سابقاً '
            '${state.alreadyReturnedByProduct[item.item.productId] ?? 0}',
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
        reason: state.returnReason,
      );

      state = state.copyWith(isProcessing: false, clearSelected: true);
      await loadInvoices();
      return true;
    } on ShiftRequiredException {
      // 🔴 بلاغُ المالك (مرتجع «استرداد نقدي» يُغلق الحوارَ ولا يحدث شيء):
      // المرتجعُ النقديُّ يُدخِل مالاً الدرجَ فيستلزم ورديّةً مفتوحة، والمستودعُ
      // يرمي هذا النوع. وابتلاعُه هنا نصّاً في `error` — والشاشةُ لا تقرأه —
      // كان هو الصمتَ بعينه. فيُرمى للواجهة لتعرض فتحَ ورديّةٍ ثمّ تعيد
      // المحاولة، كما يفعل توأمُ المبيعات (`sales_return_provider`).
      state = state.copyWith(isProcessing: false);
      rethrow;
    } catch (e) {
      state = state.copyWith(isProcessing: false, error: _describe(e));
      return false;
    }
  }

  /// نصُّ الخطأ للمستخدم — بلا بادئة `Exception: ` / `Bad state: ` التقنيّة.
  static String _describe(Object e) {
    final raw = e.toString();
    for (final prefix in const ['Exception: ', 'Bad state: ']) {
      if (raw.startsWith(prefix)) return raw.substring(prefix.length);
    }
    return raw;
  }

  void clearError() => state = state.copyWith(clearError: true);

  /// J2 — استمارةٌ جديدةٌ تبدأ فارغة: المزوّدُ عامٌّ يعيش بعد إغلاق صفحتها.
  void resetForm() {
    state = state.copyWith(
      clearSelected: true,
      clearError: true,
      isProcessing: false,
    );
  }

  /// J2 — يفتح مسوّدةً محفوظة: الفاتورةُ الأصل ثمّ سببُها وكمّيّاتُها
  /// (مقصوصةً عند المتاح اليوم — `updateReturnQuantity`).
  Future<bool> loadDraft({
    required PurchaseInvoiceData invoice,
    required Map<int, double> quantities,
    String? reason,
  }) async {
    resetForm();
    await selectInvoice(invoice);
    if (state.selectedInvoice?.id != invoice.id) return false;
    updateReturnReason(reason);
    for (final e in quantities.entries) {
      if (state.invoiceItems.any((i) => i.item.id == e.key)) {
        updateReturnQuantity(e.key, e.value);
      }
    }
    return true;
  }
}

final purchaseReturnProvider = NotifierProvider<PurchaseReturnNotifier, PurchaseReturnState>(() {
  return PurchaseReturnNotifier();
});
