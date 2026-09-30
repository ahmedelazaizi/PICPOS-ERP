// ignore_for_file: library_private_types_in_public_api
part of '../../sales_invoices_screen.dart';

class SalesFilterBar extends ConsumerWidget {
  final TextEditingController searchController;
  final FocusNode searchFocusNode;

  const SalesFilterBar({
    super.key,
    required this.searchController,
    required this.searchFocusNode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusFilters = ref.watch(salesInvoicesControllerProvider.select((s) => s.statusFilters));
    final dateRange = ref.watch(salesInvoicesControllerProvider.select((s) => s.dateRange));
    final selectedWarehouseId = ref.watch(salesInvoicesControllerProvider.select((s) => s.selectedWarehouseId));
    final selectedBranchId = ref.watch(salesInvoicesControllerProvider.select((s) => s.selectedBranchId));
    final selectedCostCenterId = ref.watch(salesInvoicesControllerProvider.select((s) => s.selectedCostCenterId));
    final sortMode = ref.watch(salesInvoicesControllerProvider.select((s) => s.sortMode));
    final controller = ref.read(salesInvoicesControllerProvider.notifier);
    final warehousesAsync = ref.watch(allWarehousesProvider);
    final branchesAsync = ref.watch(allBranchesProvider);
    final costCentersAsync = ref.watch(allCostCentersProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Search
          Expanded(
            flex: 2,
            child: TextField(
              controller: searchController,
              focusNode: searchFocusNode,
              decoration: InputDecoration(
                hintText: tr('بحث برقم الفاتورة أو اسم العميل...'),
                prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                isDense: true,
              ),
              onChanged: (val) => controller.updateSearchQuery(val),
            ),
          ),
          const SizedBox(width: 12),
          // Date Range
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(PhosphorIconsBold.calendarBlank),
              label: Text(
                dateRange != null
                    ? '${dateRange.start.day}/${dateRange.start.month} - ${dateRange.end.day}/${dateRange.end.month}'
                    : tr('تاريخ'),
              ),
              onPressed: () async {
                final range = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                  initialDateRange: dateRange,
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
          if (dateRange != null) ...[
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(PhosphorIconsBold.x, size: 16),
              tooltip: tr('إلغاء فلتر التاريخ'),
              onPressed: () => controller.updateDateRange(null),
            ),
          ],
          const SizedBox(width: 12),
          // Branch Filter — show only when multiple branches exist
          branchesAsync.when(
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
                      value: selectedBranchId,
                      hint:  Text(tr('كل الفروع')),
                      isDense: true,
                      items: [
                         DropdownMenuItem(value: null, child: Text(tr('كل الفروع'))),
                        ...branches.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name))),
                      ],
                      onChanged: (v) {
                        // Issue 8 — surface the auto-clear of warehouse when
                        // its branch differs from the picked branch so the
                        // user understands why the warehouse chip just reset.
                        final whMap = ref.read(salesInvoicesControllerProvider).warehouseBranchId;
                        final cleared = controller.updateBranchFilter(v, warehouseBranchMap: whMap);
                        if (cleared) {
                          AppToast.show(
                            context,
                            tr('تم إلغاء فلتر المستودع لأنه يتبع فرعاً مختلفاً'),
                            type: ToastType.info,
                          );
                        }
                      },
                    ),
                  ),
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          // Warehouse Filter
          warehousesAsync.when(
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
                    value: selectedWarehouseId,
                    hint:  Text(tr('كل المستودعات')),
                    isDense: true,
                    items: [
                       DropdownMenuItem(value: null, child: Text(tr('كل المستودعات'))),
                      ...warehouses.map((w) => DropdownMenuItem(value: w.id, child: Text(trData(w.name)))),
                    ],
                    onChanged: (v) {
                      // Issue 8 — auto-clear branch when warehouse belongs
                      // to a different branch; surface the change with a toast.
                      final whBranch = v == null
                          ? null
                          : warehouses.firstWhere((w) => w.id == v).branchId;
                      final cleared = controller.updateWarehouseFilter(v, warehouseBranchId: whBranch);
                      if (cleared) {
                        AppToast.show(
                          context,
                          tr('تم إلغاء فلتر الفرع لأن المستودع يتبع فرعاً آخر'),
                          type: ToastType.info,
                        );
                      }
                    },
                  ),
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          const SizedBox(width: 12),
          // Cost Center Filter
          costCentersAsync.when(
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
                      value: selectedCostCenterId,
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
          // Cluster 025 / Issue 3: sort selector. The default `dateDesc`
          // matches the previous behaviour; `byClientReceiveOrder` groups
          // rows per client in the order the server received them — useful
          // when checking whether a specific client's outbox is keeping up.
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<SalesInvoiceSortMode>(
                value: sortMode,
                isDense: true,
                items:  [
                  DropdownMenuItem(
                    value: SalesInvoiceSortMode.dateDesc,
                    child: Text(tr('الأحدث أولاً')),
                  ),
                  DropdownMenuItem(
                    value: SalesInvoiceSortMode.byClientReceiveOrder,
                    child: Text(tr('ترتيب الاستقبال (لكل عميل)')),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) controller.updateSortMode(v);
                },
              ),
            ),
          ),
          const SizedBox(width: 0),
          // Status Filter — Issue 8: multi-select. Empty selection means
          // "show all" so the user doesn't need to remember an "all" segment.
          // Picking nothing == picking everything. Each chip is OR'd.
          Wrap(
            spacing: 6,
            children: [
              for (final entry in  [
                ('paid', tr('مدفوع')),
                ('partial', tr('جزئي')),
                ('unpaid', tr('غير مدفوع')),
              ])
                FilterChip(
                  label: Text(entry.$2),
                  selected: statusFilters.contains(entry.$1),
                  onSelected: (val) => controller.toggleStatusFilter(entry.$1, val),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
