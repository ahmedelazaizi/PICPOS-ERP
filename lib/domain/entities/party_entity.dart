/// Party entity (Customer/Supplier) for domain layer
///
/// Pure domain entity - no Drift or UI dependencies
class PartyEntity {
  final int id;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final bool isCustomer;
  final bool isSupplier;
  final double balance;
  final double creditLimit;
  final String? taxNumber;
  final String? notes;
  final bool isActive;

  const PartyEntity({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.isCustomer = false,
    this.isSupplier = false,
    this.balance = 0,
    this.creditLimit = 0,
    this.taxNumber,
    this.notes,
    this.isActive = true,
  });

  /// Check if party is dual role
  bool get isDualRole => isCustomer && isSupplier;

  /// Check if has outstanding balance
  bool get hasBalance => balance != 0;

  /// Check if owes money (debit balance)
  bool get owes => balance > 0;

  /// Check if owed money (credit balance)
  bool get owed => balance < 0;

  /// Check if credit limit exceeded
  bool get creditExceeded => creditLimit > 0 && balance > creditLimit;

  /// Available credit
  double get availableCredit =>
      creditLimit > 0 ? (creditLimit - balance) : double.infinity;

  PartyEntity copyWith({
    int? id,
    String? name,
    String? phone,
    String? email,
    String? address,
    bool? isCustomer,
    bool? isSupplier,
    double? balance,
    double? creditLimit,
    String? taxNumber,
    String? notes,
    bool? isActive,
  }) {
    return PartyEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      isCustomer: isCustomer ?? this.isCustomer,
      isSupplier: isSupplier ?? this.isSupplier,
      balance: balance ?? this.balance,
      creditLimit: creditLimit ?? this.creditLimit,
      taxNumber: taxNumber ?? this.taxNumber,
      notes: notes ?? this.notes,
      isActive: isActive ?? this.isActive,
    );
  }
}
