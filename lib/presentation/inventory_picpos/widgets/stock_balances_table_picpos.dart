// جدولُ أرصدة المخزون بهويّة PicPos — **فوركٌ بقرار المالك 2026-08-22**
// («انسخه إلى PicPos ولا تشارك تعديلاتِ PicPos على UralCash»).
//
// المصدر: `lib/presentation/screens/inventory/widgets/stock_balances_table.dart`
// ويبقى بلا مساسٍ لشاشة UralCash.
//
// ⚠️ **و`inventory_notifier` لم يُفرَك عمداً.** هو حالةٌ ومنطقُ ترشيحٍ لا
// تصميم، ويقرؤه شريطُ الفلاتر المشتركُ وجدولُ الحركات معاً. فنسخُه كان
// سيُنشئ حالةً ثانيةً تنحرف عن الأولى — والقرارُ يمنع مشاركةَ **التعديل** مع
// UralCash، لا يأمر بمضاعفةِ المحرّك.
//
// ما تغيّر: عمقُ الاستيراد، اسمُ الصنف العامّ، وشريطُ امتلاءِ المخزون تحت
// الرصيد (‏`barW`/`barC` في التصميم). ولا منطقَ تغيّر.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../domain/models/picpos_product_view.dart';
import '../../../core/diagnostics/perf_trace.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/product_entity.dart';
import '../../../core/widgets/shimmer_loading.dart';
import '../../../data/providers/providers.dart';
import '../../screens/inventory/inventory_notifier.dart';

// ─── Column widths (Spec 032 v2 — flex distribution) ─────────────────────
//
// Same flex-on-wide / SCV-on-narrow approach as products_table. Three
// flex columns (barcode, name, category); the rest are fixed pixel
// widths. The vertical scrollbar sits flush at the screen's right edge
// in flex mode (no horizontal scroll engages).
const double _kCodeColWidth = 70;
const double _kUnitColWidth = 60;

// ⚠️ **٧٠ → ١٦٠.** خليّةُ المخزون في هذا الفورك صارت سطرَين (الرصيدُ وبجانبه
// «حد أدنى …»، وتحتهما شريطُ الامتلاء) بدل رقمٍ واحد. وعمودُ التصميم `1.5fr`
// أعرضُ من الرقم المفرد بكثير. تُركت ٧٠ فكان الصفُّ يفيض في كلّ سطر.
// و`_kFixedSum` أدناه يقرأ الثابتَ فيتحرّك معه تلقائيّاً — والعتبةُ كذلك.
const double _kStockColWidth = 160;
const double _kStatusColWidth = 80;
const double _kExpiryColWidth = 110;
const double _kActionsColWidth = 100;

const double _kMinBarcodeWidth = 90;
const double _kMinNameWidth = 160;
const double _kMinCategoryWidth = 100;

const int _kBarcodeFlex = 2;
const int _kNameFlex = 4;
const int _kCategoryFlex = 2;
const int _kFlexTotal = _kBarcodeFlex + _kNameFlex + _kCategoryFlex;

const double _kFixedSum = _kCodeColWidth +
    _kUnitColWidth +
    _kStockColWidth +
    _kStatusColWidth +
    _kExpiryColWidth +
    _kActionsColWidth;

const double _kMinFlexSum =
    _kMinBarcodeWidth + _kMinNameWidth + _kMinCategoryWidth;

const double _kFlexModeThreshold = _kFixedSum + _kMinFlexSum;

const double _kRowHeight = 48;
const double _kHeaderHeight = 44;

class StockBalancesTablePicpos extends ConsumerStatefulWidget {
  final AsyncValue<List<ProductEntity>> productsAsync;
  final Map<int, String> categoryMap;
  final Map<int, String> unitMap;
  final Map<int, DateTime> expiryMap;
  final void Function(ProductEntity) onAdjustStock;
  final void Function(ProductEntity) onPrint;
  final Map<int, double> warehouseStockMap;
  final bool filterByWarehouse;
  // Spec 136 ISS-9b — infinite scroll: fired when the operator scrolls near
  // the end so the screen can append the next page; [isLoadingMore] shows a
  // footer spinner while a page is in flight.
  final VoidCallback? onLoadMore;
  final bool isLoadingMore;

  const StockBalancesTablePicpos({
    super.key,
    required this.productsAsync,
    required this.categoryMap,
    this.unitMap = const {},
    required this.expiryMap,
    required this.onAdjustStock,
    required this.onPrint,
    this.warehouseStockMap = const {},
    this.filterByWarehouse = false,
    this.onLoadMore,
    this.isLoadingMore = false,
  });

  @override
  ConsumerState<StockBalancesTablePicpos> createState() => _StockBalancesTableState();
}

class _StockBalancesTableState extends ConsumerState<StockBalancesTablePicpos> {
  // Cluster 024 / Issue 3 — multi-barcode index for the inventory search.
  // Loaded once so the synchronous filter can match scanned alternate UPCs
  // (stored on `product_barcodes`) in addition to the primary `barcode`
  // column.
  Map<String, int> _barcodeToProductId = {};

  // Spec 030 — explicit scroll controllers for vertical (ListView.builder)
  // and horizontal (header + body share). Always-on scrollbars give the
  // operator a draggable thumb to jump through long inventories.
  final ScrollController _vScrollController = ScrollController();
  final ScrollController _hScrollController = ScrollController();

  // Spec 032 v3 diagnostic — same rebuild + scroll counters as
  // products_table so we can compare the two screens' behaviour from
  // the log file.
  final _tableBuilds =
      PerfRebuildCounter('stock_balances_table', everyN: 10);
  final _layoutBuilds =
      PerfRebuildCounter('stock_balances_table.layout', everyN: 50);
  final _scrollLog = PerfScrollLogger('stock_balances', throttleMs: 100);
  bool _scrollListenerAttached = false;

  @override
  void initState() {
    super.initState();
    _loadBarcodeIndex();
    // Spec 136 ISS-9b — single scroll listener: triggers infinite-scroll
    // load-more near the end, and (in perf-debug) logs scroll positions.
    _vScrollController.addListener(_onScroll);
    _scrollListenerAttached = true;
  }

  void _onScroll() {
    if (!_vScrollController.hasClients) return;
    final pos = _vScrollController.position;
    if (kPerfDebug) {
      _scrollLog.log(pos.pixels, pos.maxScrollExtent);
    }
    // Within ~600px of the bottom → ask the screen for the next page. The
    // callback is a no-op while a page is loading or once the end is reached.
    if (widget.onLoadMore != null &&
        pos.pixels >= pos.maxScrollExtent - 600) {
      widget.onLoadMore!();
    }
  }

  @override
  void dispose() {
    _vScrollController.dispose();
    _hScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadBarcodeIndex() async {
    try {
      final repo = ref.read(productRepositoryProvider);
      final pairs = await repo.getAllProductBarcodes();
      if (!mounted) return;
      setState(() {
        _barcodeToProductId = {
          for (final pair in pairs) pair.barcode.toLowerCase(): pair.productId,
        };
      });
    } catch (_) {/* fallback to primary-column-only search */}
  }

  double _stockFor(ProductEntity p) {
    if (widget.filterByWarehouse) {
      return widget.warehouseStockMap[p.id] ?? 0.0;
    }
    return p.currentStock;
  }

  List<ProductEntity> _filterProducts(
    List<ProductEntity> products,
    InventoryState state,
  ) {
    var filtered = products.toList();

    if (widget.filterByWarehouse) {
      filtered = filtered
          .where((p) => widget.warehouseStockMap.containsKey(p.id))
          .toList();
    }

    if (state.showLowStockOnly) {
      filtered = filtered.where((p) => _stockFor(p) <= p.minStock).toList();
    }

    final query = state.searchQuery.toLowerCase();
    if (query.isNotEmpty) {
      // Cluster 024 / Issue 3 — also match on primary barcode + multi-barcode
      // entries from product_barcodes so a scanned UPC works in this search.
      final extraIds = <int>{};
      _barcodeToProductId.forEach((bc, pid) {
        if (bc.contains(query)) extraIds.add(pid);
      });
      filtered = filtered
          .where(
            (p) =>
                p.name.toLowerCase().contains(query) ||
                p.code.toLowerCase().contains(query) ||
                (p.barcode?.toLowerCase().contains(query) ?? false) ||
                extraIds.contains(p.id),
          )
          .toList();
    }
    if (state.selectedCategoryId != null) {
      filtered = filtered
          .where((p) => p.categoryId == state.selectedCategoryId)
          .toList();
    }
    return filtered;
  }

  /// Issue 8 (Feature 018): originally a 500-row cap to keep the stock
  /// DataTable from freezing the UI thread on large categories. Spec 030
  /// replaced DataTable2 with ListView.builder, which renders only the
  /// ~20 visible rows regardless of list length.
  ///
  /// Spec 136 ISS-9b: the list is now OFFSET-paginated (load-on-scroll), so the
  /// in-memory set is bounded by how far the operator has scrolled — a 5000 cap
  /// would wrongly stop infinite scroll on big catalogs. Raised to a high
  /// absolute safety ceiling that real catalogs never hit.
  static const int _maxRenderedRows = 200000;

  @override
  Widget build(BuildContext context) {
    _tableBuilds.tick();
    final state = ref.watch(inventoryNotifierProvider);

    return widget.productsAsync.when(
      data: (products) {
        final filteredAll = _filterProducts(products, state);
        final wasTruncated = filteredAll.length > _maxRenderedRows;
        final filteredProducts = wasTruncated
            ? filteredAll.take(_maxRenderedRows).toList()
            : filteredAll;

        if (filteredProducts.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    PhosphorIconsBold.archive,
                    size: 48,
                    color: AppColors.textMuted,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'لا توجد أصناف مطابقة للبحث',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          );
        }

        return Column(
          children: [
            if (wasTruncated)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                color: AppColors.warning.withValues(alpha: 0.08),
                child: Text(
                  'يتم عرض أول $_maxRenderedRows من ${filteredAll.length} '
                  'صنف. استخدم البحث لتضييق النتائج.',
                  style: const TextStyle(
                    color: AppColors.warning,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Expanded(child: _buildTable(context, filteredProducts)),
          ],
        );
      },
      loading: () => ShimmerLoading.list(),
      error: (e, _) => Center(child: Text('خطأ في تحميل المخزون: $e')),
    );
  }

  Widget _buildTable(
      BuildContext context, List<ProductEntity> filteredProducts) {
    // Spec 032 — adaptive name column + decoupled scrollbars. When the
    // viewport fits everything, no horizontal scroll is needed and the
    // vertical scrollbar sits flush at the screen's right edge. When it
    // doesn't fit, both scrollbars hover at the visible edges (vertical
    // at right, horizontal at bottom) regardless of horizontal scroll
    // position — the operator can grab either one without first scrolling
    // the other.
    return LayoutBuilder(
      builder: (context, constraints) {
        _layoutBuilds.tick();
        final viewportWidth = constraints.maxWidth;
        final useFlex = viewportWidth >= _kFlexModeThreshold;

        late final double barcodeWidth;
        late final double nameWidth;
        late final double categoryWidth;
        if (useFlex) {
          final flexAvailable = viewportWidth - _kFixedSum;
          final unit = flexAvailable / _kFlexTotal;
          barcodeWidth = unit * _kBarcodeFlex;
          nameWidth = unit * _kNameFlex;
          categoryWidth = unit * _kCategoryFlex;
        } else {
          barcodeWidth = _kMinBarcodeWidth;
          nameWidth = _kMinNameWidth;
          categoryWidth = _kMinCategoryWidth;
        }
        final totalWidth = useFlex
            ? viewportWidth
            : _kFixedSum + barcodeWidth + nameWidth + categoryWidth;

        // Spec 136 ISS-9b — a fixed-height footer spinner row while the next
        // page loads (kept at _kRowHeight so the itemExtent stays uniform).
        final showFooter = widget.isLoadingMore;
        Widget buildRows() => ListView.builder(
              controller: _vScrollController,
              itemCount: filteredProducts.length + (showFooter ? 1 : 0),
              itemExtent: _kRowHeight,
              itemBuilder: (ctx, i) {
                if (i >= filteredProducts.length) {
                  return const SizedBox(
                    height: _kRowHeight,
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                final p = filteredProducts[i];
                return _StockBalanceRow(
                  key: ValueKey(p.id),
                  product: p,
                  stock: _stockFor(p),
                  categoryLabel:
                      widget.categoryMap[p.categoryId] ?? 'غير مصنف',
                  unitLabel: widget.unitMap[p.id] ?? 'قطعة',
                  expiryDate: widget.expiryMap[p.id],
                  isStriped: i.isOdd,
                  barcodeWidth: barcodeWidth,
                  nameWidth: nameWidth,
                  categoryWidth: categoryWidth,
                  onAdjust: () => widget.onAdjustStock(p),
                  onPrint: () => widget.onPrint(p),
                );
              },
            );

        if (useFlex) {
          return Scrollbar(
            controller: _vScrollController,
            thumbVisibility: true,
            child: Column(
              children: [
                _StockBalancesHeader(
                  barcodeWidth: barcodeWidth,
                  nameWidth: nameWidth,
                  categoryWidth: categoryWidth,
                ),
                Expanded(child: buildRows()),
              ],
            ),
          );
        }

        // Narrow-screen fallback: keep horizontal scroll.
        return Scrollbar(
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
                  _StockBalancesHeader(
                    barcodeWidth: barcodeWidth,
                    nameWidth: nameWidth,
                    categoryWidth: categoryWidth,
                  ),
                  Expanded(
                    child: Scrollbar(
                      controller: _vScrollController,
                      thumbVisibility: true,
                      child: buildRows(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StockBalancesHeader extends StatelessWidget {
  final double barcodeWidth;
  final double nameWidth;
  final double categoryWidth;
  const _StockBalancesHeader({
    required this.barcodeWidth,
    required this.nameWidth,
    required this.categoryWidth,
  });

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
          _cell('كود', _kCodeColWidth, headerStyle),
          _cell('الباركود', barcodeWidth, headerStyle),
          _cell('الصنف', nameWidth, headerStyle),
          _cell('التصنيف', categoryWidth, headerStyle),
          _cell('الوحدة', _kUnitColWidth, headerStyle),
          _cell('المخزون', _kStockColWidth, headerStyle, alignEnd: true),
          _cell('الحالة', _kStatusColWidth, headerStyle),
          _cell('الصلاحية', _kExpiryColWidth, headerStyle),
          _cell('إجراءات', _kActionsColWidth, headerStyle),
        ],
      ),
    );
  }

  Widget _cell(String text, double width, TextStyle? style,
      {bool alignEnd = false}) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Align(
          alignment: alignEnd ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
          child: Text(text, style: style, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }
}

class _StockBalanceRow extends StatelessWidget {
  const _StockBalanceRow({
    super.key,
    required this.product,
    required this.stock,
    required this.categoryLabel,
    required this.unitLabel,
    required this.expiryDate,
    required this.isStriped,
    required this.barcodeWidth,
    required this.nameWidth,
    required this.categoryWidth,
    required this.onAdjust,
    required this.onPrint,
  });

  final ProductEntity product;
  final double stock;
  final String categoryLabel;
  final String unitLabel;
  final DateTime? expiryDate;
  final bool isStriped;
  final double barcodeWidth;
  final double nameWidth;
  final double categoryWidth;
  final VoidCallback onAdjust;
  final VoidCallback onPrint;

  @override
  Widget build(BuildContext context) {
    final isOut = stock <= 0;
    final isLow = stock <= product.minStock && !isOut;
    final stockColor = isOut
        ? AppColors.error
        : isLow
            ? AppColors.warning
            : AppColors.textPrimary;

    return Container(
      height: _kRowHeight,
      decoration: BoxDecoration(
        color: isStriped
            ? Theme.of(context).colorScheme.surface.withValues(alpha: 0.4)
            : Colors.transparent,
        border: const Border(
          bottom: BorderSide(color: AppColors.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          _textCell(product.code, _kCodeColWidth),
          _textCell(product.barcode ?? '-', barcodeWidth),
          _textCell(product.name, nameWidth, tooltip: product.name),
          _textCell(categoryLabel, categoryWidth, tooltip: categoryLabel),
          _textCell(
            unitLabel,
            _kUnitColWidth,
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
          SizedBox(
            width: _kStockColWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: StockCellPicpos(
                stock: stock,
                minStock: product.minStock,
                trackInventory: product.trackInventory,
                stockColor: stockColor,
              ),
            ),
          ),
          SizedBox(
            width: _kStatusColWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: _StockStatusBadge(isOut: isOut, isLow: isLow),
              ),
            ),
          ),
          SizedBox(
            width: _kExpiryColWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: _ExpiryBadge(
                  expiryDate: expiryDate,
                  trackExpiry: product.trackExpiry,
                ),
              ),
            ),
          ),
          SizedBox(
            width: _kActionsColWidth,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(PhosphorIconsRegular.plusMinus, size: 18),
                  tooltip: 'تسوية الجرد',
                  color: AppColors.primary,
                  padding: const EdgeInsets.all(6),
                  constraints:
                      const BoxConstraints(minWidth: 40, minHeight: 40),
                  onPressed: onAdjust,
                ),
                IconButton(
                  icon: const Icon(PhosphorIconsRegular.barcode, size: 18),
                  tooltip: 'طباعة باركود',
                  color: AppColors.info,
                  padding: const EdgeInsets.all(6),
                  constraints:
                      const BoxConstraints(minWidth: 40, minHeight: 40),
                  onPressed: onPrint,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _textCell(
    String text,
    double width, {
    double fontSize = 14,
    Color? color,
    String? tooltip,
  }) {
    final child = Text(
      text,
      style: TextStyle(fontSize: fontSize, color: color),
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    );
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: tooltip == null
              ? child
              : Tooltip(message: tooltip, child: child),
        ),
      ),
    );
  }
}

/// خليّةُ المخزون على التصميم: الرصيدُ وبجانبه «حد أدنى …»، وتحتهما شريطُ
/// امتلاء.
///
/// ⚠️ **والشريطُ يختفي حين لا مرجعَ لقياسه** — لا يُرسم فارغاً ولا ممتلئاً.
/// راجع [picposStockFillRatio]: حدٌّ أدنى صفريٌّ يعني «غيرُ مضبوط» (وهو
/// افتراضُ العمود في القاعدة)، فرسمُ شريطٍ حينها ادّعاءُ قياسٍ لا مرجعَ له.
///
/// والمرجعُ **الحدُّ الأدنى لا سعةُ المخزن**: لا سعةَ قصوى في النظام، فامتلاءٌ
/// كاملٌ يعني بلوغَ الحدِّ الأدنى فأكثر — لا أنّ الرفَّ ملآن.
/// ⚠️ **عامّةٌ و`@visibleForTesting` عمداً** — نفسُ نمطِ
/// `buildProductSalePriceCell` في جدول الأصناف، ولنفسِ السبب المكتوبِ هناك:
/// تركيبُ [StockBalancesTablePicpos] كاملةً يجرّ `AppDatabase` حقيقيّةً
/// (‏درسُ دفعة ٦أ). ولو تُركت خاصّةً لاضطرّ الاختبارُ إلى بناء **نسخةٍ
/// موازيةٍ** بنفس المنطق — فيُثبت النسخةَ لا التوصيلة، وهو بالضبط ما يحذّر
/// منه رأسُ `task_8_products_grid_permission_gates_test`.
@visibleForTesting
class StockCellPicpos extends StatelessWidget {
  const StockCellPicpos({
    super.key,
    required this.stock,
    required this.minStock,
    required this.trackInventory,
    required this.stockColor,
  });

  final double stock;
  final double minStock;
  final bool trackInventory;
  final Color stockColor;

  @override
  Widget build(BuildContext context) {
    final ratio = picposStockFillRatio(
      currentStock: stock,
      minStock: minStock,
      trackInventory: trackInventory,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                stock.toStringAsFixed(1),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: stockColor,
                ),
              ),
            ),
            if (minStock > 0) ...[
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'حد أدنى ${minStock.toStringAsFixed(0)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ],
        ),
        if (ratio != null) ...[
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 5,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation<Color>(stockColor),
            ),
          ),
        ],
      ],
    );
  }
}

class _StockStatusBadge extends StatelessWidget {
  const _StockStatusBadge({required this.isOut, required this.isLow});

  final bool isOut;
  final bool isLow;

  @override
  Widget build(BuildContext context) {
    String text;
    Color color;
    if (isOut) {
      text = 'نفذ';
      color = AppColors.error;
    } else if (isLow) {
      text = 'منخفض';
      color = AppColors.warning;
    } else {
      text = 'متوفر';
      color = AppColors.success;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _ExpiryBadge extends StatelessWidget {
  const _ExpiryBadge({required this.expiryDate, required this.trackExpiry});

  final DateTime? expiryDate;
  final bool trackExpiry;

  @override
  Widget build(BuildContext context) {
    if (!trackExpiry) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.textMuted.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text(
          '-',
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      );
    }
    if (expiryDate == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text(
          'سليم',
          style: TextStyle(
            color: AppColors.success,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }
    final now = DateTime.now();
    final daysUntilExpiry = expiryDate!.difference(now).inDays;
    String text;
    Color color;
    if (daysUntilExpiry < 0) {
      text = 'منتهي';
      color = AppColors.error;
    } else if (daysUntilExpiry <= 30) {
      text = 'قرب الإنتهاء ($daysUntilExpiry يوم)';
      color = AppColors.warning;
    } else {
      text = 'سليم';
      color = AppColors.success;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
