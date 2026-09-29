import 'package:ural_erp/core/i18n/tr.dart';
import 'package:ural_erp/core/design_system/typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/cart_item_entity.dart';
import '../../../data/providers/providers.dart';
import '../providers/cart_controller.dart';
import '../../widgets/permission_guard.dart';
import '../../widgets/searchable_unit_selection_dialog.dart';
import 'modifier_selection_dialog.dart';
import 'cart/cart_discount_dialog.dart';

part 'cart_item_modifier_panel.dart';

class CartItemTile extends ConsumerStatefulWidget {
  final CartItemEntity item;
  final int index;
  final VoidCallback onRemove;
  final ValueChanged<double> onQuantityChanged;
  final ValueChanged<double>? onPriceChanged; // Inline price edit
  final VoidCallback? onEdit;
  final VoidCallback? onToggleType; // Toggle return/exchange
  final VoidCallback? onPrintBarcode; // Print barcode for this item
  final bool isExchangeMode; // Show toggle button

  const CartItemTile({
    super.key,
    required this.item,
    required this.index,
    required this.onRemove,
    required this.onQuantityChanged,
    this.onPriceChanged,
    this.onEdit,
    this.onToggleType,
    this.onPrintBarcode,
    this.isExchangeMode = false,
  });

  @override
  ConsumerState<CartItemTile> createState() => _CartItemTileState();
}

class _CartItemTileState extends ConsumerState<CartItemTile>
    with SingleTickerProviderStateMixin, _CartItemModifierPanelMixin {
  bool _isEditingQuantity = false;
  bool _isEditingPrice = false;
  bool _isExpanded = false;
  int _activeModifierTab = 0; // 0 = الإضافات, 1 = الخيارات
  OptionQuantityLevel _selectedQuantityLevel = OptionQuantityLevel.medium;

  // ── Mixin interface for _CartItemModifierPanelMixin ──
  @override
  int get activeModifierTab => _activeModifierTab;
  @override
  set activeModifierTab(int v) => _activeModifierTab = v;
  @override
  OptionQuantityLevel get selectedQuantityLevel => _selectedQuantityLevel;
  @override
  set selectedQuantityLevel(OptionQuantityLevel v) => _selectedQuantityLevel = v;
  @override
  TextEditingController get noteController => _noteController;
  @override
  CartItemTile get tileWidget => widget;
  @override
  int get tileIndex => widget.index;
  @override
  WidgetRef get tileRef => ref;
  late TextEditingController _qtyController;
  late TextEditingController _priceController;
  late TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    _qtyController = TextEditingController();
    _priceController = TextEditingController();
    _noteController = TextEditingController(text: widget.item.itemNote ?? '');
  }

  @override
  void didUpdateWidget(CartItemTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.itemNote != widget.item.itemNote) {
      _noteController.text = widget.item.itemNote ?? '';
    }
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _priceController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  /// Show discount dialog for this specific item
  void _showItemDiscountDialog(
    BuildContext context,
    WidgetRef ref,
    int index,
    CartItemEntity item,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) => CartDiscountDialog(
        subtotal: item.subtotal,
        currentDiscountPercent: item.discountPercent,
        onApply: (percent) {
          ref.read(cartControllerProvider.notifier).setItemDiscount(index, percent);
        },
        onRemove: () {
          ref.read(cartControllerProvider.notifier).setItemDiscount(index, 0);
          Navigator.pop(dialogContext);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Compact scale for more items visible
        final layoutScale = (constraints.maxWidth / 400).clamp(0.6, 1.0);
        final userScale = ref.watch(posCartItemScaleProvider).value ?? 1.0;
        final scaleFactor = layoutScale * userScale;

        final fontSize = 12.0 * scaleFactor;
        final smallFontSize = 10.0 * scaleFactor;
        final rowHeight =
            38.0 *
            scaleFactor; // Compact height to display more items
        final hasModifiers = widget.item.modifiers.isNotEmpty;
        final hasItemNote = widget.item.itemNote != null && widget.item.itemNote!.isNotEmpty;
        final hasExtra = hasModifiers || hasItemNote;

        final isReturned = widget.item.itemType == CartItemType.returned;
        final isEven = widget.index.isEven;

        // Premium background logic
        final Color backgroundColor = isReturned
            ? AppColors.error.withValues(alpha: 0.1)
            : (isEven
                  ? Theme.of(context).cardColor
                  : Theme.of(context).colorScheme.surface);

        return Container(
          margin: EdgeInsets.symmetric(
            horizontal: 6 * scaleFactor,
            vertical: 1 * scaleFactor,
          ),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isReturned
                  ? AppColors.error.withValues(alpha: 0.3)
                  : AppColors.border.withValues(alpha: 0.5),
              width: 1,
            ),
            boxShadow: [
              if (!isEven && !isReturned)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ─── Main row ───
              Container(
                constraints: BoxConstraints(minHeight: rowHeight),
                padding: EdgeInsets.symmetric(
                  horizontal: 8 * scaleFactor,
                  vertical: hasExtra ? 4 * scaleFactor : 0,
                ),
                child: Row(
                  children: [
                    // Product Code & Type Icon
                    SizedBox(
                      width: 60 * scaleFactor,
                      child: Row(
                        children: [
                          Icon(
                            isReturned
                                ? PhosphorIconsBold.arrowUUpLeft
                                : PhosphorIconsBold.tag,
                            size: 14 * scaleFactor,
                            color: isReturned ? AppColors.error : AppColors.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              widget.item.productCode,
                              style: TextStyle(
                                fontSize: smallFontSize - 1,
                                color: AppColors.textMuted,
                                fontWeight: FontWeight.w600,
                                fontFamily: AppTypography.mono,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 8),

                    // Product Name + modifiers indicator
                    Expanded(
                      flex: 4,
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.item.productName,
                                  style: TextStyle(
                                    fontSize: fontSize,
                                    fontWeight: FontWeight.w800,
                                    color: isReturned
                                        ? AppColors.error
                                        : Theme.of(
                                            context,
                                          ).textTheme.bodyLarge?.color,
                                    letterSpacing: -0.2,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                                if (isReturned)
                                  Text(
                                    tr('مرتجع من العميل'),
                                    style: TextStyle(
                                      fontSize: smallFontSize - 2,
                                      color: AppColors.error.withValues(alpha: 0.8),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                // Unit selector badge
                                if (widget.item.selectedUnitName != null &&
                                    widget.item.selectedUnitName!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: _buildUnitBadge(scaleFactor),
                                  ),
                                // Show modifiers + note summary under name
                                if (hasExtra)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: _buildModifiersSummary(scaleFactor),
                                  ),
                              ],
                            ),
                          ),
                          if (widget.isExchangeMode && widget.onToggleType != null)
                            IconButton(
                              onPressed: widget.onToggleType,
                              icon: Icon(
                                isReturned
                                    ? PhosphorIconsBold.arrowsLeftRight
                                    : PhosphorIconsBold.arrowUUpLeft,
                                size: 18 * scaleFactor,
                                color: isReturned
                                    ? AppColors.success
                                    : AppColors.error,
                              ),
                              tooltip: isReturned
                                  ? tr('تبديل إلى بيع')
                                  : tr('تبديل إلى مرتجع'),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              splashRadius: 20,
                            ),
                        ],
                      ),
                    ),

                    // Quantity Controls
                    Container(
                      width: 100 * scaleFactor,
                      height: 34 * scaleFactor,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Row(
                        children: [
                          PermissionGuard(
                            permission: PermissionCodes.posItemMinus,
                            allowManagerOverride: true,
                            actionName: tr('نقص كمية'),
                            child: _buildQtyBtn(
                              icon: PhosphorIconsBold.minus,
                              color: AppColors.error,
                              scaleFactor: scaleFactor,
                              onTap: widget.item.quantity > 1
                                  ? () => widget.onQuantityChanged(
                                      widget.item.quantity - 1,
                                    )
                                  : widget.onRemove,
                            ),
                          ),
                          Expanded(
                            child: Center(
                              child: _isEditingQuantity
                                  ? TextField(
                                      controller: _qtyController,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      textAlign: TextAlign.center,
                                      autofocus: true,
                                      style: TextStyle(
                                        fontSize: fontSize,
                                        fontWeight: FontWeight.w900,
                                        color: AppColors.primary,
                                      ),
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        border: InputBorder.none,
                                      ),
                                      onSubmitted: (value) {
                                        final newQty = double.tryParse(value);
                                        if (newQty != null && newQty > 0) {
                                          widget.onQuantityChanged(newQty);
                                        }
                                        setState(() => _isEditingQuantity = false);
                                      },
                                      onTapOutside: (_) =>
                                          setState(() => _isEditingQuantity = false),
                                    )
                                  : PermissionGuard(
                                      permission: PermissionCodes.posQuantityEdit,
                                      allowManagerOverride: true,
                                      actionName: tr('تعديل الكمية يدوياً'),
                                      child: GestureDetector(
                                        onTap: () {
                                          _qtyController.text =
                                              widget.item.isSoldByWeight
                                              ? widget.item.quantity.toStringAsFixed(
                                                  3,
                                                )
                                              : widget.item.quantity.toStringAsFixed(
                                                  0,
                                                );
                                          setState(() => _isEditingQuantity = true);
                                        },
                                        child: Text(
                                          widget.item.isSoldByWeight
                                              ? widget.item.quantity.toStringAsFixed(
                                                  AppConstants.decimalPlaces,
                                                )
                                              : widget.item.quantity.toStringAsFixed(
                                                  0,
                                                ),
                                          style: TextStyle(
                                            fontSize: fontSize,
                                            fontWeight: FontWeight.w900,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                          PermissionGuard(
                            permission: PermissionCodes.posItemPlus,
                            allowManagerOverride: true,
                            actionName: tr('زيادة كمية'),
                            child: _buildQtyBtn(
                              icon: PhosphorIconsBold.plus,
                              color: AppColors.primary,
                              scaleFactor: scaleFactor,
                              onTap: () =>
                                  widget.onQuantityChanged(widget.item.quantity + 1),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Price
                    SizedBox(
                      width: 70 * scaleFactor,
                      child: _isEditingPrice
                          ? TextField(
                              controller: _priceController,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              textAlign: TextAlign.center,
                              autofocus: true,
                              style: TextStyle(
                                fontSize: fontSize,
                                fontWeight: FontWeight.bold,
                                color: AppColors.warningDark,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              onSubmitted: (value) {
                                final newPrice = double.tryParse(value);
                                if (newPrice != null && newPrice > 0) {
                                  widget.onPriceChanged?.call(newPrice);
                                }
                                setState(() => _isEditingPrice = false);
                              },
                              onTapOutside: (_) =>
                                  setState(() => _isEditingPrice = false),
                            )
                          : PermissionGuard(
                              permission: PermissionCodes.posPriceEdit,
                              allowManagerOverride: true,
                              actionName: tr('تعديل سعر الصنف'),
                              child: GestureDetector(
                                onTap: widget.onPriceChanged != null
                                    ? () {
                                        _priceController.text = widget
                                            .item
                                            .effectivePrice
                                            .toStringAsFixed(AppConstants.decimalPlaces);
                                        setState(() => _isEditingPrice = true);
                                      }
                                    : widget.onEdit,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      widget.item.effectivePrice.toStringAsFixed(AppConstants.decimalPlaces),
                                      style: TextStyle(
                                        fontSize: fontSize - 1,
                                        color:
                                            Theme.of(context).brightness ==
                                                Brightness.light
                                            ? AppColors.warningDark
                                            : AppColors.warning,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    Text(
                                      tr('سعر الوحدة'),
                                      style: TextStyle(
                                        fontSize: smallFontSize - 3,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ),

                    const SizedBox(width: 12),

                    // Expand/Collapse arrow for modifiers
                    _buildExpandArrow(scaleFactor),

                    const SizedBox(width: 12),

                    // Total + discount badge
                    GestureDetector(
                      onTap: () => _showItemDiscountDialog(
                        context,
                        ref,
                        widget.index,
                        widget.item,
                      ),
                      child: SizedBox(
                        width: 80 * scaleFactor,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              // `total` بيضيف ضريبة الصف **بلا شرط**، بينما
                              // `CalculateInvoiceTotalsUseCase` بيتجاهل ضريبة
                              // الصف المخزّنة عن قصد ويعيد حسابها على الصافي
                              // **ومشروطة بـ `taxEnabled`** (سبيك ١٣٧ —
                              // BUG-C02/BUG-H01).
                              //
                              // فلما الضريبة تكون مقفولة، الصف كان بيعرض
                              // ضريبة الفاتورة قررت ما تحصّلهاش: صنف ٧ × ٥
                              // يعرض ٤٠.٦ والإجمالي النهائي ٣٥. الباج كامن
                              // عند أي عميل شغّال بضريبة مفتوحة، وبيظهر فوراً
                              // لما تتقفل.
                              //
                              // الصافي هو اللي بيجمع للمجموع الفرعي، والضريبة
                              // سطر مستقل في لوحة الإجماليات.
                              widget.item.totalBeforeTax
                                  .abs()
                                  .toStringAsFixed(AppConstants.decimalPlaces),
                              style: TextStyle(
                                fontSize: fontSize + 1,
                                fontWeight: FontWeight.w900,
                                color: isReturned
                                    ? AppColors.error
                                    : AppColors.getPriceColor(context),
                              ),
                            ),
                            // Show item discount badge
                            if (widget.item.discountPercent > 0)
                              Container(
                                margin: const EdgeInsets.only(top: 2),
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppColors.success.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                                ),
                                child: Text(
                                  '-${widget.item.discountPercent.toStringAsFixed(0)}%',
                                  style: TextStyle(
                                    fontSize: smallFontSize - 2,
                                    color: AppColors.success,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              )
                            else
                              Text(
                                tr('خصم'),
                                style: TextStyle(
                                  fontSize: smallFontSize - 3,
                                  color: AppColors.textMuted.withValues(alpha: 0.5),
                                ),
                              ),
                            // BUG-C03: use the fresh getter (net of line
                            // discount, recomputed each rebuild) not the stored
                            // gross taxAmount field which goes stale on merge.
                            if (widget.item.calculatedTaxAmount > 0)
                              Text(
                                tr('+ {p0} ضريبة', {'p0': widget.item.calculatedTaxAmount.toStringAsFixed(AppConstants.decimalPlaces)}),
                                style: TextStyle(
                                  fontSize: smallFontSize - 3,
                                  color: AppColors.textMuted,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    // The expand arrow has been moved before the Total section

                    // Delete Button
                    PermissionGuard(
                      permission: PermissionCodes.posRemoveItem,
                      allowManagerOverride: true,
                      actionName: tr('حذف صنف'),
                      child: IconButton(
                        onPressed: widget.onRemove,
                        tooltip: tr('حذف الصنف'), // BUG-U29/U37
                        icon: Icon(
                          PhosphorIconsBold.trash,
                          size: 18 * scaleFactor,
                          color: AppColors.error.withValues(alpha: 0.6),
                        ),
                        splashRadius: 20,
                      ),
                    ),
                  ],
                ),
              ),

              // ─── Expandable inline modifier/note panel ───
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: buildExpandedPanel(scaleFactor),
                crossFadeState: _isExpanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 200),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Small arrow button to expand/collapse modifier panel
  Widget _buildExpandArrow(double scaleFactor) {
    return GestureDetector(
      onTap: () => setState(() => _isExpanded = !_isExpanded),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12), // Increases tap target
        child: AnimatedRotation(
          turns: _isExpanded ? 0.5 : 0,
          duration: const Duration(milliseconds: 200),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              PhosphorIconsBold.caretDown,
              size: 20 * scaleFactor, // Increased size
              color: AppColors.primary,
            ),
          ),
        ),
      ),
    );
  }

  /// Unit selector badge — shows current unit and allows switching
  Widget _buildUnitBadge(double scaleFactor) {
    final unitName = widget.item.selectedUnitName ?? tr('قطعة');
    return FutureBuilder<List<ProductUnit>>(
      future: ref.read(productRepositoryProvider).getProductUnits(widget.item.productId),
      builder: (context, snapshot) {
        final units = snapshot.data ?? [];
        if (units.length <= 1) {
          // Single unit — show static badge only
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              unitName,
              style: TextStyle(
                fontSize: 9 * scaleFactor,
                color: AppColors.info,
                fontWeight: FontWeight.w700,
              ),
            ),
          );
        }
        // Multiple units — show searchable badge
        return GestureDetector(
          onTap: () async {
            final selectedUnit = await showDialog<ProductUnit>(
              context: context,
              builder: (context) => SearchableUnitSelectionDialog(
                units: units,
                currentUnitName: unitName,
              ),
            );

            if (selectedUnit != null) {
              ref.read(cartControllerProvider.notifier).updateItemUnit(
                widget.index,
                unitId: selectedUnit.id,
                unitName: selectedUnit.unitName,
                quantityInBase: selectedUnit.quantityInBase,
                unitSalePrice: selectedUnit.salePrice,
              );
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  unitName,
                  style: TextStyle(
                    fontSize: 9 * scaleFactor,
                    color: AppColors.info,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(width: 2 * scaleFactor),
                Icon(
                  PhosphorIconsBold.caretDown,
                  size: 8 * scaleFactor,
                  color: AppColors.info,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Summary of modifiers and notes shown under the product name
  Widget _buildModifiersSummary(double scaleFactor) {
    final addons = widget.item.modifiers.where((m) => !m.isOption).toList();
    final options = widget.item.modifiers.where((m) => m.isOption).toList();
    final itemNote = widget.item.itemNote;

    return Wrap(
      spacing: 4,
      runSpacing: 2,
      children: [
        // Addons with + prefix
        for (final addon in addons)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              '+${addon.itemName}',
              style: TextStyle(
                fontSize: 9 * scaleFactor,
                color: AppColors.success,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        // Options with quantity level badge
        for (final opt in options)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: opt.quantityLevel.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: opt.quantityLevel.color.withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (opt.quantityLevel != OptionQuantityLevel.none) ...[
                  Icon(
                    opt.quantityLevel.icon,
                    size: 8 * scaleFactor,
                    color: opt.quantityLevel.color,
                  ),
                  SizedBox(width: 2 * scaleFactor),
                ],
                Text(
                  opt.displayText,
                  style: TextStyle(
                    fontSize: 9 * scaleFactor,
                    color: opt.quantityLevel != OptionQuantityLevel.none
                        ? opt.quantityLevel.color
                        : AppColors.info,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        // Manual note
        if (itemNote != null && itemNote.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              '📝 $itemNote',
              style: TextStyle(
                fontSize: 9 * scaleFactor,
                color: AppColors.warningDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  // NOTE: _buildExpandedPanel and all modifier/toggle methods have been
  // extracted to cart_item_modifier_panel.dart via _CartItemModifierPanelMixin

  Widget _buildQtyBtn({
    required IconData icon,
    required Color color,
    required double scaleFactor,
    required VoidCallback? onTap,
  }) {
    final size = 28.0 * scaleFactor;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Icon(icon, size: 14 * scaleFactor, color: color),
      ),
    );
  }
}
