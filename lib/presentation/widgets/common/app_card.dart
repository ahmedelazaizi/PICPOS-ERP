import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// بطاقة موحدة لكل شاشات النظام.
///
/// تستبدل استخدام `Container(decoration: BoxDecoration(...))` المنتشر
/// في الشاشات بحيث تتوحد الزوايا، الظل، الحدود، والـ padding.
///
/// أحجام:
/// - `AppCardDensity.compact` — حشو 12، للقوائم المكدّسة
/// - `AppCardDensity.regular` — حشو 16، للاستخدام الافتراضي
/// - `AppCardDensity.featured` — حشو 20، للبطاقات البارزة (داشبورد)
enum AppCardDensity { compact, regular, featured }

class AppCard extends StatelessWidget {
  final Widget child;
  final AppCardDensity density;
  final Color? backgroundColor;
  final Color? borderColor;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final double? width;
  final double? height;

  const AppCard({
    super.key,
    required this.child,
    this.density = AppCardDensity.regular,
    this.backgroundColor,
    this.borderColor,
    this.padding,
    this.margin,
    this.onTap,
    this.width,
    this.height,
  });

  EdgeInsets get _defaultPadding {
    switch (density) {
      case AppCardDensity.compact:
        return const EdgeInsets.all(12);
      case AppCardDensity.regular:
        return const EdgeInsets.all(16);
      case AppCardDensity.featured:
        return const EdgeInsets.all(20);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = backgroundColor ?? (isDark ? AppColors.cardDark : AppColors.card);
    final border = borderColor ?? (isDark ? AppColors.borderDark : AppColors.border);

    final content = Container(
      width: width,
      height: height,
      padding: padding ?? _defaultPadding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );

    final wrapped = onTap == null
        ? content
        : Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: content,
            ),
          );

    return margin == null ? wrapped : Padding(padding: margin!, child: wrapped);
  }
}
