import 'package:flutter/material.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../../core/config/app_config.dart';
import '../../../services/client_write_interceptor.dart';
// Spec 135 NOTE 1 — the POS timeout UI now drives the single canonical
// session_timeout_minutes key (System A); invalidate its provider on save.
import '../../../services/session_timeout_service.dart' show sessionTimeoutProvider;

/// Standalone POS Settings Widget — extracted from Hardware Settings
class PosSettingsWidget extends ConsumerStatefulWidget {
  const PosSettingsWidget({super.key});
  @override
  ConsumerState<PosSettingsWidget> createState() => _PosSettingsWidgetState();
}

class _PosSettingsWidgetState extends ConsumerState<PosSettingsWidget> {
  bool _isLoading = true;
  // Action buttons
  bool _showTaxButtonInPOS = true;
  bool _showDiscountButtonInPOS = true;
  bool _showDrawerButtonInPOS = true;
  bool _showExpenseButtonInPOS = true;
  bool _showWorkOrderButton = false;
  bool _showDeliveryButton = false;
  bool _showOffersButton = true;
  bool _showKeyboardButton = true;
  String _invoiceCodePrefix = '';
  // Per-document-type prefix settings
  String _prefixSalesPos = '';
  String _prefixSalesManual = '';
  String _prefixSalesReturn = '';
  String _prefixPurchase = '';
  String _prefixPurchaseReturn = '';
  String _prefixReceiptVoucher = '';
  String _prefixPaymentVoucher = '';
  String _prefixQuotation = '';
  // Cart top buttons
  bool _showReturnButtonInPOS = true;
  bool _showHoldButtonInPOS = true;
  bool _showExchangeButtonInPOS = true;
  bool _showBarcodeInPOS = true;
  bool _showPricingInquiryInPOS = true;
  bool _showSearchInPOS = true;
  bool _showSaveOnlyInPOS = true;
  bool _showSubtotalInPOS = true;
  bool _showAddCustomerInPOS = true;
  // Product icon
  bool _showProductSortInPOS = true;
  bool _showProductImagesInPOS = true;
  bool _showProductLayoutToggleInPOS = true;
  double _productNameFontSize = 12.0;
  double _productPriceFontSize = 14.0;
  // Cart
  bool _posCartRatioLocked = false;
  double _posCartRatioValue = 0.6;
  // Receipt
  bool _autoPrint = false;
  // Feature 022 / Issue 10 follow-up: surface the "السماح بالبيع بالسالب"
  // toggle inside POS settings where the user expects it. Backed by the
  // same `enable_negative_sales` setting that the orchestrator reads on
  // every sale (sales_transaction_orchestrator.dart). Defaults to false
  // (safe); the boot-time backfill writes 'true' on existing installs to
  // preserve legacy behavior.
  bool _enableNegativeSales = false;
  String _receiptCodeType = 'barcode';
  String _invoiceLanguage = 'ar';
  String _receiptFooter = '';
  // Table POS settings
  bool _tposShowBarcode = true;
  bool _tposShowProductImages = true;
  bool _tposShowProductSort = true;
  bool _tposShowCheckout = true;
  double _tposNameFontSize = 12.0;
  double _tposPriceFontSize = 14.0;
  // New POS features
  bool _showOrderTypeInPOS = true;
  bool _showAdhocCustomerInPOS = true;
  bool _preventItemStacking = false; // Each tap = new line instead of merging
  bool _posSessionTimeoutEnabled = true;
  double _posSessionTimeoutMinutes = 5.0; // Double for slider
  // New items 1, 2, 3
  bool _posShiftDialogEnabled = true;
  bool _showTopBar = true;
  String _posStockAlertMode = 'zero'; // 'zero' or 'min_stock'
  double _posDefaultTaxRate = 0.16;
  // Category display settings
  double _catIconSize = 44.0;
  double _catFontSize = 9.0;
  double _catSpacing = 12.0;
  double _catRunSpacing = 8.0;
  double _catLabelWidth = 52.0;
  String _catShape = 'circle';
  double _catMaxHeight = 200.0;
  // Product grid display settings
  int _gridColumns = 8;
  double _gridSpacing = 8.0;
  double _gridAspectRatio = 0.75;
  // POS default warehouse — global (device-specific fallback)
  int? _posDefaultWarehouseId;
  // Feature 006 #4: per-branch default warehouse for this user's branch.
  // Resolved at runtime by activeWarehouseIdProvider before the global value.
  int? _currentBranchId;
  int? _perBranchWarehouseId;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final s = ref.read(settingsRepositoryProvider);
    final autoPrint = await s.getSetting('auto_print_receipt');
    final negativeSales = await s.getSetting('enable_negative_sales');
    final showTax = await s.getSetting('show_tax_button_pos');
    final showDiscount = await s.getSetting('show_discount_button_pos');
    final showDrawer = await s.getSetting('show_drawer_button_pos');
    final showExpense = await s.getSetting('show_expense_button_pos');
    final codeType = await s.getSetting('receipt_code_type');
    final workOrder = await s.getSetting('show_work_order_button');
    final delivery = await s.getSetting('show_delivery_button');
    final offers = await s.getSetting('show_offers_button_pos');
    final keyboard = await s.getSetting('show_keyboard_button_pos');
    final invoicePrefix = await s.getSetting('invoice_code_prefix');
    // Per-document-type prefix settings
    final pSalesPos = await s.getSetting('prefix_sales_pos');
    final pSalesManual = await s.getSetting('prefix_sales_manual');
    final pSalesReturn = await s.getSetting('prefix_sales_return');
    final pPurchase = await s.getSetting('prefix_purchase');
    final pPurchaseReturn = await s.getSetting('prefix_purchase_return');
    final pReceiptVoucher = await s.getSetting('prefix_receipt_voucher');
    final pPaymentVoucher = await s.getSetting('prefix_payment_voucher');
    final pQuotation = await s.getSetting('prefix_quotation');
    final showReturn = await s.getSetting('show_return_button_pos');
    final showHold = await s.getSetting('show_hold_button_pos');
    final showExchange = await s.getSetting('show_exchange_button_pos');
    final showBarcode = await s.getSetting('pos_show_barcode');
    final showPricingInquiry = await s.getSetting('pos_show_pricing_inquiry');
    final showSearch = await s.getSetting('pos_show_search');
    final showSaveOnly = await s.getSetting('pos_show_save_only');
    final showSubtotal = await s.getSetting('pos_show_subtotal');
    final showAddCustomer = await s.getSetting('pos_show_add_customer');
    final showProductSort = await s.getSetting('pos_show_product_sort');
    final showProductImages = await s.getSetting('pos_show_product_images');
    final showProductLayoutToggle = await s.getSetting('pos_show_layout_toggle');
    final cartRatioLocked = await s.getSetting('pos_cart_ratio_locked');
    final cartRatioValue = await s.getSetting('pos_cart_ratio_value');
    final productNameFont = await s.getSetting('pos_product_name_font_size');
    final productPriceFont = await s.getSetting('pos_product_price_font_size');
    final receiptFooter = await s.getSetting('receipt_footer');
    // Table POS settings
    final tposBarcode = await s.getSetting('tpos_show_barcode');
    final tposImages = await s.getSetting('tpos_show_product_images');
    final tposSort = await s.getSetting('tpos_show_product_sort');
    final tposCheckout = await s.getSetting('tpos_show_checkout');
    final tposNameFont = await s.getSetting('tpos_name_font_size');
    final tposPriceFont = await s.getSetting('tpos_price_font_size');
    // New POS features
    final showOrderType = await s.getSetting('pos_show_order_type');
    final showAdhocCustomer = await s.getSetting('pos_show_adhoc_customer');
    final preventStacking = await s.getSetting('pos_prevent_item_stacking');
    // Spec 135 NOTE 1 — read the single canonical key (System A). 0 = disabled.
    final timeoutMinutes = await s.getSetting('session_timeout_minutes');
    // New items 1, 2, 3
    final shiftDialogEnabled = await s.getSetting('pos_shift_dialog_enabled');
    final showTopBar = await s.getSetting('app_show_top_bar');
    final stockAlertMode = await s.getSetting('pos_stock_alert_mode');
    final taxRate = await s.getSetting('pos_default_tax_rate');
    // Category display
    final catIconSize = await s.getSetting('pos_category_icon_size');
    final catFontSize = await s.getSetting('pos_category_font_size');
    final catSpacing = await s.getSetting('pos_category_spacing');
    final catRunSpacing = await s.getSetting('pos_category_run_spacing');
    final catLabelWidth = await s.getSetting('pos_category_label_width');
    final catShape = await s.getSetting('pos_category_shape');
    final catMaxHeight = await s.getSetting('pos_category_max_height');
    // Grid display
    final gridCols = await s.getSetting('pos_grid_columns');
    final gridSpacing = await s.getSetting('pos_grid_spacing');
    final gridAspect = await s.getSetting('pos_grid_aspect_ratio');
    // POS default warehouse
    final posWhId = await s.getSetting('pos_default_warehouse_id');
    // Feature 006 #4: per-branch override
    final branchId = await ref.read(activeBranchIdProvider.future);
    final perBranchWhId = branchId != null
        ? await s.getSetting('pos_default_warehouse_branch_$branchId')
        : null;

    final invoiceLang = await s.getSetting('invoice_language');

    if (mounted) {
      setState(() {
        _autoPrint = autoPrint == 'true';
        _enableNegativeSales = negativeSales == 'true';
        _receiptFooter = receiptFooter ?? '';
        _showTaxButtonInPOS = showTax != 'false';
        _showDiscountButtonInPOS = showDiscount != 'false';
        _showDrawerButtonInPOS = showDrawer != 'false';
        _showExpenseButtonInPOS = showExpense != 'false';
        _receiptCodeType = codeType ?? 'barcode';
        _invoiceLanguage = invoiceLang ?? 'ar';
        _showWorkOrderButton = workOrder == 'true';
        _showDeliveryButton =
            delivery != null ? delivery == 'true' : AppConfig.features.deliveryEnabled;
        _showOffersButton = offers != 'false';
        _showKeyboardButton = keyboard != 'false';
        _invoiceCodePrefix = invoicePrefix ?? '';
        _prefixSalesPos = pSalesPos ?? '';
        _prefixSalesManual = pSalesManual ?? '';
        _prefixSalesReturn = pSalesReturn ?? '';
        _prefixPurchase = pPurchase ?? '';
        _prefixPurchaseReturn = pPurchaseReturn ?? '';
        _prefixReceiptVoucher = pReceiptVoucher ?? '';
        _prefixPaymentVoucher = pPaymentVoucher ?? '';
        _prefixQuotation = pQuotation ?? '';
        _showReturnButtonInPOS = showReturn != 'false';
        _showHoldButtonInPOS = showHold != 'false';
        _showExchangeButtonInPOS = showExchange != 'false';
        _showBarcodeInPOS = showBarcode != 'false';
        _showPricingInquiryInPOS = showPricingInquiry != 'false';
        _showSearchInPOS = showSearch != 'false';
        _showSaveOnlyInPOS = showSaveOnly != 'false';
        _showSubtotalInPOS = showSubtotal != 'false';
        _showAddCustomerInPOS = showAddCustomer != 'false';
        _showProductSortInPOS = showProductSort != 'false';
        _showProductImagesInPOS = showProductImages != 'false';
        _showProductLayoutToggleInPOS = showProductLayoutToggle != 'false';
        _posCartRatioLocked = cartRatioLocked == 'true';
        _posStockAlertMode = stockAlertMode ?? 'zero';
        _posDefaultTaxRate = double.tryParse(taxRate ?? '0.16') ?? 0.16;
        if (cartRatioValue != null) {
          final parsed = double.tryParse(cartRatioValue);
          if (parsed != null && parsed >= 0.3 && parsed <= 0.7) _posCartRatioValue = parsed;
        }
        if (productNameFont != null) {
          final parsed = double.tryParse(productNameFont);
          if (parsed != null && parsed >= 10 && parsed <= 24) _productNameFontSize = parsed;
        }
        if (productPriceFont != null) {
          final parsed = double.tryParse(productPriceFont);
          if (parsed != null && parsed >= 10 && parsed <= 24) _productPriceFontSize = parsed;
        }
        // Table POS
        _tposShowBarcode = tposBarcode != 'false';
        _tposShowProductImages = tposImages != 'false';
        _tposShowProductSort = tposSort != 'false';
        _tposShowCheckout = tposCheckout != 'false';
        if (tposNameFont != null) {
          final parsed = double.tryParse(tposNameFont);
          if (parsed != null && parsed >= 10 && parsed <= 24) _tposNameFontSize = parsed;
        }
        if (tposPriceFont != null) {
          final parsed = double.tryParse(tposPriceFont);
          if (parsed != null && parsed >= 10 && parsed <= 24) _tposPriceFontSize = parsed;
        }
        _isLoading = false;
        _showOrderTypeInPOS = showOrderType != 'false';
        _showAdhocCustomerInPOS = showAdhocCustomer != 'false';
        _preventItemStacking = preventStacking == 'true';
        // Spec 135 NOTE 1 — derive enable + minutes from the single canonical
        // session_timeout_minutes value (System A semantics: 0 = disabled).
        final parsedTimeout = timeoutMinutes == null
            ? null
            : double.tryParse(timeoutMinutes);
        _posSessionTimeoutEnabled = parsedTimeout == null ? true : parsedTimeout > 0;
        if (parsedTimeout != null && parsedTimeout >= 1 && parsedTimeout <= 60) {
          _posSessionTimeoutMinutes = parsedTimeout;
        }
        // New items 1, 2, 3
        _posShiftDialogEnabled = shiftDialogEnabled != 'false';
        _showTopBar = showTopBar != 'false';
        _posStockAlertMode = stockAlertMode ?? 'zero';
        // Category display
        if (catIconSize != null) { final p = double.tryParse(catIconSize); if (p != null) _catIconSize = p.clamp(30, 80); }
        if (catFontSize != null) { final p = double.tryParse(catFontSize); if (p != null) _catFontSize = p.clamp(8, 18); }
        if (catSpacing != null) { final p = double.tryParse(catSpacing); if (p != null) _catSpacing = p.clamp(4, 24); }
        if (catRunSpacing != null) { final p = double.tryParse(catRunSpacing); if (p != null) _catRunSpacing = p.clamp(4, 16); }
        if (catLabelWidth != null) { final p = double.tryParse(catLabelWidth); if (p != null) _catLabelWidth = p.clamp(40, 80); }
        _catShape = catShape ?? 'circle';
        if (catMaxHeight != null) { final p = double.tryParse(catMaxHeight); if (p != null) _catMaxHeight = p.clamp(80, 300); }
        // Grid display
        if (gridCols != null) { final p = int.tryParse(gridCols); if (p != null) _gridColumns = p.clamp(2, 12); }
        if (gridSpacing != null) { final p = double.tryParse(gridSpacing); if (p != null) _gridSpacing = p.clamp(2, 20); }
        if (gridAspect != null) { final p = double.tryParse(gridAspect); if (p != null) _gridAspectRatio = p.clamp(0.5, 1.5); }
        // POS default warehouse
        if (posWhId != null) { _posDefaultWarehouseId = int.tryParse(posWhId); }
        _currentBranchId = branchId;
        if (perBranchWhId != null && perBranchWhId.isNotEmpty) {
          _perBranchWarehouseId = int.tryParse(perBranchWhId);
        }
      });
    }
  }

  Future<void> _saveSettings() async {
    final s = ref.read(settingsRepositoryProvider);
    await s.saveSetting('auto_print_receipt', _autoPrint.toString());
    await s.saveSetting('enable_negative_sales', _enableNegativeSales.toString());
    await s.saveSetting('receipt_code_type', _receiptCodeType);
    await s.saveSetting('invoice_language', _invoiceLanguage);
    await s.saveSetting('receipt_footer', _receiptFooter);
    await s.saveSetting('show_tax_button_pos', _showTaxButtonInPOS.toString());
    await s.saveSetting('show_discount_button_pos', _showDiscountButtonInPOS.toString());
    await s.saveSetting('show_drawer_button_pos', _showDrawerButtonInPOS.toString());
    await s.saveSetting('show_expense_button_pos', _showExpenseButtonInPOS.toString());
    await s.saveSetting('show_work_order_button', _showWorkOrderButton.toString());
    await s.saveSetting('show_delivery_button', _showDeliveryButton.toString());
    await s.saveSetting('show_offers_button_pos', _showOffersButton.toString());
    await s.saveSetting('show_keyboard_button_pos', _showKeyboardButton.toString());
    await s.saveSetting('invoice_code_prefix', _prefixSalesPos.isNotEmpty ? _prefixSalesPos : _invoiceCodePrefix);
    // Per-document-type prefix settings
    await s.saveSetting('prefix_sales_pos', _prefixSalesPos);
    await s.saveSetting('prefix_sales_manual', _prefixSalesManual);
    await s.saveSetting('prefix_sales_return', _prefixSalesReturn);
    await s.saveSetting('prefix_purchase', _prefixPurchase);
    await s.saveSetting('prefix_purchase_return', _prefixPurchaseReturn);
    await s.saveSetting('prefix_receipt_voucher', _prefixReceiptVoucher);
    await s.saveSetting('prefix_payment_voucher', _prefixPaymentVoucher);
    await s.saveSetting('prefix_quotation', _prefixQuotation);

    // Phase 3: fail loud if two document types end up with the same
    // prefix — duplicates would cause invoice numbers to collide and
    // trip the UNIQUE constraint the moment a transaction saves.
    final db = ref.read(databaseProvider);
    final prefixError = await db.validateInvoicePrefixes();
    if (prefixError != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(prefixError),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 6),
        ),
      );
      return;
    }
    await s.saveSetting('show_return_button_pos', _showReturnButtonInPOS.toString());
    await s.saveSetting('show_hold_button_pos', _showHoldButtonInPOS.toString());
    await s.saveSetting('show_exchange_button_pos', _showExchangeButtonInPOS.toString());
    await s.saveSetting('pos_show_barcode', _showBarcodeInPOS.toString());
    await s.saveSetting('pos_show_pricing_inquiry', _showPricingInquiryInPOS.toString());
    await s.saveSetting('pos_show_search', _showSearchInPOS.toString());
    await s.saveSetting('pos_show_save_only', _showSaveOnlyInPOS.toString());
    await s.saveSetting('pos_show_subtotal', _showSubtotalInPOS.toString());
    await s.saveSetting('pos_show_add_customer', _showAddCustomerInPOS.toString());
    await s.saveSetting('pos_show_product_sort', _showProductSortInPOS.toString());
    await s.saveSetting('pos_show_product_images', _showProductImagesInPOS.toString());
    await s.saveSetting('pos_show_layout_toggle', _showProductLayoutToggleInPOS.toString());
    await s.saveSetting('pos_cart_ratio_locked', _posCartRatioLocked.toString());
    await s.saveSetting('pos_cart_ratio_value', _posCartRatioValue.toString());
    await s.saveSetting('pos_product_name_font_size', _productNameFontSize.toString());
    await s.saveSetting('pos_product_price_font_size', _productPriceFontSize.toString());
    // Table POS settings
    await s.saveSetting('tpos_show_barcode', _tposShowBarcode.toString());
    await s.saveSetting('tpos_show_product_images', _tposShowProductImages.toString());
    await s.saveSetting('tpos_show_product_sort', _tposShowProductSort.toString());
    await s.saveSetting('tpos_show_checkout', _tposShowCheckout.toString());
    await s.saveSetting('tpos_name_font_size', _tposNameFontSize.toString());
    await s.saveSetting('tpos_price_font_size', _tposPriceFontSize.toString());
    // New POS features
    await s.saveSetting('pos_show_order_type', _showOrderTypeInPOS.toString());
    await s.saveSetting('pos_show_adhoc_customer', _showAdhocCustomerInPOS.toString());
    await s.saveSetting('pos_prevent_item_stacking', _preventItemStacking.toString());
    // Spec 135 NOTE 1 — write the single canonical key. Toggle OFF → 0
    // (disabled); ON → the chosen minutes. This is the SAME key General
    // Settings writes, so there is exactly one flag + one minutes + one
    // detector (InactivityDetector).
    await s.saveSetting('session_timeout_minutes',
        (_posSessionTimeoutEnabled ? _posSessionTimeoutMinutes.round() : 0).toString());
    // New items 1, 2, 3
    await s.saveSetting('pos_shift_dialog_enabled', _posShiftDialogEnabled.toString());
    await s.saveSetting('app_show_top_bar', _showTopBar.toString());
    await s.saveSetting('pos_stock_alert_mode', _posStockAlertMode);
    await s.saveSetting('pos_default_tax_rate', _posDefaultTaxRate.toString());
    // Category display settings
    await s.saveSetting('pos_category_icon_size', _catIconSize.toString());
    await s.saveSetting('pos_category_font_size', _catFontSize.toString());
    await s.saveSetting('pos_category_spacing', _catSpacing.toString());
    await s.saveSetting('pos_category_run_spacing', _catRunSpacing.toString());
    await s.saveSetting('pos_category_label_width', _catLabelWidth.toString());
    await s.saveSetting('pos_category_shape', _catShape);
    await s.saveSetting('pos_category_max_height', _catMaxHeight.toString());
    // Grid display settings
    await s.saveSetting('pos_grid_columns', _gridColumns.toString());
    await s.saveSetting('pos_grid_spacing', _gridSpacing.toString());
    await s.saveSetting('pos_grid_aspect_ratio', _gridAspectRatio.toString());
    // POS default warehouse
    if (_posDefaultWarehouseId != null) {
      await s.saveSetting('pos_default_warehouse_id', _posDefaultWarehouseId.toString());
    } else {
      await s.saveSetting('pos_default_warehouse_id', '');
    }
    // Feature 006 #4: per-branch override
    if (_currentBranchId != null) {
      final key = 'pos_default_warehouse_branch_$_currentBranchId';
      await s.saveSetting(key, _perBranchWarehouseId?.toString() ?? '');
    }
    // ── Client mode: batch-sync ALL settings to server ──
    final allSettings = <String, String>{
      // Receipt & printing
      'auto_print_receipt': _autoPrint.toString(),
      'receipt_code_type': _receiptCodeType,
      'invoice_language': _invoiceLanguage,
      'receipt_footer': _receiptFooter,
      // Action buttons
      'show_tax_button_pos': _showTaxButtonInPOS.toString(),
      'show_discount_button_pos': _showDiscountButtonInPOS.toString(),
      'show_drawer_button_pos': _showDrawerButtonInPOS.toString(),
      'show_expense_button_pos': _showExpenseButtonInPOS.toString(),
      'show_work_order_button': _showWorkOrderButton.toString(),
      'show_delivery_button': _showDeliveryButton.toString(),
      'show_offers_button_pos': _showOffersButton.toString(),
      'show_keyboard_button_pos': _showKeyboardButton.toString(),
      // Document prefixes
      'invoice_code_prefix': _prefixSalesPos.isNotEmpty ? _prefixSalesPos : _invoiceCodePrefix,
      'prefix_sales_pos': _prefixSalesPos,
      'prefix_sales_manual': _prefixSalesManual,
      'prefix_sales_return': _prefixSalesReturn,
      'prefix_purchase': _prefixPurchase,
      'prefix_purchase_return': _prefixPurchaseReturn,
      'prefix_receipt_voucher': _prefixReceiptVoucher,
      'prefix_payment_voucher': _prefixPaymentVoucher,
      'prefix_quotation': _prefixQuotation,
      // Cart top buttons
      'show_return_button_pos': _showReturnButtonInPOS.toString(),
      'show_hold_button_pos': _showHoldButtonInPOS.toString(),
      'show_exchange_button_pos': _showExchangeButtonInPOS.toString(),
      // Display toggles
      'pos_show_barcode': _showBarcodeInPOS.toString(),
      'pos_show_pricing_inquiry': _showPricingInquiryInPOS.toString(),
      'pos_show_search': _showSearchInPOS.toString(),
      'pos_show_save_only': _showSaveOnlyInPOS.toString(),
      'pos_show_subtotal': _showSubtotalInPOS.toString(),
      'pos_show_add_customer': _showAddCustomerInPOS.toString(),
      'pos_show_product_sort': _showProductSortInPOS.toString(),
      'pos_show_product_images': _showProductImagesInPOS.toString(),
      'pos_show_layout_toggle': _showProductLayoutToggleInPOS.toString(),
      'pos_show_order_type': _showOrderTypeInPOS.toString(),
      'pos_show_adhoc_customer': _showAdhocCustomerInPOS.toString(),
      'pos_prevent_item_stacking': _preventItemStacking.toString(),
      // Cart settings
      'pos_cart_ratio_locked': _posCartRatioLocked.toString(),
      'pos_cart_ratio_value': _posCartRatioValue.toString(),
      'pos_product_name_font_size': _productNameFontSize.toString(),
      'pos_product_price_font_size': _productPriceFontSize.toString(),
      // Shift & security
      'pos_shift_dialog_enabled': _posShiftDialogEnabled.toString(),
      'app_show_top_bar': _showTopBar.toString(),
      'pos_stock_alert_mode': _posStockAlertMode,
      'pos_default_tax_rate': _posDefaultTaxRate.toString(),
      // Spec 135 NOTE 1 — single canonical key (0 = disabled).
      'session_timeout_minutes':
          (_posSessionTimeoutEnabled ? _posSessionTimeoutMinutes.round() : 0).toString(),
      // Table POS settings
      'tpos_show_barcode': _tposShowBarcode.toString(),
      'tpos_show_product_images': _tposShowProductImages.toString(),
      'tpos_show_product_sort': _tposShowProductSort.toString(),
      'tpos_show_checkout': _tposShowCheckout.toString(),
      'tpos_name_font_size': _tposNameFontSize.toString(),
      'tpos_price_font_size': _tposPriceFontSize.toString(),
      // Category display settings
      'pos_category_icon_size': _catIconSize.toString(),
      'pos_category_font_size': _catFontSize.toString(),
      'pos_category_spacing': _catSpacing.toString(),
      'pos_category_run_spacing': _catRunSpacing.toString(),
      'pos_category_label_width': _catLabelWidth.toString(),
      'pos_category_shape': _catShape,
      'pos_category_max_height': _catMaxHeight.toString(),
      // Grid display settings
      'pos_grid_columns': _gridColumns.toString(),
      'pos_grid_spacing': _gridSpacing.toString(),
      'pos_grid_aspect_ratio': _gridAspectRatio.toString(),
      // POS default warehouse
      'pos_default_warehouse_id': _posDefaultWarehouseId?.toString() ?? '',
      // Feature 006 #4: per-branch override (only present when branch known)
      if (_currentBranchId != null)
        'pos_default_warehouse_branch_$_currentBranchId':
            _perBranchWarehouseId?.toString() ?? '',
    };
    // Spec 118 (Bug Z) — تغليف saveSettings بـ try/catch لمنع رفع
    // exceptions (خاصة 429 rate limit) لـ PlatformDispatcher. الـ
    // settings المحلية تم حفظها بالفعل أعلاه (s.saveSetting calls)،
    // فالـ server sync fire-and-forget آمن.
    try {
      await ClientWriteInterceptor.saveSettings(allSettings);
    } catch (e) {
      // ignore: avoid_print
      print('[POS-SETTINGS-SYNC] server sync failed (local saved): $e');
      if (mounted) {
        final isRateLimit = e.toString().contains('429') ||
            e.toString().contains('Too many requests');
        AppToast.show(
          context,
          isRateLimit
              ? 'تم الحفظ محلياً — السيرفر مشغول، ستُزامَن لاحقاً'
              : 'تم الحفظ محلياً — السيرفر غير متاح، ستُزامَن لاحقاً',
          type: ToastType.warning,
        );
      }
    }
    if (mounted) {
      // Invalidate all POS-related providers so changes take effect immediately
      ref.invalidate(showTaxButtonInPOSProvider);
      ref.invalidate(showDiscountButtonInPOSProvider);
      ref.invalidate(showDrawerButtonInPOSProvider);
      ref.invalidate(showExpenseButtonInPOSProvider);
      ref.invalidate(receiptCodeTypeProvider);
      ref.invalidate(showWorkOrderButtonProvider);
      ref.invalidate(showDeliveryButtonProvider);
      ref.invalidate(showOffersButtonProvider);
      ref.invalidate(showKeyboardButtonProvider);
      ref.invalidate(invoiceCodePrefixProvider);
      ref.invalidate(showReturnButtonInPOSProvider);
      ref.invalidate(showHoldButtonInPOSProvider);
      ref.invalidate(showExchangeButtonInPOSProvider);
      ref.invalidate(showBarcodeInPOSProvider);
      ref.invalidate(showPricingInquiryInPOSProvider);
      ref.invalidate(showSearchInPOSProvider);
      ref.invalidate(showSaveOnlyInPOSProvider);
      ref.invalidate(showSubtotalInPOSProvider);
      ref.invalidate(showAddCustomerInPOSProvider);
      ref.invalidate(showProductSortInPOSProvider);
      ref.invalidate(showProductImagesProvider);
      ref.invalidate(showProductLayoutToggleInPOSProvider);
      ref.invalidate(productNameFontSizeProvider);
      ref.invalidate(productPriceFontSizeProvider);
      ref.invalidate(posCartRatioLockedProvider);
      ref.invalidate(posCartRatioValueProvider);
      ref.invalidate(showOrderTypeInPOSProvider);
      ref.invalidate(showAdhocCustomerInPOSProvider);
      ref.invalidate(preventItemStackingProvider);
      ref.invalidate(sessionTimeoutProvider); // Spec 135 NOTE 1 — single key
      ref.invalidate(posShiftDialogEnabledProvider);
      ref.invalidate(showTopBarProvider);
      ref.invalidate(posStockAlertModeProvider);
      ref.invalidate(posDefaultTaxRateProvider);
      // Category display
      ref.invalidate(posCategoryIconSizeProvider);
      ref.invalidate(posCategoryFontSizeProvider);
      ref.invalidate(posCategorySpacingProvider);
      ref.invalidate(posCategoryRunSpacingProvider);
      ref.invalidate(posCategoryLabelWidthProvider);
      ref.invalidate(posCategoryShapeProvider);
      ref.invalidate(posCategoryMaxHeightProvider);
      // Grid display
      ref.invalidate(posGridColumnsProvider);
      ref.invalidate(posGridSpacingProvider);
      ref.invalidate(posGridAspectRatioProvider);
      // Warehouse & safe providers — CRITICAL for branch-specific operations
      ref.invalidate(activeWarehouseIdProvider);
      ref.invalidate(posCashSafeIdProvider);
      ref.invalidate(posBankSafeIdProvider);
      AppToast.show(context, 'تم حفظ إعدادات نقطة البيع', type: ToastType.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(children: [
                _buildMainPOSSection(),
                const SizedBox(height: 16),
                _buildCategoryDisplaySection(),
                const SizedBox(height: 16),
                _buildProductGridSection(),
                const SizedBox(height: 16),
                _buildReceiptSection(),
                const SizedBox(height: 16),
                _buildTablePOSSection(),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity, height: 48,
            child: ElevatedButton(onPressed: _saveSettings, child: const Text('حفظ الإعدادات')),
          ),
        ],
      ),
    );
  }

  Widget _buildMainPOSSection() {
    return _buildSectionCard(
      title: 'إعدادات نقطة البيع الرئيسية', icon: PhosphorIconsBold.shoppingCart, iconColor: AppColors.primary,
      children: [
        // ─── إعدادات الوردية والعرض ───
        const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('إعدادات الوردية والعرض', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.primary))),
        SwitchListTile(title: const Text('إظهار ديالوج فتح الوردية'), subtitle: const Text('عند الإغلاق يتم فتح الوردية تلقائياً بدون سؤال'), value: _posShiftDialogEnabled, onChanged: (v) => setState(() => _posShiftDialogEnabled = v), contentPadding: EdgeInsets.zero),
        SwitchListTile(title: const Text('إظهار شريط التنقل العلوي'), subtitle: const Text('إظهار أو إخفاء شريط التنبيهات والتنقل أعلى الشاشة'), value: _showTopBar, onChanged: (v) => setState(() => _showTopBar = v), contentPadding: EdgeInsets.zero),
        ListTile(
          title: const Text('وضع تنبيهات المخزون'),
          subtitle: Text(_posStockAlertMode == 'min_stock' ? 'تنبيه عند الوصول للحد الأدنى' : 'تنبيه فقط عند نفاد المخزون'),
          contentPadding: EdgeInsets.zero,
          trailing: DropdownButton<String>(
            value: _posStockAlertMode,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: 'zero', child: Text('نفاد المخزون فقط')),
              DropdownMenuItem(value: 'min_stock', child: Text('الحد الأدنى')),
            ],
            onChanged: (v) => setState(() => _posStockAlertMode = v ?? 'zero'),
          ),
        ),
        // Feature 022 (follow-up): expose the negative-sales toggle in
        // POS settings — that's where operators expect it. The same
        // setting key is read by sales_transaction_orchestrator on every
        // sale; defaults to false (block) on fresh installs and is
        // preserved as true on existing installs via the boot-time
        // backfill (Cluster 018).
        SwitchListTile(
          title: const Text('السماح بالبيع بالسالب عند نقص المخزون'),
          subtitle: Text(
            _enableNegativeSales
                ? 'يمكن للكاشير بيع أصناف خارج المخزون — قد ينتج مخزون سالب.'
                : 'يمنع البيع عند نفاد المخزون ويظهر تنبيه باللغة العربية.',
          ),
          value: _enableNegativeSales,
          onChanged: (v) => setState(() => _enableNegativeSales = v),
          contentPadding: EdgeInsets.zero,
          secondary: Icon(
            PhosphorIconsBold.warning,
            color: _enableNegativeSales ? AppColors.warning : AppColors.success,
          ),
        ),
        ListTile(
          title: const Text('نسبة الضريبة الافتراضية'),
          subtitle: const Text('النسبة المئوية للضريبة التي يتم تطبيقها تلقائياً'),
          contentPadding: EdgeInsets.zero,
          trailing: SizedBox(
            width: 100,
            child: TextFormField(
              initialValue: (_posDefaultTaxRate * 100).toStringAsFixed(0),
              decoration: const InputDecoration(
                suffixText: '%',
                isDense: true,
              ),
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              onChanged: (v) {
                final val = double.tryParse(v);
                if (val != null) {
                  setState(() => _posDefaultTaxRate = val / 100);
                }
              },
            ),
          ),
        ),
        // ─── المخزن الافتراضي لنقطة البيع ───
        FutureBuilder(
          future: ref.read(branchRepositoryProvider).getWarehouses(),
          builder: (context, snapshot) {
            final warehouses = snapshot.data ?? [];
            if (warehouses.isEmpty) return const SizedBox.shrink();
            return Column(
              children: [
                // Feature 006 #4: Per-branch picker. Wins over the global one
                // when set; lets HQ admins assign each branch a default
                // warehouse without juggling per-device overrides.
                if (_currentBranchId != null)
                  ListTile(
                    title: const Text('المخزن الافتراضي لـ POS هذا الفرع'),
                    subtitle: const Text('يُطبَّق على كل أجهزة هذا الفرع — يسبق الإعداد العام'),
                    contentPadding: EdgeInsets.zero,
                    trailing: DropdownButton<int?>(
                      value: warehouses.any((w) => w.id == _perBranchWarehouseId)
                          ? _perBranchWarehouseId : null,
                      underline: const SizedBox.shrink(),
                      hint: const Text('استخدم الإعداد العام'),
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('استخدم الإعداد العام')),
                        ...warehouses.map((w) => DropdownMenuItem<int?>(value: w.id, child: Text(w.name ?? ''))),
                      ],
                      onChanged: (v) => setState(() => _perBranchWarehouseId = v),
                    ),
                  ),
                ListTile(
                  title: const Text('المخزن الافتراضي لنقطة البيع (عام)'),
                  subtitle: const Text('يُستخدم إذا لم يكن هناك إعداد مخصّص للفرع'),
                  contentPadding: EdgeInsets.zero,
                  trailing: DropdownButton<int?>(
                    value: warehouses.any((w) => w.id == _posDefaultWarehouseId) ? _posDefaultWarehouseId : null,
                    underline: const SizedBox.shrink(),
                    hint: const Text('تلقائي (الافتراضي)'),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('تلقائي (الافتراضي)')),
                      ...warehouses.map((w) => DropdownMenuItem<int?>(value: w.id, child: Text(w.name ?? ''))),
                    ],
                    onChanged: (v) => setState(() => _posDefaultWarehouseId = v),
                  ),
                ),
              ],
            );
          },
        ),
        const Divider(thickness: 2),

        // ─── أزرار الإجراءات السريعة والسلة ───
        const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('أزرار نقطة البيع والسلة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.primary))),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterChip(label: const Text('زر الضريبة'), selected: _showTaxButtonInPOS, onSelected: (v) => setState(() => _showTaxButtonInPOS = v)),
            FilterChip(label: const Text('زر الخصم'), selected: _showDiscountButtonInPOS, onSelected: (v) => setState(() => _showDiscountButtonInPOS = v)),
            FilterChip(label: const Text('زر الدرج'), selected: _showDrawerButtonInPOS, onSelected: (v) => setState(() => _showDrawerButtonInPOS = v)),
            FilterChip(label: const Text('زر المصاريف'), selected: _showExpenseButtonInPOS, onSelected: (v) => setState(() => _showExpenseButtonInPOS = v)),
            FilterChip(label: const Text('زر أمر الشغل'), selected: _showWorkOrderButton, onSelected: (v) => setState(() => _showWorkOrderButton = v)),
            FilterChip(label: const Text('زر التوصيل'), selected: _showDeliveryButton, onSelected: (v) => setState(() => _showDeliveryButton = v)),
            FilterChip(label: const Text('زر العروض'), selected: _showOffersButton, onSelected: (v) => setState(() => _showOffersButton = v)),
            FilterChip(label: const Text('لوحة المفاتيح'), selected: _showKeyboardButton, onSelected: (v) => setState(() => _showKeyboardButton = v)),
            FilterChip(label: const Text('زر المرتجعات'), selected: _showReturnButtonInPOS, onSelected: (v) => setState(() => _showReturnButtonInPOS = v)),
            FilterChip(label: const Text('أزرار التعليق'), selected: _showHoldButtonInPOS, onSelected: (v) => setState(() => _showHoldButtonInPOS = v)),
            FilterChip(label: const Text('زر الاستبدال'), selected: _showExchangeButtonInPOS, onSelected: (v) => setState(() => _showExchangeButtonInPOS = v)),
          ],
        ),
        const Divider(thickness: 2),

        // ─── إعدادات ترقيم المستندات ───
        const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('إعدادات ترقيم المستندات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.primary))),
        const Text('تحديد بادئة الترقيم لكل نوع مستند. اترك الحقل فارغاً للترقيم الافتراضي.', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
        const SizedBox(height: 8),
        // Sales group
        Row(children: [
          Expanded(child: TextFormField(
            initialValue: _prefixSalesPos,
            decoration: const InputDecoration(labelText: 'فاتورة مبيعات (POS)', hintText: 'R-', prefixIcon: Icon(PhosphorIconsBold.receipt, size: 18), isDense: true),
            onChanged: (v) => _prefixSalesPos = v,
          )),
          const SizedBox(width: 12),
          Expanded(child: TextFormField(
            initialValue: _prefixSalesManual,
            decoration: const InputDecoration(labelText: 'فاتورة مبيعات (يدوية)', hintText: 'INV', prefixIcon: Icon(PhosphorIconsBold.fileText, size: 18), isDense: true),
            onChanged: (v) => _prefixSalesManual = v,
          )),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextFormField(
            initialValue: _prefixSalesReturn,
            decoration: const InputDecoration(labelText: 'مردودات مبيعات', hintText: 'RET-', prefixIcon: Icon(PhosphorIconsBold.arrowUUpLeft, size: 18), isDense: true),
            onChanged: (v) => _prefixSalesReturn = v,
          )),
          const SizedBox(width: 12),
          Expanded(child: TextFormField(
            initialValue: _prefixQuotation,
            decoration: const InputDecoration(labelText: 'عرض سعر', hintText: 'QUO', prefixIcon: Icon(PhosphorIconsBold.clipboardText, size: 18), isDense: true),
            onChanged: (v) => _prefixQuotation = v,
          )),
        ]),
        const SizedBox(height: 8),
        // Purchases group
        Row(children: [
          Expanded(child: TextFormField(
            initialValue: _prefixPurchase,
            decoration: const InputDecoration(labelText: 'فاتورة مشتريات', hintText: 'PUR', prefixIcon: Icon(PhosphorIconsBold.shoppingBag, size: 18), isDense: true),
            onChanged: (v) => _prefixPurchase = v,
          )),
          const SizedBox(width: 12),
          Expanded(child: TextFormField(
            initialValue: _prefixPurchaseReturn,
            decoration: const InputDecoration(labelText: 'مردودات مشتريات', hintText: 'PRET', prefixIcon: Icon(PhosphorIconsBold.arrowUUpRight, size: 18), isDense: true),
            onChanged: (v) => _prefixPurchaseReturn = v,
          )),
        ]),
        const SizedBox(height: 8),
        // Treasury group
        Row(children: [
          Expanded(child: TextFormField(
            initialValue: _prefixReceiptVoucher,
            decoration: const InputDecoration(labelText: 'سند قبض', hintText: 'RV', prefixIcon: Icon(PhosphorIconsBold.arrowDown, size: 18), isDense: true),
            onChanged: (v) => _prefixReceiptVoucher = v,
          )),
          const SizedBox(width: 12),
          Expanded(child: TextFormField(
            initialValue: _prefixPaymentVoucher,
            decoration: const InputDecoration(labelText: 'سند صرف', hintText: 'PV', prefixIcon: Icon(PhosphorIconsBold.arrowUp, size: 18), isDense: true),
            onChanged: (v) => _prefixPaymentVoucher = v,
          )),
        ]),
        const Divider(thickness: 2),

        // ─── واجهة العرض والتفاعل ───
        const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('واجهة العرض والتفاعل', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.primary))),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterChip(label: const Text('حقل الباركود'), selected: _showBarcodeInPOS, onSelected: (v) => setState(() => _showBarcodeInPOS = v)),
            FilterChip(label: const Text('تسعير الأصناف (شاشة منبثقة)'), selected: _showPricingInquiryInPOS, onSelected: (v) => setState(() => _showPricingInquiryInPOS = v)),
            FilterChip(label: const Text('البحث عن المنتج'), selected: _showSearchInPOS, onSelected: (v) => setState(() => _showSearchInPOS = v)),
            FilterChip(label: const Text('الحفظ فقط'), selected: _showSaveOnlyInPOS, onSelected: (v) => setState(() => _showSaveOnlyInPOS = v)),
            FilterChip(label: const Text('المجموع الفرعي'), selected: _showSubtotalInPOS, onSelected: (v) => setState(() => _showSubtotalInPOS = v)),
            FilterChip(label: const Text('إضافة عميل'), selected: _showAddCustomerInPOS, onSelected: (v) => setState(() => _showAddCustomerInPOS = v)),
            FilterChip(label: const Text('نوع الطلب'), selected: _showOrderTypeInPOS, onSelected: (v) => setState(() => _showOrderTypeInPOS = v)),
            FilterChip(label: const Text('اسم العميل بالسلة'), selected: _showAdhocCustomerInPOS, onSelected: (v) => setState(() => _showAdhocCustomerInPOS = v)),
            FilterChip(label: const Text('منع تراكم الأصناف (سطر جديد)'), selected: _preventItemStacking, onSelected: (v) => setState(() => _preventItemStacking = v)),
          ],
        ),
        const Divider(thickness: 2),

        // ─── أيقونة الصنف وباقي الإعدادات ───
        const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('عرض المنتجات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.primary))),
        SwitchListTile(title: const Text('إظهار صور الأصناف'), subtitle: const Text('إظهار أو إخفاء صور المنتجات في شبكة نقطة البيع'), value: _showProductImagesInPOS, onChanged: (v) => setState(() => _showProductImagesInPOS = v), contentPadding: EdgeInsets.zero),
        SwitchListTile(title: const Text('إظهار ترتيب الأصناف'), value: _showProductSortInPOS, onChanged: (v) => setState(() => _showProductSortInPOS = v), contentPadding: EdgeInsets.zero),
        SwitchListTile(title: const Text('إظهار زر طي القائمة'), subtitle: const Text('إظهار أو إخفاء زر التحكم في أماكن عرض المنتجات'), value: _showProductLayoutToggleInPOS, onChanged: (v) => setState(() => _showProductLayoutToggleInPOS = v), contentPadding: EdgeInsets.zero),
        const SizedBox(height: 8),
        Row(children: [
          const Text('حجم خط الاسم: '),
          Expanded(child: Slider(value: _productNameFontSize, min: 10, max: 24, divisions: 14, label: '${_productNameFontSize.round()}', onChanged: (v) => setState(() => _productNameFontSize = v))),
          Text('${_productNameFontSize.round()}', style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
        Row(children: [
          const Text('حجم خط السعر: '),
          Expanded(child: Slider(value: _productPriceFontSize, min: 10, max: 24, divisions: 14, label: '${_productPriceFontSize.round()}', onChanged: (v) => setState(() => _productPriceFontSize = v))),
          Text('${_productPriceFontSize.round()}', style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
        const Divider(thickness: 2),

        // ─── إعدادات السلة ───
        const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('إعدادات السلة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.primary))),
        SwitchListTile(title: const Text('قفل نسبة عرض السلة'), subtitle: const Text('منع الكاشير من تغيير حجم السلة'), value: _posCartRatioLocked, onChanged: (v) => setState(() => _posCartRatioLocked = v), contentPadding: EdgeInsets.zero),
        if (_posCartRatioLocked) ...[
          const SizedBox(height: 8),
          Row(children: [
            const Text('نسبة عرض السلة: '),
            Expanded(child: Slider(value: _posCartRatioValue, min: 0.3, max: 0.7, divisions: 8, label: '${(_posCartRatioValue * 100).round()}%', onChanged: (v) => setState(() => _posCartRatioValue = v))),
            Text('${(_posCartRatioValue * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
        ],
        const Divider(thickness: 2),

        // ─── إعدادات الأمان ───
        const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('إعدادات الأمان والحماية', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.primary))),
        SwitchListTile(title: const Text('مهلة انتهاء الجلسة'), subtitle: const Text('تسجيل خروج تلقائي عند ترك النظام بدون نشاط (نفس إعداد الإعدادات العامة)'), value: _posSessionTimeoutEnabled, onChanged: (v) => setState(() => _posSessionTimeoutEnabled = v), contentPadding: EdgeInsets.zero),
        if (_posSessionTimeoutEnabled) ...[
          const SizedBox(height: 8),
          Row(children: [
            const Text('مدة الانتظار (دقائق): '),
            Expanded(child: Slider(value: _posSessionTimeoutMinutes, min: 1, max: 60, divisions: 59, label: '${_posSessionTimeoutMinutes.round()} دقيقة', onChanged: (v) => setState(() => _posSessionTimeoutMinutes = v))),
            Text('${_posSessionTimeoutMinutes.round()}', style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
        ],
      ],
    );
  }

  Widget _buildCategoryDisplaySection() {
    return _buildSectionCard(
      title: 'إعدادات منطقة التصنيفات', icon: PhosphorIconsBold.squaresFour, iconColor: AppColors.success,
      children: [
        const Text('تحكم في مظهر أيقونات التصنيفات أسفل منطقة المنتجات', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        const SizedBox(height: 12),
        Row(children: [
          const Text('حجم الأيقونة: '),
          Expanded(child: Slider(value: _catIconSize, min: 30, max: 80, divisions: 10, label: '${_catIconSize.round()}', onChanged: (v) => setState(() => _catIconSize = v))),
          Text('${_catIconSize.round()}', style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
        Row(children: [
          const Text('حجم خط الاسم: '),
          Expanded(child: Slider(value: _catFontSize, min: 8, max: 18, divisions: 10, label: '${_catFontSize.round()}', onChanged: (v) => setState(() => _catFontSize = v))),
          Text('${_catFontSize.round()}', style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
        Row(children: [
          const Text('التباعد الأفقي: '),
          Expanded(child: Slider(value: _catSpacing, min: 4, max: 24, divisions: 10, label: '${_catSpacing.round()}', onChanged: (v) => setState(() => _catSpacing = v))),
          Text('${_catSpacing.round()}', style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
        Row(children: [
          const Text('التباعد الرأسي: '),
          Expanded(child: Slider(value: _catRunSpacing, min: 4, max: 16, divisions: 6, label: '${_catRunSpacing.round()}', onChanged: (v) => setState(() => _catRunSpacing = v))),
          Text('${_catRunSpacing.round()}', style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
        Row(children: [
          const Text('عرض نص التصنيف: '),
          Expanded(child: Slider(value: _catLabelWidth, min: 40, max: 80, divisions: 8, label: '${_catLabelWidth.round()}', onChanged: (v) => setState(() => _catLabelWidth = v))),
          Text('${_catLabelWidth.round()}', style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
        Row(children: [
          const Text('ارتفاع المنطقة: '),
          Expanded(child: Slider(value: _catMaxHeight, min: 80, max: 300, divisions: 11, label: '${_catMaxHeight.round()}', onChanged: (v) => setState(() => _catMaxHeight = v))),
          Text('${_catMaxHeight.round()}', style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('شكل الأيقونة'),
          trailing: DropdownButton<String>(
            value: _catShape,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: 'circle', child: Text('دائري')),
              DropdownMenuItem(value: 'rounded', child: Text('مستطيل مدور')),
            ],
            onChanged: (v) => setState(() => _catShape = v ?? 'circle'),
          ),
        ),
      ],
    );
  }

  Widget _buildProductGridSection() {
    return _buildSectionCard(
      title: 'إعدادات شبكة المنتجات', icon: PhosphorIconsBold.gridFour, iconColor: AppColors.info,
      children: [
        const Text('تحكم في عدد وتباعد أيقونات المنتجات في الشبكة', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        const SizedBox(height: 12),
        Row(children: [
          const Text('عدد الأعمدة: '),
          Expanded(child: Slider(value: _gridColumns.toDouble(), min: 2, max: 12, divisions: 10, label: '$_gridColumns', onChanged: (v) => setState(() => _gridColumns = v.round()))),
          Text('$_gridColumns', style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
        Row(children: [
          const Text('التباعد بين الأيقونات: '),
          Expanded(child: Slider(value: _gridSpacing, min: 2, max: 20, divisions: 9, label: '${_gridSpacing.round()}', onChanged: (v) => setState(() => _gridSpacing = v))),
          Text('${_gridSpacing.round()}', style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
        Row(children: [
          const Text('نسبة العرض/الارتفاع: '),
          Expanded(child: Slider(value: _gridAspectRatio, min: 0.5, max: 1.5, divisions: 10, label: _gridAspectRatio.toStringAsFixed(2), onChanged: (v) => setState(() => _gridAspectRatio = v))),
          Text(_gridAspectRatio.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
      ],
    );
  }


  Widget _buildReceiptSection() {
    return _buildSectionCard(
      title: 'إعدادات الإيصال',
      icon: PhosphorIconsBold.receipt,
      iconColor: AppColors.info,
      children: [
        SwitchListTile(
          title: const Text('طباعة تلقائية عند البيع'),
          subtitle: const Text('طباعة الإيصال تلقائياً بعد إتمام عملية البيع'),
          value: _autoPrint,
          onChanged: (v) => setState(() => _autoPrint = v),
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _receiptCodeType,
          decoration: const InputDecoration(
            labelText: 'نوع الكود في الإيصال',
            isDense: true,
          ),
          items: const [
            DropdownMenuItem(value: 'barcode', child: Text('باركود')),
            DropdownMenuItem(value: 'qr', child: Text('QR Code')),
            DropdownMenuItem(value: 'none', child: Text('بدون')),
          ],
          onChanged: (v) => setState(() => _receiptCodeType = v ?? 'barcode'),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _invoiceLanguage,
          decoration: const InputDecoration(
            labelText: 'لغة طباعة الفاتورة',
            isDense: true,
          ),
          items: const [
            DropdownMenuItem(value: 'ar', child: Text('العربية')),
            DropdownMenuItem(value: 'en', child: Text('English')),
          ],
          onChanged: (v) => setState(() => _invoiceLanguage = v ?? 'ar'),
        ),
        const SizedBox(height: 8),
        TextFormField(
          initialValue: _receiptFooter,
          decoration: const InputDecoration(
            labelText: 'تذييل الإيصال',
            hintText: 'نص يظهر أسفل الإيصال...',
            isDense: true,
          ),
          maxLines: 2,
          onChanged: (v) => _receiptFooter = v,
        ),
      ],
    );
  }

  Widget _buildTablePOSSection() {
    return _buildSectionCard(
      title: 'إعدادات نقطة بيع الطاولات', icon: PhosphorIconsBold.table, iconColor: AppColors.warning,
      children: [
        const Text('إعدادات تنظيم وتنسيق نقطة بيع الطاولات والصالة', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        const SizedBox(height: 12),

        // ─── واجهة العرض ───
        const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('واجهة العرض', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.warning))),
        SwitchListTile(title: const Text('إظهار حقل الباركود'), subtitle: const Text('إظهار أو إخفاء حقل مسح الباركود'), value: _tposShowBarcode, onChanged: (v) => setState(() => _tposShowBarcode = v), contentPadding: EdgeInsets.zero),
        SwitchListTile(title: const Text('إظهار صور الأصناف'), subtitle: const Text('إظهار أو إخفاء صور المنتجات في شبكة الطاولات'), value: _tposShowProductImages, onChanged: (v) => setState(() => _tposShowProductImages = v), contentPadding: EdgeInsets.zero),
        SwitchListTile(title: const Text('إظهار ترتيب الأصناف'), value: _tposShowProductSort, onChanged: (v) => setState(() => _tposShowProductSort = v), contentPadding: EdgeInsets.zero),
        const Divider(thickness: 2),

        // ─── أزرار الإجراءات ───
        const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('أزرار الإجراءات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.warning))),
        SwitchListTile(title: const Text('إظهار زر تحصيل الحساب'), subtitle: const Text('إظهار أو إخفاء زر تحصيل الحساب في سلة الطاولة'), value: _tposShowCheckout, onChanged: (v) => setState(() => _tposShowCheckout = v), contentPadding: EdgeInsets.zero),
        const Divider(thickness: 2),

        // ─── خطوط الأصناف ───
        const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('حجم خطوط الأصناف', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.warning))),
        Row(children: [
          const Text('حجم خط الاسم: '),
          Expanded(child: Slider(value: _tposNameFontSize, min: 10, max: 24, divisions: 14, label: '${_tposNameFontSize.round()}', onChanged: (v) => setState(() => _tposNameFontSize = v))),
          Text('${_tposNameFontSize.round()}', style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
        Row(children: [
          const Text('حجم خط السعر: '),
          Expanded(child: Slider(value: _tposPriceFontSize, min: 10, max: 24, divisions: 14, label: '${_tposPriceFontSize.round()}', onChanged: (v) => setState(() => _tposPriceFontSize = v))),
          Text('${_tposPriceFontSize.round()}', style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
      ],
    );
  }

  Widget _buildSectionCard({required String title, required IconData icon, required Color iconColor, required List<Widget> children}) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ]),
            const Divider(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Helper to show POS settings in a dialog
Future<void> showPosSettingsDialog(BuildContext context) {
  return showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Row(children: [
        Icon(PhosphorIconsBold.shoppingCart, color: AppColors.primary),
        SizedBox(width: 8),
        Text('إعدادات نقطة البيع'),
      ]),
      content: const SizedBox(width: 550, height: 650, child: PosSettingsWidget()),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق'))],
    ),
  );
}
