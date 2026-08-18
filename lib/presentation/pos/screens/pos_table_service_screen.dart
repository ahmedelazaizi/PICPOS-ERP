import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/entities/product_entity.dart';
import '../../../domain/entities/cart_item_entity.dart';
import '../../../domain/models/table_charge_check.dart';
import '../providers/pos_controller.dart';
import '../providers/cart_controller.dart';
import '../providers/checkout_controller.dart';
import '../providers/pos_search_controller.dart';
import '../providers/pos_notification_provider.dart';
import '../widgets/pos_product_selection_panel.dart';
import '../widgets/payment_sheet.dart';
import '../widgets/pos_dialogs.dart' hide PaymentResult;
import '../widgets/modifier_selection_dialog.dart';
import '../widgets/table_pos/table_pos_header.dart';
import '../widgets/table_pos/table_pos_cart_panel.dart';
import '../widgets/table_pos/table_pos_summary.dart';
import '../dialogs/quick_add_product_dialog.dart';
// `TableSettleStatus` / `TableSettleOutcome` — نتيجةُ حلقةِ حجز→ترحيل→تثبيت.
import '../../../services/table_checkout_coordinator.dart';

// ── Part files (logic and operations) ──────────────────────────────────
part 'table_pos_dialogs.dart';
part 'table_pos_operations.dart';

class TablePosScreen extends ConsumerStatefulWidget {
  final int tableId;
  final String tableName;

  const TablePosScreen({
    super.key,
    required this.tableId,
    required this.tableName,
  });

  @override
  ConsumerState<TablePosScreen> createState() => _TablePosScreenState();
}

class _TablePosScreenState extends ConsumerState<TablePosScreen>
    with _TablePosOperationsMixin, _TablePosDialogsMixin {
  
  @override
  void initState() {
    super.initState();
    _initOperations();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      barcodeFocus.requestFocus();
      // Load existing table order items into cart
      ref.read(posControllerProvider.notifier)
         .initTableOrder(widget.tableId, widget.tableName);
      // Auto-select first category
      _autoSelectFirstCategory();
    });
  }

  @override
  void dispose() {
    _disposeOperations();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isProcessing = ref.watch(posControllerProvider.select((s) => s.isProcessing));

    return Directionality(
      textDirection: TextDirection.rtl,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          await _handleBack();
        },
        child: Stack(
          children: [
            Scaffold(
              backgroundColor: const Color(0xFF080E1E),
              body: Column(
                children: [
                  TablePosHeader(
                    tableName: widget.tableName,
                    onBack: _handleBack,
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        // Left — Product Selection
                        Expanded(
                          flex: 6,
                          child: PosProductSelectionPanel(
                            barcodeController: barcodeController,
                            barcodeFocus: barcodeFocus,
                            onSearchBarcode: _searchBarcode,
                            onProductTap: _handleProductTap,
                          ),
                        ),
                        // Right — Modular Cart
                        SizedBox(
                          width: 380,
                          child: Column(
                            children: [
                              Expanded(
                                child: TablePosCartPanel(
                                  onUpdateQuantity: (idx, qty) => ref.read(cartControllerProvider.notifier).updateQuantity(idx, qty),
                                  onRemove: (idx) => ref.read(cartControllerProvider.notifier).removeFromCart(idx),
                                  onAddNote: (idx) async {
                                    if (!await ensurePosNoteAddPermission(ref, context)) return;
                                    await _showNoteDialog(idx, ref.read(cartControllerProvider).items[idx]);
                                  },
                                ),
                              ),
                              TablePosSummary(
                                onSendToKitchen: _sendToKitchen,
                                onCheckout: _checkoutTable,
                                onClear: _handleClearTable,
                                onBack: _handleBack,
                                onToggleTax: _toggleOrderTax,
                              ),
                            ],
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
    );
  }

  Widget _buildProcessingOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.5),
        child: const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('جاري تحميل الطلب...'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
