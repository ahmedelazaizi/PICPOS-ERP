// بطاقةُ اختيارٍ بأيقونةٍ وراديو — `Semantics(selected:)` بدل aria-pressed.
// ألوانٌ من tokens PicPos (‏بطاقة/حدّ رفيع/حبر العلامة) تتبع الفاتح والداكن.
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../picpos_shell/picpos_surface.dart';

class FirstRunChoiceCard extends StatelessWidget {
  const FirstRunChoiceCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ink = context.picposBrandInk;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: title,
      child: Material(
        color: selected
            ? AppColors.primary.withValues(alpha: 0.08)
            : context.picposCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? ink : context.picposHairline,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 24, color: selected ? ink : context.picposMuted),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: context.picposText,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: context.picposMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: selected ? ink : context.picposMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
