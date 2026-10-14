import 'package:ural_erp/core/i18n/tr.dart';
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
import '../../../services/session_timeout_service.dart'
    show sessionTimeoutProvider;
import '../../../domain/models/tax_rate_bounds.dart';

part 'pos_settings_widget_tax.dart';
part 'pos_settings_widget_storage.dart';
part 'pos_settings_widget_design.dart';
part 'pos_settings_widget_main_section.dart';
part 'pos_settings_widget_other_sections.dart';

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
  bool _pricesIncludeTax = false;

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
      child: Column(
        children: [
          _buildMainPOSSection(),
          const SizedBox(height: 16),
          _buildCategoryDisplaySection(),
          const SizedBox(height: 16),
          _buildProductGridSection(),
          const SizedBox(height: 16),
          _buildReceiptSection(),
          const SizedBox(height: 16),
          _buildTablePOSSection(),
        ],
      ),
    );

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Column(
        children: [
          Expanded(child: sections),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _saveSettings,
              child: Text(tr('حفظ الإعدادات')),
            ),
          ),
        ],
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
Future<void> showPosSettingsDialog(
  BuildContext context, {
  bool picpos = false,
}) {
  if (picpos) {
    final handle = PicPosBodyHandle();
    return showDialog(
      context: context,
      builder: (_) => ValueListenableBuilder<bool>(
        valueListenable: handle.isReady,
        builder: (_, ready, _) => PicPosDialog(
          icon: PhosphorIconsBold.lightning,
          title: tr('إعدادات البيع السريع'),
          subtitle: tr('ما يظهر للكاشير وما يُطبَع على الإيصال'),
          width: 760,
          primaryAction: PicPosDialogAction(
            label: tr('حفظ إعدادات البيع'),
            icon: PhosphorIconsBold.check,
            onPressed: ready ? handle.invoke : null,
          ),
          body: [
            SizedBox(
              height: 600,
              child: PosSettingsWidget(picposChrome: true, saveHandle: handle),
            ),
          ],
        ),
      ),
    ).whenComplete(handle.dispose);
  }
  return showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Row(
        children: [
          const Icon(PhosphorIconsBold.shoppingCart, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(tr('إعدادات البيع السريع')),
        ],
      ),
      content: const SizedBox(
        width: 550,
        height: 650,
        child: PosSettingsWidget(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('إغلاق')),
        ),
      ],
    ),
  );
}
