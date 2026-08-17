import 'dart:math' as math;

import '../../core/constants/app_constants.dart';

/// وحداتٌ صحيحةٌ للمقارنة النقديّة — نفسُ قاعدة `SplitPlan` و
/// `TableSessionService`: جمعُ `double` يُنتج ٩٩٫٩٩٩٩٩٩٩٩٩ في القسمة على
/// ثلاثة، فمقارنةُ `==` المباشرة تُبلّغ عن فرقٍ لا وجود له.
int tableMoneyUnits(double value) =>
    (value * math.pow(10, AppConstants.decimalPlaces)).round();

String _money(double value) =>
    value.toStringAsFixed(AppConstants.decimalPlaces);

/// فرقٌ بين **ما سيُشحَن على الفاتورة** و**ما سيُسجَّل على الطلب**.
///
/// المحرّكان مختلفان: السلّةُ تحسب بـ`CalculateInvoiceTotalsUseCase` (ضريبةٌ
/// تُضاف فوق، وخصومُ سطرٍ وفاتورةٍ وعروضٍ تُطرح)، والطلبُ يحسب
/// `SUM(quantity × unitPrice)` ناقصَ خصمِ الطلب. فما دام الرقمان يخرجان من
/// محرّكين، يجب أن يُقارَنا **قبل** ترحيل الفاتورة لا بعده: فاتورةٌ لم تصدر
/// لا تحتاج تسوية.
class TableChargeMismatch {
  const TableChargeMismatch({required this.charged, required this.expected});

  /// إجماليُّ السلّة كما سيُشحَن على الزبون.
  final double charged;

  /// المستحقُّ على الطلب (بعد الخصم، ناقصاً ما دُفع).
  final double expected;

  double get difference => charged - expected;

  /// رسالةٌ تُسمّي الرقمين والفرقَ — الكاشيرُ يجب أن يرى **لماذا** رُفض،
  /// لا «فشل الدفع» فحسب.
  String get message =>
      'المبلغُ المطلوبُ على الشاشة ${_money(charged)} ${AppConstants.currencySymbolEn} '
      'والمستحقُّ على الطلب ${_money(expected)} ${AppConstants.currencySymbolEn} '
      '— فرقٌ قدرُه ${_money(difference)}. لم تُصدَر فاتورة: راجع الضريبةَ '
      'وخصمَ الطلب وأصنافَه ثم أعِد المحاولة.';
}

/// `null` إن تطابق الرقمان بدقّة [AppConstants.decimalPlaces]، وإلّا وصفُ
/// الفرق.
TableChargeMismatch? checkTableCharge({
  required double charged,
  required double expected,
}) {
  if (tableMoneyUnits(charged) == tableMoneyUnits(expected)) return null;
  return TableChargeMismatch(charged: charged, expected: expected);
}
