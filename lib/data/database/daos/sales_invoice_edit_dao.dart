part of '../database.dart';

extension SalesInvoiceEditDao on AppDatabase {
  Future<SalesInvoiceData> getSalesInvoiceForContentEdit(int invoiceId) async {
    final invoice = await getSalesInvoiceById(invoiceId);
    if (invoice == null) throw Exception('Invoice not found');
    await requireNoSalesReturnForEdit(invoiceId, invoice.status);
    return invoice;
  }

  Future<void> requireNoSalesReturnForEdit(int invoiceId, String status) async {
    if (await hasActiveSalesReturn(invoiceId, invoiceStatus: status)) {
      throw StateError(
        'لا يمكن تعديل فاتورة عليها مرتجع. ألغِ المرتجع أو حرّر فاتورة بديلة.',
      );
    }
  }

  Future<bool> hasActiveSalesReturn(int invoiceId, {String? invoiceStatus}) async {
    final original = await (select(salesInvoices)
          ..where((i) => i.id.equals(invoiceId)))
        .getSingleOrNull();
    if (original == null) return false;
    final returnDocs = await (select(salesInvoices)
          ..where((i) => i.saleType.equals('return')))
        .get();
    final linkedDocs = returnDocs.where((returnInvoice) {
      final returnGid = returnOriginalGidFromNote(returnInvoice.notes);
      if (returnGid != null && original.globalId != null) {
        return returnGid == original.globalId;
      }
      return returnOriginalIdFromNote(returnInvoice.notes) == invoiceId;
    }).toList();
    if (linkedDocs.isNotEmpty) {
      return linkedDocs.any((returnInvoice) => !returnInvoice.isDeleted);
    }
    final cancelledReturn = await (select(safeTransactions)
          ..where(
            (t) =>
                t.referenceType.equals('return_cancel') &
                t.referenceId.equals(invoiceId),
          )
          ..limit(1))
        .getSingleOrNull();
    if (cancelledReturn != null) return false;
    if (invoiceStatus == 'partial_return' || invoiceStatus == 'returned') {
      return true;
    }
    return await (select(safeTransactions)
          ..where(
            (t) =>
                t.referenceType.equals('sales_return') &
                t.referenceId.equals(invoiceId),
          )
          ..limit(1))
        .getSingleOrNull() !=
        null;
  }

  /// Keeps old postings auditable by reversing before reposting changed data.
  Future<void> updateSalesInvoice({
    required int invoiceId,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    required double paid,
    required String paymentMethod,
    String? notes,
    required List<SalesInvoiceItemsCompanion> items,
    int? userId,
  }) async {
    return transaction(() async {
      final oldInvoice = await (select(
        salesInvoices,
      )..where((i) => i.id.equals(invoiceId))).getSingleOrNull();
      if (oldInvoice == null) return;

      if (oldInvoice.isLocked) {
        await permissionEnforcer.requireCriticalOp(
          userId: userId,
          code: PermissionCodes.modifyLockedInvoice,
          arabicReason:
              'لا يمكن تعديل فاتورة مُرحّلة محاسبيًا. '
              'استخدم المرتجعات بدلاً من التعديل، '
              'أو يلزم صلاحية "تعديل فاتورة مقفلة".',
        );
      }

      await accountingDao.validateFinancialPeriod(
        oldInvoice.invoiceDate,
        operation: 'تعديل فاتورة مبيعات',
      );
      final oldItems = await (select(
        salesInvoiceItems,
      )..where((i) => i.invoiceId.equals(invoiceId))).get();
      final itemsChanged =
          oldItems.length != items.length ||
          List<int>.generate(
            oldItems.length < items.length ? oldItems.length : items.length,
            (i) => i,
          ).any((i) {
            final old = oldItems[i];
            final next = items[i];
            return !next.productId.present ||
                next.productId.value != old.productId ||
                !next.quantity.present ||
                next.quantity.value != old.quantity ||
                !next.unitPrice.present ||
                next.unitPrice.value != old.unitPrice ||
                !next.total.present ||
                next.total.value != old.total ||
                (next.quantityInBase.present
                        ? next.quantityInBase.value
                        : 1.0) !=
                    old.quantityInBase ||
                (next.costPrice.present ? next.costPrice.value : 0.0) !=
                    old.costPrice;
          });
      final invoiceChanged =
          oldInvoice.subtotal != subtotal ||
          oldInvoice.discount != discount ||
          oldInvoice.tax != tax ||
          oldInvoice.total != total ||
          oldInvoice.paid != paid ||
          oldInvoice.paymentMethod != paymentMethod ||
          oldInvoice.notes != notes ||
          itemsChanged;

      // A return is an immutable event; changing its source breaks later voids.
      if (await hasActiveSalesReturn(invoiceId, invoiceStatus: oldInvoice.status)) {
        throw StateError(
          'لا يمكن تعديل فاتورة عليها مرتجع. ألغِ المرتجع أو حرّر فاتورة بديلة.',
        );
      }
      if (!invoiceChanged) return;

      // Preserve locked invoice behavior; unlocked posted POS invoices also
      // reverse and repost whenever their header or lines have changed.
      final amountsChanged =
          oldInvoice.isLocked &&
          (oldInvoice.subtotal != subtotal ||
              oldInvoice.discount != discount ||
              oldInvoice.tax != tax ||
              oldInvoice.total != total);
      var repostRevision = 0;
      if (amountsChanged || (!oldInvoice.isLocked && invoiceChanged)) {
        repostRevision = await _reverseActiveSaleEntriesForEdit(
          invoiceId,
          'عكس تعديل فاتورة مبيعات',
        );
      }
      final shouldRepost =
          amountsChanged ||
          (!oldInvoice.isLocked && invoiceChanged && repostRevision > 0);
      final oldPaid = oldInvoice.paid;

      for (final oldItem in oldItems) {
        final product = await getProductById(oldItem.productId);
        if (product != null && product.trackInventory) {
          final oldQtyInBase = oldItem.quantityInBase > 0
              ? oldItem.quantityInBase
              : 1.0;
          final restoreQty = oldItem.quantity * oldQtyInBase;
          await updateProductWAC(
            productId: oldItem.productId,
            newQuantity: restoreQty,
            newUnitCost: oldItem.costPrice,
          );
          await adjustStock(
            productId: oldItem.productId,
            warehouseId: oldInvoice.warehouseId,
            quantity: restoreQty,
            type: 'edit_reversal',
            referenceType: 'sales_invoice',
            referenceId: invoiceId,
            unitCost: oldItem.costPrice,
            notes: 'عكس الكمية لتعديل فاتورة مبيعات #$invoiceId',
          );
        }
      }

      await (delete(
        salesInvoiceItems,
      )..where((i) => i.invoiceId.equals(invoiceId))).go();
      final remaining = total - paid;
      final status = remaining <= 0 ? 'completed' : 'pending';
      await (update(salesInvoices)..where((i) => i.id.equals(invoiceId))).write(
        SalesInvoicesCompanion(
          subtotal: Value(subtotal),
          discount: Value(discount),
          tax: Value(tax),
          total: Value(total),
          paymentMethod: Value(paymentMethod),
          status: Value(status),
          notes: Value(notes),
        ),
      );
      await _writeSalesInvoicePaid(invoiceId, paid);
      await resignSalesInvoice(invoiceId);

      for (final item in items) {
        await into(
          salesInvoiceItems,
        ).insert(item.copyWith(invoiceId: Value(invoiceId)));
        final prodId = item.productId.value;
        final quantity = item.quantity.value;
        final editQtyInBase = item.quantityInBase.present
            ? item.quantityInBase.value
            : 1.0;
        final product = await getProductById(prodId);
        if (product != null && product.trackInventory) {
          await adjustStock(
            productId: prodId,
            warehouseId: oldInvoice.warehouseId,
            quantity: -(quantity * editQtyInBase),
            type: 'edit_adjustment',
            referenceType: 'sales_invoice',
            referenceId: invoiceId,
            notes: 'تعديل فاتورة مبيعات #$invoiceId',
          );
        }
      }

      final paymentDiff = paid - oldPaid;
      if (paymentDiff != 0) {
        final diff = SalesPaymentCalculator.computeProportionalDiff(
          oldPaymentMethod: oldInvoice.paymentMethod,
          oldTotalPaid: oldPaid,
          oldCashPaid: oldInvoice.cashPaid,
          oldBankPaid: oldInvoice.bankPaid,
          oldClickPaid: oldInvoice.clickPaid,
          newPaymentMethod: paymentMethod,
          newTotalPaid: paid,
        );
        final cashDiff = diff.cashDiff;
        if (cashDiff != 0) {
          final cashSafe = await getDefaultSafeByType('cash');
          if (cashSafe != null) {
            final newBalance = cashSafe.balance + cashDiff;
            final voucherNumber = await generateInvoiceNumber(
              cashDiff > 0 ? 'RV' : 'PV',
            );
            await into(safeTransactions).insert(
              SafeTransactionsCompanion.insert(
                voucherNumber: voucherNumber,
                safeId: cashSafe.id,
                transactionType: cashDiff > 0 ? 'receipt' : 'payment',
                category: 'sales',
                amount: cashDiff.abs(),
                balanceAfter: newBalance,
                referenceType: const Value('sales_invoice'),
                referenceId: Value(invoiceId),
                description: Value(
                  'تعديل فاتورة مبيعات #$invoiceId — دفع متعدد (كاش)',
                ),
              ),
            );
            await adjustSafeBalance(cashSafe.id, cashDiff);
          }
        }

        final bankDiff = diff.bankDiff;
        if (bankDiff != 0) {
          final bankSafe = await getDefaultSafeByType('bank');
          if (bankSafe != null) {
            final newBalance = bankSafe.balance + bankDiff;
            final voucherNumber = await generateInvoiceNumber(
              bankDiff > 0 ? 'RV' : 'PV',
            );
            await into(safeTransactions).insert(
              SafeTransactionsCompanion.insert(
                voucherNumber: voucherNumber,
                safeId: bankSafe.id,
                transactionType: bankDiff > 0 ? 'receipt' : 'payment',
                category: 'sales',
                amount: bankDiff.abs(),
                balanceAfter: newBalance,
                referenceType: const Value('sales_invoice'),
                referenceId: Value(invoiceId),
                description: Value(
                  'تعديل فاتورة مبيعات #$invoiceId — دفع متعدد (بنك)',
                ),
              ),
            );
            await adjustSafeBalance(bankSafe.id, bankDiff);
          }
        }

        final clickDiff = diff.clickDiff;
        if (clickDiff != 0) {
          final clickSafe = await getDefaultSafeByType('click');
          if (clickSafe != null) {
            final newBalance = clickSafe.balance + clickDiff;
            final voucherNumber = await generateInvoiceNumber(
              clickDiff > 0 ? 'RV' : 'PV',
            );
            await into(safeTransactions).insert(
              SafeTransactionsCompanion.insert(
                voucherNumber: voucherNumber,
                safeId: clickSafe.id,
                transactionType: clickDiff > 0 ? 'receipt' : 'payment',
                category: 'sales',
                amount: clickDiff.abs(),
                balanceAfter: newBalance,
                referenceType: const Value('sales_invoice'),
                referenceId: Value(invoiceId),
                description: Value(
                  'تعديل فاتورة مبيعات #$invoiceId — دفع متعدد (كليك)',
                ),
              ),
            );
            await adjustSafeBalance(clickSafe.id, clickDiff);
          }
        }
      }

      if (oldInvoice.customerId != null) {
        final oldRemaining = oldInvoice.total - oldPaid;
        final newRemaining = total - paid;
        final balanceDiff = newRemaining - oldRemaining;
        if (balanceDiff != 0) {
          await adjustPartyBalance(oldInvoice.customerId!, balanceDiff);
        }
      }

      if (shouldRepost) {
        final updated = await getSalesInvoiceById(invoiceId);
        if (updated != null) {
          if (paymentMethod == 'credit') {
            final posted = await autoPostCreditSale(
              updated,
              repostAfterReversal: true,
              repostRevision: repostRevision,
            );
            if (updated.total > 0 && (posted == null || posted == 0)) {
              throw Exception('تعذّر إعادة ترحيل قيد الفاتورة بعد التعديل');
            }
          } else {
            final posted = await autoPostCashSale(
              updated,
              repostAfterReversal: true,
              repostRevision: repostRevision,
            );
            if (updated.total > 0 && (posted == null || posted == 0)) {
              throw Exception('تعذّر إعادة ترحيل قيد الفاتورة بعد التعديل');
            }
          }
        }
      }
      await resignSalesInvoice(invoiceId);
    });
  }
}
