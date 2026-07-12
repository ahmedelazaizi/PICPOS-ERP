import '../../../core/constants/app_constants.dart';
import '../../../core/utils/financial_utils.dart';
import '../../repositories/sales_repository.dart';
import 'calculate_invoice_totals_usecase.dart';

/// Use case for completing a sale transaction.
///
/// Owns the pure business-rule validations that must always pass before
/// the request reaches the repository (database). Keeping them here means:
///   • Unit tests exercise the rules without touching the DB.
///   • The repository stays focused on persistence, not policy.
///
/// Validations performed (Day 9 — PIR):
///   1. Cart must not be empty.
///   2. Credit payment requires a named customer.
///   3. Mixed/split payment totals must cover the invoice total.
class CompleteSaleUseCase {
  final SalesRepository _repository;
  final CalculateInvoiceTotalsUseCase _totalsUseCase;

  CompleteSaleUseCase(
    this._repository, [
    CalculateInvoiceTotalsUseCase? totalsUseCase,
  ]) : _totalsUseCase = totalsUseCase ?? CalculateInvoiceTotalsUseCase();

  /// Execute the sale completion.
  ///
  /// Returns [SaleResult.failure] immediately for any policy violation;
  /// otherwise delegates to [SalesRepository.completeSalesTransaction].
  Future<SaleResult> execute(SaleRequest request) async {
    // ── Rule 1: non-empty cart ───────────────────────────────────────────
    if (request.items.isEmpty) {
      return SaleResult.failure('السلة فارغة — أضف منتجاً قبل إتمام البيع');
    }

    // ── Rule 2: credit payment requires a customer ───────────────────────
    if (request.paymentMethod == 'credit' && request.customerId == null) {
      return SaleResult.failure('يجب اختيار عميل لإتمام البيع الآجل');
    }

    // ── Rule 3: mixed/split payment must cover the invoice total ─────────
    if (request.paymentMethod == 'mixed' ||
        request.paymentMethod == 'multiple') {
      final totals = _totalsUseCase.execute(
        items: request.items,
        invoiceDiscountPercent: request.discountPercent,
        taxPercent: request.taxEnabled ? request.taxPercent : 0,
        taxEnabled: request.taxEnabled,
      );
      // BUG-C04: the delivery fee is part of the amount due — totals.total
      // excludes it (it is added at the orchestrator), so a split payment must
      // be validated against total + deliveryFee. Round both sides to avoid a
      // sub-fils (3dp) false negative.
      final invoiceDue =
          FinancialUtils.round(totals.total + request.deliveryFee);
      final totalPaid = FinancialUtils.round((request.cashAmount ?? 0) +
          (request.bankAmount ?? 0) +
          (request.clickAmount ?? 0));
      if (totalPaid < invoiceDue) {
        return SaleResult.failure(
          'المبلغ المدفوع (${totalPaid.toStringAsFixed(AppConstants.decimalPlaces)}) '
          'أقل من إجمالي الفاتورة (${invoiceDue.toStringAsFixed(AppConstants.decimalPlaces)})',
        );
      }
    }

    return _repository.completeSalesTransaction(request);
  }
}
