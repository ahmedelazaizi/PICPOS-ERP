// Cash-flow classification of manual / unclassified journal entries
// (audit B ACC-006, IAS 7).
//
// `getCashFlowStatement` knows the activity of an engine-written entry from its
// `reference_type`. A manual entry (reference_type NULL or any type the report
// does not know) used to be dumped into operating and labelled as customer
// receipts / supplier payments — a capital injection, a bank loan, an owner
// drawing or a cash<->bank transfer all landed there (a transfer grossed up
// BOTH sides).
//
// The rule used here, from the nature of the NON-cash legs of the same entry:
//   * no non-cash leg (cash <-> bank / safe transfer) -> transfer: excluded,
//     it is not a cash flow of the entity (IAS 7.6, cash equivalents);
//   * a counter-leg on an equity account (type 'equity') or on a
//     non-current liability (code 22*)                  -> financing (7.17);
//   * a counter-leg on a fixed asset / long-term investment (code 12*)
//                                                       -> investing (7.16);
//   * both financing and investing legs, or neither      -> operating (7.14),
//     the default; documented limitation: an entry mixing activities is not
//     split.
// Cash legs themselves are never counted as counter legs.
import 'database.dart';

enum ManualCashActivity { operating, investing, financing, transfer }

/// Pure decision, shared by the query below and the unit tests.
ManualCashActivity classifyManualCashEntry({
  required int nonCashLegs,
  required int financingLegs,
  required int investingLegs,
}) {
  if (nonCashLegs == 0) return ManualCashActivity.transfer;
  if (financingLegs > 0 && investingLegs == 0) return ManualCashActivity.financing;
  if (investingLegs > 0 && financingLegs == 0) return ManualCashActivity.investing;
  return ManualCashActivity.operating;
}

/// Classifies [entryIds] (journal entry ids that carry a cash/bank leg).
/// [cashBankIds] is the cash & equivalents account set used by the report.
Future<Map<int, ManualCashActivity>> classifyManualCashEntries(
  AppDatabase db,
  Iterable<int> entryIds,
  Set<int> cashBankIds,
) async {
  final ids = entryIds.toList();
  final result = <int, ManualCashActivity>{};
  if (ids.isEmpty) return result;
  final cashList = cashBankIds.isEmpty ? '-1' : cashBankIds.join(', ');
  for (var i = 0; i < ids.length; i += 400) {
    final chunk = ids.sublist(i, i + 400 > ids.length ? ids.length : i + 400);
    final rows = await db.customSelect(
      '''
      SELECT jel.entry_id AS eid,
             SUM(CASE WHEN jel.account_id IN ($cashList) THEN 0 ELSE 1 END) AS non_cash,
             SUM(CASE WHEN jel.account_id NOT IN ($cashList)
                       AND (a.account_type = 'equity' OR a.code LIKE '22%')
                      THEN 1 ELSE 0 END) AS fin,
             SUM(CASE WHEN jel.account_id NOT IN ($cashList)
                       AND a.code LIKE '12%'
                      THEN 1 ELSE 0 END) AS inv
      FROM journal_entry_lines jel
      INNER JOIN accounts a ON a.id = jel.account_id
      WHERE jel.entry_id IN (${chunk.join(', ')})
      GROUP BY jel.entry_id
      ''',
      readsFrom: {db.journalEntryLines, db.accounts},
    ).get();
    for (final r in rows) {
      int n(String k) => (r.data[k] as num?)?.toInt() ?? 0;
      result[r.read<int>('eid')] = classifyManualCashEntry(
        nonCashLegs: n('non_cash'),
        financingLegs: n('fin'),
        investingLegs: n('inv'),
      );
    }
  }
  return result;
}
