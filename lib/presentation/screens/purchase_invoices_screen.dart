import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import '../../core/widgets/app_shortcuts.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/permissions/permission_codes.dart';
// دفعة ٩ — حارس purchases_print على زرار الطباعة في قائمة الفواتير.
import '../widgets/permission_guard.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_state_view.dart';

import '../../data/providers/providers.dart';
import '../../services/invoice_generator.dart';
import '../../core/constants/app_constants.dart' hide InvoiceStatus;
import '../../domain/models/branch_assignment_scope.dart';
import '../../domain/entities/invoice_entity.dart';
import '../../domain/repositories/purchases_repository.dart';
import 'purchases/purchase_invoices_controller.dart';
import 'purchase_orders_screen.dart';
import '../../data/services/excel_service.dart';
import 'purchase_invoices/widgets/purchase_invoice_form.dart';
import '../widgets/common/common.dart';

// ── Part files (mixin-based extraction) ─────────────────────────────────
part 'purchase_invoices/purchase_invoice_details.dart';
part 'purchase_invoices/purchase_invoice_crud.dart';

/// Purchase Invoices Screen - View, Search, and Manage All Purchase Invoices
/// Form-based design matching Sales Invoices for commercial system
class PurchaseInvoicesScreen extends ConsumerStatefulWidget {
  const PurchaseInvoicesScreen({super.key});

  @override
  ConsumerState<PurchaseInvoicesScreen> createState() =>
      _PurchaseInvoicesScreenState();
}

class _PurchaseInvoicesScreenState
    extends ConsumerState<PurchaseInvoicesScreen>
    with _PurchaseInvoiceDetailsMixin, _PurchaseInvoiceCrudMixin {
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

  /// Edit with confirmation if invoice has payments
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
                ? tr('تعديل فاتورة مُرحّلة محاسبياً')
                : tr('تعديل فاتورة مدفوعة')),
            content: Text(
              isPosted
                  ? tr('هذه الفاتورة مُرحّلة إلى دفتر الأستاذ. التعديل سيعكس القيد المحاسبي وحركة المخزون والتكلفة المتوسطة ثم يعيد ترحيلها بالقيم الجديدة، وسيُسجَّل في سجل التدقيق.\n\nهل تريد المتابعة؟')
                  : tr('هذه الفاتورة تم دفع مبلغ منها. التعديل سيؤدي إلى عكس القيود المحاسبية وحركة المخزون وإعادة تطبيقها.\n\nهل تريد المتابعة؟'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child:  Text(tr('إلغاء')),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.warning,
                  foregroundColor: Colors.white,
                ),
                child:  Text(tr('تعديل الفاتورة')),
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
    // A permitted user (including مدير النظام) edits without limit, before or
    // after posting; the DAO reverses and re-posts the GL entry each time.
    // Previously this was `onPressed: invoice.isLocked ? null : ...`, which
    // made every posted invoice permanently uneditable from the UI and left
    // the `modify_locked_invoice` permission unreachable.
    final canEditPurchase =
        ref.watch(hasPermissionProvider(PermissionCodes.purchasesEdit)).value ??
            false;

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: AppShortcuts(
        searchFocusNode: _searchFocusNode,
        searchController: _searchController,
        onNew: createNewInvoice,
        child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          title:  Text(tr('فواتير المشتريات')),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(PhosphorIconsBold.arrowClockwise),
              tooltip: tr('تحديث'),
              onPressed: () => ref.invalidate(purchaseInvoicesControllerProvider),
            ),
            const SizedBox(width: 8),
            // Excel Import/Export Button
            PopupMenuButton<String>(
              icon: const Icon(PhosphorIconsBold.fileXls),
              tooltip: tr('استيراد / تصدير Excel'),
              onSelected: (value) async {
                final excelService = ref.read(excelServiceProvider) as ExcelService?;
                if (excelService == null) return;
                if (value == 'export_template') {
                  final path = await excelService.exportPurchaseInvoicesTemplate();
                  if (context.mounted) {
                    AppToast.show(
                      context,
                      path != null ? tr('تم تصدير القالب بنجاح') : tr('فشل تصدير القالب'),
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
                 PopupMenuItem(
                  value: 'export_template',
                  child: ListTile(
                    leading: const Icon(PhosphorIconsBold.export),
                    title: Text(tr('تصدير قالب فارغ')),
                    dense: true,
                  ),
                ),
                 PopupMenuItem(
                  value: 'import',
                  child: ListTile(
                    leading: const Icon(PhosphorIconsBold.upload),
                    title: Text(tr('استيراد من Excel')),
                    dense: true,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PurchaseOrdersScreen()),
                );
              },
              icon: const Icon(PhosphorIconsBold.clipboardText, size: 16),
              label:  Text(tr('طلبات الشراء')),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white54),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: createNewInvoice,
              icon: const Icon(PhosphorIconsBold.plus),
              label:  Text(tr('فاتورة جديدة')),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
              ),
            ),
            const SizedBox(width: 16),
          ],
        ),
        // Day 11: unified loading / empty state via AppStateView.
        body: AppStateView(
          isLoading: state.isLoading,
          isEmpty: state.allInvoices.isEmpty && !state.isLoading,
          emptyMessage: tr('لا توجد فواتير مشتريات'),
          emptyIcon: PhosphorIconsBold.shoppingCart,
          child: Column(
                children: [
                   SyncPendingBanner(
                    tableName: 'purchase_invoices',
                    label: tr('فاتورة مشتريات'),
                  ),
                  // Summary Cards — مكوّن موحّد مع شاشة المبيعات
                  Padding(
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
                            label: tr('إجمالي المشتريات'),
                            value: '${state.totalAmount.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                            color: AppColors.info,
                          ),
                          AppKpiCard(
                            icon: PhosphorIconsBold.wallet,
                            label: tr('المدفوع'),
                            value: '${state.totalPaid.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                            color: AppColors.success,
                          ),
                          // Returns card — makes the المتبقي formula explicit:
                          //   المتبقي = الإجمالي − المدفوع − إجمالي المرتجعات
                          AppKpiCard(
                            icon: PhosphorIconsBold.arrowUUpLeft,
                            label: tr('إجمالي المرتجعات'),
                            value: '${state.totalReturns.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                            color: AppColors.error,
                          ),
                          AppKpiCard(
                            icon: PhosphorIconsBold.clock,
                            label: tr('المتبقي'),
                            value: '${state.totalRemaining.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                            color: AppColors.warning,
                          ),
                          AppKpiCard(
                            icon: PhosphorIconsBold.receipt,
                            label: tr('عدد الفواتير'),
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
                  ),

                  // Filters
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _searchController,
                            focusNode: _searchFocusNode,
                            decoration: InputDecoration(
                              hintText: tr('بحث برقم الفاتورة...'),
                              prefixIcon: const Icon(
                                PhosphorIconsBold.magnifyingGlass,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              isDense: true,
                            ),
                            onChanged: (val) =>
                                controller.updateSearchQuery(val),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Branch filter
                        ref.watch(allBranchesProvider).when(
                          data: (branches) {
                            if (branches.length <= 1) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsetsDirectional.only(end: 12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  border: Border.all(color: AppColors.border),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<int?>(
                                    value: state.selectedBranchId,
                                    hint:  Text(tr('كل الفروع')),
                                    isDense: true,
                                    items: [
                                       DropdownMenuItem(value: null, child: Text(tr('كل الفروع'))),
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
                                  hint:  Text(tr('كل المستودعات')),
                                  isDense: true,
                                  items: [
                                     DropdownMenuItem(value: null, child: Text(tr('كل المستودعات'))),
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
                              padding: const EdgeInsetsDirectional.only(end: 12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  border: Border.all(color: AppColors.border),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<int?>(
                                    value: state.selectedCostCenterId,
                                    hint:  Text(tr('كل مراكز التكلفة')),
                                    isDense: true,
                                    items: [
                                       DropdownMenuItem(value: null, child: Text(tr('كل مراكز التكلفة'))),
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
                                  : tr('تاريخ'),
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
                          segments:  [
                            ButtonSegment(value: 'all', label: Text(tr('الكل'))),
                            ButtonSegment(value: 'paid', label: Text(tr('مدفوع'))),
                            ButtonSegment(
                              value: 'partial',
                              label: Text(tr('جزئي')),
                            ),
                            ButtonSegment(
                              value: 'unpaid',
                              label: Text(tr('غير مدفوع')),
                            ),
                          ],
                          selected: {state.statusFilter},
                          onSelectionChanged: (val) {
                            controller.updateStatusFilter(val.first);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Invoices Table
                  Expanded(
                    child: state.filteredInvoices.isEmpty
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
                                 Text(
                                  tr('لا توجد فواتير مشتريات'),
                                  style: const TextStyle(color: AppColors.textMuted),
                                ),
                              ],
                            ),
                          )
                        : AppDataTable(
                            showCheckboxColumn: true,
                            onSelectAll: (_) {
                              ref.read(purchaseInvoicesControllerProvider.notifier).toggleAllSelection();
                            },
                            columns:  [
                              DataColumn(label: Text(tr('رقم الفاتورة'))),
                              DataColumn(label: Text(tr('المورد'))),
                              DataColumn(label: Text(tr('التاريخ'))),
                              DataColumn(label: Text(tr('الإجمالي'))),
                              DataColumn(label: Text(tr('المدفوع'))),
                              DataColumn(label: Text(tr('المتبقي'))),
                              DataColumn(label: Text(tr('الحالة'))),
                              DataColumn(label: Text(tr('الفرع / المخزن'))),
                              DataColumn(label: Text(tr('مركز التكلفة'))),
                              // نفسُ عطبِ شاشة المبيعات: أربعةُ أزرارٍ (192)
                              // في حصّةٍ متساويةٍ بين عشرة أعمدةٍ تقلّ عنها،
                              // فيفيض أوّلُ زرٍّ خارجَ خليّته ويموت.
                              DataColumn2(label: Text(tr('الإجراءات')), fixedWidth: 210),
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
                                      tr('غير محدد'))
                                      : tr('غير محدد');

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
                                            // "شاشة مرتجع المشتريات".
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
                                                ? tr('مدفوع')
                                                : isPartial
                                                ? tr('جزئي')
                                                : invoice.status == InvoiceStatus.cancelled
                                                ? tr('ملغي')
                                                : tr('غير مدفوع'),
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
                                              ? (state.branchNames[brId] ?? tr('فرع #{brId}', {'brId': brId}))
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
                                              tooltip: tr('عرض التفاصيل'),
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
                                                      ? tr('تعديل فاتورة مُرحّلة')
                                                      : tr('تعديل'))
                                                  : tr('لا تملك صلاحية تعديل فواتير المشتريات'),
                                              onPressed: canEditPurchase
                                                  ? () => _confirmEditInvoice(
                                                      invoice)
                                                  : null,
                                            ),
                                            // purchases_print — كان مكشوف
                                            // جنب زرار التعديل المبوّب فوقه
                                            // بالظبط. تجاوز مدير: منع الطباعة
                                            // نهائياً بيوقف تسليم مستند شرعي.
                                            PermissionGuard(
                                              permission: PermissionCodes
                                                  .purchasesPrint,
                                              allowManagerOverride: true,
                                              actionName:
                                                  tr('طباعة فاتورة مشتريات'),
                                              onGranted: () =>
                                                  printInvoice(invoice),
                                              child: IconButton(
                                                icon: const Icon(
                                                  PhosphorIconsBold.printer,
                                                  size: 18,
                                                ),
                                                color: AppColors.primary,
                                                tooltip: tr('طباعة'),
                                                onPressed: () =>
                                                    printInvoice(invoice),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  );
                            }).toList(),
                          ),
                  ),
                  if (state.selectedInvoices.isNotEmpty)
                    _buildBatchActionBar(state, controller),
                  const SizedBox(height: 16),
                ],
              ), // Column
          ), // AppStateView
      ), // Scaffold
      ), // AppShortcuts
    ); // Directionality
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
            tr('تم تحديد {p0} فاتورة مسجلة', {'p0': state.selectedInvoices.length}),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          Row(
            children: [
              TextButton.icon(
                onPressed: () {
                  controller.clearSelection();
                },
                icon: const Icon(PhosphorIconsBold.x, color: Colors.white70),
                label:  Text(tr('إلغاء التحديد'), style: const TextStyle(color: Colors.white70)),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: () => _batchPrint(state),
                icon: const Icon(PhosphorIconsBold.printer, size: 18),
                label:  Text(tr('طباعة المحددة')),
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
                        title:  Row(
                          children: [
                            const Icon(PhosphorIconsBold.warning, color: AppColors.error),
                            const SizedBox(width: 8),
                            Text(tr('تأكيد الحذف المجمع')),
                          ],
                        ),
                        content: Text(tr('هل أنت متأكد من حذف {p0} فاتورة مشتريات محددة؟', {'p0': state.selectedInvoices.length})),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child:  Text(tr('إلغاء')),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
                            child:  Text(tr('حذف الجميع')),
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
                      if (!mounted) return;
                      AppToast.show(context, tr('تم حذف الفواتير المحددة بنجاح'), type: ToastType.success);
                  }
                },
                icon: const Icon(PhosphorIconsBold.trash, size: 18),
                label:  Text(tr('حذف المحددة')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
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
      AppToast.show(context, tr('لم يتم العثور على الفواتير المحددة'), type: ToastType.warning);
      return;
    }

    // Fire-and-forget each print — printInvoice() handles its own errors and toasts
    for (final invoice in invoicesToPrint) {
      printInvoice(invoice);
    }

    AppToast.show(
      context,
      tr('جاري طباعة {p0} فاتورة...', {'p0': invoicesToPrint.length}),
      type: ToastType.info,
    );
  }

}

/// Compact badge surfaced next to a purchase invoice number when the
/// invoice has been returned (fully or partially) via the returns-screen
/// flow. Mirrors `_ReturnBadge` on the sales side so the look and feel
/// stay consistent across both modules.
class _PurchaseReturnBadge extends StatelessWidget {
  final bool full;
  const _PurchaseReturnBadge({required this.full});

  @override
  Widget build(BuildContext context) {
    final color = full ? AppColors.error : AppColors.warning;
    return Tooltip(
      message: full
          ? tr('تم إرجاع الفاتورة بالكامل — راجع شاشة مرتجع المشتريات للتفاصيل')
          : tr('تم إرجاع جزء من الفاتورة — راجع شاشة مرتجع المشتريات للتفاصيل'),
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
              full ? tr('مُرتجعة') : tr('مُرتجعة جزئياً'),
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
