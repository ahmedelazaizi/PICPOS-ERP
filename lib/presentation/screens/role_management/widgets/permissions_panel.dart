import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../core/design_system/typography.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/database/database_barrel.dart';
import '../data/permission_categories.dart';
import 'permission_category_card.dart';

class PermissionsPanel extends StatelessWidget {
  final Role selectedRole;
  final List<Permission> allPermissions;
  final List<int> selectedPermissionIds;
  final Set<String> expandedCategories;
  final bool isSaving;
  final Function(Set<String>) onExpandedCategoriesChanged;
  final Function(int, bool) onTogglePermission;
  final Function(String, bool) onToggleCategory;
  final VoidCallback onSave;

  const PermissionsPanel({
    super.key,
    required this.selectedRole,
    required this.allPermissions,
    required this.selectedPermissionIds,
    required this.expandedCategories,
    required this.isSaving,
    required this.onExpandedCategoriesChanged,
    required this.onTogglePermission,
    required this.onToggleCategory,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isReadOnly = selectedRole.name == 'مدير النظام';

    // Build a map of permission code -> permission id
    final permMap = <String, int>{};
    for (final p in allPermissions) {
      permMap[p.code] = p.id;
    }

    return Column(
      children: [
        // Header with role info and search
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.cardColor,
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: Row(
            children: [
              Icon(
                selectedRole.isSystemRole
                    ? PhosphorIconsBold.shieldStar
                    : PhosphorIconsBold.shieldCheck,
                color: AppColors.primary,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('صلاحيات: {p0}', {'p0': selectedRole.name}),
                      style: AppTypography.h3,
                    ),
                    if (isReadOnly)
                       Text(
                        tr('ℹ️ المدير لديه كل الصلاحيات تلقائياً'),
                        style: const TextStyle(color: AppColors.info, fontSize: 12),
                      ),
                  ],
                ),
              ),
              // Expand all / Collapse all buttons
              IconButton(
                icon: const Icon(PhosphorIconsBold.arrowsOut, size: 20),
                onPressed: () => onExpandedCategoriesChanged(permissionCategories.keys.toSet()),
                tooltip: tr('توسيع الكل'),
              ),
              IconButton(
                icon: const Icon(PhosphorIconsBold.arrowsIn, size: 20),
                onPressed: () => onExpandedCategoriesChanged({}),
                tooltip: tr('طي الكل'),
              ),
            ],
          ),
        ),
        // Permission categories
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: permissionCategories.length,
            itemBuilder: (context, index) {
              final categoryKey = permissionCategories.keys.elementAt(index);
              final category = permissionCategories[categoryKey]!;
              final isExpanded = expandedCategories.contains(categoryKey);

              return PermissionCategoryCard(
                categoryKey: categoryKey,
                categoryName: category.name,
                categoryIcon: category.icon,
                categoryColor: category.color,
                categoryPermissions: category.permissions,
                permMap: permMap,
                selectedPermissionIds: selectedPermissionIds,
                isExpanded: isExpanded,
                isReadOnly: isReadOnly || isSaving,
                onToggleExpand: () {
                  final newSet = Set<String>.from(expandedCategories);
                  if (isExpanded) {
                    newSet.remove(categoryKey);
                  } else {
                    newSet.add(categoryKey);
                  }
                  onExpandedCategoriesChanged(newSet);
                },
                onToggleCategory: (value) => onToggleCategory(categoryKey, value == true),
                onTogglePermission: onTogglePermission,
              );
            },
          ),
        ),
        // Save button
        if (!isReadOnly)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.cardColor,
              border: Border(top: BorderSide(color: theme.dividerColor)),
            ),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isSaving ? null : onSave,
                icon: isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(PhosphorIconsBold.floppyDisk),
                label: Text(isSaving ? tr('جاري الحفظ...') : tr('حفظ الصلاحيات')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
