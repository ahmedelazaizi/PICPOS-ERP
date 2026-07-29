import '../../domain/entities/shift_closing_snapshot.dart';
import '../../domain/repositories/printers_repository.dart';
import '../invoice_generator.dart';

/// Prints a shift-closing report from a [ShiftClosingSnapshot].
///
/// Both the close path and the reprint path go through here, which is what
/// guarantees a reprint is the same document rather than a lookalike rebuilt
/// from a second set of assumptions. The close path builds the snapshot,
/// persists it, and prints from it; the reprint path loads the stored one and
/// prints from that.
Future<void> printShiftClosingSnapshot({
  required ShiftClosingSnapshot snapshot,
  double fontScale = 1.0,
  IPrintersRepository? printersRepo,
}) {
  return InvoiceGenerator.printShiftClosingReport(
    invoiceCount: snapshot.invoiceCount,
    totalSales: snapshot.totalSales,
    systemCash: snapshot.systemCash,
    systemCard: snapshot.systemCard,
    actualCash: snapshot.actualCash,
    actualCard: snapshot.actualCard,
    cashVariance: snapshot.cashVariance,
    cardVariance: snapshot.cardVariance,
    totalVariance: snapshot.totalVariance,
    systemClick: snapshot.systemClick,
    actualClick: snapshot.actualClick,
    clickVariance: snapshot.clickVariance,
    totalExpenses: snapshot.totalExpenses,
    cashRefunds: snapshot.cashRefunds,
    cashIncome: snapshot.cashIncome,
    creditSales: snapshot.creditSales,
    creditSalesCount: snapshot.creditSalesCount,
    openingBalance: snapshot.openingBalance,
    fontScale: fontScale,
    employeeName: snapshot.employeeName,
    companyName: snapshot.companyName,
    printersRepo: printersRepo,
  );
}
