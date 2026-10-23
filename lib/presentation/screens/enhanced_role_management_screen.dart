import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:picpos_erp/core/widgets/app_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/shimmer_loading.dart';
import '../../data/database/sync_interceptor.dart';
import '../../data/providers/providers.dart';
import 'role_management/data/permission_categories.dart';
import 'role_management/widgets/role_list_panel.dart';
import 'role_management/widgets/permissions_panel.dart';

/// Enhanced Role Management Screen - Refactored version
class EnhancedRoleManagementScreen extends ConsumerStatefulWidget {
  const EnhancedRoleManagementScreen({super.key});

  @override
  ConsumerState<EnhancedRoleManagementScreen> createState() =>
      _EnhancedRoleManagementScreenState();
}

class _EnhancedRoleManagementScreenState
    extends ConsumerState<EnhancedRoleManagementScreen> {
  Role? _selectedRole;
  List<int> _selectedPermissionIds = [];
  bool _isSaving = false;
  Set<String> _expandedCategories = {};

  @override
  Widget build(BuildContext context) {
    final rolesAsync = ref.watch(allRolesProvider);
    final permissionsAsync = ref.watch(allPermissionsProvider);
  // ignore: unused_local_variable
    final theme = Theme.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title:  Text(tr('إدارة الأدوار والصلاحيات المتقدمة')),
          actions: [
            IconButton(
              icon: const Icon(PhosphorIconsBold.plus),
              onPressed: _showAddRoleDialog,
              tooltip: tr('إضافة دور جديد'),
            ),
            if (_selectedRole != null && !_isSaving && _selectedRole!.name != 'مدير النظام')
              IconButton(
                icon: const Icon(PhosphorIconsBold.floppyDisk),
                onPressed: _savePermissions,
                tooltip: tr('حفظ الصلاحيات'),
              ),
          ],
        ),
        body: rolesAsync.when(
          data: (roles) => Row(
            children: [
              // Roles List Side
              RoleListPanel(
                roles: roles,
                selectedRole: _selectedRole,
                onSelectRole: _selectRole,
                onDeleteRole: _deleteRole,
              ),
              // Permissions Panel Side
              Expanded(
                child: _selectedRole == null
                    ? _buildEmptyState()
                    : permissionsAsync.when(
                        data: (allPerms) => PermissionsPanel(
                          selectedRole: _selectedRole!,
                          allPermissions: allPerms,
                          selectedPermissionIds: _selectedPermissionIds,
                          expandedCategories: _expandedCategories,
                          isSaving: _isSaving,
                          onExpandedCategoriesChanged: (newSet) =>
                              setState(() => _expandedCategories = newSet),
                          onTogglePermission: _togglePermission,
                          onToggleCategory: (key, selectAll) =>
                              _toggleCategoryPermissions(allPerms, key, selectAll),
                          onSave: _savePermissions,
                        ),
                        loading: () => Padding(
                          padding: const EdgeInsets.all(16),
                          child: ShimmerLoading.list(itemCount: 4),
                        ),
                        error: (e, _) => Center(child: Text(tr('خطأ: {e}', {'e': e}))),
                      ),
              ),
            ],
          ),
          loading: () => Padding(
            padding: const EdgeInsets.all(16),
            child: ShimmerLoading.list(itemCount: 6),
          ),
          error: (e, _) => Center(child: Text(tr('خطأ: {e}', {'e': e}))),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return  Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            PhosphorIconsBold.shieldCheck,
            size: 80,
            color: AppColors.textMuted,
          ),
          const SizedBox(height: 16),
          Text(
            tr('اختر دوراً لتعديل صلاحياته'),
            style: const TextStyle(color: AppColors.textMuted, fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            tr('يمكنك تحديد الصلاحيات التفصيلية لكل دور'),
            style: const TextStyle(color: AppColors.textMuted, fontSize: 14),
          ),
        ],
      ),
    );
  }

  void _selectRole(Role role) async {
    setState(() {
      _selectedRole = role;
      _isSaving = true;
      _expandedCategories = {}; // Collapse all when switching roles
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

  void _togglePermission(int permId, bool isSelected) {
    setState(() {
      if (isSelected) {
        if (!_selectedPermissionIds.contains(permId)) {
          _selectedPermissionIds.add(permId);
        }
      } else {
        _selectedPermissionIds.remove(permId);
      }
    });
  }

  void _toggleCategoryPermissions(
    List<Permission> allPerms,
    String categoryKey,
    bool selectAll,
  ) {
    final category = permissionCategories[categoryKey];
    if (category == null) return;

    final permMap = <String, int>{};
    for (final p in allPerms) {
      permMap[p.code] = p.id;
    }

    setState(() {
      for (final permCode in category.permissions.keys) {
        final permId = permMap[permCode];
        if (permId != null) {
          if (selectAll) {
            if (!_selectedPermissionIds.contains(permId)) {
              _selectedPermissionIds.add(permId);
            }
          } else {
            _selectedPermissionIds.remove(permId);
          }
        }
      }
    });
  }

  Future<void> _savePermissions() async {
    if (_selectedRole == null || _selectedRole!.name == 'مدير النظام') return;

    setState(() => _isSaving = true);

    try {
      final authRepo = ref.read(authRepositoryProvider);
      await authRepo.setRolePermissions(_selectedRole!.id, _selectedPermissionIds);

      // Invalidate cached permission providers so changes take effect immediately
      ref.invalidate(rolePermissionsProvider(_selectedRole!.id));
      ref.invalidate(currentUserPermissionsProvider);

      final user = ref.read(authProvider).user;
      final logger = ref.read(activityLoggerProvider);
      await logger.logUpdateRolePermissions(
        user?.id ?? 0,
        user?.displayName ?? tr('مجهول'),
        _selectedRole!.name,
        _selectedPermissionIds.length,
      );

      if (mounted) {
        AppToast.show(
          context,
          tr('✅ تم حفظ الصلاحيات بنجاح'),
          type: ToastType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, tr('❌ خطأ في الحفظ: {e}', {'e': e}), type: ToastType.error);
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showAddRoleDialog() {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title:  Row(
            children: [
              const Icon(PhosphorIconsBold.userPlus, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(tr('إضافة دور جديد')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration:  InputDecoration(
                  labelText: tr('اسم الدور'),
                  hintText: tr('مثال: محاسب، أمين مخزن'),
                  prefixIcon: const Icon(PhosphorIconsBold.user),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descController,
                decoration:  InputDecoration(
                  labelText: tr('الوصف (اختياري)'),
                  hintText: tr('وصف مختصر للدور'),
                  prefixIcon: const Icon(PhosphorIconsBold.textAa),
                ),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child:  Text(tr('إلغاء')),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) {
                  AppToast.show(context, tr('يرجى إدخال اسم الدور'));
                  return;
                }
                final authRepo = ref.read(authRepositoryProvider);
                // In client mode: push role to server first
                if (SyncInterceptor.isClientMode) {
                  await SyncInterceptor.instance!.createRole(
                    name: nameController.text.trim(),
                    description: descController.text.trim().isEmpty
                        ? null
                        : descController.text.trim(),
                  );
                }
                await authRepo.insertRole(
                  name: nameController.text.trim(),
                  description: descController.text.trim().isEmpty
                      ? null
                      : descController.text.trim(),
                );
                final user = ref.read(authProvider).user;
                final logger = ref.read(activityLoggerProvider);
                await logger.logRoleCreate(
                  user?.id ?? 0,
                  user?.displayName ?? tr('مجهول'),
                  nameController.text.trim(),
                );
                ref.invalidate(allRolesProvider);
                if (context.mounted) Navigator.pop(context);
              },
              child:  Text(tr('إضافة')),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteRole(Role role) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title:  Row(
            children: [
              const Icon(PhosphorIconsBold.warning, color: AppColors.error),
              const SizedBox(width: 8),
              Text(tr('تأكيد الحذف')),
            ],
          ),
          content: Text(tr('هل أنت متأكد من حذف دور "{p0}"؟', {'p0': role.name})),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child:  Text(tr('إلغاء')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              child:  Text(tr('حذف')),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      final authRepo = ref.read(authRepositoryProvider);
      await authRepo.deleteRole(role.id);
      final user = ref.read(authProvider).user;
      final logger = ref.read(activityLoggerProvider);
      await logger.logRoleDelete(
        user?.id ?? 0,
        user?.displayName ?? tr('مجهول'),
        role.name,
      );
      ref.invalidate(allRolesProvider);
      if (_selectedRole?.id == role.id) {
        setState(() => _selectedRole = null);
      }
    }
  }
}
