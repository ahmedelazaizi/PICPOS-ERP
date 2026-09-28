/// A party whose stored balance differs from its posted ledger balance.
class PartyBalanceMismatch {
  final int partyId;
  final String partyName;
  final bool isCustomer;
  final bool isSupplier;
  final double cardBalance;
  final double glBalance;
  final double delta;

  const PartyBalanceMismatch({
    required this.partyId,
    required this.partyName,
    required this.isCustomer,
    required this.isSupplier,
    required this.cardBalance,
    required this.glBalance,
    required this.delta,
  });

  bool get isBalanced => delta.abs() < 0.01;
}
