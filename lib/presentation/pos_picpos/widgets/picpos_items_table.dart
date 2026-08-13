import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/config/business_profile_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/number_utils.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/entities/cart_item_entity.dart';
import '../../pos/providers/cart_controller.dart';
import '../../pos/widgets/modifier_selection_dialog.dart';
import 'picpos_numeric_keypad_dialog.dart';
import 'picpos_cart_permissions.dart';
import 'picpos_pos_text.dart';

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

  /// يُنادى بعد ما الكيبورد الرقمي يقفل بقيمة مؤكَّدة.
  ///
  /// ── ليه محتاجين ده ───────────────────────────────────────────────────────
  /// الكيبورد ديالوج، ولما بيقفل الفوكس مايرجعش لحد. والباركود سكانر جهاز
  /// **كيبورد** — بيكتب في اللي عليه الفوكس. فبعد تعديل كمية، أول مسحة باركود
  /// كانت هتروح في العدم بصمت. الشاشة بترجّع الفوكس لخانة الباركود من هنا.
  final VoidCallback? onEditComplete;

  const PicPosItemsTable({
    super.key,
    required this.selectedIndex,
    this.density = 1.0,
    required this.onSelect,
    required this.onRemove,
    this.onEditComplete,
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
    // «الإضافات والمعدلات» ميزةُ مطبخ. مقفولةٌ ⇒ لا عمودَ ولا زرّ — لا زرٌّ
    // معطَّلٌ يسأل عنه الكاشير.
    final showOptions = ref.watch(featureFlagsProvider).modifiersEnabled;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _TableHeader(scale: scale, showOptions: showOptions),
          Expanded(
            child: items.isEmpty
                ? const _EmptyState()
                : _AutoScrollItemList(
                    items: items,
                    selectedIndex: selectedIndex,
                    scale: scale,
                    showOptions: showOptions,
                    onSelect: onSelect,
                    onRemove: onRemove,
                    onEditComplete: onEditComplete,
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

/// عمودُ «الإضافات والخيارات» — يظهر فقط لما `modifiersEnabled` مفتوحة.
/// عمودٌ ثابتُ الوجود كان يسرق عرضاً من تجزئةٍ لا مطبخَ فيها.
const _kFlexOptions = 6;
const _kFlexRemove = 6;

/// The line list, with the row the cashier just touched kept on screen.
///
/// Without this the cart never scrolled at all: once the lines outgrew the
/// panel, every further add landed below the fold. The cashier kept scanning
/// into a list whose last visible row was several items stale — and the
/// selected-row highlight, which F6/F8 act on, was off-screen too.
///
/// It scrolls to the SELECTED row rather than simply to the bottom, because
/// an add doesn't always append: with «منع تراكم الأصناف» off, adding a
/// product already in the cart merges into its existing line, which may sit
/// anywhere. The parent points `selectedIndex` at whichever line changed, so
/// following the selection is correct in both cases.
class _AutoScrollItemList extends StatefulWidget {
  final List<CartItemEntity> items;
  final int? selectedIndex;
  final double scale;
  final bool showOptions;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onRemove;
  final VoidCallback? onEditComplete;

  const _AutoScrollItemList({
    required this.items,
    required this.selectedIndex,
    required this.scale,
    required this.showOptions,
    required this.onSelect,
    required this.onRemove,
    this.onEditComplete,
  });

  @override
  State<_AutoScrollItemList> createState() => _AutoScrollItemListState();
}

class _AutoScrollItemListState extends State<_AutoScrollItemList> {
  final ScrollController _controller = ScrollController();

  double get _rowExtent => 44 * widget.scale;

  @override
  void didUpdateWidget(_AutoScrollItemList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final grew = widget.items.length > oldWidget.items.length;
    final movedSelection = widget.selectedIndex != oldWidget.selectedIndex;
    if (grew || movedSelection) _revealSelected();
  }

  /// Brings the selected row fully into view, scrolling the shortest distance
  /// that does the job. Deliberately does nothing when the row is already
  /// visible — yanking the list on every quantity edit would fight the
  /// cashier for control of the scroll position.
  void _revealSelected() {
    final index = widget.selectedIndex;
    if (index == null || index < 0 || index >= widget.items.length) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final position = _controller.position;
      final extent = _rowExtent;
      final rowStart = index * extent;
      final rowEnd = rowStart + extent;
      final viewStart = position.pixels;
      final viewEnd = viewStart + position.viewportDimension;

      double? target;
      if (rowStart < viewStart) {
        target = rowStart;
      } else if (rowEnd > viewEnd) {
        target = rowEnd - position.viewportDimension;
      }
      if (target == null) return;

      _controller.animateTo(
        target.clamp(position.minScrollExtent, position.maxScrollExtent),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _controller,
      child: ListView.builder(
        controller: _controller,
        // Rows are a fixed `44 * scale` tall, so declaring the extent lets
        // the list resolve any row's offset arithmetically — that is what
        // makes scrolling to an arbitrary index possible at all here.
        itemExtent: _rowExtent,
        itemCount: widget.items.length,
        itemBuilder: (context, i) => _ItemRow(
          index: i,
          item: widget.items[i],
          isSelected: widget.selectedIndex == i,
          scale: widget.scale,
          showOptions: widget.showOptions,
          onSelect: () => widget.onSelect(i),
          onRemove: () => widget.onRemove(i),
          onEditComplete: widget.onEditComplete,
        ),
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  final double scale;
  final bool showOptions;

  const _TableHeader({required this.scale, required this.showOptions});

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
          if (showOptions) _HeaderCell('', _kFlexOptions, scale: scale),
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(PhosphorIconsBold.barcode,
              size: 44, color: AppColors.textMuted),
          const SizedBox(height: 10),
          Text(
            'امسح باركود أو اكتب كود الصنف للبدء',
            style: PicPosText.l(14),
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
  final bool showOptions;
  final VoidCallback onSelect;
  final VoidCallback onRemove;
  final VoidCallback? onEditComplete;

  const _ItemRow({
    required this.index,
    required this.item,
    required this.isSelected,
    required this.scale,
    required this.showOptions,
    required this.onSelect,
    required this.onRemove,
    this.onEditComplete,
  });

  /// حوارُ «الإضافات والخيارات + ملاحظة الصنف» للسطر.
  ///
  /// سلّةُ UralCash تفتح نفسَ المحتوى لوحاً يتوسّع تحت الصف
  /// (`cart_item_modifier_panel.dart`)، وسلّةُ PicPos جدولٌ بأعمدةٍ ثابتة
  /// وارتفاعِ صفٍّ ثابت (`itemExtent`) — فالتوسّعُ يكسرها. قرارُ المالك
  /// 2026-08-12: حوارٌ للسطر المحدَّد.
  Future<void> _openOptions(BuildContext context, WidgetRef ref) async {
    onSelect();
    final result = await ModifierSelectionDialog.showForCartItem(
      context,
      ref,
      productId: item.productId,
      productName: item.productName,
      initialSelection: item.modifiers,
      initialNote: item.itemNote,
    );
    if (result == null) return;

    // ⚠️ الترتيبُ مقصود: `updateItemNote` تُعيد تركيبَ النصّ المعروض من
    // `item.modifiers` **بعد** تحديثها. لو انعكس، رُكّب النصُّ على معدِّلاتٍ
    // قديمة فخالف المطبوعُ ما في السلّة.
    final cart = ref.read(cartControllerProvider.notifier);
    cart.updateItemModifiers(index, result.modifiers);
    cart.updateItemNote(index, result.note);

    // الحوارُ خطف الفوكس، والسكانر جهازُ كيبورد — بلا هذا تضيع أوّلُ مسحةٍ
    // بعده في العدم بصمت (نفسُ سبب `onEditComplete` في الكيبورد الرقمي).
    onEditComplete?.call();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.read(cartControllerProvider.notifier);
    final unitSuffix =
        item.selectedUnitName != null ? ' (${item.selectedUnitName})' : '';

    // ── «إظهارٌ وإخفاء» — طلبُ المالك 2026-08-12 ──────────────────────────
    // كان الفحصُ يقع في `onSubmitted` وحدَه، فالكاشيرُ يكتب الرقمَ ثم يُسأل
    // كلمةَ السرّ ثم يُرفض. المطلوبُ أن تُعطَّل الخانةُ أصلاً لمن لا يملك
    // الصلاحية، والسؤالُ عند اللمس **قبل** أيّ جهد.
    //
    // ⚠️ و`onSubmitted` يبقى هو الحدُّ الأمنيَّ ولا يُستغنى عنه: القيمةُ قد
    // تصل من مسارٍ لا يمرّ باللمس (فقدُ التركيز، Enter من كيبورد فيزيائيّ).
    // والسؤالُ لا يتكرّر لأن `_ensure` صار يستهلك موافقةَ المسؤول من ذاكرتها.
    final perms = ref.watch(currentUserPermissionsProvider).asData?.value ??
        const <String>[];
    final canQty = canEditCartQuantityCodes(perms);
    final canPrice = canEditCartPriceCodes(perms);
    final canDiscount = canApplyDiscountCodes(perms);

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
                  style: PicPosText.l(13 * scale)),
            ),
            Expanded(
              flex: _kFlexName,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  '${item.productName}$unitSuffix',
                  overflow: TextOverflow.ellipsis,
                  style: PicPosText.v(13 * scale),
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
                // نطاقات الكيبورد **مطابقة** لشروط الـ callbacks تحتها. لو
                // اختلفوا كان الكاشير هيأكّد رقم والكيبورد يقبله والسلة تتجاهله
                // بصمت — أسوأ من الرفض الصريح.
                label: 'الكمية',
                min: item.isSoldByWeight ? 0.001 : 0.01,
                onEditComplete: onEditComplete,
                canEdit: canQty,
                requestAccess: () =>
                    ensureCartQuantityPermission(ref, context),
                // التعديلُ المباشرُ في الجدول مسارٌ ثانٍ لنفس الفعل — حوارُ
                // «تعديل الصنف» هو الأول. حراسةُ أحدِهما وحدَه تترك البابَ
                // الآخرَ مفتوحاً، وهو بالضبط ما جعل الحراسةَ في `pos/` بلا
                // أثرٍ هنا. (بلاغٌ ميدانيّ 2026-08-11)
                onSubmitted: (v) async {
                  if (v <= 0) return;
                  if (!await ensureCartQuantityPermission(ref, context)) return;
                  cart.updateQuantity(index, v);
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
                label: 'السعر',
                min: 0,
                onEditComplete: onEditComplete,
                canEdit: canPrice,
                requestAccess: () => ensureCartPricePermission(ref, context),
                onSubmitted: (v) async {
                  if (v < 0) return;
                  if (!await ensureCartPricePermission(ref, context)) return;
                  cart.updatePrice(index, v);
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
                label: 'الخصم %',
                min: 0,
                max: 100,
                suffix: '%',
                onEditComplete: onEditComplete,
                canEdit: canDiscount,
                requestAccess: () => ensureCartDiscountPermission(ref, context),
                // ⚠️ كانت هذه الخانةُ **بلا فحصٍ إطلاقاً** حتى 2026-08-13 —
                // وجارتاها فوقها محروستان في نفس الملفّ، فالنمطُ كان موجوداً
                // ولم يُطبَّق عليها. ولم يكشفها الحارسُ البنيويُّ لأنه عَدَّ
                // لوناً اسمُه `AppColors.posDiscount` إنفاذاً للكود.
                onSubmitted: (v) async {
                  if (v < 0 || v > 100) return;
                  if (!await ensureCartDiscountPermission(ref, context)) return;
                  cart.setItemDiscount(index, v);
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
                // `13 * scale` مش `13`: الخانة دي كانت مثبِّتة المقاس وبتتجاهل
                // `posCartItemScaleProvider`، فسلايدر «حجم نص الأصناف» كان
                // بيكبّر كل الأعمدة إلا المجموع.
                style: PicPosText.v(13 * scale,
                    color: AppColors.primaryDark),
              ),
            ),
            if (showOptions)
              Expanded(
                flex: _kFlexOptions,
                child: IconButton(
                  onPressed: () => _openOptions(context, ref),
                  padding: EdgeInsets.zero,
                  iconSize: 18 * scale,
                  icon: Icon(
                    PhosphorIconsBold.slidersHorizontal,
                    // أخضرُ لما السطرُ يحمل شيئاً بالفعل — بلا هذا لا يفرّق
                    // الكاشيرُ بين سطرٍ بإضافاتٍ وسطرٍ بلا، والجدولُ لا
                    // يتّسع لعرضها نصّاً.
                    color: (item.modifiers.isNotEmpty ||
                            (item.itemNote?.isNotEmpty ?? false))
                        ? AppColors.success
                        : AppColors.textMuted,
                  ),
                  tooltip: 'الإضافات والخيارات وملاحظة الصنف',
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
///
/// **الضغط عليها بيفتح كيبورد رقمي** ([PicPosNumericKeypadDialog]) في الوضعين
/// اللمسي والعادي — والتحرير السطري بالكيبورد الفيزيائي (Tab ثم كتابة) يفضل
/// شغال زي ما هو، فالكاشير على ديسكتوب ما بيخسرش سرعته.
class _NumberCell extends StatefulWidget {
  final double value;
  final int decimals;
  final double scale;
  final ValueChanged<double> onSubmitted;

  /// عنوان الكيبورد — يعرّف الكاشير خانة إيه اللي بيعدّلها بعد ما الديالوج
  /// يغطي الصف.
  final String label;

  /// نطاق التحقّق داخل الكيبورد. لازم يطابق شرط [onSubmitted].
  final double? min;
  final double? max;
  final String? suffix;

  /// بعد قفل الكيبورد بقيمة مؤكَّدة — الشاشة بترجّع الفوكس للباركود.
  final VoidCallback? onEditComplete;

  /// هل يملك المستخدمُ صلاحيةَ تعديل هذه الخانة؟
  ///
  /// `false` ⇒ الخانةُ معطَّلةٌ بصرياً ولا تُكتَب مباشرةً، واللمسُ يستأذن
  /// **قبل** فتح الكيبورد. وهذا طلبُ المالك الصريح: «إظهارٌ وإخفاء، لا رفضٌ
  /// بعد الجهد».
  final bool canEdit;

  /// يُستدعى عند لمس خانةٍ معطَّلة — يطلب موافقةَ مسؤولٍ ويعيد نتيجتَها.
  final Future<bool> Function() requestAccess;

  const _NumberCell({
    super.key,
    required this.value,
    required this.decimals,
    required this.scale,
    required this.onSubmitted,
    required this.label,
    required this.canEdit,
    required this.requestAccess,
    this.min,
    this.max,
    this.suffix,
    this.onEditComplete,
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

  /// يفتح الكيبورد الرقمي. `unfocus()` الأول مقصود: في الوضع اللمسي الفوكس على
  /// الخانة بيرفع `TouchKeyboardOverlay` العام كمان، فبقى فيه كيبوردين على
  /// الشاشة. بنسيب الفوكس قبل ما نفتح الديالوج فيبقى واحد بس.
  Future<void> _openKeypad() async {
    _focus.unfocus();
    // الاستئذانُ **قبل** الكيبورد: بلا هذا يكتب الكاشيرُ الرقمَ ثم يُرفض.
    if (!widget.canEdit) {
      final granted = await widget.requestAccess();
      if (!mounted) return;
      if (!granted) {
        widget.onEditComplete?.call();
        return;
      }
      // الموافقةُ محفوظةٌ في `ManagerApprovalCache` ويستهلكها `onSubmitted`،
      // فلا يُسأل المسؤولُ مرّتين للتعديل الواحد.
    }
    final v = await PicPosNumericKeypadDialog.show(
      context,
      title: widget.label,
      initialValue: widget.value,
      decimals: widget.decimals,
      min: widget.min,
      max: widget.max,
      suffix: widget.suffix,
    );
    if (!mounted) return;
    if (v != null) {
      _controller.text = _format(v);
      widget.onSubmitted(v);
    }
    // بيتنادى في حالتي التأكيد والإلغاء: الفوكس ضاع مع فتح الديالوج في
    // الحالتين، فالباركود لازم يرجع يشتغل في الحالتين.
    widget.onEditComplete?.call();
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
        style: PicPosText.v(13 * widget.scale,
            color: widget.canEdit ? null : AppColors.textMuted),
        // `readOnly` لا `enabled: false`: المعطَّلُ لا يستقبل `onTap` أصلاً،
        // فيضيع بابُ موافقة المسؤول. والقراءةُ فقط تمنع الكتابةَ المباشرة
        // (‏كيبورد فيزيائيّ) وتُبقي اللمسَ يستأذن.
        readOnly: !widget.canEdit,
        decoration: InputDecoration(
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          border: const OutlineInputBorder(),
          filled: true,
          fillColor: widget.canEdit ? Colors.white : AppColors.border,
        ),
        onTap: _openKeypad,
        onSubmitted: (_) => _commit(),
      ),
    );
  }
}
