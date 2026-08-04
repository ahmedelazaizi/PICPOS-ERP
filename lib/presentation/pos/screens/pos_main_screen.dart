import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ural_erp/presentation/widgets/dialogs/app_confirm_dialog.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:ural_erp/core/widgets/app_toast.dart';
import '../../../core/theme/app_colors.dart';
import '../../../services/journal_entry_diagnostics.dart';
import '../../../data/providers/providers.dart';
import '../providers/pos_controller.dart';
import '../providers/cart_controller.dart';
import '../providers/checkout_controller.dart';
import '../providers/pos_notification_provider.dart';
import '../providers/pos_search_controller.dart';
import '../providers/cfd_controller.dart';

import '../../../domain/entities/product_entity.dart';
import '../../../domain/usecases/sales/add_to_cart_usecase.dart'
    show resolveStackingFlags;
import '../../screens/sales_returns_screen.dart';
import '../logic/pos_credential_handler.dart';

import '../widgets/pos_header.dart';
import '../widgets/pos_product_selection_panel.dart';
import '../widgets/pos_cart_panel.dart';
import '../widgets/pos_dialogs.dart' hide PaymentResult;
import '../widgets/held_orders_dialog.dart';
import '../widgets/pos_cashier_closing_dialog.dart';
import '../widgets/pos_previous_invoices_dialog.dart';
import '../widgets/pos_edit_invoice_dialog.dart';
import '../widgets/pos_previous_expenses_dialog.dart';
import '../widgets/pos_deleted_items_dialog.dart';
import '../widgets/pos_offers_dialog.dart';
import '../widgets/pos_customer_selection_dialog.dart';
import '../dialogs/unit_selection_dialog.dart';
import '../widgets/pos_opening_balance_dialog.dart';
import '../widgets/pos_cash_tendering_dialog.dart';
import '../dialogs/quick_add_product_dialog.dart';
import '../../../services/cash_drawer_service.dart';
import '../../../services/client_write_interceptor.dart';
import '../../../services/manager_approval_cache.dart';
import '../../../services/shift_dialog_session_guard.dart';
import '../../../core/logging/diagnostic_logger.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../widgets/permission_guard.dart' show requestManagerApproval;

// ── Part files (dialogs and operations) ────────────────────────────────
part 'pos_main_dialogs.dart';
part 'pos_main_operations.dart';

class PosScreenV2 extends ConsumerStatefulWidget {
  final bool showBackButton;
  final int? tableId;
  final String? tableName;

  const PosScreenV2({
    super.key,
    this.showBackButton = false,
    this.tableId,
    this.tableName,
  });

  @override
  ConsumerState<PosScreenV2> createState() => _PosScreenV2State();
}

class _PosScreenV2State extends ConsumerState<PosScreenV2>
    with PosCredentialHandler, _PosMainDialogsMixin, _PosMainOperationsMixin {
  final _barcodeController = TextEditingController();
  final _barcodeFocus = FocusNode();
  final _keyboardFocus = FocusNode();
  
  // -- Aggressive Focus Policy --
  Timer? _focusPersistenceTimer;

  // -- KDS Ready notification --
  int _lastKdsReadyCount = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _barcodeFocus.requestFocus();
      if (widget.tableId != null && widget.tableName != null) {
        ref.read(posControllerProvider.notifier)
           .initTableOrder(widget.tableId!, widget.tableName!);
      }
      _ensureShiftOpen();
      _startFocusPersistence();
    });
  }
  
  /// Continuously ensures focus returns to the scanner when idle.
  /// This prevents "dead" scanning after external popups or accidental clicks.
  void _startFocusPersistence() {
    _focusPersistenceTimer?.cancel();
    _focusPersistenceTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      // If no other field has focus (primaryFocus is null or just the RootFocusNode),
      // or if we're on the main screen and not interaction-heavy, re-request focus.
      final currentFocus = FocusScope.of(context).focusedChild;
      if (currentFocus == null || currentFocus == _keyboardFocus) {
         _barcodeFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _barcodeController.dispose();
    _barcodeFocus.dispose();
    _keyboardFocus.dispose();
    _focusPersistenceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _handleKdsNotifications();

    // Initialize CFD bridge — keeps cart state in sync with customer display
    ref.watch(cfdControllerProvider);

    final isGridCollapsed = ref.watch(posControllerProvider.select((s) => s.isGridCollapsed));
    final cartFlexRatio = ref.watch(posControllerProvider.select((s) => s.cartFlexRatio));
    final isProcessing = ref.watch(posControllerProvider.select((s) => s.isProcessing));
    
    final isRatioLocked = ref.watch(posCartRatioLockedProvider).value ?? false;
    final lockedRatioValue = ref.watch(posCartRatioValueProvider).value ?? 0.6;
    final effectiveRatio = isRatioLocked ? lockedRatioValue : cartFlexRatio;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: KeyboardListener(
        focusNode: _keyboardFocus,
        autofocus: true,
        onKeyEvent: _handlePhysicalKeyboard,
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: _handlePopInvoked,
          child: GestureDetector(
            onTap: () {
              // POS Priority: Always maintain focus on barcode scanner when tapping non-interactive areas
              if (!_barcodeFocus.hasFocus) {
                FocusScope.of(context).requestFocus(_barcodeFocus);
              }
            },
            behavior: HitTestBehavior.translucent,
            child: Stack(
              children: [
              Scaffold(
                backgroundColor: Theme.of(context).colorScheme.surface,
                body: Column(
                  children: [
                    PosHeader(
                      showBackButton: widget.showBackButton,
                      tableName: widget.tableName,
                      tableId: widget.tableId,
                      onShowOffers: _showOffersDialog,
                      onShowDelivery: _showDeliveryDialog,
                      onShowHeldOrders: _showHeldOrdersDialog,
                      onHoldOrder: _holdCurrentOrder,
                      onCashierClosing: _showCashierClosingDialog,
                      onViewReturns: _navigateToReturns,
                      onQuickReturn: () => ref.read(cartControllerProvider.notifier).convertToQuickReturn(),
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          if (!isGridCollapsed)
                            Expanded(
                              flex: ((1 - effectiveRatio) * 10).round(),
                              child: PosProductSelectionPanel(
                                barcodeController: _barcodeController,
                                barcodeFocus: _barcodeFocus,
                                onSearchBarcode: _searchBarcode,
                                onProductTap: _handleProductTap,
                              ),
                            ),
                          if (!isGridCollapsed && !isRatioLocked) _buildResizeHandle(),
                          Expanded(
                            flex: isGridCollapsed ? 12 : (effectiveRatio * 10).round(),
                            child: PosCartPanel(
                              posState: ref.read(posControllerProvider),
                              onCheckout: _showPaymentDialog,
                              onClearCart: () {
                                if (mounted) _barcodeFocus.requestFocus();
                              },
                              onEditItem: _showEditItemDialog,
                              onVReturns: _navigateToReturns,
                              onHoldOrder: _holdCurrentOrder,
                              onShowHeldOrders: _showHeldOrdersDialog,
                              getDrawerPrinterName: _getDrawerPrinterName,
                              onSave: _saveOrder,
                              onSaveQuotation: _saveAsQuotation,
                              onSaveAndPrint: _saveAndPrint,
                              onPreviousInvoices: _showPreviousInvoicesDialog,
                              onExpense: _showPreviousExpensesDialog,
                              onDeletedItems: _showDeletedItemsDialog,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (isProcessing) _buildProcessingOverlay(),
            ],
          ),
        ),
      ),
    ));
  }

  // ── Helper UI Builders ───────────────────────────────────────────────

  void _handleKdsNotifications() {
     final kdsReady = ref.watch(kdsReadyOrdersProvider);
     kdsReady.whenData((readyOrders) {
      if (_lastKdsReadyCount == -1) {
        _lastKdsReadyCount = readyOrders.length;
        return;
      }
      if (readyOrders.length > _lastKdsReadyCount && mounted) {
        final newest = readyOrders.first;
        SystemSound.play(SystemSoundType.alert);
        ScaffoldMessenger.of(context).showMaterialBanner(
            MaterialBanner(
              backgroundColor: AppColors.success.withValues(alpha: 0.95),
              leading: const Icon(PhosphorIconsBold.cookingPot, color: Colors.white, size: 28),
              content: Text('🍽️ الطلب ${newest.orderNumber} جاهز!', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              actions: [TextButton(onPressed: () => ScaffoldMessenger.of(context).clearMaterialBanners(), child: const Text('حسناً', style: TextStyle(color: Colors.white)))],
            ),
          );
        Future.delayed(const Duration(seconds: 8), () { if (mounted) ScaffoldMessenger.of(context).clearMaterialBanners(); });
      }
      _lastKdsReadyCount = readyOrders.length;
    });
  }

  void _handlePhysicalKeyboard(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.f12) {
      _saveAndPrint();
    } else if (key == LogicalKeyboardKey.f1) _barcodeFocus.requestFocus();
    else if (key == LogicalKeyboardKey.f2) _holdCurrentOrder();
    else if (key == LogicalKeyboardKey.f3) _showOffersDialog();
    else if (key == LogicalKeyboardKey.f4) _showCustomersDialog();
    else if (key == LogicalKeyboardKey.f5) _navigateToReturns();
    else if (key == LogicalKeyboardKey.f6) _showHeldOrdersDialog();
    else if (key == LogicalKeyboardKey.f7) _showPreviousExpensesDialog();
    else if (key == LogicalKeyboardKey.f8) _handleCheckout();
    else if (key == LogicalKeyboardKey.f9) _saveOrder();
    else if (key == LogicalKeyboardKey.f10) _showCashierClosingDialog();
    else if (key == LogicalKeyboardKey.f11) _showPreviousInvoicesDialog();
    else if (key == LogicalKeyboardKey.delete) { _confirmClearCartViaKey(); }
    else if (key == LogicalKeyboardKey.escape) { _barcodeFocus.requestFocus(); _barcodeController.clear(); }
  }

  // BUG-U04: the Delete key used to wipe the whole cart with no confirmation,
  // unlike the on-screen "مسح الكل" button. Route it through the same confirm.
  Future<void> _confirmClearCartViaKey() async {
    final cartState = ref.read(cartControllerProvider);
    if (cartState.items.isEmpty) return;
    final ok = await AppConfirmDialog.show(
      context,
      title: 'مسح السلة',
      message: 'هل أنت متأكد من مسح جميع المنتجات؟',
      confirmLabel: 'مسح',
      isDangerous: true,
    );
    if (!ok || !mounted) return;
    ref.read(cartControllerProvider.notifier).clearCart();
    _barcodeFocus.requestFocus();
  }

  Future<void> _handlePopInvoked(bool didPop, dynamic result) async {
    if (didPop) return;
    final cartState = ref.read(cartControllerProvider);
    if (cartState.items.isNotEmpty) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (ctx) => Directionality(
           textDirection: TextDirection.rtl,
           child: AlertDialog(
             title: const Text('تنبيه'),
             content: const Text('يوجد أصناف في السلة. هل تريد المتابعة بدون حفظ؟'),
             actions: [
               TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لا')),
               ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: AppColors.error), child: const Text('خروج وتجاهل')),
             ],
           ),
        ),
      ) ?? false;
      if (leave && mounted) Navigator.of(context).pop();
    } else {
      Navigator.of(context).pop();
    }
  }

  Widget _buildResizeHandle() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (details) {
        final delta = -details.delta.dx / MediaQuery.of(context).size.width;
        ref.read(posControllerProvider.notifier).adjustFlexRatio(delta);
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: Container(
          width: 20, decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, border: Border.symmetric(vertical: BorderSide(color: AppColors.border.withValues(alpha: 0.3)))),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            _buildRatioButton(0.3, '30%'), const SizedBox(height: 4),
            _buildRatioButton(0.4, '40%'), const SizedBox(height: 4),
            _buildRatioButton(0.5, '50%'), const SizedBox(height: 8),
            const Icon(PhosphorIconsBold.dotsThreeVertical, size: 16, color: AppColors.textMuted),
          ]),
        ),
      ),
    );
  }

  Widget _buildRatioButton(double ratio, String label) {
    final currentRatio = ref.watch(posControllerProvider).cartFlexRatio;
    final isActive = (currentRatio - ratio).abs() < 0.05;
    return InkWell(
      onTap: () => ref.read(posControllerProvider.notifier).setCartFlexRatio(ratio),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
        decoration: BoxDecoration(color: isActive ? AppColors.primary : Colors.transparent, borderRadius: BorderRadius.circular(3)),
        child: Text(label, style: TextStyle(fontSize: 8, fontWeight: isActive ? FontWeight.bold : FontWeight.normal, color: isActive ? Colors.white : AppColors.textMuted)),
      ),
    );
  }

  Widget _buildProcessingOverlay() {
    return Positioned.fill(
      child: Container(
        color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.4),
        child: Center(
          child: Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text('جاري المعالجة...', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  void _navigateToReturns() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const SalesReturnsScreen()));
  }

  Future<void> _showPaymentDialog() async {
    await _handleCheckout();
  }
}
