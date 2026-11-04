import '../../../domain/usecases/sales/calculate_invoice_totals_usecase.dart';
import 'cart_controller.dart';

/// خصمُ الفاتورة بمبلغٍ ثابت (بند ٦ — ب): قراءاتٌ مشتقّة من [CartState].
///
/// في ملفٍّ مستقلّ حفاظاً على سقف حجم `cart_controller.dart`؛ يُعاد تصديره
/// من هناك فلا يحتاج المستدعون استيراداً جديداً.
extension CartInvoiceDiscount on CartState {
  /// هل على الفاتورة خصمٌ (نسبةً أو مبلغاً)؟
  bool get hasInvoiceDiscount => invoiceDiscountAmount != null
      ? invoiceDiscountAmount! > 0
      : discountPercent > 0;

  /// النسبةُ **الفعلية** لخصم الفاتورة = الخصمُ المطبَّق ÷ قاعدةِ الخصم
  /// (المجموع − خصومات الأصناف) × ١٠٠. هي ما يُقاس عليه `disccap`.
  double get effectiveInvoiceDiscountPercent => invoiceDiscountAmount == null
      ? discountPercent
      : effectivePercentForAmount(invoiceDiscountAmount!);

  /// النسبةُ الفعلية التي **سيبلغها** مبلغٌ ثابت [amount] على الأصناف الحالية
  /// (بعد القصّ عند القاعدة)، مقرَّبةً لست خانات لتفادي ضجيج الفاصلة العائمة
  /// عند المقارنة بالسقف.
  double effectivePercentForAmount(double amount) {
    final t = totals;
    final base = t.subtotal - t.itemDiscounts;
    final applied =
        CalculateInvoiceTotalsUseCase.clampInvoiceDiscountAmount(amount, base);
    if (base <= 0 || applied <= 0) return 0;
    return (applied / base * 100 * 1e6).round() / 1e6;
  }
}
