// Purchase DTOs: PurchaseInvoiceSummary (SQL-side totals for the filtered window).
part of '../database.dart';

/// إجمالياتُ فواتير المشتريات المطابِقةِ للمرشِّحات — **من SQL لا من الصفحة**.
///
/// ‏`watchAllPurchases` يسقّف بـ٥٠٠ صفّ (‏PIR P1-05)، فطيُّ الصفحة في Dart
/// يعطي رقماً أقلَّ من الحقيقة بلا ما يشي بذلك. وهذا هو نفسُ عطبِ «ح-2» الذي
/// عولج في جانب المبيعات بـ[SalesInvoiceSummary].
class PurchaseInvoiceSummary {
  /// عدد فواتير الشراء **المطابِقة** (لا المحمَّلة على الشاشة).
  final int invoiceCount;

  /// إجمالي المشتريات — شامل الضريبة، بعد الخصم، قبل المرتجعات.
  final double totalAmount;

  /// المدفوعُ للموردين من الفواتير نفسِها.
  ///
  /// ولا سنداتِ صرفٍ مضمومةً إليه — بخلاف «المحصّل» في المبيعات الذي يضمّ
  /// سنداتِ القبض: `PurchaseInvoicesScreenState` لا تحمل سنداتِ صرفٍ أصلاً،
  /// وضمُّها هنا وحدَها كان سيجعل البطاقةَ تخالف الصفوفَ تحتها.
  final double totalPaid;

  /// إجمالي مرتجعات المشتريات لفواتيرِ **هذه** النافذة والنطاق.
  final double totalReturns;

  /// عددُ الفواتير المسدَّدةِ بالكامل.
  ///
  /// ⚠️ والعدُّ على عمود `status` لا على `paid >= total` — بخلاف المبيعات.
  /// السببُ مقيسٌ لا مذوَّق: `_applyFilters` في
  /// `purchase_invoices_controller.dart` يرشِّح بـ`inv.status`، و`inv.status`
  /// يأتي من `InvoiceEntity._mapStatus` على العمود. فلو عُدَّ هنا بالمبلغ
  /// لأعطت الشريحةُ عدداً لا يطابق ما تُظهره حين تُنقَر — عدّادٌ يكذب على
  /// مرشِّحه.
  final int paidCount;

  /// عددُ الفواتير المسدَّدةِ جزئيّاً — `status = 'partial'`.
  final int partialCount;

  /// عددُ الفواتير غيرِ المسدَّدة.
  ///
  /// وهي **حالةُ الافتراض** في `_mapStatus` لا قيمةٌ مسمّاة: أيُّ `status`
  /// خارجَ المعروفِ يقع هنا (بما فيه `NULL` والفارغُ والمجهول). فالعدُّ
  /// بالنفي لا بالإثبات، وإلّا سقط صفٌّ من العدّادات الثلاثة وهو معروضٌ في
  /// القائمة.
  final int unpaidCount;

  const PurchaseInvoiceSummary({
    required this.invoiceCount,
    required this.totalAmount,
    required this.totalPaid,
    required this.totalReturns,
    this.paidCount = 0,
    this.partialCount = 0,
    this.unpaidCount = 0,
  });

  /// المتبقي = الإجمالي − المدفوع − المرتجعات. نفسُ معادلةِ `_applyFilters`
  /// حرفاً بحرف كي لا تخالف البطاقةُ مجموعَ الصفوف.
  double get totalRemaining => totalAmount - totalPaid - totalReturns;
}
