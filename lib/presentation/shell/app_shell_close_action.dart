import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:ural_erp/core/i18n/tr.dart';
import 'package:ural_erp/core/navigation/dirty_screens_registry.dart';
import 'package:ural_erp/core/theme/app_colors.dart';
import 'package:ural_erp/domain/models/app_close_cart_gate.dart';
import 'package:ural_erp/presentation/widgets/dialogs/cart_not_empty_close_dialog.dart';

/// زرّ «إغلاق البرنامج» اليدويّ في الشريط الجانبيّ.
///
/// الترتيب: (١) سلّةُ بيعٍ غير فارغة ⇒ منعٌ. (٢) شاشاتٌ متّسخة في
/// [registry] ⇒ تسألُ كلٌّ منها عن إسقاط ما لم يُحفَظ، ورفضُ واحدةٍ يُبقي
/// البرنامج. (٣) حوارُ تأكيد الإغلاق، ثم [backup] ثم [exitApp].
///
/// هذا الزرّ ينتهي بـ`exitApp` مباشرةً بلا مرورٍ بـ`onWindowClose`، فحارسُ
/// النافذة وحده لا يغطّيه — لذا يستشير السجلَّ هنا أيضاً.
Future<void> runCloseAppAction({
  required BuildContext context,
  required int cartItemCount,
  required DirtyScreensRegistry registry,
  required Future<void> Function() backup,
  required VoidCallback exitApp,
}) async {
  if (shouldBlockAppCloseForCart(cartItemCount)) {
    await showCartNotEmptyCloseBlockedDialog(context);
    return;
  }
  if (!await registry.confirmCloseAll()) return;
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => Directionality(
      textDirection: Directionality.of(dialogContext),
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(PhosphorIconsBold.power, color: AppColors.error),
            const SizedBox(width: 8),
            Text(tr('إغلاق البرنامج')),
          ],
        ),
        content: Text(
          tr('هل تريد إغلاق البرنامج بالكامل؟ سيتم عمل نسخة احتياطية تلقائياً.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(tr('إلغاء')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              Navigator.pop(dialogContext);
              // Perform final backup before exit
              await backup();
              exitApp();
            },
            child: Text(tr('إغلاق وبالنسخ الاحتياطي')),
          ),
        ],
      ),
    ),
  );
}
