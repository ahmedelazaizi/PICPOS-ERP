import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:picpos_erp/core/theme/app_colors.dart';

/// يعرض حواراً يمنع إغلاقَ البرنامج بسبب أصنافٍ في سلة البيع.
///
/// زرٌّ واحدٌ عمداً — لا «أغلق على أي حال» (طلبُ مالكٍ 2026-08-17: منعٌ لا
/// تخيير). لا يمسح السلّةَ ولا يفعل شيئاً غير الإغلاق؛ الحسمُ على الكاشير:
/// يبيع أو يعلّق أو يمسح السلّةَ يدوياً ثم يعيد محاولة الإغلاق.
Future<void> showCartNotEmptyCloseBlockedDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title:  Row(
          children: [
            const Icon(PhosphorIconsBold.shoppingCartSimple, color: AppColors.warning, size: 28),
            const SizedBox(width: 10),
            Text(tr('لا يمكن إغلاق البرنامج')),
          ],
        ),
        content:  Text(
          tr('يوجد أصنافٌ في سلة البيع الحالية.\nأتمّ عمليةَ البيع، أو علّق الطلبَ، أو امسح السلّةَ يدوياً — ثم أعد محاولة الإغلاق.'),
          style: const TextStyle(height: 1.6),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
              foregroundColor: Colors.white,
            ),
            child:  Text(tr('حسناً')),
          ),
        ],
      ),
    ),
  );
}
