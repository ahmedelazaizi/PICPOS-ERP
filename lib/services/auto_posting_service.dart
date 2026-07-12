import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import '../data/database/database.dart';

/// AutoPostingService — الترحيل المحاسبي التلقائي
///
/// Hooks into the existing DAO methods to automatically generate
/// journal entries when financial transactions occur.
///
/// Supported transaction types:
/// - Sales invoices (cash / credit)
/// - Purchase invoices
/// - Receipt vouchers (سند قبض)
/// - Payment vouchers (سند صرف)
/// - Sales returns
class AutoPostingService {
  final AppDatabase _db;

  AutoPostingService(this._db);

  /// Auto-post a sales invoice based on payment method.
  /// PIR P0-04: Logs failures to failed_autoposts table instead of silently swallowing.
  Future<int?> postSaleInvoice(SalesInvoiceData sale) async {
    // Skip if already posted (check both reference types to prevent duplicates)
    if (await _db.hasAutoPostEntry('sale', sale.id)) return null;
    if (await _db.hasAutoPostEntry('sales_invoice', sale.id)) return null;

    // Determine cash vs credit — propagate costCenterId from invoice
    int? jeId;
    try {
      if (sale.paymentMethod == 'credit') {
        jeId = await _db.autoPostCreditSale(sale, costCenterId: sale.costCenterId);
      } else {
        jeId = await _db.autoPostCashSale(sale, costCenterId: sale.costCenterId);
      }
    } catch (e) {
      debugPrint('[AutoPostingService] Sale #${sale.id} JE failed: $e');
      await _logFailedAutopost(sale.id, 'sale', e.toString());
      return null;
    }

    // ISS-04 / PIR P0-03: Auto-lock invoice after successful posting
    if (jeId != null) {
      await (_db.update(_db.salesInvoices)
            ..where((i) => i.id.equals(sale.id)))
          .write(const SalesInvoicesCompanion(isLocked: Value(true)));
    }
    return jeId;
  }

  /// Auto-post a purchase invoice.
  /// PIR P0-04: Logs failures to failed_autoposts table.
  Future<int?> postPurchaseInvoice(PurchaseInvoiceData purchase) async {
    if (await _db.hasAutoPostEntry('purchase', purchase.id)) return null;
    if (await _db.hasAutoPostEntry('purchase_invoice', purchase.id)) return null;

    int? jeId;
    try {
      jeId = await _db.autoPostPurchase(purchase, costCenterId: purchase.costCenterId);
    } catch (e) {
      debugPrint('[AutoPostingService] Purchase #${purchase.id} JE failed: $e');
      await _logFailedAutopost(purchase.id, 'purchase', e.toString());
      return null;
    }

    // PIR P0-03: Lock purchase invoice after successful posting
    if (jeId != null) {
      await (_db.update(_db.purchaseInvoices)
            ..where((i) => i.id.equals(purchase.id)))
          .write(const PurchaseInvoicesCompanion(isLocked: Value(true)));
    }
    return jeId;
  }

  /// Helper — log a failed autopost to the failed_autoposts table (non-fatal).
  Future<void> _logFailedAutopost(int invoiceId, String referenceType, String error) async {
    try {
      await _db.into(_db.failedAutoposts).insert(
        FailedAutopostsCompanion.insert(
          invoiceId: invoiceId,
          referenceType: referenceType,
          errorMessage: error,
        ),
      );
    } catch (logErr) {
      debugPrint('[AutoPostingService] Failed to log autopost failure: $logErr');
    }
  }

  /// Auto-post a receipt voucher
  Future<int?> postReceipt(SafeTransactionData txn) async {
    if (txn.transactionType != 'receipt') return null;
    if (await _db.hasAutoPostEntry('receipt', txn.id)) return null;
    return _db.autoPostReceipt(txn, costCenterId: txn.costCenterId);
  }

  /// Auto-post a payment voucher
  Future<int?> postPayment(SafeTransactionData txn) async {
    if (txn.transactionType != 'payment') return null;
    if (await _db.hasAutoPostEntry('payment', txn.id)) return null;
    // C-06 pattern: also check 'payment_voucher' — the DAO inline path uses this referenceType
    if (await _db.hasAutoPostEntry('payment_voucher', txn.id)) return null;
    return _db.autoPostPayment(txn, costCenterId: txn.costCenterId);
  }

  /// Auto-post a safe transaction (receipt or payment)
  Future<int?> postSafeTransaction(SafeTransactionData txn) async {
    if (txn.transactionType == 'receipt') {
      return postReceipt(txn);
    } else if (txn.transactionType == 'payment') {
      return postPayment(txn);
    }
    return null;
  }

  /// Batch auto-post all un-posted sales invoices
  Future<int> batchPostSales() async {
    int count = 0;
    final sales = await (_db.select(
      _db.salesInvoices,
    )..where((s) => s.status.equals('completed'))).get();

    for (final sale in sales) {
      // Skip quickly if either known reference type is already posted
      if (await _db.hasAutoPostEntry('sale', sale.id)) continue;
      if (await _db.hasAutoPostEntry('sales_invoice', sale.id)) continue;
      final result = await postSaleInvoice(sale);
      if (result != null) count++;
    }
    return count;
  }

  /// Batch auto-post all un-posted purchases
  Future<int> batchPostPurchases() async {
    int count = 0;
    final purchases = await _db.select(_db.purchaseInvoices).get();

    for (final purchase in purchases) {
      // Skip quickly if either known reference type is already posted.
      // 'purchase_invoice' is used by the inline DAO path in createPurchaseInvoice();
      // 'purchase' is used by autoPostPurchase(). Both must be checked here so
      // we avoid an unnecessary autoPostPurchase() call that would only return null.
      if (await _db.hasAutoPostEntry('purchase', purchase.id)) continue;
      if (await _db.hasAutoPostEntry('purchase_invoice', purchase.id)) continue;
      final result = await postPurchaseInvoice(purchase);
      if (result != null) count++;
    }
    return count;
  }

  /// Batch auto-post all un-posted treasury transactions
  Future<int> batchPostTreasury() async {
    int count = 0;
    final transactions = await _db.select(_db.safeTransactions).get();

    for (final txn in transactions) {
      final type = txn.transactionType;
      if (type != 'receipt' && type != 'payment') continue;
      if (await _db.hasAutoPostEntry(type, txn.id)) continue;
      // Also check the inline DAO reference types ('receipt_voucher', 'payment_voucher')
      final voucherType = type == 'receipt' ? 'receipt_voucher' : 'payment_voucher';
      if (await _db.hasAutoPostEntry(voucherType, txn.id)) continue;
      final result = await postSafeTransaction(txn);
      if (result != null) count++;
    }
    return count;
  }

  /// Run all batch posting operations
  Future<Map<String, int>> batchPostAll() async {
    final salesCount = await batchPostSales();
    final purchaseCount = await batchPostPurchases();
    final treasuryCount = await batchPostTreasury();

    return {
      'sales': salesCount,
      'purchases': purchaseCount,
      'treasury': treasuryCount,
      'total': salesCount + purchaseCount + treasuryCount,
    };
  }

  /// Auto-post a sales return
  Future<int?> postSalesReturn({
    required SalesInvoiceData originalInvoice,
    required double returnAmount,
    required double cogsAmount,
    required double cashRefund,
    required double bankRefund,
    required double arRefund,
    double vatAmount = 0,
  }) async {
    // Unique key check handled inside autoPostSalesReturn DAO
    return _db.autoPostSalesReturn(
      originalInvoice: originalInvoice,
      returnAmount: returnAmount,
      cogsAmount: cogsAmount,
      cashRefund: cashRefund,
      bankRefund: bankRefund,
      arRefund: arRefund,
      vatAmount: vatAmount,
      costCenterId: originalInvoice.costCenterId,
    );
  }

  /// Auto-post a purchase return
  Future<int?> postPurchaseReturn({
    required PurchaseInvoiceData originalPurchase,
    required double returnAmount,
    double vatAmount = 0,
  }) async {
    return _db.autoPostPurchaseReturn(
      originalPurchase: originalPurchase,
      returnAmount: returnAmount,
      vatAmount: vatAmount,
      costCenterId: originalPurchase.costCenterId,
    );
  }
}
