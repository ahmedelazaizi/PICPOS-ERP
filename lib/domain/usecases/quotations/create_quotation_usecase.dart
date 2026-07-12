import '../../repositories/i_quotations_repository.dart';
import '../../entities/cart_item_entity.dart';

/// Use case: Create a quotation with validation.
///
/// Validates customer and items before delegating to the repository.
class CreateQuotationUseCase {
  final IQuotationsRepository _repo;

  const CreateQuotationUseCase(this._repo);

  /// Saves a new quotation.
  Future<int> execute({
    required List<CartItemEntity> items,
    required int? customerId,
    required int userId,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    String? notes,
  }) async {
    if (items.isEmpty) {
      throw ArgumentError('يجب إضافة صنف واحد على الأقل');
    }
    if (total <= 0) {
      throw ArgumentError('إجمالي عرض السعر يجب أن يكون أكبر من صفر');
    }
    if (userId <= 0) {
      throw ArgumentError('المستخدم غير صحيح');
    }

    return _repo.saveQuotation(
      items: items,
      customerId: customerId,
      userId: userId,
      subtotal: subtotal,
      discount: discount,
      tax: tax,
      total: total,
      notes: notes,
    );
  }
}

/// Use case: Convert a quotation into a sales invoice.
class ConvertQuotationUseCase {
  final IQuotationsRepository _repo;

  const ConvertQuotationUseCase(this._repo);

  /// Marks quotation as converted and links it to the invoice ID.
  Future<void> execute(int quotationId, int invoiceId) async {
    if (quotationId <= 0 || invoiceId <= 0) {
      throw ArgumentError('معرّف عرض السعر أو الفاتورة غير صحيح');
    }

    await _repo.updateQuotationStatus(
      quotationId,
      'converted',
      convertedInvoiceId: invoiceId,
    );
  }
}
