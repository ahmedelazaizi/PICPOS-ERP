import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/theme/app_colors.dart';

/// Category icons for selection
/// Maps icon names to PhosphorIcons for display in categories
class CategoryIconPicker extends StatefulWidget {
  final String? selectedIcon;
  final ValueChanged<String?> onIconSelected;

  const CategoryIconPicker({
    super.key,
    this.selectedIcon,
    required this.onIconSelected,
  });

  // Available icons for categories with Arabic labels
  static Map<String, ({IconData icon, String label})> get availableIcons => {
    'hamburger': (icon: PhosphorIconsBold.hamburger, label: tr('برجر')),
    'pizza': (icon: PhosphorIconsBold.pizza, label: tr('بيتزا')),
    'coffee': (icon: PhosphorIconsBold.coffee, label: tr('مشروبات ساخنة')),
    'beer': (icon: PhosphorIconsBold.beerBottle, label: tr('مشروبات')),
    'cookingPot': (icon: PhosphorIconsBold.cookingPot, label: tr('طبخ')),
    'bowl': (icon: PhosphorIconsBold.bowlFood, label: tr('أطباق')),
    'iceCream': (icon: PhosphorIconsBold.iceCream, label: tr('حلويات')),
    'cake': (icon: PhosphorIconsBold.cake, label: tr('كيك')),
    'cookie': (icon: PhosphorIconsBold.cookie, label: tr('معجنات')),
    'bread': (icon: PhosphorIconsBold.bread, label: tr('مخبوزات')),
    'egg': (icon: PhosphorIconsBold.egg, label: tr('فطور')),
    'fish': (icon: PhosphorIconsBold.fish, label: tr('مأكولات بحرية')),
    'grains': (icon: PhosphorIconsBold.grains, label: tr('حبوب')),
    'orange': (icon: PhosphorIconsBold.orange, label: tr('فواكه')),
    'carrot': (icon: PhosphorIconsBold.carrot, label: tr('خضروات')),
    'wine': (icon: PhosphorIconsBold.wine, label: tr('مشروبات فاخرة')),
    'shoppingCart': (icon: PhosphorIconsBold.shoppingCart, label: tr('تسوق')),
    'tShirt': (icon: PhosphorIconsBold.tShirt, label: tr('ملابس')),
    'sneaker': (icon: PhosphorIconsBold.sneaker, label: tr('أحذية')),
    'bag': (icon: PhosphorIconsBold.handbag, label: tr('حقائب')),
    'watch': (icon: PhosphorIconsBold.watch, label: tr('ساعات')),
    'sparkle': (icon: PhosphorIconsBold.sparkle, label: tr('إكسسوارات')),
    'phone': (icon: PhosphorIconsBold.phone, label: tr('هواتف')),
    'laptop': (icon: PhosphorIconsBold.laptop, label: tr('أجهزة')),
    'headphones': (icon: PhosphorIconsBold.headphones, label: tr('سماعات')),
    'gameController': (icon: PhosphorIconsBold.gameController, label: tr('ألعاب')),
    'pill': (icon: PhosphorIconsBold.pill, label: tr('أدوية')),
    'heart': (icon: PhosphorIconsBold.heartbeat, label: tr('صحة')),
    'firstAid': (icon: PhosphorIconsBold.firstAid, label: tr('إسعافات')),
    'scissors': (icon: PhosphorIconsBold.scissors, label: tr('تجميل')),
    'sprayBottle': (icon: PhosphorIconsBold.sprayBottle, label: tr('تنظيف')),
    'baby': (icon: PhosphorIconsBold.baby, label: tr('أطفال')),
    'paw': (icon: PhosphorIconsBold.pawPrint, label: tr('حيوانات')),
    'house': (icon: PhosphorIconsBold.house, label: tr('منزل')),
    'car': (icon: PhosphorIconsBold.car, label: tr('سيارات')),
    'wrench': (icon: PhosphorIconsBold.wrench, label: tr('أدوات')),
    'gift': (icon: PhosphorIconsBold.gift, label: tr('هدايا')),
    'star': (icon: PhosphorIconsBold.star, label: tr('مميز')),
    'fire': (icon: PhosphorIconsBold.fire, label: tr('عرض خاص')),
    'tag': (icon: PhosphorIconsBold.tag, label: tr('عروض')),
    'percent': (icon: PhosphorIconsBold.percent, label: tr('خصومات')),
    'package': (icon: PhosphorIconsBold.package, label: tr('منتجات')),
    'box': (icon: PhosphorIconsBold.cube, label: tr('صناديق')),
    'flower': (icon: PhosphorIconsBold.flower, label: tr('زهور')),
    'sun': (icon: PhosphorIconsBold.sun, label: tr('صيف')),
    'snowflake': (icon: PhosphorIconsBold.snowflake, label: tr('شتاء')),
    'leaf': (icon: PhosphorIconsBold.leaf, label: tr('طبيعي')),
    'recycle': (icon: PhosphorIconsBold.recycle, label: tr('بيئي')),
  };

  /// Get icon data from icon name
  static IconData getIconData(String? iconName) {
    if (iconName == null || !availableIcons.containsKey(iconName)) {
      return PhosphorIconsBold.squaresFour; // Default category icon
    }
    return availableIcons[iconName]!.icon;
  }

  @override
  State<CategoryIconPicker> createState() => _CategoryIconPickerState();
}

class _CategoryIconPickerState extends State<CategoryIconPicker> {
  String? _selectedIcon;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _selectedIcon = widget.selectedIcon;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with selected icon preview
        InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _selectedIcon != null
                        ? CategoryIconPicker
                                  .availableIcons[_selectedIcon]
                                  ?.icon ??
                              PhosphorIconsBold.squaresFour
                        : PhosphorIconsBold.squaresFour,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _selectedIcon != null
                        ? CategoryIconPicker
                                  .availableIcons[_selectedIcon]
                                  ?.label ??
                              tr('أيقونة مخصصة')
                        : tr('اختر أيقونة (اختياري)'),
                    style: TextStyle(
                      color: _selectedIcon != null
                          ? AppColors.textPrimary
                          : AppColors.textMuted,
                    ),
                  ),
                ),
                Icon(
                  _isExpanded
                      ? PhosphorIconsBold.caretUp
                      : PhosphorIconsBold.caretDown,
                  size: 18,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),

        // Expandable icon grid
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                // Clear selection button
                if (_selectedIcon != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _selectedIcon = null;
                          _isExpanded = false;
                        });
                        widget.onIconSelected(null);
                      },
                      icon: const Icon(PhosphorIconsBold.x, size: 16),
                      label:  Text(tr('إزالة الأيقونة')),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.error,
                      ),
                    ),
                  ),

                // Icons grid
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: CategoryIconPicker.availableIcons.entries.map((
                    entry,
                  ) {
                    final isSelected = _selectedIcon == entry.key;
                    return _IconButton(
                      iconData: entry.value.icon,
                      label: entry.value.label,
                      isSelected: isSelected,
                      onTap: () {
                        setState(() {
                          _selectedIcon = entry.key;
                          _isExpanded = false;
                        });
                        widget.onIconSelected(entry.key);
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          crossFadeState: _isExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }
}

class _IconButton extends StatefulWidget {
  final IconData iconData;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _IconButton({
    required this.iconData,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_IconButton> createState() => _IconButtonState();
}

class _IconButtonState extends State<_IconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Tooltip(
        message: widget.label,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: widget.isSelected
                  ? LinearGradient(
                      colors: [
                        AppColors.primary.withValues(alpha: 0.2),
                        AppColors.primary.withValues(alpha: 0.1),
                      ],
                    )
                  : null,
              color: widget.isSelected
                  ? null
                  : _isHovered
                  ? AppColors.primary.withValues(alpha: 0.08)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: widget.isSelected
                    ? AppColors.primary
                    : _isHovered
                    ? AppColors.primary.withValues(alpha: 0.5)
                    : AppColors.border,
                width: widget.isSelected ? 2 : 1,
              ),
              boxShadow: widget.isSelected
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.3),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              widget.iconData,
              color: widget.isSelected
                  ? AppColors.primary
                  : _isHovered
                  ? AppColors.primary
                  : AppColors.textMuted,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}
