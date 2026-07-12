import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/theme/app_colors.dart';

/// Unified empty state widget used across all screens.
///
/// Provides a consistent look for tables, lists, and grids when no data exists.
/// Supports an optional action button for quick creation/navigation.
class AppEmptyState extends StatelessWidget {
  /// Icon to display (defaults to empty clipboard)
  final IconData icon;

  /// Main title text (e.g. "لا توجد منتجات")
  final String title;

  /// Subtitle or description (e.g. "قم بإضافة منتج جديد")
  final String? subtitle;

  /// Optional action button label (shows button if provided)
  final String? actionLabel;

  /// Callback for the action button
  final VoidCallback? onAction;

  /// Optional icon for the action button
  final IconData? actionIcon;

  /// Size of the main icon (default 64)
  final double iconSize;

  const AppEmptyState({
    super.key,
    this.icon = PhosphorIconsBold.clipboardText,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
    this.iconSize = 64,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon with subtle background circle
            Container(
              width: iconSize + 32,
              height: iconSize + 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (isDark ? Colors.white : AppColors.primary)
                    .withValues(alpha: 0.06),
              ),
              child: Icon(
                icon,
                size: iconSize,
                color: AppColors.textMuted.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 20),

            // Title
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),

            // Subtitle
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textMuted.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
            ],

            // Action button
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onAction,
                icon: Icon(
                  actionIcon ?? PhosphorIconsBold.plus,
                  size: 18,
                ),
                label: Text(actionLabel!),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
