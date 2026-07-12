import '../../data/database/database.dart';

abstract class ILoyaltyRepository {
  Stream<List<LoyaltyProgram>> watchLoyaltyPrograms();
  Future<void> createLoyaltyProgram(LoyaltyProgramsCompanion program);
  Future<void> updateLoyaltyProgram(int id, LoyaltyProgramsCompanion program);
  Future<void> deleteLoyaltyProgram(int id);
  
  Stream<List<CustomerLoyaltyPoint>> watchAllCustomerPointsByProgram(int programId);
  Future<List<LoyaltyTransaction>> getTransactions({
    int? programId,
    int? customerId,
    String? type,
  });
  
  Future<void> adjustPoints({
    required int customerId,
    required int programId,
    required int points,
    String? notes,
  });
}
