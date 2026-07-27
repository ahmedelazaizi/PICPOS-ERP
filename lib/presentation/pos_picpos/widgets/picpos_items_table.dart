import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/number_utils.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/entities/cart_item_entity.dart';
import '../../pos/providers/cart_controller.dart';

/// The invoice line table: م · المادة · الكمية · السعر · الخصم · المجموع · إلغاء
///
/// Quantity / price / discount are edited IN PLACE. A classic retail POS is
/// keyboard-driven — round-tripping through a dialog for every quantity
/// change is the single biggest speed cost, so the cells are live fields.
///
/// The selected row is tracked by the parent because the F-key handler acts
/// on it (F8 deletes it, F6 edits it) — the table itself owns no shortcut.
class PicPosItemsTable extends ConsumerWidget {
  final int? selectedIndex;

  /// مضاعِف لحظي من شريط التحكم أعلى السلة، فوق إعداد `pos_cart_item_scale`.
  /// الإعداد هو تفضيل التركيب الدائم؛ ده تعديل الجلسة.
  final double density;

  final ValueChanged<int> onSelect;
  final ValueChanged<int> onRemove;

  const PicPosItemsTable({
    super.key,
    required this.selectedIndex,
    this.density = 1.0,
    required this.onSelect,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(cartControllerProvider.select((s) => s.items));
    // `pos_cart_item_scale` من «إعدادات نقطة البيع» — نفس المفتاح ونفس
    // الافتراضي اللي صفوف سلة UralCash بتقراهم. شاشات الكاشير بتتفاوت من
    // ١٠″ لمسية لـ ٢٤″ بماوس، والصف اللي مريح على واحدة بيبقى مضيعة للتانية.
    final scale =
        ((ref.watch(posCartItemScaleProvider).value ?? 1.0) * density)
            .clamp(0.7, 1.6);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _TableHeader(scale: scale),
          Expanded(
            child: items.isEmpty
                ? const _EmptyState()
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, i) => _ItemRow(
                      index: i,
                      item: items[i],
                      isSelected: selectedIndex == i,
                      scale: scale,
                      onSelect: () => onSelect(i),
                      onRemove: () => onRemove(i),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// Column widths are shared by the header and every row so they stay locked
// together. Flex values, not pixels — the panel is resizable.
const _kFlexIndex = 5;
const _kFlexName = 34;
const _kFlexQty = 13;
const _kFlexPrice = 14;
const _kFlexDiscount = 12;
const _kFlexTotal = 16;
const _kFlexRemove = 6;

class _TableHeader extends StatelessWidget {
  final double scale;

  const _TableHeader({required this.scale});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40 * scale,
      color: AppColors.primaryDark,
      child: Row(
        children: [
          _HeaderCell('م', _kFlexIndex, scale: scale),
          _HeaderCell('المادة', _kFlexName,
              align: TextAlign.right, scale: scale),
          _HeaderCell('الكمية', _kFlexQty, scale: scale),
          _HeaderCell('السعر', _kFlexPrice, scale: scale),
          _HeaderCell('الخصم %', _kFlexDiscount, scale: scale),
          _HeaderCell('المجموع', _kFlexTotal, scale: scale),
          _HeaderCell('', _kFlexRemove, scale: scale),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String label;
  final int flex;
  final TextAlign align;
  final double scale;

  const _HeaderCell(this.label, this.flex,
      {this.align = TextAlign.center, required this.scale});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Align(
          alignment: align == TextAlign.right
              ? Alignment.centerRight
              : Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13 * scale,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PhosphorIconsBold.barcode, size: 44, color: AppColors.textMuted),
          SizedBox(height: 10),
          Text(
            'امسح باركود أو اكتب كود الصنف للبدء',
            style: TextStyle(color: AppColors.textMuted, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _ItemRow extends ConsumerWidget {
  final int index;
  final CartItemEntity item;
  final bool isSelected;
  final double scale;
  final VoidCallback onSelect;
  final VoidCallback onRemove;

  const _ItemRow({
    required this.index,
    required this.item,
    required this.isSelected,
    required this.scale,
    required this.onSelect,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.read(cartControllerProvider.notifier);
    final unitSuffix =
        item.selectedUnitName != null ? ' (${item.selectedUnitName})' : '';

    return InkWell(
      onTap: onSelect,
      child: Container(
        height: 44 * scale,
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.10)
              : (index.isEven ? AppColors.card : AppColors.surface),
          border: Border(
            bottom: const BorderSide(color: AppColors.border),
            right: BorderSide(
              color: isSelected ? AppColors.primary : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              flex: _kFlexIndex,
              child: Text('${index + 1}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13 * scale, color: AppColors.textMuted)),
            ),
            Expanded(
              flex: _kFlexName,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  '${item.productName}$unitSuffix',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13 * scale, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            Expanded(
              flex: _kFlexQty,
              child: _NumberCell(
                // The key ties the field to the row's identity AND its current
                // value: without the value in the key, a quantity changed by
                // the barcode path (scanning the same item twice) would leave
                // the visible field showing the stale number.
                key: ValueKey('qty-$index-${item.quantity}'),
                value: item.quantity,
                scale: scale,
                decimals: item.isSoldByWeight ? 3 : 2,
                onSubmitted: (v) {
                  if (v > 0) cart.updateQuantity(index, v);
                },
              ),
            ),
            Expanded(
              flex: _kFlexPrice,
              child: _NumberCell(
                key: ValueKey('price-$index-${item.effectivePrice}'),
                value: item.effectivePrice,
                scale: scale,
                decimals: 2,
                onSubmitted: (v) {
                  if (v >= 0) cart.updatePrice(index, v);
                },
              ),
            ),
            Expanded(
              flex: _kFlexDiscount,
              child: _NumberCell(
                key: ValueKey('disc-$index-${item.discountPercent}'),
                value: item.discountPercent,
                scale: scale,
                decimals: 2,
                onSubmitted: (v) {
                  if (v >= 0 && v <= 100) cart.setItemDiscount(index, v);
                },
              ),
            ),
            Expanded(
              flex: _kFlexTotal,
              child: Text(
                // ── ليه `totalBeforeTax` مش `total` ──────────────────────
                // `CartItemEntity.total` بيضيف ضريبة الصف **بلا شرط**،
                // بينما حساب الفاتورة بيتجاهل ضريبة الصف المخزّنة عن قصد
                // ويعيد حسابها على الصافي **ومشروطة بـ `taxEnabled`**
                // (اقرا التعليق في `CalculateInvoiceTotalsUseCase` — سبيك
                // ١٣٧، BUG-C02/BUG-H01).
                //
                // فالنتيجة كانت صف بيعرض رقم مالوش علاقة بأي حاجة تانية على
                // الشاشة: صنف بسعر ٥ وكمية ٧ والضريبة مقفولة كان بيعرض
                // ٤٠.٦٠٠ (٣٥ + ١٦٪) والمجموع الفرعي والإجمالي النهائي
                // الاتنين ٣٥.٠٠٠.
                //
                // العمود ده جنب «السعر» و«الخصم ٪»، فمعناه المتوقّع هو
                // ناتجهم: الكمية × السعر − الخصم. والضريبة سطر مستقل في
                // لوحة الإجماليات، مش مدسوسة في صفوف الأصناف.
                NumberUtils.formatCurrency(item.totalBeforeTax),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryDark,
                ),
              ),
            ),
            Expanded(
              flex: _kFlexRemove,
              child: IconButton(
                onPressed: onRemove,
                padding: EdgeInsets.zero,
                iconSize: 18 * scale,
                icon: const Icon(PhosphorIconsBold.x, color: AppColors.error),
                tooltip: 'إلغاء الصنف',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An inline numeric cell. Commits on submit or on losing focus; reverts to
/// the model value if the text can't be parsed, so a half-typed entry can
/// never write a garbage number into the cart.
class _NumberCell extends StatefulWidget {
  final double value;
  final int decimals;
  final double scale;
  final ValueChanged<double> onSubmitted;

  const _NumberCell({
    super.key,
    required this.value,
    required this.decimals,
    required this.scale,
    required this.onSubmitted,
  });

  @override
  State<_NumberCell> createState() => _NumberCellState();
}

class _NumberCellState extends State<_NumberCell> {
  late final TextEditingController _controller =
      TextEditingController(text: _format(widget.value));
  late final FocusNode _focus = FocusNode();

  String _format(double v) {
    final s = v.toStringAsFixed(widget.decimals);
    // Trim trailing zeros so "1.00" shows as "1" — a cashier reads the
    // column dozens of times a minute.
    return s.contains('.')
        ? s.replaceFirst(RegExp(r'\.?0+$'), '')
        : s;
  }

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  void _commit() {
    final parsed = double.tryParse(_controller.text.trim());
    if (parsed == null) {
      _controller.text = _format(widget.value);
      return;
    }
    if (parsed != widget.value) widget.onSubmitted(parsed);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        textAlign: TextAlign.center,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
        ],
        style: TextStyle(fontSize: 13 * widget.scale, fontWeight: FontWeight.w600),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
        ),
        onSubmitted: (_) => _commit(),
      ),
    );
  }
}
