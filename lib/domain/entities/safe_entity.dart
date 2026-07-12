/// Domain entity representing a treasury safe (cash register / bank account).
class SafeEntity {
  final int id;
  final String name;
  final String type; // 'cash' | 'bank'
  final double balance;
  final bool isDefault;
  final String? bankName;
  final String? accountNumber;
  final bool isActive;

  const SafeEntity({
    required this.id,
    required this.name,
    required this.type,
    required this.balance,
    this.isDefault = false,
    this.bankName,
    this.accountNumber,
    this.isActive = true,
  });

  bool get isCash => type == 'cash';
  bool get isBank => type == 'bank';

  SafeEntity copyWith({
    int? id,
    String? name,
    String? type,
    double? balance,
    bool? isDefault,
    String? bankName,
    String? accountNumber,
    bool? isActive,
  }) =>
      SafeEntity(
        id: id ?? this.id,
        name: name ?? this.name,
        type: type ?? this.type,
        balance: balance ?? this.balance,
        isDefault: isDefault ?? this.isDefault,
        bankName: bankName ?? this.bankName,
        accountNumber: accountNumber ?? this.accountNumber,
        isActive: isActive ?? this.isActive,
      );
}
