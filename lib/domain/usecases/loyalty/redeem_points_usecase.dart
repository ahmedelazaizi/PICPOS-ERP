import '../../repositories/loyalty_repository.dart';

/// Use case: Redeem or adjust loyalty points for a customer.
///
/// Validates that points > 0 and customer exists, then delegates
/// to the loyalty repository for atomic point adjustment.
class RedeemPointsUseCase {
  final ILoyaltyRepository _repo;

  const RedeemPointsUseCase(this._repo);

  /// Adjusts (earn or redeem) points for a customer in a loyalty program.
  ///
  /// Use negative [points] for redemption, positive for earning.
  Future<void> execute({
    required int programId,
    required int customerId,
    required int points,
    String? notes,
  }) async {
    if (programId <= 0) {
      throw ArgumentError('برنامج الولاء غير صحيح');
    }
    if (customerId <= 0) {
      throw ArgumentError('العميل غير صحيح');
    }
    if (points == 0) {
      throw ArgumentError('عدد النقاط لا يمكن أن يكون صفر');
    }

    await _repo.adjustPoints(
      programId: programId,
      customerId: customerId,
      points: points,
      notes: notes,
    );
  }
}
