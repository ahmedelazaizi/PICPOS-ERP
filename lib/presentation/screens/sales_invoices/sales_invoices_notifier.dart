import 'package:ural_erp/core/constants/app_constants.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/repositories/sales_repository.dart';
import '../../../data/providers/providers.dart';
import '../../../data/providers/e_invoicing_providers.dart';
import '../../../core/tax/effective_item_tax_rate.dart';
import '../../../core/utils/financial_utils.dart';
import '../../../domain/usecases/sales/complete_sale_usecase.dart';
import '../../../domain/usecases/sales/calculate_invoice_totals_usecase.dart';
import '../../../domain/entities/cart_item_entity.dart';
import '../../../domain/entities/product_entity.dart';

/// Cart item for sales invoices
class SalesCartItem {
  final int productId;
  final String productName;
  final String productCode;
  double quantity;
  double unitPrice;
  double discount;
  int? selectedUnitId;
  String? selectedUnitName;
  double quantityInBase;
  /// Per-line VAT: one invoice may mix taxable and exempt items. Rate is a
  /// percentage (e.g. 16.0 for 16%), to match the product card and the
  /// purchase-invoice convention. When [taxEnabled] is false the line
  /// contributes zero to the invoice tax regardless of [taxRate].
  double taxRate;
  bool taxEnabled;

  SalesCartItem({
    required this.productId,
    required this.productName,
    required this.productCode,
    this.quantity = 1,
    this.unitPrice = 0,
    this.discount = 0,
    this.selectedUnitId,
    this.selectedUnitName,
    this.quantityInBase = 1.0,
    this.taxRate = 0,
    this.taxEnabled = false,
  });

  double get total => FinancialUtils.calculateLineNetTotal(
    quantity: quantity,
    unitPrice: unitPrice,
    discountAmount: discount,
  );

  /// Tax amount for this line (0 if taxEnabled is false).
  double get taxAmount => taxEnabled
      ? FinancialUtils.round(total * (taxRate / 100))
      : 0.0;

  SalesCartItem copyWith({
    double? quantity,
    double? unitPrice,
    double? discount,
    int? selectedUnitId,
    String? selectedUnitName,
    double? quantityInBase,
    double? taxRate,
    bool? taxEnabled,
  }) {
    return SalesCartItem(
      productId: productId,
      productName: productName,
      productCode: productCode,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      discount: discount ?? this.discount,
      selectedUnitId: selectedUnitId ?? this.selectedUnitId,
      selectedUnitName: selectedUnitName ?? this.selectedUnitName,
      quantityInBase: quantityInBase ?? this.quantityInBase,
      taxRate: taxRate ?? this.taxRate,
      taxEnabled: taxEnabled ?? this.taxEnabled,
    );
  }
}

/// State for the sales invoices form
class SalesInvoicesFormState {
  final List<SalesCartItem> cart;
  final int? selectedCustomerId;
  final double discount;
  final double tax;
  final bool taxEnabled;
  final double taxRate; // decimal (e.g. 0.14 for 14%)
  final double paidAmount;
  final String paymentMethod;
  final String notes;
  final bool isLoading;
  final bool isReturnMode;
  final int warehouseId;
  final int? costCenterId;

  SalesInvoicesFormState({
    this.cart = const [],
    this.selectedCustomerId,
    this.discount = 0,
    this.tax = 0,
    this.taxEnabled = false,
    this.taxRate = 0,
    this.paidAmount = 0,
    this.paymentMethod = 'نقدي',
    this.notes = '',
    this.isLoading = false,
    this.isReturnMode = false,
    this.warehouseId = 1,
    this.costCenterId,
  });

  double get subtotal => cart.fold(
    0.0,
    (sum, item) =>
        sum +
        FinancialUtils.calculateLineSubtotal(item.quantity, item.unitPrice),
  );

  /// Invoice-level tax is the SUM of per-line tax amounts — each
  /// [SalesCartItem] owns its own [taxRate]/[taxEnabled], so an invoice
  /// can mix taxable and exempt items. The invoice-level [taxEnabled] /
  /// [taxRate] fields are kept only to drive the "bulk apply" button in
  /// the summary (which flips every line at once); they no longer gate
  /// the totals.
  ///
  /// Spec 151 E-02: the displayed tax/total MUST equal what the save path
  /// (completeSalesTransaction) persists. Both now run through the SAME pure
  /// engine — [CalculateInvoiceTotalsUseCase] — so the invoice-level [discount]
  /// reduces the VAT base (net-base VAT), not merely the grand total. Before
  /// this fix the invoice discount was subtracted from grandTotal but NOT from
  /// the tax base, so the cashier saw (and collected) a higher tax/total than
  /// the system saved (e.g. 1040/tax 140 shown vs 1026/tax 126 saved).
  InvoiceTotals get _totals {
    if (cart.isEmpty) return const InvoiceTotals.empty();
    final gross = subtotal;
    final items = cart
        .map(
          (item) => CartItemEntity(
            productId: item.productId,
            productName: item.productName,
            productCode: item.productCode,
            quantity: item.quantity,
            unitPrice: item.unitPrice,
            // SalesCartItem carries an ABSOLUTE per-line discount; the use case
            // (like the save path) expects a percent. Reconstruct it exactly as
            // saveInvoice() / _saveInvoice do so display == saved.
            discountPercent: (item.unitPrice > 0 && item.quantity > 0)
                ? (item.discount / (item.unitPrice * item.quantity)) * 100
                : 0.0,
            // Exempt (taxEnabled == false) lines contribute zero VAT.
            taxRate: item.taxEnabled ? item.taxRate : 0,
          ),
        )
        .toList();
    return CalculateInvoiceTotalsUseCase().execute(
      items: items,
      // Absolute invoice discount → percent on the gross subtotal, the exact
      // conversion the save path uses (sales_invoice_save_edit.dart:200-201).
      invoiceDiscountPercent: gross > 0 ? (discount / gross) * 100 : 0.0,
      // Per-line rates already encode exempt lines (rate 0); no global fallback
      // rate, and the per-line taxEnabled flag is the only gate (mirrored into
      // the mapped taxRate above), so taxEnabled here stays true.
      taxPercent: 0,
      taxEnabled: true,
    );
  }

  double get calculatedTax => _totals.taxAmount;

  double get grandTotal => _totals.total;

  SalesInvoicesFormState copyWith({
    List<SalesCartItem>? cart,
    int? selectedCustomerId,
    double? discount,
    double? tax,
    bool? taxEnabled,
    double? taxRate,
    double? paidAmount,
    String? paymentMethod,
    String? notes,
    bool? isLoading,
    bool? isReturnMode,
    int? warehouseId,
    int? costCenterId,
  }) {
    return SalesInvoicesFormState(
      cart: cart ?? this.cart,
      selectedCustomerId: selectedCustomerId ?? this.selectedCustomerId,
      discount: discount ?? this.discount,
      tax: tax ?? this.tax,
      taxEnabled: taxEnabled ?? this.taxEnabled,
      taxRate: taxRate ?? this.taxRate,
      paidAmount: paidAmount ?? this.paidAmount,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      notes: notes ?? this.notes,
      isLoading: isLoading ?? this.isLoading,
      isReturnMode: isReturnMode ?? this.isReturnMode,
      warehouseId: warehouseId ?? this.warehouseId,
      costCenterId: costCenterId ?? this.costCenterId,
    );
  }
}

/// Notifier for sales invoice form
class SalesInvoicesFormNotifier extends Notifier<SalesInvoicesFormState> {
  ActivityLogger get _logger => ref.read(activityLoggerProvider);

  @override
  SalesInvoicesFormState build() {
    // Resolve active warehouse (async, update state when ready)
    final whAsync = ref.watch(activeWarehouseIdProvider);
    final whId = whAsync.value ?? 1;
    // Read the system default tax rate (POS uses the same provider)
    final taxRate = ref.read(posDefaultTaxRateProvider).value ?? 0;
    return SalesInvoicesFormState(warehouseId: whId, taxRate: taxRate);
  }

  void setWarehouse(int warehouseId) {
    state = state.copyWith(warehouseId: warehouseId);
  }

  void setCostCenter(int? costCenterId) {
    state = state.copyWith(costCenterId: costCenterId);
  }

  // --- Cart Management ---

  void addToCart(ProductEntity product) {
    final existingIndex = state.cart.indexWhere(
      (item) => item.productId == product.id,
    );

    if (existingIndex != -1) {
      final updatedCart = List<SalesCartItem>.from(state.cart);
      updatedCart[existingIndex] = updatedCart[existingIndex].copyWith(
        quantity: updatedCart[existingIndex].quantity + 1,
      );
      state = state.copyWith(cart: updatedCart);
    } else {
      // Seed per-line tax from the product card. `taxEnabled` follows the
      // rate: a product flagged with a non-zero tax rate is taxable by
      // default; the cashier can toggle it off per line for exempt sales.
      // B3: an «معفى» product resolves to 0 % (no company default here).
      final rate = effectiveItemTaxRate(
        rate: product.taxRate,
        exempt: product.taxExempt,
        companyDefault: 0,
      );
      final newItem = SalesCartItem(
        productId: product.id,
        productName: product.name,
        productCode: product.code,
        unitPrice: product.salePrice,
        taxRate: rate,
        taxEnabled: rate > 0,
      );
      state = state.copyWith(cart: [...state.cart, newItem]);
    }
  }

  void updateLineTaxEnabled(int index, bool enabled) {
    if (index < 0 || index >= state.cart.length) return;
    final updatedCart = List<SalesCartItem>.from(state.cart);
    updatedCart[index] = updatedCart[index].copyWith(taxEnabled: enabled);
    state = state.copyWith(cart: updatedCart);
  }

  void updateLineTaxRate(int index, double rate) {
    if (index < 0 || index >= state.cart.length) return;
    final updatedCart = List<SalesCartItem>.from(state.cart);
    updatedCart[index] = updatedCart[index].copyWith(taxRate: rate);
    state = state.copyWith(cart: updatedCart);
  }

  void removeFromCart(int index) {
    if (index < 0 || index >= state.cart.length) return;
    final updatedCart = List<SalesCartItem>.from(state.cart);
    updatedCart.removeAt(index);
    state = state.copyWith(cart: updatedCart);
  }

  void updateQuantity(int index, double quantity) {
    if (index < 0 || index >= state.cart.length) return;
    final updatedCart = List<SalesCartItem>.from(state.cart);
    updatedCart[index] = updatedCart[index].copyWith(quantity: quantity);
    state = state.copyWith(cart: updatedCart);
  }

  void updateUnitPrice(int index, double price) {
    if (index < 0 || index >= state.cart.length) return;
    final updatedCart = List<SalesCartItem>.from(state.cart);
    updatedCart[index] = updatedCart[index].copyWith(unitPrice: price);
    state = state.copyWith(cart: updatedCart);
  }

  void updateUnit(int index, {int? unitId, String? unitName, double? quantityInBase, double? unitPrice}) {
    if (index < 0 || index >= state.cart.length) return;
    final updatedCart = List<SalesCartItem>.from(state.cart);
    updatedCart[index] = updatedCart[index].copyWith(
      selectedUnitId: unitId,
      selectedUnitName: unitName,
      quantityInBase: quantityInBase,
      unitPrice: unitPrice,
    );
    state = state.copyWith(cart: updatedCart);
  }

  // --- Form State ---

  void selectCustomer(int? customerId) {
    state = state.copyWith(selectedCustomerId: customerId);
  }

  void updateDiscount(double discount) {
    state = state.copyWith(discount: discount);
  }

  void updateTax(double tax) {
    state = state.copyWith(tax: tax);
  }

  void toggleTax(bool enabled) {
    state = state.copyWith(taxEnabled: enabled);
  }

  void updatePaidAmount(double paid) {
    state = state.copyWith(paidAmount: paid);
  }

  void updatePaymentMethod(String method) {
    state = state.copyWith(paymentMethod: method);
    // Auto-fill paid amount for cash/transfer payments
    if (method != 'آجل') {
      state = state.copyWith(paidAmount: state.grandTotal);
    }
  }

  void updateNotes(String notes) {
    state = state.copyWith(notes: notes);
  }

  void setReturnMode(bool isReturn) {
    state = state.copyWith(isReturnMode: isReturn);
  }

  void setLoading(bool loading) {
    state = state.copyWith(isLoading: loading);
  }

  void clearForm() {
    state = SalesInvoicesFormState();
  }

  // --- Business Logic ---

  Future<int?> saveInvoice() async {
    try {
      setLoading(true);
      final salesRepo = ref.read(salesRepositoryProvider);
      final auth = ref.read(authProvider);
      final user = auth.user;

      if (state.cart.isEmpty) throw Exception('يرجى إضافة أصناف');

      // Generate invoice number
      final invoiceNumber = state.isReturnMode
          // allow-bare-generateInvoiceNumber: SalesRepositoryImpl wraps in db.transaction (Spec 066 / T006).
          ? await salesRepo.generateInvoiceNumber('RET-')
          // allow-bare-generateInvoiceNumber: SalesRepositoryImpl wraps in db.transaction (Spec 066 / T006).
          : await salesRepo.generateInvoiceNumber('INV');

      // Map cart items to domain entities
      final domainItems = state.cart.map((item) {
        final percentage = item.unitPrice > 0
            ? (item.discount / (item.unitPrice * item.quantity)) * 100
            : 0.0;
        return CartItemEntity(
          productId: item.productId,
          productName: item.productName,
          productCode: item.productCode,
          quantity: item.quantity,
          unitPrice: item.unitPrice,
          discountPercent: percentage,
          selectedUnitId: item.selectedUnitId,
          selectedUnitName: item.selectedUnitName,
          quantityInBase: item.quantityInBase,
          // Per-line tax: 0/disabled lines contribute zero so exempt items
          // inside a mixed invoice do not inflate the VAT journal entry.
          taxRate: item.taxEnabled ? item.taxRate : 0,
          taxAmount: item.taxAmount,
        );
      }).toList();

      // Translate Arabic payment method to English for the DAO layer
      final paymentMethodEn = switch (state.paymentMethod) {
        'نقدي' => 'cash',
        'تحويل' => 'transfer',
        'آجل' => 'credit',
        _ => state.paymentMethod,
      };

      // Auto-fill paid amount for cash/transfer if user didn't set it
      final effectivePaid = (paymentMethodEn != 'credit' && state.paidAmount <= 0)
          ? state.grandTotal
          : state.paidAmount;

      final useCase = CompleteSaleUseCase(salesRepo);

      final request = SaleRequest(
        items: domainItems,
        customerId: state.selectedCustomerId,
        warehouseId: state.warehouseId,
        userId: user?.id ?? 1,
        paymentMethod: paymentMethodEn,
        paidAmount: effectivePaid,
        isReturn: state.isReturnMode,
        notes: state.notes,
        invoiceNumber: invoiceNumber,
        costCenterId: state.costCenterId,
        taxEnabled: state.taxEnabled,
      );

      final result = await useCase.execute(request);

      if (result.isSuccess) {
        final success = result as SaleSuccess;

        // Audit Trail
        await _logger.log(
          userId: user?.id,
          userName: user?.displayName ?? 'Admin',
          action: state.isReturnMode ? 'sales_return' : 'sale',
          entityType: 'invoice',
          entityId: success.invoiceId,
          description: state.isReturnMode
              ? 'إنشاء مرتجع مبيعات $invoiceNumber بقيمة ${state.grandTotal.toStringAsFixed(AppConstants.decimalPlaces)}'
              : 'إنشاء فاتورة مبيعات $invoiceNumber بقيمة ${state.grandTotal.toStringAsFixed(AppConstants.decimalPlaces)}',
          amount: state.grandTotal,
        );

        // #E-Invoice Auto-Submit (fire-and-forget)
        try {
          final autoSubmitter = ref.read(eInvoiceAutoSubmitterProvider);
          if (state.isReturnMode) {
            autoSubmitter.submitCreditNote(success.invoiceId);
          } else {
            autoSubmitter.submitSaleInvoice(success.invoiceId);
          }
        } catch (_) {}

        // NOTE: Server sync is already handled inside completeSalesTransaction()
        // which does direct POST + outbox queuing. No duplicate interceptor call needed.

        // Ensure the sales-list screen reflects this invoice immediately
        // without requiring a manual refresh tap. Mirrors the checkout
        // controller's explicit invalidation.
        ref.invalidate(salesInvoicesChangeProvider);

        setLoading(false);
        return success.invoiceId;
      } else {
        throw Exception((result as SaleFailure).error);
      }
    } catch (e) {
      setLoading(false);
      rethrow;
    }
  }
}

final salesInvoicesFormProvider =
    NotifierProvider<SalesInvoicesFormNotifier, SalesInvoicesFormState>(() {
      return SalesInvoicesFormNotifier();
    });
