import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/profit_margin_analysis_service.dart';
import '../../../data/providers/providers.dart';
/// Use case that calculates profit margins for a specific sales invoice.
class CalculateProfitMarginUseCase {
  final AppDatabase _db;

  CalculateProfitMarginUseCase(this._db);

  /// Execute margin calculation for [invoiceId]
  Future<InvoiceProfitAnalysis?> execute(int invoiceId) async {
    try {
      final items = await _db.getSalesInvoiceItems(invoiceId);
      if (items.isEmpty) return null;

      final List<LineProfitAnalysis> lines = [];
      
      for (final item in items) {
        final product = await _db.getProductById(item.productId);
        final productName = product?.name ?? 'Unknown Product';
        
        lines.add(
          LineProfitAnalysis(
            productName: productName,
            quantity: item.quantity,
            sellingPrice: item.unitPrice,
            costPrice: item.costPrice,
            lineTotal: item.total,
            // Use stored costPrice for the actual historic margin calculation.
            // SAL-1: costPrice is per BASE unit; quantity is in SALE units —
            // multiply by quantityInBase for the true physical COGS.
            lineCost: item.costPrice * item.quantity * item.quantityInBase,
          )
        );
      }

      return InvoiceProfitAnalysis(lines: lines);
      
    } catch (e) {
      return null;
    }
  }
}

final calculateProfitMarginUseCaseProvider = Provider((ref) {
  final db = ref.watch(databaseProvider);
  return CalculateProfitMarginUseCase(db);
});

final invoiceProfitAnalysisStreamProvider = StreamProvider.family<InvoiceProfitAnalysis?, int>((ref, invoiceId) async* {
  final useCase = ref.watch(calculateProfitMarginUseCaseProvider);
  yield await useCase.execute(invoiceId);
});
