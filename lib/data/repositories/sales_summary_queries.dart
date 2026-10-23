// Sales summary aggregates (audit B RPT-005).
//
// Extracted from `SalesRepositoryImpl.getSummary` so the file-size ratchet is
// not grown. Rules enforced here:
//  * the range is closed at the LAST SECOND of [toDate] (columns are stored in
//    epoch seconds and `BETWEEN` is inclusive): an invoice stamped exactly at
//    the next midnight belongs to the next day and is counted once there;
//  * `paid` uses the same filters as the sales total (live, non-deleted,
//    returns signed negative) so `due = sales - paid` mixes no bases.
import '../database/database.dart';

class SalesSummaryRaw {
  const SalesSummaryRaw({
    required this.totalSales,
    required this.totalPaid,
    required this.invoiceCount,
  });

  final double totalSales;
  final double totalPaid;
  final int invoiceCount;
}

Future<SalesSummaryRaw> querySalesSummary(
  AppDatabase db, {
  required DateTime fromDate,
  required DateTime toDate,
}) async {
  final start = DateTime(fromDate.year, fromDate.month, fromDate.day);
  final end = DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59);

  final totalSales = await db.getTotalSales(from: start, to: end);
  final invoiceCount = await db.getSalesCount(from: start, to: end);

  final result = await db.customSelect(
    "SELECT COALESCE(SUM(CASE WHEN sale_type = 'return' THEN -paid ELSE paid END), 0) AS paid "
    'FROM sales_invoices WHERE invoice_date BETWEEN ? AND ? '
    'AND is_deleted = ${db.sqlBool(false)}',
    variables: [db.dateVar(start), db.dateVar(end)],
    readsFrom: {db.salesInvoices},
  ).getSingle();
  final totalPaid = (result.data['paid'] as num?)?.toDouble() ?? 0.0;

  return SalesSummaryRaw(
    totalSales: totalSales,
    totalPaid: totalPaid,
    invoiceCount: invoiceCount,
  );
}
