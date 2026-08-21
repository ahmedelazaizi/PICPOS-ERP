import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:ural_erp/core/theme/app_colors.dart';

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
        title: const Row(
          children: [
            Icon(PhosphorIconsBold.shoppingCartSimple, color: AppColors.warning, size: 28),
            SizedBox(width: 10),
            Text('لا يمكن إغلاق البرنامج'),
          ],
        ),
        content: const Text(
          'يوجد أصنافٌ في سلة البيع الحالية.\n'
          'أتمّ عمليةَ البيع، أو علّق الطلبَ، أو امسح السلّةَ يدوياً — ثم '
          'أعد محاولة الإغلاق.',
          style: TextStyle(height: 1.6),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
              foregroundColor: Colors.white,
            ),
            child: const Text('حسناً'),
          ),
        ],
      ),
    ),
  );
}
