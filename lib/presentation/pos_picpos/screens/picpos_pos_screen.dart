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
import '../../pos/widgets/pos_previous_invoices_dialog.dart';
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
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 68, child: _buildMainColumn()),
                          const SizedBox(width: 6),
                          Expanded(
                            flex: 32,
                            child: PicPosSidePanel(operations: _operations()),
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

  Widget _buildMainColumn() {
    return Column(
      children: [
        PicPosInvoiceHeader(onPickCustomer: _pickCustomer),
        const SizedBox(height: 6),
        _buildScannerField(),
        const SizedBox(height: 6),
        Expanded(
          child: PicPosItemsTable(
            selectedIndex: selectedIndex,
            onSelect: (i) => setState(() => selectedIndex = i),
            onRemove: _removeAt,
          ),
        ),
        const SizedBox(height: 6),
        PicPosTotalsBar(
          onEditDiscount: _editInvoiceDiscount,
          onPreviousInvoices: _showPreviousInvoices,
        ),
      ],
    );
  }

  Widget _buildScannerField() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          const Icon(PhosphorIconsBold.barcode,
              size: 20, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: barcodeController,
              focusNode: barcodeFocus,
              autofocus: true,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'باركود أو كود الصنف…',
              ),
              onSubmitted: _searchBarcode,
            ),
          ),
        ],
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
