import 'package:flutter/material.dart';
import '../../../core/widgets/app_shortcuts.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_state_view.dart';
import '../../../core/widgets/shimmer_loading.dart';

import '../../../data/providers/providers.dart';
import '../../../services/invoice_generator.dart';
import '../../../core/constants/app_constants.dart' hide InvoiceStatus;
import '../../../domain/entities/invoice_entity.dart';
import '../../../domain/repositories/purchases_repository.dart';
import '../../screens/purchases/purchase_invoices_controller.dart';
import '../../screens/purchase_orders_screen.dart';
import '../../../data/services/excel_service.dart';
import '../../screens/purchase_invoices/widgets/purchase_invoice_form.dart';
import '../../widgets/common/common.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_content_card.dart';

// ── Part files (mixin-based extraction — faithful copy of the UralCash
// `part of` mixins; see purchases_picpos_crud.dart / purchases_picpos_details.dart
// for the copy-discipline note). ─────────────────────────────────────────
part 'purchases_picpos_crud.dart';
part 'purchases_picpos_details.dart';

/// شاشة المشتريات بهوية PicPos. تُختار بالعلامة في app_main_screen (`Brand.isPicPos`).
/// أثقل fork حتى الآن: منطق الحفظ (`createNewInvoice` / `editInvoice` /
/// `_handleSavePurchaseSimple`) كان في mixin **خاص** (`part of`) داخل شاشة
/// UralCash الأصلية، فما ينفعش يتعمله import — اتنسخ حرفياً هنا بنفس أسلوب
/// `picpos_pos_operations.dart`. تنادي نفس `purchasesRepositoryProvider`
/// (`createInvoice`/`updateInvoice`)، نفس `PurchaseInvoiceForm`، نفس
/// `AppDataTable`/`AppKpiCard`/`AppStateView`. الهيدر يستبدل `AppBar`.
/// راجع lib/presentation/screens/purchase_invoices_screen.dart (الأصل).
class PurchasesPicposScreen extends ConsumerStatefulWidget {
  const PurchasesPicposScreen({super.key});

  @override
  ConsumerState<PurchasesPicposScreen> createState() =>
      _PurchasesPicposScreenState();
}

class _PurchasesPicposScreenState extends ConsumerState<PurchasesPicposScreen>
    with _PurchasesPicposDetails, _PurchasesPicposCrud {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_searchController.text.isNotEmpty) {
        ref
            .read(purchaseInvoicesControllerProvider.notifier)
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

  /// Edit with confirmation if invoice has payments — verbatim from
  /// purchase_invoices_screen.dart's `_confirmEditInvoice`.
  Future<void> _confirmEditInvoice(InvoiceEntity invoice) async {
    // Confirm on either risk factor: money already paid, OR the invoice is
    // already posted to the GL (isLocked). Editing a posted invoice is now
    // permitted without limit for permission holders, so the operator should
    // still see explicitly that the GL entry will be reversed and re-posted.
    if (invoice.paid > 0 || invoice.isLocked) {
      final isPosted = invoice.isLocked;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: ui.TextDirection.rtl,
          child: AlertDialog(
            title: Text(isPosted
                ? 'تعديل فاتورة مُرحّلة محاسبياً'
                : 'تعديل فاتورة مدفوعة'),
            content: Text(
              isPosted
                  ? 'هذه الفاتورة مُرحّلة إلى دفتر الأستاذ. التعديل سيعكس القيد المحاسبي وحركة المخزون والتكلفة المتوسطة ثم يعيد ترحيلها بالقيم الجديدة، وسيُسجَّل في سجل التدقيق.\n\nهل تريد المتابعة؟'
                  : 'هذه الفاتورة تم دفع مبلغ منها. التعديل سيؤدي إلى عكس القيود المحاسبية وحركة المخزون وإعادة تطبيقها.\n\nهل تريد المتابعة؟',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.warning,
                  foregroundColor: Colors.white,
                ),
                child: const Text('تعديل الفاتورة'),
              ),
            ],
          ),
        ),
      );
      if (confirmed != true) return;
    }
    editInvoice(invoice);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(purchaseInvoicesControllerProvider);
    final controller = ref.read(purchaseInvoicesControllerProvider.notifier);

    // Purchase-edit policy (owner decision 2026-07-22): the edit button is
    // gated by the `purchases_edit` permission ONLY — never by `isLocked`.
    // Identical gate to purchase_invoices_screen.dart.
    final canEditPurchase =
        ref.watch(hasPermissionProvider(PermissionCodes.purchasesEdit)).value ??
            false;

    return AppShortcuts(
      searchFocusNode: _searchFocusNode,
      searchController: _searchController,
      onNew: createNewInvoice, // من الـ mixin المنسوخ
      child: PicPosScreenScaffold(
        title: 'المشتريات',
        icon: PhosphorIconsBold.receipt,
        headerActions: [
          IconButton(
            icon: const Icon(PhosphorIconsBold.arrowClockwise),
            tooltip: 'تحديث',
            onPressed: () => ref.invalidate(purchaseInvoicesControllerProvider),
          ),
          const SizedBox(width: 8),
          _buildExcelMenu(context, ref),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PurchaseOrdersScreen()),
              );
            },
            icon: const Icon(PhosphorIconsBold.clipboardText, size: 16),
            label: const Text('طلبات الشراء'),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: createNewInvoice,
            icon: const Icon(PhosphorIconsBold.plus, size: 18),
            label: const Text('فاتورة جديدة'),
          ),
        ],
        // Day 11: unified loading / empty state via AppStateView.
        body: AppStateView(
          isLoading: state.isLoading,
          isEmpty: state.allInvoices.isEmpty && !state.isLoading,
          emptyMessage: 'لا توجد فواتير مشتريات',
          emptyIcon: PhosphorIconsBold.shoppingCart,
          child: Column(
            children: [
              const SyncPendingBanner(
                tableName: 'purchase_invoices',
                label: 'فاتورة مشتريات',
              ),
              // Summary Cards — مكوّن موحّد مع شاشة المبيعات
              _buildKpiCards(context, state),

              // Filters
              _buildFilters(context, ref, state, controller),
              const SizedBox(height: 16),

              // Invoices Table
              Expanded(
                child: PicPosContentCard(
                  child: _buildInvoicesTable(
                      context, ref, state, canEditPurchase),
                ),
              ),
              if (state.selectedInvoices.isNotEmpty)
                _buildBatchActionBar(state, controller),
              const SizedBox(height: 16),
            ],
          ), // Column
        ), // AppStateView
      ),
    );
  }

  // ── Excel import/export menu — verbatim logic from the PopupMenuButton in
  // purchase_invoices_screen.dart (lines ~141-188), extracted as a helper. ──
  Widget _buildExcelMenu(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: const Icon(PhosphorIconsBold.fileXls),
      tooltip: 'استيراد / تصدير Excel',
      onSelected: (value) async {
        final excelService = ref.read(excelServiceProvider) as ExcelService?;
        if (excelService == null) return;
        if (value == 'export_template') {
          final path = await excelService.exportPurchaseInvoicesTemplate();
          if (context.mounted) {
            AppToast.show(
              context,
              path != null ? 'تم تصدير القالب بنجاح' : 'فشل تصدير القالب',
              type: path != null ? ToastType.success : ToastType.error,
            );
          }
        } else if (value == 'import') {
          final result = await excelService.importPurchaseInvoices();
          if (context.mounted) {
            AppToast.show(
              context,
              result.message,
              type: result.success ? ToastType.success : ToastType.error,
            );
            if (result.success) {
              ref.invalidate(purchaseInvoicesControllerProvider);
            }
          }
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'export_template',
          child: ListTile(
            leading: Icon(PhosphorIconsBold.export),
            title: Text('تصدير قالب فارغ'),
            dense: true,
          ),
        ),
        const PopupMenuItem(
          value: 'import',
          child: ListTile(
            leading: Icon(PhosphorIconsBold.upload),
            title: Text('استيراد من Excel'),
            dense: true,
          ),
        ),
      ],
    );
  }

  // ── KPI cards row — verbatim from purchase_invoices_screen.dart (~231-280). ──
  Widget _buildKpiCards(BuildContext context, PurchaseInvoicesScreenState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final perRow = w >= 1200 ? 5 : w >= 900 ? 4 : w >= 600 ? 3 : 2;
          const spacing = 10.0;
          final cardWidth = (w - (perRow - 1) * spacing) / perRow;
          final cards = <Widget>[
            AppKpiCard(
              icon: PhosphorIconsBold.shoppingCart,
              label: 'إجمالي المشتريات',
              value: '${state.totalAmount.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
              color: AppColors.info,
            ),
            AppKpiCard(
              icon: PhosphorIconsBold.wallet,
              label: 'المدفوع',
              value: '${state.totalPaid.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
              color: AppColors.success,
            ),
            // Returns card — makes the المتبقي formula explicit:
            //   المتبقي = الإجمالي − المدفوع − إجمالي المرتجعات
            AppKpiCard(
              icon: PhosphorIconsBold.arrowUUpLeft,
              label: 'إجمالي المرتجعات',
              value: '${state.totalReturns.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
              color: AppColors.error,
            ),
            AppKpiCard(
              icon: PhosphorIconsBold.clock,
              label: 'المتبقي',
              value: '${state.totalRemaining.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
              color: AppColors.warning,
            ),
            AppKpiCard(
              icon: PhosphorIconsBold.receipt,
              label: 'عدد الفواتير',
              value: '${state.invoiceCount}',
              color: AppColors.primary,
            ),
          ];
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: cards
                .map((c) => SizedBox(width: cardWidth, height: 72, child: c))
                .toList(),
          );
        },
      ),
    );
  }

  // ── Filters row — verbatim from purchase_invoices_screen.dart (~283-459). ──
  Widget _buildFilters(
    BuildContext context,
    WidgetRef ref,
    PurchaseInvoicesScreenState state,
    PurchaseInvoicesController controller,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              decoration: InputDecoration(
                hintText: 'بحث برقم الفاتورة...',
                prefixIcon: const Icon(
                  PhosphorIconsBold.magnifyingGlass,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                isDense: true,
              ),
              onChanged: (val) => controller.updateSearchQuery(val),
            ),
          ),
          const SizedBox(width: 12),
          // Branch filter
          ref.watch(allBranchesProvider).when(
            data: (branches) {
              if (branches.length <= 1) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int?>(
                      value: state.selectedBranchId,
                      hint: const Text('كل الفروع'),
                      isDense: true,
                      items: [
                        const DropdownMenuItem(value: null, child: Text('كل الفروع')),
                        ...branches.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name))),
                      ],
                      onChanged: (v) => controller.updateBranchFilter(v),
                    ),
                  ),
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          // Warehouse filter
          ref.watch(allWarehousesProvider).when(
            data: (warehouses) {
              if (warehouses.length <= 1) return const SizedBox.shrink();
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int?>(
                    value: state.selectedWarehouseId,
                    hint: const Text('كل المستودعات'),
                    isDense: true,
                    items: [
                      const DropdownMenuItem(value: null, child: Text('كل المستودعات')),
                      ...warehouses.map((w) => DropdownMenuItem(value: w.id, child: Text(w.name))),
                    ],
                    onChanged: (v) => controller.updateWarehouseFilter(v),
                  ),
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          const SizedBox(width: 12),
          // Cost center filter
          ref.watch(allCostCentersProvider).when(
            data: (centers) {
              if (centers.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int?>(
                      value: state.selectedCostCenterId,
                      hint: const Text('كل مراكز التكلفة'),
                      isDense: true,
                      items: [
                        const DropdownMenuItem(value: null, child: Text('كل مراكز التكلفة')),
                        ...centers.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
                      ],
                      onChanged: (v) => controller.updateCostCenterFilter(v),
                    ),
                  ),
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(PhosphorIconsBold.calendarBlank),
              label: Text(
                state.dateRange != null
                    ? '${state.dateRange!.start.day}/${state.dateRange!.start.month} - ${state.dateRange!.end.day}/${state.dateRange!.end.month}'
                    : 'تاريخ',
              ),
              onPressed: () async {
                final range = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(
                    const Duration(days: 365),
                  ),
                  initialDateRange: state.dateRange,
                  builder: (context, child) {
                    return Directionality(
                      textDirection: ui.TextDirection.rtl,
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: const ColorScheme.light(
                            primary: AppColors.primary,
                          ),
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: 450,
                              maxHeight: 600,
                            ),
                            child: child!,
                          ),
                        ),
                      ),
                    );
                  },
                );
                if (range != null) {
                  controller.updateDateRange(range);
                }
              },
            ),
          ),
          const SizedBox(width: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'all', label: Text('الكل')),
              ButtonSegment(value: 'paid', label: Text('مدفوع')),
              ButtonSegment(
                value: 'partial',
                label: Text('جزئي'),
              ),
              ButtonSegment(
                value: 'unpaid',
                label: Text('غير مدفوع'),
              ),
            ],
            selected: {state.statusFilter},
            onSelectionChanged: (val) {
              controller.updateStatusFilter(val.first);
            },
          ),
        ],
      ),
    );
  }

  // ── Invoices table — verbatim from purchase_invoices_screen.dart (~464-743). ──
  Widget _buildInvoicesTable(
    BuildContext context,
    WidgetRef ref,
    PurchaseInvoicesScreenState state,
    bool canEditPurchase,
  ) {
    return state.filteredInvoices.isEmpty
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  PhosphorIconsBold.receipt,
                  size: 64,
                  color: AppColors.textMuted.withValues(
                    alpha: 0.3,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'لا توجد فواتير مشتريات',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ],
            ),
          )
        : AppDataTable(
            showCheckboxColumn: true,
            onSelectAll: (_) {
              ref.read(purchaseInvoicesControllerProvider.notifier).toggleAllSelection();
            },
            columns: const [
              DataColumn(label: Text('رقم الفاتورة')),
              DataColumn(label: Text('المورد')),
              DataColumn(label: Text('التاريخ')),
              DataColumn(label: Text('الإجمالي')),
              DataColumn(label: Text('المدفوع')),
              DataColumn(label: Text('المتبقي')),
              DataColumn(label: Text('الحالة')),
              DataColumn(label: Text('الفرع / المخزن')),
              DataColumn(label: Text('مركز التكلفة')),
              DataColumn(label: Text('الإجراءات')),
            ],
            rows: state.filteredInvoices.map((invoice) {
                  // Subtract any purchase return value from
                  // the displayed remaining so a partially
                  // returned invoice doesn't keep showing
                  // its pre-return outstanding amount.
                  final returnedForInvoice =
                      state.returnedAmounts[invoice.id] ?? 0.0;
                  final remaining = invoice.total -
                      invoice.paid -
                      returnedForInvoice;
                  final isPaid = invoice.status == InvoiceStatus.paid;
                  final isPartial =
                      invoice.status == InvoiceStatus.partial;
                  final supplierName = invoice.partyId != null
                      ? (state.supplierNames[invoice.partyId] ??
                      'غير محدد')
                      : 'غير محدد';

                  return DataRow(
                    selected: state.selectedInvoices.contains(invoice.id ?? 0),
                    onSelectChanged: (selected) {
                      if (selected != null && invoice.id != null) {
                        ref.read(purchaseInvoicesControllerProvider.notifier).toggleSelection(invoice.id!);
                      }
                    },
                    cells: [
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                invoice.invoiceNumber,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow:
                                    TextOverflow.ellipsis,
                              ),
                            ),
                            // Return-status badge — mirrors
                            // the sales-invoice list so the
                            // user knows this purchase
                            // invoice has a linked return in
                            // "شاشة مردودات المشتريات".
                            if (invoice.status ==
                                    InvoiceStatus.returned ||
                                invoice.status ==
                                    InvoiceStatus
                                        .partialReturn) ...[
                              const SizedBox(width: 6),
                              _PurchaseReturnBadge(
                                full: invoice.status ==
                                    InvoiceStatus.returned,
                              ),
                            ],
                          ],
                        ),
                      ),
                      DataCell(
                        Text(
                          supplierName,
                          style: const TextStyle(
                            color: AppColors.warning,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          invoice.invoiceDate
                              .toString()
                              .substring(0, 10),
                        ),
                      ),
                      DataCell(
                        Text(
                          '${invoice.total.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                        ),
                      ),
                      DataCell(
                        Text(
                          '${invoice.paid.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                          style: const TextStyle(
                            color: AppColors.success,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          '${remaining.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                          style: TextStyle(
                            color: remaining > 0
                                ? AppColors.error
                                : remaining < 0
                                    ? AppColors.warning
                                    : AppColors.success,
                            fontWeight: remaining < 0
                                ? FontWeight.w600
                                : null,
                          ),
                        ),
                      ),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isPaid
                                ? AppColors.success.withValues(
                                    alpha: 0.1,
                                  )
                                : isPartial
                                ? AppColors.warning.withValues(
                                    alpha: 0.1,
                                  )
                                : invoice.status == InvoiceStatus.cancelled
                                ? AppColors.error.withValues(
                                    alpha: 0.1,
                                  )
                                : AppColors.error.withValues(
                                    alpha: 0.1,
                                  ),
                            borderRadius:
                                BorderRadius.circular(4),
                          ),
                          child: Text(
                            isPaid
                                ? 'مدفوع'
                                : isPartial
                                ? 'جزئي'
                                : invoice.status == InvoiceStatus.cancelled
                                ? 'ملغي'
                                : 'غير مدفوع',
                            style: TextStyle(
                              color: isPaid
                                  ? AppColors.success
                                  : isPartial
                                  ? AppColors.warning
                                  : AppColors.error,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      // Branch / Warehouse cell — prefer
                      // direct branchId on the invoice (L3),
                      // fall back to warehouse FK lookup for
                      // legacy rows.
                      DataCell(
                        Builder(builder: (_) {
                          final whId = invoice.warehouseId;
                          final whName = state.warehouseNames[whId] ?? 'WH#$whId';
                          final brId = invoice.branchId ??
                              state.warehouseBranchId[whId];
                          final brName = brId != null
                              ? (state.branchNames[brId] ?? 'فرع #$brId')
                              : null;
                          return Text.rich(
                            TextSpan(
                              children: [
                                if (brName != null) ...[
                                  TextSpan(
                                    text: brName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  const TextSpan(text: ' / '),
                                ],
                                TextSpan(
                                  text: whName,
                                  style: const TextStyle(color: AppColors.info),
                                ),
                              ],
                            ),
                            style: const TextStyle(fontSize: 12),
                          );
                        }),
                      ),
                      DataCell(
                        Text(
                          invoice.costCenterId != null
                              // Spec 119 (Bug K) — fallback أنظف بدل "م.ت #N"
                              ? (state.costCenterNames[invoice.costCenterId] ?? '—')
                              : '—',
                          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                        ),
                      ),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                PhosphorIconsBold.eye,
                                size: 18,
                              ),
                              color: AppColors.info,
                              tooltip: 'عرض التفاصيل',
                              onPressed: () =>
                                  showInvoiceDetails(invoice),
                            ),
                            IconButton(
                              icon: Icon(
                                PhosphorIconsBold.pencilSimple,
                                size: 18,
                                color: canEditPurchase
                                    ? AppColors.warning
                                    : AppColors.textMuted
                                        .withValues(alpha: 0.3),
                              ),
                              tooltip: canEditPurchase
                                  ? (invoice.isLocked
                                      ? 'تعديل فاتورة مُرحّلة'
                                      : 'تعديل')
                                  : 'لا تملك صلاحية تعديل فواتير المشتريات',
                              onPressed: canEditPurchase
                                  ? () => _confirmEditInvoice(
                                      invoice)
                                  : null,
                            ),
                            IconButton(
                              icon: const Icon(
                                PhosphorIconsBold.printer,
                                size: 18,
                              ),
                              color: AppColors.primary,
                              tooltip: 'طباعة',
                              onPressed: () =>
                                  printInvoice(invoice),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
            }).toList(),
          );
  }

  Widget _buildBatchActionBar(PurchaseInvoicesScreenState state, PurchaseInvoicesController controller) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          )
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'تم تحديد ${state.selectedInvoices.length} فاتورة مسجلة',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          Row(
            children: [
              TextButton.icon(
                onPressed: () {
                  controller.clearSelection();
                },
                icon: const Icon(PhosphorIconsBold.x, color: Colors.white70),
                label: const Text('إلغاء التحديد', style: TextStyle(color: Colors.white70)),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: () => _batchPrint(state),
                icon: const Icon(PhosphorIconsBold.printer, size: 18),
                label: const Text('طباعة المحددة'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.primary,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => Directionality(
                      textDirection: ui.TextDirection.rtl,
                      child: AlertDialog(
                        title: const Row(
                          children: [
                            Icon(PhosphorIconsBold.warning, color: Colors.red),
                            SizedBox(width: 8),
                            Text('تأكيد الحذف المجمع'),
                          ],
                        ),
                        content: Text('هل أنت متأكد من حذف ${state.selectedInvoices.length} فاتورة مشتريات محددة؟'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('إلغاء'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                            child: const Text('حذف الجميع'),
                          ),
                        ],
                      ),
                    ),
                  );

                  if (confirm == true) {
                     // Delete in batch
                     for (final invoiceId in state.selectedInvoices) {
                        final inv = state.allInvoices.firstWhere((element) => element.id == invoiceId);
                        await controller.deleteInvoice(invoiceId, inv.invoiceNumber, inv.total);
                     }
                     controller.clearSelection();
                     if (context.mounted) {
                       AppToast.show(context, 'تم حذف الفواتير المحددة بنجاح', type: ToastType.success);
                     }
                  }
                },
                icon: const Icon(PhosphorIconsBold.trash, size: 18),
                label: const Text('حذف المحددة'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  void _batchPrint(PurchaseInvoicesScreenState state) {
    final selected = state.selectedInvoices;
    if (selected.isEmpty) return;

    final invoicesToPrint = state.allInvoices
        .where((inv) => selected.contains(inv.id))
        .toList();

    if (invoicesToPrint.isEmpty) {
      AppToast.show(context, 'لم يتم العثور على الفواتير المحددة', type: ToastType.warning);
      return;
    }

    // Fire-and-forget each print — printInvoice() handles its own errors and toasts
    for (final invoice in invoicesToPrint) {
      printInvoice(invoice);
    }

    AppToast.show(
      context,
      'جاري طباعة ${invoicesToPrint.length} فاتورة...',
      type: ToastType.info,
    );
  }

}

/// Compact badge surfaced next to a purchase invoice number when the
/// invoice has been returned (fully or partially) via the returns-screen
/// flow. Verbatim copy of `_PurchaseReturnBadge` from
/// purchase_invoices_screen.dart — private class, separate library, no
/// name clash with the UralCash original.
class _PurchaseReturnBadge extends StatelessWidget {
  final bool full;
  const _PurchaseReturnBadge({required this.full});

  @override
  Widget build(BuildContext context) {
    final color = full ? AppColors.error : AppColors.warning;
    return Tooltip(
      message: full
          ? 'تم إرجاع الفاتورة بالكامل — راجع شاشة مردودات المشتريات للتفاصيل'
          : 'تم إرجاع جزء من الفاتورة — راجع شاشة مردودات المشتريات للتفاصيل',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              full ? Icons.undo_rounded : Icons.rotate_left_rounded,
              size: 12,
              color: color,
            ),
            const SizedBox(width: 3),
            Text(
              full ? 'مُرتجعة' : 'مُرتجعة جزئياً',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
