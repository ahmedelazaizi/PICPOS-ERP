import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../core/theme/app_colors.dart';

class PermissionCategoryCard extends StatelessWidget {
  final String categoryKey;
  final String categoryName;
  final IconData categoryIcon;
  final Color categoryColor;
  final Map<String, String> categoryPermissions;
  final Map<String, int> permMap;
  final List<int> selectedPermissionIds;
  final bool isExpanded;
  final bool isReadOnly;
  final VoidCallback onToggleExpand;
  final Function(bool?) onToggleCategory;
  final Function(int, bool) onTogglePermission;

  const PermissionCategoryCard({
    super.key,
    required this.categoryKey,
    required this.categoryName,
    required this.categoryIcon,
    required this.categoryColor,
    required this.categoryPermissions,
    required this.permMap,
    required this.selectedPermissionIds,
    required this.isExpanded,
    this.isReadOnly = false,
    required this.onToggleExpand,
    required this.onToggleCategory,
    required this.onTogglePermission,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // Count selected permissions in this category
    int selectedCount = 0;
    int totalCount = 0;
    for (final permCode in categoryPermissions.keys) {
      final permId = permMap[permCode];
      if (permId != null) {
        totalCount++;
        if (selectedPermissionIds.contains(permId)) {
          selectedCount++;
        }
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          // Category header
          InkWell(
            onTap: onToggleExpand,
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(12),
              bottom: isExpanded ? Radius.zero : const Radius.circular(12),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: categoryColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.vertical(
                  top: const Radius.circular(12),
                  bottom: isExpanded ? Radius.zero : const Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Icon(categoryIcon, color: categoryColor, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      categoryName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: categoryColor,
                      ),
                    ),
                  ),
                  // Badge showing selected/total
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: selectedCount == totalCount && totalCount > 0
                          ? AppColors.success.withValues(alpha: 0.2)
                          : selectedCount > 0
                              ? AppColors.warning.withValues(alpha: 0.2)
                              : theme.dividerColor.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$selectedCount / $totalCount',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: selectedCount == totalCount && totalCount > 0
                            ? AppColors.success
                            : selectedCount > 0
                                ? AppColors.warning
                                : AppColors.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Select all checkbox for category
                  Checkbox(
                    value: selectedCount == totalCount && totalCount > 0,
                    tristate: true,
                    onChanged: isReadOnly ? null : onToggleCategory,
                  ),
                  Icon(
                    isExpanded ? PhosphorIconsBold.caretUp : PhosphorIconsBold.caretDown,
                    size: 18,
                    color: AppColors.textMuted,
                  ),
                ],
              ),
            ),
          ),
          // Permission checkboxes
          if (isExpanded)
            Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2)),
                ),
              ),
              child: Column(
                children: (() {
                  final entries = categoryPermissions.entries.toList();
                  // Sort alphabetically by Arabic label
                  entries.sort((a, b) => a.value.compareTo(b.value));
                  return entries;
                })().map((entry) {
                  final permId = permMap[entry.key];
                  if (permId == null) return const SizedBox.shrink();

                  final isChecked = selectedPermissionIds.contains(permId);

                  return CheckboxListTile(
                    value: isChecked,
                    onChanged: isReadOnly ? null : (value) => onTogglePermission(permId, value ?? false),
                    title: Text(
                      entry.value,
                      style: TextStyle(
                        fontSize: 14,
                        color: isChecked ? null : AppColors.textMuted,
                      ),
                    ),
                    subtitle: Text(
                      entry.key,
                      style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                    ),
                    dense: true,
                    controlAffinity: ListTileControlAffinity.trailing,
                    secondary: Icon(
                      isChecked ? PhosphorIconsBold.checkCircle : PhosphorIconsBold.circle,
                      color: isChecked ? AppColors.success : AppColors.textMuted,
                      size: 18,
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}
