import 'package:ural_erp/core/i18n/tr.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../../services/login_rate_limiter.dart';
import '../widgets/pos_notification_handler.dart';

/// Mixin to handle POS admin credential validation for a SINGLE action.
///
/// The dialog validates username + password and, on success, pops `true`
/// to the caller. It deliberately does NOT elevate the session or start
/// any "admin window" timer — per per-action-elevation plan, every
/// protected tap must re-prompt.
mixin PosCredentialHandler {
  /// Request admin credentials for a sensitive action (e.g. price override).
  /// Returns true iff an admin/manager authenticated; false on cancel or
  /// failure. The caller is responsible for running the single action.
  Future<bool> requestAdminCredentials({
    required BuildContext context,
    required WidgetRef ref,
  }) async {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title:  Row(
            children: [
              const Icon(PhosphorIconsBold.shieldStar, color: AppColors.warning),
              const SizedBox(width: 8),
              Text(tr('تسجيل دخول المدير')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
               Text(tr('أدخل بيانات حساب المدير للحصول على صلاحيات')),
              const SizedBox(height: 16),
              TextField(
                controller: usernameController,
                decoration: InputDecoration(
                  labelText: tr('اسم المستخدم'),
                  prefixIcon: const Icon(PhosphorIconsBold.user),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: tr('كلمة المرور'),
                  prefixIcon: const Icon(PhosphorIconsBold.lock),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onSubmitted: (_) => validateCredentials(
                  ctx,
                  ref,
                  usernameController.text,
                  passwordController.text,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:  Text(tr('إلغاء')),
            ),
            FilledButton(
              onPressed: () => validateCredentials(
                ctx,
                ref,
                usernameController.text,
                passwordController.text,
              ),
              child:  Text(tr('تأكيد')),
            ),
          ],
        ),
      ),
    );

    return result ?? false;
  }

  Future<void> validateCredentials(
    BuildContext ctx,
    WidgetRef ref,
    String username,
    String password,
  ) async {
    if (username.isEmpty || password.isEmpty) {
      showPosToast(
        ctx,
        ref,
        tr('يرجى إدخال المستخدم وكلمة المرور'),
        type: PosNotificationType.error,
      );
      return;
    }

    // Rate limiting check
    final lockoutRemaining = LoginRateLimiter.getLockoutRemaining(username);
    if (lockoutRemaining != null) {
      final minutes = lockoutRemaining.inMinutes;
      final seconds = lockoutRemaining.inSeconds % 60;
      if (ctx.mounted) {
        showPosToast(
          ctx,
          ref,
          tr('محاولات كثيرة — انتظر {minutes}:{p0} دقيقة', {'minutes': minutes, 'p0': seconds.toString().padLeft(2, '0')}),
          type: PosNotificationType.error,
        );
      }
      return;
    }

    try {
      final authRepo = ref.read(authRepositoryProvider);
      final userWithRole = await authRepo.authenticateUser(username, password);

      if (userWithRole != null) {
        final roleName = userWithRole.role?.name.toLowerCase() ?? '';
        final isAdminOrManager =
            roleName.contains('admin') ||
            roleName.contains('مدير') ||
            roleName.contains('مشرف') ||
            roleName.contains('manager');

        if (isAdminOrManager) {
          LoginRateLimiter.recordSuccess(username);

          // Log per-action admin approval for forensic trail (no session
          // elevation is performed — this authorizes exactly ONE caller).
          final auth = ref.read(authProvider);
          final activityLogRepo = ref.read(activityLogRepositoryProvider);
          await activityLogRepo.logActivity(
            userId: auth.user?.id,
            userName: auth.user?.displayName ?? tr('مستخدم'),
            action: 'admin_per_action_approval',
            entityType: 'session',
            description:
                tr('موافقة المدير {p0} على إجراء واحد', {'p0': userWithRole.user.displayName}),
          );

          if (ctx.mounted) Navigator.pop(ctx, true);
        } else {
          if (ctx.mounted) {
            showPosToast(
              ctx,
              ref,
              tr('هذا المستخدم ليس لديه صلاحية المدير'),
              type: PosNotificationType.error,
            );
          }
        }
      } else {
        final remaining = LoginRateLimiter.recordFailure(username);
        if (ctx.mounted) {
          showPosToast(
            ctx,
            ref,
            remaining <= 0
                ? tr('تم قفل الحساب لمدة 15 دقيقة')
                : tr('اسم المستخدم أو كلمة المرور غير صحيحة ({remaining} متبقية)', {'remaining': remaining}),
            type: PosNotificationType.error,
          );
        }
      }
    } catch (e) {
      if (ctx.mounted) {
        showPosToast(ctx, ref, tr('خطأ: {e}', {'e': e}), type: PosNotificationType.error);
      }
    }
  }
}
