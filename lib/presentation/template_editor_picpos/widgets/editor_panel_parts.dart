// لبِناتُ لوحات المحرّر المشتركة — مستخرَجةٌ لا منسوخة.
//
// كانت خاصّةً في `editor_properties_panel.dart` وشاشةِ المحرّر، ثمّ احتاجها
// «قماشُ الملصق» بحرفها. فنُقلت إلى هنا عامّةً، والملفّان الأصليّان
// يستعملانها بأسمائهما القديمة عبر `typedef` — فلا نسختان تتخلّف إحداهما.

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../picpos_shell/picpos_surface.dart';

/// قسمٌ بعنوانٍ صغيرٍ وخطٍّ أسفله.
class EditorPanelSection extends StatelessWidget {
  const EditorPanelSection({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.picposHairline)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: context.picposMuted)),
            const SizedBox(height: 9),
            child,
          ],
        ),
      );
}

/// ± بخطوةٍ ثابتة — بالمليمتر أو بالنقطة.
class EditorStepper extends StatelessWidget {
  const EditorStepper({
    super.key,
    required this.label,
    required this.value,
    required this.onDelta,
    this.step = 1,
    this.decimals = 1,
  });

  final String label;
  final double value;
  final ValueChanged<double> onDelta;
  final double step;
  final int decimals;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: context.picposMuted)),
        ),
        EditorMiniButton(
            icon: PhosphorIconsBold.minus, onTap: () => onDelta(-step)),
        SizedBox(
          width: 40,
          child: Text(
            value.toStringAsFixed(decimals),
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: context.picposText),
          ),
        ),
        EditorMiniButton(
            icon: PhosphorIconsBold.plus, onTap: () => onDelta(step)),
      ],
    );
  }
}

class EditorMiniButton extends StatelessWidget {
  const EditorMiniButton({super.key, required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: context.picposHairline),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon,
              size: 11,
              color: onTap == null
                  ? context.picposHairline
                  : context.picposText),
        ),
      );
}

class EditorToggle extends StatelessWidget {
  const EditorToggle({
    super.key,
    required this.icon,
    required this.on,
    required this.onTap,
    this.label,
    this.wide = false,
  });

  final IconData icon;
  final bool on;
  final VoidCallback onTap;
  final String? label;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final tone = on ? context.picposBrandInk : context.picposMuted;
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 30,
        width: wide ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border.all(
              color: on ? context.picposBrandInk : context.picposHairline,
              width: 1.5),
          color: on
              ? context.picposBrandInk.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: wide ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 13, color: tone),
            if (label != null) ...[
              const SizedBox(width: 5),
              Text(label!,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: tone)),
            ],
          ],
        ),
      ),
    );
  }
}

/// شريحةُ شريط الأدوات — مقاسُ ورق، تكبير، شبكة، معاينة.
class EditorChip extends StatelessWidget {
  const EditorChip({
    super.key,
    required this.on,
    required this.onTap,
    this.label,
    this.icon,
  });

  final bool on;
  final VoidCallback onTap;
  final String? label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final tone = on ? context.picposBrandInk : context.picposMuted;
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          border: Border.all(
              color: on ? context.picposBrandInk : context.picposHairline,
              width: 1.5),
          color: on
              ? context.picposBrandInk.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) Icon(icon, size: 13, color: tone),
            if (icon != null && label != null) const SizedBox(width: 5),
            if (label != null)
              Text(label!,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: tone)),
          ],
        ),
      ),
    );
  }
}

/// شارةٌ ملوّنةٌ صغيرة — «تعديلات غير محفوظة».
class EditorBadge extends StatelessWidget {
  const EditorBadge({super.key, required this.label, required this.tone});

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w800, color: tone)),
      );
}
