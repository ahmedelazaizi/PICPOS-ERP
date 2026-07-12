part of '../activity_logger.dart';

// ═══════════════════════════════════════════════════════════════════════════
// POS & SALES — void, discount, return, sale completion, held orders
// ═══════════════════════════════════════════════════════════════════════════

extension ActivityLoggerSales on ActivityLogger {
  /// Log a void/cancelled invoice with amount.
  Future<void> logVoid(int userId, String userName, String invoiceNum, double amount) {
    return log(userId: userId, userName: userName, action: 'void', entityType: 'invoice',
        description: 'إلغاء فاتورة #$invoiceNum بقيمة $amount', amount: amount);
  }

  /// Log discount applied to an invoice
  Future<void> logDiscount(int userId, String userName, String invoiceNum, double discountAmount,
      {String? discountType}) {
    return log(userId: userId, userName: userName, action: 'discount', entityType: 'invoice',
        description: 'تطبيق خصم ${discountType ?? ''} على فاتورة #$invoiceNum', amount: discountAmount);
  }

  /// Log a sales or purchase return
  Future<void> logReturn(int userId, String userName, String invoiceNum, double amount,
      {String returnType = 'sales'}) {
    return log(userId: userId, userName: userName, action: 'return', entityType: 'invoice',
        description: 'مرتجع ${returnType == 'sales' ? 'مبيعات' : 'مشتريات'} — فاتورة #$invoiceNum', amount: amount);
  }

  /// Log invoice deletion
  Future<void> logDeleteInvoice(int userId, String userName, String invoiceNum, double amount) {
    return log(userId: userId, userName: userName, action: 'delete_invoice', entityType: 'invoice',
        description: 'حذف فاتورة #$invoiceNum بقيمة $amount', amount: amount);
  }

  /// Log sale completion
  Future<void> logSale(int userId, String userName, int invoiceId, double total, String paymentMethod) {
    return log(userId: userId, userName: userName, action: 'sale', entityType: 'invoice',
        entityId: invoiceId, description: 'بيع فاتورة #$invoiceId — $paymentMethod', amount: total);
  }

  /// Log a manual price override for a product.
  Future<void> logPriceOverride(int userId, String userName, String productName, double oldPrice, double newPrice) {
    return log(userId: userId, userName: userName, action: 'price_override', entityType: 'product',
        description: 'تعديل سعر صنف $productName يدوياً', oldValue: oldPrice.toString(), newValue: newPrice.toString());
  }

  /// Log manual cash drawer open
  Future<void> logCashDrawerOpen(int userId, String userName) {
    return log(userId: userId, userName: userName, action: 'cash_drawer_open', entityType: 'cash_drawer',
        description: 'فتح درج النقود يدوياً');
  }

  /// Log shift closing
  Future<void> logShiftClose(int userId, String userName, {double? expectedAmount, double? actualAmount}) {
    return log(userId: userId, userName: userName, action: 'shift_close', entityType: 'shift',
        description: 'إغلاق وردية', oldValue: expectedAmount?.toString(), newValue: actualAmount?.toString(),
        amount: actualAmount != null && expectedAmount != null ? actualAmount - expectedAmount : null);
  }
}
