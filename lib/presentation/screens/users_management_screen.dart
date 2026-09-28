import 'package:flutter/material.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
// 063 (D1-005): dual-approval gate for user-role changes.
import 'package:ural_erp/services/dual_approval_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/auth/bootstrap_admin.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/shimmer_loading.dart';

import '../../data/providers/providers.dart';
import '../widgets/enhanced_components.dart';
import '../../services/client_write_interceptor.dart';
import '../widgets/dialogs/app_confirm_dialog.dart';
import 'settings/widgets/add_user_dialog.dart';
import 'settings/widgets/edit_user_dialog.dart';
import 'settings/widgets/reset_password_dialog.dart';
import 'settings/widgets/security_alerts_panel.dart';
import 'settings/widgets/set_pin_dialog.dart';
import 'settings/widgets/branch_access_dialog.dart';
import 'settings/widgets/warehouse_access_dialog.dart';

/// Users Management Screen - Admin only
/// Allows managing users and assigning roles
class UsersManagementScreen extends ConsumerStatefulWidget {
  const UsersManagementScreen({super.key});

  @override
  ConsumerState<UsersManagementScreen> createState() =>
      _UsersManagementScreenState();
}

class _UsersManagementScreenState extends ConsumerState<UsersManagementScreen> {
  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(allUsersProvider);
    final rolesAsync = ref.watch(allRolesProvider);
    final branchNamesAsync = ref.watch(allUserBranchNamesProvider);
    final theme = Theme.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title: const Row(
            children: [
              Icon(PhosphorIconsBold.usersThree),
              SizedBox(width: 8),
              Text('إدارة المستخدمين والصلاحيات'),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(PhosphorIconsBold.userPlus),
              onPressed: () => _showAddUserDialog(),
              tooltip: 'إضافة مستخدم',
            ),
          ],
        ),
        body: usersAsync.when(
          data: (users) => rolesAsync.when(
            data: (roles) => Column(
              children: [
                // Feature 004 (US2) — surface unresolved cross-branch password
                // collision alerts to the System Admin only. The panel hides
                // itself when there are no alerts.
                if (ref.watch(authProvider).isAdmin)
                  const SecurityAlertsPanel(),
                Expanded(
                  child: _buildUsersList(
                    users,
                    roles,
                    theme,
                    branchNamesAsync.value ?? {},
                  ),
                ),
              ],
            ),
            loading: () => Padding(
              padding: const EdgeInsets.all(16),
              child: ShimmerLoading.list(itemCount: 4),
            ),
            error: (e, _) => Center(child: Text('خطأ: $e')),
          ),
          loading: () => Padding(
            padding: const EdgeInsets.all(16),
            child: ShimmerLoading.list(itemCount: 4),
          ),
          error: (e, _) => Center(child: Text('خطأ: $e')),
        ),
      ),
    );
  }

  Widget _buildUsersList(
    List<UserWithRole> users,
    List<Role> roles,
    ThemeData theme,
    Map<int, List<String>> userBranchNames,
  ) {
    if (users.isEmpty) {
      return const EmptyStateWidget(
        icon: PhosphorIconsBold.users,
        message: 'لا توجد مستخدمين',
        description: 'أضف أول مستخدم للنظام',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: users.length,
      itemBuilder: (context, index) {
        final userWithRole = users[index];
        final user = userWithRole.user;
        final role = userWithRole.role;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          child: ExpansionTile(
            leading: CircleAvatar(
              backgroundColor: user.isActive
                  ? _getRoleColor(role?.name).withValues(alpha: 0.15)
                  : Colors.grey.withValues(alpha: 0.15),
              child: Icon(
                _getRoleIcon(role?.name),
                color: user.isActive ? _getRoleColor(role?.name) : Colors.grey,
              ),
            ),
            title: Row(
              children: [
                Text(
                  user.displayName,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: user.isActive ? null : Colors.grey,
                  ),
                ),
                const SizedBox(width: 8),
                if (user.isLocked)
                  const Icon(
                    PhosphorIconsBold.lock,
                    size: 16,
                    color: Colors.orange,
                  ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('@${user.username}'),
                Wrap(
                  spacing: 8,
                  children: [
                    if (role != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        margin: const EdgeInsets.only(top: 4),
                        decoration: BoxDecoration(
                          color: _getRoleColor(
                            role.name,
                          ).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          role.name,
                          style: TextStyle(
                            fontSize: 11,
                            color: _getRoleColor(role.name),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    if (!user.isActive)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        margin: const EdgeInsets.only(top: 4),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'معطل',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.error,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    // Branch badge
                    _buildBranchBadge(user.id, userBranchNames),
                  ],
                ),
              ],
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Role Assignment
                    const Text(
                      'تعيين الدور:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    // Spec 061 (D1-003): role dropdown disabled for the
                    // bootstrap admin — admin's role assignment is immutable.
                    Tooltip(
                      message: isBootstrapAdmin(user.id, username: user.username)
                          ? bootstrapAdminRoleGuardMessage
                          : '',
                      child: DropdownButtonFormField<int>(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(PhosphorIconsLight.shieldCheck),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        initialValue: user.roleId,
                        items: roles
                            .map(
                              (role) => DropdownMenuItem(
                                value: role.id,
                                child: Text(role.name),
                              ),
                            )
                            .toList(),
                        onChanged: isBootstrapAdmin(user.id,
                                username: user.username)
                            ? null
                            : (roleId) => _updateUserRole(user.id, roleId),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Default Screen
                    const Text(
                      'الشاشة الافتراضية:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(PhosphorIconsLight.monitor),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      initialValue: user.defaultScreen,
                      items: const [
                        DropdownMenuItem(
                          value: 'pos',
                          child: Text('البيع السريع'),
                        ),
                        DropdownMenuItem(
                          value: 'dashboard',
                          child: Text('لوحة القيادة'),
                        ),
                        DropdownMenuItem(
                          value: 'products',
                          child: Text('المنتجات'),
                        ),
                        DropdownMenuItem(
                          value: 'inventory',
                          child: Text('المخزون'),
                        ),
                      ],
                      onChanged: (screen) =>
                          _updateDefaultScreen(user.id, screen),
                    ),
                    const SizedBox(height: 16),

                    // Max Discount Percent
                    const Text(
                      'حد الخصم الأقصى (%):',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue:
                                user.maxDiscountPercent?.toStringAsFixed(0) ??
                                '',
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              prefixIcon: const Icon(
                                PhosphorIconsLight.percent,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              hintText: 'بلا حد',
                              suffixText: '%',
                              helperText: user.maxDiscountPercent != null
                                  ? 'الحد الحالي: ${user.maxDiscountPercent!.toStringAsFixed(0)}%'
                                  : 'لا يوجد حد - اتركه فارغاً لعدم التحديد',
                            ),
                            onFieldSubmitted: (val) =>
                                _updateMaxDiscount(user.id, val),
                          ),
                        ),
                        if (user.maxDiscountPercent != null)
                          IconButton(
                            icon: const Icon(
                              PhosphorIconsBold.x,
                              color: AppColors.error,
                              size: 18,
                            ),
                            tooltip: 'إزالة الحد',
                            onPressed: () => _updateMaxDiscount(user.id, ''),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Actions
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        // Issue 7 (Feature 018): edit display_name / username /
                        // MSR card. Other identity fields (role, branches,
                        // PIN, password) keep their dedicated buttons below.
                        ElevatedButton.icon(
                          onPressed: () => _showEditUserDialog(user),
                          icon: const Icon(PhosphorIconsBold.pencilSimple),
                          label: const Text('تعديل البيانات'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        // Toggle Active
                        ElevatedButton.icon(
                          onPressed: () => _toggleUserActive(user),
                          icon: Icon(
                            user.isActive
                                ? PhosphorIconsBold.prohibit
                                : PhosphorIconsBold.check,
                          ),
                          label: Text(user.isActive ? 'تعطيل' : 'تفعيل'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: user.isActive
                                ? Colors.orange
                                : AppColors.success,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        // Toggle Lock
                        ElevatedButton.icon(
                          onPressed: () async {
                            final confirmed = await AppConfirmDialog.show(
                              context,
                              title: user.isLocked ? 'فك قفل المستخدم' : 'قفل المستخدم',
                              message: user.isLocked
                                  ? 'هل أنت متأكد من فك قفل المستخدم ${user.displayName}؟'
                                  : 'هل أنت متأكد من قفل المستخدم ${user.displayName}؟ لن يتمكن من تسجيل الدخول.',
                              confirmLabel: user.isLocked ? 'فك القفل' : 'قفل',
                              icon: user.isLocked ? PhosphorIconsBold.lockOpen : PhosphorIconsBold.lock,
                              color: user.isLocked ? AppColors.info : Colors.orange,
                            );
                            if (confirmed) _toggleUserLock(user);
                          },
                          icon: Icon(
                            user.isLocked
                                ? PhosphorIconsBold.lockOpen
                                : PhosphorIconsBold.lock,
                          ),
                          label: Text(user.isLocked ? 'فك القفل' : 'قفل'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: user.isLocked
                                ? AppColors.info
                                : Colors.orange,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        // Reset Password
                        ElevatedButton.icon(
                          onPressed: () => _showResetPasswordDialog(user),
                          icon: const Icon(PhosphorIconsBold.key),
                          label: const Text('إعادة كلمة المرور'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.secondary,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        // Set PIN
                        ElevatedButton.icon(
                          onPressed: () => _showSetPinDialog(user),
                          icon: const Icon(PhosphorIconsBold.password),
                          label: Text(
                            user.pin != null ? 'تغيير PIN' : 'تعيين PIN',
                          ),
                        ),
                        // Delete User (soft delete)
                        if (user.id != 1)
                          ElevatedButton.icon(
                            onPressed: () => _deleteUser(user),
                            icon: const Icon(PhosphorIconsBold.trash),
                            label: const Text('حذف'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.error,
                              foregroundColor: Colors.white,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // N3: Branch & Warehouse Access
                    if (user.id != 1) ...[
                      const Text(
                        'صلاحيات الفروع والمخازن:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _showBranchAccessDialog(user),
                              icon: const Icon(PhosphorIconsBold.buildings, size: 16),
                              label: const Text('إدارة الفروع'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _showWarehouseAccessDialog(user),
                              icon: const Icon(PhosphorIconsBold.warehouse, size: 16),
                              label: const Text('إدارة المخازن'),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                        ),
                        child: const Row(
                          children: [
                            Icon(PhosphorIconsBold.shieldStar, color: AppColors.primary, size: 16),
                            SizedBox(width: 8),
                            Text('مدير النظام — وصول كامل لجميع الفروع والمخازن',
                              style: TextStyle(fontSize: 12, color: AppColors.primary)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showAddUserDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const AddUserDialog(),
    );

    if (result == true) {
      ref.invalidate(allUsersProvider);
      ref.invalidate(allUserBranchNamesProvider);
    }
  }

  Future<void> _showEditUserDialog(dynamic user) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => EditUserDialog(user: user),
    );
    if (result == true) {
      ref.invalidate(allUsersProvider);
      if (!mounted) return;
      AppToast.show(context, 'تم حفظ التعديلات', type: ToastType.success);
    }
  }

  // _addUser logic is now handled in AddUserDialog

  Future<void> _updateUserRole(int userId, int? roleId) async {
    if (roleId == null) return;
    // 063 (D1-005): dual-approval gate (settings-flag gated; OFF by
    // default = no dialog).
    final approved = await DualApprovalService.requireApprovalForOp(
      context,
      ref,
      operation: DualApprovalOperation.userRoleChange,
      details: 'تغيير دور المستخدم #$userId',
    );
    if (!approved) {
      if (mounted) {
        AppToast.show(context, 'الموافقة الثنائية مرفوضة — لم يتم تغيير الدور', type: ToastType.warning);
      }
      return;
    }
    // Route through interceptor in client mode
    final intercepted = await ClientWriteInterceptor.updateUser(userId, {
      'roleId': roleId,
    });
    if (!intercepted) {
      final authRepo = ref.read(authRepositoryProvider);
      await authRepo.assignRoleToUser(userId, roleId);
    }
    // #Forensic Log: Role change
    try {
      final auth = ref.read(authProvider);
      final logger = ref.read(activityLoggerProvider);
      await logger.logUserEdit(
        auth.user?.id ?? 0,
        auth.user?.displayName ?? '',
        'User#$userId',
        'تغيير الدور',
      );
    } catch (e) {
      debugPrint('[ActivityLog] Error: $e');
    }
    // Invalidate permission providers so UI reflects the new role immediately
    ref.invalidate(currentUserPermissionsProvider);
    ref.invalidate(userNavItemsProvider);
    ref.invalidate(userAllowedScreensProvider);

    if (!mounted) return;
    AppToast.show(context, 'تم تحديث الدور', type: ToastType.success);
  }

  Future<void> _updateDefaultScreen(int userId, String? screen) async {
    if (screen == null) return;
    // Route through interceptor in client mode
    final intercepted = await ClientWriteInterceptor.updateUser(userId, {
      'defaultScreen': screen,
    });
    if (!intercepted) {
      final authRepo = ref.read(authRepositoryProvider);
      // Get current user to preserve other info or use a dedicated method
      final userWithRole = await authRepo.getUserById(userId);
      if (userWithRole != null) {
        await authRepo.updateUserInfo(
          userId: userId,
          displayName: userWithRole.user.displayName,
          roleId: userWithRole.user.roleId,
          maxDiscountPercent: userWithRole.user.maxDiscountPercent,
          discountLimitIsPercent: userWithRole.user.discountLimitIsPercent,
          cardCode: userWithRole.user.cardCode,
          defaultScreen: screen,
        );
      }
    }
    // #Forensic Log: Default screen change
    try {
      final auth = ref.read(authProvider);
      final logger = ref.read(activityLoggerProvider);
      await logger.logUserEdit(
        auth.user?.id ?? 0,
        auth.user?.displayName ?? '',
        'User#$userId',
        'تغيير الشاشة الافتراضية',
        newValue: screen,
      );
    } catch (e) {
      debugPrint('[ActivityLog] Error: $e');
    }
    if (!mounted) return;
    AppToast.show(
      context,
      'تم تحديث الشاشة الافتراضية',
      type: ToastType.success,
    );
  }

  Future<void> _updateMaxDiscount(int userId, String value) async {
    final maxDiscount = value.isEmpty ? null : double.tryParse(value);

    if (value.isNotEmpty && maxDiscount == null) {
      AppToast.show(context, 'يرجى إدخال رقم صحيح', type: ToastType.error);
      return;
    }

    if (maxDiscount != null && (maxDiscount < 0 || maxDiscount > 100)) {
      AppToast.show(
        context,
        'يجب أن تكون النسبة بين 0 و 100',
        type: ToastType.error,
      );
      return;
    }

    // Route through interceptor in client mode
    final intercepted = await ClientWriteInterceptor.updateUser(userId, {
      'maxDiscountPercent': maxDiscount,
    });
    if (!intercepted) {
      final authRepo = ref.read(authRepositoryProvider);
      final userWithRole = await authRepo.getUserById(userId);
      if (userWithRole != null) {
        await authRepo.updateUserInfo(
          userId: userId,
          displayName: userWithRole.user.displayName,
          roleId: userWithRole.user.roleId,
          maxDiscountPercent: maxDiscount,
          discountLimitIsPercent: userWithRole.user.discountLimitIsPercent,
          cardCode: userWithRole.user.cardCode,
          defaultScreen: userWithRole.user.defaultScreen,
        );
      }
    }
    // #Forensic Log: Max discount change
    try {
      final auth = ref.read(authProvider);
      final logger = ref.read(activityLoggerProvider);
      await logger.logUserEdit(
        auth.user?.id ?? 0,
        auth.user?.displayName ?? '',
        'User#$userId',
        'تغيير حد الخصم',
        newValue: maxDiscount?.toStringAsFixed(0) ?? 'بدون حد',
      );
    } catch (e) {
      debugPrint('[ActivityLog] Error: $e');
    }
    if (!mounted) return;
    AppToast.show(
      context,
      maxDiscount != null
          ? 'تم تحديد حد الخصم: ${maxDiscount.toStringAsFixed(0)}%'
          : 'تم إزالة حد الخصم',
      type: ToastType.success,
    );
    // Refresh the list
    ref.invalidate(allUsersProvider);
  }

  Future<void> _toggleUserActive(User user) async {
    final newActive = !user.isActive;
    // Spec 061 (D1-003): refuse to deactivate the bootstrap admin row.
    if (isBootstrapAdmin(user.id, username: user.username) && !newActive) {
      AppToast.show(context, bootstrapAdminGuardMessage,
          type: ToastType.error);
      return;
    }
    // Route through interceptor in client mode
    final intercepted = await ClientWriteInterceptor.updateUser(user.id, {
      'isActive': newActive,
    });
    if (!intercepted) {
      final authRepo = ref.read(authRepositoryProvider);
      await authRepo.toggleUserActive(userId: user.id, isActive: newActive);
    }
    // #Forensic Log: User activate/deactivate
    try {
      final auth = ref.read(authProvider);
      final logger = ref.read(activityLoggerProvider);
      await logger.logUserToggleActive(
        auth.user?.id ?? 0,
        auth.user?.displayName ?? '',
        user.displayName,
        newActive,
      );
    } catch (e) {
      debugPrint('[ActivityLog] Error: $e');
    }
    if (!mounted) return;
    AppToast.show(
      context,
      user.isActive ? 'تم تعطيل المستخدم' : 'تم تفعيل المستخدم',
      type: ToastType.success,
    );
  }

  Future<void> _toggleUserLock(User user) async {
    final newLocked = !user.isLocked;
    // Spec 061 (D1-003): refuse to lock the bootstrap admin row.
    if (isBootstrapAdmin(user.id, username: user.username) && newLocked) {
      AppToast.show(context, bootstrapAdminGuardMessage,
          type: ToastType.error);
      return;
    }
    // Route through interceptor in client mode
    final intercepted = await ClientWriteInterceptor.updateUser(user.id, {
      'isLocked': newLocked,
    });
    if (!intercepted) {
      final authRepo = ref.read(authRepositoryProvider);
      await authRepo.setUserLocked(user.id, newLocked);
    }
    // #Forensic Log: User lock/unlock
    try {
      final auth = ref.read(authProvider);
      final logger = ref.read(activityLoggerProvider);
      await logger.logUserToggleLock(
        auth.user?.id ?? 0,
        auth.user?.displayName ?? '',
        user.displayName,
        newLocked,
      );
    } catch (e) {
      debugPrint('[ActivityLog] Error: $e');
    }
    if (!mounted) return;
    AppToast.show(
      context,
      user.isLocked ? 'تم فك قفل المستخدم' : 'تم قفل المستخدم',
      type: ToastType.success,
    );
  }

  Future<void> _deleteUser(User user) async {
    // Spec 061 (D1-003): refuse to delete the bootstrap admin row — block
    // BEFORE the confirmation dialog appears so the operator isn't even
    // invited to attempt it.
    if (isBootstrapAdmin(user.id, username: user.username)) {
      AppToast.show(context, bootstrapAdminGuardMessage,
          type: ToastType.error);
      return;
    }
    final confirmed = await AppConfirmDialog.show(
      context,
      title: 'حذف المستخدم',
      message: 'هل أنت متأكد من حذف المستخدم "${user.displayName}"؟\n'
          'سيتم تعطيل الحساب وقفله نهائياً.',
      confirmLabel: 'حذف',
      icon: PhosphorIconsBold.trash,
      color: AppColors.error,
    );
    if (!confirmed) return;

    // Soft delete: deactivate + lock
    final intercepted = await ClientWriteInterceptor.updateUser(user.id, {
      'isActive': false,
      'isLocked': true,
    });
    if (!intercepted) {
      final authRepo = ref.read(authRepositoryProvider);
      await authRepo.toggleUserActive(userId: user.id, isActive: false);
      await authRepo.setUserLocked(user.id, true);
    }
    // #Forensic Log: User delete
    try {
      final auth = ref.read(authProvider);
      final logger = ref.read(activityLoggerProvider);
      await logger.logUserToggleActive(
        auth.user?.id ?? 0,
        auth.user?.displayName ?? '',
        user.displayName,
        false,
      );
    } catch (e) {
      debugPrint('[ActivityLog] Error: $e');
    }
    if (!mounted) return;
    AppToast.show(context, 'تم حذف المستخدم', type: ToastType.success);
    ref.invalidate(allUsersProvider);
    ref.invalidate(allUserBranchNamesProvider);
  }

  Future<void> _showResetPasswordDialog(User user) async {
    await showDialog(
      context: context,
      builder: (context) => ResetPasswordDialog(user: user),
    );
  }

  Future<void> _showSetPinDialog(User user) async {
    await showDialog(
      context: context,
      builder: (context) => SetPinDialog(user: user),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // N3: BRANCH & WAREHOUSE ACCESS DIALOGS
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _showBranchAccessDialog(User user) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => BranchAccessDialog(user: user),
    );
    if (result == true) {
      ref.invalidate(allUserBranchNamesProvider);
    }
  }

  Future<void> _showWarehouseAccessDialog(User user) async {
    await showDialog(
      context: context,
      builder: (context) => WarehouseAccessDialog(user: user),
    );
  }

  Widget _buildBranchBadge(int userId, Map<int, List<String>> userBranchNames) {
    final branches = userBranchNames[userId];
    if (branches == null) return const SizedBox.shrink();

    final String label;
    if (branches.isEmpty) {
      // Empty list = full access (admin/system role)
      label = 'كل الفروع';
    } else {
      label = branches.join('، ');
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: Colors.teal.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(PhosphorIconsBold.buildings, size: 11, color: Colors.teal),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.teal,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Color _getRoleColor(String? roleName) {
    if (roleName == 'مدير النظام') return Colors.purple;
    if (roleName == 'مدير') return Colors.blue;
    if (roleName == 'كاشير') return Colors.green;
    return Colors.grey;
  }

  IconData _getRoleIcon(String? roleName) {
    if (roleName == 'مدير النظام') return PhosphorIconsBold.shieldCheck;
    if (roleName == 'مدير') return PhosphorIconsBold.userGear;
    if (roleName == 'كاشير') return PhosphorIconsBold.cashRegister;
    return PhosphorIconsBold.user;
  }
}
