import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/core/widgets/app_toast.dart';

import '../../core/theme/app_colors.dart';
import '../../data/providers/providers.dart';
import '../../data/providers/quick_sale_policy_providers.dart';
import '../../domain/models/app_close_cart_gate.dart';
import '../../domain/models/quick_sale_policy.dart';
import '../pos/logic/hold_cart_before_leaving.dart';
import '../pos/logic/open_shift_gate.dart';
import '../pos/providers/cart_controller.dart';
import '../pos_picpos/widgets/picpos_cart_permissions.dart';
import '../widgets/dialogs/cart_not_empty_close_dialog.dart';

/// حارسُ السلّة عند مغادرة البيع/الخروج (قرارُ مالكٍ): يعرض حوارَ
/// «تعليق الفاتورة ثم المتابعة / إلغاء والبقاء». يُرجع `true` فقط إذا اختار
/// الكاشيرُ التعليقَ **ونجح** (صلاحية `pos_hold_order` + سقف الفواتير المعلّقة
/// + الحفظ، كما في شاشة البيع السريع). غير ذلك ⇒ `false` والسلّةُ باقية.
Future<bool> confirmHoldCartToLeave(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  required String holdLabel,
}) async {
  final proceed = await showCartNotEmptyBlockedDialog(
    context,
    title: title,
    holdLabel: holdLabel,
  );
  if (!proceed || !context.mounted) return false;
  if (!await ensureHoldOrderPermission(ref, context)) return false;
  if (!context.mounted) return false;

  final policy = await ref.read(quickSalePolicyProvider.future);
  if (!context.mounted) return false;
  final cap = quickSaleHoldCap(policy);
  final heldNow = ref.read(heldOrdersProvider).value?.length ?? 0;
  if (!quickSaleCanHoldMore(current: heldNow, cap: cap)) {
    AppToast.show(
      context,
      tr('بلغتَ الحدَّ الأقصى للفواتير المعلّقة ({cap}) — أنهِ فاتورةً معلّقةً أوّلاً', {'cap': cap}),
      type: ToastType.error,
    );
    return false;
  }

  final outcome = await holdSaleCartBeforeLeaving(ref, reason: title);
  if (outcome == CartHoldOutcome.failed) {
    if (context.mounted) {
      AppToast.show(
        context,
        tr('تعذّر تعليق الفاتورة — بقيت السلة كما هي'),
        type: ToastType.error,
      );
    }
    return false;
  }
  return true;
}

/// تسجيلُ الخروج من الشلّ (مُستخرَج من `app_shell.dart`). سلّةٌ غير فارغة ⇒
/// حوارُ التعليق أولاً؛ وبعد نجاحه يُكمَل الخروجُ دون حوار تأكيدٍ ثانٍ.
Future<void> showLogoutConfirmation(
  BuildContext context,
  WidgetRef ref,
  bool Function() isMounted,
) async {
  var alreadyConfirmed = false;
  if (shouldBlockLogoutForCart(ref.read(cartControllerProvider).items.length)) {
    if (!await confirmHoldCartToLeave(
      context,
      ref,
      title: tr('لا يمكن تسجيل الخروج'),
      holdLabel: tr('تعليق الفاتورة ثم تسجيل الخروج'),
    )) {
      return;
    }
    alreadyConfirmed = true;
  }
  if (!isMounted() || !context.mounted) return;

  // الوردية بتتبلّغ مش بتتمنع: تفضل مفتوحة والكاشير يكمّلها لما يرجع، أو
  // اللي عنده `pos_shift_close` يقفلها من شاشة الورديات المفتوحة.
  await notifyOpenShift(
    context: context,
    ref: ref,
    reason: tr('قبل تسجيل الخروج'),
  );
  if (!isMounted() || !context.mounted) return;

  if (alreadyConfirmed) {
    await _performLogout(ref);
    return;
  }
  showDialog(
    context: context,
    builder: (context) => Directionality(
      textDirection: Directionality.of(context),
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(PhosphorIconsBold.signOut, color: AppColors.error),
            const SizedBox(width: 8),
            Text(tr('تسجيل الخروج')),
          ],
        ),
        content: Text(tr('هل تريد تسجيل الخروج من النظام؟')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('إلغاء')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              Navigator.pop(context);
              await _performLogout(ref);
            },
            child: Text(tr('خروج')),
          ),
        ],
      ),
    ),
  );
}

Future<void> _performLogout(WidgetRef ref) async {
  final auth = ref.read(authProvider);
  try {
    final logger = ref.read(activityLoggerProvider);
    await logger.logLogout(
      auth.user?.id ?? 0,
      auth.user?.displayName ?? 'Unknown',
    );
  } catch (e) {
    debugPrint('[ActivityLog] Error: $e');
  }
  // Invalidate all user-scoped providers so the next login starts with a
  // clean state rather than briefly showing the previous user's nav items.
  ref.invalidate(userNavItemsProvider);
  ref.invalidate(userAllowedScreensProvider);
  ref.invalidate(currentUserPermissionsProvider);
  ref.invalidate(userRoleProvider);
  ref.invalidate(activeBranchIdProvider);
  ref.read(authProvider.notifier).logout();
  // Navigation handled reactively by MaterialApp.home watching authProvider
}
