import 'package:flutter/material.dart';
import 'package:ural_erp/core/utils/friendly_error.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/shimmer_loading.dart';

import '../../data/providers/providers.dart';
import 'settings/widgets/add_role_dialog.dart';
import '../widgets/dialogs/app_confirm_dialog.dart';

class RoleManagementScreen extends ConsumerStatefulWidget {
  const RoleManagementScreen({super.key});

  @override
  ConsumerState<RoleManagementScreen> createState() =>
      _RoleManagementScreenState();
}

class _RoleManagementScreenState extends ConsumerState<RoleManagementScreen> {
  Role? _selectedRole;
  List<int> _selectedPermissionIds = [];
  bool _isSaving = false;

  final Map<String, String> _categoryLabels = {
    'pos': 'البيع السريع',
    'dashboard': 'لوحة التحكم',
    'inventory': 'المخزون',
    'products': 'المنتجات',
    'categories': 'التصنيفات',
    'customers': 'العملاء',
    'suppliers': 'الموردين',
    'purchases': 'المشتريات',
    'treasury': 'الخزينة',
    'tables': 'الطاولات',
    'kitchen': 'المطبخ',
    'hr': 'الموظفين',
    'reports': 'التقارير',
    'settings': 'الإعدادات',
    'users': 'المستخدمين',
    'system': 'النظام',
  };

  @override
  Widget build(BuildContext context) {
    final rolesAsync = ref.watch(allRolesProvider);
    final permissionsAsync = ref.watch(allPermissionsProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title: const Text('إدارة الأدوار والصلاحيات'),
          actions: [
            IconButton(
              icon: const Icon(PhosphorIconsBold.plus),
              onPressed: _showAddRoleDialog,
              tooltip: 'إضافة دور جديد',
            ),
          ],
        ),
        body: rolesAsync.when(
          data: (roles) => Row(
            children: [
              // Roles List Side
              Container(
                width: 280,
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  border: Border(
                    left: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.05),
                        border: Border(
                          bottom: BorderSide(
                            color: Theme.of(context).dividerColor,
                          ),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            PhosphorIconsBold.users,
                            size: 20,
                            color: AppColors.primary,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'الأدوار المتوفرة',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: roles.length,
                        itemBuilder: (context, index) {
                          final role = roles[index];
                          final isSelected = _selectedRole?.id == role.id;
                          return ListTile(
                            selected: isSelected,
                            selectedTileColor: AppColors.primary.withValues(
                              alpha: 0.1,
                            ),
                            leading: Icon(
                              isSelected
                                  ? PhosphorIconsBold.userCircleCheck
                                  : PhosphorIconsBold.userCircle,
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.textMuted,
                            ),
                            title: Text(
                              role.name,
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            subtitle: role.description != null
                                ? Text(
                                    role.description!,
                                    style: const TextStyle(fontSize: 11),
                                  )
                                : null,
                            onTap: () => _selectRole(role),
                            trailing: role.isSystemRole
                                ? const Icon(
                                    PhosphorIconsBold.lock,
                                    size: 14,
                                    color: AppColors.textMuted,
                                  )
                                : IconButton(
                                    icon: const Icon(
                                      PhosphorIconsBold.trash,
                                      size: 16,
                                      color: AppColors.error,
                                    ),
                                    onPressed: () => _deleteRole(role),
                                  ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              // Permissions Grid Side
              Expanded(
                child: _selectedRole == null
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              PhosphorIconsBold.shieldCheck,
                              size: 64,
                              color: AppColors.textMuted,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'اختر دوراً لتعديل صلاحياته',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                      )
                    : permissionsAsync.when(
                        data: (allPerms) => _buildPermissionsGrid(allPerms),
                        loading: () => Padding(
                          padding: const EdgeInsets.all(16),
                          child: ShimmerLoading.list(itemCount: 4),
                        ),
                        error: (e, _) => Center(
                          child: Text('Error loading permissions: $e'),
                        ),
                      ),
              ),
            ],
          ),
          loading: () => Padding(
            padding: const EdgeInsets.all(16),
            child: ShimmerLoading.list(itemCount: 6),
          ),
          error: (e, _) => Center(child: Text(friendlyError(e))),
        ),
      ),
    );
  }

  void _selectRole(Role role) async {
    setState(() {
      _selectedRole = role;
      _isSaving = true; // Temporary state while loading
    });

    final rolePerms = await ref
        .read(authRepositoryProvider)
        .getPermissionsForRole(role.id);

    if (mounted) {
      setState(() {
        _selectedPermissionIds = rolePerms.map((p) => p.id).toList();
        _isSaving = false;
      });
    }
  }

  Widget _buildPermissionsGrid(List<Permission> allPerms) {
    // Group permissions by category
    final Map<String, List<Permission>> groupedPerms = {};
    for (final perm in allPerms) {
      if (!groupedPerms.containsKey(perm.category)) {
        groupedPerms[perm.category] = [];
      }
      groupedPerms[perm.category]!.add(perm);
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: AppColors.primary.withValues(alpha: 0.05),
          child: Row(
            children: [
              const Icon(
                PhosphorIconsBold.shieldCheck,
                color: AppColors.primary,
              ),
              const SizedBox(width: 12),
              Text(
                'صلاحيات الدور: ${_selectedRole!.name}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (_selectedRole!.isSystemRole)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  margin: const EdgeInsets.only(left: 12),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'دور نظامي',
                    style: TextStyle(
                      color: AppColors.warning,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _savePermissions,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(PhosphorIconsBold.check),
                label: const Text('حفظ التغييرات'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Table(
                  border: TableBorder.symmetric(
                    inside: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                  columnWidths: const {
                    0: FlexColumnWidth(2.5),
                    1: FlexColumnWidth(5),
                  },
                  children: [
                    // Header
                    TableRow(
                      decoration: BoxDecoration(color: Colors.grey[100]),
                      children: const [
                        Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'الميزة / النظام',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'الصلاحيات المتاحة',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    // Feature Rows
                    ...groupedPerms.entries.map((entry) {
                      final category = entry.key;
                      final perms = entry.value;
                      return TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _categoryLabels[category] ?? category,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                  ),
                                ),
                                Text(
                                  category.toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: perms.map((p) {
                                final isSelected = _selectedPermissionIds
                                    .contains(p.id);
                                final isDark =
                                    Theme.of(context).brightness ==
                                    Brightness.dark;
                                // Text color: black on light mode, white on dark mode
                                final labelColor = isDark
                                    ? Colors.white
                                    : Colors.black87;

                                return IntrinsicWidth(
                                  child: FilterChip(
                                    label: Text(
                                      p.name,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: labelColor,
                                      ),
                                    ),
                                    selected: isSelected,
                                    onSelected: (selected) {
                                      setState(() {
                                        if (selected) {
                                          _selectedPermissionIds.add(p.id);
                                        } else {
                                          _selectedPermissionIds.remove(p.id);
                                        }
                                      });
                                    },
                                    selectedColor: AppColors.primary.withValues(
                                      alpha: 0.15,
                                    ),
                                    checkmarkColor: AppColors.primary,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showAddRoleDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const AddRoleDialog(),
    );
    // Provider will auto-refresh, but we might want to reset selection if needed
  }

  void _deleteRole(Role role) async {
    final confirmed = await AppConfirmDialog.show(
      context,
      title: 'تأكيد الحذف',
      message: 'هل أنت متأكد من حذف دور "${role.name}"؟',
      confirmLabel: 'حذف',
      color: AppColors.error,
      icon: PhosphorIconsBold.trash,
    );

    if (confirmed == true) {
      final authRepo = ref.read(authRepositoryProvider);
      await authRepo.deleteRole(role.id);
      if (mounted) {
        setState(() => _selectedRole = null);
      }
    }
  }

  Future<void> _savePermissions() async {
    if (_selectedRole == null) return;

    setState(() => _isSaving = true);

    try {
      await ref
          .read(authRepositoryProvider)
          .setRolePermissions(_selectedRole!.id, _selectedPermissionIds);

      // Invalidate cached permission providers so changes take effect immediately
      ref.invalidate(rolePermissionsProvider(_selectedRole!.id));
      ref.invalidate(currentUserPermissionsProvider);

      if (mounted) {
        AppToast.show(
          context,
          'تم حفظ الصلاحيات بنجاح',
          type: ToastType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'خطأ أثناء الحفظ: $e', type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
