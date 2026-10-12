// Purchase invoice full edit: reverse old effects, rewrite items, repost.
part of '../database.dart';

extension PurchaseUpdateDao on AppDatabase {
  /// Update a purchase invoice with full edit capability
  /// Reverses old stock amounts, applies new amounts, updates supplier balance
  Future<void> updatePurchaseInvoice({
    required int invoiceId,
    required int supplierId,
    required int warehouseId,
    required List<PurchaseInvoiceItemsCompanion> items,
    required double paid,
    required String paymentMethod,
    String? notes,
    String? supplierInvoiceNumber,
    int? costCenterId,
    // Purchase-edit policy: the caller's userId is the ONLY gate. Required —
    // a null userId is denied (see the requireCriticalOp call below).
    int? userId,
    // ح-1: the edit path had no discount parameter, so re-saving a discounted
    // invoice — even with identical lines — recomputed `total` GROSS and left
    // the `discount` column stale. That silently restored the phantom payable
    // ح-1 exists to prevent, on EVERY edit. Null = keep whatever the header
    // already holds (so callers that don't collect a discount can't wipe one).
    double? discount,
    // J1b (v188): when true the invoice's «حساب المشتريات» becomes
    // [purchaseAccountId] (`null` ⇒ back to the mapped default) BEFORE the
    // repost, so the new JE debits it. False ⇒ the stored value is untouched.
    bool changePurchaseAccount = false,
    int? purchaseAccountId,
  }) async {
    return transaction(() async {
      // Get original invoice
      final oldInvoice = await getPurchaseInvoiceById(invoiceId);
      if (oldInvoice == null) throw Exception('Invoice not found');

      // ═══ 🔴 فاتورةُ الاستيراد لا تُحرَّر من مسار الفاتورة المحلّيّة ═══
      //
      // هذا المسارُ يستقبل مبالغَ **محلّيّةً** ولا يعرف عملةً ولا سعراً، وهو
      // لا يمسّ `currency_id`/`exchange_rate`. فتحريرُ فاتورةِ استيرادٍ هنا
      // يُبقي اللقطةَ تقول «حُوِّلت من USD @ 0.71» فوق مبالغَ أُدخلت
      // بالمحلّيّة — صفٌّ **يناقض نفسَه** ولا شيءَ يبدو معطوباً: القيدُ
      // متّزنٌ والذمّةُ معقولة، والمستندُ وحدَه هو الذي صار يكذب.
      //
      // ⚠️ والمنعُ هنا لا في الشاشة: لهذا المسار مناديان (شاشةُ المشتريات
      //    و`putPurchase` على الخادم)، وحارسٌ في أحدهما يترك الآخرَ مفتوحاً.
      //
      // (‏وأوراقُ الاستيراد نفسُها تُحرَّر من شاشتها عبر
      //  `updateImportPurchaseDetails` — وهي لا تمسّ مالاً.)
      if (oldInvoice.currencyId != null) {
        throw StateError(
          'فاتورةُ استيرادٍ بعملةٍ أجنبيّة — تُحرَّر من شاشة المشتريات '
          'الخارجيّة، وتحريرُها هنا يُبقي سعرَ الصرف فوق مبالغَ محلّيّة',
        );
      }

      // ── Purchase-edit policy (supersedes ISS-04 / 062 D1-004) ────────────
      // Owner decision 2026-07-22: editing a purchase invoice is governed by
      // ONE thing — does the caller hold `purchases_edit`?
      //   • holds it  → UNLIMITED edits, before or after posting. Re-posting
      //     the GL entry is already handled at the end of this method
      //     (_reverseOldPurchaseJournalEntry + autoPostPurchase), so a posted
      //     invoice stays consistent across any number of edits.
      //   • lacks it  → denied outright.
      // `isLocked` is therefore NO LONGER a gate; it stays as the posted-state
      // marker that drives integrityHash verification and the void reversal.
      //
      // Why this replaced the old gate: the previous code demanded the
      // `modify_locked_invoice` critical-op permission whenever isLocked was
      // true, but NO call site ever threaded `userId` down here — so
      // PermissionEnforcer.hasCriticalOp(null, ...) always returned false and
      // EVERY posted purchase invoice was permanently uneditable, even for a
      // system admin holding the permission. The userId is now threaded from
      // every call site (local repo, server putPurchase, client interceptor).
      await permissionEnforcer.requireCriticalOp(
        userId: userId,
        code: PermissionCodes.purchasesEdit,
        arabicReason: 'لا تملك صلاحية تعديل فواتير المشتريات. '
            'يلزم صلاحية "تعديل فاتورة مشتريات".',
      );

      // البند 5: reject a supplier-invoice-number that belongs to a DIFFERENT
      // live invoice of this supplier. Excluding this invoice's own id keeps
      // re-saving under its existing number legal.
      await _assertSupplierInvoiceNumberFree(
        supplierId,
        supplierInvoiceNumber,
        excludeInvoiceId: invoiceId,
      );

      // Audit breadcrumb — editing an already-posted (locked) invoice reverses
      // and re-posts the GL entry, so it is worth a persistent trail even
      // though it is now a permitted operation.
      if (oldInvoice.isLocked) {
        unawaited(DiagnosticLogger.log(
          'PURCHASE-EDIT',
          'posted invoice edited — id=$invoiceId '
          'number=${oldInvoice.invoiceNumber} by userId=$userId '
          'oldTotal=${oldInvoice.total}',
        ));
      }

      // S-COST-2 (Spec 145): the FK that crashes the item hard-delete below is
      // landed_cost_allocations.purchaseItemId (NOT NULL, NO ACTION). Those
      // allocation rows are persisted by calculateAllocations while the sheet
      // is still 'draft' — BEFORE apply — so gating on 'applied' alone would
      // miss the crash (compute-then-cancel leaves draft allocations). Block
      // whenever a non-voided sheet of this invoice has persisted allocations
      // (the real crash predicate). Operator must void the invoice or delete
      // the sheet or use returns instead.
      final pinned = await customSelect(
        '''SELECT lcs.sheet_number AS sn
           FROM landed_cost_allocations lca
           JOIN landed_cost_sheets lcs ON lcs.id = lca.sheet_id
           WHERE lcs.purchase_invoice_id = ? AND lcs.status != 'voided'
           LIMIT 1''',
        variables: [Variable<int>(invoiceId)],
        readsFrom: {landedCostAllocations, landedCostSheets},
      ).getSingleOrNull();
      if (pinned != null) {
        throw Exception(
            'لا يمكن تعديل فاتورة عليها تكاليف محمّلة (${pinned.data['sn']}) — '
            'ألغِ الفاتورة أو احذف ورقة التكاليف أو استخدم المرتجعات.');
      }

      // 0. Soft/Hard Period Closing Gating
      await accountingDao.validateFinancialPeriod(oldInvoice.invoiceDate, operation: 'تعديل فاتورة مشتريات');

      // Get original items
      final oldItems = await getPurchaseInvoiceItems(invoiceId);

      // Reverse old stock quantities and WAC
      final oldProductMap = await getProductsByIds(oldItems.map((i) => i.productId).toList());
      for (final item in oldItems) {
        final product = oldProductMap[item.productId];
        if (product != null && product.trackInventory) {
          // 1. First reverse the WAC impact of the old purchase line
          await reverseProductWAC(
            productId: item.productId,
            reversedQuantity: item.quantity,
            reversedUnitCost: item.unitCost,
          );

          // 2. Reverse the stock
          await adjustStock(
            productId: item.productId,
            warehouseId: oldInvoice.warehouseId,
            quantity: -item.quantity,
            type: 'adjustment',
            referenceType: 'purchase_invoice',
            referenceId: invoiceId,
            // F-02: the inventory GL leg is owned by the base purchase JE
            // (reversed by _reverseOldPurchaseJournalEntry + reposted by
            // autoPostPurchase below). This old-stock reversal must move
            // stock/WAC ONLY — never post a stock_adjustment shrinkage/surplus
            // JE, or it survives the base-JE reversal and corrupts inventory GL.
            postAdjustmentJournal: false,
            notes:
                'تعديل فاتورة مشتريات (حذف قديم) #${oldInvoice.invoiceNumber}',
          );
        }
      }

      // Reverse old supplier balance (if had remaining balance)
      final oldRemaining = oldInvoice.total - oldInvoice.paid;
      if (oldRemaining > 0) {
        await adjustPartyBalance(oldInvoice.supplierId, -oldRemaining);
      }

      // F-02 (Spec 151): reverse the OLD purchase GL journal entry AND the OLD
      // treasury payment here, so the re-post at the end of this method reflects
      // the NEW amounts. Before this fix the method moved stock/WAC/supplier-
      // balance to the new values but left the purchase JE frozen at the OLD
      // amounts (the trailing "simplified — just log" comment) and never touched
      // the safe — GL diverged from inventory/AP and the safe was never adjusted
      // for the payment delta on every edit. This mirrors updateFullSalesInvoice
      // (the sales sibling): delete the old JE + recompute balances, then re-post.
      await _reverseOldPurchaseJournalEntry(invoiceId);
      // F02-1/F02-2: reversing the old payment also reverses any separate GL
      // 'payment' JE (prevents the double-count on re-post) and yields the
      // original payment's safe so we re-record onto the SAME safe.
      final originalPaymentSafeId = await _reverseOldPurchasePayment(invoiceId);

      // Delete old items
      // Cluster 023 / Issue 2 — capture the deleted-row count and log a
      // SYNC-WARN whenever it diverges from oldItems.length. Field reports
      // showed sites whose edit-then-save flow ended up with 2N rows; a
      // mismatch here is the only place a stale duplicate (left by an
      // earlier sync race or a prior buggy version) could survive the
      // delete-then-insert dance and surface as the doubled-items
      // symptom on the next reopen.
      final deletedCount = await (delete(
        purchaseInvoiceItems,
      )..where((i) => i.invoiceId.equals(invoiceId))).go();
      if (deletedCount != oldItems.length) {
        DiagnosticLogger.log(
          'SYNC-WARN',
          'updatePurchaseInvoice deleted=$deletedCount but oldItems.length=${oldItems.length} '
          'for invoice=$invoiceId — pre-existing duplicate purchase items detected and cleaned up.',
        );
      }

      // Delete old batches linked to this invoice
      await (delete(
        productBatches,
      )..where((b) => b.purchaseInvoiceId.equals(invoiceId))).go();

      // Calculate new totals
      double newTotal = 0;
      double newTaxTotal = 0;
      for (final item in items) {
        final qty = item.quantity.present ? item.quantity.value : 1.0;
        final cost = item.unitCost.present ? item.unitCost.value : 0.0;
  // ignore: dead_code
        final rate = item.taxRate.present ? (item.taxRate.value ?? 0.0) : 0.0;
        final subtotal = qty * cost;
        // Same rationale as createPurchaseInvoice: honour the form's
        // per-line taxAmount so editing a mixed invoice keeps exempt
        // rows at zero tax. Spec 151 E-03: round with the SAME expression as
        // the per-line INSERT below so SUM(line.tax) == header.tax exactly.
        final tax = FinancialUtils.round(item.taxAmount.present
  // ignore: dead_code
            ? (item.taxAmount.value ?? 0.0)
            : subtotal * (rate / 100));
        newTotal += subtotal + tax;
        newTaxTotal += tax;
      }

      // ح-1 (trade discount): the edit must produce the SAME shape as create —
      // header stored NET, line costs apportioned, and NO 4316 leg. Storing a
      // net `subtotal` also makes autoPostPurchase's _deriveBalancedLegs
      // compute discountLeg == 0 by construction, so the re-post debits
      // inventory net and credits only the payable.
      final requestedDiscount = FinancialUtils.round(
          discount ?? oldInvoice.discount);
      // نفسُ قاعدةِ الإنشاء: خصمُ المستند لا يقلّ عن مجموع خصوم السطور.
      var explicitLineDiscountSum = 0.0;
      for (final it in items) {
        final d = it.discount.present ? it.discount.value : 0.0;
        if (d > 0) explicitLineDiscountSum += d;
      }
      explicitLineDiscountSum = FinancialUtils.round(explicitLineDiscountSum);
      final effectiveDiscount = requestedDiscount > explicitLineDiscountSum
          ? requestedDiscount
          : explicitLineDiscountSum;
      final grossSubtotal = newTotal - newTaxTotal;
      if (effectiveDiscount > newTotal) {
        throw StateError(
          'الخصم (${effectiveDiscount.toStringAsFixed(2)}) أكبر من إجمالي '
          'الفاتورة (${newTotal.toStringAsFixed(2)}).',
        );
      }
      // 🔴 **والتحريرُ يقرأ الصيغةَ نفسَها التي يقرؤها الإنشاء.** كان هنا
      // معاملٌ نسبيٌّ مكتوبٌ بيده، فتحريرُ فاتورةٍ بخصومِ أصنافٍ كان يُعيد
      // توزيعَها نسبيّاً ويمحو ما كتبه المستخدمُ لكلّ سطر — بلا رسالةٍ، ولا
      // يظهر إلّا في متوسّط التكلفة بعد حين.
      final lineNets = resolvePurchaseLineNets(
        grossPerLine: [
          for (final it in items)
            (it.quantity.present ? it.quantity.value : 1.0) *
                (it.unitCost.present ? it.unitCost.value : 0.0),
        ],
        explicitDiscountPerLine: [
          for (final it in items) it.discount.present ? it.discount.value : 0.0,
        ],
        documentDiscount: effectiveDiscount,
      );
      newTotal = FinancialUtils.round(newTotal - effectiveDiscount);
      final netSubtotal = FinancialUtils.round(grossSubtotal - effectiveDiscount);

      final newRemaining = newTotal - paid;
      final newStatus = newRemaining <= 0
          ? 'paid'
          : (paid > 0 ? 'partial' : 'pending');

      // Update invoice header
      await (update(
        purchaseInvoices,
      )..where((i) => i.id.equals(invoiceId))).write(
        PurchaseInvoicesCompanion(
          supplierId: Value(supplierId),
          warehouseId: Value(warehouseId),
          subtotal: Value(netSubtotal),
          discount: Value(effectiveDiscount),
          tax: Value(newTaxTotal),
          total: Value(newTotal),
          paid: Value(paid),
          paymentMethod: Value(paymentMethod),
          status: Value(newStatus),
          notes: Value(notes),
          supplierInvoiceNumber: Value(supplierInvoiceNumber),
        ),
      );
      await resignPurchaseInvoice(invoiceId);

      // Insert new items and update stock
      final newProductIds = items.map((i) => i.productId.present ? i.productId.value : 0)
          .where((id) => id > 0).toList();
      final newProductMap = await getProductsByIds(newProductIds);

      for (var lineAt = 0; lineAt < items.length; lineAt++) {
        final item = items[lineAt];
        final productId = item.productId.present ? item.productId.value : 0;
        final quantity = item.quantity.present ? item.quantity.value : 1.0;
        // ح-1 (trade discount): apportion on the edit path too, so re-saving
        // never restores gross line costs into stock/WAC.
        //
        // 🔴 **ومرّةً واحدةً بالضبط** — الصريحُ وحصّتُه من الباقي معاً في
        // [resolvePurchaseLineNets]، فلا ضربَ في معاملٍ هنا يُطبّقه ثانيةً.
        final unitCost = quantity > 0
            ? FinancialUtils.round(lineNets[lineAt] / quantity)
            : 0.0;
  // ignore: dead_code
        final taxRate = item.taxRate.present ? (item.taxRate.value ?? 0.0) : 0.0;
        // Spec 151 E-03: honour the passed per-line taxAmount (matching the
        // header loop above) instead of always recomputing from the rate, so an
        // exempt line (rate>0, amount=0) stores 0 tax — no phantom input VAT
        // for a later return to reverse — and SUM(line.tax) == header.tax.
        // Fallback-recompute only when no amount was supplied; round to the
        // financial precision.
        final taxAmount = FinancialUtils.round(item.taxAmount.present
  // ignore: dead_code
            ? (item.taxAmount.value ?? 0.0)
            : (quantity * unitCost) * (taxRate / 100));

        final hasLineGid = item.globalId.present &&
            (item.globalId.value?.isNotEmpty ?? false);
        await into(purchaseInvoiceItems).insert(
          item.copyWith(
            invoiceId: Value(invoiceId),
            unitCost: Value(unitCost),
            // The rounded net is authoritative; the remainder belongs to
            // the largest line rather than being lost in unit-cost division.
            total: Value(FinancialUtils.round(lineNets[lineAt] + taxAmount)),
            taxAmount: Value(taxAmount),
            // UUID-First Phase 1 Slice 3: stable per-line identity.
            globalId: hasLineGid ? item.globalId : Value(UuidV7.generate()),
          ),
        );

        // Update product stock (add new quantity)
        final product = newProductMap[productId];
        if (product != null && product.trackExpiry &&
            ((item.batchNumber.value?.trim().isNotEmpty ?? false) == false ||
                item.expiryDate.value == null)) {
          throw StateError('رقم الدفعة وتاريخ الصلاحية مطلوبان للصنف ${product.name}.');
        }
        if (product != null && product.trackInventory) {
          // 1. Update WAC Cost with new values
          await updateProductWAC(
            productId: productId,
            newQuantity: quantity,
            newUnitCost: unitCost,
          );

          // 2. Adjust Stock
          // B10 (S-INV-COST / PUR-1): same gap as createPurchaseInvoice —
          // thread the edited line's real unitCost so the per-warehouse
          // average_cost blend uses the actual receipt cost, not whatever
          // updateProductWAC just wrote to the global costPrice.
          await adjustStock(
            productId: productId,
            warehouseId: warehouseId,
            quantity: quantity,
            type: 'purchase',
            referenceType: 'purchase_invoice',
            referenceId: invoiceId,
            notes: 'تعديل فاتورة مشتريات #${oldInvoice.invoiceNumber}',
            unitCost: unitCost,
          );
        }

        // Create batch if expiry tracking
        if (product != null &&
            product.trackExpiry &&
            item.expiryDate.value != null) {
          await into(productBatches).insert(
            ProductBatchesCompanion.insert(
              productId: productId,
              warehouseId: warehouseId,
              batchNumber: item.batchNumber.value ?? oldInvoice.invoiceNumber,
              quantity: Value(quantity),
              initialQuantity: Value(quantity),
              productionDate: item.productionDate,
              expiryDate: item.expiryDate.value!,
              unitCost: Value(unitCost),
              purchaseInvoiceId: Value(invoiceId),
            ),
          );
          await syncDefaultBinStock(productId, warehouseId);
        }
      }

      // Update new supplier balance if on credit
      if (newRemaining > 0) {
        await adjustPartyBalance(supplierId, newRemaining);
      }

      // F-02 (Spec 151): re-record the treasury payment for the NEW `paid`
      // amount (the old payment safe_transaction(s) were reversed above). Uses
      // the SAME _recordPurchasePayment helper as createPurchaseInvoice:586-589
      // so the safe debit + safe_transaction row are identical in shape to a
      // fresh purchase — the safe now moves by exactly (newPaid − oldPaid).
      // F02-2: thread the original payment's safe so a payment made from a
      // non-default safe is re-recorded onto that SAME safe (not the global
      // default). Null when there was no prior payment → default resolution.
      SafeTransactionData? repostPaymentTxn;
      if (paid > 0) {
        repostPaymentTxn = await _recordPurchasePayment(
          invoiceId,
          paid,
          paymentMethod,
          costCenterId,
          safeId: originalPaymentSafeId,
          supplierId: supplierId,
        );
        // Same fail-loud contract as the create path: an edit that says "paid"
        // but moves no safe would leave the payable open with no trail.
        if (repostPaymentTxn == null) {
          throw StateError(
            'تعذّر تسجيل دفعة تعديل فاتورة المشتريات #$invoiceId: لا يوجد '
            'صندوق مطابق لطريقة الدفع.',
          );
        }
      }

      // F-02 (Spec 151): re-post the purchase GL entry with the NEW amounts.
      // autoPostPurchase reads the header we just updated, is dedup/TOCTOU-
      // guarded (the old JE was deleted above so this posts fresh), and builds a
      // balanced JE via the canonical path — exactly how updateFullSalesInvoice
      // re-posts through autoPostCashSale/autoPostCreditSale after deleting the
      // old sale JE. Balanced-by-construction; createJournalEntry hard-fails an
      // imbalance so a broken COA rolls the whole edit back (R3, fail-loud).
      if (changePurchaseAccount) {
        await setPurchaseInvoicePurchaseAccountId(invoiceId, purchaseAccountId);
      }
      final repostInvoice = await getPurchaseInvoiceById(invoiceId);
      if (repostInvoice != null && repostInvoice.total > 0) {
        await autoPostPurchase(
          repostInvoice,
          costCenterId: costCenterId ?? repostInvoice.costCenterId,
        );
      }

      // البند 6 — re-post the settlement leg for the NEW payment. The old
      // payment JE was reversed by _reverseOldPurchasePayment above, and
      // autoPostPurchase now credits the payable for the FULL total, so
      // without this the payable would stay open even though the safe moved.
      if (repostPaymentTxn != null) {
        final repostJeId = await accountingDao.autoPostPayment(
          repostPaymentTxn,
          costCenterId: costCenterId ?? repostInvoice?.costCenterId,
        );
        if (repostJeId == null) {
          throw StateError(
            'تعذّر ترحيل قيد سداد تعديل فاتورة المشتريات #$invoiceId: '
            'حساب الصندوق أو حساب الذمم غير مربوط في الدليل المحاسبي.',
          );
        }
      }
      await resignPurchaseInvoice(invoiceId);
    });
  }
}
