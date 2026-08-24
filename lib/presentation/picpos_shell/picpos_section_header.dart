import 'picpos_surface.dart';
import 'package:flutter/material.dart';

import '../../core/design_system/spacing.dart';
import '../../core/theme/app_colors.dart';

/// عنوان قسم داخل كرت أو صفحة.
///
/// كل شاشة كانت بتخترع نسختها (`_miniHeader` في شاشة التقارير، الترويسة
/// المكتوبة inline في كرت الإعدادات، وغيرها) — فالمقاسات والألوان والمسافات
/// بتختلف من شاشة للتانية بلا سبب. ده البديل الواحد.
class PicPosSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;

  /// إجراءات على آخر الصف (شمال في RTL) — زي «تصدير» أو «تحديث».
  final List<Widget> actions;

  /// خط فاصل تحت العنوان. يتشال لما العنوان جوه كرت له حد أصلاً.
  final bool showDivider;

  const PicPosSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.actions = const [],
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 17, color: AppColors.primary),
              const SizedBox(width: Spacing.sm),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            ...actions,
          ],
        ),
        if (showDivider) ...[
          const SizedBox(height: Spacing.md),
          Divider(height: 1, color: context.picposHairline),
        ],
      ],
    );
  }
}
