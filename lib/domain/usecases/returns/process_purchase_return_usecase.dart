import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import '../../../data/database/database_barrel.dart';
import '../../../domain/entities/accounting_entities.dart';
import '../../../services/activity_logger.dart';

/// Use case for processing purchase returns
class ProcessPurchaseReturnUseCase {
  final AppDatabase _db;
  final ActivityLogger _logger;

  ProcessPurchaseReturnUseCase(this._db, this._logger);

  /// Execute the purchase return
  Future<PurchaseReturnResult> execute(PurchaseReturnRequest request) async {
    // 1. Validation
    if (request.items.isEmpty) {
      return PurchaseReturnResult.failure('لا توجد أصناف للإرجاع');
    }

    try {
      await _db.transaction(() async {
        await _processReturn(request);
      });

      return PurchaseReturnResult.success(
        returnId: request.originalInvoiceId,
        itemsReturned: request.items.length,
      );
    } catch (e, stack) {
      debugPrint('[PurchaseReturnUseCase] Error: $e\n$stack');
      return PurchaseReturnResult.failure('فشل في معالجة مرتجع المشتريات: $e');
    }
  }

  Future<void> _processReturn(PurchaseReturnRequest request) async {
    final invoice = await _db.getPurchaseInvoiceById(request.originalInvoiceId);
    if (invoice == null) throw Exception('فاتورة مشتريات غير موجودة');

    double totalReturnAmount = 0;
    double totalTaxReturn = 0;

    // 1. Update stock and check items
    for (final item in request.items) {
      final product = await _db.getProductById(item.productId);
      if (product == null) continue;

      totalReturnAmount += (item.unitCost * item.quantity);
      // Estimate tax based on product rate
      final itemTax = (item.unitCost * item.quantity) * (product.taxRate / 100);
      totalTaxReturn += itemTax;

      // Deduct stock using adjustStock — properly updates product.currentStock AND warehouse balance
      if (product.trackInventory) {
        
        // 1. First reverse the WAC impact of the returned purchase line
        await _db.reverseProductWAC(
          productId: item.productId,
          reversedQuantity: item.quantity,
          reversedUnitCost: item.unitCost,
        );

        // 2. Adjust stock
        await _db.adjustStock(
          productId: item.productId,
          warehouseId: invoice.warehouseId,
          quantity: -item.quantity, // negative = stock out (returning to supplier)
          type: 'return',
          referenceType: 'purchase_return',
          referenceId: request.originalInvoiceId,
          notes: request.returnReason.isNotEmpty
              ? 'مرتجع مورد: ${request.returnReason}'
              : 'مرتجع فاتورة مشتريات ${invoice.invoiceNumber}',
          userId: request.userId,
        );
      }
    }

    final totalWithTax = totalReturnAmount + totalTaxReturn;

    // 2. Financial Adjustments
    double cashReceived = 0;
    double bankReceived = 0;
    double apReduction = 0;

    if (request.refundMethod == 'credit') {
      apReduction = totalWithTax;
      await _db.adjustPartyBalance(
        invoice.supplierId,
        -totalWithTax,
      ); // Reduce debt to supplier
    } else {
      // Logic for cash/bank refund
      if (request.refundMethod == 'bank') {
        bankReceived = totalWithTax;
      } else {
        cashReceived = totalWithTax;
      }

      // Create Treasury Transaction (Receipt from supplier)
      if (cashReceived > 0) {
        final cashSafe = await _db.getDefaultSafeByType('cash');
        if (cashSafe != null) {
          // 069 (D5-003): atomic delta update to avoid PG lost-update.
          final newBalance = cashSafe.balance + cashReceived;
          await _db.adjustSafeBalance(cashSafe.id, cashReceived);
          await _db.createSafeTransaction(
            SafeTransactionsCompanion.insert(
              voucherNumber:
                  'PRET${DateTime.now().year}${invoice.id.toString().padLeft(6, '0')}',
              safeId: cashSafe.id,
              transactionType: 'receipt',
              category: 'purchase_return',
              amount: cashReceived,
              balanceAfter: newBalance,
              referenceType: const Value('purchase_return'),
              referenceId: Value(invoice.id),
              description: Value(
                'استرداد نقدي مرتجع مشتريات ${invoice.invoiceNumber}',
              ),
              userId: Value(request.userId),
            ),
          );
        }
      }

      if (bankReceived > 0) {
        final bankSafe = await _db.getDefaultSafeByType('bank');
        if (bankSafe != null) {
          // 069 (D5-003): atomic delta update to avoid PG lost-update.
          final newBalance = bankSafe.balance + bankReceived;
          await _db.adjustSafeBalance(bankSafe.id, bankReceived);
          await _db.createSafeTransaction(
            SafeTransactionsCompanion.insert(
              voucherNumber:
                  'PRET-B${DateTime.now().year}${invoice.id.toString().padLeft(6, '0')}',
              safeId: bankSafe.id,
              transactionType: 'receipt',
              category: 'purchase_return',
              amount: bankReceived,
              balanceAfter: newBalance,
              referenceType: const Value('purchase_return'),
              referenceId: Value(invoice.id),
              description: Value(
                'استرداد بنكي مرتجع مشتريات ${invoice.invoiceNumber}',
              ),
              userId: Value(request.userId),
            ),
          );
        }
      }
    }

    // 3. Accounting Journal Entry
    try {
      // Use mapped account purposes instead of hardcoded codes
      final cashAcc = await _db.getAccountByPurpose('cash');
      final bankAcc = await _db.getAccountByPurpose('bank');
      final apAcc = await _db.getAccountByPurpose('payables');
      final inventoryAcc = await _db.getAccountByPurpose('inventory');
      final taxAcc = await _db.getAccountByPurpose('input_vat');
      final purchaseReturnAcc = await _db.getAccountByPurpose('purchase_return');

      if (inventoryAcc != null) {
        final List<JournalLine> lines = [];

        // Inventory Reduction (Credit)
        lines.add(
          JournalLine(
            accountId: inventoryAcc.id,
            debit: 0,
            credit: totalReturnAmount,
            description:
                'تخفيض المخزون - مرتجع مشتريات ${invoice.invoiceNumber}',
          ),
        );

        // Tax Reversal (Credit Input Tax)
        if (totalTaxReturn > 0 && taxAcc != null) {
          lines.add(
            JournalLine(
              accountId: taxAcc.id,
              debit: 0,
              credit: totalTaxReturn,
              description:
                  'عكس ضريبة مدخلات - مرتجع مشتريات ${invoice.invoiceNumber}',
            ),
          );
        }

        // Debit: AP or Cash/Bank
        if (apReduction > 0 && apAcc != null) {
          lines.add(
            JournalLine(
              accountId: apAcc.id,
              debit: apReduction,
              credit: 0,
              description:
                  'تخفيض مديونية المورد - مرتجع فاتورة ${invoice.invoiceNumber}',
            ),
          );
        }
        if (cashReceived > 0 && cashAcc != null) {
          lines.add(
            JournalLine(
              accountId: cashAcc.id,
              debit: cashReceived,
              credit: 0,
              description:
                  'استلام نقدي - مرتجع فاتورة ${invoice.invoiceNumber}',
            ),
          );
        }
        if (bankReceived > 0 && bankAcc != null) {
          lines.add(
            JournalLine(
              accountId: bankAcc.id,
              debit: bankReceived,
              credit: 0,
              description:
                  'استلام بنكي - مرتجع فاتورة ${invoice.invoiceNumber}',
            ),
          );
        }

        await _db.createJournalEntry(
          description: 'قيد مشتريات مرتجعة - فاتورة ${invoice.invoiceNumber}',
          date: DateTime.now(),
          lines: lines,
          referenceType: 'purchase_return',
          referenceId: invoice.id,
          isAutoPosted: true,
          costCenterId: invoice.costCenterId,
        );
      }
    } catch (e) {
      debugPrint('[PurchaseReturnUseCase] Accounting Error: $e');
    }

    // 4. Update purchase invoice status
    final isFullReturn = request.isFullReturn;
    final newStatus = isFullReturn ? 'returned' : 'partial_return';

    await (_db.update(_db.purchaseInvoices)
          ..where((i) => i.id.equals(invoice.id)))
        .write(PurchaseInvoicesCompanion(status: Value(newStatus)));

    // 5. Log Activity
    final user = await (_db.select(
      _db.users,
    )..where((u) => u.id.equals(request.userId))).getSingleOrNull();
    final userName = user?.displayName ?? 'Unknown';

    await _logger.log(
      userId: request.userId,
      userName: userName,
      action: 'purchase_return',
      entityType: 'purchase_invoice',
      entityId: invoice.id,
      description:
          'مرتجع مشتريات ${isFullReturn ? 'كلي' : 'جزئي'} من المورد ${invoice.supplierId} لفاتورة ${invoice.invoiceNumber}. المبلغ: $totalWithTax',
      amount: totalWithTax,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DATA MODELS
// ═══════════════════════════════════════════════════════════════════════════

class PurchaseReturnRequest {
  final int originalInvoiceId;
  final List<PurchaseReturnItemInput> items;
  final String returnReason;
  final String refundMethod; // cash, bank, credit
  final int userId;
  final bool isFullReturn;

  const PurchaseReturnRequest({
    required this.originalInvoiceId,
    required this.items,
    this.returnReason = '',
    this.refundMethod = 'cash',
    this.userId = 1,
    this.isFullReturn = false,
  });
}

class PurchaseReturnItemInput {
  final int productId;
  final double quantity;
  final double unitCost;

  const PurchaseReturnItemInput({
    required this.productId,
    required this.quantity,
    required this.unitCost,
  });
}

sealed class PurchaseReturnResult {
  const PurchaseReturnResult();
  factory PurchaseReturnResult.success({
    required int returnId,
    required int itemsReturned,
  }) = PurchaseReturnSuccess;
  factory PurchaseReturnResult.failure(String message) = PurchaseReturnFailure;
}

class PurchaseReturnSuccess extends PurchaseReturnResult {
  final int returnId;
  final int itemsReturned;
  const PurchaseReturnSuccess({
    required this.returnId,
    required this.itemsReturned,
  });
}

class PurchaseReturnFailure extends PurchaseReturnResult {
  final String message;
  const PurchaseReturnFailure(this.message);
}
