/// المصدرُ الوحيدُ لحساب مبلغ استردادِ مرتجعِ مبيعاتٍ — خالصةٌ عمداً (لا
/// استيرادَ `data/database` ولا Riverpod)، يستعملها **الطرفان** معاً:
///
///  * `ReturnsRepositoryImpl._calculateReturnTotal` — الصرفُ الفعليّ من
///    الدرج (‏`processSalesReturn`).
///  * `PosReturnMode.refundTotal` — «مبلغُ الاسترداد» المعروضُ للكاشير في
///    `_QuickReturnLinesEditorDialog` قبل التأكيد.
///
/// العطبُ المقيسُ في مراجعة 2026-08-16: كانا يحسبان بصيغتَين مختلفتَين —
/// المعروضُ `Σ qty × unitPrice` (سعرُ البيع قبل الضريبة وقبل خصم السطر)،
/// والمصروفُ فعلياً `Σ qty × (item.total/item.quantity) × factor` + حصّةُ
/// التوصيل، حيث `item.total` شاملُ الضريبة وصافٍ من الخصم. فاتورةٌ بضريبة
/// ١٤٪ بلا خصمٍ كانت تعرض ١٠٠ وتُخرج ١١٤ من الدرج فعلياً — فائضٌ صامتٌ في
/// الدرج يُقيَّد لاحقاً «فائضَ نقدية» (إيرادٌ وهميّ). استخراجُ الصيغة هنا
/// دالّةً واحدةً يجعل افتراقهما ثانيةً مستحيلاً بنيوياً، لا بالتوثيق فقط.
library;

/// المدخلُ الأدنى لحساب سطرٍ واحد: هويّةُ السطر (تُطابق مفاتيحَ
/// [returnQuantities])، الكميةُ المباعةُ الأصليةُ للسطر (`item.quantity`)،
/// وإجماليُّه الفعليّ (`item.total` — شاملُ الضريبة، صافٍ من خصم السطر؛ لا
/// `unitPrice × quantity`).
typedef ReturnRefundLineInput = ({
  int id,
  double quantity,
  double lineTotal,
});

/// يحسب مبلغَ الاسترداد الفعليّ لطلبِ مرتجعٍ — نفسُ صيغةِ
/// `ReturnsRepositoryImpl._calculateReturnTotal` بالحرف، منقولةً هنا دون أيّ
/// تغييرٍ في المنطق:
///
///  ١. `factor` نسبةُ إجماليّ الفاتورة (بعد حسم رسم التوصيل) إلى مجموع
///     إجماليّات كلّ سطورها — يوزّع أثرَ خصم/تقريب مستوى الفاتورة على كلّ
///     سطر.
///  ٢. سعرُ وحدة السطر للاسترداد = `lineTotal / quantity` (لا أيّ سعرٍ
///     آخر).
///  ٣. حصّةٌ نسبيةٌ من رسم التوصيل تُضاف مرّةً واحدةً على مستوى الفاتورة،
///     لا لكلّ سطر (مطابقةً لـB2 في `_calculateReturnTotal`).
double calculateReturnRefundTotal({
  required Iterable<ReturnRefundLineInput> lines,
  required double invoiceTotal,
  required double invoiceDeliveryFee,
  required Map<int, double> returnQuantities,
  int decimalPlaces = 3,
}) {
  final sumAllLineTotals =
      lines.fold<double>(0.0, (sum, l) => sum + l.lineTotal);
  final factor = sumAllLineTotals > 0
      ? (invoiceTotal - invoiceDeliveryFee) / sumAllLineTotals
      : 1.0;

  double refundTotal = 0;
  double returnedRawTotal = 0;
  for (final line in lines) {
    final qty = returnQuantities[line.id] ?? 0;
    if (qty <= 0) continue;
    final unitLinePrice = line.lineTotal / line.quantity;
    returnedRawTotal += qty * unitLinePrice;
    refundTotal += qty * unitLinePrice * factor;
  }

  // B2: Proportional delivery fee refund for partial returns.
  if (invoiceDeliveryFee > 0 && sumAllLineTotals > 0) {
    final deliveryFeeRefund =
        invoiceDeliveryFee * (returnedRawTotal / sumAllLineTotals);
    refundTotal +=
        double.parse(deliveryFeeRefund.toStringAsFixed(decimalPlaces));
  }

  return double.parse(refundTotal.toStringAsFixed(decimalPlaces));
}
