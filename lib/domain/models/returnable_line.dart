/// سطرٌ من فاتورةٍ أصلية بحدّ إرجاعه.
///
/// خالصٌ عمداً: القاعدةُ «المرتجع ≤ المباع − المرتجع سلفاً» كانت مدفونةً في
/// `returns_repository_impl.dart:105` داخلَ حلقةٍ تضرب القاعدة، فلا تُختبر
/// إلا بقاعدةٍ كاملة — ولا يراها بناءُ الواجهة أصلاً فيسمح بإدخالٍ يُرفض
/// عند الحفظ.
class ReturnableLine {
  final int invoiceItemId;
  final int productId;
  final String productName;
  final double soldQty;
  final double alreadyReturnedQty;
  final double unitPrice;

  /// إجماليّ السطر الفعليّ في الفاتورة الأصليّة (`SalesInvoiceItem.total`)
  /// — شاملُ الضريبة وصافٍ من خصم السطر، لا `unitPrice × soldQty`. هو أساسُ
  /// حساب مبلغ الاسترداد الفعليّ (‏[calculateReturnRefundTotal])، فالعطبُ
  /// المقيسُ في مراجعة 2026-08-16 كان استعمالَ `unitPrice` (سعرُ ما قبل
  /// الضريبة والخصم) لحساب مبلغٍ يُفترض أن يطابق ما يخرج من الدرج فعلياً.
  ///
  /// اختياريٌّ: `null` لاختباراتٍ لا تُعنى بالاسترداد فتترك `effectiveLineTotal`
  /// يشتقّ تقريباً من `unitPrice × soldQty` (صحيحٌ فقط بلا ضريبةٍ ولا خصم
  /// سطر). المسارُ الوحيدُ في الإنتاج (`_showQuickReturn`) يمرّره صراحةً
  /// دوماً من `item.total`.
  final double? lineTotal;

  const ReturnableLine({
    required this.invoiceItemId,
    required this.productId,
    required this.productName,
    required this.soldQty,
    required this.alreadyReturnedQty,
    required this.unitPrice,
    this.lineTotal,
  });

  /// [lineTotal] الفعليّ حين مُرَّر، وإلا تقريبٌ من `unitPrice × soldQty` —
  /// راجع توثيق [lineTotal] لحدود هذا التقريب.
  double get effectiveLineTotal => lineTotal ?? (unitPrice * soldQty);

  /// نفسُ سماحِ `returns_repository_impl.dart` — الفاصلةُ العائمة تجعل
  /// إرجاعَ الكامل يبدو تجاوزاً بمقدارٍ لا يُرى.
  static const double _epsilon = 0.001;

  double get availableQty {
    final remaining = soldQty - alreadyReturnedQty;
    return remaining > 0 ? remaining : 0;
  }

  bool isReturnRequestValid(double requested) {
    if (requested <= 0) return false;
    final remaining = soldQty - alreadyReturnedQty;
    return requested <= remaining + _epsilon;
  }
}
