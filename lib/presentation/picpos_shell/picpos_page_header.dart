import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// هيدر شاشات PicPos: خلفية فاتحة، عنوان داكن، وخط لوني سفلي 2.5px بلون العلامة
/// (فلسفة PicPosTheme: «شريط علوي فاتح بشريحة لونية سفلية»). التايبوغرافي من الثيم.
class PicPosPageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;

  /// حقل بحث اختياري يوضع على يسار صف العنوان (بعرض محدود).
  final Widget? search;

  /// أزرار الإجراءات على أول الصف (يمين في RTL).
  final List<Widget> actions;

  const PicPosPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.search,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(
          bottom: BorderSide(color: AppColors.primary, width: 2.5),
        ),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: 12),
          ],
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: text.headlineSmall),
              if (subtitle != null)
                Text(subtitle!, style: text.bodySmall),
            ],
          ),
          const Spacer(),
          if (search != null) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: search!,
            ),
            const SizedBox(width: 12),
          ],
          ...actions,
        ],
      ),
    );
  }
}
