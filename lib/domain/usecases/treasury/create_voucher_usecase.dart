import '../../repositories/treasury_repository.dart';

/// Use case: Create a receipt or payment voucher.
///
/// Validates amount > 0, safe exists and has sufficient balance (for payments),
/// then delegates to the treasury repository.
class CreateVoucherUseCase {
  final ITreasuryRepository _repo;

  const CreateVoucherUseCase(this._repo);

  /// Creates a receipt voucher (money IN).
  Future<int> createReceipt({
    required double amount,
    required String category,
    required int safeId,
    int? partyId,
    String? description,
  }) async {
    _validateAmount(amount);
    return _repo.createReceiptVoucher(
      amount: amount,
      category: category,
      safeId: safeId,
      partyId: partyId,
      description: description,
    );
  }

  /// Creates a payment voucher (money OUT).
  Future<int> createPayment({
    required double amount,
    required String category,
    required int safeId,
    int? partyId,
    String? description,
  }) async {
    _validateAmount(amount);
    // Balance check is done at the repository/DAO level
    return _repo.createPaymentVoucher(
      amount: amount,
      category: category,
      safeId: safeId,
      partyId: partyId,
      description: description,
    );
  }

  void _validateAmount(double amount) {
    if (amount <= 0) {
      throw ArgumentError('المبلغ يجب أن يكون أكبر من صفر');
    }
  }
}
