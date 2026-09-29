// ignore_for_file: library_private_types_in_public_api
// نسخةُ PicPos من شريط ترشيح الفواتير. المنطقُ (المرشِّحاتُ ونداءاتُ
// المتحكّم وتنبيهاتُ الإلغاء التلقائيّ) يبقى مطابقاً لتوأمِ UralCash في
// `screens/widgets/sales_invoices/sales_filter_bar.dart` — وأيُّ إصلاحٍ
// منطقيٍّ يتصلّح في المصدر أوّلاً ثمّ patch (مصيدة النسخ §٥.٨).
//
// ⚠️ **والشكلُ وحدَه هو الذي تباعد** (تصميمُ PicPos 2026-08-21): الشريطُ صار
// بطاقةً واحدةً تحمل حبّاتٍ دائريّةً بدل حقولٍ وقوائمَ منسدلةٍ عارية. ولا
// مرشِّحَ أُضيف ولا حُذف: البحثُ والتاريخُ والفرعُ والمخزنُ ومركزُ التكلفة
// والفرزُ وشرائحُ الحالة — الستّةُ كما هي بنفس النداءات.
part of 'sales_invoices_picpos_screen.dart';

/// حبّةٌ دائريّةٌ تحمل قائمةً منسدلة — `filterChips` في التصميم.
///
/// `DropdownButton` مغلَّفٌ لا مُعاد بناؤه: القائمةُ وسلوكُ لوحة المفاتيح
/// وإمكانيةُ الوصول تبقى من Material، والحبّةُ غلافٌ بصريٌّ فوقها.
class _FilterPill<T> extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = _mutedOf(context);
    return Container(
      height: 36,
      padding: const EdgeInsetsDirectional.only(start: 13, end: 9),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: muted,
            ),
          ),
          const SizedBox(width: 7),
          DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isDense: true,
              borderRadius: BorderRadius.circular(12),
              icon: Icon(PhosphorIconsBold.caretDown, size: 11, color: muted),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: theme.textTheme.bodyMedium?.color,
              ),
              items: items,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// شريحةُ حالةٍ ملوّنةٌ بمعناها ومعها عدّادُها — `statusChips` في التصميم.
class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
    this.count,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  /// `null` ⇒ لا عدّادَ يُعرض. وهو الحالُ قبل أن يصل تجميعُ SQL — عرضُ «‏0»
  /// حينئذٍ كان سيقول «لا فواتيرَ بهذه الحالة» وهو ما لم يُقَس بعد.
  final int? count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // غيرُ المنتقاة تبقى محايدةً كي يبقى اللونُ دالّاً على **الانتقاء** لا
    // على الحالة وحدَها — وإلّا بدت الثلاثةُ منتقاةً دائماً.
    final fg = selected ? color : _mutedOf(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: .12)
                : theme.cardColor,
            border: Border.all(
              color: selected
                  ? color.withValues(alpha: .40)
                  : theme.dividerColor,
            ),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: fg.withValues(alpha: .6),
                    fontFeatures: const [ui.FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class SalesFilterBar extends ConsumerWidget {
  final TextEditingController searchController;
  final FocusNode searchFocusNode;

  const SalesFilterBar({
    super.key,
    required this.searchController,
    required this.searchFocusNode,
  });

  static List<(String, String, Color)> get _statuses => [
    ('paid', tr('مدفوع'), AppColors.success),
    ('partial', tr('جزئي'), AppColors.warning),
    ('unpaid', tr('غير مدفوع'), AppColors.error),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusFilters = ref.watch(
        salesInvoicesControllerProvider.select((s) => s.statusFilters));
    final statusCounts = ref.watch(
        salesInvoicesControllerProvider.select((s) => s.statusCounts));
    final dateRange = ref
        .watch(salesInvoicesControllerProvider.select((s) => s.dateRange));
    final selectedWarehouseId = ref.watch(
        salesInvoicesControllerProvider.select((s) => s.selectedWarehouseId));
    final selectedBranchId = ref.watch(
        salesInvoicesControllerProvider.select((s) => s.selectedBranchId));
    final selectedCostCenterId = ref.watch(
        salesInvoicesControllerProvider.select((s) => s.selectedCostCenterId));
    final sortMode =
        ref.watch(salesInvoicesControllerProvider.select((s) => s.sortMode));
    final controller = ref.read(salesInvoicesControllerProvider.notifier);
    final warehousesAsync = ref.watch(allWarehousesProvider);
    final branchesAsync = ref.watch(allBranchesProvider);
    final costCentersAsync = ref.watch(allCostCentersProvider);

    final theme = Theme.of(context);
    final muted = _mutedOf(context);

    Widget divider() => Container(
          width: 1,
          height: 24,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          color: theme.dividerColor,
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.cardColor,
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            // ── البحث ───────────────────────────────────────────────────
            SizedBox(
              width: 260,
              height: 36,
              child: TextField(
                controller: searchController,
                focusNode: searchFocusNode,
                style: const TextStyle(fontSize: 12.5),
                decoration: InputDecoration(
                  hintText: tr('بحث برقم الفاتورة أو اسم العميل...'),
                  hintStyle: TextStyle(fontSize: 12.5, color: muted),
                  prefixIcon: Icon(PhosphorIconsBold.magnifyingGlass,
                      size: 15, color: muted),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                  filled: true,
                  fillColor: theme.inputDecorationTheme.fillColor,
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: BorderSide.none,
                  ),
                  isDense: true,
                ),
                onChanged: (val) => controller.updateSearchQuery(val),
              ),
            ),
            const SizedBox(width: 8),

            // ── مدى التاريخ ─────────────────────────────────────────────
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () async {
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
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: theme.inputDecorationTheme.fillColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(PhosphorIconsBold.calendarBlank,
                          size: 14, color: AppColors.primary),
                      const SizedBox(width: 7),
                      Text(
                        dateRange != null
                            ? '${dateRange.start.day}/${dateRange.start.month}'
                                ' — ${dateRange.end.day}/${dateRange.end.month}'
                            : tr('كل التواريخ'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: theme.textTheme.bodyMedium?.color,
                        ),
                      ),
                      // زرُّ المسح داخل الحبّة — ولا يظهر بلا مدىً مختار،
                      // فلا يُعرض إجراءٌ لا أثرَ له.
                      if (dateRange != null) ...[
                        const SizedBox(width: 7),
                        InkWell(
                          onTap: () => controller.updateDateRange(null),
                          borderRadius: BorderRadius.circular(999),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(PhosphorIconsBold.x,
                                size: 12, color: muted),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            divider(),

            // ── الفرع (يظهر عند تعدّد الفروع فقط) ───────────────────────
            branchesAsync.when(
              data: (branches) {
                if (branches.length <= 1) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: _FilterPill<int?>(
                    label: tr('الفرع'),
                    value: selectedBranchId,
                    items: [
                       DropdownMenuItem(value: null, child: Text(tr('الكل'))),
                      ...branches.map((b) =>
                          DropdownMenuItem(value: b.id, child: Text(b.name))),
                    ],
                    onChanged: (v) {
                      // Issue 8 — surface the auto-clear of warehouse when
                      // its branch differs from the picked branch so the
                      // user understands why the warehouse chip just reset.
                      final whMap = ref
                          .read(salesInvoicesControllerProvider)
                          .warehouseBranchId;
                      final cleared = controller.updateBranchFilter(v,
                          warehouseBranchMap: whMap);
                      if (cleared) {
                        AppToast.show(
                          context,
                          tr('تم إلغاء فلتر المستودع لأنه يتبع فرعاً مختلفاً'),
                          type: ToastType.info,
                        );
                      }
                    },
                  ),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
            ),

            // ── المخزن ──────────────────────────────────────────────────
            warehousesAsync.when(
              data: (warehouses) {
                if (warehouses.length <= 1) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: _FilterPill<int?>(
                    label: tr('المخزن'),
                    value: selectedWarehouseId,
                    items: [
                       DropdownMenuItem(value: null, child: Text(tr('الكل'))),
                      ...warehouses.map((w) =>
                          DropdownMenuItem(value: w.id, child: Text(w.name))),
                    ],
                    onChanged: (v) {
                      // Issue 8 — auto-clear branch when warehouse belongs
                      // to a different branch; surface the change with a toast.
                      final whBranch = v == null
                          ? null
                          : warehouses.firstWhere((w) => w.id == v).branchId;
                      final cleared = controller.updateWarehouseFilter(v,
                          warehouseBranchId: whBranch);
                      if (cleared) {
                        AppToast.show(
                          context,
                          tr('تم إلغاء فلتر الفرع لأن المستودع يتبع فرعاً آخر'),
                          type: ToastType.info,
                        );
                      }
                    },
                  ),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
            ),

            // ── مركز التكلفة ────────────────────────────────────────────
            costCentersAsync.when(
              data: (centers) {
                if (centers.isEmpty) return const SizedBox.shrink();
                return _FilterPill<int?>(
                  label: tr('مركز التكلفة'),
                  value: selectedCostCenterId,
                  items: [
                     DropdownMenuItem(value: null, child: Text(tr('الكل'))),
                    ...centers.map((c) =>
                        DropdownMenuItem(value: c.id, child: Text(c.name))),
                  ],
                  onChanged: (v) => controller.updateCostCenterFilter(v),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
            ),

            const Spacer(),

            // ── شرائحُ الحالة — Issue 8: انتقاءٌ متعدّد، والفراغُ = الكل ──
            for (final (code, label, color) in _statuses) ...[
              _StatusChip(
                label: label,
                color: color,
                selected: statusFilters.contains(code),
                count: statusCounts[code],
                onTap: () => controller.toggleStatusFilter(
                  code,
                  !statusFilters.contains(code),
                ),
              ),
              const SizedBox(width: 6),
            ],

            divider(),

            // ── الفرز — Cluster 025 / Issue 3 ───────────────────────────
            Container(
              height: 36,
              padding: const EdgeInsetsDirectional.only(start: 12, end: 8),
              decoration: BoxDecoration(
                border: Border.all(color: theme.dividerColor),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(PhosphorIconsBold.sortDescending,
                      size: 14, color: muted),
                  const SizedBox(width: 7),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<SalesInvoiceSortMode>(
                      value: sortMode,
                      isDense: true,
                      borderRadius: BorderRadius.circular(12),
                      icon: Icon(PhosphorIconsBold.caretDown,
                          size: 11, color: muted),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.textTheme.bodyMedium?.color,
                      ),
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
