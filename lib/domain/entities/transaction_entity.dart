/// Domain entity representing a treasury transaction (receipt or payment).
class TransactionEntity {
  final int id;
  final int safeId;
  final String transactionType; // 'receipt' | 'payment'
  final double amount;
  final String category;
  final String? description;
  final int? partyId;
  final int? userId;
  final DateTime createdAt;

  const TransactionEntity({
    required this.id,
    required this.safeId,
    required this.transactionType,
    required this.amount,
    required this.category,
    this.description,
    this.partyId,
    this.userId,
    required this.createdAt,
  });

  bool get isReceipt => transactionType == 'receipt';
  bool get isPayment => transactionType == 'payment';

  /// Signed amount: positive for receipts, negative for payments.
  double get signedAmount => isReceipt ? amount : -amount;

  TransactionEntity copyWith({
    int? id,
    int? safeId,
    String? transactionType,
    double? amount,
    String? category,
    String? description,
    int? partyId,
    int? userId,
    DateTime? createdAt,
  }) =>
      TransactionEntity(
        id: id ?? this.id,
        safeId: safeId ?? this.safeId,
        transactionType: transactionType ?? this.transactionType,
        amount: amount ?? this.amount,
        category: category ?? this.category,
        description: description ?? this.description,
        partyId: partyId ?? this.partyId,
        userId: userId ?? this.userId,
        createdAt: createdAt ?? this.createdAt,
      );
}
