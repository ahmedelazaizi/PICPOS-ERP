// =======================================================================
// SALES ACTIONS DAO
// Extracted from sales_mutations_dao.dart — PIR Phase 3 Batch 1
// Specialized actions: Voiding, hard deletes, and validation helpers
// =======================================================================

part of '../database.dart';

/// Extension for specialized Sales Invoice actions (void, delete, etc.)
extension SalesActionsDao on AppDatabase {

  /// Void a sales invoice (ISS-05: void instead of hard delete)
  /// Preserves the invoice for audit trail, reverses stock and treasury.
  /// [deletedBy]: userId of the operator performing the void (for P0-01 audit trail).
  /// [globalId]: C-02 (Spec 151) / R9 — the void operation's reversal-JE
  /// identity. The caller (SalesRepositoryImpl.voidInvoice / api_sales_handler
  /// .postVoidSale) mints ONE deterministic id from the invoice's own globalId
  /// + verb 'void' and threads the SAME value into both the local reversal here
  /// and the server submit, so the reversal JE converges under
  /// journal_entries.globalId's UNIQUE index instead of surviving DeltaPull as
  /// two rows. Default null keeps standalone behaviour (createJournalEntry mints
  /// its own gid), mirroring voidPurchaseInvoice's {globalId} thread.
  Future<void> voidSalesInvoice(int invoiceId, {String? reason, int? deletedBy, String? globalId}) async {
    await transaction(() async {
      // #Phase4: Check if invoice is locked
      final inv = await (select(
        salesInvoices,
      )..where((i) => i.id.equals(invoiceId))).getSingleOrNull();
      if (inv == null) return;
      if (inv.status == 'voided') {
        throw Exception('الفاتورة ملغية بالفعل');
      }

      // 062 (D1-004): voidPaidInvoice gate. A user voiding a fully-paid
      // invoice must hold the explicit "إلغاء فاتورة مدفوعة" permission,
      // even if they are system admin (segregation of duties).
      final isPaidInFull = inv.paid >= inv.total - 0.01;
      if (isPaidInFull) {
        await permissionEnforcer.requireCriticalOp(
          userId: deletedBy,
          code: PermissionCodes.voidPaidInvoice,
          arabicReason: 'لا يمكن إلغاء فاتورة مدفوعة بالكامل — '
              'يلزم صلاحية "إلغاء فاتورة مدفوعة".',
        );
      }

      // 0. Soft/Hard Period Closing Gating
      await accountingDao.validateFinancialPeriod(inv.invoiceDate, operation: 'إلغاء فاتورة مبيعات');

      // Get invoice items to reverse stock
      final items = await getSalesInvoiceItems(invoiceId);

      for (final item in items) {
        // Restore product stock (add back sold quantity)
        final product = await (select(
          products,
        )..where((p) => p.id.equals(item.productId))).getSingleOrNull();
        if (product != null && product.trackInventory) {
          // UOM: apply quantityInBase conversion for base-unit accuracy
          final voidQtyInBase = item.quantityInBase > 0 ? item.quantityInBase : 1.0;
          final restoreQty = item.quantity * voidQtyInBase;
          // Same asymmetry the sales-return path had: the reversing JE below
          // mirrors the original entry line-for-line, so it books the FROZEN
          // cost — while the stock comes back valued at the CURRENT WAC.
          // Blend at the frozen cost so valuation and the GL agree.
          // Before adjustStock: updateProductWAC reads current_stock.
          await updateProductWAC(
            productId: item.productId,
            newQuantity: restoreQty,
            newUnitCost: item.costPrice,
          );
          await adjustStock(
            productId: item.productId,
            warehouseId: inv.warehouseId,
            quantity: restoreQty,
            type: 'void_reversal',
            referenceType: 'sales_invoice',
            referenceId: invoiceId,
            unitCost: item.costPrice,
            notes: 'إلغاء فاتورة مبيعات #${inv.invoiceNumber}',
          );
        }
      }

      // Reverse treasury transactions (adjust safe balances back)
      final treasuryTxns = await (select(safeTransactions)..where(
            (t) =>
                t.referenceType.equals('sales_invoice') &
                t.referenceId.equals(invoiceId),
          )).get();

      for (final txn in treasuryTxns) {
        final safe = await (select(safes)
              ..where((s) => s.id.equals(txn.safeId)))
            .getSingleOrNull();
        if (safe != null) {
          final reverseAmount = txn.transactionType == 'receipt'
              ? -txn.amount
              : txn.amount;
          // 069 (D5-003): atomic delta-style update — safe under PG
          // Read-Committed. balanceAfter is the projected post-state for
          // the audit row; the actual balance write is the SQL +=.
          final newBalance = safe.balance + reverseAmount;
          final voucherNumber = await generateInvoiceNumber('VD');

          await into(safeTransactions).insert(
            SafeTransactionsCompanion.insert(
              voucherNumber: voucherNumber,
              safeId: safe.id,
              transactionType: txn.transactionType == 'receipt' ? 'payment' : 'receipt',
              category: 'void',
              amount: txn.amount,
              balanceAfter: newBalance,
              referenceType: const Value('sales_invoice_void'),
              referenceId: Value(invoiceId),
              description: Value('عكس حركة إلغاء فاتورة #${inv.invoiceNumber}'),
            ),
          );
          await adjustSafeBalance(safe.id, reverseAmount);
        }
      }

      // Reverse customer balance
      if (inv.customerId != null) {
        // ⚠️ **وفرقُ التقريب يُطرَح — وإلّا صار الإبطالُ يمنح العميلَ رصيداً.**
        // إنشاءُ البيعة لم يُضِف الفرقَ إلى `parties.balance` (‏المصدرُ
        // `sales_mutations_dao` يطرحه)، فإبطالُها بطرحه يمنح دائناً بمقدار
        // ٠٫٠٢ لم يوجد قطّ — ويتراكم بلا قيدٍ يقابله.
        final remaining = inv.total - inv.paid - inv.roundingAdjustment;
        if (remaining > 0) {
          await adjustPartyBalance(inv.customerId!, -remaining);
        }
      }

      // Create reversal journal entry if original was posted.
      //
      // A-03 FIX (Spec 151): the reversal JE MUST post atomically with the
      // stock / treasury / AR reversals performed above. The whole method runs
      // inside a single db.transaction(); previously this block wrapped the
      // createJournalEntry call in a try/catch that swallowed any failure and
      // let the transaction COMMIT anyway ("the void itself is NOT rolled
      // back"). That converted a failed reversal (closed period, missing 4319
      // rounding account, a view/unmapped account) into permanent GL↔subledger
      // divergence: every subledger (stock/treasury/AR) was reversed while the
      // original sale JE stayed live, and there is NO auto-repair for
      // 'sales_invoice_void'. Fail loud instead — let the exception propagate
      // so the enclosing transaction rolls back the ENTIRE void
      // (all-or-nothing). The success path is byte-for-byte unchanged.
      // ── الشرط بقى «فيه قيد؟» بدل «مقفولة؟» ─────────────────────────────
      //
      // البوابة كانت `if (inv.isLocked)`، و`isLocked` بتتحط في تلات مسارات
      // ترحيل من أربعة: `autoPostCashSale` و`autoPostCreditSale`
      // و`autoPostPurchase` بيحطوها، و**`_autoPostDeferredRevenue` لأ**.
      // فطلب توصيل بإيراد مؤجل كان بيتلغي والمخزون والخزينة ورصيد العميل
      // بيتعكسوا، والأستاذ فاضل فيه الذمم والإيراد المقدم على فاتورة ملغية.
      //
      // ربط **صحة الدفاتر** بحقل بيتحط في مكان تاني معناه إن أي مسار ترحيل
      // جديد ينسى يحطه بيعيد نفس الباج. السؤال الصح: فيه قيد مرحَّل
      // للفاتورة دي؟
      //
      // و`deferred_sale` اتضاف للفلتر — كان مستثنى فما كانش هيتلقى أصلاً
      // حتى لو البوابة عدّت.
      {
        // Get original auto-post JE and create a reversal
        final originalJE = await (select(journalEntries)
              ..where((e) =>
                  e.referenceType.isIn(const [
                    'sale',
                    'sales_invoice',
                    'deferred_sale',
                  ]) &
                  e.referenceId.equals(inv.id) &
                  e.isAutoPosted.equals(true))
              ..limit(1))
            .getSingleOrNull();

        if (originalJE != null) {
          final originalLines = await (select(journalEntryLines)
                ..where((l) => l.entryId.equals(originalJE.id)))
              .get();

          final reversalLines = originalLines.map((line) => JournalLine(
                accountId: line.accountId,
                debit: line.credit, // Swap debit/credit
                credit: line.debit,
                description: 'عكس: ${line.description ?? ""}',
              )).toList();

          if (reversalLines.isNotEmpty) {
            // H-09 FIX: Get branchId from warehouse to ensure financial isolation
            final warehouse = await getWarehouseById(inv.warehouseId);
            final branchId = warehouse?.branchId;

            await accountingDao.createJournalEntry(
              description: 'قيد عكسي — إلغاء فاتورة ${inv.invoiceNumber}${reason != null ? " ($reason)" : ""}',
              date: DateTime.now(),
              lines: reversalLines,
              referenceType: 'sales_invoice_void',
              referenceId: invoiceId,
              isAutoPosted: true,
              costCenterId: inv.costCenterId,
              branchId: branchId,
              // C-02 (Spec 151) / R9 — deterministic reversal-JE gid threaded
              // from the caller (same value sent to the server submit). Null
              // (legacy callers) → createJournalEntry mints its own = unchanged.
              globalId: globalId,
            );
          }
        }
      }

      // Mark invoice as voided and soft-deleted (Phase 4)
      // PIR P0-01: record deletedBy for audit trail
      await (update(salesInvoices)..where((i) => i.id.equals(invoiceId))).write(
        SalesInvoicesCompanion(
          status: const Value('voided'),
          notes: Value('${inv.notes ?? ""}\n[ملغي] ${reason ?? "بدون سبب"} - ${DateTime.now().toIso8601String()}'),
          isLocked: const Value(true), // Keep locked
          isDeleted: const Value(true),
          deletedAt: Value(DateTime.now()),
          deletedBy: Value(deletedBy),
        ),
      );
    });
  }

  /// Legacy delete — redirects to void for backward compatibility
  Future<void> deleteSalesInvoice(int invoiceId, {int? deletedBy}) async {
    await voidSalesInvoice(invoiceId, reason: 'حذف (تم تحويله إلى إلغاء)', deletedBy: deletedBy);
  }

  /// Get the total quantity already returned for a specific product on a specific invoice.
  /// Used to prevent returning more than the original sold quantity.
  Future<double> getAlreadyReturnedQty(int invoiceId, int productId) async {
    final result = await customSelect(
      'SELECT COALESCE(SUM(quantity), 0) as total_returned '
      'FROM stock_movements '
      'WHERE reference_type = ? AND reference_id = ? '
      'AND product_id = ? AND movement_type = ?',
      variables: [
        const Variable('sales_invoice'),
        Variable(invoiceId),
        Variable(productId),
        const Variable('return'),
      ],
      readsFrom: {stockMovements},
    ).getSingle();

    return (result.data['total_returned'] as num?)?.toDouble() ?? 0.0;
  }
}
