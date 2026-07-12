import 'package:drift/drift.dart';
import '../database.dart';

/// Extensions for Loyalty Points system
extension LoyaltyExtensions on AppDatabase {
  // ═══════════════════════════════════════════════════════════════════════
  // LOYALTY PROGRAMS
  // ═══════════════════════════════════════════════════════════════════════

  /// Watch all loyalty programs
  Stream<List<LoyaltyProgram>> watchLoyaltyPrograms() {
    return select(loyaltyPrograms).watch();
  }

  /// Get active loyalty program
  Future<LoyaltyProgram?> getActiveLoyaltyProgram() {
    return (select(loyaltyPrograms)
          ..where((p) => p.isActive.equals(true))
          ..limit(1))
        .getSingleOrNull();
  }

  /// Create a loyalty program
  Future<int> createLoyaltyProgram(LoyaltyProgramsCompanion program) {
    return into(loyaltyPrograms).insert(program);
  }

  /// Update loyalty program
  Future<bool> updateLoyaltyProgram(int id, LoyaltyProgramsCompanion data) {
    return (update(
      loyaltyPrograms,
    )..where((p) => p.id.equals(id))).write(data).then((rows) => rows > 0);
  }

  /// Delete loyalty program
  Future<int> deleteLoyaltyProgram(int id) {
    return (delete(loyaltyPrograms)..where((p) => p.id.equals(id))).go();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // CUSTOMER POINTS
  // ═══════════════════════════════════════════════════════════════════════

  /// Get or create customer loyalty points for a program
  Future<CustomerLoyaltyPoint> getOrCreateCustomerPoints(
    int customerId,
    int programId,
  ) async {
    final existing =
        await (select(customerLoyaltyPoints)..where(
              (c) =>
                  c.customerId.equals(customerId) &
                  c.programId.equals(programId),
            ))
            .getSingleOrNull();

    if (existing != null) return existing;

    // Create new record
    final id = await into(customerLoyaltyPoints).insert(
      CustomerLoyaltyPointsCompanion.insert(
        customerId: customerId,
        programId: programId,
      ),
    );

    return (select(
      customerLoyaltyPoints,
    )..where((c) => c.id.equals(id))).getSingle();
  }

  /// Get customer points balance
  Future<int> getCustomerPointsBalance(int customerId, int programId) async {
    final record =
        await (select(customerLoyaltyPoints)..where(
              (c) =>
                  c.customerId.equals(customerId) &
                  c.programId.equals(programId),
            ))
            .getSingleOrNull();
    return record?.currentBalance ?? 0;
  }

  /// Watch customer points for all programs
  Stream<List<CustomerLoyaltyPoint>> watchCustomerPoints(int customerId) {
    return (select(
      customerLoyaltyPoints,
    )..where((c) => c.customerId.equals(customerId))).watch();
  }

  /// Watch all customers with points for a specific program
  Stream<List<CustomerLoyaltyPoint>> watchAllCustomerPointsByProgram(
    int programId,
  ) {
    return (select(customerLoyaltyPoints)
          ..where((c) => c.programId.equals(programId))
          ..orderBy([(c) => OrderingTerm.desc(c.currentBalance)]))
        .watch();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // LOYALTY TRANSACTIONS
  // ═══════════════════════════════════════════════════════════════════════

  /// Earn points for a customer (after a sale)
  Future<void> earnPoints({
    required int customerId,
    required int programId,
    required int points,
    int? saleId,
    String? notes,
  }) async {
    await transaction(() async {
      // Add transaction
      await into(loyaltyTransactions).insert(
        LoyaltyTransactionsCompanion.insert(
          customerId: customerId,
          programId: programId,
          type: 'earn',
          points: points,
          saleId: Value(saleId),
          notes: Value(notes ?? 'كسب نقاط من فاتورة بيع'),
        ),
      );

      // Update balance
      final current = await getOrCreateCustomerPoints(customerId, programId);
      await (update(
        customerLoyaltyPoints,
      )..where((c) => c.id.equals(current.id))).write(
        CustomerLoyaltyPointsCompanion(
          totalEarned: Value(current.totalEarned + points),
          currentBalance: Value(current.currentBalance + points),
        ),
      );
    });
  }

  /// Redeem points for a customer
  Future<bool> redeemPoints({
    required int customerId,
    required int programId,
    required int points,
    int? saleId,
    String? notes,
  }) async {
    final balance = await getCustomerPointsBalance(customerId, programId);
    if (balance < points) return false;

    // Check minimum redeem
    final program = await (select(
      loyaltyPrograms,
    )..where((p) => p.id.equals(programId))).getSingleOrNull();
    if (program != null && points < program.minRedeemPoints) return false;

    await transaction(() async {
      // Add transaction
      await into(loyaltyTransactions).insert(
        LoyaltyTransactionsCompanion.insert(
          customerId: customerId,
          programId: programId,
          type: 'redeem',
          points: -points,
          saleId: Value(saleId),
          notes: Value(notes ?? 'استبدال نقاط'),
        ),
      );

      // Update balance
      final current = await getOrCreateCustomerPoints(customerId, programId);
      await (update(
        customerLoyaltyPoints,
      )..where((c) => c.id.equals(current.id))).write(
        CustomerLoyaltyPointsCompanion(
          totalRedeemed: Value(current.totalRedeemed + points),
          currentBalance: Value(current.currentBalance - points),
        ),
      );
    });

    return true;
  }

  /// Adjust points manually
  Future<void> adjustPoints({
    required int customerId,
    required int programId,
    required int points,
    String? notes,
  }) async {
    await transaction(() async {
      final type = points >= 0 ? 'adjust' : 'adjust';
      await into(loyaltyTransactions).insert(
        LoyaltyTransactionsCompanion.insert(
          customerId: customerId,
          programId: programId,
          type: type,
          points: points,
          notes: Value(notes ?? 'تعديل يدوي'),
        ),
      );

      final current = await getOrCreateCustomerPoints(customerId, programId);
      final newBalance = current.currentBalance + points;
      await (update(
        customerLoyaltyPoints,
      )..where((c) => c.id.equals(current.id))).write(
        CustomerLoyaltyPointsCompanion(
          currentBalance: Value(newBalance < 0 ? 0 : newBalance),
          totalEarned: Value(
            points > 0 ? current.totalEarned + points : current.totalEarned,
          ),
          totalRedeemed: Value(
            points < 0
                ? current.totalRedeemed + points.abs()
                : current.totalRedeemed,
          ),
        ),
      );
    });
  }

  /// Get loyalty transactions for a customer
  Future<List<LoyaltyTransaction>> getCustomerLoyaltyTransactions(
    int customerId, {
    int? programId,
  }) {
    final query = select(loyaltyTransactions)
      ..where((t) => t.customerId.equals(customerId))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    if (programId != null) {
      query.where((t) => t.programId.equals(programId));
    }
    return query.get();
  }

  /// Watch loyalty transactions for a customer
  Stream<List<LoyaltyTransaction>> watchCustomerLoyaltyTransactions(
    int customerId,
  ) {
    return (select(loyaltyTransactions)
          ..where((t) => t.customerId.equals(customerId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(50))
        .watch();
  }

  /// Calculate total points earned in a date range
  Future<int> getTotalPointsEarned(
    int programId,
    DateTime from,
    DateTime to,
  ) async {
    final result =
        await (select(loyaltyTransactions)..where(
              (t) =>
                  t.programId.equals(programId) &
                  t.type.equals('earn') &
                  t.createdAt.isBiggerOrEqual(Variable(from)) &
                  t.createdAt.isSmallerThan(Variable(to)),
            ))
            .get();
    return result.fold<int>(0, (sum, t) => sum + t.points);
  }
}
