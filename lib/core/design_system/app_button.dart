import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Shared action button with the application's semantic palette.
class AppButton extends StatelessWidget {
  final AppButtonVariant variant;
  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;
  final ButtonStyle? style;

  const AppButton.primary({
    super.key,
    required this.onPressed,
    required this.child,
    this.icon,
    this.style,
  }) : variant = AppButtonVariant.primary;

  const AppButton.secondary({
    super.key,
    required this.onPressed,
    required this.child,
    this.icon,
    this.style,
  }) : variant = AppButtonVariant.secondary;

  const AppButton.danger({
    super.key,
    required this.onPressed,
    required this.child,
    this.icon,
    this.style,
  }) : variant = AppButtonVariant.danger;

  const AppButton.warning({
    super.key,
    required this.onPressed,
    required this.child,
    this.icon,
    this.style,
  }) : variant = AppButtonVariant.warning;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = switch (variant) {
      AppButtonVariant.primary => scheme.primary,
      AppButtonVariant.secondary => scheme.surface,
      AppButtonVariant.danger => dark ? AppColors.errorDark : AppColors.error,
      AppButtonVariant.warning => dark ? AppColors.warningDark : AppColors.warning,
    };
    final foreground = variant == AppButtonVariant.secondary
        ? scheme.primary
        : ThemeData.estimateBrightnessForColor(color) == Brightness.dark
            ? Colors.white
            : Colors.black;
    final buttonStyle = variant == AppButtonVariant.secondary
        ? OutlinedButton.styleFrom(
            foregroundColor: foreground,
            side: BorderSide(color: scheme.primary),
          )
        : ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: foreground,
          );
    final resolvedStyle = style == null
        ? buttonStyle
        : buttonStyle.merge(style);
    final content = icon == null
        ? child
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [icon!, const SizedBox(width: 8), child],
          );
    if (variant == AppButtonVariant.secondary) {
      return OutlinedButton(
        onPressed: onPressed,
        style: resolvedStyle,
        child: content,
      );
    }
    return ElevatedButton(
      onPressed: onPressed,
      style: resolvedStyle,
      child: content,
    );
  }
}

enum AppButtonVariant { primary, secondary, danger, warning }
