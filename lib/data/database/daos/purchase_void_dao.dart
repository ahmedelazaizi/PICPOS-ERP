// Purchase invoice void (reverse stock, treasury, party balance, GL) and legacy delete.
part of '../database.dart';

extension PurchaseVoidDao on AppDatabase {
  /// Void a purchase invoice (ISS-05: void instead of hard delete)
  /// Preserves the invoice for audit trail, reverses stock and treasury
  /// [deletedBy]: userId of the operator performing the void (PIR P0-01 audit trail).
  /// [globalId]: PR-2 (pre-deploy batch B6) — the void operation's identity,
  /// minted once by the caller and threaded into both the server submit and
  /// this method's reversal JE (R9). When omitted, the reversal JE derives a
  /// deterministic id from the invoice's own globalId + verb 'void' (same
  /// `JournalEntryGid.compute` pattern the landed-cost reversal below uses),
  /// so client-mode retries and the standalone path both converge on the
  /// same JE identity without needing an explicit value.
  Future<void> voidPurchaseInvoice(int invoiceId, {String? reason, int? deletedBy, String? globalId}) async {
    await transaction(() async {
      final invoice = await getPurchaseInvoiceById(invoiceId);
      if (invoice == null) return;

      if (invoice.status == 'voided') {
        throw Exception('الفاتورة ملغية بالفعل');
      }

      // 062 (D1-004): voidPaidInvoice gate for purchase invoices.
      final isPaidInFull = invoice.paid >= invoice.total - 0.01;
      if (isPaidInFull) {
        await permissionEnforcer.requireCriticalOp(
          userId: deletedBy,
          code: PermissionCodes.voidPaidInvoice,
          arabicReason: 'لا يمكن إلغاء فاتورة مشتريات مدفوعة بالكامل — '
              'يلزم صلاحية "إلغاء فاتورة مدفوعة".',
        );
      }

      // 0. Soft/Hard Period Closing Gating
      await accountingDao.validateFinancialPeriod(invoice.invoiceDate, operation: 'إلغاء فاتورة مشتريات');

      final items = await getPurchaseInvoiceItems(invoiceId);
      final productMap = await getProductsByIds(items.map((i) => i.productId).toList());
      for (final item in items) {
        final product = productMap[item.productId];
        if (product != null && product.trackInventory) {
          await adjustStock(
            productId: item.productId,
            warehouseId: invoice.warehouseId,
            quantity: -item.quantity,
            type: 'void_reversal',
            referenceType: 'purchase_invoice',
            referenceId: invoiceId,
            unitCost: item.unitCost,
            notes: 'إلغاء فاتورة مشتريات #${invoice.invoiceNumber}',
          );
          // B8 (S-LANDED-LIFECYCLE / PUR-2a): the WAC recalc used to run
          // right here, but at this point the invoice is still 'active'
          // (the status flip happens near the end of this method) and any
          // applied landed-cost sheet is still 'applied' (its reversal runs
          // further below too) — recalculateProductWAC's PR-1 fix filters
          // on BOTH, so recalculating this early would still count this
          // void's own purchase cost and landed allocation, a no-op in
          // disguise. The real recalc now runs once, after every status
          // flip below, so it actually excludes them.
        }
      }

      // Reverse treasury transactions
      final treasuryTxns = await (select(safeTransactions)..where(
            (t) =>
                t.referenceType.equals('purchase_invoice') &
                t.referenceId.equals(invoiceId),
          )).get();

      final txnSafeIds = treasuryTxns.map((t) => t.safeId).toSet().toList();
      final safeList = await (select(safes)..where((s) => s.id.isIn(txnSafeIds))).get();
      final safeMap = {for (final s in safeList) s.id: s};

      // البند 6 / regression guard: since the purchase JE stopped carrying the
      // cash leg (it now credits the payable in full and the settlement is a
      // SEPARATE `referenceType:'payment'` JE posted by autoPostPayment), the
      // void below — which only mirrors the purchase JE — no longer undoes the
      // cash movement. Left unreversed it produced a phantom AP DEBIT and left
      // GL cash permanently below `safes.balance` by the paid amount.
      //
      // Reverse the settlement JE per payment transaction. Same call
      // `_reverseOldPurchasePayment` uses on the edit path — but here we must
      // NOT touch `safes.balance`, because the treasury loop below already
      // restores it via its own reversal transactions.
      for (final txn in treasuryTxns) {
        if (txn.transactionType != 'payment') continue;
        await reverseAutoPostedJournalEntriesFor(
          referenceType: 'payment',
          referenceId: txn.id,
          voidReferenceType: 'payment_void',
          sourceGlobalId: txn.globalId ?? 'paytxn${txn.id}',
          description: 'عكس قيد سداد (إلغاء فاتورة مشتريات) #$invoiceId',
        );
      }

      for (final txn in treasuryTxns) {
        final safe = safeMap[txn.safeId];
        if (safe != null) {
          final reverseAmount = txn.transactionType == 'payment'
              ? txn.amount
              : -txn.amount;
          final newBalance = safe.balance + reverseAmount;
          final voucherNumber = await generateInvoiceNumber('VD');

          await into(safeTransactions).insert(
            SafeTransactionsCompanion.insert(
              voucherNumber: voucherNumber,
              safeId: safe.id,
              transactionType: txn.transactionType == 'payment' ? 'receipt' : 'payment',
              category: 'void',
              amount: txn.amount,
              balanceAfter: newBalance,
              referenceType: const Value('purchase_invoice_void'),
              referenceId: Value(invoiceId),
              description: Value('عكس حركة إلغاء فاتورة مشتريات #${invoice.invoiceNumber}'),
            ),
          );
          // H15 — عكسٌ ذرّيّ بمقدار `reverseAmount` (موجبٌ للسداد المعكوس،
          // سالبٌ لغيره). `newBalance` لقطةُ `balanceAfter` وحدَها.
          await adjustSafeBalance(safe.id, reverseAmount);
        }
      }

      // Reverse supplier balance
      final remaining = invoice.total - invoice.paid;
      if (remaining > 0) {
        await adjustPartyBalance(invoice.supplierId, -remaining);
      }

      // Create reversal journal entry if one was posted.
      //
      // The `invoice.isLocked` gate that used to wrap this was dead-wrong:
      // `createPurchaseInvoice` posts its JE inline and NEVER sets `isLocked`
      // (only autoPostPurchase / AutoPostingService do). So voiding any
      // invoice created from the purchases screen skipped the reversal
      // entirely — stock was returned and the safe restored while the
      // inventory GL account kept the full debit against zero stock, and the
      // supplier payable kept its credit. Pre-existing; surfaced by the void
      // regression test added with the البند 6 pass-through work.
      //
      // The lookup below already keys on referenceType + referenceId +
      // isAutoPosted, so "was anything posted?" is answered by whether it
      // finds a row — the flag added nothing but the bug.
      {
        try {
          final originalJE = await (select(journalEntries)
                ..where((e) =>
                    e.referenceType
                        .isIn(kPurchaseJeReferenceTypes.toList()) &
                    e.referenceId.equals(invoice.id) &
                    e.isAutoPosted.equals(true))
                ..limit(1))
              .getSingleOrNull();

          if (originalJE != null) {
            final originalLines = await (select(journalEntryLines)
                  ..where((l) => l.entryId.equals(originalJE.id)))
                .get();

            final reversalLines = originalLines.map((line) => JournalLine(
                  accountId: line.accountId,
                  debit: line.credit,
                  credit: line.debit,
                  description: 'عكس: ${line.description ?? ""}',
                )).toList();

            if (reversalLines.isNotEmpty) {
              // H-09 FIX: Get branchId from warehouse to ensure financial isolation
              final warehouse = await getWarehouseById(invoice.warehouseId);
              final branchId = warehouse?.branchId;

              // PR-2 (batch B6) / R9: deterministic globalId so this reversal
              // JE converges across client/mirror + server instead of each
              // side minting its own random id (which would survive DeltaPull
              // as two rows). Prefer the caller-supplied [globalId] (threaded
              // from the same value sent to the server submit); fall back to
              // deriving one from the invoice's own globalId — mirrors the
              // landed-cost reversal a few lines below.
              final voidJeGid = (globalId != null && globalId.isNotEmpty)
                  ? globalId
                  : JournalEntryGid.compute(
                      sourceType: JournalEntryGid.sourcePurchase,
                      sourceGid: invoice.globalId ?? 'invid$invoiceId',
                      verb: 'void',
                    );

              await accountingDao.createJournalEntry(
                description: 'قيد عكسي — إلغاء فاتورة مشتريات ${invoice.invoiceNumber}${reason != null ? " ($reason)" : ""}',
                date: DateTime.now(),
                lines: reversalLines,
                referenceType: 'purchase_invoice_void',
                referenceId: invoiceId,
                isAutoPosted: true,
                costCenterId: invoice.costCenterId,
                branchId: branchId,
                globalId: voidJeGid,
              );
            }
          }
        } catch (e, st) {
          // B7 (S-FAILLOUD / PUR-4): this used to be non-blocking — the
          // reversal JE's failure was logged and swallowed while the void
          // proceeded to reverse stock/treasury/supplier-balance and flip
          // the invoice to 'voided' anyway. That leaves the ORIGINAL
          // purchase JE live in the GL with none of its financial effects
          // reflected anywhere else (inventory reversed, GL untouched) — a
          // financial side-effect with no balanced counter-entry, and the
          // caller saw a false "void succeeded". Log to the audit trail for
          // visibility (best-effort — see inner catch), then RETHROW so the
          // whole transaction (stock reversal, treasury reversal, supplier-
          // balance reversal, invoice status flip) rolls back atomically.
          // Note: because this insert shares the SAME db.transaction() that
          // is about to roll back, it is rolled back too — the debugPrint
          // above is therefore the durable trace for this failure; the
          // logActivity call is kept for the (rare) case a future refactor
          // moves it off this connection, and as a hint in case a partial
          // commit is ever observed.
          debugPrint('[ISS-05] Purchase reversal JE failed — logging to audit trail: $e\n$st');
          try {
            await logActivity(
              userId: deletedBy ?? 0,
              userName: 'System',
              action: 'accounting_warning',
              entityType: 'purchase_invoice',
              entityId: invoiceId,
              description:
                  '[P1-02] فشل القيد العكسي عند إلغاء فاتورة المشتريات #${invoice.invoiceNumber}: $e',
            );
          } catch (error, stack) {
             await DiagnosticLogger.logError(
               'PURCHASE-AUDIT',
               'reversal failure audit log failed',
               error,
               stack,
             );
           }
          rethrow;
        }
      }

      // S-COST-2 (Spec 145): reverse any APPLIED landed-cost sheet's JE so the
      // capitalized freight/customs does not linger in the inventory GL after
      // the void, and un-apply the sheet. Independent of invoice.isLocked — a
      // landed JE exists whenever the sheet was applied.
      final landedSheets =
          await getLandedCostSheets(purchaseInvoiceId: invoiceId);
      for (final sheet in landedSheets.where((s) => s.status == 'applied')) {
        try {
          final landedJE = await (select(journalEntries)
                ..where((e) =>
                    e.referenceType.equals('landed_cost') &
                    e.referenceId.equals(sheet.id) &
                    e.isAutoPosted.equals(true))
                ..limit(1))
              .getSingleOrNull();
          if (landedJE != null) {
            final lines = await (select(journalEntryLines)
                  ..where((l) => l.entryId.equals(landedJE.id)))
                .get();
            final reversalLines = lines
                .map((l) => JournalLine(
                      accountId: l.accountId,
                      debit: l.credit,
                      credit: l.debit,
                      description: 'عكس: ${l.description ?? ""}',
                    ))
                .toList();
            if (reversalLines.isNotEmpty) {
              final warehouse = await getWarehouseById(invoice.warehouseId);
              await accountingDao.createJournalEntry(
                description:
                    'عكس تكاليف محملة ${sheet.sheetNumber} — إلغاء فاتورة #${invoice.invoiceNumber}',
                date: DateTime.now(),
                lines: reversalLines,
                referenceType: 'landed_cost_void',
                referenceId: sheet.id,
                isAutoPosted: true,
                costCenterId: invoice.costCenterId,
                branchId: warehouse?.branchId,
                globalId: JournalEntryGid.compute(
                  sourceType: JournalEntryGid.sourceLandedCost,
                  sourceGid: 'sheet${sheet.id}',
                  verb: 'void',
                ),
              );
            }
          }
          // B7 (S-FAILLOUD / PUR-4): only flip the sheet to 'voided' AFTER
          // its reversal JE has actually posted (or there was genuinely
          // nothing to reverse — landedJE == null / no lines). Previously
          // this write ran unconditionally after the try/catch, so a sheet
          // whose reversal JE failed still got marked voided — the
          // capitalized freight/customs stayed live in the inventory GL
          // while the sheet record claimed it had been reversed.
          await (update(landedCostSheets)..where((s) => s.id.equals(sheet.id)))
              .write(const LandedCostSheetsCompanion(status: Value('voided')));
        } catch (e) {
          // B7: was non-blocking (log + swallow, sheet still flipped below).
          // Now rethrows — see the purchase-reversal catch above for the
          // full rationale (no financial side-effect may survive with its
          // counter-entry missing). The sheet status update above is
          // skipped on this path since it sits inside the try, after the
          // post, so a failed reversal leaves the sheet 'applied' — honest
          // about the fact its JE was never reversed.
          debugPrint(
              '[S-COST-2] landed reversal failed for sheet ${sheet.id}: $e');
          try {
            await logActivity(
              userId: deletedBy ?? 0,
              userName: 'System',
              action: 'accounting_warning',
              entityType: 'purchase_invoice',
              entityId: invoiceId,
              description:
                  'فشل عكس قيد التكاليف المحمّلة ${sheet.sheetNumber} عند إلغاء الفاتورة #${invoice.invoiceNumber}: $e',
            );
          } catch (error, stack) {
             await DiagnosticLogger.logError(
               'PURCHASE-AUDIT',
               'landed-cost reversal audit log failed',
               error,
               stack,
             );
           }
          rethrow;
        }
      }

      // Mark invoice as voided and soft-deleted (Phase 4)
      // PIR P0-01: record deletedBy for audit trail
      await (update(purchaseInvoices)..where((i) => i.id.equals(invoiceId))).write(
        PurchaseInvoicesCompanion(
          status: const Value('voided'),
          notes: Value('${invoice.notes ?? ""}\n[ملغي] ${reason ?? "بدون سبب"} - ${DateTime.now().toIso8601String()}'),
          isLocked: const Value(true),
          isDeleted: const Value(true),
          deletedAt: Value(DateTime.now()),
          deletedBy: Value(deletedBy),
        ),
      );

      // B8 (S-LANDED-LIFECYCLE / PUR-2a): recalc WAC HERE — after BOTH the
      // invoice header is marked 'voided'/isDeleted (just above) AND the
      // landed-cost sheet(s), if any, were flipped away from 'applied'
      // (the loop above). recalculateProductWAC's PR-1 fix excludes both a
      // voided invoice's own purchase lines and its landed allocation, so
      // running it only now actually unwinds the void's cost impact — one
      // call per affected product (dedup: an invoice can repeat a product
      // across multiple lines).
      final affectedProductIds = items.map((i) => i.productId).toSet();
      for (final pid in affectedProductIds) {
        final product = productMap[pid];
        if (product != null && product.trackInventory) {
          await recalculateProductWAC(pid);
        }
      }
    });
  }

  /// Legacy delete — redirects to void for backward compatibility
  Future<void> deletePurchaseInvoice(int invoiceId, {int? deletedBy}) async {
    await voidPurchaseInvoice(invoiceId, reason: 'حذف (تم تحويله إلى إلغاء)', deletedBy: deletedBy);
  }
}
