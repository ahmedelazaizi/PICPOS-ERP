import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../services/security_service.dart';
import '../../../../data/providers/providers.dart';
import '../../../../services/client_write_interceptor.dart';
import '../../../widgets/dialogs/app_form_dialog.dart';
import 'package:ural_erp/l10n/app_localizations.dart';

class ResetPasswordDialog extends AppFormDialog<bool> {
  final User user;

  const ResetPasswordDialog({super.key, required this.user});

  @override
  AppFormDialogState<bool, ResetPasswordDialog> createState() =>
      _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends AppFormDialogState<bool, ResetPasswordDialog> {
  late final passwordController = registerController();
  bool forcePasswordChange = true;

  @override
  String get dialogTitle => 'إعادة تعيين كلمة مرور ${widget.user.displayName}';

  @override
  IconData get dialogIcon => PhosphorIconsBold.key;

  @override
  String? get dialogSubtitle => 'كلمةٌ جديدةٌ تسري من أوّل تسجيل دخول';

  @override
  String? get dialogSaveLabel => 'حفظ كلمة المرور';

  @override
  Widget buildFormContent(BuildContext context, AppLocalizations localizations) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: passwordController,
          obscureText: true,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'كلمة المرور الجديدة',
            prefixIcon: Icon(PhosphorIconsLight.lock),
          ),
        ),
        if (passwordController.text.isNotEmpty) ...[
          const SizedBox(height: 10),
          _buildPasswordStrength(),
        ],
        const SizedBox(height: 12),
        CheckboxListTile(
          title: const Text('فرض تغيير كلمة المرور عند الدخول القادم'),
          subtitle: const Text('سيُطلب من المستخدم تغيير كلمة المرور فور تسجيل دخوله التالي'),
          value: forcePasswordChange,
          onChanged: (v) => setState(() => forcePasswordChange = v ?? true),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: AppColors.primary,
        ),
      ],
    );
  }

  Widget _buildPasswordStrength() {
    final result = SecurityService.validatePassword(passwordController.text);
    final strengthLabel = SecurityService.getPasswordStrengthLabel(result.strength);
    final strengthColor = result.strength < 30
        ? Colors.red
        : result.strength < 50
            ? Colors.orange
            : result.strength < 70
                ? Colors.amber
                : result.strength < 90
                    ? Colors.lightGreen
                    : Colors.green;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: result.strength / 100,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation(strengthColor),
                  minHeight: 6,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              strengthLabel,
              style: TextStyle(
                fontSize: 11,
                color: strengthColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        if (!result.isValid) ...[
          const SizedBox(height: 6),
          ...result.errors.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: [
                    const Icon(Icons.close, size: 14, color: Colors.red),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(e, style: const TextStyle(fontSize: 11, color: Colors.red)),
                    ),
                  ],
                ),
              )),
        ],
      ],
    );
  }

  @override
  Future<bool> onSave() async {
    final password = passwordController.text;

    if (password.isEmpty) {
      throw 'يرجى إدخال كلمة مرور جديدة';
    }

    // Password strength indicator is shown as a guide only — no enforcement
    // final passwordValidation = SecurityService.validatePassword(password);

    final authRepo = ref.read(authRepositoryProvider);
    
    // Route through interceptor in client mode
    final intercepted = await ClientWriteInterceptor.updateUser(widget.user.id, {
      'password': password,
    });
    
    if (!intercepted) {
      await authRepo.updateUserPassword(
        userId: widget.user.id,
        newPassword: password,
      );

      // If force change is requested, we need to set the flag
      // (Because updateUserPassword clears it by default)
      if (forcePasswordChange) {
        await authRepo.updateUserInfo(
          userId: widget.user.id,
          displayName: widget.user.displayName,
          roleId: widget.user.roleId,
          maxDiscountPercent: widget.user.maxDiscountPercent,
          discountLimitIsPercent: widget.user.discountLimitIsPercent,
          cardCode: widget.user.cardCode,
          defaultScreen: widget.user.defaultScreen,
          forcePasswordChange: true,
        );
      }
    }

    // #Forensic Log: Password reset
    try {
      final auth = ref.read(authProvider);
      final logger = ref.read(activityLoggerProvider);
      await logger.logUserEdit(
        auth.user?.id ?? 0,
        auth.user?.displayName ?? '',
        widget.user.displayName,
        'إعادة تعيين كلمة المرور',
      );
    } catch (e) {
      debugPrint('[ActivityLog] Error: $e');
    }

    return true;
  }
}
