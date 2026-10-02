import 'package:ural_erp/core/i18n/tr.dart';
// لبِناتُ استمارة المرتجع (مبيعاتٍ ومشتريات) على تصميم المالك المرجعيّ —
// المرحلة C2 من البند ٣.
//
// ═══ لماذا ملفٌّ مشتركٌ لا نسختان ═══
//
// شاشتا «مرتجع المبيعات» و«مردود المشتريات» ترسمان **نفسَ** الاستمارة:
// رأسُ صفحةٍ (العنوان + الرقم + شارةُ الحالة) ← بطاقةُ حقول الترويسة ←
// جدولُ الأصناف المرتجعة ← كتلةُ التسوية بجوار «تفاصيل إضافية» ← شريطُ
// الأفعال. وبناؤها في كلّ شاشةٍ على حدة هو بعينه الازدواجُ الذي ينحرف بأوّل
// تعديل (راجع رأسَ `picpos_returns_panel.dart`).
//
// ⚠️ **والمقاساتُ والألوانُ منقولةٌ عن استمارة الفاتورة المعاد تصميمها**
// (`invoice_form_picpos/picpos_invoice_layout.dart` و`_PicPosDocBar`): خليّةُ
// الحقل بارتفاع ٦٤ وحدودٍ بنصف قطر ١١، والشبكةُ ٤/٣/٢ أعمدةً بالعرض، وشارةُ
// الحالة، وشريطُ الأفعال بأزرارٍ ارتفاعُها ٤٤. تلك لبِناتٌ خاصّةٌ مربوطةٌ
// بحالة الفاتورة (`part of`) فلا تُستورَد، فنُقل شكلُها هنا عامّاً.
//
// 🔴 **عرضٌ خالص.** لا يعرف هذا الملفُّ القاعدةَ ولا Riverpod ولا مزوّداً:
// يستقبل نصوصاً وأرقاماً وردودَ نداء. كلُّ تحقّقٍ وترقيمٍ وقيدٍ ومخزونٍ في
// منادي الشاشة كما كان.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import 'picpos_surface.dart';

/// مبلغٌ بدقّة العملة.
String picposReturnMoney(double v) =>
    v.toStringAsFixed(AppConstants.decimalPlaces);

/// كمّيّةٌ بلا أصفارٍ زائدة: «٥» لا «5.000»، و«2.5» كما هي.
String picposReturnQty(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  var s = v.toStringAsFixed(3);
  while (s.endsWith('0')) {
    s = s.substring(0, s.length - 1);
  }
  return s.endsWith('.') ? s.substring(0, s.length - 1) : s;
}

/// حالةُ سداد الفاتورة الأصليّة — **عرضٌ مشتقٌّ** من الإجماليّ والمدفوع.
String picposPaymentStatusLabel({required double total, required double paid}) {
  if (paid <= 0.0005) return tr('غير مسددة');
  if (total - paid <= 0.0005) return tr('مسددة');
  return tr('مسددة جزئياً');
}

/// بطاقةٌ بأرضيّة البطاقة وحدودِ الفاصل — نفسُ بطاقات استمارة الفاتورة.
class PicPosFormCard extends StatelessWidget {
  const PicPosFormCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }
}

/// رأسُ الصفحة — العنوانُ والرقمُ وشارةُ الحالة (كـ`_PicPosPageHeader`).
///
/// ⚠️ [number] نصٌّ يُمرَّر لا رقمٌ يُحسَب هنا: رقمُ المرتجع يُولَّد داخلَ
/// معاملة الحفظ، فالمنادي يمرّر «يُولَّد تلقائياً» لا رقماً مُخمَّناً.
class PicPosDocPageHeader extends StatelessWidget {
  const PicPosDocPageHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.number,
    required this.statusLabel,
    this.statusColor = AppColors.info,
  });

  final IconData icon;
  final String title;
  final String number;
  final String statusLabel;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    final muted = context.picposMuted;
    return Row(
      children: [
        Icon(icon, size: 22, color: AppColors.primary),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            number,
            key: const Key('picpos_return_header_number'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: muted,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          key: const Key('picpos_return_status_chip'),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: .12),
            border: Border.all(color: statusColor.withValues(alpha: .4)),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            statusLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: statusColor,
            ),
          ),
        ),
      ],
    );
  }
}

/// شبكةُ حقول الترويسة — أربعةُ أعمدةٍ على ١٣٦٦ فما فوق، وثلاثةٌ ثمّ اثنان
/// دونه، فلا حقلَ يُسحَق ولا فيضَ أفقيّ (نفسُ قاعدة `_PicPosDocBar`).
class PicPosFormGrid extends StatelessWidget {
  const PicPosFormGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 1000
            ? 4
            : c.maxWidth >= 640
                ? 3
                : 2;
        const gap = 10.0;
        final cellW = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children)
              SizedBox(
                width: cellW,
                height: 64,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.dividerColor),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: child,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// عنوانُ الحقل الصغير — أيقونةٌ ونصٌّ ونجمةُ الإلزام.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel({
    required this.icon,
    required this.label,
    required this.required,
  });

  final IconData icon;
  final String label;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final muted = context.picposMuted;
    return Row(
      children: [
        Icon(icon, size: 11, color: muted),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              color: muted,
            ),
          ),
        ),
        if (required) ...[
          const SizedBox(width: 3),
          const Text(
            '*',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.error,
            ),
          ),
        ],
      ],
    );
  }
}

/// حقلٌ في الشبكة — قراءةٌ أو اختيارٌ بنقرة.
///
/// [readOnly] يرسمه بأرضيّة الحقل الخافتة كما في التصميم: قيمةٌ مشتقّةٌ من
/// الفاتورة الأصليّة لا تُحرَّر هنا.
class PicPosFormField extends StatelessWidget {
  const PicPosFormField({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.required = false,
    this.readOnly = false,
    this.trailing,
    this.valueColor,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool required;
  final bool readOnly;
  final IconData? trailing;
  final Color? valueColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = context.picposMuted;
    return Material(
      color: readOnly ? context.picposField : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          // ⚠️ حشوٌ أصغرُ من خليّة الفاتورة (١٠/٥): خطُّ الثيم العربيّ أطولُ
          // سطراً من خطّ الاختبار الافتراضيّ، فيفيض الحقلُ بكسلَين في ٦٤.
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _FieldLabel(icon: icon, label: label, required: required),
              const SizedBox(height: 3),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: valueColor ?? theme.textTheme.bodyLarge?.color,
                        fontFeatures: const [ui.FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  if (trailing != null) Icon(trailing, size: 12, color: muted),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// حقلُ قائمةٍ في الشبكة — لسبب المرتجع.
///
/// ⚠️ القيمةُ خارجَ القائمة تُعرَض فارغةً لا تُسقط الشاشة: `DropdownButton`
/// يؤكّد أنّ قيمتَه بين عناصره، وتبديلُ اللغة يقلب نصوصَ القائمة.
class PicPosFormDropdownField extends StatelessWidget {
  const PicPosFormDropdownField({
    super.key,
    required this.icon,
    required this.label,
    required this.items,
    required this.value,
    required this.onChanged,
    this.required = false,
    this.hint,
  });

  final IconData icon;
  final String label;
  final List<String> items;
  final String? value;
  final ValueChanged<String?>? onChanged;
  final bool required;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = context.picposMuted;
    final missing = required && (value == null || !items.contains(value));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _FieldLabel(icon: icon, label: label, required: required),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: items.contains(value) ? value : null,
              isExpanded: true,
              isDense: true,
              iconSize: 16,
              icon: Icon(PhosphorIconsBold.caretDown, size: 12, color: muted),
              dropdownColor: theme.cardColor,
              hint: Text(
                hint ?? tr('اختر'),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: missing ? AppColors.error : muted,
                ),
              ),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: theme.textTheme.bodyLarge?.color,
              ),
              items: [
                for (final r in items)
                  DropdownMenuItem(
                    value: r,
                    child: Text(r, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// سطرٌ في جدول الأصناف المرتجعة — أرقامٌ جاهزةٌ من المنادي.
class PicPosReturnLine {
  const PicPosReturnLine({
    required this.id,
    required this.name,
    required this.originalQty,
    required this.previouslyReturned,
    required this.available,
    required this.returnQty,
    required this.unitPrice,
    required this.lineValue,
    this.editable = true,
  });

  final int id;
  final String name;

  /// المُباعة (مرتجع المبيعات) أو المُشتراة (مردود المشتريات).
  final double originalQty;
  final double previouslyReturned;

  /// السقفُ الفعليّ — المنادي يحسبه بدالّة المحرّك نفسِها.
  final double available;
  final double returnQty;
  final double unitPrice;
  final double lineValue;
  final bool editable;

  /// الكسورُ للصنف الموزون وحدَه — صنفُ القطعة كان يُردّ بخطوة ١ (أزرار
  /// −/+)، فحقلٌ يقبل «٠٫٥» منه يفتح ما لم يكن مفتوحاً.
  bool get allowsFraction =>
      originalQty != originalQty.roundToDouble() ||
      available != available.roundToDouble();
}

/// جدولُ الأصناف المرتجعة: # / الصنف / المباعة|المشتراة / المرتجع سابقاً /
/// المتاح حالياً / كمّيّة المرتجع (قابلةٌ للتحرير) / السعر / القيمة.
class PicPosReturnLinesTable extends StatelessWidget {
  const PicPosReturnLinesTable({
    super.key,
    required this.lines,
    required this.originalQtyLabel,
    required this.returnQtyLabel,
    required this.unitPriceLabel,
    required this.lineValueLabel,
    required this.onQtyChanged,
    required this.emptyMessage,
    this.loading = false,
  });

  final List<PicPosReturnLine> lines;
  final String originalQtyLabel;
  final String returnQtyLabel;
  final String unitPriceLabel;
  final String lineValueLabel;
  final void Function(int id, double qty) onQtyChanged;
  final String emptyMessage;
  final bool loading;

  static const _flex = [26, 12, 12, 12, 0, 12, 13];
  static const _qtyWidth = 124.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = context.picposMuted;

    Widget cells(List<Widget> c) => Row(
          children: [
            SizedBox(width: 34, child: c[0]),
            for (var i = 1; i < c.length; i++)
              if (_flex[i - 1] == 0)
                SizedBox(
                  width: _qtyWidth,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(end: 10),
                    child: c[i],
                  ),
                )
              else
                Expanded(
                  flex: _flex[i - 1],
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: c[i],
                  ),
                ),
          ],
        );

    Text head(String s) => Text(
          s,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: muted,
          ),
        );

    Text fig(String s, {Color? color, FontWeight w = FontWeight.w600}) => Text(
          s,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: w,
            color: color ?? theme.textTheme.bodyLarge?.color,
            fontFeatures: const [ui.FontFeature.tabularFigures()],
          ),
        );

    final header = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: context.picposField,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: cells([
        head('#'),
        head(tr('الصنف')),
        head(originalQtyLabel),
        head(tr('المرتجع سابقاً')),
        head(tr('المتاح حالياً')),
        Row(children: [
          Flexible(child: head(returnQtyLabel)),
          const Text(' *',
              style: TextStyle(fontSize: 11, color: AppColors.error)),
        ]),
        head(unitPriceLabel),
        head(lineValueLabel),
      ]),
    );

    final Widget body;
    if (loading) {
      body = const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (lines.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        child: Center(
          child: Text(
            emptyMessage,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: muted),
          ),
        ),
      );
    } else {
      body = Column(
        children: [
          for (var i = 0; i < lines.length; i++)
            Container(
              key: ValueKey('picpos_return_line_${lines[i].id}'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: i == lines.length - 1
                    ? null
                    : Border(bottom: BorderSide(color: theme.dividerColor)),
              ),
              child: cells([
                fig('${i + 1}', color: muted),
                Text(
                  lines[i].name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: lines[i].available <= 0
                        ? muted
                        : theme.textTheme.bodyLarge?.color,
                    decoration: lines[i].available <= 0
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                fig(picposReturnQty(lines[i].originalQty)),
                fig(
                  picposReturnQty(lines[i].previouslyReturned),
                  color: lines[i].previouslyReturned > 0
                      ? AppColors.warning
                      : null,
                ),
                fig(
                  picposReturnQty(lines[i].available),
                  color: lines[i].available <= 0 ? AppColors.error : null,
                  w: FontWeight.w800,
                ),
                PicPosReturnQtyField(
                  key: ValueKey('picpos_return_qty_${lines[i].id}'),
                  value: lines[i].returnQty,
                  max: lines[i].available,
                  enabled: lines[i].editable && lines[i].available > 0,
                  allowFraction: lines[i].allowsFraction,
                  onChanged: (q) => onQtyChanged(lines[i].id, q),
                ),
                fig(picposReturnMoney(lines[i].unitPrice)),
                fig(
                  picposReturnMoney(lines[i].lineValue),
                  w: FontWeight.w800,
                  color: lines[i].returnQty > 0 ? AppColors.warning : null,
                ),
              ]),
            ),
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [header, body],
      ),
    );
  }
}

/// حقلُ كمّيّة المرتجع.
///
/// 🔴 **ما يتجاوز المتاحَ يُرفَض ولا يُمرَّر.** كان الحدُّ زرَّ «+» يتعطّل
/// عند المتاح، فلا سبيلَ لتجاوزه. والحقلُ الحرُّ يحفظ القاعدةَ نفسَها: رقمٌ
/// أكبرُ من [max] لا يصل ردَّ النداء، ويُعرَض الخطأ، وتعود القيمةُ المقبولةُ
/// عند مغادرة الحقل. (والمحرّكُ يرفضه مرّةً ثانيةً عند التنفيذ كما كان.)
class PicPosReturnQtyField extends StatefulWidget {
  const PicPosReturnQtyField({
    super.key,
    required this.value,
    required this.max,
    required this.onChanged,
    this.enabled = true,
    this.allowFraction = false,
  });

  final double value;
  final double max;
  final ValueChanged<double> onChanged;
  final bool enabled;
  final bool allowFraction;

  @override
  State<PicPosReturnQtyField> createState() => _PicPosReturnQtyFieldState();
}

class _PicPosReturnQtyFieldState extends State<PicPosReturnQtyField> {
  late final TextEditingController _ctrl =
      TextEditingController(text: picposReturnQty(widget.value));
  final _focus = FocusNode();
  String? _error;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _revertIfRejected();
    });
  }

  @override
  void didUpdateWidget(covariant PicPosReturnQtyField old) {
    super.didUpdateWidget(old);
    // القيمةُ تتبدّل من خارج الحقل («إرجاع الفاتورة كاملة» مثلاً).
    if (!_focus.hasFocus &&
        (old.value != widget.value ||
            _ctrl.text != picposReturnQty(widget.value))) {
      _ctrl.text = picposReturnQty(widget.value);
      _error = null;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _revertIfRejected() {
    if (_error == null) return;
    setState(() {
      _error = null;
      _ctrl.text = picposReturnQty(widget.value);
    });
  }

  void _onText(String text) {
    final v = text.trim().isEmpty ? 0.0 : double.tryParse(text.trim());
    if (v == null || v < 0) {
      setState(() => _error = tr('كمية غير صالحة'));
      return;
    }
    if (v > widget.max + 0.0005) {
      setState(() => _error = tr('الكمية تتجاوز المتاح ({p0})',
          {'p0': picposReturnQty(widget.max)}));
      return;
    }
    if (_error != null) setState(() => _error = null);
    widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final err = _error;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(
        color: err != null ? AppColors.error : theme.dividerColor,
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 34,
          child: TextField(
            controller: _ctrl,
            focusNode: _focus,
            enabled: widget.enabled,
            onChanged: _onText,
            onSubmitted: (_) => _revertIfRejected(),
            keyboardType:
                TextInputType.numberWithOptions(decimal: widget.allowFraction),
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                widget.allowFraction ? RegExp(r'^\d*\.?\d{0,3}') : RegExp(r'^\d*'),
              ),
            ],
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              fontFeatures: [ui.FontFeature.tabularFigures()],
            ),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: widget.enabled ? theme.cardColor : context.picposField,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: border,
              enabledBorder: border,
              disabledBorder: border,
              focusedBorder: border.copyWith(
                borderSide: BorderSide(
                  color: err != null ? AppColors.error : AppColors.primary,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ),
        if (err != null)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              err,
              maxLines: 2,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.error,
              ),
            ),
          ),
      ],
    );
  }
}

/// صفٌّ في كتلة التسوية.
class PicPosSettlementRow {
  const PicPosSettlementRow(this.label, this.value);
  final String label;
  final String value;
}

/// كتلةُ «تسوية المبلغ» — **مرآةٌ مشتقّةٌ لا حقولُ إدخال.**
///
/// 🔴 «طريقة التسوية» تُعرَض **حقلاً مقروءاً** لا قائمةً منسدلة: المحرّكُ
/// في الجانبَين يقسم آليّاً (الذمّةُ أوّلاً ثمّ النقد) ولا يستشير اختياراً.
/// فقائمةٌ تُعرَض ولا تُقرأ أسوأُ من غيابها (قرارُ المالك 2026-09-18).
class PicPosSettlementCard extends StatelessWidget {
  const PicPosSettlementCard({
    super.key,
    required this.title,
    required this.method,
    required this.rows,
    required this.resultLabel,
    required this.resultValue,
  });

  final String title;
  final String method;
  final List<PicPosSettlementRow> rows;
  final String resultLabel;
  final String resultValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = context.picposMuted;

    Widget line(String label, Widget value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: muted,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(flex: 6, child: value),
            ],
          ),
        );

    Widget box(String text, {Key? key, bool emphasis = false, IconData? icon}) =>
        Container(
          key: key,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: emphasis
                ? AppColors.primary.withValues(alpha: .10)
                : context.picposField,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: emphasis ? 15 : 12.5,
                    fontWeight: emphasis ? FontWeight.w800 : FontWeight.w700,
                    color: emphasis
                        ? context.picposBrandInk
                        : theme.textTheme.bodyLarge?.color,
                    fontFeatures: const [ui.FontFeature.tabularFigures()],
                  ),
                ),
              ),
              if (icon != null) Icon(icon, size: 12, color: muted),
            ],
          ),
        );

    return PicPosFormCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          line(
            tr('طريقة التسوية'),
            box(
              method,
              key: const Key('picpos_return_settlement_method'),
              icon: PhosphorIconsBold.lockSimple,
            ),
          ),
          for (final r in rows) line(r.label, box(r.value)),
          line(resultLabel, box(resultValue, emphasis: true)),
        ],
      ),
    );
  }
}

/// «تفاصيل إضافية» — صفٌّ مطويٌّ كما في استمارة الفاتورة.
///
/// [forceOpen] يفتحه متى صار فيه ما يجب أن يُرى (نصُّ سببٍ حرٍّ مثلاً)،
/// فلا يُخفي الطيُّ حقلاً مطلوباً.
class PicPosCollapsibleCard extends StatefulWidget {
  const PicPosCollapsibleCard({
    super.key,
    required this.title,
    required this.child,
    this.forceOpen = false,
  });

  final String title;
  final Widget child;
  final bool forceOpen;

  @override
  State<PicPosCollapsibleCard> createState() => _PicPosCollapsibleCardState();
}

class _PicPosCollapsibleCardState extends State<PicPosCollapsibleCard> {
  late bool _open = widget.forceOpen;

  @override
  void didUpdateWidget(covariant PicPosCollapsibleCard old) {
    super.didUpdateWidget(old);
    if (widget.forceOpen && !old.forceOpen) _open = true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = context.picposMuted;
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              key: const Key('picpos_return_details_toggle'),
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
                child: Row(
                  children: [
                    Icon(PhosphorIconsBold.fileText, size: 15, color: muted),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Icon(
                      _open
                          ? PhosphorIconsBold.caretUp
                          : PhosphorIconsBold.caretDown,
                      size: 13,
                      color: muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: widget.child,
            ),
        ],
      ),
    );
  }
}

/// شريطُ الأفعال الثابتُ أسفلَ الشاشة — بشكل شريط استمارة الفاتورة.
///
/// ⚠️ **J2 (قرارُ المالك):** «حفظ مسودة» صار له دورةُ حياة (`return_drafts`)
/// فعاد زرّاً ثانوياً — يُعرَض متى مُرِّر [secondaryLabel]، ولا يُعرَض إلا ما
/// له معالجٌ قائم.
class PicPosReturnActionBar extends StatelessWidget {
  const PicPosReturnActionBar({
    super.key,
    required this.primaryLabel,
    required this.onPrimary,
    this.onBack,
    this.busy = false,
    this.hint,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String primaryLabel;

  /// الفعلُ المرحِّل — `null` يعطّله ولا يخفيه.
  final VoidCallback? onPrimary;

  /// «حفظ مسودة» — يُعرَض متى مُرِّر نصُّه، و`null` [onSecondary] يعطّله.
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  /// «رجوع» — يُخفى متى لم يكن خلفَ الشاشة ما يُرجَع إليه.
  final VoidCallback? onBack;
  final bool busy;

  /// ما ينقص قبل التنفيذ — يُقال لا يُخفى.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onPrimaryInk = theme.colorScheme.onPrimary;
    return LayoutBuilder(
      builder: (context, c) {
        final pad = c.maxWidth >= 960 ? 20.0 : 12.0;
        return Container(
          padding: EdgeInsetsDirectional.fromSTEB(pad, 10, pad, 10),
          decoration: BoxDecoration(
            color: theme.cardColor,
            border: Border(top: BorderSide(color: theme.dividerColor)),
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 8,
            spacing: 12,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.icon(
                    key: const Key('picpos_return_approve'),
                    onPressed: busy ? null : onPrimary,
                    icon: busy
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: onPrimaryInk,
                            ),
                          )
                        : const Icon(PhosphorIconsBold.checkCircle, size: 16),
                    label: Text(
                      primaryLabel,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: onPrimaryInk,
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11),
                      ),
                    ),
                  ),
                  if (secondaryLabel != null)
                    OutlinedButton.icon(
                      key: const Key('picpos_return_save_draft'),
                      onPressed: busy ? null : onSecondary,
                      icon: const Icon(PhosphorIconsBold.floppyDisk, size: 15),
                      label: Text(
                        secondaryLabel!,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        side: BorderSide(color: theme.dividerColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11),
                        ),
                      ),
                    ),
                  if (hint != null)
                    Text(
                      hint!,
                      key: const Key('picpos_return_action_hint'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.picposMuted,
                      ),
                    ),
                ],
              ),
              if (onBack != null)
                OutlinedButton.icon(
                  key: const Key('picpos_return_back'),
                  onPressed: busy ? null : onBack,
                  // نفسُ علاج `PicPosPageHeader`: `arrow_back` يحمل
                  // `matchTextDirection` فينقلب مع الاتجاه وحدَه (→ في RTL
                  // و← في LTR) بلا فرعٍ يدويٍّ على `Directionality`.
                  icon: const Icon(Icons.arrow_back, size: 15),
                  label: Text(
                    tr('رجوع'),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    side: BorderSide(color: theme.dividerColor),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// تخطيطُ الاستمارة: محتوىً يتمرّر وشريطُ أفعالٍ ثابت.
///
/// [details] على البداية و[settlement] على النهاية كما في التصميم (اليمينُ
/// واليسارُ في العربيّة)، ويتراصّان عموداً تحت ٩٦٠ بكسل.
class PicPosReturnFormLayout extends StatelessWidget {
  const PicPosReturnFormLayout({
    super.key,
    required this.header,
    required this.lines,
    required this.settlement,
    required this.details,
    required this.actionBar,
  });

  final Widget header;
  final Widget lines;
  final Widget settlement;
  final Widget details;
  final Widget actionBar;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 960;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                key: const Key('picpos_return_scroll'),
                padding: const EdgeInsetsDirectional.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    const SizedBox(height: 12),
                    lines,
                    const SizedBox(height: 12),
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: details),
                          const SizedBox(width: 14),
                          Expanded(child: settlement),
                        ],
                      )
                    else ...[
                      settlement,
                      const SizedBox(height: 12),
                      details,
                    ],
                  ],
                ),
              ),
            ),
            actionBar,
          ],
        );
      },
    );
  }
}

/// مفتاحٌ اختياريٌّ صغير — زرّا «كامل/محدّد» وصندوقُ الإتلاف في رأس الجدول.
class PicPosToggleChip extends StatelessWidget {
  const PicPosToggleChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.tone = AppColors.primary,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Color tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = context.picposMuted;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? tone.withValues(alpha: .12) : null,
            border: Border.all(
              color: selected ? tone : theme.dividerColor,
            ),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon ??
                    (selected
                        ? PhosphorIconsBold.checkCircle
                        : PhosphorIconsBold.circle),
                size: 13,
                color: selected ? tone : muted,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? tone : theme.textTheme.bodyMedium?.color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
