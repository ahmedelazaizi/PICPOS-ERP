import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/logging/diagnostic_logger.dart';
import '../../../core/utils/number_utils.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/entities/cart_item_entity.dart';
import '../../../domain/entities/product_entity.dart';
import '../../../services/cash_drawer_service.dart';
import '../../../services/journal_entry_diagnostics.dart';
import '../../widgets/dialogs/app_confirm_dialog.dart';
import '../../pos/providers/cart_controller.dart';
import '../../pos/providers/checkout_controller.dart';
import '../../pos/providers/pos_controller.dart';
import '../../pos/providers/pos_notification_provider.dart';
import '../../pos/providers/pos_search_controller.dart';
import '../../pos/widgets/held_orders_dialog.dart';
import '../../pos/widgets/pos_customer_selection_dialog.dart';
import '../../pos/widgets/pos_dialogs.dart' hide PaymentResult;
import '../../pos/widgets/pos_previous_expenses_dialog.dart';
import '../../pos/widgets/pos_previous_invoices_dialog.dart';
import '../../pos/widgets/pos_product_selection_panel.dart';
import '../widgets/picpos_display_settings.dart';
import '../widgets/picpos_payment_panel.dart';
import '../widgets/picpos_invoice_header.dart';
import '../widgets/picpos_items_table.dart';
import '../widgets/picpos_shortcut_bar.dart';
import '../widgets/picpos_side_panel.dart';
import '../widgets/picpos_top_bar.dart';
import '../widgets/picpos_totals_bar.dart';

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
    });
  }

  @override
  void dispose() {
    barcodeController.dispose();
    barcodeFocus.dispose();
    _keyboardFocus.dispose();
    super.dispose();
  }

  /// The bottom strip from the product-owner's design. Deliberately a
  /// DIFFERENT map from the UralCash screen's F1–F12 — that screen's keys are
  /// muscle memory for existing UralCash cashiers and are not ours to move;
  /// these are what the PicPos design puts on screen, and the labels and the
  /// handler are built from this one list so they cannot disagree.
  List<PicPosShortcut> _shortcuts() => [
        PicPosShortcut(
          label: 'دفع',
          keyLabel: 'F4',
          onPressed: _handleCheckout,
          color: AppColors.success,
        ),
        PicPosShortcut(
          label: 'حفظ',
          keyLabel: 'F2',
          onPressed: () => _saveInvoice(printAfter: false),
        ),
        PicPosShortcut(
          label: 'طباعة',
          keyLabel: 'F3',
          onPressed: () => _saveInvoice(printAfter: true),
        ),
        PicPosShortcut(
          label: 'تعديل',
          keyLabel: 'F6',
          onPressed: _editSelected,
        ),
        PicPosShortcut(
          label: 'حذف',
          keyLabel: 'F8',
          onPressed: _deleteSelected,
          color: AppColors.warning,
        ),
        PicPosShortcut(
          label: 'إلغاء',
          keyLabel: 'ESC',
          onPressed: _cancelInvoice,
          color: AppColors.error,
        ),
      ];

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.f2) {
      _saveInvoice(printAfter: false);
    } else if (key == LogicalKeyboardKey.f3) {
      _saveInvoice(printAfter: true);
    } else if (key == LogicalKeyboardKey.f4) {
      _handleCheckout();
    } else if (key == LogicalKeyboardKey.f6) {
      _editSelected();
    } else if (key == LogicalKeyboardKey.f8) {
      _deleteSelected();
    } else if (key == LogicalKeyboardKey.escape) {
      _cancelInvoice();
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _moveSelection(1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _moveSelection(-1);
    }
  }

  void _moveSelection(int delta) {
    final count = ref.read(cartControllerProvider).items.length;
    if (count == 0) return;
    setState(() {
      final current = selectedIndex ?? (delta > 0 ? -1 : count);
      selectedIndex = (current + delta).clamp(0, count - 1);
    });
  }

  List<PicPosOperation> _operations() => [
        PicPosOperation(
          label: 'تعليق',
          icon: PhosphorIconsBold.pauseCircle,
          onPressed: _holdOrder,
        ),
        PicPosOperation(
          label: 'فواتير معلقة',
          icon: PhosphorIconsBold.listChecks,
          onPressed: _showHeldOrders,
        ),
        PicPosOperation(
          label: 'فواتير سابقة',
          icon: PhosphorIconsBold.receipt,
          onPressed: _showPreviousInvoices,
        ),
        PicPosOperation(
          label: 'العميل',
          icon: PhosphorIconsBold.user,
          onPressed: _pickCustomer,
        ),
        PicPosOperation(
          label: 'خصم',
          icon: PhosphorIconsBold.percent,
          onPressed: _editInvoiceDiscount,
        ),
        PicPosOperation(
          label: 'فتح الدرج',
          icon: PhosphorIconsBold.money,
          onPressed: _openDrawer,
        ),
      ];

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
                    onHeldOrders: _showHeldOrders,
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
                  PicPosShortcutBar(shortcuts: _shortcuts()),
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
        color: AppColors.card,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(PhosphorIconsBold.arrowsHorizontal,
              size: 13, color: AppColors.textMuted),
          const SizedBox(width: 5),
          if (locked)
            const Expanded(
              child: Text(
                'عرض المنطقة مقفول من الإعدادات',
                style: TextStyle(fontSize: 10, color: AppColors.textMuted),
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
              color: AppColors.border,
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
        color: AppColors.card,
        border: Border.all(color: AppColors.border),
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
    return Column(
      children: [
        PicPosInvoiceHeader(onPickCustomer: _pickCustomer),
        const SizedBox(height: 4),
        _buildSizeControls(),
        const SizedBox(height: 4),
        Expanded(
          child: PicPosItemsTable(
            selectedIndex: selectedIndex,
            onSelect: (i) => setState(() => selectedIndex = i),
            onRemove: _removeAt,
          ),
        ),
        const SizedBox(height: 6),
        // المجاميع + طرق الدفع + أزرار الأفعال — نسخة PicPos من لوحة UralCash،
        // بتحترم إعدادات إظهار الأزرار والمقاسات في «إعدادات نقطة البيع».
        // شريط العمليات المنفصل اتشال: «فواتير» و«الدرج» و«خصم» و«العميل»
        // كانوا ظاهرين مرتين — مرة في اللوحة ومرة تحتها. التعليق والفواتير
        // المعلقة انضموا للوحة بدل ما يعيشوا في شريط لوحدهم.
        PicPosPaymentPanel(
          onCheckout: _handleCheckout,
          onSave: () => _saveInvoice(printAfter: false),
          onSaveAndPrint: () => _saveInvoice(printAfter: true),
          onEditDiscount: _editInvoiceDiscount,
          onPickCustomer: _pickCustomer,
          onPreviousInvoices: _showPreviousInvoices,
          onOpenDrawer: _openDrawer,
          onExpense: _showExpenses,
          onHold: _holdOrder,
          onHeldOrders: _showHeldOrders,
        ),
      ],
    );
  }

  /// Operations strip. Scrolls horizontally rather than wrapping — the
  /// invoice column is the narrow one, and a wrapping button grid would eat
  /// rows from the line table every time one more operation is added.
  Widget _buildOperationsRow() {
    return Container(
      height: 58,
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        itemCount: _operations().length,
        separatorBuilder: (context, i) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final op = _operations()[i];
          return SizedBox(
            width: 88,
            child: OutlinedButton(
              onPressed: op.onPressed,
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                side: const BorderSide(color: AppColors.border),
                foregroundColor: AppColors.primaryDark,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(op.icon, size: 17),
                  const SizedBox(height: 2),
                  Text(
                    op.label,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          );
        },
      ),
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
              color: active ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: active ? Colors.white : AppColors.textMuted,
            ),
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
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(PhosphorIconsBold.trash, size: 13, color: AppColors.error),
              SizedBox(width: 4),
              Text(
                'مسح الكل',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.error,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}