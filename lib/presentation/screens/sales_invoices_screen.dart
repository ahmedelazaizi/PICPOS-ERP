import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/widgets/app_shortcuts.dart';
import '../../domain/repositories/sales_repository.dart';
import '../../domain/repositories/inventory_repository.dart' show WarehouseData;
import '../../core/utils/financial_utils.dart';
import '../../core/utils/app_error_handler.dart';
import '../../core/logging/diagnostic_logger.dart';
import '../../core/widgets/app_toast.dart';
// 063 (D1-005): dual-approval gate for invoice deletion.
import '../../services/dual_approval_service.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_state_view.dart';
import '../../core/widgets/shimmer_loading.dart';

import '../../data/providers/providers.dart';
import '../../domain/models/branch_assignment_scope.dart';
import '../../data/database/sync_interceptor.dart';
import '../../services/network_service.dart';
import '../../core/constants/app_constants.dart' hide InvoiceStatus;
import 'sales_invoices_controller.dart';
// دفعة ٩ — حرّاس sales_print و sales_amounts_view في ملفات الـpart تحت.
import '../widgets/permission_guard.dart';
import '../../core/permissions/permission_codes.dart';
import '../widgets/dialogs/add_product_dialog.dart';
import 'sales_orders_screen.dart';

// Additional imports for sales_invoice_dialogs.part
import '../widgets/searchable_unit_selection_dialog.dart';
import '../../domain/entities/cart_item_entity.dart';
import 'quotations/quotations_tab.dart'; // Add quotations tab import
import 'quotations/quotations_controller.dart';
import '../../domain/entities/quotation_entity.dart';
import '../../domain/entities/invoice_entity.dart';
import '../../core/widgets/unsaved_changes_dialog.dart';
// Replace quotations_dao import with database

import '../../services/profit_margin_analysis_service.dart';
import '../../domain/usecases/sales/calculate_profit_margin_usecase.dart';
import '../widgets/common/common.dart';
// Spec 090 — extracted full-screen sales-invoice form (replaces the broken
// AlertDialog + StatefulBuilder + PopScope pattern that froze on
// client/mirror). Standalone widget, NOT a part-file, so it is unit-testable.
import 'widgets/sales_invoices/sales_invoice_form.dart';

part 'widgets/sales_invoices/sales_summary_cards.dart';
part 'widgets/sales_invoices/sales_invoices_table.dart';
part 'widgets/sales_invoices/sales_filter_bar.dart';
part 'widgets/sales_invoices/sales_invoice_dialogs.dart';
part 'widgets/sales_invoices/sales_invoice_save_edit.dart';
part 'widgets/sales_invoices/sales_batch_action_bar.dart';

/// Sales Invoices Screen — Accounting-Style (matching PurchaseInvoicesScreen)
class SalesInvoicesScreen extends ConsumerStatefulWidget {
  const SalesInvoicesScreen({super.key});

  @override
  ConsumerState<SalesInvoicesScreen> createState() =>
      _SalesInvoicesScreenState();
}

class _SalesInvoicesScreenState extends ConsumerState<SalesInvoicesScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_searchController.text.isNotEmpty) {
        ref
            .read(salesInvoicesControllerProvider.notifier)
            .updateSearchQuery(_searchController.text);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(salesInvoicesControllerProvider);

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: AppShortcuts(
        searchFocusNode: _searchFocusNode,
        searchController: _searchController,
        onNew: _createNewInvoice,
        child: DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: AppColors.surface,
          appBar: AppBar(
            title: const Text('المبيعات وعروض الأسعار'),
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            bottom: const TabBar(
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              indicatorColor: Colors.white,
              tabs: [
                Tab(text: 'فواتير المبيعات'),
                Tab(text: 'عروض الأسعار'),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(PhosphorIconsBold.arrowClockwise),
                tooltip: 'تحديث',
                onPressed: () => ref.read(salesInvoicesControllerProvider.notifier).refresh(),
              ),
              // Recovery tool: push local sales that haven't reached the
              // server yet (e.g. after a server-side fix to an earlier
              // sync rejection, OR after a Spec 089 reconcile drift that
              // saved invoices in server mode on a mirror device).
              // Server-side duplicate check makes this idempotent.
              //
              // Spec 097 (R9 broadened): visible on both client AND mirror
              // — both can accumulate local-only invoices that need to
              // backfill to HQ.
              if (NetworkService.instance.isClient ||
                  NetworkService.instance.isMirror)
                IconButton(
                  icon: const Icon(PhosphorIconsBold.cloudArrowUp),
                  tooltip: 'دفع الفواتير المحلية للسيرفر',
                  onPressed: () async {
                    final syncRepo = ref.read(syncRepositoryProvider);
                    AppToast.show(
                      context,
                      'جارى دفع الفواتير المحلية إلى السيرفر...',
                      type: ToastType.info,
                    );
                    final result = await syncRepo.pushLocalSalesToServer();
                    if (!context.mounted) return;
                    AppToast.show(
                      context,
                      result.message,
                      type: result.success ? ToastType.success : ToastType.warning,
                    );
                    ref.read(salesInvoicesControllerProvider.notifier).refresh();
                  },
                ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SalesOrdersScreen()),
                  );
                },
                icon: const Icon(PhosphorIconsBold.clipboardText, size: 16),
                label: const Text('طلبات البيع'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _createNewInvoice,
                icon: const Icon(PhosphorIconsBold.plus),
                label: const Text('فاتورة جديدة'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.primary,
                ),
              ),
              const SizedBox(width: 16),
            ],
          ),
          body: TabBarView(
            children: [
              // Tab 1: Sales Invoices — Day 11: unified state via AppStateView.
              AppStateView(
                isLoading: state.isLoading,
                isEmpty: state.allInvoices.isEmpty && !state.isLoading,
                emptyMessage: 'لا توجد فواتير مبيعات',
                emptyIcon: PhosphorIconsBold.receipt,
                child: Column(
                  children: [
                    const SyncPendingBanner(
                      tableName: 'sales',
                      label: 'فاتورة مبيعات',
                    ),
                    const SalesSummaryRow(),
                    SalesFilterBar(
                      searchController: _searchController,
                      searchFocusNode: _searchFocusNode,
                    ),
                    const SizedBox(height: 16),
                    SalesInvoicesTable(
                      onView: _showInvoiceDetails,
                      onEdit: _editInvoice,
                      onPrint: _printInvoice,
                      onDelete: _deleteInvoice,
                    ),
                    const SalesBatchActionBar(),
                  ],
                ),
              ),

              // Tab 2: Quotations
              QuotationsTab(
                onEditQuotation: (q) =>
                    _createNewInvoice(editQuotation: q, isConvert: false),
                onConvertQuotation: (q) =>
                    _createNewInvoice(editQuotation: q, isConvert: true),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

}
