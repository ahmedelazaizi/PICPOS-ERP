import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' show showDialog;

import '../../pos/widgets/cart/cart_discount_dialog.dart';

/// ناتجُ حوار خصم الفاتورة: **نسبة** أو **مبلغٌ ثابت** (واحدٌ منهما فقط).
class PicPosInvoiceDiscountChoice {
  const PicPosInvoiceDiscountChoice.percent(double value)
      : percent = value,
        amount = null;
  const PicPosInvoiceDiscountChoice.amount(double value)
      : amount = value,
        percent = null;

  /// «إزالة الخصم».
  const PicPosInvoiceDiscountChoice.none()
      : percent = 0,
        amount = null;

  final double? percent;
  final double? amount;
}

/// حوارُ خصم الفاتورة في البيع السريع: **نسبة أو مبلغٌ ثابت** (بند ٦ — ب).
///
/// في تبويب «قيمة» يُمرَّر المبلغُ **كما أُدخل** (10.00 تبقى 10.00) ولا يُحوَّل
/// إلى نسبةٍ مقرَّبة؛ والقصُّ عند القاعدة يتولّاه حسابُ الإجماليات.
///
/// [base] = قاعدةُ خصم الفاتورة (`subtotal − Σ خصم الأسطر`) للمعاينة فقط.
/// السقفُ لا يُمرَّر للحوار عمداً: يُحكم بـ`ensureDiscountWithinPolicy` على
/// النسبة الفعلية بعد الحوار.
///
/// يعيد: `null` عند الإغلاق بلا تطبيق، و`none()` عند «إزالة الخصم».
Future<PicPosInvoiceDiscountChoice?> showPicPosInvoiceDiscountDialog(
  BuildContext context, {
  required double base,
  required double currentPercent,
}) async {
  PicPosInvoiceDiscountChoice? picked;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => CartDiscountDialog(
      subtotal: base,
      currentDiscountPercent: currentPercent,
      onApply: (percent) => picked = PicPosInvoiceDiscountChoice.percent(percent),
      onApplyAmount: (amount) =>
          picked = PicPosInvoiceDiscountChoice.amount(amount),
      onRemove: () {
        picked = const PicPosInvoiceDiscountChoice.none();
        Navigator.pop(dialogContext);
      },
    ),
  );
  return picked;
}
