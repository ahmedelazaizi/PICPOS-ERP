import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/auth/password_policy.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';

/// Dialog to force user to change their password on first login or after reset.
///
/// [viaMain] (client/mirror, plan P2): the change is made ON THE MAIN SYSTEM -
/// online only, never queued - proving identity with [currentPassword] or
/// [cardCode] (kept in memory, never persisted). [onPasswordChanged] hands the
/// new password to the caller so it can complete the login with it.
class ForceChangePasswordDialog extends ConsumerStatefulWidget {
  final int? userId;
  final String username;
  final bool viaMain;
  final String? currentPassword;
  final String? cardCode;
  final ValueSetter<String>? onPasswordChanged;

  const ForceChangePasswordDialog({
    super.key,
    this.userId,
    required this.username,
    this.viaMain = false,
    this.currentPassword,
    this.cardCode,
    this.onPasswordChanged,
  });

  @override
  ConsumerState<ForceChangePasswordDialog> createState() => _ForceChangePasswordDialogState();
}

class _ForceChangePasswordDialogState extends ConsumerState<ForceChangePasswordDialog> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (_passwordController.text.isEmpty) {
      setState(() => _errorMessage = tr('يرجى إدخال كلمة المرور الجديدة'));
      return;
    }

    if (_passwordController.text.length < kMinPasswordLength) {
      setState(() => _errorMessage = tr(
          'يجب أن تكون كلمة المرور {p0} خانات على الأقل.', {'p0': kMinPasswordLength}));
      return;
    }

    if (_passwordController.text != _confirmController.text) {
      setState(() => _errorMessage = tr('كلمات المرور غير متطابقة'));
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authRepo = ref.read(authRepositoryProvider);
      if (widget.viaMain) {
        await authRepo.changeOwnPassword(
          username: widget.username,
          currentPassword: widget.currentPassword,
          cardCode: widget.cardCode,
          newPassword: _passwordController.text,
        );
      } else {
        await authRepo.updateUserPassword(
          userId: widget.userId!,
          newPassword: _passwordController.text,
        );
      }
      widget.onPasswordChanged?.call(_passwordController.text);

      if (!mounted) return;
      AppToast.show(context, tr('تم تغيير كلمة المرور بنجاح'), type: ToastType.success);
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _errorMessage =
          e is StateError ? e.message : e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title:  Row(
          children: [
            const Icon(PhosphorIconsBold.shieldWarning, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(tr('تغيير كلمة المرور')),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
               Text(
                tr('يجب عليك تغيير كلمة المرور الافتراضية للمتابعة.'),
                style: const TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 24),
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(PhosphorIconsBold.warning, color: AppColors.error, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: AppColors.error, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: tr('كلمة المرور الجديدة'),
                  prefixIcon: const Icon(PhosphorIconsBold.lock),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? PhosphorIconsBold.eye : PhosphorIconsBold.eyeSlash),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _confirmController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: tr('تأكيد كلمة المرور'),
                  prefixIcon: const Icon(PhosphorIconsBold.lockKey),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onSubmitted: (_) => _changePassword(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child:  Text(tr('إلغاء')),
          ),
          ElevatedButton(
            onPressed: _isLoading ? null : _changePassword,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: _isLoading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                :  Text(tr('تغيير كلمة المرور')),
          ),
        ],
      ),
    );
  }
}
