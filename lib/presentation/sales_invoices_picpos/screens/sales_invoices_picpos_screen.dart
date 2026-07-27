import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/widgets/app_shortcuts.dart';
import '../../../core/utils/app_error_handler.dart';
import '../../../core/logging/diagnostic_logger.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../services/dual_approval_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_state_view.dart';

import '../../../data/providers/providers.dart';
import '../../../data/database/sync_interceptor.dart';
import '../../../services/network_service.dart';
import '../../../core/constants/app_constants.dart' hide InvoiceStatus;
import '../../screens/sales_invoices_controller.dart';
import '../../widgets/dialogs/add_product_dialog.dart';
import '../../screens/sales_orders_screen.dart';

// Additional imports for sales_invoice_dialogs.dart / sales_invoice_save_edit.dart
import '../../widgets/searchable_unit_selection_dialog.dart';
import '../../../domain/entities/cart_item_entity.dart';
import '../../screens/quotations/quotations_controller.dart';
import '../../../domain/entities/quotation_entity.dart';
import '../../../domain/entities/invoice_entity.dart';
import '../../../domain/repositories/sales_repository.dart';
import '../../../domain/repositories/inventory_repository.dart' show WarehouseData;

import '../../../services/profit_margin_analysis_service.dart';
import '../../../domain/usecases/sales/calculate_profit_margin_usecase.dart';
import '../../widgets/common/common.dart';
// Spec 090 — the extracted full-screen sales-invoice form, standalone
// widget (NOT a part-file), reused as-is — see task brief §Reuse.
import '../../screens/widgets/sales_invoices/sales_invoice_form.dart';

import '../../picpos_shell/picpos_screen_scaffold.dart';

// ── Part files (منسوخة حرفياً من lib/presentation/screens/widgets/sales_invoices/
// — الشاشة الأصل `part of _SalesInvoicesScreenState` خاصة فما ينفعش تتعمل
// import، فبتنتقل بنسخ حرفي هنا؛ راجع تعليق مصيدة النسخ في رأس كل ملف). ─────
part 'sales_summary_cards.dart';
part 'sales_invoices_table.dart';
part 'sales_filter_bar.dart';
part 'sales_invoice_dialogs.dart';
part 'sales_invoice_save_edit.dart';
part 'sales_batch_action_bar.dart';

/// شاشة فواتير البيع بهوية PicPos. تُختار بالعلامة في app_main_screen
/// (`Brand.isPicPos`). تعيد استخدام نفس `salesInvoicesControllerProvider` /
/// `SalesInvoiceForm` / `AddProductDialog` / `SearchableUnitSelectionDialog` /
/// `SyncPendingBanner` من UralCash — فقط طبقة العرض تبدّلت لـ `picpos_shell`.
///
/// النطاق: تبويب فواتير المبيعات فقط (بدون تبويب «عروض الأسعار» — غير مذكور
/// في نطاق المهمة ولا في الهيدر المطلوب). زر «حفظ كعرض سعر» داخل
/// `SalesInvoiceForm` نفسه (`onSaveQuotation`) يبقى شغّال بلا تغيير لأن
/// النموذج يُعاد استخدامه كما هو.
///
/// راجع lib/presentation/screens/sales_invoices_screen.dart (الأصل).
class SalesInvoicesPicposScreen extends ConsumerStatefulWidget {
  const SalesInvoicesPicposScreen({super.key});

  @override
  ConsumerState<SalesInvoicesPicposScreen> createState() =>
      _SalesInvoicesPicposScreenState();
}

class _SalesInvoicesPicposScreenState
    extends ConsumerState<SalesInvoicesPicposScreen> {
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

    return AppShortcuts(
      searchFocusNode: _searchFocusNode,
      searchController: _searchController,
      onNew: _createNewInvoice, // من الملف المنسوخ sales_invoice_dialogs.dart
      child: PicPosScreenScaffold(
        title: 'فواتير البيع',
        subtitle: 'إدارة فواتير المبيعات ومتابعة التحصيل',
        icon: PhosphorIconsBold.receipt,
        headerActions: [
          IconButton(
            icon: const Icon(PhosphorIconsBold.arrowClockwise),
            tooltip: 'تحديث',
            onPressed: () =>
                ref.read(salesInvoicesControllerProvider.notifier).refresh(),
          ),
          // Recovery tool: push local sales that haven't reached the server
          // yet — verbatim from sales_invoices_screen.dart's AppBar actions.
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
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _createNewInvoice,
            icon: const Icon(PhosphorIconsBold.plus, size: 18),
            label: const Text('فاتورة جديدة'),
          ),
        ],
        body: AppStateView(
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
              // ملاحظة تخطيط: SalesInvoicesTable بترجع Expanded من جوّاها
              // (منسوخة حرفياً بلا تعديل منطقي — مصيدة النسخ)، فما بتتلفّش
              // بـ PicPosContentCard (Container بيكسر ParentDataWidget بتاع
              // Expanded لو حط بينها وبين الـ Flex). AppDataTable أصلاً
              // بترسم حدودها كـ"كارت" بنفسها، فمفيش فرق بصري محسوس.
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
      ),
    );
  }
}
