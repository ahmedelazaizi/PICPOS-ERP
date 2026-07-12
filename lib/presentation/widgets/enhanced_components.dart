import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/theme/app_colors.dart';

/// Enhanced UI Components for UralCash ERP
/// Maintains Teal Theme visual identity with improved UX

// ============================================================================
// ENHANCED CATEGORY FILTER - Circular icons with labels
// ============================================================================

/// Category item data for the enhanced filter
class CategoryFilterItem {
  final int? id;
  final String name;
  final IconData icon;
  final Color? color;

  const CategoryFilterItem({
    this.id,
    required this.name,
    required this.icon,
    this.color,
  });
}

/// Enhanced category filter with circular icon buttons
class EnhancedCategoryFilter extends StatelessWidget {
  final List<CategoryFilterItem> categories;
  final int? selectedId;
  final Function(int?) onSelect;
  final bool showAllOption;
  // ── Configurable display parameters ──
  final double iconSize;
  final double fontSize;
  final double spacing;
  final double runSpacing;
  final double labelWidth;
  final String iconShape; // 'circle' or 'rounded'
  final double maxHeight;

  const EnhancedCategoryFilter({
    super.key,
    required this.categories,
    required this.selectedId,
    required this.onSelect,
    this.showAllOption = true,
    this.iconSize = 44,
    this.fontSize = 9,
    this.spacing = 12,
    this.runSpacing = 8,
    this.labelWidth = 52,
    this.iconShape = 'circle',
    this.maxHeight = 200,
  });

  /// Get default icon based on category name (Arabic support)
  static IconData getIconForCategory(String name) {
    final lowerName = name.toLowerCase();
    // Arabic category mappings
    if (name.contains('مشروبات') || lowerName.contains('drink')) {
      return PhosphorIconsBold.coffee;
    }
    if (name.contains('سناكس') ||
        name.contains('وجبات') ||
        lowerName.contains('snack')) {
      return PhosphorIconsBold.cookie;
    }
    if (name.contains('بقالة') || lowerName.contains('grocery')) {
      return PhosphorIconsBold.shoppingCart;
    }
    if (name.contains('ألبان') ||
        name.contains('البان') ||
        lowerName.contains('dairy')) {
      return PhosphorIconsBold.drop;
    }
    if (name.contains('مخبوزات') ||
        name.contains('خبز') ||
        lowerName.contains('bakery')) {
      return PhosphorIconsBold.bread;
    }
    if (name.contains('مجمدات') || lowerName.contains('frozen')) {
      return PhosphorIconsBold.snowflake;
    }
    if (name.contains('منزلية') ||
        name.contains('منزل') ||
        lowerName.contains('household')) {
      return PhosphorIconsBold.house;
    }
    if (name.contains('تجميل') ||
        name.contains('عناية') ||
        lowerName.contains('beauty')) {
      return PhosphorIconsBold.sparkle;
    }
    if (name.contains('خضروات') ||
        name.contains('فواكه') ||
        lowerName.contains('vegetable') ||
        lowerName.contains('fruit')) {
      return PhosphorIconsBold.carrot;
    }
    if (name.contains('لحوم') || lowerName.contains('meat')) {
      return PhosphorIconsBold.knife;
    }
    if (name.contains('إلكترونيات') || lowerName.contains('electronic')) {
      return PhosphorIconsBold.lightning;
    }
    // Default
    return PhosphorIconsBold.squaresFour;
  }

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];

    if (showAllOption) {
      items.add(_buildCategoryItem(
        id: null,
        name: 'الكل',
        icon: PhosphorIconsBold.squaresFour,
        color: AppColors.primary,
        isSelected: selectedId == null,
      ));
    }

    for (final cat in categories) {
      items.add(_buildCategoryItem(
        id: cat.id,
        name: cat.name,
        icon: cat.icon,
        color: cat.color ?? AppColors.primary,
        isSelected: selectedId == cat.id,
      ));
    }

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(
            color: AppColors.border.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: items,
        ),
      ),
    );
  }

  Widget _buildCategoryItem({
    required int? id,
    required String name,
    required IconData icon,
    required Color color,
    required bool isSelected,
  }) {
    final isRounded = iconShape == 'rounded';
    final iconInnerSize = iconSize * 0.45; // Scale icon inside container
    return GestureDetector(
      onTap: () => onSelect(id),
      child: AnimatedScale(
        scale: isSelected ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon container with Gradient
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: iconSize,
              height: iconSize,
              decoration: BoxDecoration(
                gradient: isSelected
                    ? LinearGradient(
                        colors: [color, color.withValues(alpha: 0.8)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: isSelected ? null : AppColors.surface,
                shape: BoxShape.rectangle,
                borderRadius: isRounded 
                    ? BorderRadius.circular(iconSize * 0.25) 
                    : BorderRadius.circular(iconSize / 2),
                border: Border.all(
                  color: isSelected
                      ? Colors.transparent
                      : AppColors.border.withValues(alpha: 0.5),
                  width: 1.5,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                icon,
                color: isSelected
                    ? Colors.white
                    : AppColors.textPrimary.withValues(alpha: 0.7),
                size: iconInnerSize,
              ),
            ),
            const SizedBox(height: 4),
            // Label
            SizedBox(
              width: labelWidth,
              child: Text(
                name,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.textSecondary,
                  letterSpacing: -0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// AVATAR BADGE - User/Party avatar with initials
// ============================================================================

/// Avatar with initials and optional status badge
class AvatarBadge extends StatelessWidget {
  final String name;
  final double size;
  final Color? backgroundColor;
  final Widget? badge;
  final ImageProvider? image;

  const AvatarBadge({
    super.key,
    required this.name,
    this.size = 40,
    this.backgroundColor,
    this.badge,
    this.image,
  });

  String get _initials {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return '${parts[0].substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }

  Color get _defaultColor {
    // Generate consistent color based on name hash
    final hash = name.hashCode;
    final colors = [
      AppColors.primary,
      AppColors.primaryLight,
      AppColors.success,
      AppColors.info,
      AppColors.warning,
      AppColors.booking,
    ];
    return colors[hash.abs() % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: backgroundColor ?? _defaultColor,
            shape: BoxShape.circle,
            image: image != null
                ? DecorationImage(image: image!, fit: BoxFit.cover)
                : null,
          ),
          child: image == null
              ? Center(
                  child: Text(
                    _initials,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: size * 0.4,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              : null,
        ),
        if (badge != null) Positioned(right: 0, bottom: 0, child: badge!),
      ],
    );
  }
}

// ============================================================================
// ENHANCED SUMMARY CARD - Improved stat cards with animations
// ============================================================================

/// Enhanced summary card with gradient and micro-interactions
class EnhancedSummaryCard extends StatefulWidget {
  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final bool showTrend;
  final double? trendValue;

  const EnhancedSummaryCard({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    required this.icon,
    required this.color,
    this.onTap,
    this.showTrend = false,
    this.trendValue,
  });

  @override
  State<EnhancedSummaryCard> createState() => _EnhancedSummaryCardState();
}

class _EnhancedSummaryCardState extends State<EnhancedSummaryCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? AppColors.cardDark : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isHovered
                  ? widget.color.withValues(alpha: 0.5)
                  : Colors.transparent,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: _isHovered
                    ? widget.color.withValues(alpha: 0.15)
                    : Colors.black.withValues(alpha: 0.05),
                blurRadius: _isHovered ? 16 : 10,
                offset: Offset(0, _isHovered ? 6 : 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // Icon container with gradient background
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      widget.color.withValues(alpha: 0.2),
                      widget.color.withValues(alpha: 0.1),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(widget.icon, color: widget.color, size: 28),
              ),
              const SizedBox(width: 16),
              // Text content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? AppColors.textMuted
                            : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.value,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: widget.color,
                      ),
                    ),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle!,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? AppColors.textMuted
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Trend indicator
              if (widget.showTrend && widget.trendValue != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: widget.trendValue! >= 0
                        ? AppColors.success.withValues(alpha: 0.1)
                        : AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.trendValue! >= 0
                            ? PhosphorIconsBold.arrowUp
                            : PhosphorIconsBold.arrowDown,
                        size: 14,
                        color: widget.trendValue! >= 0
                            ? AppColors.success
                            : AppColors.error,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${widget.trendValue!.abs().toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: widget.trendValue! >= 0
                              ? AppColors.success
                              : AppColors.error,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// ENHANCED TABLE ROW - Hoverable table row
// ============================================================================

/// Table row with hover effect
class EnhancedTableRow extends StatefulWidget {
  final List<Widget> cells;
  final VoidCallback? onTap;
  final bool isHeader;
  final Color? backgroundColor;

  const EnhancedTableRow({
    super.key,
    required this.cells,
    this.onTap,
    this.isHeader = false,
    this.backgroundColor,
  });

  @override
  State<EnhancedTableRow> createState() => _EnhancedTableRowState();
}

class _EnhancedTableRowState extends State<EnhancedTableRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color bgColor;
    if (widget.isHeader) {
      bgColor = isDark ? AppColors.secondaryDark : AppColors.surface;
    } else if (_isHovered) {
      bgColor = isDark
          ? AppColors.primary.withValues(alpha: 0.1)
          : AppColors.primary.withValues(alpha: 0.05);
    } else {
      bgColor = widget.backgroundColor ?? Colors.transparent;
    }

    return MouseRegion(
      onEnter: widget.isHeader
          ? null
          : (_) => setState(() => _isHovered = true),
      onExit: widget.isHeader
          ? null
          : (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: widget.isHeader ? 12 : 10,
          ),
          decoration: BoxDecoration(
            color: bgColor,
            border: Border(
              bottom: BorderSide(
                color: isDark ? AppColors.borderDark : AppColors.border,
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: widget.cells
                .map((cell) => Expanded(child: cell))
                .toList(),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// SECTION HEADER - Consistent section headers
// ============================================================================

/// Section header with optional action button
class SectionHeader extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Widget? action;
  final Widget? trailing;
  final double fontSize;

  const SectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.action,
    this.trailing,
    this.fontSize = 20,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ),
          if (trailing != null) ...[trailing!, const SizedBox(width: 12)],
          ?action,
        ],
      ),
    );
  }
}

// ============================================================================
// EMPTY STATE - Consistent empty state widget
// ============================================================================

/// Empty state placeholder with icon and message
class EmptyStateWidget extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? description;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyStateWidget({
    super.key,
    required this.icon,
    required this.message,
    this.description,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Gradient icon container
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.primary.withValues(alpha: 0.10),
                    AppColors.primary.withValues(alpha: 0.03),
                  ],
                ),
              ),
              child: Icon(
                icon,
                size: 44,
                color: AppColors.primary.withValues(alpha: 0.45),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            if (description != null) ...[
              const SizedBox(height: 8),
              Text(
                description!,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: onAction,
                icon: const Icon(PhosphorIconsBold.plus, size: 18),
                label: Text(actionLabel!),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
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

// ============================================================================
// QUICK ACTION BUTTON - Circular action button
// ============================================================================

/// Circular quick action button
class QuickActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const QuickActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  State<QuickActionButton> createState() => _QuickActionButtonState();
}

class _QuickActionButtonState extends State<QuickActionButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(widget.icon, color: Colors.white, size: 24),
            ),
            const SizedBox(height: 8),
            Text(
              widget.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: widget.color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
