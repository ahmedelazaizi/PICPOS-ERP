import 'dart:async' show unawaited;
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import '../database/database.dart';
import '../../core/constants/app_constants.dart';
import '../../domain/repositories/returns_repository.dart';
import '../../services/accounting_service.dart';
import '../../services/generators/base_generator.dart' show InvoiceItem;
import '../../domain/entities/product_entity.dart';
import '../../domain/entities/accounting_entities.dart';
import '../../services/client_write_interceptor.dart';
import '../../services/network_service.dart';
import '../../core/utils/uuid_v7.dart';
import '../database/sync_interceptor.dart';

class ReturnsRepositoryImpl implements IReturnsRepository {
  final AppDatabase _db;
  final AccountingService _accountingService;

  ReturnsRepositoryImpl(this._db, this._accountingService);

  @override
  Future<List<SalesInvoiceData>> getInvoicesForReturn({
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    final invoices = await _db.getSalesByDateRange(fromDate, toDate);
    debugPrint('[ReturnsRepo] getInvoicesForReturn: total fetched=${invoices.length}, fromDate=$fromDate, toDate=$toDate');
    final filtered = invoices.where((invoice) {
        if (invoice.total <= 0) return false;           // skip returns & zero invoices
        if (invoice.status == 'returned') return false;  // already fully returned
        if (invoice.status == 'cancelled') return false; // cancelled invoices
        if (invoice.saleType == 'return') return false;  // this IS a return invoice
        return true;  // show all other sale types (default, delivery, table, etc.)
      }).toList();
    debugPrint('[ReturnsRepo] getInvoicesForReturn: after filter=${filtered.length} (excluded ${invoices.length - filtered.length} non-returnable)');
    return filtered;
  }

  @override
  Future<List<SalesInvoiceItem>> getSalesInvoiceItems(int invoiceId) =>
      _db.getSalesInvoiceItems(invoiceId);

  @override
  Future<double> getReturnedQuantityForInvoiceItem({
    required int invoiceId,
    required int productId,
  }) => _db.getReturnedQuantityForInvoiceItem(
    invoiceId: invoiceId,
    productId: productId,
  );

  @override
  Future<Map<int, double>> getReturnedQuantitiesForInvoice(int invoiceId) =>
      _db.getReturnedQuantitiesForInvoice(invoiceId);

  @override
  Future<List<SalesInvoiceData>> getSalesReturnHistory({
    required DateTime fromDate,
    required DateTime toDate,
    Set<int>? allowedBranchIds,
  }) async {
    // Use dedicated query that filters at the DB level for returns
    // (saleType='return' OR status='returned'/'partial_return' OR total<0)
    // instead of fetching ALL invoices then filtering in Dart.
    // Spec 151 Track-3: thread the auth branch-scope cap into the query.
    final invoices = await _db.getSalesReturns(
      fromDate,
      toDate,
      allowedBranchIds: allowedBranchIds,
    );
    debugPrint('[ReturnsRepo] getSalesReturnHistory: fromDate=$fromDate, toDate=$toDate, found ${invoices.length} return invoices');
    for (final inv in invoices) {
      debugPrint('[ReturnsRepo]   Invoice #${inv.invoiceNumber}: saleType=${inv.saleType}, status=${inv.status}, total=${inv.total}');
    }
    return invoices;
  }

  @override
  Future<List<SalesReturnHistoryEntry>> getSalesReturnHistoryEntries({
    required DateTime fromDate,
    required DateTime toDate,
    Set<int>? allowedBranchIds,
  }) =>
      _db.getSalesReturnHistoryEntries(
        fromDate,
        toDate,
        allowedBranchIds: allowedBranchIds,
      );

  @override
  Future<bool> processSalesReturn({
    required SalesInvoiceData invoice,
    required Map<int, double> returnQuantities,
    required Map<int, ProductEntity> productCache,
    String? reason,
    required int userId,
    required String userName,
    bool isFullReturn = false,
    bool isDamaged = false,
  }) async {
    final invoiceItems = await _db.getSalesInvoiceItems(invoice.id);
    
    // === PIR F9: Return Quantity Validation ===
    // Validate that returnedQty ≤ (originalQty - alreadyReturnedQty)
    for (final item in invoiceItems) {
      final requestedReturn = returnQuantities[item.id] ?? 0;
      if (requestedReturn > 0) {
        final alreadyReturned = await _db.getAlreadyReturnedQty(
          invoice.id,
          item.productId,
        );
        final maxReturnable = item.quantity - alreadyReturned;
        if (requestedReturn > maxReturnable + 0.001) {
          throw Exception(
            'الكمية المطلوب إرجاعها (${requestedReturn.toStringAsFixed(AppConstants.decimalPlaces)}) '
            'أكبر من المتاح للإرجاع (${maxReturnable.toStringAsFixed(AppConstants.decimalPlaces)}) '
            'للصنف رقم ${item.productId}',
          );
        }
      }
    }

    // Calculate total return amount
    double totalReturn = _calculateReturnTotal(invoice, invoiceItems, returnQuantities);
    if (totalReturn <= 0) return false;

    // Spec 007 / FR-003, FR-005: broadened predicate so mirror admins'
    // sales returns reach HQ.
    final isClientMode = SyncInterceptor.isClientMode;

    // ── Client Mode: lightweight local cache + server handles heavy operations ──
    if (isClientMode) {
      // Build items payload matching server's expected format
      final returnItemsList = <Map<String, dynamic>>[];
      double subtotal = 0;
      double tax = 0;
      for (final item in invoiceItems) {
        final qty = returnQuantities[item.id] ?? 0;
        if (qty <= 0) continue;
        final itemTotal = qty * item.unitPrice;
        final itemDiscount = item.discount * (qty / item.quantity);
        final itemTax = item.taxAmount * (qty / item.quantity);
        subtotal += itemTotal;
        tax += itemTax;
        returnItemsList.add({
          'productId': item.productId,
          'quantity': qty,
          'unitPrice': item.unitPrice,
          'discount': itemDiscount,
          'total': itemTotal - itemDiscount,
          'costPrice': item.costPrice,
          // SAL-2: without this the server defaults quantityInBase to 1.0 and
          // under-restores physical stock on non-base-unit (carton/box) returns.
          'quantityInBase': item.quantityInBase,
          'taxRate': item.taxRate,
          'taxAmount': itemTax,
        });
      }

      // P5: Mint a stable globalId for the return invoice so the server can
      // dedupe outbox replays. Without this, every retry of the POST creates a
      // brand-new return invoice on the server and the client sees phantom
      // duplicates after the next DeltaPull.
      final returnGlobalId = UuidV7.generate();
      // Mirror: awaited — the local return-invoice cache row below (Spec 136)
      // makes the return visible in the party statement immediately. Writing it
      // for a return HQ rejected would credit the customer locally on a
      // document that exists nowhere else.
      await ClientWriteInterceptor.dispatchWrite(
        () => ClientWriteInterceptor.submitSalesReturn({
          'globalId': returnGlobalId,
          'originalInvoiceId': invoice.id,
          // Send the original invoice's identifiers so the server can resolve
          // it even when client/server IDs diverge.
          if (invoice.globalId != null && invoice.globalId!.isNotEmpty)
            'originalInvoiceGlobalId': invoice.globalId,
          'originalInvoiceNumber': invoice.invoiceNumber,
          // Spec 002 (B2): tell the server whether to flip the original
          // invoice's status to 'returned' (full) or 'partial_return'. Without
          // this hint the server only recorded the new return row but left
          // the original 'completed', so neither the server's invoices screen
          // nor its returns history reflected the return.
          'isFullReturn': isFullReturn,
          // Customer attribution — without these the return loses its customer
          // link on the server (resolvePartyId returns null).
          'customerId': invoice.customerId,
          'items': returnItemsList,
          'warehouseId': invoice.warehouseId,
          'userId': userId,
          'subtotal': subtotal,
          'discount': 0.0,
          'tax': tax,
          'total': totalReturn,
          // Spec 113 — only the portion of the return that exceeds the
          // customer's outstanding debt becomes an actual cash refund.
          // Sending `paid: totalReturn` blindly caused the server to mint
          // a phantom PV/PMT for credit-sale returns (where no cash
          // physically moved) → the customer statement showed a duplicate
          // "سند صرف" alongside the return invoice. Matches the math the
          // standalone path already runs at lines 254-285 below.
          'paid': () {
            final remaining = (invoice.total - invoice.paid)
                .clamp(0.0, double.infinity);
            final cashRefundShare = totalReturn - remaining;
            return cashRefundShare > 0 ? cashRefundShare : 0.0;
          }(),
          'paymentMethod': invoice.paymentMethod,
          'reason': reason,
        }),
        tag: 'SALES-RETURN-SYNC',
      );

      // Spec 136 — light LOCAL return-invoice cache so the sales return shows
      // in the CUSTOMER statement immediately on the mirror/client. The server
      // (postSalesReturn) creates the authoritative saleType='return' row, but
      // the party statement is a LOCAL read and this client path previously
      // wrote NO local return representation (only flipped the original
      // invoice's status) — so the return was invisible locally, and the
      // pulled server row carries the SERVER customerId which never matches the
      // local party id. We insert a header-only row with saleType='return',
      // the LOCAL customerId, and the SHARED returnGlobalId so
      // SalesInvoiceSyncStrategy dedups on globalId when the server echo
      // arrives (no double). getPartyStatement's sales loop renders it as
      // 'مرتجع مبيعات' (credit). Idempotent — skip if the gid already exists.
      if (invoice.customerId != null) {
        try {
          final existing = await (_db.select(_db.salesInvoices)
                ..where((s) => s.globalId.equals(returnGlobalId))
                ..limit(1))
              .getSingleOrNull();
          if (existing == null) {
            final shortGid = returnGlobalId.length >= 8
                ? returnGlobalId.substring(0, 8)
                : returnGlobalId;
            await _db.insertSalesInvoiceWithoutStock(
              invoice: SalesInvoicesCompanion.insert(
                invoiceNumber: 'SRET-$shortGid',
                warehouseId: invoice.warehouseId,
                userId: userId,
                invoiceDate: DateTime.now(),
                customerId: Value(invoice.customerId),
                subtotal: Value(totalReturn),
                total: Value(totalReturn),
                paid: const Value(0),
                paymentMethod: Value(invoice.paymentMethod),
                saleType: const Value('return'),
                status: const Value('completed'),
                globalId: Value(returnGlobalId),
                // البند 3: without this the local cache row carried NO link to
                // its original, so the device under-counted the refund in
                // «المتبقي» until a DeltaPull replaced it with the server's
                // row. `invoice.id` is the LOCAL id — which is exactly what the
                // local query matches on.
                notes: Value(localReturnLinkNote(invoice.id,
                    originalGlobalId: invoice.globalId)),
              ),
              items: const [],
            );
          }
        } catch (e) {
          debugPrint('[SALES-RETURN] local return-row cache failed (non-fatal): $e');
        }
      }

      // Local cache: update invoice status
      await _db.updateSalesInvoiceStatus(
        invoice.id,
        isFullReturn ? 'returned' : 'partial_return',
      );
      return true;
    }

    // ── Standalone/Server: Full local processing ──
    await _db.transaction(() async {
      // B3: Generate sequential return invoice number
      final returnVoucherNumber = await _db.generateInvoiceNumber('SRET-');

      double totalTaxReturn = 0;
      double totalCogsReturn = 0;
      double totalDamagedCogs = 0; // NEW: Track cost of damaged goods returned
      // Feature 009 / T031 (Issue 6 / Cluster 021): per-item return fractions
      // for reverseSaleConsumption. Built alongside the existing per-item
      // loop so no extra DB round-trip is needed.
      final itemReturnFractions = <int, double>{};

      for (final item in invoiceItems) {
        final returnQty = returnQuantities[item.id] ?? 0;
        if (returnQty > 0) {
          final product = productCache[item.productId];
          if (product != null) {
            // Track the fraction so the BOM-reversal pass below can scale
            // each consumption row by it.
            itemReturnFractions[item.id] = returnQty / item.quantity;
            // UOM: Convert return quantity to base units for correct stock adjustment
            final qtyInBase = item.quantityInBase > 0 ? item.quantityInBase : 1.0;
            final stockReturnQty = returnQty * qtyInBase;

            // C-04 FIX: Use adjustStock for proper warehouse-level stock update
            // (handles global stock, warehouse balance, stock movement, FIFO batches)
            // SRET-3 (spec 149 B15): only restock inventory-tracked products — a
            // service / non-stock item has no stock to return, so restocking it
            // would create phantom inventory balances/movements. Tax + COGS
            // reversal below still runs (a service can carry VAT; its costPrice
            // is 0 so the COGS leg is naturally zero). Mirrors purchase_dao.dart's
            // `if (product != null && product.trackInventory)` guard.
            if (product.trackInventory) {
              // Re-blend the returned units into WAC at the SAME cost the
              // journal entry below uses (item.costPrice, frozen at sale
              // time). Without this, valuation keeps the current WAC while
              // the GL takes the frozen one, and the gap
              // (qty × (WAC_now − frozen)) never self-corrects.
              //
              // MUST run before adjustStock — updateProductWAC reads
              // products.current_stock as the "before" quantity.
              //
              // The sibling here is the RECEIPT path (purchase_dao's
              // createPurchaseInvoice), not the purchase-RETURN path: a sales
              // return brings goods IN, so it blends (updateProductWAC);
              // reverseProductWAC is for goods going OUT and would push the
              // cost the wrong way.
              await _db.updateProductWAC(
                productId: item.productId,
                newQuantity: stockReturnQty,
                newUnitCost: item.costPrice,
              );
              await _db.adjustStock(
                productId: item.productId,
                warehouseId: invoice.warehouseId,
                quantity: stockReturnQty, // positive = adding back to stock (in base units)
                type: 'return',
                referenceType: 'sales_return',
                referenceId: invoice.id,
                userId: userId,
                // Same frozen cost, so the per-warehouse average_cost layer
                // lands on the same number as the product-level WAC.
                unitCost: item.costPrice,
                notes: reason != null && reason.isNotEmpty
                    ? 'مرتجع: $reason'
                    : 'مرتجع فاتورة ${invoice.invoiceNumber}',
              );
            }

            // Calculate Tax and COGS for accounting
            // B9 (SRET-2): prorate the FROZEN original per-line tax
            // (item.taxAmount — computed at sale time on the DISCOUNTED net
            // base, see calculate_invoice_totals_usecase.dart) by the return
            // fraction, matching the sibling client-mode path above
            // (~124-125: `item.taxAmount * (qty / item.quantity)`). The
            // previous `unitPrice * returnQty * taxRate` recompute used the
            // GROSS pre-discount price, over-reversing output VAT whenever
            // the original sale carried a line/invoice discount — which in
            // turn understated the contra-revenue leg in autoPostSalesReturn
            // (salesReturnNet = returnAmount - vatAmount).
            final itemTax = item.quantity > 0
                ? item.taxAmount * (returnQty / item.quantity)
                : 0.0;
            totalTaxReturn += itemTax;
            // H-08 FIX: Use item.costPrice (from invoice) instead of product.costPrice (stale cache)
            // SAL-1: costPrice is per BASE unit; returnQty is in SALE units — multiply
            // by qtyInBase (already resolved above for the stock-restore leg) so COGS
            // reversal matches the physical stock this return actually restores.
            totalCogsReturn += (item.costPrice * returnQty * qtyInBase);

            if (isDamaged) {
              totalDamagedCogs += (item.costPrice * returnQty * qtyInBase);
              // SRET-3: same guard — no stock movement for a service/non-stock item.
              if (product.trackInventory) {
                await _db.adjustStock(
                  productId: item.productId,
                  warehouseId: invoice.warehouseId,
                  quantity: -stockReturnQty, // negative = deduct from stock (in base units)
                  type: 'waste',
                  referenceType: 'sales_return_damaged',
                  referenceId: invoice.id,
                  userId: userId,
                  notes: reason != null && reason.isNotEmpty
                      ? 'إتلاف مرتجع: $reason'
                      : 'إتلاف مباشر مع مرتجع فاتورة ${invoice.invoiceNumber}',
                );
              }
            }
          }
        }
      }

      // Financial Reconciliation
      double actualRefundToPay = totalReturn;
      double arRefund = 0;

      if (invoice.customerId != null) {
        final oldRemaining = (invoice.total - invoice.paid).clamp(0.0, double.infinity);
        if (oldRemaining > 0) {
          final balanceCorrection = totalReturn.clamp(0.0, oldRemaining);
          await _db.adjustPartyBalance(invoice.customerId!, -balanceCorrection);
          arRefund = balanceCorrection;
          actualRefundToPay = totalReturn - balanceCorrection;
        }
      }

      double cashRefund = 0;
      double bankRefund = 0;

      if (actualRefundToPay > 0) {
        if (invoice.paymentMethod == 'multiple' || invoice.paymentMethod == 'mixed') {
          final totalPaid = invoice.cashPaid + invoice.bankPaid;
          if (totalPaid > 0) {
            cashRefund = actualRefundToPay * (invoice.cashPaid / totalPaid);
            bankRefund = actualRefundToPay * (invoice.bankPaid / totalPaid);
          } else {
            cashRefund = actualRefundToPay;
          }
        } else if (['transfer', 'card', 'bank'].contains(invoice.paymentMethod)) {
          bankRefund = actualRefundToPay;
        } else {
          cashRefund = actualRefundToPay;
        }
      }

      // Safe Transactions
      //
      // CRITICAL: both blocks below used to call `createSafeTransaction`
      // which (a) decrements the safe balance via SQL arithmetic AND
      // (b) re-adjusts the party balance based on `transactionType`.
      // We already called `updateSafeBalance(newBalance)` above, so the
      // arithmetic decrement would have double-debited the safe. And the
      // party-balance adjustment is plain wrong for a cash/bank refund —
      // the customer didn't owe us anything, so reducing their balance
      // turns them into a creditor by mistake.
      //
      // Additionally, `createSafeTransaction` opens its own nested
      // transaction. That nesting inside the outer `_db.transaction(...)`
      // is what caused the full-invoice-return freeze the user reported
      // (repro: paid-in-cash invoice → full return → the UI locks and
      // only a gray ModalBarrier remains on the body while the sidebar
      // continues to navigate).
      //
      // Fix: write the ledger row with a plain `into(...).insert(...)`
      // so no nested transaction runs and no auto balance mutation fires.
      if (cashRefund > 0) {
        final cashSafe = await _db.getDefaultSafeByType('cash');
        if (cashSafe != null) {
          final newBalance = cashSafe.balance - cashRefund;
          await _db.updateSafeBalance(cashSafe.id, newBalance);
          await _db.into(_db.safeTransactions).insert(
            SafeTransactionsCompanion.insert(
              voucherNumber: returnVoucherNumber,
              safeId: cashSafe.id,
              transactionType: 'payment',
              category: 'sales_return',
              amount: cashRefund,
              balanceAfter: newBalance,
              referenceType: const Value('sales_return'),
              referenceId: Value(invoice.id),
              partyId: Value(invoice.customerId),
              description: Value('مرتجع نقدي فاتورة ${invoice.invoiceNumber}'),
              userId: Value(userId),
            ),
          );
        }
      }

      if (bankRefund > 0) {
        final bankSafe = await _db.getDefaultSafeByType('bank');
        if (bankSafe != null) {
          final newBalance = bankSafe.balance - bankRefund;
          await _db.updateSafeBalance(bankSafe.id, newBalance);
          await _db.into(_db.safeTransactions).insert(
            SafeTransactionsCompanion.insert(
              voucherNumber: returnVoucherNumber,
              safeId: bankSafe.id,
              transactionType: 'payment',
              category: 'sales_return',
              amount: bankRefund,
              balanceAfter: newBalance,
              referenceType: const Value('sales_return'),
              referenceId: Value(invoice.id),
              partyId: Value(invoice.customerId),
              description: Value('مرتجع بنك فاتورة ${invoice.invoiceNumber}'),
              userId: Value(userId),
            ),
          );
        }
      }

      // Record a balance-adjustment memo entry for the customer statement
      // when the return reduced a credit balance (no actual cash refund
      // was issued).
      //
      // CRITICAL: this MUST go in as a plain insert — not through
      // `createSafeTransaction` — because that method unconditionally
      // mutates the safe balance AND the party balance based on
      // `transactionType`. We already did `adjustPartyBalance(-balanceCorrection)`
      // above; letting `createSafeTransaction` do it again causes a
      // double-deduction from the customer's AR and an incorrect safe
      // balance. The direct insert leaves both intact and keeps the
      // memo visible in the customer's statement. This is likely the
      // freeze-on-full-return bug the user reported.
      if (arRefund > 0 && invoice.customerId != null) {
        final arSafe = ['transfer', 'card', 'bank'].contains(invoice.paymentMethod)
            ? await _db.getDefaultSafeByType('bank')
            : await _db.getDefaultSafeByType('cash');
        if (arSafe != null) {
          await _db.into(_db.safeTransactions).insert(
            SafeTransactionsCompanion.insert(
              voucherNumber: returnVoucherNumber,
              safeId: arSafe.id,
              // Use a distinct type so downstream aggregation queries
              // (shift close, treasury reports) skip memo rows instead
              // of double-counting them.
              transactionType: 'memo',
              category: 'sales_return_balance',
              amount: arRefund,
              balanceAfter: arSafe.balance,
              referenceType: const Value('sales_return'),
              referenceId: Value(invoice.id),
              partyId: Value(invoice.customerId),
              description: Value(
                  'تسوية رصيد مرتجع مبيعات فاتورة ${invoice.invoiceNumber}'),
              userId: Value(userId),
              // Spec 136 ISS-7 (symmetry) — give each sales-return memo its own
              // globalId. Multiple partial returns on one invoice therefore get
              // DISTINCT ids (was NULL → the (refType,refId,partyId) Tier-2
              // merge would collapse them if this row ever synced). The server
              // does not currently emit a sales-return memo, so this is
              // standalone-local + future-proofing rather than an active
              // cross-device bug like the purchase-return path.
              globalId: Value(UuidV7.generate()),
            ),
          );
        }
      }

      // Feature 009 / T031 (Issue 6 / Cluster 021): if the original sale used
      // BOM auto-deplete, reverse the raw-material consumption at the FROZEN
      // unit_cost_at_sale and feed the cost map into autoPostSalesReturn so
      // the JE uses the original cost instead of the legacy
      // `item.costPrice × returnQty` (which can drift if WAC moved). For
      // sales without auto-deplete consumption rows the call is a silent
      // no-op (empty map → empty result) and the legacy COGS path runs.
      final reverseResult = await _db.reverseSaleConsumption(
        saleInvoiceId: invoice.id,
        salesReturnId: invoice.id,
        itemReturnFractions: itemReturnFractions,
      );

      // Auto-post return journal entry (IFRS 15.B20)
      await _db.autoPostSalesReturn(
        originalInvoice: invoice,
        // المرتجع حدث النهاردة مش في فترة الفاتورة الأصلية. من غير ده كان
        // مرتجع لفاتورة شهر مقفول **بيترفض تماماً** والترانزاكشن كلها ترجع،
        // فالكاشير مش قادر يعمل مرتجع مشروع.
        returnDate: DateTime.now(),
        returnAmount: totalReturn,
        cogsAmount: totalCogsReturn,
        cashRefund: cashRefund,
        bankRefund: bankRefund,
        arRefund: arRefund,
        vatAmount: totalTaxReturn,
        reversalCogs: reverseResult.cogsBreakdown.isEmpty
            ? null
            : reverseResult.cogsBreakdown,
        // A-01 (Spec 151): thread the return's own sequential SRET-N voucher as
        // the dedup discriminator so two DISTINCT partial returns of the SAME
        // amount on one invoice don't collide (the JE is now keyed on the
        // shared invoice id — uniqueness rides on the derived globalId).
        returnEventId: returnVoucherNumber,
      );

      // P0 FIX: If items are returned as damaged, record the inventory loss (waste)
      // to keep GL balanced with actual stock.
      if (isDamaged && totalDamagedCogs > 0) {
        // Defaults pulled from accountPurposes (single source of truth) to
        // stay in sync with the seeder. The earlier hardcoded '1103' for
        // inventory was wrong — the seeded code is '1136' (مخزون البضاعة للبيع).
        final shrinkageAccount = await _db.getAccountByCode(
          await _db.getMappedAccountCode(
              'inventory_shrinkage',
              AccountingDao.accountPurposes['inventory_shrinkage']!),
        );
        final inventoryAccount = await _db.getAccountByCode(
          await _db.getMappedAccountCode(
              'inventory',
              AccountingDao.accountPurposes['inventory']!),
        );

        if (shrinkageAccount != null && inventoryAccount != null) {
          final warehouse = await _db.getWarehouseById(invoice.warehouseId);
          await _db.createJournalEntry(
            description: 'إتلاف مباشر لمرتجع مبيعات فاتورة ${invoice.invoiceNumber}',
            date: DateTime.now(),
            lines: [
              JournalLine(
                accountId: shrinkageAccount.id,
                debit: totalDamagedCogs,
                description: 'عجز وإتلاف مخزون (مرتجع)',
              ),
              JournalLine(
                accountId: inventoryAccount.id,
                credit: totalDamagedCogs,
                description: 'تخفيض مخزون لمعالجة الإتلاف',
              ),
            ],
            referenceType: 'sales_return_damaged',
            referenceId: invoice.id,
            isAutoPosted: true,
            costCenterId: invoice.costCenterId,
            branchId: warehouse?.branchId,
          );
        }
      }

      await _db.updateSalesInvoiceStatus(
        invoice.id,
        isFullReturn ? 'returned' : 'partial_return',
      );

      await _db.logActivity(
        userId: userId,
        userName: userName,
        action: 'refund',
        entityType: 'invoice',
        entityId: invoice.id,
        description: 'مرتجع فاتورة ${invoice.invoiceNumber}',
        amount: totalReturn,
      );
    });

    // Note: Client-mode sync is handled in the early-exit block above.
    // Server/standalone mode processes locally and doesn't need to sync.

    return true;
  }

  @override
  Future<List<PurchaseInvoiceData>> getInvoicesForPurchaseReturn({
    required DateTime fromDate,
    required DateTime toDate,
    int? supplierId,
    int? productId,
    String? invoiceNumberLike,
  }) async {
    final invoices = await _db.getPurchasesForDateRange(
      fromDate,
      toDate,
      supplierId: supplierId,
      productId: productId,
      invoiceNumberLike: invoiceNumberLike,
    );
    debugPrint('[ReturnsRepo] getInvoicesForPurchaseReturn: total fetched=${invoices.length}, fromDate=$fromDate, toDate=$toDate');
    final filtered = invoices.where((invoice) {
        if (invoice.total <= 0) return false;            // skip zero/negative total invoices
        if (invoice.status == 'returned') return false;  // already fully returned
        if (invoice.status == 'cancelled') return false; // cancelled invoices
        if (invoice.status == 'voided') return false;    // voided invoices
        return true;  // show all other purchase invoices (completed, pending, partial_return, etc.)
      }).toList();
    debugPrint('[ReturnsRepo] getInvoicesForPurchaseReturn: after filter=${filtered.length} (excluded ${invoices.length - filtered.length} non-returnable)');
    return filtered;
  }

  @override
  Future<List<PurchaseInvoiceItem>> getPurchaseInvoiceItems(int invoiceId) =>
      _db.getPurchaseInvoiceItems(invoiceId);

  @override
  Future<List<PurchaseInvoiceData>> getPurchaseReturnHistory({
    required DateTime fromDate,
    required DateTime toDate,
    Set<int>? allowedBranchIds,
  }) async {
    // Spec 151 Track-3: thread the auth branch-scope cap into the query so a
    // branch-restricted user cannot see other branches' purchase returns.
    final invoices = await _db.getPurchasesForDateRange(
      fromDate,
      toDate,
      allowedBranchIds: allowedBranchIds,
    );
    return invoices.where((inv) =>
        inv.status == 'returned' ||
        inv.status == 'partial_return' ||
        inv.total < 0).toList();
  }

  @override
  Future<ReturnPrintData?> getSalesReturnPrintData({
    required String invoiceNumber,
    required double returnTotal,
    SalesInvoiceData? selectedInvoice,
    List<SalesInvoiceItem>? invoiceItems,
    Map<int, ProductEntity>? productCache,
    Map<int, double>? returnQuantities,
  }) async {
    final receiptSettings = await _db.getReceiptSettings();
    final List<InvoiceItem> printableItems = [];

    if (selectedInvoice != null &&
        invoiceItems != null &&
        productCache != null &&
        returnQuantities != null) {
      // Data exists from the current active return session
      for (final item in invoiceItems) {
        final returnQty = returnQuantities[item.id] ?? 0;
        if (returnQty > 0) {
          final product = productCache[item.productId];
          // Recalculate refund for this item (global discount aware)
          double sumItemTotals = invoiceItems.fold(0, (sum, i) => sum + i.total);
          double factor = sumItemTotals > 0
              ? (selectedInvoice.total - selectedInvoice.deliveryFee) /
                  sumItemTotals
              : 1.0;
          final netUnitPrice = (item.total / item.quantity) * factor;
          final itemRefundTotal = returnQty * netUnitPrice;

          printableItems.add(
            InvoiceItem(
              name: product?.name ?? 'منتج #${item.productId}',
              quantity: returnQty,
              price: netUnitPrice,
              total: itemRefundTotal,
            ),
          );
        }
      }
    } else {
      // Data must be fetched for an existing return (from history)
      final invoices = await _db.getSalesByDateRange(
        DateTime.now().subtract(const Duration(days: 30)),
        DateTime.now().add(const Duration(days: 1)),
      );
      final inv = invoices.where((i) => i.invoiceNumber == invoiceNumber).firstOrNull;
      if (inv != null) {
        final items = await _db.getSalesInvoiceItems(inv.id);
        for (final item in items) {
          final product = await _db.getProductById(item.productId);
          printableItems.add(
            InvoiceItem(
              name: product?.name ?? 'منتج #${item.productId}',
              quantity: item.quantity,
              price: item.unitPrice,
              total: item.total,
            ),
          );
        }
        selectedInvoice = inv;
      }
    }

    if (selectedInvoice == null) return null;

    String paymentMethod = selectedInvoice.paymentMethod;
    double cashRefund = returnTotal;
    double bankRefund = 0;

    if (paymentMethod == 'multiple' || paymentMethod == 'mixed') {
      final totalPaid = selectedInvoice.cashPaid + selectedInvoice.bankPaid;
      if (totalPaid > 0) {
        cashRefund = returnTotal * (selectedInvoice.cashPaid / totalPaid);
        bankRefund = returnTotal * (selectedInvoice.bankPaid / totalPaid);
      }
    } else if (['transfer', 'card', 'bank'].contains(paymentMethod)) {
      cashRefund = 0;
      bankRefund = returnTotal;
    }

    String? customerName;
    if (selectedInvoice.customerId != null) {
      final customer = await _db.getPartyById(selectedInvoice.customerId!);
      customerName = customer?.name;
    }

    // Resolve the real return-voucher number from the ledger rows written
    // during processSalesReturn (SafeTransactions + SRET-N format). This
    // replaces the placeholder `'RET-<originalInvoice>'` the UI used to
    // print, which was confusing because it duplicated the original
    // invoice number verbatim.
    final invId = selectedInvoice.id;
    String? returnVoucherNumber;
    try {
      final row = await (_db.select(_db.safeTransactions)
            ..where((t) =>
                t.referenceType.equals('sales_return') &
                t.referenceId.equals(invId))
            ..orderBy([(t) => OrderingTerm.desc(t.id)])
            ..limit(1))
          .getSingleOrNull();
      returnVoucherNumber = row?.voucherNumber;
    } catch (e, st) {
      // Non-critical: voucher number is for display only — log and continue.
      debugPrint('[ReturnsRepo] getReturnPrintData: failed to fetch voucher number for return $invId: $e\n$st');
    }

    return ReturnPrintData(
      receiptSettings: receiptSettings,
      items: printableItems,
      paymentMethod: paymentMethod,
      cashRefund: cashRefund,
      bankRefund: bankRefund,
      customerName: customerName,
      returnVoucherNumber: returnVoucherNumber,
    );
  }

  @override
  Future<void> cancelSalesReturn({
    required SalesInvoiceData invoice,
    required int userId,
    required String userName,
  }) async {
    await _accountingService.cancelSalesReturn(
      invoice: invoice,
      userId: userId,
      userName: userName,
    );
  }

  double _calculateReturnTotal(
    SalesInvoiceData invoice,
    List<SalesInvoiceItem> items,
    Map<int, double> returnQuantities,
  ) {
    double sumItemTotals = items.fold(0.0, (sum, i) => sum + i.total);
    double factor = sumItemTotals > 0
        ? (invoice.total - invoice.deliveryFee) / sumItemTotals
        : 1.0;

    double refundTotal = 0;
    double returnedRawTotal = 0;
    for (final item in items) {
      final qty = returnQuantities[item.id] ?? 0;
      if (qty <= 0) continue;
      final unitItemPrice = item.total / item.quantity;
      returnedRawTotal += qty * unitItemPrice;
      refundTotal += qty * unitItemPrice * factor;
    }

    // B2: Proportional delivery fee refund for partial returns
    if (invoice.deliveryFee > 0 && sumItemTotals > 0) {
      final deliveryFeeRefund = invoice.deliveryFee * (returnedRawTotal / sumItemTotals);
      refundTotal += double.parse(deliveryFeeRefund.toStringAsFixed(AppConstants.decimalPlaces));
    }

    return double.parse(refundTotal.toStringAsFixed(AppConstants.decimalPlaces));
  }
}
