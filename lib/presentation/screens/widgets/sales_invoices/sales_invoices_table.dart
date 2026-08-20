// ignore_for_file: library_private_types_in_public_api
part of '../../sales_invoices_screen.dart';

/// زرار طباعة فاتورة البيع — `sales_print`.
///
/// تجاوز مدير مش إخفاء: الطباعة بتتطلب والعميل واقف، والمنع النهائي بيوقف
/// تسليم فاتورة شرعية. `onGranted` متمرَّر صراحة (درس f8d3fa9 — الحارس
/// بيلفّ الابن في `AbsorbPointer` وبيمسك الضغطة بنفسه).
///
/// دالة top-level عشان الاختبار يبنيها لوحدها — `SalesInvoicesTable` بتقرا
/// من `salesInvoicesControllerProvider` وقاعدة بيانات حقيقية.
@visibleForTesting
Widget buildSalesPrintButtonGuarded({required VoidCallback onPrint}) {
  return PermissionGuard(
    permission: PermissionCodes.salesPrint,
    allowManagerOverride: true,
    actionName: 'طباعة فاتورة بيع',
    onGranted: onPrint,
    child: IconButton(
      icon: const Icon(PhosphorIconsBold.printer, size: 18),
      color: AppColors.primary,
      tooltip: 'طباعة',
      onPressed: onPrint,
    ),
  );
}

class SalesInvoicesTable extends ConsumerWidget {
  final Function(InvoiceEntity) onView;
  final Function(InvoiceEntity) onEdit;
  final Function(InvoiceEntity) onPrint;
  final Function(InvoiceEntity) onDelete;

  const SalesInvoicesTable({
    super.key,
    required this.onView,
    required this.onEdit,
    required this.onPrint,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filteredInvoices = ref.watch(salesInvoicesControllerProvider.select((s) => s.filteredInvoices));
    final customerNames = ref.watch(salesInvoicesControllerProvider.select((s) => s.customerNames));
    final selectedInvoices = ref.watch(salesInvoicesControllerProvider.select((s) => s.selectedInvoices));
    final returnedAmounts = ref.watch(salesInvoicesControllerProvider.select((s) => s.returnedAmounts));

    // Build warehouse name map for branch indicator on all devices
    final warehousesList = ref.watch(allWarehousesProvider).value ?? [];
    final warehouseNames = <int, String>{};
    final warehouseBranchId = <int, int?>{};
    for (final w in warehousesList) {
      warehouseNames[w.id] = w.name;
      warehouseBranchId[w.id] = w.branchId;
    }
    // Branch name lookup so the cashier can see which branch issued each
    // invoice — resolved via warehouse.branchId since SalesInvoices doesn't
    // carry a direct branchId column (yet — Level 3).
    final branchesList = ref.watch(allBranchesProvider).value ?? [];
    final branchNames = <int, String>{
      for (final b in branchesList) b.id: b.name,
    };
    // Cost center lookup — sales invoices store costCenterId directly
    final costCentersList = ref.watch(allCostCentersProvider).value ?? [];
    final costCenterNames = <int, String>{
      for (final c in costCentersList) c.id: c.name,
    };
    
    if (filteredInvoices.isEmpty) {
      // Issue 8 — distinguish "no invoices at all" from "filters narrowed
      // the result set to empty". The latter offers a reset so the user
      // doesn't have to clear each chip individually.
      final hasFilters = ref.read(salesInvoicesControllerProvider.notifier).hasActiveFilters;
      return Expanded(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                hasFilters ? PhosphorIconsBold.funnelSimple : PhosphorIconsBold.receipt,
                size: 64,
                color: AppColors.textMuted.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 16),
              Text(
                hasFilters ? 'لا نتائج تطابق الفلاتر الحالية' : 'لا توجد فواتير مبيعات',
                style: const TextStyle(color: AppColors.textMuted),
              ),
              if (hasFilters) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(PhosphorIconsBold.arrowsCounterClockwise, size: 16),
                  label: const Text('إعادة تعيين الفلاتر'),
                  onPressed: () => ref
                      .read(salesInvoicesControllerProvider.notifier)
                      .clearAllFilters(),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Expanded(
      child: AppDataTable(
        showCheckboxColumn: true,
        onSelectAll: (_) {
          ref.read(salesInvoicesControllerProvider.notifier).toggleAllSelection();
        },
        columns: const [
          DataColumn(label: Text('رقم الفاتورة')),
          DataColumn(label: Text('العميل')),
          DataColumn(label: Text('التاريخ')),
          DataColumn(label: Text('الإجمالي')),
          DataColumn(label: Text('المدفوع')),
          DataColumn(label: Text('المتبقي')),
          DataColumn(label: Text('الحالة')),
          DataColumn(label: Text('الفرع / المخزن')),
          DataColumn(label: Text('مركز التكلفة')),
          // عرضٌ ثابت: أربعةُ `IconButton` عرضُ كلٍّ منها 48 = 192، والحصّةُ
          // المتساوية بين عشرة أعمدةٍ تقلّ عن ذلك فيفيض أوّلُ زرٍّ خارجَ
          // الخليّة ويموت (لا يُختبَر بالإصابة خارجَ حدود الأب).
          DataColumn2(label: Text('الإجراءات'), fixedWidth: 210),
        ],
        rows: filteredInvoices.map<DataRow>((invoice) {
              // Returns reduce the invoice's effective receivable, so subtract
              // them from the displayed remaining. A negative value means the
              // refund exceeds the unpaid balance and we owe the customer the
              // difference — color it accordingly so the cashier notices.
              final returnedForInvoice = returnedAmounts[invoice.id] ?? 0.0;
              final remaining =
                  invoice.total - invoice.paid - returnedForInvoice;
              final isPaid = invoice.status == InvoiceStatus.paid;
              final isPartial = invoice.status == InvoiceStatus.partial;
              final isCancelled = invoice.status == InvoiceStatus.cancelled;
              final customerName = invoice.partyId != null
                  ? (customerNames[invoice.partyId] ??
                        () {
                          // Spec 002 (B4): the lookup map should resolve
                          // every existing FK now that we load inactive
                          // customers too. If we still hit the fallback,
                          // the party row itself is missing locally —
                          // log it so operators can see chronic gaps.
                          debugPrint(
                            '[SalesList] customer name fallback for '
                            'partyId=${invoice.partyId} on invoice '
                            '${invoice.invoiceNumber}',
                          );
                          return 'عميل #${invoice.partyId}';
                        }())
                  : 'عميل نقدي';

              return DataRow(
                selected: selectedInvoices.contains(invoice.id),
                onSelectChanged: (selected) {
                  if (selected != null) {
                    ref.read(salesInvoicesControllerProvider.notifier).toggleSelection(invoice.id!);
                  }
                },
                cells: [
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: invoice.invoiceNumber,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                TextSpan(
                                  text: ' — ${warehouseNames[invoice.warehouseId] ?? 'WH#${invoice.warehouseId ?? 0}'}',
                                  style: TextStyle(fontSize: 11, color: warehouseNames.containsKey(invoice.warehouseId) ? AppColors.info : AppColors.textMuted),
                                ),
                              ],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Return-status badge — makes it obvious the
                        // cashier should check "شاشة مردودات المبيعات"
                        // for the details. Returns invoices themselves
                        // (saleType='return') are filtered out of this
                        // list upstream; this only tags ORIGINAL
                        // invoices whose status was changed to
                        // returned / partial_return by the returns-screen.
                        if (invoice.status == InvoiceStatus.returned ||
                            invoice.status == InvoiceStatus.partialReturn) ...[
                          const SizedBox(width: 6),
                          _ReturnBadge(full: invoice.status == InvoiceStatus.returned),
                        ],
                      ],
                    ),
                  ),
                  DataCell(
                    Text(
                      customerName,
                      style: const TextStyle(color: AppColors.info),
                    ),
                  ),
                  DataCell(
                    Text((invoice.createdAt ?? invoice.invoiceDate).toString().substring(0, 10)),
                  ),
                  // sales_amounts_view — الإجمالي والمدفوع والمتبقي. المتبقي
                  // مشتقّ من الاتنين، فسيبانه مكشوف كان بيسرّبهم.
                  DataCell(
                    PermissionMaskedText(
                      permission: PermissionCodes.salesAmountsView,
                      text: invoice.total
                          .toStringAsFixed(AppConstants.decimalPlaces),
                    ),
                  ),
                  DataCell(
                    PermissionMaskedText(
                      permission: PermissionCodes.salesAmountsView,
                      text: invoice.paid
                          .toStringAsFixed(AppConstants.decimalPlaces),
                      style: const TextStyle(color: AppColors.success),
                    ),
                  ),
                  DataCell(
                    PermissionMaskedText(
                      permission: PermissionCodes.salesAmountsView,
                      text: remaining
                          .toStringAsFixed(AppConstants.decimalPlaces),
                      style: TextStyle(
                        color: remaining > 0
                            ? AppColors.error
                            : remaining < 0
                                ? AppColors.warning
                                : AppColors.success,
                        fontWeight: remaining < 0 ? FontWeight.w600 : null,
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
                            ? AppColors.success.withValues(alpha: 0.1)
                            : isPartial
                            ? AppColors.warning.withValues(alpha: 0.1)
                            : isCancelled
                            ? AppColors.error.withValues(alpha: 0.1)
                            : AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isPaid
                            ? 'مدفوع'
                            : isPartial
                            ? 'جزئي'
                            : isCancelled
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
                  // Branch / Warehouse cell — prefer the direct branchId
                  // stamped on the invoice (L3). Falls back to resolving via
                  // warehouse → branch FK for legacy rows that haven't been
                  // backfilled yet.
                  DataCell(
                    Builder(builder: (_) {
                      final whId = invoice.warehouseId;
                      final whName = whId != null
                          ? (warehouseNames[whId] ?? 'WH#$whId')
                          : '—';
                      final brId = invoice.branchId ??
                          (whId != null ? warehouseBranchId[whId] : null);
                      final brName = brId != null
                          ? (branchNames[brId] ?? 'فرع #$brId')
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
                          // Spec 119 (Bug K) — fallback أنظف عندما الـ cost
                          // center غير موجود في الـ map (race condition مع
                          // delta pull على mirror، أو cost center محذوف).
                          // قبلاً: "م.ت #6" كان يُربك المستخدم. الآن: "—".
                          ? (costCenterNames[invoice.costCenterId] ?? '—')
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
                          onPressed: () => onView(invoice),
                        ),
                        if (!invoice.isLocked)
                          IconButton(
                            icon: const Icon(
                              PhosphorIconsBold.pencilSimple,
                              size: 18,
                              color: AppColors.warning,
                            ),
                            tooltip: 'تعديل الدفع / وسيلة الدفع',
                            onPressed: () => onEdit(invoice),
                          ),
                        buildSalesPrintButtonGuarded(
                          onPrint: () => onPrint(invoice),
                        ),
                        if (!invoice.isLocked)
                          IconButton(
                            icon: const Icon(
                              PhosphorIconsBold.trash,
                              size: 18,
                            ),
                            color: AppColors.error,
                            tooltip: 'حذف',
                            onPressed: () => onDelete(invoice),
                          ),
                      ],
                    ),
                  ),
                ],
              );
        }).toList(),
      ),
    );
  }
}

/// Compact badge rendered next to an invoice number when the invoice's
/// status is `returned` or `partial_return`. Lets the cashier know to
/// look in "شاشة مردودات المبيعات" for the matching return record
/// without having to open the invoice.
class _ReturnBadge extends StatelessWidget {
  final bool full;
  const _ReturnBadge({required this.full});

  @override
  Widget build(BuildContext context) {
    final color = full ? AppColors.error : AppColors.warning;
    return Tooltip(
      message: full
          ? 'تم إرجاع الفاتورة بالكامل — راجع شاشة مردودات المبيعات للتفاصيل'
          : 'تم إرجاع جزء من الفاتورة — راجع شاشة مردودات المبيعات للتفاصيل',
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
