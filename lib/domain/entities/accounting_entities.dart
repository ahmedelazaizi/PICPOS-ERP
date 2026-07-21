
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

/// Result of the one-off branch cost-center repair (see
/// `repairBranchCostCenterAttribution`). [applied] is false for a dry-run
/// preview, true after the changes were committed. Counts describe how many
/// auto-posted rows currently on the global «عام» (GEN) centre belong to a
/// branch that has its own centre — i.e. how many would move / did move.
class BranchCostCenterRepairReport {
  final int affectedEntries;
  final int affectedLines;
  final bool applied;

  const BranchCostCenterRepairReport({
    required this.affectedEntries,
    required this.affectedLines,
    required this.applied,
  });

  bool get hasWork => affectedEntries > 0 || affectedLines > 0;

  @override
  String toString() => 'BranchCostCenterRepairReport(entries: $affectedEntries, '
      'lines: $affectedLines, applied: $applied)';
}
