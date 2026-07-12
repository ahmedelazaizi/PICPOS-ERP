import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/treasury_repository.dart';

/// Request model for the Cashflow Statement
class CashFlowStatementRequest {
  final DateTime fromDate;
  final DateTime toDate;
  final int? costCenterId;

  const CashFlowStatementRequest({
    required this.fromDate,
    required this.toDate,
    this.costCenterId,
  });
}

/// Result model containing categorized cash flows
class CashFlowStatementResult {
  final double totalInflows;
  final double totalOutflows;
  final double netFlow;
  final Map<String, double> inflowsByCategory;
  final Map<String, double> outflowsByCategory;

  const CashFlowStatementResult({
    required this.totalInflows,
    required this.totalOutflows,
    required this.netFlow,
    required this.inflowsByCategory,
    required this.outflowsByCategory,
  });
}

/// Use case that calculates cash flow statistics from a stream of transactions.
/// Replaces the inline presentation logic in treasury_screen _CashFlowTab.
class GetCashFlowStatementUseCase {
  
  /// Categorizes a list of transactions into a cashflow statement result
  CashFlowStatementResult executeFromTransactions(List<TransactionData> transactions) {
    if (transactions.isEmpty) {
      return const CashFlowStatementResult(
        totalInflows: 0,
        totalOutflows: 0,
        netFlow: 0,
        inflowsByCategory: {},
        outflowsByCategory: {},
      );
    }

    final receipts = transactions.where((t) => t.transactionType == 'receipt');
    final payments = transactions.where((t) => t.transactionType != 'receipt');

    final totalIn = receipts.fold<double>(0, (s, t) => s + t.amount);
    final totalOut = payments.fold<double>(0, (s, t) => s + t.amount);
    final netFlow = totalIn - totalOut;

    final Map<String, double> catIn = {};
    final Map<String, double> catOut = {};
    
    for (final t in receipts) {
      catIn[t.category] = (catIn[t.category] ?? 0) + t.amount;
    }
    for (final t in payments) {
      catOut[t.category] = (catOut[t.category] ?? 0) + t.amount;
    }

    return CashFlowStatementResult(
      totalInflows: totalIn,
      totalOutflows: totalOut,
      netFlow: netFlow,
      inflowsByCategory: catIn,
      outflowsByCategory: catOut,
    );
  }
}

final getCashFlowStatementUseCaseProvider = Provider((ref) {
  return GetCashFlowStatementUseCase();
});
