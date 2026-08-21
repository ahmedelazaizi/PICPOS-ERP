/// اتّجاهُ الحركة النقدية في الاستبدال.
enum ExchangeCashDirection {
  /// البديلُ أغلى — العميلُ يدفع الفرق.
  collect,

  /// البديلُ أرخص — نردّ الفرق.
  refund,

  /// متساويان — **لا حركةَ إطلاقاً**، ولا صفٌّ بصفر.
  none,
}

/// يقرّر اتّجاهَ الفرق ومقدارَه.
///
/// خالصٌ عمداً: الاتّجاهُ قرارٌ ماليٌّ، وحالةُ التساوي هي التي تُنسى فيُكتب
/// صفُّ خزنةٍ بصفرٍ يلوّث الكشف. والمبلغُ **موجبٌ دائماً** — الإشارةُ في
/// الاتّجاه لا في الرقم، كي لا يتسرّب سالبٌ إلى `createSafeTransaction`.
({ExchangeCashDirection direction, double amount}) settleExchange({
  required double returnTotal,
  required double saleTotal,
  int decimalPlaces = 3,
}) {
  final factor = _pow10(decimalPlaces);
  final diff = ((saleTotal - returnTotal) * factor).roundToDouble() / factor;

  if (diff == 0) {
    return (direction: ExchangeCashDirection.none, amount: 0);
  }
  if (diff > 0) {
    return (direction: ExchangeCashDirection.collect, amount: diff);
  }
  return (direction: ExchangeCashDirection.refund, amount: -diff);
}

double _pow10(int n) {
  var r = 1.0;
  for (var i = 0; i < n; i++) {
    r *= 10;
  }
  return r;
}
