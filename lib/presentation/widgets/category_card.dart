import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../data/database/database.dart';

/// Enhanced category card with hover effects and dynamic icons.
///
/// Extracted from `categories_screen.dart` (PIR Phase 1.1).
/// Redesigned with cleaner action layout: edit/delete as primary buttons,
/// other actions in a 3-dot menu.
class CategoryCard extends StatefulWidget {
  final Category cat;
  final Color color;
  final bool isLocked;
  final bool isExcluded;
  final IconData categoryIcon;
  final VoidCallback onLockToggle;
  final VoidCallback onExcludeAll;
  final VoidCallback? onPosVisibilityToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onScaleUpload;

  const CategoryCard({
    super.key,
    required this.cat,
    required this.color,
    required this.isLocked,
    required this.isExcluded,
    required this.categoryIcon,
    required this.onLockToggle,
    required this.onExcludeAll,
    this.onPosVisibilityToggle,
    required this.onEdit,
    required this.onDelete,
    required this.onScaleUpload,
  });

  @override
  State<CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<CategoryCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = widget.isLocked ? AppColors.error : widget.color;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isHovered
                ? effectiveColor
                : effectiveColor.withValues(alpha: 0.3),
            width: _isHovered ? 2.5 : 2,
          ),
          boxShadow: [
            BoxShadow(
              color: _isHovered
                  ? effectiveColor.withValues(alpha: 0.2)
                  : Colors.black.withValues(alpha: 0.05),
              blurRadius: _isHovered ? 16 : 8,
              offset: Offset(0, _isHovered ? 6 : 3),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Lock indicator badge (top-left)
            if (widget.isLocked)
              PositionedDirectional(
                top: 8,
                end: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child:  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        PhosphorIconsBold.lock,
                        color: Colors.white,
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        tr('مقفل'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // Excluded indicator badge
            if (widget.isExcluded && !widget.isLocked)
              PositionedDirectional(
                top: 8,
                end: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.warning,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child:  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        PhosphorIconsBold.eyeSlash,
                        color: Colors.white,
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        tr('مستثنى'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // POS hidden badge
            if (!widget.cat.showInPos && !widget.isLocked && !widget.isExcluded)
              PositionedDirectional(
                top: 8,
                end: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.textMuted.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child:  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        PhosphorIconsBold.prohibit,
                        color: Colors.white,
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        tr('مخفي'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // Printer badge (top-right)
            if (widget.cat.printerId != null)
              PositionedDirectional(
                top: 8,
                start: 8,
                child: Tooltip(
                  message: tr('مرتبط بطابعة'),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.info.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: AppColors.info.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Icon(
                      PhosphorIconsBold.printer,
                      color: AppColors.info,
                      size: 12,
                    ),
                  ),
                ),
              ),
            // Main content
            Positioned.fill(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 8),
                  // Icon with animated container
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: _isHovered ? 44 : 40,
                    height: _isHovered ? 44 : 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          effectiveColor.withValues(alpha: 0.2),
                          effectiveColor.withValues(alpha: 0.1),
                        ],
                        begin: AlignmentDirectional.topEnd,
                        end: AlignmentDirectional.bottomStart,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: _isHovered
                          ? [
                              BoxShadow(
                                color: effectiveColor.withValues(alpha: 0.3),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                    child: Icon(
                      widget.isLocked
                          ? PhosphorIconsBold.lock
                          : widget.categoryIcon,
                      color: effectiveColor,
                      size: _isHovered ? 22 : 20,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      widget.cat.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color:
                            widget.isLocked ? AppColors.textSecondary : null,
                        decoration: widget.isLocked
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Action buttons — clean layout: Edit, Delete, More menu
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Edit
                        _ActionChip(
                          icon: PhosphorIconsBold.pencilSimple,
                          label: tr('تعديل'),
                          color: AppColors.primary,
                          onTap: widget.onEdit,
                        ),
                        const SizedBox(width: 6),
                        // Delete
                        _ActionChip(
                          icon: PhosphorIconsBold.trash,
                          label: tr('حذف'),
                          color: AppColors.error,
                          onTap: widget.onDelete,
                        ),
                        const SizedBox(width: 4),
                        // More actions menu
                        _buildMoreMenu(context),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMoreMenu(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: AppColors.textMuted.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Icon(
          PhosphorIconsBold.dotsThreeVertical,
          size: 16,
          color: AppColors.textSecondary,
        ),
      ),
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      position: PopupMenuPosition.under,
      onSelected: (action) {
        switch (action) {
          case 'lock':
            widget.onLockToggle();
            break;
          case 'exclude':
            widget.onExcludeAll();
            break;
          case 'pos_visibility':
            widget.onPosVisibilityToggle?.call();
            break;
          case 'scale':
            widget.onScaleUpload();
            break;
        }
      },
      itemBuilder: (context) => [
        // Lock / Unlock
        PopupMenuItem(
          value: 'lock',
          child: Row(
            children: [
              Icon(
                widget.isLocked
                    ? PhosphorIconsBold.lockOpen
                    : PhosphorIconsBold.lock,
                size: 18,
                color: widget.isLocked ? AppColors.success : AppColors.warning,
              ),
              const SizedBox(width: 10),
              Text(
                widget.isLocked ? tr('فتح التصنيف') : tr('قفل التصنيف'),
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
        // Exclude / Show
        PopupMenuItem(
          value: 'exclude',
          child: Row(
            children: [
              Icon(
                widget.isExcluded
                    ? PhosphorIconsBold.eye
                    : PhosphorIconsBold.eyeSlash,
                size: 18,
                color: widget.isExcluded ? AppColors.info : AppColors.warning,
              ),
              const SizedBox(width: 10),
              Text(
                widget.isExcluded ? tr('إلغاء الاستثناء') : tr('استثناء من العرض'),
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
        // POS Visibility
        if (widget.onPosVisibilityToggle != null)
          PopupMenuItem(
            value: 'pos_visibility',
            child: Row(
              children: [
                Icon(
                  widget.cat.showInPos
                      ? PhosphorIconsBold.prohibit
                      : PhosphorIconsBold.storefront,
                  size: 18,
                  color: widget.cat.showInPos
                      ? AppColors.error
                      : AppColors.success,
                ),
                const SizedBox(width: 10),
                Text(
                  widget.cat.showInPos
                      ? tr('إخفاء من البيع السريع')
                      : tr('إظهار في البيع السريع'),
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
        const PopupMenuDivider(),
        // Scale Upload
         PopupMenuItem(
          value: 'scale',
          child: Row(
            children: [
              const Icon(
                PhosphorIconsBold.upload,
                size: 18,
                color: AppColors.info,
              ),
              const SizedBox(width: 10),
              Text(
                tr('ترحيل للميزان'),
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Small labeled action chip for category cards.
class _ActionChip extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  State<_ActionChip> createState() => _ActionChipState();
}

class _ActionChipState extends State<_ActionChip> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.label,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedScale(
          scale: _isPressed ? 0.9 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: widget.color.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 14, color: widget.color),
                const SizedBox(width: 4),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: widget.color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small action button for category cards (kept for backward compatibility).
class CategoryActionButton extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const CategoryActionButton({
    super.key,
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  State<CategoryActionButton> createState() => _CategoryActionButtonState();
}

class _CategoryActionButtonState extends State<CategoryActionButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedScale(
          scale: _isPressed ? 0.9 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(widget.icon, size: 16, color: widget.color),
          ),
        ),
      ),
    );
  }
}
