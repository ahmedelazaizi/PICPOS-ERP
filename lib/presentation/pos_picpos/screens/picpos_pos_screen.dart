import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../picpos_shell/picpos_surface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/logging/diagnostic_logger.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../core/utils/number_utils.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../../services/client_write_interceptor.dart';
import '../../../services/manager_approval_cache.dart';
import '../../../services/shift_dialog_session_guard.dart';
import '../../widgets/permission_guard.dart'
    show requestManagerApproval, ensurePermission;
import '../../pos/widgets/pos_opening_balance_dialog.dart';
import '../../../domain/entities/cart_item_entity.dart';
import '../../../domain/entities/product_entity.dart';
import '../widgets/picpos_payment_methods.dart';
import '../widgets/picpos_shift_conflict_dialog.dart';
import '../../../domain/models/shift_open_gate.dart';
import '../../../services/delta_pull_service.dart';
import '../../../services/network_service.dart';
import '../../shift_close_picpos/screens/shift_close_picpos_screen.dart';
import '../../../domain/usecases/sales/add_to_cart_usecase.dart'
    show resolveStackingFlags;
import '../../../services/cash_drawer_service.dart';
import '../../../services/journal_entry_diagnostics.dart';
import '../../widgets/dialogs/app_confirm_dialog.dart';
import '../../pos/providers/cart_controller.dart';
import '../../pos/providers/checkout_controller.dart';
import '../../pos/providers/pos_controller.dart';
import '../../pos/providers/pos_notification_provider.dart';
import '../../pos/providers/pos_search_controller.dart';
import '../../pos/services/scale_barcode_handler.dart';
import '../../pos/dialogs/quick_add_product_dialog.dart';
import '../../pos/dialogs/unit_selection_dialog.dart';
import '../../pos/widgets/held_orders_dialog.dart';
import '../../pos/widgets/pos_cash_tendering_dialog.dart';
import '../../pos/widgets/pos_customer_selection_dialog.dart';
import '../../pos/widgets/pos_dialogs.dart' hide PaymentResult;
import '../../pos/widgets/pos_edit_invoice_dialog.dart';
import '../../pos/widgets/pos_previous_expenses_dialog.dart';
import '../../pos/widgets/pos_previous_invoices_dialog.dart';
import '../../pos/widgets/pos_product_selection_panel.dart';
import '../../shift_close_picpos/widgets/picpos_cashier_closing_dialog.dart';
import '../widgets/picpos_display_settings.dart';
import '../widgets/picpos_payment_panel.dart';
import '../widgets/picpos_invoice_header.dart';
import '../widgets/picpos_items_table.dart';
import '../widgets/picpos_last_invoice_dialog.dart';
import '../widgets/picpos_numeric_keypad_dialog.dart';
import '../widgets/picpos_cart_permissions.dart';
import '../widgets/picpos_pos_shortcuts.dart';
import '../widgets/picpos_pos_text.dart';
import '../widgets/picpos_return_mode_banner.dart';
import '../widgets/picpos_switch_user_dialog.dart';
import '../widgets/picpos_top_bar.dart';
import '../providers/pos_return_mode_provider.dart';
import '../providers/pos_exchange_mode_provider.dart';
import '../state/pos_return_mode.dart';
import '../state/pos_exchange_mode.dart';
import '../widgets/picpos_exchange_mode_banner.dart';
import '../../../domain/models/exchange_settlement.dart';
// `ExchangeResult` — نتيجةُ الاستبدال بأرقامِ الدرج المقيسة. مستودعٌ لا قاعدة:
// حارسُ `presentation_db_import_guard` يمنع `data/database` وحدَه.
import '../../../data/repositories/exchange_repository_impl.dart';
import '../../../domain/models/returnable_line.dart';
import '../../shared_widgets/open_shift_prompt.dart';
import '../../../core/navigation/screen_id.dart';
import '../../bookings_picpos/screens/bookings_picpos_screen.dart';

part 'picpos_pos_operations.dart';

/// PicPos point-of-sale screen.
///
/// Selected by BRAND, not by profile — see `app_main_screen.dart`. The layout
/// is the one the product owner specified: invoice header, line table and
/// totals down the main column; display board and operations down the side;
/// keyboard shortcuts along the bottom.
///
/// It shares the engine completely: `cart_controller`, `checkout_controller`,
/// `pos_search_controller` and every dialog are the same objects the UralCash
/// screen uses. Nothing about pricing, stock or accounting is re-implemented
/// here — this class owns layout and key handling, and that is all.
class PicPosPosScreen extends ConsumerStatefulWidget {
  final bool showBackButton;

  const PicPosPosScreen({super.key, this.showBackButton = false});

  @override
  ConsumerState<PicPosPosScreen> createState() => _PicPosPosScreenState();
}

class _PicPosPosScreenState extends ConsumerState<PicPosPosScreen>
    with _PicPosOperations {
  @override
  final TextEditingController barcodeController = TextEditingController();
  @override
  final FocusNode barcodeFocus = FocusNode();

  final FocusNode _keyboardFocus = FocusNode();

  @override
  int? selectedIndex;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      barcodeFocus.requestFocus();
      unawaited(DiagnosticLogger.log('PICPOS-POS', 'screen mounted'));
      // Parity with UralCash PosScreenV2.initState: prompt the cashier to open
      // a shift (opening balance) on landing if none is open. Shares the
      // session guard with MainScreen._enforceShiftForCashier so it never
      // double-prompts. Was missing from this fork → PicPos cashiers/managers
      // never saw the open-shift dialog.
      _ensureShiftOpen();
    });
  }

  @override
  void dispose() {
    barcodeController.dispose();
    barcodeFocus.dispose();
    _keyboardFocus.dispose();
    super.dispose();
  }

  /// خريطة مفاتيح الشاشة — الأفعال. التسميات في [picposShortcutLabels].
  ///
  /// ── ليه خريطة ومش سلسلة `if/else` ─────────────────────────────────────
  /// كان فيه قائمة تسميات (`_shortcuts()`) للشريط السفلي وسلسلة `if/else`
  /// للمعالج، والتعليق القديم كان بيوعد إنهم من مصدر واحد فما يختلفوش. الشريط
  /// اتشال (طلب ٤) فالوعد ده مات — والـ `assert` تحت هو اللي بيحرسه بدلاً منه:
  /// مفتاح يتضاف هنا ويُنسى في التوثيق (أو العكس) بيفشل صريح في أول ضغطة زر
  /// في الديباج، مش بيبقى اختصار ميت بصمت في الإنتاج.
  Map<LogicalKeyboardKey, VoidCallback> _keyActions() {
    final actions = <LogicalKeyboardKey, VoidCallback>{
      LogicalKeyboardKey.f2: _saveOnly,
      LogicalKeyboardKey.f3: _showLastInvoice,
      LogicalKeyboardKey.f4: _handleCheckout,
      LogicalKeyboardKey.f6: _editSelected,
      LogicalKeyboardKey.f8: _deleteSelected,
      LogicalKeyboardKey.escape: _cancelInvoice,
      LogicalKeyboardKey.arrowDown: () => _moveSelection(1),
      LogicalKeyboardKey.arrowUp: () => _moveSelection(-1),
    };
    assert(
      actions.length == picposShortcutLabels.length &&
          actions.keys.every(picposShortcutLabels.containsKey),
      'اختصارات البيع السريع اختلفت عن توثيقها: '
      'أفعال=${actions.keys} توثيق=${picposShortcutLabels.keys}. '
      'حدِّث picpos_pos_shortcuts.dart مع أي تغيير هنا.',
    );
    return actions;
  }

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    _keyActions()[event.logicalKey]?.call();
  }

  void _moveSelection(int delta) {
    final count = ref.read(cartControllerProvider).items.length;
    if (count == 0) return;
    setState(() {
      final current = selectedIndex ?? (delta > 0 ? -1 : count);
      selectedIndex = (current + delta).clamp(0, count - 1);
    });
  }

  /// عرض عمود الفاتورة كنسبة من الشاشة. القيمة الافتراضية **0.4** — الشبكة
  /// هي النص الأوسع.
  ///
  /// ── ليه حالة محلية ومش `posController.cartFlexRatio`؟ ─────────────────
  /// قرأت `cartFlexRatio` مباشرة في أول تنفيذ، وطلعت الفاتورة ٦٠٪ والشبكة
  /// ٤٠٪ — بالظبط عكس المطلوب. السبب إن `PosState.cartFlexRatio` افتراضيها
  /// `0.6` وهي في شاشة UralCash معناها «**السلة** ٦٠٪»، ومفيش طريقة أفرّق
  /// بيها بين «المستخدم اختار 0.6» و«ده الافتراضي»، فمقدرتش أعيد تفسيرها.
  ///
  /// ── ولا بنزرع من `pos_cart_ratio_value` كمان ─────────────────────────
  /// المحاولة التانية زرعت منه، والفاتورة رجعت ٦٠٪ تاني: المفتاح ده كمان
  /// افتراضيه `0.6` بنفس دلالة UralCash («**السلة** ٦٠٪»). المفتاحان
  /// الاتنين بيحملوا نفس المعنى المعكوس عن اللي محتاجينه هنا.
  ///
  /// فالقاعدة بقت: **غير مقفولة** → نبدأ من 0.4 والسحب هو المصدر.
  /// **مقفولة** → قيمة الإعداد هي المصدر، لأن المدير ساعتها ضبطها بنفسه
  /// وهو شايف النتيجة، فدلالتها بقت اللي هو قصده.
  double _invoiceRatio = 0.4;


  double get invoiceRatio {
    final locked = ref.watch(posCartRatioLockedProvider).value ?? false;
    if (locked) {
      return (ref.watch(posCartRatioValueProvider).value ?? 0.4)
          .clamp(0.25, 0.65);
    }
    return _invoiceRatio;
  }

  @override
  Widget build(BuildContext context) {
    final isProcessing =
        ref.watch(posControllerProvider.select((s) => s.isProcessing));
    // وضعُ المرتجع (جولةُ إصلاح ٢ — مانعٌ ١): تعطيلُ زرّ «الفواتير المعلّقة»
    // في الشريط العلويّ بصرياً، فوق حراسة `_showHeldOrders` نفسِها. راجع
    // تعليقَ `PicPosTopBar.onHeldOrders`.
    // ووضعُ الاستبدال يعطّله كذلك: `_showHeldOrders` **يحذف الطلبَ المعلَّق
    // من القاعدة** عند استرجاعه، فتركُه مفتوحاً أثناء استبدالٍ قائمٍ يُبيد
    // طلباً معلَّقاً نهائياً مقابل سلّةٍ لن تُحفَظ بيعاً عاديّاً.
    final returnModeActive = ref.watch(posReturnModeProvider) != null ||
        ref.watch(posExchangeModeProvider) != null;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: KeyboardListener(
        focusNode: _keyboardFocus,
        autofocus: true,
        onKeyEvent: _handleKey,
        child: Stack(
          children: [
            Scaffold(
              backgroundColor: AppColors.posBackground,
              body: Column(
                children: [
                  PicPosTopBar(
                    showBackButton: widget.showBackButton,
                    onBack: () => Navigator.of(context).maybePop(),
                    onHeldOrders: returnModeActive ? null : _showHeldOrders,
                    // Task 10B — يسدّ فجوة إن كاشير PicPos ما عندوش أي طريقة
                    // يقفل الوردية. الفعل نفسه (10C يبدّله للمعاد تصميمه)؛
                    // حارس الصلاحية يعيش داخل `PicPosTopBar` نفسها.
                    onCloseShift: () => PicposCashierClosingDialog.show(context),
                    onSwitchUser: _switchUser,
                    // ⚠️ **مشروطٌ بنطاق الملفّ لا معروضٌ دائماً**: تنصيبةُ
                    // سوبرماركت لا تحجز مواعيد، وزرٌّ يفتح شاشةً خارجَ
                    // نطاقها يقود إلى فراغ. والنطاقُ هو نفسُ المصدر الذي
                    // تُبنى منه القائمةُ الجانبيّة، فلا يفترق الاثنان.
                    onBookings: ref
                            .watch(userAllowedScreensProvider)
                            .value
                            ?.contains(ScreenId.bookings.navigationIndex) ??
                            false
                        ? _openBookings
                        : null,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      // RTL: the first child renders on the RIGHT. Browsing is
                      // the wide half and the invoice is the narrow one — same
                      // split as the UralCash till, so a cashier moving between
                      // the two products isn't relearning where things live.
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: ((1 - invoiceRatio) * 100).round(),
                            child: _buildBrowsePanel(),
                          ),
                          _buildResizeHandle(),
                          Expanded(
                            flex: (invoiceRatio * 100).round(),
                            child: _buildInvoiceColumn(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // ── الشريط السفلي اتشال (طلب ٤) ──────────────────────────
                  // كان `PicPosShortcutBar` هنا بياكل ٤٠ بكسل ثابتة من كل
                  // شاشة. الـ F-keys شغالة زي ما هي من `_keyActions()` —
                  // الشريط كان عرضاً للاختصارات لا مصدراً لها.
                ],
              ),
            ),
            if (isProcessing) _buildProcessingOverlay(),
          ],
        ),
      ),
    );
  }

  /// شريط تحكم فوري أعلى السلة: عرض منطقة السلة والدفع + كثافة الجدول.
  ///
  /// السحب من الفاصل موجود، لكنه تقدير بالعين. النسب الجاهزة بتوصل لعرض
  /// معروف بضغطة — نفس فكرة أزرار `30% / 40% / 50%` في مقبض شاشة UralCash.
  ///
  /// بيختفي كله لما `pos_cart_ratio_locked` يبقى مشغّل: المدير قافل العرض،
  /// فأزرار بتغيّره تبقى وعد كذّاب.
  Widget _buildSizeControls() {
    final locked = ref.watch(posCartRatioLockedProvider).value ?? false;

    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border.all(color: context.picposHairline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(PhosphorIconsBold.arrowsHorizontal,
              size: 13, color: AppColors.textMuted),
          const SizedBox(width: 5),
          if (locked)
            Expanded(
              child: Text(
                'عرض المنطقة مقفول من الإعدادات',
                style: PicPosText.l(10),
              ),
            )
          else
            for (final r in const [0.30, 0.40, 0.50, 0.60])
              _MiniToggle(
                label: '${(r * 100).round()}٪',
                active: (_invoiceRatio - r).abs() < 0.02,
                onTap: () => setState(() => _invoiceRatio = r),
              ),
          const Spacer(),
          // شارة «بيع بالسالب»: تظهر فقط لما السماح مفتوح فعلاً، وبتديه مخرج
          // بضغطة. المسارين الاتنين (الضغط على الكارت ومسح الباركود) بيفتحوا
          // السماح من نفس السؤال اللحظي — الشارة هي اللي بتخلّي الكاشير عارف
          // إنه لسه مفتوح، عشان ما ينساهوش شغّال على فاتورة مش محتاجاه.
          const _OversellBadge(),
          // الترس: نفس حوار «إعدادات عرض السلة» بتاع UralCash — خمس سلايدرات
          // بتكتب على نفس مفاتيح الإعدادات، فتحكم دائم مش لحظي.
          const PicPosDisplaySettingsButton(),
          const SizedBox(width: 5),
          _ClearCartButton(onClear: _cancelInvoice),
        ],
      ),
    );
  }

  /// Divider between the two halves. Drag it to trade grid space for invoice
  /// space; the ratio persists via `posController.setCartFlexRatio`.
  ///
  /// Collapses to a plain gap when `pos_cart_ratio_locked` is on — an admin
  /// who pinned the split does not want a cashier's stray drag to move it, and
  /// a handle that silently does nothing is worse than no handle.
  Widget _buildResizeHandle() {
    final locked = ref.watch(posCartRatioLockedProvider).value ?? false;
    if (locked) return const SizedBox(width: 6);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (details) {
        // RTL: the invoice column is on the LEFT, so dragging left (negative
        // dx) must GROW it.
        final delta = -details.delta.dx / MediaQuery.of(context).size.width;
        setState(() {
          _invoiceRatio = (_invoiceRatio + delta).clamp(0.25, 0.65);
        });
      },
      onDoubleTap: () => setState(() => _invoiceRatio = 0.4),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: Container(
          width: 12,
          margin: const EdgeInsets.symmetric(vertical: 2),
          alignment: Alignment.center,
          child: Container(
            width: 4,
            decoration: BoxDecoration(
              color: context.picposHairline,
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Center(
              child: Icon(PhosphorIconsBold.dotsSixVertical,
                  size: 11, color: AppColors.textMuted),
            ),
          ),
        ),
      ),
    );
  }

  /// Browsing half — barcode field, category filter and the product grid.
  ///
  /// This is `PosProductSelectionPanel`, the exact component the UralCash till
  /// and the table-service screen use. Reusing it rather than rebuilding a
  /// grid means the category rules (locked / excluded / `showInPos`), the
  /// branch-scoped product query, the scale input and the permission guards
  /// are the same code in every till we ship — one place to fix, one
  /// behaviour to learn.
  Widget _buildBrowsePanel() {
    return Container(
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border.all(color: context.picposHairline),
      ),
      child: PosProductSelectionPanel(
        barcodeController: barcodeController,
        barcodeFocus: barcodeFocus,
        onSearchBarcode: _searchBarcode,
        onProductTap: _handleProductTap,
      ),
    );
  }

  /// Invoice half — header, lines, totals and the operation buttons.
  Widget _buildInvoiceColumn() {
    // وضعُ المرتجع (المهمّة ٧): الترويسةُ الحمراءُ تظهر فوق كلِّ شيءٍ في هذا
    // العمود طالما `posReturnModeProvider` غيرُ `null` — نفسُ الشرط الذي
    // يحكم مسارَ الحفظ في `_processPaymentAndSave`. `_returnInvoiceNumber`
    // نصٌّ محليٌّ يُضبط مع الوضع نفسِه في `_showQuickReturn` (`PosReturnMode`
    // خالصةٌ ولا تحمل رقمَ الفاتورة، رأى مواصفةَ الملفّ).
    final returnMode = ref.watch(posReturnModeProvider);

    // الأرقامُ الثلاثةُ للاستبدال: المرتجعُ من الوضع، والبديلُ من سلّة البيع
    // نفسِها (هي سلّةُ البديل)، والفرقُ من `settleExchange` عبر
    // `previewSettlement` — **لا يُشتقّ هنا بطرح**، وإلّا صار حاسبٌ ثانٍ
    // يفترق عن المنفَّذ عند أوّل تقريب.
    final exchangeMode = ref.watch(posExchangeModeProvider);
    final replacementTotal =
        ref.watch(cartControllerProvider.select((s) => s.total));

    return Column(
      children: [
        if (returnMode != null)
          PicPosReturnModeBanner(
            invoiceNumber: _returnInvoiceNumber ?? '#${returnMode.invoiceId}',
          ),
        if (exchangeMode != null)
          Builder(
            builder: (_) {
              final preview = exchangeMode.previewSettlement(
                  replacementTotal: replacementTotal);
              return PicPosExchangeModeBanner(
                invoiceNumber:
                    _exchangeInvoiceNumber ?? '#${exchangeMode.invoiceId}',
                refundTotal: exchangeMode.refundTotal,
                replacementTotal: replacementTotal,
                direction: preview.direction,
                difference: preview.amount,
              );
            },
          ),
        PicPosInvoiceHeader(
          onPickCustomer: _pickCustomer,
          onShowLastInvoice: _showLastInvoice,
        ),
        const SizedBox(height: 4),
        _buildSizeControls(),
        const SizedBox(height: 4),
        Expanded(
          child: PicPosItemsTable(
            selectedIndex: selectedIndex,
            onSelect: (i) => setState(() => selectedIndex = i),
            onRemove: _removeAt,
            // الكيبورد الرقمي ديالوج، وقفله بيسيب الفوكس معلّق. الباركود سكانر
            // جهاز كيبورد، فبدون الرجوع ده أول مسحة بعد تعديل كمية كانت تروح
            // في العدم.
            onEditComplete: _refocusScanner,
          ),
        ),
        const SizedBox(height: 6),
        // المجاميع + طرق الدفع + أزرار الأفعال — نسخة PicPos من لوحة UralCash،
        // بتحترم إعدادات إظهار الأزرار والمقاسات في «إعدادات البيع السريع».
        // شريط العمليات المنفصل اتشال: «فواتير» و«الدرج» و«خصم» و«العميل»
        // كانوا ظاهرين مرتين — مرة في اللوحة ومرة تحتها. التعليق والفواتير
        // المعلقة انضموا للوحة بدل ما يعيشوا في شريط لوحدهم.
        PicPosPaymentPanel(
          onCheckout: _handleCheckout,
          onSave: _saveOnly,
          onLastInvoice: _showLastInvoice,
          onEditDiscount: _editInvoiceDiscount,
          onPickCustomer: _pickCustomer,
          onPreviousInvoices: _showPreviousInvoices,
          onOpenDrawer: _openDrawer,
          onExpense: _showExpenses,
          onHold: _holdOrder,
          onHeldOrders: _showHeldOrders,
          onQuickReturn: _showQuickReturn,
          onExchange: _showExchange,
        ),
      ],
    );
  }

  Widget _buildProcessingOverlay() {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.35),
        child: const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('جاري المعالجة...'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// شارة «بيع بالسالب مسموح» — بتظهر فقط لما `CartState.allowOversell` مفتوح.
///
/// ── ليه بتظهر وتختفي بدل ما تكون سويتش دائم ──────────────────────────────
/// السماح ده حالة **استثنائية** عمرها فاتورة واحدة. سويتش دائم في الشريط كان
/// معناه إن الكاشير يفتحه مرة وينساه مفتوح، وساعتها الرفض اللي بيحمي المخزون
/// ما بيشتغلش تاني — وهو بالظبط اللي المسار القديم («اضغط آجل الأول») كان
/// بيعمله بلا قصد.
///
/// فبتظهر بس بعد ما السماح يُفتح فعلاً، بلون تحذير، وقابلة للضغط عشان يُقفل.
/// و`clearCart` بيصفّر السماح، فالشارة بتختفي لوحدها مع كل فاتورة جديدة.
class _OversellBadge extends ConsumerWidget {
  const _OversellBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowed = ref
        .watch(cartControllerProvider.select((s) => s.allowOversell));
    if (!allowed) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(left: 5),
      child: Tooltip(
        message: 'مسموح بيع أصناف غير متوفرة في هذه الفاتورة — اضغط للإلغاء',
        child: InkWell(
          onTap: () =>
              ref.read(cartControllerProvider.notifier).setAllowOversell(false),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border:
                  Border.all(color: AppColors.warning.withValues(alpha: 0.45)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(PhosphorIconsBold.warningDiamond,
                    size: 12, color: AppColors.warning),
                const SizedBox(width: 4),
                Text('بيع بالسالب',
                    style: PicPosText.v(10, color: AppColors.warning)),
                const SizedBox(width: 3),
                const Icon(PhosphorIconsBold.x,
                    size: 9, color: AppColors.warning),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// زرار صغير جداً لشريط التحكم — بلا حشو زائد عشان الشريط يفضل ٣٠ بكسل.
class _MiniToggle extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback? onTap;

  const _MiniToggle({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.35 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: active ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: active ? AppColors.primary : context.picposHairline,
            ),
          ),
          child: Text(
            label,
            style: active
                ? PicPosText.v(10, color: Colors.white)
                : PicPosText.l(10),
          ),
        ),
      ),
    );
  }
}

/// «مسح الكل» أعلى السلة — بيتعطّل لما السلة فاضية بدل ما يفتح تأكيد
/// على مفيش حاجة.
class _ClearCartButton extends ConsumerWidget {
  final VoidCallback onClear;

  const _ClearCartButton({required this.onClear});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isEmpty =
        ref.watch(cartControllerProvider.select((s) => s.items.isEmpty));
    return Opacity(
      opacity: isEmpty ? 0.35 : 1,
      child: InkWell(
        onTap: isEmpty ? null : onClear,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                  PhosphorIconsBold.trash, size: 13, color: AppColors.error),
              const SizedBox(width: 4),
              Text(
                'مسح الكل',
                style: PicPosText.v(10, color: AppColors.error),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
