import 'package:drift/drift.dart';
import '../database/database.dart';
import '../../core/utils/financial_utils.dart';
import '../../domain/entities/cart_item_entity.dart';
import '../../domain/usecases/sales/calculate_invoice_totals_usecase.dart';

class SalesInvoiceEditReconciler {
  const SalesInvoiceEditReconciler(this._db);

  final AppDatabase _db;

  Future<({double subtotal, InvoiceTotals totals})> replaceLines(
    SalesInvoiceData oldInvoice,
    int invoiceId,
    int warehouseId,
    List<CartItemEntity> items,
  ) async {
    final currentCosts = await _captureCurrentCosts(items);
    final previousLines = await _db.getSalesInvoiceItems(invoiceId);
    await _restoreOldStock(oldInvoice, invoiceId, previousLines);
    await (_db.delete(_db.salesInvoiceItems)
          ..where((line) => line.invoiceId.equals(invoiceId)))
        .go();

    final invoiceDiscount = oldInvoice.discount -
        items.fold<double>(0, (sum, item) => sum + item.discountAmount);
    final discountBase = items.fold<double>(
      0,
      (sum, item) => sum + item.totalBeforeTax,
    );
    final discountPercent = discountBase > 0
        ? (invoiceDiscount < 0 ? 0 : invoiceDiscount) / discountBase * 100
        : 0.0;
    final pricesIncludeTax =
        await _db.getSettingValue('prices_include_tax') == 'true';
    final totals = CalculateInvoiceTotalsUseCase().execute(
      items: items,
      invoiceDiscountPercent: discountPercent,
      pricesIncludeTax: pricesIncludeTax,
    );
    final lineAmounts = FinancialUtils.calculateInvoiceTotals(
      items: items
          .map((item) => (
                quantity: item.quantity,
                unitPrice: item.effectivePrice,
                taxRatePercent: item.taxRate,
              ))
          .toList(),
      globalDiscountAmount: invoiceDiscount < 0 ? 0 : invoiceDiscount,
      pricesIncludeTax: pricesIncludeTax,
      lineDiscountAmounts: items.map((item) => item.discountAmount).toList(),
    );
    await _insertEditedLines(_SalesInvoiceEditLines(
      invoiceId: invoiceId,
      warehouseId: warehouseId,
      items: items,
      costSnapshots: currentCosts,
      amounts: lineAmounts,
    ));
    return (
      subtotal: pricesIncludeTax
          ? FinancialUtils.round(totals.subtotal - totals.taxAmount)
          : totals.subtotal,
      totals: totals,
    );
  }

  Future<Map<int, double>> _captureCurrentCosts(
    List<CartItemEntity> items,
  ) async {
    final costs = <int, double>{};
    for (final item in items) {
      if (costs.containsKey(item.productId)) continue;
      final product = await _db.getProductById(item.productId);
      costs[item.productId] = product?.costPrice ?? 0.0;
    }
    return costs;
  }

  Future<void> _restoreOldStock(
    SalesInvoiceData invoice,
    int invoiceId,
    List<SalesInvoiceItem> oldLines,
  ) async {
    for (final line in oldLines) {
      final product = await _db.getProductById(line.productId);
      if (product == null || !product.trackInventory) continue;
      final baseQty = line.quantityInBase > 0 ? line.quantityInBase : 1.0;
      final restoredQty = line.quantity * baseQty;
      await _db.updateProductWAC(
        productId: line.productId,
        newQuantity: restoredQty,
        newUnitCost: line.costPrice,
      );
      await _db.adjustStock(
        productId: line.productId,
        warehouseId: invoice.warehouseId,
        quantity: restoredQty,
        type: 'edit_reversal',
        referenceType: 'sales_invoice',
        referenceId: invoiceId,
        unitCost: line.costPrice,
        notes: 'عكس الكمية لتعديل فاتورة مبيعات #$invoiceId',
      );
    }
  }

  Future<void> _insertEditedLines(_SalesInvoiceEditLines edit) async {
    for (var index = 0; index < edit.items.length; index++) {
      final item = edit.items[index];
      final product = await _db.getProductById(item.productId);
      final unitCost = edit.costSnapshots[item.productId] ?? 0.0;
      final lineTax = edit.amounts.lineTaxes[index];
      await _db.into(_db.salesInvoiceItems).insert(SalesInvoiceItemsCompanion.insert(
        invoiceId: edit.invoiceId,
        productId: item.productId,
        quantity: item.quantity,
        unitName: Value(item.selectedUnitName),
        quantityInBase: Value(item.quantityInBase),
        unitPrice: item.unitPrice,
        costPrice: Value(unitCost),
        discount: Value(item.discountAmount),
        total: FinancialUtils.round(edit.amounts.lineNets[index] + lineTax),
        taxRate: Value(item.taxRate),
        taxAmount: Value(lineTax),
        note: Value(item.note),
      ));
      if (product == null || !product.trackInventory) continue;
      await _db.adjustStock(
        productId: item.productId,
        warehouseId: edit.warehouseId,
        quantity: -(item.quantity * item.quantityInBase),
        type: 'edit_adjustment',
        referenceType: 'sales_invoice',
        referenceId: edit.invoiceId,
        unitCost: unitCost,
        notes: 'تعديل فاتورة مبيعات #${edit.invoiceId}',
      );
    }
  }

  Future<void> reconcilePartyBalance(
    SalesInvoiceData oldInvoice,
    int? customerId,
    double total,
    double paid,
  ) async {
    final oldDue = oldInvoice.total - oldInvoice.paid;
    final newDue = total - paid;
    if (oldInvoice.customerId == customerId) {
      if (customerId != null && newDue != oldDue) {
        await _db.adjustPartyBalance(customerId, newDue - oldDue);
      }
      return;
    }
    if (oldInvoice.customerId != null && oldDue != 0) {
      await _db.adjustPartyBalance(oldInvoice.customerId!, -oldDue);
    }
    if (customerId != null && newDue != 0) {
      await _db.adjustPartyBalance(customerId, newDue);
    }
  }
}

class _SalesInvoiceEditLines {
  const _SalesInvoiceEditLines({
    required this.invoiceId,
    required this.warehouseId,
    required this.items,
    required this.costSnapshots,
    required this.amounts,
  });

  final int invoiceId;
  final int warehouseId;
  final List<CartItemEntity> items;
  final Map<int, double> costSnapshots;
  final ({
    double subtotal,
    double totalDiscount,
    double totalTax,
    double grandTotal,
    List<double> lineNets,
    List<double> lineTaxes,
  }) amounts;
}
