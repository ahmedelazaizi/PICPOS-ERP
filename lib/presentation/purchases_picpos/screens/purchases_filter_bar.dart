// ignore_for_file: library_private_types_in_public_api
// نسخةُ PicPos من شريط ترشيح فواتير المشتريات — **مرآةُ شكلٍ** لتوأمِ
// المبيعات في `sales_invoices_picpos/screens/sales_filter_bar.dart`: بطاقةٌ
// واحدةٌ تحمل حبّاتٍ دائريّةً وشرائحَ حالةٍ بعدّادات، بدل حقولٍ وقوائمَ
// منسدلةٍ عارية و`SegmentedButton`.
//
// ⚠️ **وفرقان مقيسان لا منسوخان:**
//
// ‏١) **انتقاءُ الحالة أُحاديٌّ لا متعدّد.** المبيعاتُ تحمل
//    `statusFilters` (‏`Set<String>`) و`toggleStatusFilter`؛ والمشترياتُ تحمل
//    `statusFilter` (‏`String`) و`updateStatusFilter` وحدَهما، و`_applyFilters`
//    مبنيٌّ على `if/else if` أُحاديّ. فقلبُها إلى متعدّدٍ تغييرُ **منطقٍ** لا
//    شكل، ولا يطلبه التصميم. فالشريحةُ هنا تعمل انتقاءً أُحاديّاً: نقرُ
//    المنتقاةِ يعيد `all`، ونقرُ غيرِها يحلّ محلَّها.
//
// ‏٢) **لا حبّةَ فرز.** `PurchaseInvoicesScreenState` لا تحمل `sortMode`
//    إطلاقاً — ولا نظيرَ لـ`SalesInvoiceSortMode`. وإضافةُ قائمةٍ لا تفرز
//    شيئاً كانت زخرفاً يكذب.
part of 'purchases_picpos_screen.dart';

/// حبّةٌ دائريّةٌ تحمل قائمةً منسدلة — `filterChips` في التصميم.
///
/// `DropdownButton` مغلَّفٌ لا مُعاد بناؤه: القائمةُ وسلوكُ لوحة المفاتيح
/// وإمكانيةُ الوصول تبقى من Material، والحبّةُ غلافٌ بصريٌّ فوقها.
class _PurFilterPill<T> extends StatelessWidget {
  const _PurFilterPill({
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
    final muted = _purMuted(context);
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
class _PurStatusChip extends StatelessWidget {
  const _PurStatusChip({
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

  /// `null` ⇒ لا عدّادَ يُعرض. وهو الحالُ قبل أن يصل تجميعُ SQL (ولا يصل إلّا
  /// مع مدىً تاريخيٍّ مختار) — وعرضُ «‏0» حينئذٍ كان سيقول «لا فواتيرَ بهذه
  /// الحالة» وهو ما لم يُقَس بعد.
  final int? count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // غيرُ المنتقاة تبقى محايدةً كي يبقى اللونُ دالّاً على **الانتقاء** لا
    // على الحالة وحدَها — وإلّا بدت الثلاثةُ منتقاةً دائماً.
    final fg = selected ? color : _purMuted(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: .12) : theme.cardColor,
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

class PurchasesFilterBar extends ConsumerWidget {
  final TextEditingController searchController;
  final FocusNode searchFocusNode;

  const PurchasesFilterBar({
    super.key,
    required this.searchController,
    required this.searchFocusNode,
  });

  /// نفسُ الأكواد الثلاثة التي يفهمها `_applyFilters` حرفاً بحرف — و`all`
  /// ليست شريحةً بل غيابُ انتقاء.
  static const _statuses = [
    ('paid', 'مدفوع', AppColors.success),
    ('partial', 'جزئي', AppColors.warning),
    ('unpaid', 'غير مدفوع', AppColors.error),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusFilter = ref.watch(
        purchaseInvoicesControllerProvider.select((s) => s.statusFilter));
    final statusCounts = ref.watch(
        purchaseInvoicesControllerProvider.select((s) => s.statusCounts));
    final dateRange = ref
        .watch(purchaseInvoicesControllerProvider.select((s) => s.dateRange));
    final selectedWarehouseId = ref.watch(purchaseInvoicesControllerProvider
        .select((s) => s.selectedWarehouseId));
    final selectedBranchId = ref.watch(
        purchaseInvoicesControllerProvider.select((s) => s.selectedBranchId));
    final selectedCostCenterId = ref.watch(purchaseInvoicesControllerProvider
        .select((s) => s.selectedCostCenterId));
    final controller = ref.read(purchaseInvoicesControllerProvider.notifier);
    final warehousesAsync = ref.watch(allWarehousesProvider);
    final branchesAsync = ref.watch(allBranchesProvider);
    final costCentersAsync = ref.watch(allCostCentersProvider);

    final theme = Theme.of(context);
    final muted = _purMuted(context);

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
                  // ‏`_applyFilters` يطابق رقمَ الفاتورة **واسمَ المورد**
                  // معاً، فالتلميحُ يذكرهما — والأصلُ كان يذكر الرقمَ وحدَه
                  // فيبدو البحثُ بالاسم كأنه لا يعمل.
                  hintText: 'بحث برقم الفاتورة أو اسم المورد...',
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
                            : 'كل التواريخ',
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
                  child: _PurFilterPill<int?>(
                    label: 'الفرع',
                    value: selectedBranchId,
                    items: [
                      const DropdownMenuItem(value: null, child: Text('الكل')),
                      ...branches.map((b) =>
                          DropdownMenuItem(value: b.id, child: Text(b.name))),
                    ],
                    onChanged: (v) => controller.updateBranchFilter(v),
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
                  child: _PurFilterPill<int?>(
                    label: 'المخزن',
                    value: selectedWarehouseId,
                    items: [
                      const DropdownMenuItem(value: null, child: Text('الكل')),
                      ...warehouses.map((w) =>
                          DropdownMenuItem(value: w.id, child: Text(w.name))),
                    ],
                    onChanged: (v) => controller.updateWarehouseFilter(v),
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
                return _PurFilterPill<int?>(
                  label: 'مركز التكلفة',
                  value: selectedCostCenterId,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('الكل')),
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

            // ── شرائحُ الحالة — انتقاءٌ أُحاديّ، وإعادةُ النقر تعيد «الكل» ──
            for (final (code, label, color) in _statuses) ...[
              _PurStatusChip(
                label: label,
                color: color,
                selected: statusFilter == code,
                count: statusCounts[code],
                onTap: () => controller.updateStatusFilter(
                  statusFilter == code ? 'all' : code,
                ),
              ),
              const SizedBox(width: 6),
            ],
          ],
        ),
      ),
    );
  }
}
