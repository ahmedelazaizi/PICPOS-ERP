import '../../../services/e_invoicing/e_invoice_service_wrapper.dart';

/// Result of e-invoice submission
class EInvoiceResult {
  final bool isSuccess;
  final String? submissionId;
  final String? documentUuid;
  final String? error;

  EInvoiceResult.success({this.submissionId, this.documentUuid})
      : isSuccess = true,
        error = null;

  EInvoiceResult.failure(this.error)
      : isSuccess = false,
        submissionId = null,
        documentUuid = null;
}

/// Use case: Submit invoice to tax authority (ETA or JOFOTARA)
class SubmitEInvoiceUseCase {
  final EInvoiceServiceWrapper _wrapper;

  SubmitEInvoiceUseCase(this._wrapper);

  /// Submit a unified invoice to the configured tax platform
  Future<EInvoiceResult> submit(UnifiedInvoice invoice) async {
    if (invoice.internalId.trim().isEmpty) {
      return EInvoiceResult.failure('رقم الفاتورة مطلوب');
    }
    if (invoice.totalAmount <= 0) {
      return EInvoiceResult.failure('إجمالي الفاتورة يجب أن يكون أكبر من صفر');
    }

    try {
      if (!_wrapper.isConfigured) {
        return EInvoiceResult.failure('خدمة الفوترة الإلكترونية غير مفعلة');
      }

      final result = await _wrapper.submitInvoice(invoice);

      if (result.success) {
        return EInvoiceResult.success(
          submissionId: result.submissionId,
          documentUuid: result.documentUuid,
        );
      } else {
        return EInvoiceResult.failure(
          result.errorMessage ?? 'فشل في إرسال الفاتورة',
        );
      }
    } catch (e) {
      return EInvoiceResult.failure('خطأ في الاتصال: ${e.toString()}');
    }
  }
}
