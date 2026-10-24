// تنبيهٌ ملوَّن داخل جسم الخطوة (‏callout) + شارةُ حالة (status pill α 0.12).
// اللونُ دلاليٌّ (‏AppColors.error/warning/success/primary) بشفافيّة، والنصُّ من
// tokens الثيم — فيُقرأ في الوضعين.
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../picpos_shell/picpos_surface.dart';

enum FirstRunTone { info, warning, danger, success }

Color firstRunToneColor(FirstRunTone tone) => switch (tone) {
      FirstRunTone.info => AppColors.primary,
      FirstRunTone.warning => AppColors.warning,
      FirstRunTone.danger => AppColors.error,
      FirstRunTone.success => AppColors.success,
    };

class FirstRunCallout extends StatelessWidget {
  const FirstRunCallout({
    super.key,
    required this.title,
    this.body,
    this.tone = FirstRunTone.info,
    this.icon,
  });

  final String title;
  final String? body;
  final FirstRunTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final color = firstRunToneColor(tone);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon ?? Icons.info_outline,
            size: 18,
            color: tone == FirstRunTone.info ? context.picposBrandInk : color,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: context.picposText,
                  ),
                ),
                if (body != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    body!,
                    style: TextStyle(fontSize: 12.5, color: context.picposMuted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// شارةُ حالة (‏جاهز / غير جاهز).
class FirstRunStatusBadge extends StatelessWidget {
  const FirstRunStatusBadge({
    super.key,
    required this.label,
    this.tone = FirstRunTone.success,
  });

  final String label;
  final FirstRunTone tone;

  @override
  Widget build(BuildContext context) {
    final color = firstRunToneColor(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: tone == FirstRunTone.info ? context.picposBrandInk : context.picposText,
        ),
      ),
    );
  }
}
