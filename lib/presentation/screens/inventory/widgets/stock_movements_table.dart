import 'package:ural_erp/core/constants/app_constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../domain/repositories/inventory_repository.dart';
import '../../../../core/widgets/shimmer_loading.dart';
import '../inventory_notifier.dart';

// ─── Column widths (Spec 032 v2 — flex distribution) ─────────────────────
const double _kDateColWidth = 80;
const double _kTypeColWidth = 100;
const double _kQtyColWidth = 80;
const double _kCostColWidth = 80;
const double _kBalanceColWidth = 70;
const double _kRefColWidth = 90;

const double _kMinProductWidth = 140;
const double _kMinNotesWidth = 120;

const int _kProductFlex = 6;
const int _kNotesFlex = 4;
const int _kFlexTotal = _kProductFlex + _kNotesFlex;

const double _kFixedSum = _kDateColWidth +
    _kTypeColWidth +
    _kQtyColWidth +
    _kCostColWidth +
    _kBalanceColWidth +
    _kRefColWidth;

const double _kMinFlexSum = _kMinProductWidth + _kMinNotesWidth;
const double _kFlexModeThreshold = _kFixedSum + _kMinFlexSum;

const double _kRowHeight = 52;
const double _kHeaderHeight = 40;

class StockMovementsTable extends ConsumerStatefulWidget {
  final AsyncValue<List<StockMovementData>> movementsAsync;
  final Function(String, int) onNavigateToInvoice;
  final Map<int, String> productNameMap;

  const StockMovementsTable({
    super.key,
    required this.movementsAsync,
    required this.onNavigateToInvoice,
    this.productNameMap = const {},
  });

  @override
  ConsumerState<StockMovementsTable> createState() =>
      _StockMovementsTableState();
}

class _StockMovementsTableState extends ConsumerState<StockMovementsTable> {
  // Spec 032 — independent scroll controllers. The vertical lives on the
  // ListView.builder; the horizontal on the (conditional) outer
  // SingleChildScrollView. Both surface their scrollbars via Scrollbar
  // widgets pinned to the visible viewport edges.
  final ScrollController _vScrollController = ScrollController();
  final ScrollController _hScrollController = ScrollController();

  @override
  void dispose() {
    _vScrollController.dispose();
    _hScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(inventoryNotifierProvider);

    return widget.movementsAsync.when(
      data: (mvmts) {
        if (mvmts.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  PhosphorIconsBold.arrowsLeftRight,
                  size: 64,
                  color: AppColors.textMuted.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  state.selectedMovementProductId != null
                      ? 'لا توجد حركات لهذا الصنف'
                      : 'لا توجد حركات مخزون',
                  style: const TextStyle(color: AppColors.textMuted),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            _buildSummaryBar(mvmts),
            const Divider(height: 1),
            Expanded(child: _buildTable(context, mvmts)),
          ],
        );
      },
      loading: () => Padding(
        padding: const EdgeInsets.all(16),
        child: ShimmerLoading.list(itemCount: 6),
      ),
      error: (e, _) => Center(child: Text('خطأ: $e')),
    );
  }

  Widget _buildTable(
      BuildContext context, List<StockMovementData> movements) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth;
        final useFlex = viewportWidth >= _kFlexModeThreshold;

        late final double productWidth;
        late final double notesWidth;
        if (useFlex) {
          final flexAvailable = viewportWidth - _kFixedSum;
          final unit = flexAvailable / _kFlexTotal;
          productWidth = unit * _kProductFlex;
          notesWidth = unit * _kNotesFlex;
        } else {
          productWidth = _kMinProductWidth;
          notesWidth = _kMinNotesWidth;
        }
        final totalWidth = useFlex
            ? viewportWidth
            : _kFixedSum + productWidth + notesWidth;

        Widget buildRows() => ListView.builder(
              controller: _vScrollController,
              itemCount: movements.length,
              itemExtent: _kRowHeight,
              itemBuilder: (ctx, i) {
                final m = movements[i];
                return _StockMovementRow(
                  movement: m,
                  productName: widget.productNameMap[m.productId] ??
                      '#${m.productId}',
                  isStriped: i.isOdd,
                  productWidth: productWidth,
                  notesWidth: notesWidth,
                  onNavigateToInvoice: widget.onNavigateToInvoice,
                );
              },
            );

        if (useFlex) {
          return Scrollbar(
            controller: _vScrollController,
            thumbVisibility: true,
            child: Column(
              children: [
                _StockMovementsHeader(
                  productWidth: productWidth,
                  notesWidth: notesWidth,
                ),
                Expanded(child: buildRows()),
              ],
            ),
          );
        }

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
                  _StockMovementsHeader(
                    productWidth: productWidth,
                    notesWidth: notesWidth,
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

  Widget _buildSummaryBar(List<StockMovementData> movements) {
    final totalIn = movements
        .where((m) => m.quantity > 0)
        .fold<double>(0, (s, m) => s + m.quantity);
    final totalOut = movements
        .where((m) => m.quantity < 0)
        .fold<double>(0, (s, m) => s + m.quantity.abs());
    final netChange = totalIn - totalOut;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppColors.primary.withValues(alpha: 0.03),
      child: Row(
        children: [
          _summaryChip('إجمالي الحركات', '${movements.length}',
              PhosphorIconsBold.arrowsLeftRight, AppColors.primary),
          const SizedBox(width: 16),
          _summaryChip('وارد', '+${totalIn.toStringAsFixed(0)}',
              PhosphorIconsBold.arrowDown, AppColors.success),
          const SizedBox(width: 16),
          _summaryChip('صادر', '-${totalOut.toStringAsFixed(0)}',
              PhosphorIconsBold.arrowUp, AppColors.error),
          const SizedBox(width: 16),
          _summaryChip(
              'صافي التغيير',
              '${netChange >= 0 ? '+' : ''}${netChange.toStringAsFixed(0)}',
              PhosphorIconsBold.trendUp,
              netChange >= 0 ? AppColors.success : AppColors.error),
        ],
      ),
    );
  }

  Widget _summaryChip(String label, String value, IconData icon, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text('$label: ',
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        Text(value,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}

class _StockMovementsHeader extends StatelessWidget {
  final double productWidth;
  final double notesWidth;
  const _StockMovementsHeader({
    required this.productWidth,
    required this.notesWidth,
  });

  @override
  Widget build(BuildContext context) {
    final headerStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: 12,
        );
    return Container(
      height: _kHeaderHeight,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: const Border(
          bottom: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          _cell('التاريخ', _kDateColWidth, headerStyle),
          _cell('الصنف', productWidth, headerStyle),
          _cell('نوع الحركة', _kTypeColWidth, headerStyle),
          _cell('الكمية', _kQtyColWidth, headerStyle, alignEnd: true),
          _cell('التكلفة', _kCostColWidth, headerStyle, alignEnd: true),
          _cell('الرصيد', _kBalanceColWidth, headerStyle, alignEnd: true),
          _cell('الفاتورة', _kRefColWidth, headerStyle),
          _cell('ملاحظات', notesWidth, headerStyle),
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
          alignment: alignEnd ? Alignment.centerLeft : Alignment.centerRight,
          child: Text(text, style: style, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }
}

class _StockMovementRow extends StatelessWidget {
  const _StockMovementRow({
    required this.movement,
    required this.productName,
    required this.isStriped,
    required this.productWidth,
    required this.notesWidth,
    required this.onNavigateToInvoice,
  });

  final StockMovementData movement;
  final String productName;
  final bool isStriped;
  final double productWidth;
  final double notesWidth;
  final Function(String, int) onNavigateToInvoice;

  @override
  Widget build(BuildContext context) {
    final m = movement;
    final isIn = m.quantity > 0;
    final dateText =
        '${m.createdAt.day}/${m.createdAt.month}/${m.createdAt.year}';
    final timeText =
        '${m.createdAt.hour.toString().padLeft(2, '0')}:${m.createdAt.minute.toString().padLeft(2, '0')}';

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
          // Date / time
          SizedBox(
            width: _kDateColWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dateText,
                    style: const TextStyle(
                        fontWeight: FontWeight.w500, fontSize: 12),
                  ),
                  Text(
                    timeText,
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ),
          // Product
          SizedBox(
            width: productWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: Tooltip(
                  message: productName,
                  child: Text(
                    productName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ),
            ),
          ),
          // Type
          SizedBox(
            width: _kTypeColWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _getMovementTypeIcon(m.movementType),
                    size: 14,
                    color: isIn ? AppColors.success : AppColors.error,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      _getMovementTypeLabel(m.movementType),
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Quantity (with badge)
          SizedBox(
            width: _kQtyColWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (isIn ? AppColors.success : AppColors.error)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${isIn ? '+' : ''}${m.quantity.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: isIn ? AppColors.success : AppColors.error,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Cost
          SizedBox(
            width: _kCostColWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  m.unitCost.toStringAsFixed(AppConstants.decimalPlaces),
                  style: const TextStyle(
                      fontWeight: FontWeight.w500, fontSize: 12),
                ),
              ),
            ),
          ),
          // Balance
          SizedBox(
            width: _kBalanceColWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  m.balanceAfter.toStringAsFixed(0),
                  style: const TextStyle(
                      fontWeight: FontWeight.w500, fontSize: 12),
                ),
              ),
            ),
          ),
          // Reference (invoice link)
          SizedBox(
            width: _kRefColWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: m.referenceId != null && m.referenceType != null
                    ? InkWell(
                        onTap: () => onNavigateToInvoice(
                            m.referenceType!, m.referenceId!),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color:
                                AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(PhosphorIconsBold.fileText,
                                  size: 12, color: AppColors.primary),
                              const SizedBox(width: 4),
                              Text(
                                '#${m.referenceId}',
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 11,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : const Text('-',
                        style: TextStyle(color: AppColors.textMuted)),
              ),
            ),
          ),
          // Notes
          SizedBox(
            width: notesWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: Tooltip(
                  message: m.notes ?? '',
                  child: Text(
                    m.notes ?? '-',
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getMovementTypeIcon(String type) {
    switch (type) {
      case 'purchase':
        return PhosphorIconsBold.shoppingCart;
      case 'sale':
        return PhosphorIconsBold.receipt;
      case 'return':
        return PhosphorIconsBold.arrowUDownLeft;
      case 'adjustment':
        return PhosphorIconsBold.faders;
      case 'transfer':
        return PhosphorIconsBold.arrowsLeftRight;
      default:
        return PhosphorIconsBold.question;
    }
  }

  String _getMovementTypeLabel(String type) {
    switch (type) {
      case 'purchase':
        return 'شراء';
      case 'sale':
        return 'مبيعات';
      case 'return':
        return 'مرتجع';
      case 'adjustment':
        return 'تسوية';
      case 'opening_stock':
        return 'رصيد افتتاحي';
      case 'transfer':
        return 'تحويل';
      default:
        return type;
    }
  }
}
