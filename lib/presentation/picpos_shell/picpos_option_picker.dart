import 'package:picpos_erp/core/i18n/tr.dart';
// منتقي خيارٍ واحدٍ بهويّة PicPos — بديلُ `SimpleDialog`.
//
// ═══ العطبُ المُبلَّغ عنه ═══
//
// أرسل المالكُ صوراً 2026-08-25 تُظهر منتقيَ «اختر نوع النشاط» بشكل
// `SimpleDialog` الافتراضيِّ لـMaterial — عنوانٌ عارٍ وقائمةُ `ListTile` بلا
// إطارٍ ولا هويّة. وقال: «حوارات وديالوجات ونوافذ التصميم القديم لا زالت
// موجودة، وهذا غير مطابق للتصميم الجديد المميّز الذي يجعل النظام فريداً
// لذاته وليس مشابهاً لشكل UralCash مع فرق الألوان».
//
// ومقيسٌ أنّ في فورك الإعدادات **خمسةَ** منتقياتٍ من هذا النوع:
// نوعُ النشاط · عملةُ النظام · سياسةُ نقص الخامات · مهلةُ انتهاء الجلسة ·
// مظهرُ التطبيق. وكلُّها الشكلُ نفسُه: «اختر واحداً من قائمة».
//
// ═══ لماذا ودجتٌ واحدةٌ لا خمسةُ تنسيقات ═══
//
// تنسيقُ كلٍّ على حدةٍ يعني خمسَ نسخٍ تفترق عند أوّل تعديلٍ في الهويّة — وهو
// عينُ ما بُني `PicPosDialog` ليمنعه. وهذه الودجتُ تبني على `PicPosDialog`
// نفسِها فتأخذ رأسَها وتذييلَها ومقاساتِها بلا تكرار.
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import 'picpos_dialog.dart';
import 'picpos_surface.dart';

/// خيارٌ واحدٌ في المنتقي.
class PicPosOption<T> {
  const PicPosOption({
    required this.value,
    required this.label,
    this.sub,
    this.icon,
    this.badge,
  });

  final T value;
  final String label;

  /// سطرٌ خافتٌ يشرح أثرَ الخيار — التصميمُ يعطيه لكلّ خيار.
  final String? sub;

  final IconData? icon;

  /// شارةٌ صغيرةٌ على الطرف («الحالي» في التصميم).
  final String? badge;
}

/// يفتح منتقيَ خيارٍ واحدٍ ويعيد المختارَ، أو `null` عند الإلغاء.
///
/// [applyLabel] نصُّ زرِّ التأكيد — «تطبيق» في التصميم.
///
/// ⚠️ **والاختيارُ لا يُطبَّق بالنقرة وحدَها**: `SimpleDialog` كانت تُغلق
/// وتُطبِّق فورَ اللمس، فنقرةٌ خاطئةٌ على «نوع النشاط» كانت تبدّل شاشاتِ
/// النظام كلَّها بلا تأكيد. هنا النقرةُ تُعلِّم، والزرُّ يُطبِّق.
Future<T?> showPicPosOptionPicker<T>({
  required BuildContext context,
  required String title,
  required List<PicPosOption<T>> options,
  required T selected,
  String? subtitle,
  IconData icon = PhosphorIconsBold.listChecks,
  String? applyLabel,
  double width = 560,
}) {
  return showDialog<T>(
    context: context,
    builder: (ctx) => _PicPosOptionPicker<T>(
      title: title,
      subtitle: subtitle,
      icon: icon,
      options: options,
      selected: selected,
      // `null` ⇒ «تطبيق» مترجَمةً وقتَ الفتح لا قيمةً عربيّةً ثابتة.
      applyLabel: applyLabel ?? tr('تطبيق'),
      width: width,
    ),
  );
}

class _PicPosOptionPicker<T> extends StatefulWidget {
  const _PicPosOptionPicker({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.options,
    required this.selected,
    required this.applyLabel,
    required this.width,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final List<PicPosOption<T>> options;
  final T selected;
  final String applyLabel;
  final double width;

  @override
  State<_PicPosOptionPicker<T>> createState() => _PicPosOptionPickerState<T>();
}

class _PicPosOptionPickerState<T> extends State<_PicPosOptionPicker<T>> {
  late T _value = widget.selected;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return PicPosDialog(
      icon: widget.icon,
      title: widget.title,
      subtitle: widget.subtitle,
      width: widget.width,
      primaryAction: PicPosDialogAction(
        label: widget.applyLabel,
        icon: PhosphorIconsBold.check,
        // معطَّلٌ ما لم يتبدّل شيء — زرٌّ يُطبِّق ما هو مطبَّقٌ أصلاً يوهم
        // بأنّ شيئاً حدث.
        onPressed: _value == widget.selected
            ? null
            : () => Navigator.pop(context, _value),
      ),
      body: [
        for (var i = 0; i < widget.options.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _row(widget.options[i], text),
        ],
      ],
    );
  }

  Widget _row(PicPosOption<T> o, TextTheme text) {
    final on = o.value == _value;
    final isCurrent = o.value == widget.selected;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _value = o.value),
        borderRadius: BorderRadius.circular(13),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: on
                ? AppColors.primary.withValues(alpha: 0.08)
                : context.picposField,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: on ? AppColors.primary : context.picposHairline,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Icon(
                on
                    ? PhosphorIconsBold.radioButton
                    : PhosphorIconsBold.circle,
                size: 18,
                color: on ? AppColors.primary : context.picposMuted,
              ),
              const SizedBox(width: 12),
              if (o.icon != null) ...[
                Icon(o.icon,
                    size: 18,
                    color: on ? AppColors.primary : context.picposMuted),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      o.label,
                      style: text.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: on ? AppColors.primary : null,
                      ),
                    ),
                    if (o.sub != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          o.sub!,
                          style: text.labelSmall
                              ?.copyWith(color: context.picposMuted),
                        ),
                      ),
                  ],
                ),
              ),
              // «الحالي» — يميّز المطبَّقَ الآن عن المُعلَّم الآن. وبغيره لا
              // يعرف المستخدمُ ماذا كان يعمل قبل أن يلمس.
              if (isCurrent) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    o.badge ?? tr('الحالي'),
                    style: text.labelSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.success,
                    ),
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
