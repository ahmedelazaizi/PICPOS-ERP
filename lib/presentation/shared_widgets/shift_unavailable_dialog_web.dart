// بديل الويب لـ`pos/widgets/pos_opening_balance_dialog.dart` (م3-9).
//
// `open_shift_prompt.dart` يعرض حوار الرصيد الافتتاحي لفتح وردية POS عند مرتجعٍ
// نقدي بلا وردية. الوردية مفهومُ نقطة البيع (مستبعدة من الويب: `/api/shifts`
// خارج مسارات الكتابة المفتوحة لرمز الويب)، فعلى الويب يُشرَح الأمر ويُرجَع
// `null` (= رفض فتح الوردية ⇒ لا مرتجع ولا أثر).
//
// يُختار بدل الأصل بالاستيراد الشرطي (`dart.library.js_interop`)؛ الديسكتوب
// (io) يبقى على الحوار الأصلي دون تغيير.
import 'package:flutter/material.dart';
import 'package:picpos_erp/core/i18n/tr.dart';

class PosOpeningBalanceDialog extends StatelessWidget {
  const PosOpeningBalanceDialog({
    super.key,
    required this.userName,
    this.subtitle,
  });

  final String userName;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('لا توجد وردية مفتوحة')),
      content: Text(
        tr('فتح الوردية غير متاح من نسخة الويب. افتح وردية من تطبيق الكاشير ثم أعد المحاولة.'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop<double>(null),
          child: Text(tr('حسناً')),
        ),
      ],
    );
  }
}
