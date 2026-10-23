import '../../../domain/models/journal_balance.dart';

/// C-1 — pre-flight for approving (posting) a draft journal entry.
///
/// Returns the Arabic reason the draft must NOT be posted, or `null` when it
/// may be. Run inside the approving transaction, before any write:
///  * soft-deleted drafts are never posted (they would move balances while
///    being excluded from every report);
///  * the lines must balance — compared in integer minor units with the same
///    tolerance the entry writer uses ([JournalBalance.isBalanced]);
///  * an entry without any amount cannot be posted.
String? draftApprovalBlocker({
  required bool isDeleted,
  required Iterable<({double debit, double credit})> lines,
}) {
  if (isDeleted) return 'القيد محذوف ولا يمكن اعتماده';
  final balance = JournalBalance.of(lines);
  if (balance.isEmpty) return 'القيد بلا مبالغ ولا يمكن اعتماده';
  if (!balance.isBalanced) {
    return 'القيد غير متوازن (مدين ${balance.debit.toStringAsFixed(2)} '
        '≠ دائن ${balance.credit.toStringAsFixed(2)}) — لا يمكن اعتماده';
  }
  return null;
}
