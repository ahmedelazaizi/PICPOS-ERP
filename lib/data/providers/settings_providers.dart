import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers.dart';

// ═══════════════════════════════════════════════════════════════════════════
// REPOSITORY PROVIDER
// ═══════════════════════════════════════════════════════════════════════════

// settingsRepositoryProvider moved to repository_providers.dart

// ═══════════════════════════════════════════════════════════════════════════
// UI & POS SETTINGS PROVIDERS
// ═══════════════════════════════════════════════════════════════════════════

/// Cluster 024 / Issue 2 — global negative-sales toggle. The orchestrator
/// already reads this for the auto-deplete shortage policy and the inventory
/// DAO ORs it into the per-product flag, but the POS UI guards
/// (cart_controller, product_card, pos_main_operations, accounting_validator)
/// were still gating on `product.allowNegativeSale` alone — so even with the
/// global ON, the operator couldn't add an out-of-stock item to the cart.
/// Surface the setting as a provider those guards can watch.
final enableNegativeSalesProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('enable_negative_sales');
  return value == 'true';
});

/// Show tax button in POS setting provider
final showTaxButtonInPOSProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('show_tax_button_pos');
  return value != 'false';
});

/// Show discount button in POS setting provider
final showDiscountButtonInPOSProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('show_discount_button_pos');
  return value != 'false';
});

/// Show cash drawer button in POS setting provider
final showDrawerButtonInPOSProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('show_drawer_button_pos');
  return value != 'false';
});

/// Show expenses button in POS setting provider
final showExpenseButtonInPOSProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('show_expense_button_pos');
  return value != 'false';
});

/// Receipt code type setting provider (barcode, qr_code, none)
final receiptCodeTypeProvider = FutureProvider<String>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('receipt_code_type');
  return value ?? 'barcode';
});

/// Show work order button in POS setting provider
final showWorkOrderButtonProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('show_work_order_button');
  return value == 'true';
});

/// Show delivery button in POS setting provider
final showDeliveryButtonProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('show_delivery_button');
  return value == 'true';
});

/// Show offers button in POS header toolbar
final showOffersButtonProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('show_offers_button_pos');
  return value != 'false'; // default true
});

/// Show keyboard button in POS header toolbar
final showKeyboardButtonProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('show_keyboard_button_pos');
  return value != 'false'; // default true
});

/// Invoice code prefix (e.g., 'INV-', 'POS-', user-defined)
final invoiceCodePrefixProvider = FutureProvider<String>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('invoice_code_prefix');
  return value ?? '';
});

/// Show returns button in POS cart header
final showReturnButtonInPOSProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('show_return_button_pos');
  return value != 'false';
});

/// Show hold/held orders buttons in POS cart header
final showHoldButtonInPOSProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('show_hold_button_pos');
  return value != 'false';
});

/// Show exchange button in POS cart header
final showExchangeButtonInPOSProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('show_exchange_button_pos');
  return value != 'false';
});

/// Phase 5: Prevent item stacking in POS (each tap = new line)
final preventItemStackingProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('pos_prevent_item_stacking');
  return value == 'true';
});


/// Show barcode input field in POS product grid
final showBarcodeInPOSProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('pos_show_barcode');
  return value != 'false';
});

/// Show Pricing Inquiry Popup Button in POS product grid
final showPricingInquiryInPOSProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('pos_show_pricing_inquiry');
  return value != 'false';
});

/// Show search in POS product grid
final showSearchInPOSProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('pos_show_search');
  return value != 'false';
});

/// Show save-only button (without print) in POS cart
final showSaveOnlyInPOSProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('pos_show_save_only');
  return value != 'false';
});

/// Show subtotal row in POS cart totals
final showSubtotalInPOSProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('pos_show_subtotal');
  return value != 'false';
});

/// Show add customer button in POS cart
final showAddCustomerInPOSProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('pos_show_add_customer');
  return value != 'false';
});

/// Show product sort/reorder button in POS product grid
final showProductSortInPOSProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('pos_show_product_sort');
  return value != 'false';
});

/// Show product layout toggle button in POS product grid
final showProductLayoutToggleInPOSProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('pos_show_layout_toggle');
  return value != 'false';
});

/// Show order type selector (داخلي/توصيل) in POS cart (default: true)
final showOrderTypeInPOSProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('pos_show_order_type');
  return value != 'false';
});

/// Show ad-hoc customer name/phone text fields in POS cart (default: true)
final showAdhocCustomerInPOSProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('pos_show_adhoc_customer');
  return value != 'false';
});

/// POS Session Timeout Enabled
final posSessionTimeoutEnabledProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('pos_session_timeout_enabled');
  return value != 'false'; // default true
});

/// POS Session Timeout Minutes
final posSessionTimeoutMinutesProvider = FutureProvider<int>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('pos_session_timeout_minutes');
  if (value != null) {
    return int.tryParse(value) ?? 5;
  }
  return 5;
});


/// Cart ratio locked by admin (prevents cashiers from resizing)
final posCartRatioLockedProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('pos_cart_ratio_locked');
  return value == 'true';
});

/// #3: Show product images in POS grid (default: true)
final showProductImagesProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('pos_show_product_images');
  return value != 'false';
});

/// Product card name font size (default: 12)
final productNameFontSizeProvider = FutureProvider<double>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('pos_product_name_font_size');
  if (value != null) {
    final parsed = double.tryParse(value);
    if (parsed != null && parsed >= 10 && parsed <= 24) return parsed;
  }
  return 12.0;
});

/// Product card price font size (default: 14)
final productPriceFontSizeProvider = FutureProvider<double>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('pos_product_price_font_size');
  if (value != null) {
    final parsed = double.tryParse(value);
    if (parsed != null && parsed >= 10 && parsed <= 24) return parsed;
  }
  return 14.0;
});

/// Cart ratio value (0.3 to 0.7, default 0.6)
final posCartRatioValueProvider = FutureProvider<double>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('pos_cart_ratio_value');
  if (value != null) {
    final parsed = double.tryParse(value);
    if (parsed != null && parsed >= 0.3 && parsed <= 0.7) return parsed;
  }
  return 0.6;
});

/// Show shift opening dialog on POS entry (default: true)
final posShiftDialogEnabledProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('pos_shift_dialog_enabled');
  return value != 'false'; // default true
});

/// Show top bar (breadcrumbs / notifications) (default: true)
final showTopBarProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('app_show_top_bar');
  return value != 'false'; // default true
});

/// Stock alert mode: 'min_stock' = show at min stock level, 'zero' = show only at zero (default: zero)
final posStockAlertModeProvider = FutureProvider<String>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('pos_stock_alert_mode');
  return value ?? 'zero';
});

/// Default tax rate for POS (default: 0.16)
final posDefaultTaxRateProvider = FutureProvider<double>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('pos_default_tax_rate');
  if (value != null) {
    return double.tryParse(value) ?? 0.16;
  }
  return 0.16;
});

/// Current industry mode provider (retail, supermarket, restaurant, cafe)
class IndustryModeNotifier extends Notifier<IndustryMode> {
  @override
  IndustryMode build() {
    _loadFromDb();
    return IndustryMode.supermarket;
  }

  Future<void> _loadFromDb() async {
    final repo = ref.read(settingsRepositoryProvider);
    final val = await repo.getSetting('industry_mode');
    if (val != null) {
      final mode = IndustryMode.values.firstWhere(
        (e) => e.name == val,
        orElse: () => IndustryMode.supermarket,
      );
      state = mode;
    }
  }

  void setMode(IndustryMode mode) {
    state = mode;
    ref.read(settingsRepositoryProvider).saveSetting('industry_mode', mode.name);
  }
}

final industryModeProvider =
    NotifierProvider<IndustryModeNotifier, IndustryMode>(() {
      return IndustryModeNotifier();
    });

// ═══════════════════════════════════════════════════════════════════════════
// POS BOTTOM PANEL SETTINGS
// ═══════════════════════════════════════════════════════════════════════════

/// Cart item text/row scale (0.7–1.3, default 1.0)
final posCartItemScaleProvider = FutureProvider<double>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('pos_cart_item_scale');
  final parsed = double.tryParse(value ?? '') ?? 1.0;
  return parsed.clamp(0.7, 1.3);
});

/// Bottom panel compact scale (0.7–1.0, default 1.0)
final posBottomPanelScaleProvider = FutureProvider<double>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('pos_bottom_panel_scale');
  final parsed = double.tryParse(value ?? '') ?? 1.0;
  return parsed.clamp(0.7, 1.0);
});

/// POS button height setting (default 40)
final posButtonHeightProvider = FutureProvider<double>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('pos_button_height');
  final parsed = double.tryParse(value ?? '') ?? 40.0;
  return parsed.clamp(30.0, 50.0);
});

/// POS button font size setting (default 13)
final posButtonFontSizeProvider = FutureProvider<double>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('pos_button_font_size');
  final parsed = double.tryParse(value ?? '') ?? 13.0;
  return parsed.clamp(10.0, 16.0);
});

// ═══════════════════════════════════════════════════════════════════════════
// PRINT LANGUAGE SETTING
// ═══════════════════════════════════════════════════════════════════════════

/// Print language setting: 'ar' (Arabic) or 'en' (English)
final printLanguageProvider = FutureProvider<String>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('print_language');
  return value ?? 'ar';
});

// ═══════════════════════════════════════════════════════════════════════════
// PAYMENT BUTTON SIZE SETTINGS
// ═══════════════════════════════════════════════════════════════════════════

/// Payment button width (default 100)
final paymentButtonWidthProvider = FutureProvider<double>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('pos_payment_button_width');
  final parsed = double.tryParse(value ?? '') ?? 100.0;
  return parsed.clamp(60.0, 200.0);
});


/// Payment button height (default 45)
final paymentButtonHeightProvider = FutureProvider<double>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('pos_payment_button_height');
  final parsed = double.tryParse(value ?? '') ?? 45.0;
  return parsed.clamp(30.0, 80.0);
});

// ═══════════════════════════════════════════════════════════════════════════
// POS SAFE MAPPING SETTINGS
// ═══════════════════════════════════════════════════════════════════════════

/// POS Cash Safe ID mapping.
///
/// Returns the explicitly-configured cash safe ID, or `null` if no setting
/// has been saved yet.  A `null` result tells [_recordSalesReceipt] to use
/// branch-aware safe resolution (warehouse → branch → system-wide default)
/// instead of forcing every transaction to safe #1 (the old hardcoded fallback).
final posCashSafeIdProvider = FutureProvider<int?>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('pos_cash_safe_id');
  return int.tryParse(value ?? ''); // null when no explicit setting exists
});

/// POS Bank/Visa Safe ID mapping
final posBankSafeIdProvider = FutureProvider<int?>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('pos_bank_safe_id');
  return int.tryParse(value ?? '');
});

/// POS Click Safe ID mapping
final posClickSafeIdProvider = FutureProvider<int?>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('pos_click_safe_id');
  return int.tryParse(value ?? '');
});

// ═══════════════════════════════════════════════════════════════════════════
// POS CATEGORY DISPLAY SETTINGS
// ═══════════════════════════════════════════════════════════════════════════

/// Category icon size (30-80, default: 44)
final posCategoryIconSizeProvider = FutureProvider<double>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('pos_category_icon_size');
  final parsed = double.tryParse(value ?? '') ?? 44.0;
  return parsed.clamp(30.0, 80.0);
});

/// Category label font size (8-18, default: 9)
final posCategoryFontSizeProvider = FutureProvider<double>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('pos_category_font_size');
  final parsed = double.tryParse(value ?? '') ?? 9.0;
  return parsed.clamp(8.0, 18.0);
});

/// Category horizontal spacing (4-24, default: 12)
final posCategorySpacingProvider = FutureProvider<double>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('pos_category_spacing');
  final parsed = double.tryParse(value ?? '') ?? 12.0;
  return parsed.clamp(4.0, 24.0);
});

/// Category vertical run-spacing (4-16, default: 8)
final posCategoryRunSpacingProvider = FutureProvider<double>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('pos_category_run_spacing');
  final parsed = double.tryParse(value ?? '') ?? 8.0;
  return parsed.clamp(4.0, 16.0);
});

/// Category label width (40-80, default: 52)
final posCategoryLabelWidthProvider = FutureProvider<double>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('pos_category_label_width');
  final parsed = double.tryParse(value ?? '') ?? 52.0;
  return parsed.clamp(40.0, 80.0);
});

/// Category icon shape: 'circle' or 'rounded' (default: circle)
final posCategoryShapeProvider = FutureProvider<String>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('pos_category_shape');
  return value ?? 'circle';
});

/// Category area max height (80-300, default: 200)
final posCategoryMaxHeightProvider = FutureProvider<double>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('pos_category_max_height');
  final parsed = double.tryParse(value ?? '') ?? 200.0;
  return parsed.clamp(80.0, 300.0);
});

// ═══════════════════════════════════════════════════════════════════════════
// POS PRODUCT GRID DISPLAY SETTINGS
// ═══════════════════════════════════════════════════════════════════════════

/// Product grid columns per row (2-12, default: 8)
final posGridColumnsProvider = FutureProvider<int>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('pos_grid_columns');
  final parsed = int.tryParse(value ?? '') ?? 8;
  return parsed.clamp(2, 12);
});

/// Product grid spacing between items (2-20, default: 8)
final posGridSpacingProvider = FutureProvider<double>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('pos_grid_spacing');
  final parsed = double.tryParse(value ?? '') ?? 8.0;
  return parsed.clamp(2.0, 20.0);
});

/// Product grid aspect ratio (0.5-1.5, default: 0.75)
final posGridAspectRatioProvider = FutureProvider<double>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue('pos_grid_aspect_ratio');
  final parsed = double.tryParse(value ?? '') ?? 0.75;
  return parsed.clamp(0.5, 1.5);
});
