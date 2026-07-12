
/// Input model for a single journal entry line.
/// Used for both manual entries and auto-posting.
class JournalLine {
  final int accountId;
  final double debit;
  final double credit;
  final String? description;
  final int? costCenterId;

  JournalLine({
    required this.accountId,
    this.debit = 0,
    this.credit = 0,
    this.description,
    this.costCenterId,
  });

  @override
  String toString() => 'JournalLine(accountId: $accountId, debit: $debit, credit: $credit)';
}
