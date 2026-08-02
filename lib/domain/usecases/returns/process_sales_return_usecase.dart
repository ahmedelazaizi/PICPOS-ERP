import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import '../../../data/database/database.dart';
import '../../entities/accounting_entities.dart';
import '../../../services/activity_logger.dart';

/// Use case for processing sales returns
///
/// Handles the complete return flow:
/// 1. Validate return items against original invoice
/// 2. Update product stock (restore returned quantities)
/// 3. Create stock movement records
/// 4. Create treasury transactions (deduct from correct safe(s))
/// 5. Update invoice status
class ProcessSalesReturnUseCase {
  final AppDatabase _db;
  final ActivityLogger _logger;

  ProcessSalesReturnUseCase(this._db, this._logger);

  /// Execute the sales return
  Future<ReturnResult> execute(SalesReturnRequest request) async {
    // 1. Validate request
    final validation = await _validate(request);
    if (!validation.isValid) {
      return ReturnResult.failure(validation.error!);
    }

    // 2. Calculate totals
    final totals = _calculateTotals(request.items);

    // 3. Process return through database
    try {
      await _db.transaction(() async {
        await _processReturn(request, totals);
      });

      return ReturnResult.success(
        returnId: request.originalInvoiceId,
        refundAmount: totals.total,
        itemsReturned: request.items.length,
      );
    } catch (e, stack) {
      debugPrint('[ReturnUseCase] Error: $e\n$stack');
      return ReturnResult.failure('فشل في معالجة المرتجع: $e');
    }
  }

  Future<void> _processReturn(
    SalesReturnRequest request,
    ReturnTotals totals,
  ) async {
    final invoice = await _db.getSalesInvoiceById(request.originalInvoiceId);
    if (invoice == null) throw Exception('فاتورة غير موجودة');

    final totalReturn = totals.total;
    double totalTaxReturn = 0;
    double totalCogsReturn = 0;

    // 1. Update product stock and create stock movements
    for (final item in request.items) {
      final product = await _db.getProductById(item.productId);
      if (product == null) continue;

      // Extract historical COGS from the original invoice item (P0 Fix)
      final originalItem = await (_db.select(_db.salesInvoiceItems)
            ..where((i) => i.id.equals(item.originalItemId)))
          .getSingleOrNull();
      final historicalCostPrice = originalItem?.costPrice ?? product.costPrice;

      // Calculate tax and COGS for this item
      final itemTax =
          (item.unitPrice * item.quantity) * (product.taxRate / 100);
      totalTaxReturn += itemTax;
      totalCogsReturn += (historicalCostPrice * item.quantity);

      // Restore stock using adjustStock — properly updates both product.currentStock AND warehouse balance
      if (product.trackInventory) {
        // Blend the returned units back in at the historical cost this
        // use-case already resolved for the COGS reversal above, so
        // valuation and the GL stay on the same number. Must precede
        // adjustStock — updateProductWAC reads the pre-return stock.
        await _db.updateProductWAC(
          productId: item.productId,
          newQuantity: item.quantity,
          newUnitCost: historicalCostPrice,
        );
        await _db.adjustStock(
          productId: item.productId,
          warehouseId: invoice.warehouseId,
          quantity: item.quantity, // positive = stock in
          type: 'return',
          referenceType: 'sales_return',
          referenceId: request.originalInvoiceId,
          unitCost: historicalCostPrice,
          notes: request.returnReason.isNotEmpty
              ? 'مرتجع: ${request.returnReason}'
              : 'مرتجع فاتورة ${invoice.invoiceNumber}',
          userId: request.userId,
        );
      }
    }

    // 2. Handle Financials (Treasury & AR)
    double cashRefund = 0;
    double bankRefund = 0;
    double arRefund = 0;

    if (request.refundMethod == 'credit' && invoice.customerId != null) {
      arRefund = totalReturn;
      await _db.adjustPartyBalance(invoice.customerId!, -totalReturn);
    } else {
      final paymentMethod = invoice.paymentMethod;
      if (paymentMethod == 'multiple' || paymentMethod == 'mixed') {
        final totalPaid = invoice.cashPaid + invoice.bankPaid;
        if (totalPaid > 0) {
          cashRefund = totalReturn * (invoice.cashPaid / totalPaid);
          bankRefund = totalReturn * (invoice.bankPaid / totalPaid);
        } else {
          cashRefund = totalReturn;
        }
      } else if (paymentMethod == 'transfer' ||
          paymentMethod == 'card' ||
          paymentMethod == 'bank') {
        bankRefund = totalReturn;
      } else {
        cashRefund = totalReturn;
      }

      // Proceed with Treasury transactions
      if (cashRefund > 0) {
        final cashSafe = await _db.getDefaultSafeByType('cash');
        if (cashSafe != null) {
          // 069 (D5-003): atomic delta update to avoid PG lost-update.
          final newBalance = cashSafe.balance - cashRefund;
          await _db.adjustSafeBalance(cashSafe.id, -cashRefund);
          await _db.createSafeTransaction(
            SafeTransactionsCompanion.insert(
              voucherNumber:
                  'RET${DateTime.now().year}${invoice.id.toString().padLeft(6, '0')}',
              safeId: cashSafe.id,
              transactionType: 'payment',
              category: 'sales_return',
              amount: cashRefund,
              balanceAfter: newBalance,
              referenceType: const Value('sales_return'),
              referenceId: Value(invoice.id),
              description: Value('مرتجع نقدي فاتورة ${invoice.invoiceNumber}'),
              userId: Value(request.userId),
            ),
          );
        }
      }

      if (bankRefund > 0) {
        final bankSafe = await _db.getDefaultSafeByType('bank');
        if (bankSafe != null) {
          // 069 (D5-003): atomic delta update to avoid PG lost-update.
          final newBalance = bankSafe.balance - bankRefund;
          await _db.adjustSafeBalance(bankSafe.id, -bankRefund);
          await _db.createSafeTransaction(
            SafeTransactionsCompanion.insert(
              voucherNumber:
                  'RET-B${DateTime.now().year}${invoice.id.toString().padLeft(6, '0')}',
              safeId: bankSafe.id,
              transactionType: 'payment',
              category: 'sales_return',
              amount: bankRefund,
              balanceAfter: newBalance,
              referenceType: const Value('sales_return'),
              referenceId: Value(invoice.id),
              description: Value('مرتجع بنكي فاتورة ${invoice.invoiceNumber}'),
              userId: Value(request.userId),
            ),
          );
        }
      }
    }

    // 3. Create Accounting Journal Entry (REVERSAL) via accountingDao
    try {
      // Use mapped account purposes instead of hardcoded codes
      final cashAcc = await _db.getAccountByPurpose('cash');
      final bankAcc = await _db.getAccountByPurpose('bank');
      final arAcc = await _db.getAccountByPurpose('receivables');
      final salesAcc = await _db.getAccountByPurpose('sales');
      final taxAcc = await _db.getAccountByPurpose('output_vat');
      final invAcc = await _db.getAccountByPurpose('inventory');
      final cogsAcc = await _db.getAccountByPurpose('cogs');
      final salesReturnAcc = await _db.getAccountByPurpose('sales_return');

      final List<JournalLine> lines = [];

      // Revenue reversal — use sales_return account if available, otherwise debit sales
      final revenueAccount = salesReturnAcc ?? salesAcc;
      if (revenueAccount != null) {
        lines.add(JournalLine(accountId: revenueAccount.id, debit: totalReturn - totalTaxReturn, description: 'مرتجع مبيعات فاتورة ${invoice.invoiceNumber}'));
      }
      if (totalTaxReturn > 0 && taxAcc != null) {
        lines.add(JournalLine(accountId: taxAcc.id, debit: totalTaxReturn, description: 'مرتجع ضريبة فاتورة ${invoice.invoiceNumber}'));
      }
      if (totalCogsReturn > 0 && invAcc != null) {
        lines.add(JournalLine(accountId: invAcc.id, debit: totalCogsReturn, description: 'إعادة للمخزون - مرتجع فاتورة ${invoice.invoiceNumber}'));
      }
      if (arRefund > 0 && arAcc != null) {
        lines.add(JournalLine(accountId: arAcc.id, credit: arRefund, description: 'تخفيض حساب عميل'));
      }
      if (cashRefund > 0 && cashAcc != null) {
        lines.add(JournalLine(accountId: cashAcc.id, credit: cashRefund, description: 'صرف نقدي مرتجع'));
      }
      if (bankRefund > 0 && bankAcc != null) {
        lines.add(JournalLine(accountId: bankAcc.id, credit: bankRefund, description: 'صرف بنكي مرتجع'));
      }
      if (totalCogsReturn > 0 && cogsAcc != null) {
        lines.add(JournalLine(accountId: cogsAcc.id, credit: totalCogsReturn, description: 'تخفيض تكلفة المبيعات'));
      }

      if (lines.isNotEmpty) {
        await _db.createJournalEntry(
          description: 'قيد مبيعات مرتجعة لفاتورة ${invoice.invoiceNumber}',
          date: DateTime.now(),
          lines: lines,
          referenceType: 'sales_return',
          referenceId: invoice.id,
          isAutoPosted: true,
          costCenterId: invoice.costCenterId,
        );
      }
    } catch (e) {
      debugPrint('[ReturnUseCase] Accounting Error (Non-Fatal): $e');
    }

    // 5. Update invoice status
    final isFullReturn = request.isFullReturn;
    final newStatus = isFullReturn ? 'returned' : 'partial_return';

    await (_db.update(_db.salesInvoices)..where((i) => i.id.equals(invoice.id)))
        .write(SalesInvoicesCompanion(status: Value(newStatus)));

    // 6. Log Activity
    final userName = await _getUserName(request.userId);
    await _logger.log(
      userId: request.userId,
      userName: userName,
      action: 'return',
      entityType: 'invoice',
      entityId: invoice.id,
      description:
          'مرتجع مبيعات ${isFullReturn ? 'كلي' : 'جزئي'} لفاتورة ${invoice.invoiceNumber}. المبلغ: ${totals.total}',
      amount: totals.total,
    );
  }

  Future<String> _getUserName(int userId) async {
    final user = await (_db.select(
      _db.users,
    )..where((u) => u.id.equals(userId))).getSingleOrNull();
    return user?.displayName ?? 'Unknown';
  }

  ReturnTotals _calculateTotals(List<ReturnItemInput> items) {
    double subtotal = 0;
    for (final item in items) {
      subtotal += item.quantity * item.unitPrice;
    }
    return ReturnTotals(subtotal: subtotal, itemCount: items.length);
  }

  Future<ValidationResult> _validate(SalesReturnRequest request) async {
    if (request.items.isEmpty) {
      return const ValidationResult.invalid('لا توجد منتجات للإرجاع');
    }

    if (request.originalInvoiceId <= 0) {
      return const ValidationResult.invalid('رقم الفاتورة الأصلية غير صحيح');
    }

    // Verify invoice exists
    final invoice = await _db.getSalesInvoiceById(request.originalInvoiceId);
    if (invoice == null) {
      return const ValidationResult.invalid('الفاتورة الأصلية غير موجودة');
    }

    // Verify invoice is not from a delivery app
    if (invoice.saleType != 'default') {
      return const ValidationResult.invalid(
        'لا يمكن إرجاع فواتير شركات التوصيل',
      );
    }

    // Verify invoice is not already fully returned
    if (invoice.status == 'returned') {
      return const ValidationResult.invalid('الفاتورة مرتجعة بالكامل بالفعل');
    }

    for (final item in request.items) {
      if (item.quantity <= 0) {
        return const ValidationResult.invalid(
          'الكمية المرتجعة يجب أن تكون أكبر من صفر',
        );
      }
    }

    return const ValidationResult.valid();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// REQUEST / RESPONSE CLASSES
// ═══════════════════════════════════════════════════════════════════════════

/// Sales return request data
class SalesReturnRequest {
  final int originalInvoiceId;
  final int? customerId;
  final List<ReturnItemInput> items;
  final String returnReason;
  final String refundMethod; // cash, credit, exchange
  final String? notes;
  final int userId;
  final bool isFullReturn;

  const SalesReturnRequest({
    required this.originalInvoiceId,
    this.customerId,
    required this.items,
    required this.returnReason,
    this.refundMethod = 'cash',
    this.notes,
    this.userId = 1,
    this.isFullReturn = false,
  });
}

/// Return item input
class ReturnItemInput {
  final int originalItemId;
  final int productId;
  final String productName;
  final double quantity;
  final double unitPrice;

  const ReturnItemInput({
    required this.originalItemId,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
  });

  double get total => quantity * unitPrice;
}

/// Return totals
class ReturnTotals {
  final double subtotal;
  final int itemCount;

  const ReturnTotals({required this.subtotal, required this.itemCount});

  double get total => subtotal;
}

/// Return result
sealed class ReturnResult {
  const ReturnResult();

  factory ReturnResult.success({
    required int returnId,
    required double refundAmount,
    required int itemsReturned,
  }) = ReturnSuccess;

  factory ReturnResult.failure(String error) = ReturnFailure;

  bool get isSuccess => this is ReturnSuccess;
  bool get isFailure => this is ReturnFailure;
}

class ReturnSuccess extends ReturnResult {
  final int returnId;
  final double refundAmount;
  final int itemsReturned;

  const ReturnSuccess({
    required this.returnId,
    required this.refundAmount,
    required this.itemsReturned,
  });
}

class ReturnFailure extends ReturnResult {
  final String error;
  const ReturnFailure(this.error);
}

/// Validation result
class ValidationResult {
  final bool isValid;
  final String? error;

  const ValidationResult.valid() : isValid = true, error = null;
  const ValidationResult.invalid(this.error) : isValid = false;
}
