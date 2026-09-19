import 'dart:async';
import 'package:flutter/material.dart';
import '../../picpos_shell/picpos_surface.dart';
// دفعة ٩ — حرّاس sales_print و sales_amounts_view في ملفات الـpart تحت.
import '../../widgets/permission_guard.dart';
import '../../../core/permissions/permission_codes.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../domain/models/branch_assignment_scope.dart';

import '../../../core/widgets/app_shortcuts.dart';
import '../../../core/utils/app_error_handler.dart';
import '../../../core/logging/diagnostic_logger.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../services/dual_approval_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/number_utils.dart';
import '../../../core/widgets/app_state_view.dart';

import '../../../data/providers/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/database/sync_interceptor.dart';
import '../../../domain/models/warehouse_branch_scope.dart';
import '../../../services/network_service.dart';
import '../../../core/constants/app_constants.dart' hide InvoiceStatus;
import '../../screens/sales_invoices_controller.dart';
import '../../widgets/dialogs/add_product_dialog.dart';
import '../../screens/sales_orders_screen.dart';

// Additional imports for sales_invoice_dialogs.dart / sales_invoice_save_edit.dart
import '../../widgets/searchable_unit_selection_dialog.dart';
import '../../../domain/entities/cart_item_entity.dart';
import '../../screens/quotations/quotations_controller.dart';
// Fix round 1 (owner decision): full parity with UralCash — the Quotations
// tab is reused as-is, not copied (its own file, not a `part of`).
import '../../screens/quotations/quotations_tab.dart';
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
// تصميمُ 2026-08-21 — شاشةُ «فاتورة جديدة» المشتركة بين النمطَين.
import '../../invoice_form_picpos/picpos_invoice_form.dart';
// نموذجُ سطرِ الطباعة — لمعاينة A4 قبل الحفظ.
import '../../../services/printing/printing_models.dart' as print_models;
import '../../../domain/models/picpos_invoice_draft.dart';
import '../../shared_widgets/whatsapp_send_dialog.dart';
import '../../../domain/models/whatsapp_message.dart';

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
/// Fix round 1 (owner decision) — parity: الأصل `sales_invoices_screen.dart`
/// يعرض تبويبَين دايماً وبلا أي شرط/صلاحية (`DefaultTabController(length: 2)`
/// ثابت، مفيش `PermissionGuard`/feature flag يلفّهم) — «فواتير المبيعات» و
/// «عروض الأسعار». هنا نفس الترتيب ونفس عدم الاشتراط، فقط التبويب مبني بـ
/// `TabController` صريح (نفس أسلوب `inventory_picpos_screen.dart`) عشان
/// الـ `TabBar` يتحط في `subHeader` بتاع `PicPosScreenScaffold` بدل ما يتحط
/// في `AppBar.bottom` الأصلي. تبويب «عروض الأسعار» يعيد استخدام `QuotationsTab`
/// و`quotationsControllerProvider` كما هما (بلا نسخ منطق). زر «حفظ كعرض سعر»
/// داخل `SalesInvoiceForm` نفسه (`onSaveQuotation`) يبقى شغّال بلا تغيير لأن
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
    extends ConsumerState<SalesInvoicesPicposScreen>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  // Fix round 1 — parity tab (فواتير المبيعات / عروض الأسعار). Explicit
  // TabController (not DefaultTabController) so the TabBar can live in
  // PicPosScreenScaffold's `subHeader` slot while TabBarView lives in `body`
  // — same pattern as inventory_picpos_screen.dart.
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
    _tabController.dispose();
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
        // Fix round 1 — parity tab bar. Unconditional, same order/text as
        // the original's AppBar.bottom TabBar. Styling comes from
        // PicPosTheme.tabBarTheme automatically (no hardcoded colors here,
        // unlike the original which hardcodes white for its primary-colored
        // AppBar background).
        subHeader: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'فواتير المبيعات'),
              Tab(text: 'عروض الأسعار'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            // Tab 1: Sales Invoices — unchanged from before this fix.
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
                    onWhatsApp: _sendInvoiceWhatsApp,
                  ),
                  const SalesBatchActionBar(),
                ],
              ),
            ),
            // Tab 2: Quotations — reused as-is (verbatim from the original's
            // TabBarView second child), same onEditQuotation/onConvertQuotation
            // wiring into _createNewInvoice from the copied
            // sales_invoice_dialogs.dart.
            QuotationsTab(
              onEditQuotation: (q) =>
                  _createNewInvoice(editQuotation: q, isConvert: false),
              onConvertQuotation: (q) =>
                  _createNewInvoice(editQuotation: q, isConvert: true),
            ),
          ],
        ),
      ),
    );
  }
}
