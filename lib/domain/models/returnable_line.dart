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

  const ReturnableLine({
    required this.invoiceItemId,
    required this.productId,
    required this.productName,
    required this.soldQty,
    required this.alreadyReturnedQty,
    required this.unitPrice,
  });

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
