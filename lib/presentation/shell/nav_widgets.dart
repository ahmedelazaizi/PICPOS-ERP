part of 'app_shell.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ENHANCED NAVIGATION ITEM — Sidebar item with glow effects
// ═══════════════════════════════════════════════════════════════════════════

/// Enhanced Sidebar Navigation Item with glow effects
class _EnhancedNavItem extends StatefulWidget {
  final NavItemDef item;
  final bool isExpanded;
  final bool isSelected;
  final VoidCallback onTap;

  const _EnhancedNavItem({
    required this.item,
    required this.isExpanded,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_EnhancedNavItem> createState() => _EnhancedNavItemState();
}

class _EnhancedNavItemState extends State<_EnhancedNavItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: widget.isExpanded ? 8 : 6,
        vertical: 2,
      ),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: EdgeInsets.symmetric(
              horizontal: widget.isExpanded ? 12 : 0,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              gradient: widget.isSelected
                  ? LinearGradient(
                      colors: [
                        AppColors.primary.withValues(alpha: 0.25),
                        AppColors.primary.withValues(alpha: 0.1),
                      ],
                    )
                  : _isHovered
                  ? LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.08),
                        Colors.white.withValues(alpha: 0.03),
                      ],
                    )
                  : null,
              borderRadius: BorderRadius.circular(10),
              border: widget.isSelected
                  ? Border.all(
                      color: AppColors.primary.withValues(alpha: 0.5),
                      width: 1.5,
                    )
                  : null,
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
            child: Row(
              mainAxisAlignment: widget.isExpanded
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                // Icon with glow effect when selected
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(2),
                  decoration: widget.isSelected
                      ? BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.5),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        )
                      : null,
                  child: Icon(
                    widget.item.icon,
                    color: widget.isSelected
                        ? AppColors.primary
                        : _isHovered
                        ? Colors.white
                        : AppColors.textMuted,
                    size: widget.isSelected ? 20 : 18,
                  ),
                ),
                if (widget.isExpanded) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                        color: widget.isSelected
                            ? AppColors.primary
                            : _isHovered
                            ? Colors.white
                            : Colors.white70,
                        fontSize: widget.isSelected ? 13 : 12,
                        fontWeight: widget.isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                      child: Text(widget.item.label),
                    ),
                  ),
                  // Active indicator
                  if (widget.isSelected)
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.6),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// COLLAPSIBLE NAVIGATION GROUPS — Professional accordion sidebar
// ═══════════════════════════════════════════════════════════════════════════

/// Group metadata for sidebar sections
class _GroupMeta {
  final String label;
  final IconData icon;
  const _GroupMeta(this.label, this.icon);
}

const _groupMeta = <String, _GroupMeta>{
  'home': _GroupMeta('Dashboard', PhosphorIconsBold.house),
  'sales': _GroupMeta('المبيعات', PhosphorIconsBold.shoppingCart),
  'purchases': _GroupMeta('المشتريات', PhosphorIconsBold.receipt),
  'inventory': _GroupMeta('الاصناف والمخزون', PhosphorIconsBold.package),
  'relations': _GroupMeta('العملاء والموردين', PhosphorIconsBold.usersThree),
  'accounting': _GroupMeta('المالية والمحاسبة', PhosphorIconsBold.wallet),
  'reports': _GroupMeta('التقارير', PhosphorIconsBold.chartBar),
  'system': _GroupMeta('النظام', PhosphorIconsBold.gear),
};

class _CollapsibleNavGroups extends StatefulWidget {
  final List<String> groupOrder;
  final Map<String, List<NavItemDef>> groups;
  final String? activeGroup;
  final int currentIndex;
  final void Function(NavItemDef) onItemTap;

  const _CollapsibleNavGroups({
    required this.groupOrder,
    required this.groups,
    required this.activeGroup,
    required this.currentIndex,
    required this.onItemTap,
  });

  @override
  State<_CollapsibleNavGroups> createState() => _CollapsibleNavGroupsState();
}

class _CollapsibleNavGroupsState extends State<_CollapsibleNavGroups> {
  String? _expandedGroup;

  @override
  void initState() {
    super.initState();
    _expandedGroup = widget.activeGroup;
  }

  @override
  void didUpdateWidget(covariant _CollapsibleNavGroups oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Auto-expand the group containing the active screen
    if (widget.activeGroup != oldWidget.activeGroup && widget.activeGroup != null) {
      setState(() => _expandedGroup = widget.activeGroup);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: widget.groupOrder.map((groupKey) {
        final items = widget.groups[groupKey]!;
        final meta = _groupMeta[groupKey] ?? _GroupMeta(groupKey, PhosphorIconsBold.folder);
        final isExpanded = _expandedGroup == groupKey;
        final hasActiveItem = items.any((i) => i.index == widget.currentIndex);

        // Single item groups (like "home") — render directly
        if (items.length == 1 && groupKey == 'home') {
          final item = items.first;
          final isSelected = widget.currentIndex == item.index;
          return _buildDirectItem(item, isSelected);
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Group Header
            InkWell(
              onTap: () {
                setState(() {
                  _expandedGroup = isExpanded ? null : groupKey;
                });
              },
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: hasActiveItem
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      meta.icon,
                      color: hasActiveItem
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.5),
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        meta.label,
                        style: TextStyle(
                          color: hasActiveItem
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.55),
                          fontSize: 11,
                          fontWeight: hasActiveItem ? FontWeight.w700 : FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: isExpanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        PhosphorIconsBold.caretLeft,
                        color: Colors.white.withValues(alpha: 0.35),
                        size: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Group Items (animated)
            AnimatedCrossFade(
              firstChild: Column(
                mainAxisSize: MainAxisSize.min,
                children: items.map((item) {
                  final isSelected = widget.currentIndex == item.index;
                  return _buildGroupItem(item, isSelected);
                }).toList(),
              ),
              secondChild: const SizedBox.shrink(),
              crossFadeState: isExpanded
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              duration: const Duration(milliseconds: 200),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildDirectItem(NavItemDef item, bool isSelected) {
    return InkWell(
      onTap: () => widget.onItemTap(item),
      child: Container(
        height: 40,
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.3)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(item.icon, color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.6), size: 18),
            const SizedBox(width: 10),
            Text(
              item.label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupItem(NavItemDef item, bool isSelected) {
    return InkWell(
      onTap: () => widget.onItemTap(item),
      child: Container(
        height: 34,
        margin: const EdgeInsets.only(right: 22, left: 6, top: 1, bottom: 1),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.3)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: isSelected
              ? Border.all(color: AppColors.primary.withValues(alpha: 0.4), width: 0.5)
              : null,
        ),
        child: Row(
          children: [
            Icon(
              item.icon,
              color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.55),
              size: 15,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item.label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.65),
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isSelected)
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.6),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
