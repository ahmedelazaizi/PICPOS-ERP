import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../core/permissions/permission_codes.dart';
import '../../../../services/network_service.dart';
import '../../../../services/client_write_interceptor.dart';
import '../../../../data/providers/providers.dart';
import '../../../widgets/dialogs/app_form_dialog.dart';
import 'package:ural_erp/l10n/app_localizations.dart';

/// Issue 7 (Feature 018): edit an existing user's identity (display_name +
/// username + MSR card code). The role / branch / discount editors live in
/// users_management_screen and stay there — this dialog is only for the
/// fields that previously had no UI to update.
///
/// The dialog routes through [ClientWriteInterceptor.updateUser] when in
/// client mode (matching the `_updateUserRole` / `_updateDefaultScreen`
/// pattern in users_management_screen) and falls back to the local
/// [authRepositoryProvider] in standalone/server mode. Password edits stay
/// in the dedicated reset-password dialog so that flow keeps its own audit
/// log entry and salt regeneration.
class EditUserDialog extends AppFormDialog<bool> {
  final User user;
  const EditUserDialog({super.key, required this.user});

  @override
  AppFormDialogState<bool, EditUserDialog> createState() =>
      _EditUserDialogState();
}

class _EditUserDialogState extends AppFormDialogState<bool, EditUserDialog> {
  late final nameController = registerController(widget.user.displayName);
  late final usernameController = registerController(widget.user.username);
  late final cardCodeController = registerController(widget.user.cardCode ?? '');

  @override
  String get dialogTitle => 'تعديل بيانات المستخدم';

  @override
  IconData get dialogIcon => PhosphorIconsBold.userGear;

  @override
  Widget buildFormContent(BuildContext context, AppLocalizations localizations) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'الاسم الكامل *',
            prefixIcon: Icon(PhosphorIconsLight.user),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: usernameController,
          decoration: const InputDecoration(
            labelText: 'اسم المستخدم *',
            prefixIcon: Icon(PhosphorIconsLight.at),
            helperText: 'تغييره يؤثر على تسجيل الدخول للمستخدم',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: cardCodeController,
          decoration: const InputDecoration(
            labelText: 'كود كارت MSR (اختياري)',
            hintText: 'مرر الكارت أو اكتب الكود يدوياً',
            prefixIcon: Icon(PhosphorIconsLight.identificationCard),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
          ),
          child: const Row(
            children: [
              Icon(PhosphorIconsBold.info, size: 14, color: Colors.amber),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'لتغيير كلمة المرور أو الدور أو الفروع استخدم الأزرار '
                  'المخصصة في صف المستخدم.',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Future<bool> onSave() async {
    final name = nameController.text.trim();
    final username = usernameController.text.trim();
    final cardCode = cardCodeController.text.trim().isEmpty
        ? null
        : cardCodeController.text.trim();

    if (name.isEmpty || username.isEmpty) {
      throw 'يجب ملء الاسم الكامل واسم المستخدم';
    }

    final authRepo = ref.read(authRepositoryProvider);

    // Mirror the cross-branch gate used by AddUserDialog: on a paired client,
    // editing identity propagates to the server's authoritative users row, so
    // require the same permission as creating.
    if (NetworkService.instance.isClient) {
      final actorId = ref.read(authProvider).user?.id;
      final allowed = actorId != null &&
          await authRepo.userHasPermission(
            actorId,
            PermissionCodes.usersManageCrossBranch,
          );
      if (!allowed) {
        throw 'لا تملك صلاحية تعديل المستخدمين من جهاز فرع. '
            'يرجى التعديل من المقر الرئيسى أو طلب تفعيل صلاحية '
            '"إدارة المستخدمين عبر-فروع".';
      }
    }

    // Try the interceptor first (client mode → POST to server). Returns false
    // when not in client mode so the local fallback runs.
    final intercepted = await ClientWriteInterceptor.updateUser(
      widget.user.id,
      {
        'displayName': name,
        'username': username,
        'cardCode': cardCode,
      },
    );

    if (!intercepted) {
      await authRepo.updateUserInfo(
        userId: widget.user.id,
        displayName: name,
        roleId: widget.user.roleId,
        maxDiscountPercent: widget.user.maxDiscountPercent,
        discountLimitIsPercent: widget.user.discountLimitIsPercent,
        cardCode: cardCode,
        defaultScreen: widget.user.defaultScreen,
        username: username,
      );
    }

    // Forensic log entry — best-effort, mirrors the pattern in AddUserDialog.
    try {
      final auth = ref.read(authProvider);
      final logger = ref.read(activityLoggerProvider);
      await logger.logUserEdit(
        auth.user?.id ?? 0,
        auth.user?.displayName ?? '',
        widget.user.username,
        'تعديل البيانات الشخصية',
      );
    } catch (e) {
      debugPrint('[ActivityLog] Error: $e');
    }

    return true;
  }
}
