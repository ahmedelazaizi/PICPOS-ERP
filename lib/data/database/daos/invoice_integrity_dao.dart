part of '../database.dart';

/// Shared invoice signing operations used by local, API, and sync writes.
extension InvoiceIntegrityDao on AppDatabase {
  Future<void> resignSalesInvoice(int invoiceId) async {
    final invoice = await (select(salesInvoices)
          ..where((row) => row.id.equals(invoiceId)))
        .getSingleOrNull();
    if (invoice == null) return;

    final hash = InvoiceIntegrityService.computeSalesInvoiceHash(
      invoiceNumber: invoice.invoiceNumber,
      invoiceDate: invoice.invoiceDate,
      total: invoice.total,
      subtotal: invoice.subtotal,
      discount: invoice.discount,
      tax: invoice.tax,
      paid: invoice.paid,
      customerId: invoice.customerId,
      userId: invoice.userId,
      paymentMethod: invoice.paymentMethod,
    );
    await (update(salesInvoices)..where((row) => row.id.equals(invoiceId)))
        .write(SalesInvoicesCompanion(integrityHash: Value(hash)));
  }

  Future<void> resignPurchaseInvoice(int invoiceId) async {
    final invoice = await (select(purchaseInvoices)
          ..where((row) => row.id.equals(invoiceId)))
        .getSingleOrNull();
    if (invoice == null) return;

    final hash = InvoiceIntegrityService.computePurchaseInvoiceHash(
      invoiceNumber: invoice.invoiceNumber,
      invoiceDate: invoice.invoiceDate,
      total: invoice.total,
      subtotal: invoice.subtotal,
      discount: invoice.discount,
      tax: invoice.tax,
      paid: invoice.paid,
      supplierId: invoice.supplierId,
      paymentMethod: invoice.paymentMethod,
    );
    await (update(purchaseInvoices)..where((row) => row.id.equals(invoiceId)))
        .write(PurchaseInvoicesCompanion(integrityHash: Value(hash)));
  }
}
