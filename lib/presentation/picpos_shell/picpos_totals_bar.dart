import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// شريطُ إجماليّاتٍ نحيفٌ — سطرٌ واحدٌ بدل صفِّ بطاقات.
///
/// ═══ لماذا وُجد ═══
///
/// قرارُ المالك 2026-09-18 على تصميمَي «الاستعلام عن المشتريات» و«الأصول
/// الثابتة»: **البطاقاتُ الخمسُ تُستبدَل بالشريط النحيف نهائيّاً.**
///
/// و`PicPosKpiRow` يبقى لمن يحتاج البطاقات (لوحاتُ المعلومات والمراكز)؛ هذا
/// لشاشات **الجداول** حيث كلُّ بكسلٍ يأخذه الرأسُ يأخذه من الصفوف.
///
/// ⚠️ **ويلتفّ ولا يفيض**: الشريطُ يحمل من ثلاثة بنودٍ إلى ستّة، والشاشاتُ
/// تُفتَح على عروضٍ مختلفة. فـ`Wrap` لا `Row` — و`Row` هنا تعني خطَّ بتٍ
/// أصفرَ وأسودَ على شاشةٍ ضيّقة.
class PicPosTotalsBar extends StatelessWidget {
  const PicPosTotalsBar({
    super.key,
    required this.items,
    this.padding,
  });

  final List<PicPosTotal> items;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: padding ??
          const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.10),
        ),
      ),
      child: Wrap(
        spacing: 28,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final t in items) _TotalCell(total: t),
        ],
      ),
    );
  }
}

/// بندٌ واحدٌ في الشريط.
class PicPosTotal {
  const PicPosTotal({
    required this.label,
    required this.value,
    this.emphasis = false,
    this.tone,
  });

  final String label;
  final String value;

  /// الحدُّ الأخيرُ في المعادلة (الصافي مثلاً) — أكبرُ وأغمق.
  final bool emphasis;

  /// لونُ الرقم. `null` ⇒ حبرٌ افتراضيّ.
  final Color? tone;
}

class _TotalCell extends StatelessWidget {
  const _TotalCell({required this.total});
  final PicPosTotal total;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          total.label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          total.value,
          // ⚠️ `tabular` عمداً: الأرقامُ تحت بعضها في شريطٍ يلتفّ، وبلا
          // أرقامٍ جدوليّةٍ ترقص الخاناتُ مع كلّ تحديث.
          style: TextStyle(
            fontSize: total.emphasis ? 17 : 14,
            fontWeight: total.emphasis ? FontWeight.w800 : FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: total.tone ?? onSurface,
          ),
        ),
      ],
    );
  }
}
