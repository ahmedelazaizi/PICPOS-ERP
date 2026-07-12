import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/design_system/typography.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../data/providers/providers.dart';

/// Permissions Management Screen — comprehensive role-based permission editor
///
/// Lists all 140+ system permissions grouped by category (19 categories).
/// Allows admin to select a role, then toggle individual permissions via checkboxes.
class PermissionsManagementWidget extends ConsumerStatefulWidget {
  const PermissionsManagementWidget({super.key});

  @override
  ConsumerState<PermissionsManagementWidget> createState() =>
      _PermissionsManagementWidgetState();
}

class _PermissionsManagementWidgetState
    extends ConsumerState<PermissionsManagementWidget> {
  Role? _selectedRole;
  List<Permission> _allPermissions = [];
  Set<int> _rolePermissionIds = {};
  bool _isLoading = false;
  bool _isSaving = false;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  // Track expanded categories
  final Set<String> _expandedCategories = {};

  @override
  void initState() {
    super.initState();
    _loadPermissions();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPermissions() async {
    setState(() => _isLoading = true);
    try {
      final authRepo = ref.read(authRepositoryProvider);
      _allPermissions = await authRepo.getAllPermissions();
      // Auto-expand all categories initially
      _expandedCategories.addAll(
        _allPermissions.map((p) => p.category).toSet(),
      );
    } catch (e) {
      if (mounted) {
        AppToast.show(
          context,
          'خطأ في تحميل الصلاحيات: $e',
          type: ToastType.error,
        );
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadRolePermissions(Role role) async {
    setState(() {
      _selectedRole = role;
      _isLoading = true;
    });
    try {
      final authRepo = ref.read(authRepositoryProvider);
      final perms = await authRepo.getPermissionsForRole(role.id);
      _rolePermissionIds = perms.map((p) => p.id).toSet();
    } catch (e) {
      if (mounted) {
        AppToast.show(
          context,
          'خطأ في تحميل صلاحيات الدور: $e',
          type: ToastType.error,
        );
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _togglePermission(int permissionId, bool grant) async {
    if (_selectedRole == null) return;

    // Resolve the permission's name UPFRONT so the confirmation toast shows
    // exactly which chip the cashier just toggled — the user reported
    // "Toggling pos_save did nothing" and the diagnostic log confirmed it
    // was never persisted. Hard-to-miss feedback is the cheapest fix.
    final perm = _allPermissions.firstWhere(
      (p) => p.id == permissionId,
      orElse: () => Permission(
        id: permissionId,
        code: '?',
        name: '?',
        category: '?',
      ),
    );

    // Optimistic UI update
    setState(() {
      if (grant) {
        _rolePermissionIds.add(permissionId);
      } else {
        _rolePermissionIds.remove(permissionId);
      }
    });

    try {
      final authRepo = ref.read(authRepositoryProvider);
      // Use setRolePermissions with updated set
      await authRepo.setRolePermissions(
        _selectedRole!.id,
        _rolePermissionIds.toList(),
      );
      // Invalidate cached permission providers so changes take effect immediately
      ref.invalidate(rolePermissionsProvider(_selectedRole!.id));
      ref.invalidate(currentUserPermissionsProvider);

      // P5 (Issue #1): explicit confirmation. Without it the user thought
      // they were enabling pos_save but the chip was already enabled — the
      // click silently disabled it and the log later proved 19 perms saved
      // instead of the expected 20.
      if (mounted) {
        final total = _rolePermissionIds.length;
        AppToast.show(
          context,
          grant
              ? '✓ تم إضافة "${perm.name}" — الإجمالى: $total صلاحية'
              : '⊝ تم إلغاء "${perm.name}" — الإجمالى: $total صلاحية',
          type: grant ? ToastType.success : ToastType.warning,
        );
      }
    } catch (e) {
      // Revert on failure
      setState(() {
        if (grant) {
          _rolePermissionIds.remove(permissionId);
        } else {
          _rolePermissionIds.add(permissionId);
        }
      });
      if (mounted) {
        AppToast.show(
          context,
          'فشل تحديث الصلاحية "${perm.name}": $e',
          type: ToastType.error,
        );
      }
    }
  }

  Future<void> _toggleCategory(String category, bool grantAll) async {
    if (_selectedRole == null) return;

    final categoryPerms = _allPermissions
        .where((p) => p.category == category)
        .toList();
    final permIds = categoryPerms.map((p) => p.id).toList();

    // Optimistic UI update
    setState(() {
      if (grantAll) {
        _rolePermissionIds.addAll(permIds);
      } else {
        _rolePermissionIds.removeAll(permIds);
      }
    });

    try {
      final authRepo = ref.read(authRepositoryProvider);
      // Batch update via setRolePermissions
      await authRepo.setRolePermissions(
        _selectedRole!.id,
        _rolePermissionIds.toList(),
      );
      ref.invalidate(rolePermissionsProvider(_selectedRole!.id));
      ref.invalidate(currentUserPermissionsProvider);
    } catch (e) {
      // Reload on failure to get accurate state
      if (_selectedRole != null) await _loadRolePermissions(_selectedRole!);
      if (mounted) {
        AppToast.show(
          context,
          'فشل تحديث صلاحيات الفئة',
          type: ToastType.error,
        );
      }
    }
  }

  Future<void> _grantAll() async {
    if (_selectedRole == null) return;
    setState(() => _isSaving = true);
    try {
      final authRepo = ref.read(authRepositoryProvider);
      final allIds = _allPermissions.map((p) => p.id).toList();
      await authRepo.setRolePermissions(_selectedRole!.id, allIds);
      _rolePermissionIds = allIds.toSet();
      ref.invalidate(rolePermissionsProvider(_selectedRole!.id));
      ref.invalidate(currentUserPermissionsProvider);
      if (mounted) {
        AppToast.show(
          context,
          'تم منح جميع الصلاحيات',
          type: ToastType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'خطأ: $e', type: ToastType.error);
      }
    }
    if (mounted) setState(() => _isSaving = false);
  }

  Future<void> _revokeAll() async {
    if (_selectedRole == null) return;

    // Confirm before revoking
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد إزالة جميع الصلاحيات'),
          content: Text(
            'هل أنت متأكد من إزالة جميع الصلاحيات من دور "${_selectedRole!.name}"؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('إزالة الكل'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    setState(() => _isSaving = true);
    try {
      final authRepo = ref.read(authRepositoryProvider);
      await authRepo.setRolePermissions(_selectedRole!.id, []);
      _rolePermissionIds.clear();
      ref.invalidate(rolePermissionsProvider(_selectedRole!.id));
      ref.invalidate(currentUserPermissionsProvider);
      if (mounted) {
        AppToast.show(
          context,
          'تم إزالة جميع الصلاحيات',
          type: ToastType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'خطأ: $e', type: ToastType.error);
      }
    }
    if (mounted) setState(() => _isSaving = false);
  }

  Map<String, List<Permission>> get _groupedPermissions {
    final Map<String, List<Permission>> grouped = {};
    for (final perm in _allPermissions) {
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        if (!perm.name.toLowerCase().contains(query) &&
            !perm.code.toLowerCase().contains(query) &&
            !(PermissionCodes.categoryNames[perm.category] ?? '').contains(
              query,
            )) {
          continue;
        }
      }
      grouped.putIfAbsent(perm.category, () => []).add(perm);
    }
    return grouped;
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'pos':
        return PhosphorIconsBold.storefront;
      case 'dashboard':
        return PhosphorIconsBold.chartPieSlice;
      case 'inventory':
        return PhosphorIconsBold.warehouse;
      case 'products':
        return PhosphorIconsBold.package;
      case 'categories':
        return PhosphorIconsBold.folders;
      case 'customers':
        return PhosphorIconsBold.users;
      case 'suppliers':
        return PhosphorIconsBold.truck;
      case 'purchases':
        return PhosphorIconsBold.shoppingCart;
      case 'sales':
        return PhosphorIconsBold.receipt;
      case 'offers':
        return PhosphorIconsBold.tag;
      case 'delivery':
        return PhosphorIconsBold.mapPin;
      case 'tables':
        return PhosphorIconsBold.table;
      case 'kitchen':
        return PhosphorIconsBold.cookingPot;
      case 'treasury':
        return PhosphorIconsBold.vault;
      case 'hr':
        return PhosphorIconsBold.identificationBadge;
      case 'reports':
        return PhosphorIconsBold.chartBar;
      case 'settings':
        return PhosphorIconsBold.gear;
      case 'users':
        return PhosphorIconsBold.userCircle;
      case 'system':
        return PhosphorIconsBold.desktop;
      case 'audit':
        return PhosphorIconsBold.clipboardText;
      default:
        return PhosphorIconsBold.shieldCheck;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'pos':
        return AppColors.primary;
      case 'dashboard':
        return const Color(0xFF6366F1);
      case 'inventory':
        return const Color(0xFF8B5CF6);
      case 'products':
        return AppColors.info;
      case 'categories':
        return const Color(0xFF0891B2);
      case 'customers':
        return AppColors.success;
      case 'suppliers':
        return const Color(0xFFEA580C);
      case 'purchases':
        return const Color(0xFFD97706);
      case 'sales':
        return const Color(0xFF059669);
      case 'offers':
        return AppColors.warning;
      case 'delivery':
        return const Color(0xFFDB2777);
      case 'tables':
        return const Color(0xFF7C3AED);
      case 'kitchen':
        return const Color(0xFFDC2626);
      case 'treasury':
        return const Color(0xFF0D9488);
      case 'hr':
        return const Color(0xFF4F46E5);
      case 'reports':
        return const Color(0xFF2563EB);
      case 'settings':
        return const Color(0xFF64748B);
      case 'users':
        return const Color(0xFFE11D48);
      case 'system':
        return const Color(0xFF475569);
      case 'audit':
        return const Color(0xFF9333EA);
      default:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final rolesAsync = ref.watch(allRolesProvider);

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Column(
        children: [
          // Header
          _buildHeader(),
          const SizedBox(height: 12),

          // Main content
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Role sidebar
                _buildRoleSidebar(rolesAsync),
                const SizedBox(width: 16),

                // Permissions grid
                Expanded(child: _buildPermissionsPanel()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(
          PhosphorIconsBold.shieldCheck,
          color: AppColors.primary,
          size: 24,
        ),
        const SizedBox(width: 8),
        const Text('إدارة الصلاحيات', style: AppTypography.h3),
        const Spacer(),
        if (_selectedRole != null) ...[
          // Search
          SizedBox(
            width: 220,
            height: 36,
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'بحث عن صلاحية...',
                hintStyle: AppTypography.bodySmall.copyWith(color: Colors.grey),
                prefixIcon: const Icon(
                  PhosphorIconsBold.magnifyingGlass,
                  size: 16,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Grant all / Revoke all
          _ActionButton(
            icon: PhosphorIconsBold.checkSquare,
            label: 'تحديد الكل',
            color: AppColors.success,
            onPressed: _isSaving ? null : _grantAll,
          ),
          const SizedBox(width: 6),
          _ActionButton(
            icon: PhosphorIconsBold.square,
            label: 'إلغاء الكل',
            color: AppColors.error,
            onPressed: _isSaving ? null : _revokeAll,
          ),
        ],
      ],
    );
  }

  Widget _buildRoleSidebar(AsyncValue<List<Role>> rolesAsync) {
    return Container(
      width: 200,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Sidebar header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  PhosphorIconsBold.usersThree,
                  size: 18,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'الأدوار',
                  style: AppTypography.bodyLarge.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),

          // Roles list
          Expanded(
            child: rolesAsync.when(
              data: (roles) => ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: roles.length,
                itemBuilder: (context, index) {
                  final role = roles[index];
                  final isSelected = _selectedRole?.id == role.id;
                  final isSystem =
                      role.isSystemRole && role.name == 'مدير النظام';

                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    child: Material(
                      color: isSelected
                          ? AppColors.primary.withValues(alpha: 0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: isSystem
                            ? null
                            : () => _loadRolePermissions(role),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _getRoleIcon(role.name),
                                size: 18,
                                color: isSelected
                                    ? AppColors.primary
                                    : isSystem
                                    ? Colors.grey.shade400
                                    : Theme.of(
                                        context,
                                      ).textTheme.bodyMedium?.color,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  role.name,
                                  style: AppTypography.bodyRegular.copyWith(
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isSystem
                                        ? Colors.grey.shade400
                                        : null,
                                  ),
                                ),
                              ),
                              if (isSystem)
                                Tooltip(
                                  message:
                                      'مدير النظام لديه كل الصلاحيات تلقائياً',
                                  child: Icon(
                                    PhosphorIconsBold.crown,
                                    size: 14,
                                    color: Colors.amber.shade700,
                                  ),
                                ),
                              if (isSelected)
                                const Icon(
                                  PhosphorIconsBold.caretLeft,
                                  size: 14,
                                  color: AppColors.primary,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('خطأ: $e')),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getRoleIcon(String roleName) {
    switch (roleName) {
      case 'مدير النظام':
        return PhosphorIconsBold.crown;
      case 'كاشير':
        return PhosphorIconsBold.creditCard;
      case 'مخزني':
        return PhosphorIconsBold.package;
      case 'محاسب':
        return PhosphorIconsBold.calculator;
      default:
        return PhosphorIconsBold.user;
    }
  }

  Widget _buildPermissionsPanel() {
    if (_selectedRole == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              PhosphorIconsBold.shieldChevron,
              size: 64,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              'اختر دوراً من القائمة لعرض وتعديل صلاحياته',
              style: AppTypography.bodyLarge.copyWith(
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final grouped = _groupedPermissions;
    if (grouped.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              PhosphorIconsBold.magnifyingGlass,
              size: 48,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 12),
            Text(
              'لا توجد نتائج للبحث',
              style: AppTypography.bodyLarge.copyWith(
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      );
    }

    final categories = grouped.keys.toList();

    // Stats bar
    final totalPerms = _allPermissions.length;
    final grantedPerms = _rolePermissionIds.length;
    final progress = totalPerms > 0 ? grantedPerms / totalPerms : 0.0;

    return Column(
      children: [
        // Stats row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
          ),
          child: Row(
            children: [
              const Icon(PhosphorIconsBold.user, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'صلاحيات: ${_selectedRole!.name}',
                style: AppTypography.bodyLarge.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: Colors.grey.withValues(alpha: 0.2),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      progress > 0.8
                          ? AppColors.success
                          : progress > 0.4
                          ? AppColors.warning
                          : AppColors.error,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$grantedPerms / $totalPerms',
                  style: AppTypography.bodySmall.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Category permission cards
        Expanded(
          child: ListView.builder(
            itemCount: categories.length,
            padding: const EdgeInsets.only(bottom: 20),
            itemBuilder: (context, index) {
              final category = categories[index];
              final perms = grouped[category]!;
              return _buildCategoryCard(category, perms);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryCard(String category, List<Permission> perms) {
    final categoryName = PermissionCodes.categoryNames[category] ?? category;
    final icon = _getCategoryIcon(category);
    final color = _getCategoryColor(category);
    final isExpanded = _expandedCategories.contains(category);

    // Category-level check stats
    final totalInCategory = perms.length;
    final grantedInCategory = perms
        .where((p) => _rolePermissionIds.contains(p.id))
        .length;
    final allGranted = grantedInCategory == totalInCategory;
    final someGranted = grantedInCategory > 0 && !allGranted;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: allGranted
              ? color.withValues(alpha: 0.3)
              : Colors.grey.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        children: [
          // Category header (tap to expand/collapse)
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedCategories.remove(category);
                } else {
                  _expandedCategories.add(category);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  // Category select-all checkbox
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: allGranted
                          ? true
                          : someGranted
                          ? null
                          : false,
                      tristate: true,
                      activeColor: color,
                      onChanged: (val) {
                        _toggleCategory(category, !allGranted);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(icon, size: 18, color: color),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          categoryName,
                          style: AppTypography.bodyLarge.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '$grantedInCategory من $totalInCategory صلاحية',
                          style: AppTypography.bodySmall.copyWith(
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Mini progress
                  SizedBox(
                    width: 50,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: totalInCategory > 0
                            ? grantedInCategory / totalInCategory
                            : 0,
                        minHeight: 4,
                        backgroundColor: Colors.grey.withValues(alpha: 0.15),
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    isExpanded
                        ? PhosphorIconsBold.caretUp
                        : PhosphorIconsBold.caretDown,
                    size: 16,
                    color: Colors.grey.shade500,
                  ),
                ],
              ),
            ),
          ),

          // Permission items (expanded)
          if (isExpanded) ...[
            Divider(height: 1, color: Colors.grey.withValues(alpha: 0.12)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: perms.map((perm) {
                  final isGranted = _rolePermissionIds.contains(perm.id);
                  return _PermissionChip(
                    permission: perm,
                    isGranted: isGranted,
                    color: color,
                    onToggle: (grant) => _togglePermission(perm.id, grant),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Compact permission toggle chip
class _PermissionChip extends StatelessWidget {
  final Permission permission;
  final bool isGranted;
  final Color color;
  final ValueChanged<bool> onToggle;

  const _PermissionChip({
    required this.permission,
    required this.isGranted,
    required this.color,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isGranted
          ? color.withValues(alpha: 0.08)
          : Colors.grey.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => onToggle(!isGranted),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isGranted
                    ? PhosphorIconsBold.checkSquare
                    : PhosphorIconsBold.square,
                size: 16,
                color: isGranted ? color : Colors.grey.shade400,
              ),
              const SizedBox(width: 6),
              Text(
                permission.name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isGranted ? FontWeight.w600 : FontWeight.normal,
                  color: isGranted
                      ? Theme.of(context).textTheme.bodyMedium?.color
                      : Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact action button for header
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16, color: color),
      label: Text(label, style: TextStyle(fontSize: 12, color: color)),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        backgroundColor: color.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

/// Helper to show permissions management as a full dialog
void showPermissionsManagementDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Row(
        children: [
          Icon(PhosphorIconsBold.shieldCheck, color: AppColors.primary),
          SizedBox(width: 8),
          Text('إدارة الصلاحيات'),
        ],
      ),
      content: const SizedBox(
        width: 850,
        height: 600,
        child: PermissionsManagementWidget(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إغلاق'),
        ),
      ],
    ),
  );
}
