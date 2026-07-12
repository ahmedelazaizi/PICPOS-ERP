import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../core/diagnostics/perf_trace.dart';
import '../../../../core/logging/diagnostic_logger.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/shimmer_loading.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../data/providers/inventory_providers.dart';
import '../../../products/providers/products_controller.dart';
import '../../../../data/providers/providers.dart';
import 'product_edit_dialog.dart';
import 'product_delete_dialog.dart';
import 'barcode_print_dialog.dart';
import '../../../../../../../core/constants/app_constants.dart';
import '../../../../domain/entities/product_entity.dart';
import '../../../../data/providers/manufacturing_providers.dart';

// ─── Column widths (Spec 032 v2 — flex distribution) ─────────────────────
//
// Strategy: when the viewport is wider than `_kFlexModeThreshold`, the
// table fits exactly inside the viewport (NO horizontal scroll) and the
// four flex columns (barcode/name/category/warehouse) divide the surplus
// proportionally to their flex factors. The vertical scrollbar then sits
// flush at the screen's right edge — operators don't have to scroll
// horizontally first to grab it. When the viewport is narrower than the
// threshold (rare on POS hardware, but supported for completeness), we
// fall back to a horizontal SingleChildScrollView with min column widths
// so cells don't visually break.
const double _kCheckboxColWidth = 40;
const double _kCodeColWidth = 70;
const double _kTypeColWidth = 80;
const double _kSalePriceColWidth = 80;
const double _kCostPriceColWidth = 80;
const double _kAvgCostColWidth = 90;
const double _kStockColWidth = 60;
const double _kStatusColWidth = 80;
const double _kActionsColWidth = 160;

// Min widths for the four flex columns (used in both flex and SCV modes
// to set the fall-back narrow-screen table width).
const double _kMinBarcodeWidth = 80;
const double _kMinNameWidth = 140;
const double _kMinCategoryWidth = 80;
const double _kMinWarehouseWidth = 80;

// Flex factors — proportional weights for distributing the viewport
// surplus. Name gets the lion's share.
const int _kBarcodeFlex = 2;
const int _kNameFlex = 4;
const int _kCategoryFlex = 2;
const int _kWarehouseFlex = 2;
const int _kFlexTotal =
    _kBarcodeFlex + _kNameFlex + _kCategoryFlex + _kWarehouseFlex;

const double _kFixedSum = _kCheckboxColWidth +
    _kCodeColWidth +
    _kTypeColWidth +
    _kSalePriceColWidth +
    _kCostPriceColWidth +
    _kAvgCostColWidth +
    _kStockColWidth +
    _kStatusColWidth +
    _kActionsColWidth;

const double _kMinFlexSum = _kMinBarcodeWidth +
    _kMinNameWidth +
    _kMinCategoryWidth +
    _kMinWarehouseWidth;

const double _kFlexModeThreshold = _kFixedSum + _kMinFlexSum;

const double _kRowHeight = 48;
const double _kHeaderHeight = 44;

class ProductsTable extends ConsumerStatefulWidget {
  final ScrollController scrollController;

  const ProductsTable({super.key, required this.scrollController});

  @override
  ConsumerState<ProductsTable> createState() => _ProductsTableState();
}

class _ProductsTableState extends ConsumerState<ProductsTable> {
  // Spec 030 — horizontal scroll is shared between the header and the body
  // when SCV-fallback mode is active (narrow viewport). In flex mode the
  // controller is unused but kept to avoid mid-build lifecycle churn.
  final ScrollController _hScrollController = ScrollController();

  // Spec 032 v3 diagnostic — rebuild counters help identify whether a
  // perceived scroll lag is caused by excessive whole-table rebuilds or
  // by per-row work. Emit every 10 rebuilds (plus the first 3) to
  // avoid flooding the console.
  final _tableBuilds = PerfRebuildCounter('products_table', everyN: 10);
  final _layoutBuilds = PerfRebuildCounter('products_table.layout', everyN: 50);

  @override
  void dispose() {
    _hScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _tableBuilds.tick();
    final buildSw = kPerfDebug ? (Stopwatch()..start()) : null;
    // Spec 030 — narrow watches: each `.select` returns a primitive so the
    // table only rebuilds when the *visible* items list, loading flag, or
    // error string actually change. `selectedIds` is intentionally NOT
    // watched here — selection toggles are observed by individual rows
    // (`_ProductRow`) and by the header's `_HeaderCheckbox` so a single
    // toggle never rebuilds the whole table.
    final products = ref.watch(productsControllerProvider.select((s) => s.items));
    final isLoading = ref.watch(productsControllerProvider.select((s) => s.isLoading));
    final error = ref.watch(productsControllerProvider.select((s) => s.error));

    // Spec 032 v3 — cached lookup maps (computed once per data change,
    // not per parent rebuild). The previous inline construction was
    // ~30-80ms per frame on the user's POS device because every
    // loadNextPage cycle re-constructed the Maps from scratch.
    final categoryMap = ref.watch(categoryNameMapProvider);
    final lockedCategoryIds = ref.watch(lockedCategoryIdsProvider);
    final warehouseMap = ref.watch(warehouseNameMapProvider);

    if (isLoading && products.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: ShimmerLoading.list(itemCount: 6),
      );
    }

    if (error != null && products.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(PhosphorIconsBold.warning, size: 48, color: AppColors.error),
              const SizedBox(height: 12),
              Text(
                error,
                style: const TextStyle(color: AppColors.error, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => ref
                    .read(productsControllerProvider.notifier)
                    .loadNextPage(isRefresh: true),
                icon: const Icon(PhosphorIconsBold.arrowClockwise, size: 16),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    if (!isLoading && products.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(PhosphorIconsBold.package,
                  size: 48, color: AppColors.textMuted.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              const Text(
                'لا توجد أصناف بعد',
                style: TextStyle(color: AppColors.textMuted, fontSize: 16),
              ),
              const SizedBox(height: 8),
              const Text(
                'اضغط "إضافة صنف" لإنشاء أول صنف',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    if (buildSw != null) {
      buildSw.stop();
      final us = buildSw.elapsedMicroseconds;
      if (us > 5000) {
        // Anything over 5 ms warrants a log line — at 60 fps we have
        // a 16.6 ms budget for the WHOLE frame's build phase.
        unawaited(DiagnosticLogger.log(
          'PERF',
          'products_table sync-build: ${(us / 1000).toStringAsFixed(1)}ms',
        ));
      }
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        _layoutBuilds.tick();
        final viewportWidth = constraints.maxWidth;
        final useFlex = viewportWidth >= _kFlexModeThreshold;

        // Compute concrete pixel widths for the four flex columns.
        // - Flex mode: viewport surplus split by flex factors.
        // - SCV fallback: use minimum widths; total exceeds viewport so a
        //   horizontal scroll engages.
        late final double barcodeWidth;
        late final double nameWidth;
        late final double categoryWidth;
        late final double warehouseWidth;
        if (useFlex) {
          final flexAvailable = viewportWidth - _kFixedSum;
          final unit = flexAvailable / _kFlexTotal;
          barcodeWidth = unit * _kBarcodeFlex;
          nameWidth = unit * _kNameFlex;
          categoryWidth = unit * _kCategoryFlex;
          warehouseWidth = unit * _kWarehouseFlex;
        } else {
          barcodeWidth = _kMinBarcodeWidth;
          nameWidth = _kMinNameWidth;
          categoryWidth = _kMinCategoryWidth;
          warehouseWidth = _kMinWarehouseWidth;
        }
        final totalWidth = useFlex
            ? viewportWidth
            : _kFixedSum +
                barcodeWidth +
                nameWidth +
                categoryWidth +
                warehouseWidth;

        final tableContent = Column(
          children: [
            _ProductsTableHeader(
              barcodeWidth: barcodeWidth,
              nameWidth: nameWidth,
              categoryWidth: categoryWidth,
              warehouseWidth: warehouseWidth,
            ),
            Expanded(
              child: ListView.builder(
                controller: widget.scrollController,
                itemCount: products.length,
                itemExtent: _kRowHeight,
                itemBuilder: (ctx, i) {
                  final p = products[i];
                  return _ProductRow(
                    key: ValueKey(p.id),
                    product: p,
                    categoryMap: categoryMap,
                    warehouseMap: warehouseMap,
                    lockedCategoryIds: lockedCategoryIds,
                    barcodeWidth: barcodeWidth,
                    nameWidth: nameWidth,
                    categoryWidth: categoryWidth,
                    warehouseWidth: warehouseWidth,
                    isStriped: i.isOdd,
                  );
                },
              ),
            ),
          ],
        );

        // Flex mode: NO SingleChildScrollView. The vertical scrollbar
        // attaches to the ListView's controller via a single Scrollbar
        // wrapper; its bounds equal the viewport, so the thumb sits flush
        // at the screen's right edge — no need to scroll horizontally to
        // see or grab it (the original user complaint).
        // SCV fallback: keep the proven 030 nesting for narrow screens.
        return Stack(
          children: [
            if (useFlex)
              Scrollbar(
                controller: widget.scrollController,
                thumbVisibility: true,
                child: tableContent,
              )
            else
              Scrollbar(
                controller: _hScrollController,
                thumbVisibility: true,
                notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
                child: SingleChildScrollView(
                  controller: _hScrollController,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: totalWidth,
                    child: Column(
                      children: [
                        _ProductsTableHeader(
                          barcodeWidth: barcodeWidth,
                          nameWidth: nameWidth,
                          categoryWidth: categoryWidth,
                          warehouseWidth: warehouseWidth,
                        ),
                        Expanded(
                          child: Scrollbar(
                            controller: widget.scrollController,
                            thumbVisibility: true,
                            child: ListView.builder(
                              controller: widget.scrollController,
                              itemCount: products.length,
                              itemExtent: _kRowHeight,
                              itemBuilder: (ctx, i) {
                                final p = products[i];
                                return _ProductRow(
                                  key: ValueKey(p.id),
                                  product: p,
                                  categoryMap: categoryMap,
                                  warehouseMap: warehouseMap,
                                  lockedCategoryIds: lockedCategoryIds,
                                  barcodeWidth: barcodeWidth,
                                  nameWidth: nameWidth,
                                  categoryWidth: categoryWidth,
                                  warehouseWidth: warehouseWidth,
                                  isStriped: i.isOdd,
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (isLoading)
              const Positioned(
                bottom: 8,
                right: 8,
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        );
      },
    );
  }

}

/// Sticky header row. `_HeaderCheckbox` is a separate ConsumerWidget so that
/// the master checkbox's tristate updates without rebuilding the rest of
/// the header (and without the parent watching `selectedIds`).
class _ProductsTableHeader extends StatelessWidget {
  const _ProductsTableHeader({
    required this.barcodeWidth,
    required this.nameWidth,
    required this.categoryWidth,
    required this.warehouseWidth,
  });

  final double barcodeWidth;
  final double nameWidth;
  final double categoryWidth;
  final double warehouseWidth;

  @override
  Widget build(BuildContext context) {
    final headerStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w700,
        );
    return Container(
      height: _kHeaderHeight,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: const Border(
          bottom: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: _kCheckboxColWidth,
            child: Center(child: _HeaderCheckbox()),
          ),
          _headerCell('الكود', _kCodeColWidth, headerStyle),
          _headerCell('الباركود', barcodeWidth, headerStyle),
          _headerCell('اسم الصنف', nameWidth, headerStyle),
          _headerCell('التصنيف', categoryWidth, headerStyle),
          _headerCell('نوع الصنف', _kTypeColWidth, headerStyle),
          _headerCell('المخزن', warehouseWidth, headerStyle),
          _headerCell('سعر البيع', _kSalePriceColWidth, headerStyle, alignEnd: true),
          _headerCell('سعر التكلفة', _kCostPriceColWidth, headerStyle, alignEnd: true),
          _headerCell('متوسط التكلفة', _kAvgCostColWidth, headerStyle, alignEnd: true),
          _headerCell('الرصيد', _kStockColWidth, headerStyle, alignEnd: true),
          _headerCell('الحالة', _kStatusColWidth, headerStyle),
          _headerCell('إجراءات', _kActionsColWidth, headerStyle),
        ],
      ),
    );
  }

  Widget _headerCell(String text, double width, TextStyle? style,
      {bool alignEnd = false}) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Align(
          alignment: alignEnd ? Alignment.centerLeft : Alignment.centerRight,
          child: Text(text, style: style, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }
}

/// Master tristate checkbox. Watches a *summary* of the selection state via
/// `.select` returning a record so the only rebuild trigger is when the
/// summary value itself changes — not on every selection toggle that leaves
/// the summary intact.
class _HeaderCheckbox extends ConsumerWidget {
  const _HeaderCheckbox();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(productsControllerProvider.select((s) {
      if (s.items.isEmpty) return (allSelected: false, anySelected: false);
      final allSel = s.items.every((p) => s.selectedIds.contains(p.id));
      return (allSelected: allSel, anySelected: s.selectedIds.isNotEmpty);
    }));
    return Checkbox(
      value: summary.allSelected,
      tristate: summary.anySelected && !summary.allSelected,
      onChanged: (val) {
        if (val == true) {
          ref.read(productsControllerProvider.notifier).selectAll();
        } else {
          ref.read(productsControllerProvider.notifier).clearSelection();
        }
      },
    );
  }
}

/// One product row. ConsumerWidget so it can `.select` only the slices of
/// state that affect *this* row — selection state for product.id and the
/// avg-cost entry for product.id. Other rows' selection or cost changes
/// do not rebuild this row.
class _ProductRow extends ConsumerWidget {
  const _ProductRow({
    super.key,
    required this.product,
    required this.categoryMap,
    required this.warehouseMap,
    required this.lockedCategoryIds,
    required this.barcodeWidth,
    required this.nameWidth,
    required this.categoryWidth,
    required this.warehouseWidth,
    required this.isStriped,
  });

  final ProductEntity product;
  final Map<int, String> categoryMap;
  final Map<int, String> warehouseMap;
  final Set<int> lockedCategoryIds;
  final double barcodeWidth;
  final double nameWidth;
  final double categoryWidth;
  final double warehouseWidth;
  final bool isStriped;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSelected = ref.watch(productsControllerProvider
        .select((s) => s.selectedIds.contains(product.id)));

    // `.select` returns a record so a change in another product's avg cost
    // produces a structurally-equal record for THIS row → no rebuild.
    final avgCostState = ref.watch(weightedAverageCostProvider.select((async) {
      return async.when(
        data: (m) => (loading: false, value: m[product.id]),
        loading: () => (loading: true, value: null),
        error: (_, _) => (loading: false, value: null),
      );
    }));

    final bgColor = isSelected
        ? AppColors.primary.withValues(alpha: 0.08)
        : (isStriped
            ? Theme.of(context).colorScheme.surface.withValues(alpha: 0.4)
            : Colors.transparent);

    return Material(
      color: bgColor,
      child: InkWell(
        onTap: () => ref
            .read(productsControllerProvider.notifier)
            .toggleSelection(product.id),
        child: Container(
          height: _kRowHeight,
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.border, width: 0.5),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: _kCheckboxColWidth,
                child: Center(
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (_) => ref
                        .read(productsControllerProvider.notifier)
                        .toggleSelection(product.id),
                  ),
                ),
              ),
              _textCell(product.code, _kCodeColWidth),
              _textCell(product.barcode ?? '-', barcodeWidth),
              _textCell(product.name, nameWidth, tooltip: product.name),
              _textCell(
                product.categoryId == null
                    ? '-'
                    : (categoryMap[product.categoryId!] ?? '-'),
                categoryWidth,
                fontSize: 12,
                tooltip: product.categoryId == null
                    ? null
                    : categoryMap[product.categoryId!],
              ),
              SizedBox(
                width: _kTypeColWidth,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _ProductTypeBadge(type: product.productType),
                  ),
                ),
              ),
              _textCell(
                product.warehouseId == null
                    ? '-'
                    : (warehouseMap[product.warehouseId!] ?? '-'),
                warehouseWidth,
                fontSize: 12,
                tooltip: product.warehouseId == null
                    ? null
                    : warehouseMap[product.warehouseId!],
              ),
              _textCell(
                '${product.salePrice.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                _kSalePriceColWidth,
                alignEnd: true,
              ),
              _textCell(
                '${product.costPrice.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                _kCostPriceColWidth,
                alignEnd: true,
              ),
              SizedBox(
                width: _kAvgCostColWidth,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _AvgCostCell(
                      loading: avgCostState.loading,
                      value: avgCostState.value,
                      product: product,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: _kStockColWidth,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      product.currentStock.toStringAsFixed(0),
                      style: TextStyle(
                        color: product.currentStock <= product.minStock
                            ? AppColors.error
                            : AppColors.textPrimary,
                        fontWeight: product.currentStock <= product.minStock
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: _kStatusColWidth,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _StatusBadge(
                      product: product,
                      lockedCategoryIds: lockedCategoryIds,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: _kActionsColWidth,
                child: _ProductActions(product: product),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _textCell(
    String text,
    double width, {
    double fontSize = 14,
    bool alignEnd = false,
    String? tooltip,
  }) {
    final child = Text(
      text,
      style: TextStyle(fontSize: fontSize),
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    );
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Align(
          alignment: alignEnd ? Alignment.centerLeft : Alignment.centerRight,
          child: tooltip == null ? child : Tooltip(message: tooltip, child: child),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.product, required this.lockedCategoryIds});

  final ProductEntity product;
  final Set<int> lockedCategoryIds;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final isCategoryLocked =
        p.categoryId != null && lockedCategoryIds.contains(p.categoryId);
    final isExplicitlyUnlocked = p.isLocked; // true means explicitly UNLOCKED
    final effectivelyActive =
        p.isActive && (!isCategoryLocked || isExplicitlyUnlocked);

    String statusText;
    String tooltipText;
    if (!p.isActive) {
      statusText = 'غير نشط';
      tooltipText = 'الصنف غير نشط';
    } else if (isCategoryLocked && !isExplicitlyUnlocked) {
      statusText = 'تصنيف مقفل';
      tooltipText = 'التصنيف مقفل - اضغط على زر الفتح لفتح هذا الصنف فقط';
    } else if (isCategoryLocked && isExplicitlyUnlocked) {
      statusText = 'مستثنى ✓';
      tooltipText = 'الصنف مفتوح رغم قفل التصنيف';
    } else {
      statusText = 'نشط';
      tooltipText = 'الصنف نشط';
    }

    return Tooltip(
      message: tooltipText,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: effectivelyActive
              ? (isCategoryLocked
                  ? AppColors.warning.withValues(alpha: 0.1)
                  : AppColors.success.withValues(alpha: 0.1))
              : AppColors.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isCategoryLocked && !isExplicitlyUnlocked)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(
                  PhosphorIconsBold.lock,
                  size: 10,
                  color: AppColors.error,
                ),
              ),
            Text(
              statusText,
              style: TextStyle(
                color: effectivelyActive
                    ? (isCategoryLocked ? AppColors.warning : AppColors.success)
                    : AppColors.error,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductTypeBadge extends StatelessWidget {
  const _ProductTypeBadge({required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final label = switch (type) {
      'raw_material' => 'خامة',
      'finished_goods' => 'منتج تام',
      'service' => 'خدمة',
      _ => 'عام',
    };
    final color = switch (type) {
      'raw_material' => AppColors.warning,
      'finished_goods' => AppColors.success,
      'service' => AppColors.info,
      _ => AppColors.textSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _AvgCostCell extends StatelessWidget {
  const _AvgCostCell({
    required this.loading,
    required this.value,
    required this.product,
  });

  final bool loading;
  final double? value;
  final ProductEntity product;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 1),
      );
    }
    if (value == null) {
      return const Text('-', style: TextStyle(color: AppColors.textMuted));
    }
    final diff = product.costPrice > 0
        ? ((value! - product.costPrice) / product.costPrice * 100)
        : 0.0;
    return Tooltip(
      message: 'الفرق عن سعر التكلفة الحالي: ${diff.toStringAsFixed(1)}%',
      child: Text(
        '${value!.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
        style: TextStyle(
          fontSize: 12,
          color: diff.abs() > 10 ? AppColors.warning : AppColors.textPrimary,
          fontWeight: diff.abs() > 10 ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}

class _ProductActions extends ConsumerWidget {
  const _ProductActions({required this.product});

  final ProductEntity product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _iconButton(
          icon: product.isLocked
              ? PhosphorIconsBold.lockOpen
              : PhosphorIconsBold.lock,
          color: product.isLocked ? AppColors.success : AppColors.textSecondary,
          tooltip: product.isLocked ? 'إلغاء الاستثناء' : 'استثناء من قفل التصنيف',
          onPressed: () => _toggleLock(context, ref),
        ),
        _iconButton(
          icon: PhosphorIconsBold.pencil,
          color: AppColors.primary,
          onPressed: () => showDialog(
            context: context,
            builder: (_) => ProductEditDialog(product: product),
          ),
        ),
        _iconButton(
          icon: PhosphorIconsBold.trash,
          color: AppColors.error,
          onPressed: () => showDialog(
            context: context,
            builder: (_) => ProductDeleteDialog(product: product),
          ),
        ),
        _iconButton(
          icon: PhosphorIconsBold.barcode,
          color: AppColors.warning,
          tooltip: 'طباعة الباركود',
          onPressed: () => BarcodePrintDialog.show(context, product),
        ),
      ],
    );
  }

  Widget _iconButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    String? tooltip,
  }) {
    return IconButton(
      icon: Icon(icon),
      iconSize: 18,
      color: color,
      tooltip: tooltip,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      onPressed: onPressed,
    );
  }

  Future<void> _toggleLock(BuildContext context, WidgetRef ref) async {
    final updated = product.copyWith(isLocked: !product.isLocked);
    final success = await ref
        .read(productsControllerProvider.notifier)
        .updateProduct(updated);
    if (context.mounted && success) {
      AppToast.show(
        context,
        !product.isLocked
            ? 'تم استثناء الصنف - سيظهر في نقطة البيع حتى لو التصنيف مقفل'
            : 'تم إلغاء الاستثناء - الصنف يتبع حالة التصنيف',
        type: ToastType.warning,
      );
    }
  }
}
