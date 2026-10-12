// Party DTOs: summary, statement entry, AR reconciliation, aging row, balance mismatch, group-with-count.
part of '../database.dart';

/// Helper class for party summary with totals
class PartySummary {
  final int partyId;
  final String partyName;
  final bool isCustomer;
  final bool isSupplier;
  final double currentBalance;
  final double totalInvoices;
  final double totalPayments;
  final int invoiceCount;
  final int paymentCount;

  PartySummary({
    required this.partyId,
    required this.partyName,
    required this.isCustomer,
    required this.isSupplier,
    required this.currentBalance,
    required this.totalInvoices,
    required this.totalPayments,
    required this.invoiceCount,
    required this.paymentCount,
  });
}

/// Party statement entry for account statements
class PartyStatementEntry {
  final DateTime date;
  final String description;
  final String? invoiceNumber;
  final String entryType; // 'opening', 'invoice', 'payment', 'receipt'
  final double debit;
  final double credit;
  final double balance;
  final int? referenceId;
  final String? referenceType;

  PartyStatementEntry({
    required this.date,
    required this.description,
    this.invoiceNumber,
    required this.entryType,
    required this.debit,
    required this.credit,
    required this.balance,
    this.referenceId,
    this.referenceType,
  });
}

/// GAP-21: AR reconciliation result — aggregate comparison of parties.balance vs GL
class ArReconciliation {
  final double totalCardBalance;   // SUM(parties.balance) for all customers
  final double totalGlBalance;     // SUM(debit-credit) on receivables account in GL
  final double difference;         // cardBalance - glBalance (should be ~0.0)
  final int customerCount;
  final String receivablesAccountCode;
  final String receivablesAccountName;

  const ArReconciliation({
    required this.totalCardBalance,
    required this.totalGlBalance,
    required this.difference,
    required this.customerCount,
    required this.receivablesAccountCode,
    required this.receivablesAccountName,
  });

  bool get isBalanced => difference.abs() < 0.01;
}

/// GAP-22: Single row in an AR/AP aging report.
class ArAgingRow {
  final int partyId;
  final String partyName;
  final double totalBalance;
  final double bucket0_30;
  final double bucket31_60;
  final double bucket61_90;
  final double bucket90Plus;

  const ArAgingRow({
    required this.partyId,
    required this.partyName,
    required this.totalBalance,
    required this.bucket0_30,
    required this.bucket31_60,
    required this.bucket61_90,
    required this.bucket90Plus,
  });

  double get outstandingTotal => bucket0_30 + bucket31_60 + bucket61_90 + bucket90Plus;
}

/// Day-17: A single party whose `parties.balance` does not match the
/// sum of posted GL journal-entry lines on its dedicated sub-account.
class PartyBalanceMismatch {
  final int partyId;
  final String partyName;
  final bool isCustomer;
  final bool isSupplier;

  /// The balance stored directly on the `parties` row.
  final double cardBalance;

  /// SUM(debit) − SUM(credit) for all posted, non-deleted JE lines on
  /// the party's linked GL sub-account.
  final double glBalance;

  /// `cardBalance − glBalance` (positive → card is higher than GL).
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

// ═══════════════════════════════════════════════════════════════════════════
// PARTY GROUP DAO — تصنيفات العملاء والموردين
// ═══════════════════════════════════════════════════════════════════════════

/// Snapshot of a party group together with a live member count. Used by
/// the management screen so the admin can see group sizes at a glance.
class PartyGroupWithCount {
  final PartyGroup group;
  final int memberCount;
  const PartyGroupWithCount(this.group, this.memberCount);
}
