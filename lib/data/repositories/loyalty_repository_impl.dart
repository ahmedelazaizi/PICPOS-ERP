import 'package:drift/drift.dart';
import '../database/database.dart';
import '../../domain/repositories/loyalty_repository.dart';

class LoyaltyRepositoryImpl implements ILoyaltyRepository {
  final AppDatabase _db;

  LoyaltyRepositoryImpl(this._db);

  @override
  Stream<List<LoyaltyProgram>> watchLoyaltyPrograms() {
    return _db.select(_db.loyaltyPrograms).watch();
  }

  @override
  Future<void> createLoyaltyProgram(LoyaltyProgramsCompanion program) async {
    await _db.into(_db.loyaltyPrograms).insert(program);
  }

  @override
  Future<void> updateLoyaltyProgram(int id, LoyaltyProgramsCompanion program) async {
    await (_db.update(_db.loyaltyPrograms)..where((p) => p.id.equals(id)))
        .write(program);
  }

  @override
  Future<void> deleteLoyaltyProgram(int id) async {
    await (_db.delete(_db.loyaltyPrograms)..where((p) => p.id.equals(id))).go();
  }

  @override
  Stream<List<CustomerLoyaltyPoint>> watchAllCustomerPointsByProgram(int programId) {
    return (_db.select(_db.customerLoyaltyPoints)
          ..where((p) => p.programId.equals(programId)))
        .watch();
  }

  @override
  Future<List<LoyaltyTransaction>> getTransactions({
    int? programId,
    int? customerId,
    String? type,
  }) {
    final query = _db.select(_db.loyaltyTransactions);
    if (programId != null) query.where((t) => t.programId.equals(programId));
    if (customerId != null) query.where((t) => t.customerId.equals(customerId));
    if (type != null && type != 'all') query.where((t) => t.type.equals(type));
    query.orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return query.get();
  }

  @override
  Future<void> adjustPoints({
    required int customerId,
    required int programId,
    required int points,
    String? notes,
  }) async {
    await _db.transaction(() async {
      // Update customer points balance
      final existing = await (_db.select(_db.customerLoyaltyPoints)
            ..where((p) => p.customerId.equals(customerId))
            ..where((p) => p.programId.equals(programId)))
          .getSingleOrNull();

      if (existing != null) {
        await (_db.update(_db.customerLoyaltyPoints)
              ..where((p) => p.id.equals(existing.id)))
            .write(CustomerLoyaltyPointsCompanion(
              currentBalance: Value(existing.currentBalance + points),
              totalEarned: points > 0 ? Value(existing.totalEarned + points) : const Value.absent(),
              totalRedeemed: points < 0 ? Value(existing.totalRedeemed + points.abs()) : const Value.absent(),
            ));
      } else {
        await _db.into(_db.customerLoyaltyPoints).insert(
          CustomerLoyaltyPointsCompanion.insert(
            customerId: customerId,
            programId: programId,
          ),
        );
      }

      // Record transaction
      await _db.into(_db.loyaltyTransactions).insert(
        LoyaltyTransactionsCompanion.insert(
          programId: programId,
          customerId: customerId,
          type: points > 0 ? 'earn' : 'redeem',
          points: points.abs(),
          notes: Value(notes),
        ),
      );
    });
  }
}
