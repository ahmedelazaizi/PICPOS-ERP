import 'package:flutter/foundation.dart';
import '../entities/cart_item_entity.dart';
import '../repositories/sales_repository.dart';

/// PIR Phase 2 — UseCase: Create Sales Invoice
///
/// Encapsulates the business logic for creating a sales invoice,
/// including validation before delegating to the repository.
class CreateSalesInvoiceUseCase {
  final SalesRepository _salesRepository;

  CreateSalesInvoiceUseCase(this._salesRepository);

  /// Validate and create a sales invoice.
  /// Returns the new invoice ID.
  Future<int> execute({
    required List<CartItemEntity> items,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    required double paid,
    required String paymentMethod,
    required int warehouseId,
    required int userId,
    int? customerId,
    double? cashAmount,
    double? bankAmount,
    double deliveryFee = 0,
    int? deliveryCompanyId,
    int? courierId,
    String? deliveryStatus,
    String? notes,
  }) async {
    // 1. Domain-level validation
    if (items.isEmpty) {
      throw Exception('لا يمكن إنشاء فاتورة بدون أصناف');
    }
    // For returns, total is negative — only block truly zero totals
    if (total == 0) {
      throw Exception('إجمالي الفاتورة لا يمكن أن يكون صفراً');
    }
    if (total > 0 && paid > total) {
      debugPrint('[CreateSalesInvoice] تحذير: المدفوع ($paid) أكبر من الإجمالي ($total)');
    }

    // 2. Delegate to repository
    return _salesRepository.createSalesInvoice(
      items: items,
      subtotal: subtotal,
      discount: discount,
      tax: tax,
      total: total,
      paid: paid,
      paymentMethod: paymentMethod,
      warehouseId: warehouseId,
      userId: userId,
      customerId: customerId,
      cashAmount: cashAmount,
      bankAmount: bankAmount,
      deliveryFee: deliveryFee,
      deliveryCompanyId: deliveryCompanyId,
      courierId: courierId,
      deliveryStatus: deliveryStatus,
      notes: notes,
    );
  }
}
