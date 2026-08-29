import 'package:flutter/material.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../picpos_shell/picpos_body_handle.dart';
import '../../picpos_shell/picpos_dialog.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../../settings_picpos/widgets/quick_sale_display_preview.dart';
import '../../settings_picpos/widgets/quick_sale_settings_chrome.dart';
import '../../../data/providers/providers.dart';
import '../../../core/config/app_config.dart';
import '../../../services/client_write_interceptor.dart';
import '../dialogs/app_confirm_dialog.dart';
// دفعة ١٠ — حارس settings_tax على حقل نسبة الضريبة الافتراضية.
import 'settings_permission_tiles.dart';
// Spec 135 NOTE 1 — the POS timeout UI now drives the single canonical
// session_timeout_minutes key (System A); invalidate its provider on save.
import '../../../services/session_timeout_service.dart' show sessionTimeoutProvider;
import '../../../domain/models/tax_rate_bounds.dart';

// ═══════════════════════════════════════════════════════════════════════════
// نسبةُ الضريبة الافتراضية — الرفضُ عند المصدر
// ═══════════════════════════════════════════════════════════════════════════
//
// `pos_default_tax_rate` هو منبعُ اللقطة التي تُثبَّت على كلِّ طلبِ طاولة.
// وv156 جعل «مفعَّلةٌ بصفر» مستحيلةَ التمثيل، وv157 شدَّ الحدَّ إلى ١٪ — لكنّ
// الرفضَ عند فتح الطاولة رسالةٌ تحيل المستخدمَ إلى هنا. فالرفضُ **هنا** أوضح.

/// يتحقّق من نسبةِ الضريبة كما يكتبها المستخدمُ — **مئويّةً** (16 لا 0.16).
///
/// يُعيد رسالةَ الرفض أو `null` إن قُبلت، على عقد `FormFieldValidator<String>`.
///
/// والفارغُ وغيرُ الرقمِ مرفوضان لا مُبتلَعان: `onChanged` تتجاهل ما لا
/// يُحلَّل، فتبقى الحالةُ على قيمتها القديمة والحقلُ يعرض شيئاً آخر — والرفضُ
/// يُظهر ذلك الافتراقَ بدل أن يُخفيه.
@visibleForTesting
String? validateDefaultTaxRatePercent(String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return 'أدخل نسبةَ الضريبة';

  final percent = double.tryParse(text);
  if (percent == null) return 'أدخل رقماً';

  if (!TaxRateBounds.isValidPercent(percent)) {
    return 'النسبةُ إمّا صفرٌ (بلا ضريبة) أو ١٪ فأكثر — ولا تتجاوز ١٠٠٪';
  }
  return null;
}

/// هل تُمنَع «حفظُ الإعدادات» بسبب نسبةِ الضريبة؟
///
/// **مقيَّدٌ بـ[touched] عن قصد.** الحقلُ لا يُخفى عند نقص الصلاحية —
/// `PermissionGuard` يقفله والقيمةُ تُحمَّل وتُرحَّل مع الحفظ. فمنعٌ مطلقٌ
/// يعني أن مستخدماً لا يملك `settings_tax`، وقيمةً قديمةً مخالفةً ورثها،
/// **يعجز عن حفظ كلِّ إعدادٍ آخر** بسبب حقلٍ لا يُسمح له بلمسه.
///
/// فيُرفَض ما يكتبه المستخدمُ الآن لا ما ورثه — والموروثُ يحرسه البابان
/// الآخران على مسار المال: `setOrderTax` وقيدُ الجدول.
///
/// و[rate] **كسريّةٌ** لا مئويّة: إرجاعُها بالضرب في مئة ينزلق في ٨ من كلِّ
/// ١٠٠ نسبةٍ صحيحة — اقرأ [TaxRateBounds.isValidRate].
@visibleForTesting
bool blocksSaveForTaxRate({required bool touched, required double rate}) =>
    touched && !TaxRateBounds.isValidRate(rate);

/// حقلُ النسبة داخل `Form` خاصٍّ به.
///
/// **الـ`Form` شرطٌ لا زينة:** `validator:` وحدَه لا يعمل — لا أحدَ يستدعي
/// `validate()`. وهو حول هذا الحقل وحدَه كي لا يُقحَم بقيّةُ الشاشة في دورة
/// تحقّقٍ لا تخصّها.
///
/// [initialRate] و[onRateChanged] **كسريّتان**، والمعروضُ والمكتوبُ مئويّ.
@visibleForTesting
Widget buildDefaultTaxRateFormField({
  required GlobalKey<FormState> formKey,
  required double initialRate,
  required ValueChanged<double> onRateChanged,
}) {
  return Form(
    key: formKey,
    child: TextFormField(
      initialValue: (initialRate * 100).toStringAsFixed(0),
      decoration: const InputDecoration(
        suffixText: '%',
        isDense: true,
      ),
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: validateDefaultTaxRatePercent,
      onChanged: (v) {
        final val = double.tryParse(v);
        if (val != null) {
          onRateChanged(val / 100);
        }
      },
    ),
  );
}

/// Standalone POS Settings Widget — extracted from Hardware Settings
class PosSettingsWidget extends ConsumerStatefulWidget {
  /// جسمٌ بلا زرِّ حفظٍ داخليّ — الزرُّ في تذييل `PicPosDialog`.
  final bool picposChrome;

  /// تسجّل فيه الحالةُ إجراءَ الحفظ ليبلغه زرُّ التذييل.
  final PicPosBodyHandle? saveHandle;

  const PosSettingsWidget({
    super.key,
    this.picposChrome = false,
    this.saveHandle,
  });
  @override
  ConsumerState<PosSettingsWidget> createState() => _PosSettingsWidgetState();
}

class _PosSettingsWidgetState extends ConsumerState<PosSettingsWidget> {
  bool _isLoading = true;

  /// القسمُ المعروضُ في تخطيط التصميم — فهرسٌ في [kQuickSaleSections].
  ///
  /// ⚠️ **يخصُّ غلافَ PicPos وحدَه.** لوحةُ UralCash تبقى تمريرةً واحدةً
  /// تعرض الأقسامَ الخمسةَ فوقَ بعضها، فلا يتبدّل شيءٌ لها.
  int _sectionIndex = 0;
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

  /// مفتاحُ الـ`Form` حول حقل النسبة — بلا استدعاءِ `validate()` لا يعمل
  /// المُتحقِّق.
  final GlobalKey<FormState> _taxRateFormKey = GlobalKey<FormState>();

  /// هل لمس المستخدمُ حقلَ النسبة في هذه الجلسة؟
  ///
  /// بوّابةُ الحفظ مقيَّدةٌ به كي لا تمنع قيمةٌ **موروثةٌ** مخالفةٌ حفظَ بقيّةِ
  /// الإعدادات — اقرأ [blocksSaveForTaxRate].
  bool _taxRateTouched = false;
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
    widget.saveHandle?.register(_saveSettings);
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

  /// يعرض تنزيل «البيع بالسالب» على كل الأصناف بعد تشغيل الإعداد العام.
  ///
  /// الإعداد العام لوحده كان بيسمح بالبيع لكن الواجهة في أماكن تفضل تقول
  /// «غير متوفر»، لأن `ProductEntity.isOutOfStock` و`product_list_tile`
  /// بيقروا علم الصنف بس ومش شايفين الإعداد العام. تنزيل القيمة على الأصناف
  /// بيوحّد كل القُرّاء.
  ///
  /// بيتأكد الأول: ده تعديل جماعي على كل صنف، ومش حاجة تحصل بضغطة مفتاح
  /// من غير ما المستخدم يعرف حجمها.
  Future<void> _offerNegativeSaleOnAllProducts() async {
    final ok = await AppConfirmDialog.show(
      context,
      title: 'تفعيل البيع بالسالب على كل الأصناف',
      message: 'الإعداد العام اتشغّل. تحب أفعّل «السماح بالبيع بالسالب» على '
          'كل الأصناف النشطة كمان؟\n\n'
          'من غير كده، بعض الشاشات هتفضل تعرض الصنف الناقص كـ«غير متوفر» '
          'رغم إن البيع مسموح.\n\n'
          'التفعيل الجماعي بيشغّل بس ولا بيقفل — أي صنف قافل البيع بالسالب '
          'يدوياً هيتشغّل، ومفيش حاجة هتتقفل.',
      confirmLabel: 'فعّل على كل الأصناف',
    );
    if (!ok || !mounted) return;

    final dao = ref.read(databaseProvider);
    final changed = await dao.enableNegativeSaleOnAllProducts();
    if (!mounted) return;

    // الأصناف بتتقري من providers مخزَّنة — من غير التبطيل ده الشاشات
    // تفضل معروضة بالقيم القديمة لحد ما حاجة تانية تبطّلها.
    ref.invalidate(allProductsProvider);

    AppToast.show(
      context,
      changed == 0
          ? 'كل الأصناف كانت مفعّلة أصلاً — مفيش تغيير'
          : 'اتفعّل البيع بالسالب على $changed صنف',
      type: ToastType.success,
    );
  }

  Future<void> _saveSettings() async {
    // ── نسبةُ الضريبة: الرفضُ عند المصدر ────────────────────────────────
    //
    // نقطةُ الحفظ واحدةٌ لكلِّ الإعدادات — المحليّةُ أدناه ومزامنةُ الخادم من
    // خريطةٍ في آخر هذه الدالّة — فبوّابةٌ هنا تغطّي المسارين معاً.
    //
    // ولو مُنع الحفظُ، أُطلق المُتحقِّقُ كي يظهر السببُ في الحقل نفسِه لا في
    // رسالةٍ عابرةٍ وحدَها.
    if (blocksSaveForTaxRate(
        touched: _taxRateTouched, rate: _posDefaultTaxRate)) {
      _taxRateFormKey.currentState?.validate();
      if (mounted) {
        AppToast.show(
          context,
          'نسبةُ الضريبة الافتراضية غير صالحة — صفرٌ (بلا ضريبة) أو ١٪ فأكثر',
          type: ToastType.error,
        );
      }
      return;
    }

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
      AppToast.show(context, 'تم حفظ إعدادات البيع السريع', type: ToastType.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    // في غلاف PicPos: لا زرَّ حفظٍ هنا ولا `Directionality` — الغلافُ يوفّر
    // الاثنين، وزرّان للحفظ في حوارٍ واحدٍ يربكان.
    //
    // والتخطيطُ يصير شريطاً جانبيّاً ولوحةً كما في التصميم بدل تمريرةٍ
    // واحدةٍ تُكدِّس الأقسامَ الخمسةَ — §٣ من بلاغ المالك 2026-08-29.
    // والعودةُ **قبل** بناء `sections` عمداً: ذاك يبني الأقسامَ الخمسةَ كلَّها
    // وتخطيطُ التصميم يعرض واحداً.
    if (widget.picposChrome) return _buildDesignLayout();

    final sections = SingleChildScrollView(
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
    );

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Column(
        children: [
          Expanded(child: sections),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity, height: 48,
            child: ElevatedButton(onPressed: _saveSettings, child: const Text('حفظ الإعدادات')),
          ),
        ],
      ),
    );
  }

  /// تخطيطُ التصميم — شريطُ أقسامٍ جانبيٌّ ولوحةٌ تعرض المختارَ وحدَه.
  ///
  /// ⚠️ **الشريطُ أوّلُ أبناء `Row` عمداً.** الغلافُ يوفّر `Directionality`
  /// من اليمين، فأوّلُ الأبناء يقع يميناً — وهو موضعُ الشريط في التصميم
  /// (`border-inline-end`). ولهذا الحدُّ `left` لا `right`: الطرفُ المنطقيُّ
  /// `inline-end` هو الأيسرُ فيزيائيّاً في واجهةٍ عربيّة.
  Widget _buildDesignLayout() {
    return LayoutBuilder(
      builder: (context, constraints) =>
          _buildDesignRow(showPreview: constraints.maxWidth >= _previewMinTotalWidth),
    );
  }

  Widget _buildDesignRow({required bool showPreview}) {
    final section = kQuickSaleSections[_sectionIndex];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 250,
          child: Container(
            decoration: BoxDecoration(
              color: context.picposField,
              border: Border(left: BorderSide(color: context.picposHairline)),
            ),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                  child: Text(
                    'أقسام الحوار',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: context.picposMuted,
                    ),
                  ),
                ),
                for (var i = 0; i < kQuickSaleSections.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: QuickSaleNavTile(
                      icon: kQuickSaleSections[i].icon,
                      tint: kQuickSaleSections[i].tint,
                      title: kQuickSaleSections[i].title,
                      settingCount: kQuickSaleSections[i].settingCount,
                      selected: i == _sectionIndex,
                      onTap: () => setState(() => _sectionIndex = i),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                QuickSaleSectionHeader(
                  icon: section.icon,
                  tint: section.tint,
                  title: section.title,
                  hint: section.hint,
                ),
                const SizedBox(height: 14),
                _sectionBody(_sectionIndex),
              ],
            ),
          ),
        ),
        // ⚠️ **لوحةُ المعاينة مشروطةٌ بالعرض لا دائمة.** التصميمُ يرسمها
        // ثالثةً على شاشةٍ عريضة، والحوارُ يُفتَح على أجهزةِ تِلٍّ ضيّقةٍ
        // أيضاً. وثلاثةُ أعمدةٍ ثابتةٍ على ٩٠٠px تسحق لوحةَ الإعدادات نفسَها
        // — فالمعاينةُ تُسقَط قبل أن تُضيَّق الإعدادات.
        if (showPreview)
          SizedBox(width: _previewPaneWidth, child: _buildPreviewPane()),
      ],
    );
  }

  /// عرضُ لوحةِ المعاينة — تُعرَض حين يتّسع الحوارُ لها وحدَها.
  static const double _previewPaneWidth = 360;

  /// أدنى عرضٍ يُبقي لوحةَ الإعدادات صالحةً بجوار المعاينة.
  static const double _previewMinTotalWidth = 1120;

  Widget _buildPreviewPane() {
    return Container(
      decoration: BoxDecoration(
        color: context.picposField,
        border: Border(right: BorderSide(color: context.picposHairline)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 20),
      child: SingleChildScrollView(
        child: QuickSaleDisplayPreview(
          showTopBar: _showTopBar,
          catIconSize: _catIconSize,
          catFontSize: _catFontSize,
          catSpacing: _catSpacing,
          catRunSpacing: _catRunSpacing,
          catLabelWidth: _catLabelWidth,
          catShape: _catShape,
          gridColumns: _gridColumns,
          gridSpacing: _gridSpacing,
          gridAspectRatio: _gridAspectRatio,
          nameFontSize: _productNameFontSize,
          priceFontSize: _productPriceFontSize,
          showProductImages: _showProductImagesInPOS,
        ),
      ),
    );
  }

  // لونُ كلِّ قسمٍ من [kQuickSaleSections] لا أرقاماً مكرّرة — مصدرٌ واحدٌ
  // للتصميم، فتغييرُ اللون هناك يسري على صفوفه هنا.
  Color get _mainTint => kQuickSaleSections[0].tint;
  Color get _catTint => kQuickSaleSections[1].tint;
  Color get _gridTint => kQuickSaleSections[2].tint;
  Color get _receiptTint => kQuickSaleSections[3].tint;
  Color get _tposTint => kQuickSaleSections[4].tint;

  // ═══════════════════════════════════════════════════════════════════════
  // صفوفُ الإعداد — نداءٌ واحدٌ يخدم العلامتَين
  // ═══════════════════════════════════════════════════════════════════════
  //
  // ⚠️ **لماذا الفرعُ داخلَ الصفِّ لا حولَ القسم.** تفريعُ كلِّ قسمٍ كان
  // يعني نسختَين من ٣٧ صفّاً في ملفٍّ واحد، وأوّلُ إصلاحٍ يدخل واحدةً
  // وينسى الأخرى. فالمُناداةُ واحدةٌ لكلِّ إعداد، والشكلُ وحدَه يتفرّع.
  //
  // و[legacyTitle] يحفظ نصَّ UralCash **حرفاً بحرف** حيث اختلف عن التصميم
  // (‏«حجم خط الاسم» مقابلَ «حجم الخط» مثلاً): العملُ على UralCash موقوفٌ،
  // فلا يصحُّ أن يبدّل هذا البندُ نصوصَها.

  /// ترويسةُ مجموعةٍ داخلَ القسم — شريطٌ ملوّنٌ رفيعٌ ثمّ الاسم.
  ///
  /// التصميمُ يفصل المجموعاتِ ببطاقاتٍ مستقلّة؛ وهنا تبقى بطاقةُ القسم
  /// واحدةً والمجموعاتُ تُفصَل بترويسةٍ بنفس المفردات البصريّة (شريطُ
  /// `3.5×15` بنصف قطر ٣). فرقٌ في التغليف لا في اللغة، ويُجنّب تفكيكَ
  /// خمسةِ بُناةٍ إلى بطاقاتٍ منفصلةٍ في هذا البند.
  Widget _groupHeader(String label, Color tint) {
    if (!widget.picposChrome) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(label,
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 14, color: tint)),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 6),
      child: Row(children: [
        Container(
          width: 3.5,
          height: 15,
          decoration: BoxDecoration(
            color: tint,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 10),
        Text(label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: context.picposText,
            )),
      ]),
    );
  }

  /// صفُّ مِزلاجٍ (‏`toggle` في التصميم).
  Widget _toggleRow({
    required IconData icon,
    required Color tint,
    required String title,
    required String settingKey,
    required bool value,
    required ValueChanged<bool> onChanged,
    String? sub,
    String? legacyTitle,
    bool isLast = false,
  }) {
    if (!widget.picposChrome) {
      // بلا `style` على العنوان الفرعيّ — النسخةُ القديمةُ تتركه لـ`ListTile`،
      // وأيُّ مقاسٍ هنا يبدّل مظهرَ UralCash.
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(legacyTitle ?? title),
        subtitle: sub == null ? null : Text(sub),
        value: value,
        onChanged: onChanged,
      );
    }
    return QuickSaleSettingRow(
      icon: icon,
      tint: tint,
      title: title,
      settingKey: settingKey,
      sub: sub,
      isLast: isLast,
      control: Switch(value: value, onChanged: onChanged),
    );
  }

  /// صفُّ مِنزلقٍ (‏`slider` في التصميم) — القيمةُ تُعرَض إلى جانبه.
  Widget _sliderRow({
    required IconData icon,
    required Color tint,
    required String title,
    required String settingKey,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    String? sub,
    String? legacyTitle,
    bool isLast = false,
    /// تنسيقُ القيمة المعروضة — `نسبة العرض/الارتفاع` كسريّةٌ بمنزلتَين لا
    /// صحيحة، فتقريبُها يخفي الفرقَ بين ٠٫٧٥ و٠٫٨٥.
    String Function(double)? format,

    /// تلميحُ المِنزلق حين يختلف عن القيمة المعروضة — «٥ دقيقة» في التلميح
    /// و«٥» بجانبه. تقريبُهما إلى صيغةٍ واحدةٍ يبدّل نصَّ UralCash.
    String Function(double)? labelFormat,
  }) {
    final shown = format ?? (v) => '${v.round()}';
    final tip = labelFormat ?? shown;
    final slider = Slider(
      value: value,
      min: min,
      max: max,
      divisions: divisions,
      label: tip(value),
      onChanged: onChanged,
    );

    if (!widget.picposChrome) {
      return Row(children: [
        Text('${legacyTitle ?? title}: '),
        Expanded(child: slider),
        Text(shown(value),
            style: const TextStyle(fontWeight: FontWeight.bold)),
      ]);
    }

    return QuickSaleSettingRow(
      icon: icon,
      tint: tint,
      title: title,
      settingKey: settingKey,
      sub: sub,
      isLast: isLast,
      control: SizedBox(
        width: 230,
        child: Row(children: [
          Expanded(child: slider),
          SizedBox(
            width: 44,
            child: Text(
              shown(value),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
                color: context.picposText,
              ),
            ),
          ),
        ]),
      ),
    );
  }

  /// صفُّ اختيارٍ من قائمة (‏`select` في التصميم).
  Widget _selectRow<T>({
    required IconData icon,
    required Color tint,
    required String title,
    required String settingKey,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    String? sub,
    String? legacyTitle,
    bool isLast = false,
  }) {
    final dropdown = DropdownButton<T>(
      value: value,
      underline: const SizedBox.shrink(),
      items: items,
      onChanged: onChanged,
    );

    if (!widget.picposChrome) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(legacyTitle ?? title),
        subtitle: sub == null ? null : Text(sub),
        trailing: dropdown,
      );
    }

    return QuickSaleSettingRow(
      icon: icon,
      tint: tint,
      title: title,
      settingKey: settingKey,
      sub: sub,
      isLast: isLast,
      control: dropdown,
    );
  }

  /// جسمُ القسمِ المختار — نفسُ بُناةِ UralCash بلا نسخ.
  Widget _sectionBody(int index) => switch (index) {
        0 => _buildMainPOSSection(),
        1 => _buildCategoryDisplaySection(),
        2 => _buildProductGridSection(),
        3 => _buildReceiptSection(),
        _ => _buildTablePOSSection(),
      };

  Widget _buildMainPOSSection() {
    return _buildSectionCard(
      title: 'إعدادات البيع السريع الرئيسية', icon: PhosphorIconsBold.shoppingCart, iconColor: AppColors.primary,
      children: [
        // ─── إعدادات الوردية والعرض ───
        _groupHeader('إعدادات الوردية والعرض', _mainTint),
        _toggleRow(
          icon: PhosphorIconsBold.clockCountdown,
          tint: _mainTint,
          title: 'إظهار ديالوج فتح الوردية',
          settingKey: 'pos_shift_dialog_enabled',
          sub: 'عند الإغلاق يتم فتح الوردية تلقائياً بدون سؤال',
          value: _posShiftDialogEnabled,
          onChanged: (v) => setState(() => _posShiftDialogEnabled = v),
        ),
        _toggleRow(
          icon: PhosphorIconsBold.layout,
          tint: kQuickSaleSections[0].tint,
          title: 'إظهار شريط التنقل العلوي',
          settingKey: 'app_show_top_bar',
          sub: 'إظهار أو إخفاء شريط التنبيهات والتنقل أعلى الشاشة',
          value: _showTopBar,
          onChanged: (v) => setState(() => _showTopBar = v),
        ),
        _selectRow<String>(
          icon: PhosphorIconsBold.bellRinging,
          tint: AppColors.warning,
          title: 'وضع تنبيهات المخزون',
          settingKey: 'pos_stock_alert_mode',
          sub: _posStockAlertMode == 'min_stock'
              ? 'تنبيه عند الوصول للحد الأدنى'
              : 'تنبيه فقط عند نفاد المخزون',
          value: _posStockAlertMode,
          items: const [
            DropdownMenuItem(value: 'zero', child: Text('نفاد المخزون فقط')),
            DropdownMenuItem(value: 'min_stock', child: Text('الحد الأدنى')),
          ],
          onChanged: (v) => setState(() => _posStockAlertMode = v ?? 'zero'),
        ),
        // Feature 022 (follow-up): expose the negative-sales toggle in
        // POS settings — that's where operators expect it. The same
        // setting key is read by sales_transaction_orchestrator on every
        // sale; defaults to false (block) on fresh installs and is
        // preserved as true on existing installs via the boot-time
        // backfill (Cluster 018).
        // ⚠️ الأيقونةُ تتبع الحالةَ: كهرمانيّةٌ حين يُسمح بالسالب وخضراءُ حين
        // يُمنع — إشارةُ خطرٍ لا زينة، فتُنقَل كما هي إلى صفِّ التصميم.
        widget.picposChrome
            ? _toggleRow(
                icon: PhosphorIconsBold.warning,
                tint: _enableNegativeSales
                    ? AppColors.warning
                    : AppColors.success,
                title: 'السماح بالبيع بالسالب عند نقص المخزون',
                settingKey: 'enable_negative_sales',
                sub: _enableNegativeSales
                    ? 'يمكن للكاشير بيع أصناف خارج المخزون — قد ينتج مخزون سالب.'
                    : 'يمنع البيع عند نفاد المخزون ويظهر تنبيه باللغة العربية.',
                value: _enableNegativeSales,
                onChanged: (v) async {
                  setState(() => _enableNegativeSales = v);
                  if (v) await _offerNegativeSaleOnAllProducts();
                },
              )
            : SwitchListTile(
          title: const Text('السماح بالبيع بالسالب عند نقص المخزون'),
          subtitle: Text(
            _enableNegativeSales
                ? 'يمكن للكاشير بيع أصناف خارج المخزون — قد ينتج مخزون سالب.'
                : 'يمنع البيع عند نفاد المخزون ويظهر تنبيه باللغة العربية.',
          ),
          value: _enableNegativeSales,
          onChanged: (v) async {
            setState(() => _enableNegativeSales = v);
            if (v) await _offerNegativeSaleOnAllProducts();
          },
          contentPadding: EdgeInsets.zero,
          secondary: Icon(
            PhosphorIconsBold.warning,
            color: _enableNegativeSales ? AppColors.warning : AppColors.success,
          ),
        ),
        buildDefaultTaxRateTileGuarded(
          field: buildDefaultTaxRateFormField(
            formKey: _taxRateFormKey,
            initialRate: _posDefaultTaxRate,
            onRateChanged: (rate) => setState(() {
              _posDefaultTaxRate = rate;
              _taxRateTouched = true;
            }),
          ),
        ),
        // ─── المخزن الافتراضي للبيع السريع ───
        FutureBuilder(
          // نطاقُ النسبة لا كلُّ المخازن: هذا المنتقي يقرّر أين تُخصم بضاعةُ
          // **كلِّ** بيعةٍ على الجهاز/الفرع، فمخزنُ فرعٍ آخرَ هنا يُخطئ نسبةَ
          // مبيعاتٍ كاملةٍ لا فاتورةً واحدة.
          future: ref.read(assignableWarehousesProvider(null).future),
          builder: (context, snapshot) {
            final warehouses = snapshot.data ?? [];
            if (warehouses.isEmpty) return const SizedBox.shrink();
            // والمنتقي الفرعيُّ أضيقُ من العامّ: مخازنُ هذا الفرعِ حصراً بلا
            // احتياطٍ يوسّع — «لا مخزنَ لهذا الفرع» جوابٌ صحيحٌ في شاشةِ
            // إعداداتٍ ولا يوقف عملاً، بخلافِ منتقي الفاتورة.
            final branchWarehouses = _currentBranchId == null
                ? warehouses
                : warehouses.where((w) => w.branchId == _currentBranchId).toList();
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
                      value: branchWarehouses.any((w) => w.id == _perBranchWarehouseId)
                          ? _perBranchWarehouseId : null,
                      underline: const SizedBox.shrink(),
                      hint: const Text('استخدم الإعداد العام'),
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('استخدم الإعداد العام')),
                        ...branchWarehouses.map((w) => DropdownMenuItem<int?>(value: w.id, child: Text(w.name ?? ''))),
                      ],
                      onChanged: (v) => setState(() => _perBranchWarehouseId = v),
                    ),
                  ),
                ListTile(
                  title: const Text('المخزن الافتراضي للبيع السريع (عام)'),
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
        if (!widget.picposChrome) const Divider(thickness: 2),

        // ─── أزرار الإجراءات السريعة والسلة ───
        _groupHeader('أزرار البيع السريع والسلة', _mainTint),
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
        if (!widget.picposChrome) const Divider(thickness: 2),

        // ─── إعدادات ترقيم المستندات ───
        _groupHeader('إعدادات ترقيم المستندات', _mainTint),
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
        if (!widget.picposChrome) const Divider(thickness: 2),

        // ─── واجهة العرض والتفاعل ───
        _groupHeader('واجهة العرض والتفاعل', _mainTint),
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
            // العنوان بيقول «أصناف الميزان» صراحةً لأن ده اللي الإعداد بيعمله
            // فعلاً: أصناف العدد والحبة بتتراكم دايماً مهما كان (شوف
            // `resolveStackingFlags`). العنوان القديم «منع تراكم الأصناف» كان
            // بيوعد بحاجة تانية خالص.
            FilterChip(
              label: const Text('منع تراكم أصناف الميزان (سطر لكل وزن)'),
              tooltip: 'كل وزنة ميزان تنزل في سطر مستقل بدل ما تتجمع. '
                  'أصناف العدد والحبة بتتراكم دايماً في سطر واحد.',
              selected: _preventItemStacking,
              onSelected: (v) => setState(() => _preventItemStacking = v),
            ),
          ],
        ),
        if (!widget.picposChrome) const Divider(thickness: 2),

        // ─── أيقونة الصنف وباقي الإعدادات ───
        _groupHeader('عرض المنتجات', _mainTint),
        _toggleRow(
          icon: PhosphorIconsBold.image,
          tint: AppColors.success,
          title: 'إظهار صور الأصناف',
          settingKey: 'pos_show_product_images',
          sub: 'إظهار أو إخفاء صور المنتجات في شبكة البيع السريع',
          value: _showProductImagesInPOS,
          onChanged: (v) => setState(() => _showProductImagesInPOS = v),
        ),
        _toggleRow(
          icon: PhosphorIconsBold.sortAscending,
          tint: AppColors.success,
          title: 'إظهار ترتيب الأصناف',
          settingKey: 'pos_show_product_sort',
          value: _showProductSortInPOS,
          onChanged: (v) => setState(() => _showProductSortInPOS = v),
        ),
        _toggleRow(
          icon: PhosphorIconsBold.columns,
          tint: AppColors.success,
          title: 'إظهار زر طي القائمة',
          settingKey: 'pos_show_layout_toggle',
          sub: 'إظهار أو إخفاء زر التحكم في أماكن عرض المنتجات',
          value: _showProductLayoutToggleInPOS,
          onChanged: (v) => setState(() => _showProductLayoutToggleInPOS = v),
        ),
        if (!widget.picposChrome) const SizedBox(height: 8),
        _sliderRow(
          icon: PhosphorIconsBold.textAa,
          tint: _mainTint,
          title: 'حجم خط الاسم',
          settingKey: 'pos_product_name_font_size',
          value: _productNameFontSize, min: 10, max: 24, divisions: 14,
          onChanged: (v) => setState(() => _productNameFontSize = v),
        ),
        _sliderRow(
          icon: PhosphorIconsBold.textT,
          tint: _mainTint,
          title: 'حجم خط السعر',
          settingKey: 'pos_product_price_font_size',
          value: _productPriceFontSize, min: 10, max: 24, divisions: 14,
          isLast: true,
          onChanged: (v) => setState(() => _productPriceFontSize = v),
        ),
        if (!widget.picposChrome) const Divider(thickness: 2),

        // ─── إعدادات السلة ───
        _groupHeader('إعدادات السلة', _mainTint),
        _toggleRow(
          icon: PhosphorIconsBold.lockKey,
          tint: AppColors.error,
          title: 'قفل نسبة عرض السلة',
          settingKey: 'pos_cart_ratio_locked',
          sub: 'منع الكاشير من تغيير حجم السلة',
          value: _posCartRatioLocked,
          isLast: !_posCartRatioLocked,
          onChanged: (v) => setState(() => _posCartRatioLocked = v),
        ),
        if (_posCartRatioLocked) ...[
          if (!widget.picposChrome) const SizedBox(height: 8),
          _sliderRow(
            icon: PhosphorIconsBold.columns,
            tint: _mainTint,
            title: 'نسبة عرض السلة',
            settingKey: 'pos_cart_ratio_value',
            sub: '٦٠٪ = عمود الأصناف ستون بالمئة والسلة أربعون',
            value: _posCartRatioValue, min: 0.3, max: 0.7, divisions: 8,
            format: (v) => '${(v * 100).round()}%',
            isLast: true,
            onChanged: (v) => setState(() => _posCartRatioValue = v),
          ),
        ],
        if (!widget.picposChrome) const Divider(thickness: 2),

        // ─── إعدادات الأمان ───
        _groupHeader('إعدادات الأمان والحماية', _mainTint),
        _toggleRow(
          icon: PhosphorIconsBold.timer,
          tint: AppColors.warning,
          title: 'مهلة انتهاء الجلسة',
          settingKey: 'pos_session_timeout_enabled',
          sub: 'تسجيل خروج تلقائي عند ترك النظام بدون نشاط (نفس إعداد الإعدادات العامة)',
          value: _posSessionTimeoutEnabled,
          isLast: !_posSessionTimeoutEnabled,
          onChanged: (v) => setState(() => _posSessionTimeoutEnabled = v),
        ),
        if (_posSessionTimeoutEnabled) ...[
          if (!widget.picposChrome) const SizedBox(height: 8),
          _sliderRow(
            icon: PhosphorIconsBold.hourglass,
            tint: AppColors.warning,
            title: 'مدة المهلة',
            legacyTitle: 'مدة الانتظار (دقائق)',
            settingKey: 'pos_session_timeout_minutes',
            sub: 'المفتاح الوحيد المعتمد — صفر يعني تعطيل',
            value: _posSessionTimeoutMinutes, min: 1, max: 60, divisions: 59,
            labelFormat: (v) => '${v.round()} دقيقة',
            isLast: true,
            onChanged: (v) => setState(() => _posSessionTimeoutMinutes = v),
          ),
        ],
      ],
    );
  }

  Widget _buildCategoryDisplaySection() {
    return _buildSectionCard(
      title: 'إعدادات منطقة التصنيفات', icon: PhosphorIconsBold.squaresFour, iconColor: AppColors.success,
      children: [
        // في تخطيط التصميم يحمل `QuickSaleSectionHeader` هذا الشرحَ، فتكرارُه
        // هنا سطرٌ ثانٍ بنفس المعنى.
        if (!widget.picposChrome) ...[
          const Text('تحكم في مظهر أيقونات التصنيفات أسفل منطقة المنتجات', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          const SizedBox(height: 12),
        ],
        _sliderRow(
          icon: PhosphorIconsBold.circle,
          tint: _catTint,
          title: 'حجم الأيقونة',
          settingKey: 'pos_category_icon_size',
          value: _catIconSize, min: 30, max: 80, divisions: 10,
          onChanged: (v) => setState(() => _catIconSize = v),
        ),
        _sliderRow(
          icon: PhosphorIconsBold.textAa,
          tint: _catTint,
          title: 'حجم الخط',
          legacyTitle: 'حجم خط الاسم',
          settingKey: 'pos_category_font_size',
          value: _catFontSize, min: 8, max: 18, divisions: 10,
          onChanged: (v) => setState(() => _catFontSize = v),
        ),
        _sliderRow(
          icon: PhosphorIconsBold.arrowsHorizontal,
          tint: _catTint,
          title: 'التباعد الأفقي',
          settingKey: 'pos_category_spacing',
          value: _catSpacing, min: 4, max: 24, divisions: 10,
          onChanged: (v) => setState(() => _catSpacing = v),
        ),
        _sliderRow(
          icon: PhosphorIconsBold.arrowsVertical,
          tint: _catTint,
          title: 'تباعد الأسطر',
          legacyTitle: 'التباعد الرأسي',
          settingKey: 'pos_category_run_spacing',
          value: _catRunSpacing, min: 4, max: 16, divisions: 6,
          onChanged: (v) => setState(() => _catRunSpacing = v),
        ),
        _sliderRow(
          icon: PhosphorIconsBold.textAlignCenter,
          tint: _catTint,
          title: 'عرض التسمية',
          legacyTitle: 'عرض نص التصنيف',
          settingKey: 'pos_category_label_width',
          value: _catLabelWidth, min: 40, max: 80, divisions: 8,
          onChanged: (v) => setState(() => _catLabelWidth = v),
        ),
        _sliderRow(
          icon: PhosphorIconsBold.arrowsOutLineVertical,
          tint: _catTint,
          title: 'أقصى ارتفاع للمنطقة',
          legacyTitle: 'ارتفاع المنطقة',
          settingKey: 'pos_category_max_height',
          sub: 'ما يزيد يُخفى — الأقسام لا تأكل الشبكة',
          value: _catMaxHeight, min: 80, max: 300, divisions: 11,
          onChanged: (v) => setState(() => _catMaxHeight = v),
        ),
        if (!widget.picposChrome) const SizedBox(height: 8),
        _selectRow<String>(
          icon: PhosphorIconsBold.shapes,
          tint: _catTint,
          title: 'شكل الأيقونة',
          settingKey: 'pos_category_shape',
          value: _catShape,
          isLast: true,
          items: const [
            DropdownMenuItem(value: 'circle', child: Text('دائري')),
            DropdownMenuItem(value: 'rounded', child: Text('مستطيل مدور')),
          ],
          onChanged: (v) => setState(() => _catShape = v ?? 'circle'),
        ),
      ],
    );
  }

  Widget _buildProductGridSection() {
    return _buildSectionCard(
      title: 'إعدادات شبكة المنتجات', icon: PhosphorIconsBold.gridFour, iconColor: AppColors.info,
      children: [
        if (!widget.picposChrome) ...[
          const Text('تحكم في عدد وتباعد أيقونات المنتجات في الشبكة', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          const SizedBox(height: 12),
        ],
        _sliderRow(
          icon: PhosphorIconsBold.columns,
          tint: _gridTint,
          title: 'عدد الأعمدة',
          settingKey: 'pos_grid_columns',
          sub: 'اثنا عشر عموداً على شاشة عشرة بوصات يجعل الاسم سطراً واحداً مقصوصاً',
          value: _gridColumns.toDouble(), min: 2, max: 12, divisions: 10,
          onChanged: (v) => setState(() => _gridColumns = v.round()),
        ),
        _sliderRow(
          icon: PhosphorIconsBold.dotsNine,
          tint: _gridTint,
          title: 'التباعد بين الأيقونات',
          settingKey: 'pos_grid_spacing',
          value: _gridSpacing, min: 2, max: 20, divisions: 9,
          onChanged: (v) => setState(() => _gridSpacing = v),
        ),
        _sliderRow(
          icon: PhosphorIconsBold.frameCorners,
          tint: _gridTint,
          title: 'نسبة العرض/الارتفاع',
          settingKey: 'pos_grid_aspect_ratio',
          sub: 'أقل من ١ يعني بطاقة أطول من عرضها',
          value: _gridAspectRatio, min: 0.5, max: 1.5, divisions: 10,
          format: (v) => v.toStringAsFixed(2),
          isLast: true,
          onChanged: (v) => setState(() => _gridAspectRatio = v),
        ),
      ],
    );
  }


  Widget _buildReceiptSection() {
    return _buildSectionCard(
      title: 'إعدادات الإيصال',
      icon: PhosphorIconsBold.receipt,
      iconColor: AppColors.info,
      children: [
        // ⚠️ **هذا القسمُ يتفرّع صراحةً لا عبر مساعِدات الصفوف.** ضوابطُه
        // `DropdownButtonFormField` و`TextFormField` بـ`labelText` — أي أنّ
        // التسميةَ **داخلَ** الضابط لا بجانبه. وصفُّ التصميم يضع التسميةَ
        // عنواناً والضابطَ بجواره، فتمريرُها عبر `_selectRow` كان يحوّل
        // ضوابطَ UralCash إلى شكلٍ آخر — والعملُ عليها موقوف.
        if (widget.picposChrome) ...[
          _toggleRow(
            icon: PhosphorIconsBold.printer,
            tint: _receiptTint,
            title: 'طباعة تلقائية عند البيع',
            settingKey: 'auto_print_receipt',
            sub: 'طباعة الإيصال تلقائياً بعد إتمام عملية البيع',
            value: _autoPrint,
            onChanged: (v) => setState(() => _autoPrint = v),
          ),
          _selectRow<String>(
            icon: PhosphorIconsBold.qrCode,
            tint: _receiptTint,
            title: 'نوع الكود في الإيصال',
            settingKey: 'receipt_code_type',
            value: _receiptCodeType,
            items: const [
              DropdownMenuItem(value: 'barcode', child: Text('باركود')),
              DropdownMenuItem(value: 'qr', child: Text('QR Code')),
              DropdownMenuItem(value: 'none', child: Text('بدون')),
            ],
            onChanged: (v) => setState(() => _receiptCodeType = v ?? 'barcode'),
          ),
          _selectRow<String>(
            icon: PhosphorIconsBold.translate,
            tint: _receiptTint,
            title: 'لغة طباعة الفاتورة',
            settingKey: 'invoice_language',
            sub: 'يبدّل عناوين الأعمدة والمسمّيات على الإيصال',
            value: _invoiceLanguage,
            items: const [
              DropdownMenuItem(value: 'ar', child: Text('العربية')),
              DropdownMenuItem(value: 'en', child: Text('English')),
            ],
            onChanged: (v) => setState(() => _invoiceLanguage = v ?? 'ar'),
          ),
          QuickSaleSettingRow(
            icon: PhosphorIconsBold.textAlignCenter,
            tint: _receiptTint,
            title: 'تذييل الإيصال',
            settingKey: 'receipt_footer',
            sub: 'سطران كحد أقصى على الحراري ٨٠مم',
            isLast: true,
            control: SizedBox(
              width: 260,
              child: TextFormField(
                initialValue: _receiptFooter,
                decoration: const InputDecoration(
                  hintText: 'نص يظهر أسفل الإيصال...',
                  isDense: true,
                ),
                maxLines: 2,
                onChanged: (v) => _receiptFooter = v,
              ),
            ),
          ),
        ] else ...[
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
      ],
    );
  }

  Widget _buildTablePOSSection() {
    return _buildSectionCard(
      title: 'إعدادات نقطة بيع الطاولات', icon: PhosphorIconsBold.table, iconColor: AppColors.warning,
      children: [
        if (!widget.picposChrome) ...[
          const Text('إعدادات تنظيم وتنسيق نقطة بيع الطاولات والصالة', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          const SizedBox(height: 12),
        ],
        // ─── واجهة العرض ───
        _groupHeader('واجهة العرض', _tposTint),
        _toggleRow(
          icon: PhosphorIconsBold.barcode,
          tint: _tposTint,
          title: 'إظهار حقل الباركود',
          settingKey: 'tpos_show_barcode',
          sub: 'إظهار أو إخفاء حقل مسح الباركود',
          value: _tposShowBarcode,
          onChanged: (v) => setState(() => _tposShowBarcode = v),
        ),
        _toggleRow(
          icon: PhosphorIconsBold.image,
          tint: _tposTint,
          title: 'إظهار صور الأصناف',
          settingKey: 'tpos_show_product_images',
          sub: 'إظهار أو إخفاء صور المنتجات في شبكة الطاولات',
          value: _tposShowProductImages,
          onChanged: (v) => setState(() => _tposShowProductImages = v),
        ),
        _toggleRow(
          icon: PhosphorIconsBold.sortAscending,
          tint: _tposTint,
          title: 'إظهار ترتيب الأصناف',
          settingKey: 'tpos_show_product_sort',
          value: _tposShowProductSort,
          onChanged: (v) => setState(() => _tposShowProductSort = v),
        ),
        if (!widget.picposChrome) const Divider(thickness: 2),
        // ─── أزرار الإجراءات ───
        _groupHeader('أزرار الإجراءات', _tposTint),
        _toggleRow(
          icon: PhosphorIconsBold.money,
          tint: _tposTint,
          title: 'إظهار زر تحصيل الحساب',
          settingKey: 'tpos_show_checkout',
          sub: 'إظهار أو إخفاء زر تحصيل الحساب في سلة الطاولة',
          value: _tposShowCheckout,
          onChanged: (v) => setState(() => _tposShowCheckout = v),
        ),
        if (!widget.picposChrome) const Divider(thickness: 2),
        // ─── خطوط الأصناف ───
        _groupHeader('حجم خطوط الأصناف', _tposTint),
        _sliderRow(
          icon: PhosphorIconsBold.textAa,
          tint: _tposTint,
          title: 'حجم خط الاسم',
          settingKey: 'tpos_name_font_size',
          value: _tposNameFontSize, min: 10, max: 24, divisions: 14,
          onChanged: (v) => setState(() => _tposNameFontSize = v),
        ),
        _sliderRow(
          icon: PhosphorIconsBold.textT,
          tint: _tposTint,
          title: 'حجم خط السعر',
          settingKey: 'tpos_price_font_size',
          value: _tposPriceFontSize, min: 10, max: 24, divisions: 14,
          isLast: true,
          onChanged: (v) => setState(() => _tposPriceFontSize = v),
        ),
      ],
    );
  }

  Widget _buildSectionCard({required String title, required IconData icon, required Color iconColor, required List<Widget> children}) {
    // في تخطيط التصميم: البطاقةُ إطارٌ بالشعرة بلا ظلٍّ، وترويستُها محذوفةٌ
    // لأنّ `QuickSaleSectionHeader` تعرض العنوانَ والأيقونةَ فوقها — وترويستان
    // بنفس النصّ في لوحةٍ واحدةٍ تكرارٌ يراه المستخدم.
    if (widget.picposChrome) {
      return Container(
        decoration: BoxDecoration(
          color: context.picposCard,
          border: Border.all(color: context.picposHairline),
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      );
    }

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
/// [picpos] `true` ⇒ لوحةُ `BENCH.quicksale` بغلاف `PicPosDialog`.
///
/// ⚠️ **والأقسامُ الخمسةُ تبقى كما هي عن قصد.** التصميمُ يرسم اللوحةَ
/// «طرقَ دفعٍ مؤشَّرة + خمسةَ صفوفِ سياسة»، وهذا **نموذجٌ لا تملكه الشاشة**:
/// أقسامُها الخمسةُ (‏الرئيسيّة · عرض الأقسام · شبكة الأصناف · الإيصال ·
/// بيعُ الطاولات) أوسعُ من طرق الدفع وحدَها، وطرقُ الدفع نفسُها تُدار من
/// `picpos_payment_methods.dart` في قسمٍ آخرَ من المركز. فإعادةُ رسمها هنا
/// تكرارٌ لواجهةٍ قائمةٍ لا تنسيق. الغلافُ وحدَه ما تبدّل.
Future<void> showPosSettingsDialog(BuildContext context,
    {bool picpos = false}) {
  if (picpos) {
    final handle = PicPosBodyHandle();
    return showDialog(
      context: context,
      builder: (_) => ValueListenableBuilder<bool>(
        valueListenable: handle.isReady,
        builder: (_, ready, _) => PicPosDialog(
          icon: PhosphorIconsBold.lightning,
          title: 'إعدادات البيع السريع',
          subtitle: 'ما يظهر للكاشير وما يُطبَع على الإيصال',
          width: 760,
          primaryAction: PicPosDialogAction(
            label: 'حفظ إعدادات البيع',
            icon: PhosphorIconsBold.check,
            onPressed: ready ? handle.invoke : null,
          ),
          body: [
            SizedBox(
              height: 600,
              child:
                  PosSettingsWidget(picposChrome: true, saveHandle: handle),
            ),
          ],
        ),
      ),
    ).whenComplete(handle.dispose);
  }
  return showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Row(children: [
        Icon(PhosphorIconsBold.shoppingCart, color: AppColors.primary),
        SizedBox(width: 8),
        Text('إعدادات البيع السريع'),
      ]),
      content: const SizedBox(width: 550, height: 650, child: PosSettingsWidget()),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق'))],
    ),
  );
}
