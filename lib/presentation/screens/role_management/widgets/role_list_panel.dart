import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/database/database_barrel.dart';

class RoleListPanel extends StatelessWidget {
  final List<Role> roles;
  final Role? selectedRole;
  final Function(Role) onSelectRole;
  final Function(Role) onDeleteRole;

  const RoleListPanel({
    super.key,
    required this.roles,
    required this.selectedRole,
    required this.onSelectRole,
    required this.onDeleteRole,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(left: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.05),
              border: Border(bottom: BorderSide(color: theme.dividerColor)),
            ),
            child:  Row(
              children: [
                const Icon(
                  PhosphorIconsBold.users,
                  size: 20,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  tr('الأدوار المتوفرة'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: roles.length,
              itemBuilder: (context, index) {
                final role = roles[index];
                final isSelected = selectedRole?.id == role.id;
                return ListTile(
                  selected: isSelected,
                  selectedTileColor: AppColors.primary.withValues(alpha: 0.1),
                  leading: Icon(
                    isSelected
                        ? PhosphorIconsBold.userCircleCheck
                        : PhosphorIconsBold.userCircle,
                    color: isSelected ? AppColors.primary : AppColors.textMuted,
                  ),
                  title: Text(
                    trData(role.name),
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  subtitle: role.description != null && role.description!.isNotEmpty
                      ? Text(
                          trData(role.description),
                          style: const TextStyle(fontSize: 11),
                        )
                      : null,
                  onTap: () => onSelectRole(role),
                  trailing: role.isSystemRole
                      ?  Tooltip(
                          message: tr('دور نظام - لا يمكن حذفه'),
                          child: const Icon(
                            PhosphorIconsBold.lock,
                            size: 14,
                            color: AppColors.textMuted,
                          ),
                        )
                      : IconButton(
                          icon: const Icon(
                            PhosphorIconsBold.trash,
                            size: 16,
                            color: AppColors.error,
                          ),
                          onPressed: () => onDeleteRole(role),
                          tooltip: tr('حذف الدور'),
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
