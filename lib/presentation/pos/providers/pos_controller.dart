import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../domain/entities/cart_item_entity.dart';
import '../../../data/providers/providers.dart';
import 'cart_controller.dart';

// pos_controller.dart

/// POS State - holds all state for the POS screen
class PosState {
  final int? selectedCategoryId;
  final String searchQuery;
  final bool isGridCollapsed;
  final double cartFlexRatio;
  final IndustryMode industryMode;

  // Processing & Errors
  final bool isProcessing;
  final String? error;

  // Table / Booking Context
  final int? tableId;
  final int? orderId;
  final String? tableName;
  final bool isBooking;

  // Delivery Context
  final String? deliveryStatus;
  final int? selectedCustomerId;
  final int? deliveryCompanyId;

  // Deleted Items Tracking
  final List<CartItemEntity> deletedItems;

  const PosState({
    this.selectedCategoryId,
    this.searchQuery = '',
    this.isGridCollapsed = false,
    this.cartFlexRatio = 0.6,
    this.industryMode = IndustryMode.retail,
    this.isProcessing = false,
    this.error,
    this.tableId,
    this.orderId,
    this.tableName,
    this.isBooking = false,
    this.deliveryStatus,
    this.selectedCustomerId,
    this.deliveryCompanyId,
    this.deletedItems = const [],
  });

  factory PosState.initial() => const PosState();

  PosState copyWith({
    int? selectedCategoryId,
    String? searchQuery,
    bool? isGridCollapsed,
    double? cartFlexRatio,
    IndustryMode? industryMode,
    bool? isProcessing,
    String? error,
    int? tableId,
    int? orderId,
    String? tableName,
    bool? isBooking,
    String? deliveryStatus,
    int? selectedCustomerId,
    int? deliveryCompanyId,
    List<CartItemEntity>? deletedItems,
  }) {
    return PosState(
      selectedCategoryId: selectedCategoryId ?? this.selectedCategoryId,
      searchQuery: searchQuery ?? this.searchQuery,
      isGridCollapsed: isGridCollapsed ?? this.isGridCollapsed,
      cartFlexRatio: cartFlexRatio ?? this.cartFlexRatio,
      industryMode: industryMode ?? this.industryMode,
      isProcessing: isProcessing ?? this.isProcessing,
      error: error ?? this.error,
      tableId: tableId ?? this.tableId,
      orderId: orderId ?? this.orderId,
      tableName: tableName ?? this.tableName,
      isBooking: isBooking ?? this.isBooking,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
      selectedCustomerId: selectedCustomerId ?? this.selectedCustomerId,
      deliveryCompanyId: deliveryCompanyId ?? this.deliveryCompanyId,
      deletedItems: deletedItems ?? this.deletedItems,
    );
  }

  PosState clearCategoryFilter() {
    return PosState(
      searchQuery: searchQuery,
      isGridCollapsed: isGridCollapsed,
      cartFlexRatio: cartFlexRatio,
      industryMode: industryMode,
      isProcessing: isProcessing,
      error: error,
      tableId: tableId,
      orderId: orderId,
      tableName: tableName,
      isBooking: isBooking,
      deliveryStatus: deliveryStatus,
      selectedCustomerId: selectedCustomerId,
      deliveryCompanyId: deliveryCompanyId,
      deletedItems: deletedItems,
    );
  }
}

/// POS Controller - Riverpod 3.x Notifier pattern
class PosController extends Notifier<PosState> {
  @override
  PosState build() {
    // Load persisted ratio in background
    _loadCartFlexRatio();

    return const PosState();
  }

  /// Load saved cart flex ratio - SharedPreferences first (sync), DB as fallback
  Future<void> _loadCartFlexRatio() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedRatio = prefs.getDouble('pos_cart_flex_ratio');

      if (savedRatio != null && savedRatio >= 0.3 && savedRatio <= 0.7) {
        state = state.copyWith(cartFlexRatio: savedRatio);
        return;
      }

      final settingsRepo = ref.read(settingsRepositoryProvider);
      final dbRatio = await settingsRepo.getSetting('pos_cart_flex_ratio');
      if (dbRatio != null) {
        final ratio = double.tryParse(dbRatio);
        if (ratio != null && ratio >= 0.3 && ratio <= 0.7) {
          state = state.copyWith(cartFlexRatio: ratio);
          await prefs.setDouble('pos_cart_flex_ratio', ratio);
        }
      }
    } catch (_) {}
  }

  /// Initialize POS for a specific table
  Future<void> initTableOrder(int tableId, String tableName) async {
    state = state.copyWith(
      isProcessing: true,
      tableId: tableId,
      tableName: tableName,
    );

    try {
      final restaurantRepo = ref.read(restaurantRepositoryProvider);
      final productsRepo = ref.read(productRepositoryProvider);

      final order = await restaurantRepo.getActiveOrderForTable(tableId);
      if (order != null) {
        final items = await restaurantRepo.getTableOrderItems(order.id);

        final List<CartItemEntity> cartItems = [];
        for (final item in items) {
          final product = await productsRepo.getProductById(item.productId);
          if (product != null) {
            cartItems.add(
              CartItemEntity(
                productId: product.id,
                productName: product.name,
                productCode: product.code,
                barcode: product.barcode,
                unitPrice: product.salePrice,
                quantity: item.quantity,
                customPrice: item.unitPrice,
                // نسبةُ البند من الطلب لا من بطاقة المنتج: لقطةٌ أُخذت ساعةَ
                // الطلب، فلا يُعاد تسعيرُ ما طُلب لو غُيّرت البطاقةُ بعده.
                taxRate: item.taxRate,
                isSoldByWeight: product.isSoldByWeight,
              ),
            );
          }
        }

        // السلّةُ مرآةُ الطلب في الضريبة كذلك، لا في الأصناف وحدَها: الزرُّ
        // يعرض حالةَ الطلب حين تُفتح الشاشةُ ثانيةً، وإجماليُّ الشاشة يطابق
        // ما سيُشحَن عند التحصيل.
        ref.read(cartControllerProvider.notifier).state =
            ref.read(cartControllerProvider).copyWith(
                  items: cartItems,
                  taxEnabled: order.taxEnabled,
                  taxRate: order.taxRate,
                );

        state = state.copyWith(orderId: order.id, isProcessing: false);
      } else {
        final orderId = await restaurantRepo.createTableOrder(tableId);
        // `clearCart` تحتفظ بالضريبة عمداً (سلوكُ سلّة الكاشير)، وهو هنا
        // خطأ: الطلبُ المولودُ لتوّه ضريبتُه مطفأةٌ ونسبتُه صفر، فلو ورثت
        // السلّةُ ضريبةَ **طاولةٍ سابقةٍ** لَعرض الزرُّ «مفعلة» على طلبٍ لا
        // ضريبةَ فيه — واختلف المشحونُ عن المسجَّل عند التحصيل.
        ref.read(cartControllerProvider.notifier)
          ..clearCart()
          ..toggleTax(false)
          ..setTaxRate(0);
        state = state.copyWith(orderId: orderId, isProcessing: false);
      }
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        error: 'فشل تحميل طلب الطاولة',
      );
    }
  }

  /// Toggle booking mode
  void toggleBooking(bool enabled) {
    state = state.copyWith(isBooking: enabled);
  }

  /// Print invoice (delegated to PrintingService)
  Future<void> printInvoice(int invoiceId) async {
    await ref.read(printingServiceProvider).printReceipt(invoiceId);
  }

  /// Print kitchen orders (delegated to KitchenService)
  Future<void> printKitchenOrders(int invoiceId) async {
    await ref.read(kitchenServiceProvider).printKitchenOrders(invoiceId);
  }

  /// Set industry mode
  void setIndustryMode(IndustryMode mode) {
    state = state.copyWith(industryMode: mode);
  }

  /// Clear error
  void clearError() {
    state = state.copyWith(error: null);
  }

  // UI STATE METHODS
  
  /// Toggle grid collapse state
  void toggleGridCollapse() {
    state = state.copyWith(isGridCollapsed: !state.isGridCollapsed);
  }

  /// PERF01: Debounce timer for search to avoid excessive rebuilds
  Timer? _searchDebounce;

  /// Set search query for product filtering (UI filtering)
  /// Debounced by 200ms to reduce rebuild frequency on fast typing
  void setSearchQuery(String query) {
    _searchDebounce?.cancel();
    // Short queries or empty → apply immediately for responsive feel
    if (query.isEmpty || query.length <= 1) {
      state = state.copyWith(searchQuery: query);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 200), () {
      state = state.copyWith(searchQuery: query);
    });
  }

  /// Set category filter
  void setCategoryFilter(int? categoryId) {
    if (state.selectedCategoryId == categoryId) {
      state = state.clearCategoryFilter();
    } else {
      state = state.copyWith(selectedCategoryId: categoryId);
    }
  }

  /// Adjust flex ratio (relative delta)
  void adjustFlexRatio(double delta) {
    final newRatio = (state.cartFlexRatio + delta).clamp(0.2, 0.8);
    setCartFlexRatio(newRatio);
  }

  /// Set cart flex ratio (absolute value)
  void setCartFlexRatio(double ratio) {
    state = state.copyWith(cartFlexRatio: ratio);
    _saveCartFlexRatio(ratio);
  }

  Future<void> _saveCartFlexRatio(double ratio) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('pos_cart_flex_ratio', ratio);
  }

  /// Set delivery information.
  ///
  /// P5 (Issue #6): Selecting a delivery company now also flips the cart's
  /// price level so per-company prices (priceTalabat / priceCareem /
  /// priceAshyae) take effect automatically. Without this the cashier would
  /// pick "Talabat" but the cart kept charging the regular sale price — the
  /// per-company prices defined on the product were dead data.
  ///
  /// The mapping is name-based (case-insensitive) so it works even when the
  /// admin renames a delivery company to "talabat eg" or "Careem - delivery".
  Future<void> setDeliveryInfo({String? status, int? companyId}) async {
    state = state.copyWith(
      deliveryStatus: status ?? state.deliveryStatus,
      deliveryCompanyId: companyId ?? state.deliveryCompanyId,
    );

    // Trigger price-level swap on the cart whenever the company changes
    // (or is cleared).
    final cartCtl = ref.read(cartControllerProvider.notifier);
    String level = 'retail';
    if (companyId != null) {
      try {
        final companies = await ref.read(allDeliveryCompaniesProvider.future);
        final co = companies.firstWhere(
          (c) => c.id == companyId,
          orElse: () => companies.first,
        );
        final lname = co.name.toLowerCase();
        if (lname.contains('talabat') || lname.contains('طلبات')) {
          level = 'talabat';
        } else if (lname.contains('careem') || lname.contains('كريم')) {
          level = 'careem';
        } else if (lname.contains('ashyae') ||
            lname.contains('أشيائى') ||
            lname.contains('اشيائي')) {
          level = 'ashyae';
        }
      } catch (e) {
        // Provider not ready or no companies — leave price level as 'retail'
      }
    }
    if (cartCtl.state.priceLevel != level) {
      cartCtl.setPriceLevel(level);
    }
  }

  /// Request table bill for restaurant mode
  Future<void> requestTableBill() async {
    // Logic for requesting bill... 
    // This could also be moved to a TableController if needed later.
  }

  /// Clear deleted items list
  void clearDeletedItems() {
    state = state.copyWith(deletedItems: []);
  }
}

/// Provider for POS controller - Riverpod 3.x NotifierProvider
final posControllerProvider = NotifierProvider<PosController, PosState>(
  PosController.new,
);
