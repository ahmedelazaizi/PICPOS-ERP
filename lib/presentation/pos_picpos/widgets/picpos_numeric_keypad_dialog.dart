import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../picpos_shell/picpos_surface.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/number_utils.dart';
import 'picpos_pos_text.dart';

/// كيبورد رقمي لخانات السلة (الكمية / السعر / الخصم).
///
/// بيرجّع `null` لو المستخدم ألغى أو القيمة مش صالحة — والمستدعي ساعتها
/// **مايلمسش المودل**، فنفس ضمانة `_NumberCell` القديمة (نص نصف مكتوب عمره ما
/// يكتب رقم قمامة في السلة) محفوظة.
///
/// ── ليه ودجت جديدة ومش `AppOSK` ──────────────────────────────────────────
/// مفاتيح `AppOSK` بتعمل `controller.text += value` (`app_osk.dart:113`) — أي
/// **بتضيف**. خانة كمية فيها `1` وتضغط `5` تبقى `15` مش `5`، وده عكس اللي
/// الكاشير عايزه في ٩٩٪ من الحالات (استبدال). ومستدعيه التاني
/// (`pos_barcode_input.dart:170`) **بيعتمد** على الإضافة — الباركود بيتبنى رقم
/// رقم — فتغيير السلوك هناك كان بيكسر السحب.
///
/// و`NumericLayout` (فيتشر ٠٣١) مش قابل للوصول غير من `TouchKeyboardOverlay`،
/// واللي بيرجع فوراً لما `touchModeProvider` مقفول (`main.dart:1325`) — فمايقدرش
/// يحقق «يسري في النظامين اللمسي والعادي».
///
/// ── الكيبورد الفيزيائي لازم يفضل شغال ────────────────────────────────────
/// خانة القراءة `autofocus` و**محدَّدة بالكامل** عند الفتح، فأول ضغطة من
/// كيبورد الديسكتوب بتستبدل القيمة و`Enter` بيأكّد. المفاتيح على الشاشة
/// `canRequestFocus: false` عشان الضغط عليها مايسحبش الفوكس من الخانة.
class PicPosNumericKeypadDialog extends StatefulWidget {
  final String title;
  final double initialValue;
  final int decimals;
  final double? min;
  final double? max;
  final String? suffix;

  const PicPosNumericKeypadDialog({
    super.key,
    required this.title,
    required this.initialValue,
    required this.decimals,
    this.min,
    this.max,
    this.suffix,
  });

  /// يرجّع القيمة المؤكَّدة، أو `null` عند الإلغاء.
  static Future<double?> show(
    BuildContext context, {
    required String title,
    required double initialValue,
    required int decimals,
    double? min,
    double? max,
    String? suffix,
  }) {
    return showDialog<double>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: PicPosNumericKeypadDialog(
          title: title,
          initialValue: initialValue,
          decimals: decimals,
          min: min,
          max: max,
          suffix: suffix,
        ),
      ),
    );
  }

  @override
  State<PicPosNumericKeypadDialog> createState() =>
      _PicPosNumericKeypadDialogState();
}

class _PicPosNumericKeypadDialogState
    extends State<PicPosNumericKeypadDialog> {
  late final TextEditingController _controller;
  late final FocusNode _focus;

  /// أول ضغطة رقم بعد الفتح **بتستبدل** القيمة كلها، واللي بعدها بيضيف.
  /// ده اللي بيخلي «اضغط الخانة واكتب ٧» تعمل ٧ مش ١٧.
  bool _pristine = true;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _format(widget.initialValue));
    // تحديد كامل عند الفتح: الكتابة من الكيبورد الفيزيائي تستبدل زي ما ضغطة
    // المفتاح على الشاشة بتستبدل.
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
    _focus = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _format(double v) {
    final s = v.toStringAsFixed(widget.decimals);
    return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
  }

  double? get _parsed => NumberUtils.tryParseLocale(_controller.text);

  /// رسالة الخطأ الحالية، أو `null` لو القيمة صالحة.
  String? get _error {
    final v = _parsed;
    if (v == null) return tr('قيمة غير صحيحة');
    if (widget.min != null && v < widget.min!) {
      return tr('أقل قيمة مسموحة {p0}', {'p0': _format(widget.min!)});
    }
    if (widget.max != null && v > widget.max!) {
      return tr('أكبر قيمة مسموحة {p0}', {'p0': _format(widget.max!)});
    }
    return null;
  }

  void _press(String ch) {
    setState(() {
      if (_pristine) {
        _controller.text = ch == '.' ? '0.' : ch;
        _pristine = false;
      } else {
        // نقطة عشرية واحدة بس — تانية كانت هتخلي التحليل يفشل والتأكيد يتقفل
        // بلا سبب واضح للكاشير.
        if (ch == '.' && _controller.text.contains('.')) return;
        _controller.text += ch;
      }
      _controller.selection =
          TextSelection.collapsed(offset: _controller.text.length);
    });
  }

  void _backspace() {
    setState(() {
      _pristine = false;
      final t = _controller.text;
      _controller.text = t.isEmpty ? '' : t.substring(0, t.length - 1);
      _controller.selection =
          TextSelection.collapsed(offset: _controller.text.length);
    });
  }

  void _clear() {
    setState(() {
      _pristine = false;
      _controller.text = '';
      _controller.selection = const TextSelection.collapsed(offset: 0);
    });
  }

  void _confirm() {
    if (_error != null) return;
    // نقرّب على عدد الخانات العشرية المسموح — صنف بخانتين عشريتين مايستحقش
    // يستقبل 1.23456 من لصق أو من كيبورد فيزيائي.
    final v = double.parse(_parsed!.toStringAsFixed(widget.decimals));
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(PhosphorIconsBold.calculator, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(widget.title, style: PicPosText.v(context, 16)),
        ],
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              focusNode: _focus,
              autofocus: true,
              textAlign: TextAlign.center,
              textDirection: TextDirection.ltr,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[0-9.٠-٩٫،,]')),
              ],
              style: PicPosText.v(context, 30),
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: context.picposCard,
                suffixText: widget.suffix,
                errorText: error,
                errorStyle: PicPosText.v(context, 12, color: AppColors.error),
              ),
              onChanged: (_) => setState(() => _pristine = false),
              onSubmitted: (_) => _confirm(),
            ),
            const SizedBox(height: 12),
            _row(const ['7', '8', '9'], trailing: _actionKey(
              id: 'backspace',
              icon: PhosphorIconsBold.backspace,
              color: AppColors.warning,
              onTap: _backspace,
            )),
            _row(const ['4', '5', '6'], trailing: _actionKey(
              id: 'clear',
              label: 'C',
              color: AppColors.error,
              onTap: _clear,
            )),
            _row(const ['1', '2', '3'], trailing: _digitKey('.')),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [Expanded(child: _digitKey('0'))]),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('إلغاء'), style: PicPosText.l(context, 14)),
        ),
        ElevatedButton.icon(
          onPressed: error == null ? _confirm : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.success,
            foregroundColor: Colors.white,
          ),
          icon: const Icon(PhosphorIconsBold.check, size: 18),
          label:  Text(tr('تأكيد')),
        ),
      ],
    );
  }

  Widget _row(List<String> digits, {required Widget trailing}) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          for (final d in digits) ...[
            Expanded(child: _digitKey(d)),
            const SizedBox(width: 6),
          ],
          Expanded(child: trailing),
        ],
      ),
    );
  }

  Widget _digitKey(String value) => _KeyButton(
        // مفتاح ثابت لكل زرار: نص الزرار لوحده مش كافي للتمييز، لأن نفس الرقم
        // ممكن يكون معروض في خانة القراءة كذلك — واختبار بيدوّر على '1' كان
        // بيلاقي اتنين.
        key: ValueKey('keypad-$value'),
        label: value,
        onTap: () => _press(value),
      );

  Widget _actionKey({
    required String id,
    String? label,
    IconData? icon,
    required Color color,
    required VoidCallback onTap,
  }) =>
      _KeyButton(
        key: ValueKey('keypad-$id'),
        label: label,
        icon: icon,
        color: color,
        onTap: onTap,
      );
}

/// مفتاح واحد. `canRequestFocus: false` مقصود — الضغط عليه مايسحبش الفوكس من
/// خانة القراءة، فالكيبورد الفيزيائي يفضل شغال وسط الضغط على الشاشة.
class _KeyButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final Color? color;
  final VoidCallback onTap;

  const _KeyButton({
    super.key,
    this.label,
    this.icon,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return SizedBox(
      height: 48,
      child: InkWell(
        onTap: onTap,
        canRequestFocus: false,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.withValues(alpha: 0.35)),
          ),
          child: icon != null
              ? Icon(icon, size: 22, color: c)
              : Text(label!, style: PicPosText.v(context, 22, color: c)),
        ),
      ),
    );
  }
}
