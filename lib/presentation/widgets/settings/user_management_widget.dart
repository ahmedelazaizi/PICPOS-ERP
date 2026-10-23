import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:picpos_erp/core/widgets/app_toast.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';

import '../../../core/design_system/typography.dart';
import '../../../data/providers/providers.dart';
import '../../shared_widgets/default_screen_dropdown.dart';
import '../../../services/client_write_interceptor.dart';
import 'package:picpos_erp/core/constants/app_constants.dart';

/// User Management Dialog - Restored with full logic from original screen
class UserManagementWidget extends ConsumerStatefulWidget {
  const UserManagementWidget({super.key});

  @override
  ConsumerState<UserManagementWidget> createState() =>
      _UserManagementWidgetState();
}

class _UserManagementWidgetState extends ConsumerState<UserManagementWidget> {
  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(allUsersProvider);
    final rolesAsync = ref.watch(allRolesProvider);

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Column(
        children: [
          Row(
            children: [
               Text(tr('قائمة المستخدمين'), style: AppTypography.h3),
              const Spacer(),
              rolesAsync.when(
                data: (roles) => ElevatedButton.icon(
                  onPressed: () => _showAddUserDialog(roles),
                  icon: const Icon(PhosphorIconsBold.plus, size: 16),
                  label:  Text(tr('إضافة')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                  ),
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: usersAsync.when(
              data: (list) {
                if (list.isEmpty) {
                  return  Center(child: Text(tr('لا يوجد مستخدمين')));
                }
                return ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final userWithRole = list[index];
                    final u = userWithRole.user;
                    final role = userWithRole.role;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _getRoleColor(
                            role?.name,
                          ).withValues(alpha: 0.1),
                          child: Icon(
                            _getRoleIcon(role?.name),
                            color: _getRoleColor(role?.name),
                          ),
                        ),
                        title: Text(
                          u.displayName,
                          style: AppTypography.bodyLarge.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Row(
                          children: [
                            Text(u.username, style: AppTypography.bodySmall),
                            const SizedBox(width: 8),
                            _buildBadge(
                              role?.name ?? tr('بدون دور'),
                              _getRoleColor(role?.name),
                            ),
                            if (u.maxDiscountPercent != null) ...[
                              const SizedBox(width: 4),
                              _buildBadge(
                                tr('خصم {p0}{p1}', {'p0': u.maxDiscountPercent!.toStringAsFixed(0), 'p1': u.discountLimitIsPercent ? '%' : ' ${AppConstants.currencySymbol}'}),
                                AppColors.warning,
                              ),
                            ],
                            if (!u.isActive) ...[
                              const SizedBox(width: 4),
                              _buildBadge(tr('غير نشط'), AppColors.error),
                            ],
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                PhosphorIconsBold.pencil,
                                size: 18,
                              ),
                              color: AppColors.primary,
                              onPressed: () => rolesAsync.whenData(
                                (roles) =>
                                    _showEditUserDialog(userWithRole, roles),
                              ),
                              tooltip: tr('تعديل'),
                            ),
                            IconButton(
                              icon: const Icon(PhosphorIconsBold.key, size: 18),
                              color: AppColors.warning,
                              onPressed: () => _showChangePasswordDialog(u),
                              tooltip: tr('كلمة المرور'),
                            ),
                            if (u.username != 'admin')
                              IconButton(
                                icon: Icon(
                                  u.isActive
                                      ? PhosphorIconsBold.userMinus
                                      : PhosphorIconsBold.userPlus,
                                  size: 18,
                                ),
                                color: u.isActive
                                    ? AppColors.error
                                    : AppColors.success,
                                onPressed: () => _toggleUserStatus(u),
                                tooltip: u.isActive ? tr('تعطيل') : tr('تفعيل'),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(tr('خطأ: {e}', {'e': e}))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  void _showAddUserDialog(List<Role> roles) {
    final usernameController = TextEditingController();
    final displayNameController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    final maxDiscountController = TextEditingController();
    final cardCodeController = TextEditingController();
    bool isPercent = true;
    String selectedScreen = 'pos'; // #10: Default screen
    Role? selectedRole = roles.firstWhere(
      (r) => r.name == 'كاشير',
      orElse: () => roles.first,
    );
    bool saving = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: ui.TextDirection.rtl,
          child: AlertDialog(
            title:  Row(
              children: [
                const Icon(PhosphorIconsBold.userPlus, color: AppColors.success),
                const SizedBox(width: 8),
                Text(tr('إضافة مستخدم جديد')),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: usernameController,
                      decoration:  InputDecoration(
                        labelText: tr('اسم المستخدم *'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: displayNameController,
                      decoration:  InputDecoration(
                        labelText: tr('الاسم الظاهر *'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passwordController,
                      decoration:  InputDecoration(
                        labelText: tr('كلمة المرور *'),
                      ),
                      obscureText: true,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmPasswordController,
                      decoration:  InputDecoration(
                        labelText: tr('تأكيد كلمة المرور *'),
                      ),
                      obscureText: true,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<Role>(
                      initialValue: selectedRole,
                      decoration:  InputDecoration(
                        labelText: tr('الدور / الصلاحية'),
                      ),
                      items: roles
                          .map(
                            (r) =>
                                DropdownMenuItem(value: r, child: Text(trData(r.name))),
                          )
                          .toList(),
                      onChanged: (v) => setDialogState(() => selectedRole = v),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: maxDiscountController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: tr('حد الخصم الأقصى'),
                              hintText: tr('اتركه فارغ = بلا حد'),
                              suffixText: isPercent
                                  ? '%'
                                  : AppConstants.currencySymbol,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ToggleButtons(
                          isSelected: [isPercent, !isPercent],
                          onPressed: (i) =>
                              setDialogState(() => isPercent = i == 0),
                          borderRadius: BorderRadius.circular(8),
                          selectedColor: Colors.white,
                          fillColor: AppColors.primary,
                          constraints: const BoxConstraints(
                            minHeight: 36,
                            minWidth: 44,
                          ),
                          children: [
                            const Text('%'),
                            Text(AppConstants.currencySymbol),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: cardCodeController,
                      decoration:  InputDecoration(
                        labelText: tr('كود كارت MSR'),
                        hintText: tr('مرر الكارت للقراءة التلقائية'),
                        prefixIcon: const Icon(PhosphorIconsBold.creditCard),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // #10: Default screen selector
                    DefaultScreenDropdown(
                      roleId: selectedRole?.id,
                      value: selectedScreen,
                      decoration:  InputDecoration(
                        labelText: tr('الشاشة الافتراضية'),
                        prefixIcon: const Icon(PhosphorIconsBold.monitor, size: 18),
                      ),
                      onChanged: (v) => setDialogState(() => selectedScreen = v ?? selectedScreen),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child:  Text(tr('إلغاء')),
              ),
              ElevatedButton(
                onPressed: saving ? null : () async {
                  if (usernameController.text.isEmpty ||
                      passwordController.text.isEmpty) {
                    _showError(tr('يرجى ملء الحقول المطلوبة'));
                    return;
                  }
                  if (passwordController.text !=
                      confirmPasswordController.text) {
                    _showError(tr('كلمات المرور غير متطابقة'));
                    return;
                  }
                  if (selectedRole == null) {
                    _showError(tr('يرجى اختيار دور للمستخدم'));
                    return;
                  }
                  setDialogState(() => saving = true);
                  final authRepo = ref.read(authRepositoryProvider);
                  try {
                    final discountLimit = double.tryParse(
                      maxDiscountController.text,
                    );
                    await authRepo.createUser(
                      username: usernameController.text,
                      password: passwordController.text,
                      displayName: displayNameController.text,
                      roleId: selectedRole!.id,
                      maxDiscountPercent: discountLimit,
                      discountLimitIsPercent: isPercent,
                      cardCode: cardCodeController.text.isNotEmpty
                          ? cardCodeController.text
                          : null,
                      defaultScreen: selectedScreen,
                    );
                    // ISS-15: Audit log for user creation
                    final auth = ref.read(authProvider);
                    await ref.read(auditRepositoryProvider).logActivity(
                      userId: auth.user?.id,
                      userName: auth.user?.displayName ?? tr('مجهول'),
                      action: 'CREATE_USER',
                      entityType: 'user',
                      description: tr('إنشاء مستخدم جديد: {p0} بدور {p1}', {'p0': usernameController.text, 'p1': selectedRole!.name}),
                    );
                    if (context.mounted) {
                      Navigator.pop(context);
                      AppToast.show(
                        context,
                        tr('تم الإضافة بنجاح'),
                        type: ToastType.success,
                      );
                    }
                  } catch (e) {
                    setDialogState(() => saving = false);
                    _showError(tr('خطأ: {e}', {'e': e}));
                  }
                },
                child: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    :  Text(tr('حفظ')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditUserDialog(UserWithRole userWithRole, List<Role> roles) {
    final user = userWithRole.user;
    final displayNameController = TextEditingController(text: user.displayName);
    final maxDiscountController = TextEditingController(
      text: user.maxDiscountPercent?.toStringAsFixed(0) ?? '',
    );
    final cardCodeController = TextEditingController(text: user.cardCode ?? '');
    bool isPercent = user.discountLimitIsPercent;
    String selectedScreen = user.defaultScreen; // #10
    Role? selectedRole = roles.firstWhere(
      (r) => r.id == user.roleId,
      orElse: () => roles.first,
    );
    bool saving = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: ui.TextDirection.rtl,
          child: AlertDialog(
            title: Text(tr('تعديل: {p0}', {'p0': user.username})),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: displayNameController,
                  decoration:  InputDecoration(
                    labelText: tr('الاسم الظاهر *'),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<Role>(
                  initialValue: selectedRole,
                  decoration:  InputDecoration(
                    labelText: tr('الدور / الصلاحية'),
                  ),
                  items: roles
                      .map(
                        (r) => DropdownMenuItem(value: r, child: Text(trData(r.name))),
                      )
                      .toList(),
                  onChanged: (v) => setDialogState(() => selectedRole = v),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: maxDiscountController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: tr('حد الخصم الأقصى'),
                          hintText: tr('اتركه فارغ = بلا حد'),
                          suffixText: isPercent ? '%' : AppConstants.currencySymbol,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ToggleButtons(
                      isSelected: [isPercent, !isPercent],
                      onPressed: (i) =>
                          setDialogState(() => isPercent = i == 0),
                      borderRadius: BorderRadius.circular(8),
                      selectedColor: Colors.white,
                      fillColor: AppColors.primary,
                      constraints: const BoxConstraints(
                        minHeight: 36,
                        minWidth: 44,
                      ),
                      children: [const Text('%'), Text(AppConstants.currencySymbol)],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: cardCodeController,
                  decoration:  InputDecoration(
                    labelText: tr('كود كارت MSR'),
                    hintText: tr('مرر الكارت للقراءة التلقائية'),
                    prefixIcon: const Icon(PhosphorIconsBold.creditCard),
                  ),
                ),
                const SizedBox(height: 12),
                // #10: Default screen selector
                DefaultScreenDropdown(
                  roleId: selectedRole?.id,
                  value: selectedScreen,
                  decoration:  InputDecoration(
                    labelText: tr('الشاشة الافتراضية'),
                    prefixIcon: const Icon(PhosphorIconsBold.monitor, size: 18),
                  ),
                  onChanged: (v) => setDialogState(() => selectedScreen = v ?? selectedScreen),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child:  Text(tr('إلغاء')),
              ),
              ElevatedButton(
                onPressed: saving ? null : () async {
                  setDialogState(() => saving = true);
                  try {
                    final authRepo = ref.read(authRepositoryProvider);
                    final discountLimit = double.tryParse(
                      maxDiscountController.text,
                    );
                    // CRITICAL: route the save through `ClientWriteInterceptor`
                    // in client mode. The previous direct `authRepo.updateUserInfo`
                    // call wrote ONLY to the local SQLite — the server kept its
                    // stale copy, and the next user-table fullSync overwrote
                    // the local `defaultScreen` / `roleId` / etc. back. That's
                    // why the "default screen per user" setting kept
                    // appearing to regress even after saves: the save
                    // worked for a few minutes then got clobbered.
                    //
                    // The pattern mirrors every other mutation in
                    // `users_management_screen.dart`: try the interceptor
                    // first (which queues to server), fall back to a
                    // direct local update only when not in client mode.
                    final intercepted = await ClientWriteInterceptor.updateUser(
                      user.id,
                      {
                        'displayName': displayNameController.text,
                        'roleId': selectedRole?.id,
                        'maxDiscountPercent': discountLimit,
                        'discountLimitIsPercent': isPercent,
                        'cardCode': cardCodeController.text.isNotEmpty
                            ? cardCodeController.text
                            : null,
                        'defaultScreen': selectedScreen,
                      },
                    );
                    if (!intercepted) {
                      await authRepo.updateUserInfo(
                        userId: user.id,
                        displayName: displayNameController.text,
                        roleId: selectedRole?.id,
                        maxDiscountPercent: discountLimit,
                        discountLimitIsPercent: isPercent,
                        cardCode: cardCodeController.text.isNotEmpty
                            ? cardCodeController.text
                            : null,
                        defaultScreen: selectedScreen,
                      );
                    }
                    // ISS-15: Audit log for user edit
                    final auth = ref.read(authProvider);
                    await ref.read(auditRepositoryProvider).logActivity(
                      userId: auth.user?.id,
                      userName: auth.user?.displayName ?? tr('مجهول'),
                      action: 'UPDATE_USER',
                      entityType: 'user',
                      entityId: user.id,
                      description: tr('تعديل بيانات المستخدم: {p0}', {'p0': user.username}),
                      oldValue: 'displayName=${user.displayName}, roleId=${user.roleId}',
                      newValue: 'displayName=${displayNameController.text}, roleId=${selectedRole?.id}',
                    );
                    if (context.mounted) Navigator.pop(context);
                  } catch (e) {
                    setDialogState(() => saving = false);
                    _showError(tr('خطأ: {e}', {'e': e}));
                  }
                },
                child: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    :  Text(tr('حفظ')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showChangePasswordDialog(User user) {
    final pass = TextEditingController();
    bool saving = false;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: ui.TextDirection.rtl,
          child: AlertDialog(
            title: Text(tr('تغيير كلمة المرور: {p0}', {'p0': user.username})),
            content: TextField(
              controller: pass,
              obscureText: true,
              decoration:  InputDecoration(labelText: tr('كلمة المرور الجديدة')),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child:  Text(tr('إلغاء')),
              ),
              ElevatedButton(
                onPressed: saving ? null : () async {
                  if (pass.text.isEmpty) {
                    _showError(tr('يرجى إدخال كلمة المرور'));
                    return;
                  }
                  setDialogState(() => saving = true);
                  final authRepo = ref.read(authRepositoryProvider);
                  try {
                    await authRepo.updateUserPassword(
                      userId: user.id,
                      newPassword: pass.text,
                    );
                    // ISS-15: Audit log for password change
                    final auth = ref.read(authProvider);
                    await ref.read(auditRepositoryProvider).logActivity(
                      userId: auth.user?.id,
                      userName: auth.user?.displayName ?? tr('مجهول'),
                      action: 'CHANGE_PASSWORD',
                      entityType: 'user',
                      entityId: user.id,
                      description: tr('تغيير كلمة مرور المستخدم: {p0}', {'p0': user.username}),
                    );
                    if (context.mounted) {
                      Navigator.pop(context);
                      AppToast.show(
                        context,
                        tr('تم تغيير كلمة المرور بنجاح'),
                        type: ToastType.success,
                      );
                    }
                  } catch (e) {
                    setDialogState(() => saving = false);
                    _showError('$e');
                  }
                },
                child: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    :  Text(tr('تغيير')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleUserStatus(User user) async {
    final authRepo = ref.read(authRepositoryProvider);
    await authRepo.toggleUserActive(userId: user.id, isActive: !user.isActive);
    // ISS-15: Audit log for user status toggle
    final auth = ref.read(authProvider);
    await ref.read(auditRepositoryProvider).logActivity(
      userId: auth.user?.id,
      userName: auth.user?.displayName ?? tr('مجهول'),
      action: user.isActive ? 'DEACTIVATE_USER' : 'ACTIVATE_USER',
      entityType: 'user',
      entityId: user.id,
      description: tr('{p0} المستخدم: {p1}', {'p0': user.isActive ? tr('تعطيل') : tr('تفعيل'), 'p1': user.username}),
    );
  }

  void _showError(String msg) {
    AppToast.show(context, msg, type: ToastType.error);
  }

  Color _getRoleColor(String? roleName) {
    if (roleName == 'مدير النظام') return AppColors.error;
    if (roleName == 'كاشير') return AppColors.info;
    if (roleName == 'مخزني') return AppColors.secondary;
    if (roleName == 'محاسب') return AppColors.warning;
    return AppColors.primary;
  }

  IconData _getRoleIcon(String? roleName) {
    if (roleName == 'مدير النظام') return PhosphorIconsBold.crown;
    if (roleName == 'كاشير') return PhosphorIconsBold.creditCard;
    if (roleName == 'مخزني') return PhosphorIconsBold.package;
    if (roleName == 'محاسب') return PhosphorIconsBold.calculator;
    return PhosphorIconsBold.user;
  }
}

/// Helper method to show the user management dialog
void showUsersManagementDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title:  Row(
        children: [
          const Icon(PhosphorIconsBold.users, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(tr('إدارة المستخدمين')),
        ],
      ),
      content: const SizedBox(
        width: 650,
        height: 500,
        child: UserManagementWidget(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child:  Text(tr('إغلاق')),
        ),
      ],
    ),
  );
}
