// ═══════════════════════════════════════════════════════════════════════════
// PURCHASE DAO - Purchase Invoice and Related Operations
// ═══════════════════════════════════════════════════════════════════════════
//
// This file contains all purchase-related database operations.
//
// File map (all `part of database.dart`; extensions on AppDatabase):
//   purchase_dao.dart: createPurchaseInvoice (full create: stock, WAC, batches, treasury, GL) (this file)
//   purchase_models.dart: PurchaseInvoiceSummary DTO
//   purchase_queries_dao.dart: invoice reads, watchers, paged / date-range / supplier lookups
//   purchase_return_reads_dao.dart: purchase/sales return record + item-detail reads
//   purchase_insert_support_dao.dart: insertPurchaseInvoiceWithoutStock, supplier-invoice-number guard, payment recording
//   purchase_update_dao.dart: updatePurchaseInvoice (full edit with reversal + repost)
//   purchase_payments_dao.dart: old-JE / old-payment reversal helpers, addPurchasePayment, payment/status updates
//   purchase_void_dao.dart: voidPurchaseInvoice (+ legacy deletePurchaseInvoice)
//   purchase_summary_dao.dart: getPurchaseInvoiceSummary (SQL totals)
// ═══════════════════════════════════════════════════════════════════════════

part of '../database.dart';

/// Extension for Purchase-related database operations
extension PurchaseDao on AppDatabase {

  /// Create a complete purchase invoice with items
  Future<int> createPurchaseInvoice({
    required int supplierId,
    required int warehouseId,
    required List<PurchaseInvoiceItemsCompanion> items,
    required double paid,
    String paymentMethod = 'cash',
    String? supplierInvoiceNumber,
    String? notes,
    DateTime? invoiceDate,
    int? costCenterId,
    int? safeId,
    // UUID-First (Phase 1)
    String? globalId,
     double? paymentRate,
     double? foreignAmount,
    // 062 (D1-004): caller's userId for the overrideCreditLimit gate.
    int? userId,
    // أمرُ الشراء المصدر — «ربط أمر شراء» من داخل الفاتورة (قرارُ المالك
    // 2026-09-18). ويُستهلَك **في نفس هذه المعاملة**: لولا ذلك لبقي مفتوحاً
    // بعد أن دخلت بضاعتُه، فيحوّله أحدٌ ثانيةً وتدخل مرّتَين.
    int? sourceOrderId,
    // Client issue ح-1 (2026-07-25): invoice-level discount. Was accepted by
    // the form, dropped on the way down, and never reached the DAO — so the
    // header stored the GROSS total while the operator paid the NET, leaving
    // a permanent phantom payable on the supplier for the discount amount.
    double discount = 0,
    // ═══ v174 / المرحلة ٨ — عملةُ الفاتورة ولقطةُ سعرِها ═══
    //
    // 🔴 **والمبالغُ الواصلةُ محلّيّةٌ بالفعل.** التحويلُ يقع مرّةً واحدةً في
    //    النموذج (`import_purchase_plan.foreignToLocal`)، لأنّ للشراء
    //    **مسارَين** — هذا، وحمولةُ JSON إلى الخادم في وضع العميل ثمّ
    //    `insertPurchaseInvoiceWithoutStock` للنسخة المحلّيّة. فتحويلٌ هنا
    //    يعني ثلاثةَ مواضعِ تحويلٍ يتفرّق بينها رقمُ الذمّة صامتاً.
    //
    //    فهاتان **لقطةٌ للسجلّ** لا مُعامِلٌ يُعاد تطبيقُه، ولا قارئَ يضرب
    //    بهما. راجع [PurchaseInvoices.exchangeRate].
    int? currencyId,
    double? exchangeRate,
    // وسمُ الاستيراد — يُكتَب **داخلَ هذه المعاملة**. راجع
    // [ImportPurchasesDao._writeImportPurchaseDetails].
    ImportDocumentFields? importDetails,
    // J1b (v188) — the invoice's chosen «حساب المشتريات»; `null` ⇒ the mapped
    // 'inventory' default. Written before the JE below reads it.
    int? purchaseAccountId,
  }) async {
    // 🔴 **الزوجُ يُفحَص قبل المعاملة.** عملةٌ بلا سعرٍ تُقرأ لاحقاً على
    //    أنّها ١، فتُقيَّد ألفُ دولارٍ على المورّد بألفِ وحدةٍ محلّيّة —
    //    والقيدُ متّزنٌ على الرقم الخاطئ فلا يمسكه فحصُ اتّزان. وسعرٌ بلا
    //    عملةٍ مُعامِلٌ بلا وحدةٍ لا يُعرَف ما يصف.
    final badRate = validateExchangeRate(
      currencyId: currencyId,
      localPerForeign: exchangeRate,
    );
    if (badRate != null) throw ArgumentError(badRate);
    // ⚠️ **وطولُ الحقول المستنديّة لا يُفحَص هنا** — يفحصه
    //    [ImportPurchasesDao._writeImportPurchaseDetails] قبل أن يكتب،
    //    وهو يقع قبل حلقة السطور فلا تتحرّك بضاعةٌ ولا تُحسَب تكلفةٌ قبله،
    //    ويرمي **نفسَ** `ArgumentError` بنفس الرسالة.
    //
    // 🔴 وكانت هنا نسخةٌ ثانيةٌ منه فنجت منها طفرةٌ تُسقطها: الاختبارُ
    //    بقي أخضرَ لأنّ الفحصَ الداخليَّ يمسك عينَ الحالة. وحارسٌ لا
    //    تُغيّر إزالتُه شيئاً **ليس حارساً** — هو نسخةٌ تُوهم بحمايةٍ
    //    مضاعَفة وتنقسم عن أصلها عند أوّل تعديلٍ على أحدهما.

    return transaction(() async {
      // 0. Soft/Hard Period Closing Gating
      //
      // بتاريخ **الفاتورة** مش النهاردة. الفحص على `DateTime.now()` كان
      // بيخلّي قفل الفترة متجاوَز على مستوى المستند: فاتورة مؤرَّخة مارس
      // بتتقبل حتى لو مارس مقفول، لأن الفحص بيتم على أغسطس.
      final effectiveInvoiceDate = invoiceDate ?? DateTime.now();
      await accountingDao.validateFinancialPeriod(effectiveInvoiceDate,
          operation: 'فاتورة مشتريات');

      // أهليّةُ الأمر تُفحَص **قبل** أن يتحرّك شيء: الرفضُ بعد إدخال
      // البضاعة يعتمد على تراجع المعاملة وحدَه، والرسالةُ تصل المستخدمَ
      // بعد أن رأى نجاحاً.
      if (sourceOrderId != null) {
        await _requireConsumablePurchaseOrder(sourceOrderId);
      }

      double taxTotal = 0;
      double total = 0;
      double rawMaterialSubtotal = 0;
      double subtotalSum = 0;
      // مواضعُ سطور الخامات — يُجمَع نصيبُها من **الصافي** بعد الخصم
      // أدناه، لا بضربِ إجماليّها في معاملٍ واحد.
      final rawMaterialLineIndexes = <int>{};

       double negativeStockCostAdjustment = 0.0;

      for (var lineAt = 0; lineAt < items.length; lineAt++) {
        final item = items[lineAt];
        final qty = item.quantity.present ? item.quantity.value : 1.0;
        final cost = item.unitCost.present ? item.unitCost.value : 0.0;
  // ignore: dead_code
        final rate = item.taxRate.present ? (item.taxRate.value ?? 0.0) : 0.0;
        final subtotal = qty * cost;
        // Per-line tax toggle: one invoice can mix taxable and exempt
        // items, so the form passes `taxAmount=0` for exempt lines while
        // still carrying the product's rate. Honour the passed amount
        // when present; only recompute from rate for callers that did
        // not supply it (legacy / outbox replays).
        //
        // Spec 151 E-03: round to the financial precision here too, using the
        // SAME expression the per-line INSERT below now uses, so
        // SUM(line.tax) == header.tax exactly (no float-noise drift).
        final tax = FinancialUtils.round(item.taxAmount.present
  // ignore: dead_code
            ? (item.taxAmount.value ?? 0.0)
            : subtotal * (rate / 100));

        subtotalSum += subtotal;
        // نصيب الخامات من الإجمالي. الشراء كان بيدخّل **كل** الأصناف على
        // ١١٣٦ بينما استهلاك التصنيع بيسحب من ١١٣١، فالخامة بتدخل حساب
        // وتخرج من حساب تاني و١١٣١ بيبقى رصيد أصل سالب مع كل أمر إنتاج.
        if (item.productId.present) {
          final p = await getProductById(item.productId.value);
          if (inventoryAccountPurposeForProduct(p?.productType) ==
              'raw_materials') {
            rawMaterialSubtotal += subtotal;
            rawMaterialLineIndexes.add(lineAt);
          }
        }
        total += subtotal + tax;
        taxTotal += tax;
      }

      // ح-1 — TRADE discount (owner decision 2026-07-25). IAS 2.11 requires a
      // trade discount to be DEDUCTED FROM THE COST of inventory, not booked
      // as income. So the discount is apportioned pro-rata into the line unit
      // costs, `subtotal` is stored NET, and no purchase-discount (4316) leg is
      // posted at all.
      //
      // Consequences that fall out of this, all of them correct:
      //   • WAC reflects the true landed cost (10 @ 100 less 100 → 90).
      //   • The inventory GL debit equals Σ(qty × cost), so the GL ↔ stock
      //     valuation reconciliation stays tied.
      //   • A later purchase RETURN refunds the net cost, so a discounted
      //     invoice can no longer refund more cash than was ever paid.
      final requestedDiscount =
          discount > 0 ? FinancialUtils.round(discount) : 0.0;
      // 🔴 **وخصمُ المستند لا يقلّ عن مجموع خصوم السطور.**
      // [resolvePurchaseLineNets] تقرأ خصمَ المستند على أنّه **المجموع**
      // وتحفر منه الصريحَ. فمنادٍ يمرّر خصومَ سطورٍ وخصمَ مستندٍ صفراً كان
      // يحصل على سطورٍ مخصومةٍ وترويسةٍ **غيرِ مخصومة**: مجموعُ السطور ٩٠٠
      // والترويسةُ ١٠٠٠. والفرقُ ذمّةٌ على المورّد لا يقابلها مخزونٌ دخل،
      // ولا يمسكه فحصُ اتّزانٍ لأنّ القيدَ متّزنٌ على الرقم الخاطئ.
      //
      // ⚠️ **وبلا خصومِ سطورٍ يبقى المطلوبُ كما هو حرفاً** — فلا
      // يتغيّر رقمٌ لأيّ منادٍ قائم (صندوقٌ صادرٌ · إعادةُ API · تحويلُ
      // أمرِ شراء)، وهذا شرطُ الإصلاح لا أثرُه الجانبيّ.
      var explicitLineDiscountSum = 0.0;
      for (final it in items) {
        final d = it.discount.present ? it.discount.value : 0.0;
        if (d > 0) explicitLineDiscountSum += d;
      }
      explicitLineDiscountSum = FinancialUtils.round(explicitLineDiscountSum);
      final effectiveDiscount = requestedDiscount > explicitLineDiscountSum
          ? requestedDiscount
          : explicitLineDiscountSum;
      if (effectiveDiscount > total) {
        throw StateError(
          'الخصم (${effectiveDiscount.toStringAsFixed(2)}) أكبر من إجمالي '
          'الفاتورة (${total.toStringAsFixed(2)}).',
        );
      }
      // Factor applied to every line's unit cost. Guard against a zero-value
      // invoice so we never divide by zero.
      // خصمٌ **لكلّ صنف** — قرارُ المالك 2026-09-18. القاعدةُ واحدةٌ:
      // خصمُ السطر الصريحُ يُطرَح أوّلاً، وما بقي من خصم المستند يُوزَّع
      // نسبةً إلى ما بقي من قيمة السطور. راجع [resolvePurchaseLineNets].
      //
      // ⚠️ **وبلا خصومِ سطورٍ تُنتج القاعدةُ عينَ التوزيع النسبيّ القديم**
      // حرفاً — وهو شرطُ ألّا يتغيّر رقمٌ في فاتورةٍ قديمةٍ أو في إعادةِ
      // صندوقٍ صادرٍ أو مزامنة.
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
      total = FinancialUtils.round(total - effectiveDiscount);
      subtotalSum = FinancialUtils.round(subtotalSum - effectiveDiscount);

      final remaining = total - paid;
      final status = remaining <= 0
          ? 'paid'
          : (paid > 0 ? 'partial' : 'pending');

      // Enforce supplier credit limit — mirror of the customer check in
      // sales_mutations_dao so a purchase can't silently push us past the
      // limit we agreed with the supplier. `balance > 0` means we owe
      // them, so a partial/unpaid purchase projects forward by the
      // remaining amount. Zero creditLimit means "not configured" → no
      // enforcement (matches sales semantics).
      if (remaining > 0.01) {
        final supplier = await (select(
          parties,
        )..where((p) => p.id.equals(supplierId))).getSingleOrNull();
        if (supplier != null && supplier.creditLimit > 0) {
          final projectedBalance = supplier.balance + remaining;
          if (projectedBalance > supplier.creditLimit) {
            // 062 (D1-004): overrideCreditLimit allows the purchase to
            // proceed; emit CREDIT-OVERRIDE log.
            final hasOverride = await permissionEnforcer.hasCriticalOp(
              userId, PermissionCodes.overrideCreditLimit);
            if (!hasOverride) {
              throw Exception(
                'تجاوز المورد الحد الائتماني المسموح به (${supplier.creditLimit})',
              );
            }
            unawaited(DiagnosticLogger.log('CREDIT-OVERRIDE',
                'purchase user=$userId supplier=${supplier.id} '
                'projected=$projectedBalance limit=${supplier.creditLimit}'));
          }
        }
      }

      // البند 5: reject a supplier-invoice-number already used by this supplier
      // BEFORE anything is written. Inside the transaction() → a violation
      // rolls back stock/GL/treasury with the invoice.
      await _assertSupplierInvoiceNumberFree(supplierId, supplierInvoiceNumber);

      // Use supplier invoice number if provided, else generate internal PUR- number
      // This implements Phase 5: Purchase invoices using the number provided by the supplier.
      final invoiceNumber =
          (supplierInvoiceNumber != null && supplierInvoiceNumber.isNotEmpty)
          ? supplierInvoiceNumber
          : await generateInvoiceNumber('PUR');

      // L3 (2026-04-28): Resolve branchId from warehouse so each invoice
      // carries its branch directly — eliminates 2-hop JOIN for reports.
      int? resolvedBranchId;
      try {
        final wh = await (select(warehouses)..where((w) => w.id.equals(warehouseId))).getSingleOrNull();
        resolvedBranchId = wh?.branchId;
      } catch (_) {/* non-fatal — branch stays null */}

      // Insert invoice
      // v164 — الاستحقاقُ لقطةٌ من مهلةِ المورد وقتَ الإصدار.
      final dueAt = await resolveInvoiceDueDate(
        partyId: supplierId,
        invoiceDate: invoiceDate ?? DateTime.now(),
      );
      final invoiceId = await into(purchaseInvoices).insert(
        PurchaseInvoicesCompanion.insert(
          invoiceNumber: invoiceNumber,
          supplierId: supplierId,
          warehouseId: warehouseId,
          branchId: Value(resolvedBranchId),
          invoiceDate: invoiceDate ?? DateTime.now(),
          dueDate: Value(dueAt),
          subtotal: Value(subtotalSum),
          discount: Value(effectiveDiscount),
          tax: Value(taxTotal),
          total: Value(total),
          paid: Value(paid),
          paymentMethod: Value(paymentMethod),
          status: Value(status),
          notes: Value(notes),
          supplierInvoiceNumber: Value(supplierInvoiceNumber),
          costCenterId: Value(costCenterId),
          currencyId: Value(currencyId),
          exchangeRate: Value(exchangeRate),
          // UUID-First (Phase 1): carry the caller's globalId through, or
          // mint one so every purchase invoice has stable cross-install id.
          globalId: Value(
            (globalId != null && globalId.isNotEmpty)
                ? globalId
                : UuidV7.generate(),
          ),
        ),
      );

      // ═══ وسمُ الاستيراد — في معاملة الفاتورة لا بعدَها ═══
      //
      // 🔴 صفُّ `ImportPurchaseDetails` هو **الفارقُ الوحيد** بين فاتورةِ
      //    استيرادٍ وفاتورةٍ محلّيّة. وكتابتُه بعد المعاملة تعني أنّ سقوطَه
      //    يترك فاتورةً بذمّةٍ ومخزونٍ وقيدٍ **بلا وسم**: تبدو محلّيّةً إلى
      //    الأبد، وتغيب عن الشاشة التي أُنشئت فيها، ولا شيءَ يقول إنّ شيئاً
      //    سقط.
      if (importDetails != null) {
        await _writeImportPurchaseDetails(invoiceId, importDetails);
      }
      if (purchaseAccountId != null) {
        await setPurchaseInvoicePurchaseAccountId(invoiceId, purchaseAccountId);
      }

      for (var lineAt = 0; lineAt < items.length; lineAt++) {
        final item = items[lineAt];
        final productId = item.productId.present ? item.productId.value : 0;
        final quantity = item.quantity.present ? item.quantity.value : 1.0;
        // ح-1 (trade discount): الخصمُ يصل تكلفةَ السطر **قبل** أن يصل
        // السطرَ المخزَّنَ وحركةَ المخزون و`updateProductWAC` — وهذا ما
        // يجعل متوسّطَ التكلفة تكلفةً حقيقيّةً ويمنع مرتجعاً من ردّ أكثرَ
        // ممّا دُفع.
        //
        // 🔴 **ومرّةً واحدةً بالضبط**: الصافي مطروحٌ منه الخصمُ الصريحُ
        // وحصّتُه من الباقي معاً في [resolvePurchaseLineNets]، فلا ضربَ
        // في معاملٍ هنا يُطبّقه ثانيةً.
        final unitCost = quantity > 0
            ? FinancialUtils.round(lineNets[lineAt] / quantity)
            : 0.0;
  // ignore: dead_code
        final taxRate = item.taxRate.present ? (item.taxRate.value ?? 0.0) : 0.0;
        // Spec 151 E-03: honour the passed per-line taxAmount (exactly as the
        // header loop above does) instead of always recomputing from the rate.
        // A mixed invoice sends taxAmount=0 for an exempt line while still
        // carrying the product's rate; recomputing here stored PHANTOM input
        // VAT that a purchase RETURN later reversed — and made SUM(line.tax)
        // diverge from header.tax. Only recompute as a fallback when the caller
        // supplied no amount (legacy / outbox / api_purchase_handler replays).
        // Round to the financial precision so the stored line reconciles with
        // the header exactly.
        final taxAmount = FinancialUtils.round(item.taxAmount.present
  // ignore: dead_code
            ? (item.taxAmount.value ?? 0.0)
            : (quantity * unitCost) * (taxRate / 100));

        final hasLineGid = item.globalId.present &&
            (item.globalId.value?.isNotEmpty ?? false);
        await into(purchaseInvoiceItems).insert(
          item.copyWith(
            invoiceId: Value(invoiceId),
            // ح-1 (trade discount): persist the APPORTIONED cost. copyWith
            // keeps the caller's gross value otherwise, so the stored line
            // would disagree with stock/WAC/GL and a later return would
            // refund more than was ever paid.
            unitCost: Value(unitCost),
            // The rounded net is authoritative; the remainder belongs to
            // the largest line rather than being lost in unit-cost division.
            total: Value(FinancialUtils.round(lineNets[lineAt] + taxAmount)),
            taxAmount: Value(taxAmount),
            // UUID-First Phase 1 Slice 3: stable per-line identity.
            globalId: hasLineGid ? item.globalId : Value(UuidV7.generate()),
          ),
        );

        // Update product stock and WAC cost (#PIR Phase 0)
        final product = await getProductById(productId);
        if (product != null && product.trackExpiry &&
            ((item.batchNumber.value?.trim().isNotEmpty ?? false) == false ||
                item.expiryDate.value == null)) {
          throw StateError('رقم الدفعة وتاريخ الصلاحية مطلوبان للصنف ${product.name}.');
        }
        if (product != null && product.trackInventory) {
           final stockBeforeReceipt = product.currentStock;
           final costBeforeReceipt = product.costPrice;
          // 1. Update WAC Cost BEFORE updating stock quantity if we want standard average logic,
          // or pass "newQuantity" to the helper which handles current balance.
          await updateProductWAC(
            productId: productId,
            newQuantity: quantity,
            newUnitCost: unitCost,
          );

          // 2. Update Stock Quantity
          // B10 (S-INV-COST / PUR-1): thread the receipt's real unitCost
          // through so the per-warehouse average_cost blend (inside
          // adjustStock → _updateWarehouseBalance) uses the ACTUAL receipt
          // cost instead of the just-updated GLOBAL WAC. Without this, a
          // price change or a multi-warehouse setup left
          // inventory_balances.average_cost silently diverged from the true
          // receipt cost. products.costPrice (COGS source-of-truth) is
          // still set exclusively by updateProductWAC above — untouched.
          await adjustStock(
            productId: productId,
            warehouseId: warehouseId,
            quantity: quantity,
            type: 'purchase',
            referenceType: 'purchase_invoice',
            referenceId: invoiceId,
            notes: 'مشتريات فاتورة #$invoiceNumber',
            unitCost: unitCost,
          );
           final negativeCoverage = stockBeforeReceipt < 0
               ? (stockBeforeReceipt.abs() < quantity ? stockBeforeReceipt.abs() : quantity)
               : 0.0;
           negativeStockCostAdjustment += FinancialUtils.round(
             negativeCoverage * (unitCost - costBeforeReceipt),
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
              batchNumber: item.batchNumber.value ?? invoiceNumber,
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

      // Update supplier balance if on credit
      if (remaining > 0) {
        await adjustPartyBalance(supplierId, remaining);
      }

      // Record treasury transaction if paid. Client issue البند 6: keep the
      // returned row — the cash leg is no longer posted inline; it is posted
      // from this voucher by autoPostPayment further down, so the credited
      // account is the PAYING safe's own linked account (fixes ح-4) and the
      // amount is what actually left the safe (fixes ح-3).
      SafeTransactionData? paymentTxn;
      if (paid > 0) {
        paymentTxn = await _recordPurchasePayment(
           invoiceId,
           paid,
           paymentMethod,
           costCenterId,
           safeId: safeId,
           supplierId: supplierId,
           paymentRate: exchangeRate,
           foreignAmount: currencyId != null && exchangeRate != null && exchangeRate > 0
               ? paid / exchangeRate
               : null,
           globalId: globalId,
         );
        if (paymentTxn == null) {
          // Symmetry with addPurchasePayment: a payment we cannot attribute to
          // a safe must not silently reduce the GL with no treasury movement.
          throw StateError(
            'تعذّر تسجيل دفعة فاتورة المشتريات #$invoiceNumber: لا يوجد صندوق '
            'مطابق لطريقة الدفع. أنشئ صندوقاً افتراضياً أو اختر صندوقاً '
            'قبل الحفظ.',
          );
        }
      }

      // ═══════════════════════════════════════════════════════════════════════
      // AUTOMATIC ACCOUNTING ENTRY (#PIR Phase 0)
      // PHASE-2 FIX: GL errors propagate to parent transaction() → full rollback.
      // B7 (S-FAILLOUD / PUR-3): the inventory account used to be an optional
      // leg — a missing mapping just debugPrinted a warning and SKIPPED the
      // whole GL entry while stock/WAC/party-balance/treasury above had
      // already committed inside this same transaction. That is exactly the
      // "financial side-effect with no balanced JE" invariant this batch
      // exists to close. A missing inventory account means the chart of
      // accounts is genuinely broken (syncDefaultAccounts always seeds it) —
      // fail loud and let the whole invoice roll back instead of silently
      // posting stock movements with no accounting trail.
      // ═══════════════════════════════════════════════════════════════════════
      final List<JournalLine> journalLines = [];

      // 1. Debit side (Assets - Inventory increase) — dynamic account resolution
      final invCode = await accountingDao.getMappedAccountCode(
        'inventory', AccountingDao.accountPurposes['inventory']!,
      );
      // J1b: the invoice's own «حساب المشتريات» wins over the mapped default
      // (and then takes the raw-material share too — one chosen debit account);
      // NULL / invalid ⇒ the mapping, byte-identical to before.
      final purchaseOverride = await resolvePurchaseAccountOverride(invoiceId);
      final invAcc =
          purchaseOverride ?? await accountingDao.getAccountByCode(invCode);
      if (invAcc == null) {
        throw StateError(
          'تعذّر تسجيل فاتورة المشتريات #$invoiceNumber: حساب المخزون '
          '($invCode) غير موجود في الدليل المحاسبي. '
          'راجع إعدادات الحسابات ← ربط الحسابات قبل حفظ الفاتورة.',
        );
      }
      // ── توجيه المدين حسب نوع الصنف (قرار المالك، 2026-08-02) ────────────
      //
      // الخامات على حساب الخامات (١١٣١) والباقي على المخزون (١١٣٦). قبل كده
      // كل الأصناف كانت بتدخل ١١٣٦ بينما `manufacturing_dao` بيسحب الاستهلاك
      // من ١١٣١ — فكل أمر إنتاج بيضخّم ١١٣٦ بقيمة الخامات المستهلكة ويخلّي
      // ١١٣١ رصيد أصل سالب.
      //
      // نسبة الخصم اتطبقت على `subtotalSum` فوق، فنصيب الخامات بيتعدّل بنفس
      // النسبة عشان مجموع السطرين يساوي الإجمالي بعد الخصم بالظبط.
      // نصيبُ الخامات من الصافي — مجموعُ صافي سطورها بعد الخصم، فمجموعُ
      // السطرَين المحاسبيَّين يساوي الإجماليَّ بعد الخصم بالضبط.
      final rawShare = rawMaterialSubtotal > 0
          ? FinancialUtils.round([
              for (final at in rawMaterialLineIndexes) lineNets[at],
            ].fold<double>(0, (a, v) => a + v))
          : 0.0;
      final rawAcc = rawShare > 0 && purchaseOverride == null
          ? await accountingDao.getAccountByCode(
              await accountingDao.getMappedAccountCode('raw_materials',
                  AccountingDao.accountPurposes['raw_materials']!))
          : null;
      // حساب الخامات مش موجود (دليل معدَّل) ⇒ الكل على المخزون زي الأول بدل
      // ما القيد يفشل ويوقف الفاتورة.
      final rawLeg = rawAcc == null ? 0.0 : rawShare;

      if (rawLeg > 0) {
        journalLines.add(
          JournalLine(
            accountId: rawAcc!.id,
            debit: rawLeg,
            description: 'مشتريات خامات فاتورة #$invoiceNumber',
          ),
        );
      }
      if (subtotalSum - rawLeg > 0) {
        journalLines.add(
          JournalLine(
            accountId: invAcc.id,
            debit: FinancialUtils.round(subtotalSum - rawLeg),
            description: 'مشتريات مخزنية فاتورة #$invoiceNumber',
          ),
        );
      }

      if (taxTotal > 0) {
        final inputTaxCode = await accountingDao.getMappedAccountCode(
          'input_vat', AccountingDao.accountPurposes['input_vat']!,
        );
        final inputTaxAcc = await accountingDao.getAccountByCode(inputTaxCode);
        if (inputTaxAcc != null) {
          journalLines.add(
            JournalLine(
              accountId: inputTaxAcc.id,
              debit: taxTotal,
              description: 'ضريبة مدخلات مشتريات #$invoiceNumber',
            ),
          );
        }
      }

      // ح-1 (trade discount): NO purchase-discount (4316) credit leg. A trade
      // discount reduces the cost of the goods (IAS 2.11) — it is not income.
      // `subtotalSum` above is already NET and the line costs were apportioned,
      // so the inventory debit equals Σ(qty × cost) and the JE balances against
      // the payable without any extra leg.
      //
      // (A SETTLEMENT discount would be different — that IS financing income
      // and would belong on 4316. This field is a trade discount by owner
      // decision; if that ever changes, the two treatments must not be mixed.)

      // 2. Credit side — البند 6 (approved 2026-07-25): the supplier's payable
      // is ALWAYS the counter-party, cash or credit alike. The settlement leg
      // (Dr payable / Cr cash) is posted separately from the payment voucher
      // by autoPostPayment below.
      //
      // Why: previously a cash purchase credited the cash account directly and
      // the supplier's account never moved, so their GL card showed nothing —
      // the accountant could not read "purchased / paid" per supplier from the
      // ledger. Trial-balance effect is identical either way.
      //
      // This also removes the paymentMethod-keyed branch that credited Cash for
      // the FULL total on a partially-paid cash invoice (ح-3), and stops the
      // cash leg landing on the global cash account instead of the paying
      // safe's own account (ح-4) — autoPostPayment resolves that from the safe.
      if (total > 0) {
        final apCode = await accountingDao.getMappedAccountCode(
          'payables', AccountingDao.accountPurposes['payables']!,
        );
        final apControlAcc = await accountingDao.getAccountByCode(apCode);
        // Route to the supplier sub-account (2111-XXXXX) so COA/GL show
        // per-supplier balances instead of a lumped 2111 control total.
        final apAcc = await _resolvePartySubAccount(supplierId, apControlAcc);
        if (apAcc != null) {
          journalLines.add(
            JournalLine(
              accountId: apAcc.id,
              credit: total,
              description: 'مشتريات فاتورة #$invoiceNumber',
            ),
          );
        }
      }

      // journalLines always has at least the inventory debit line at this
      // point (invAcc==null already threw above). If the cash/payables credit
      // leg above was skipped (unmapped account), createJournalEntry's own
      // balance check (Spec 139) throws on the resulting imbalance — same
      // "propagates to parent transaction() → rollback" guarantee.
      // H-09 FIX: Get branchId from warehouse to ensure financial isolation
      final warehouse = await getWarehouseById(warehouseId);
      final branchId = warehouse?.branchId;

      // Resolve costCenterId from invoice (if tracked) or warehouse
      final invoiceData = await getPurchaseInvoiceById(invoiceId);
      final ccId = invoiceData?.costCenterId ?? warehouse?.costCenterId;

      // Throws on DB failure → propagates to parent transaction() → rollback
      await accountingDao.createJournalEntry(
        description: 'قيد مشتريات تلقائي للفاتورة #$invoiceNumber',
        // تاريخ **الفاتورة** مش النهاردة. الهيدر بيتخزن بتاريخ الفاتورة
        // والقيد كان بتاريخ اليوم، فتقرير المشتريات (بيفلتر بـinvoiceDate)
        // وتقرير الضريبة (بيفلتر بـentry_date) بيقولوا شهرين مختلفين لنفس
        // المستند — وضريبة المدخلات بتتحسب في إقرار الشهر الغلط.
        // `autoPostPurchase:968` نفسه بيستعمل `purchase.invoiceDate`.
        date: effectiveInvoiceDate,
        lines: journalLines,
        referenceType: 'purchase_invoice',
        referenceId: invoiceId,
        isAutoPosted: true,
        costCenterId: ccId,
        branchId: branchId,
      );
       // Correct the cost of units sold while stock was negative.
       if (negativeStockCostAdjustment != 0) {
         final cogsCode = await accountingDao.getMappedAccountCode(
           'cogs', AccountingDao.accountPurposes['cogs']!,
         );
         final cogsAccount = await accountingDao.getAccountByCode(cogsCode);
         if (cogsAccount == null) {
           throw StateError('حساب تكلفة البضاعة المباعة غير موجود.');
         }
         final amount = negativeStockCostAdjustment.abs();
         final adjustmentLines = negativeStockCostAdjustment > 0
             ? [
                 JournalLine(accountId: invAcc.id, debit: amount,
                     description: 'تسوية تكلفة مخزون سالب #$invoiceNumber'),
                 JournalLine(accountId: cogsAccount.id, credit: amount,
                     description: 'تسوية تكلفة مخزون سالب #$invoiceNumber'),
               ]
             : [
                 JournalLine(accountId: cogsAccount.id, debit: amount,
                     description: 'تسوية تكلفة مخزون سالب #$invoiceNumber'),
                 JournalLine(accountId: invAcc.id, credit: amount,
                     description: 'تسوية تكلفة مخزون سالب #$invoiceNumber'),
               ];
         await accountingDao.createJournalEntry(
           description: 'تسوية تكلفة مخزون سالب للفاتورة #$invoiceNumber',
           date: effectiveInvoiceDate,
           lines: adjustmentLines,
           referenceType: 'negative_stock_cost_adjustment',
           referenceId: invoiceId,
           isAutoPosted: true,
           allowRepost: true,
           costCenterId: ccId,
           branchId: branchId,
         );
       }
      // البند 6 — settlement leg: Dr supplier payable / Cr the PAYING safe's
      // linked account. autoPostPayment already implements exactly this for
      // `category == 'purchase'`, so there is no new posting code: it resolves
      // the supplier sub-account for the debit and the safe's own account for
      // the credit. Runs inside the same transaction() → a failure rolls the
      // whole invoice back rather than leaving a payable that was never settled.
      if (paymentTxn != null) {
        // autoPostPayment returns null (does NOT throw) when the safe has no
        // linked account and the global cash/bank mapping is missing, or the
        // payables control account is gone. Swallowing that would leave the
        // payable credited in full with the safe already debited and NO
        // settlement JE — the exact silent divergence this batch closes.
        // addPurchasePayment already fails loud here; match it.
        final settlementJeId =
            await accountingDao.autoPostPayment(paymentTxn, costCenterId: ccId);
        if (settlementJeId == null) {
          throw StateError(
            'تعذّر ترحيل قيد سداد فاتورة المشتريات #$invoiceNumber: '
            'حساب الصندوق أو حساب الذمم غير مربوط في الدليل المحاسبي. '
            'راجع إعدادات الحسابات ← ربط الحسابات.',
          );
        }
      }

      // ═══════════════════════════════════════════════════════════════════════
      // SYNC ENGINE: Add to outbox (#Phase7)
      //
      // NO try/catch here. An outbox failure MUST fail the whole transaction
      // so stock/WAC/GL/invoice roll back together. The previous swallow-and-
      // continue masked real errors as Postgres 25P02 ("transaction aborted")
      // because the swallowed exception already poisoned the tx at the DB
      // layer, then later COMMIT would fail with 25P02 and the original cause
      // was lost.
      // ═══════════════════════════════════════════════════════════════════════
      await addToSyncOutbox(
        tableName: 'purchase_invoices',
        recordId: invoiceId.toString(),
        operation: 'insert',
        payload: {
          'invoice_number': invoiceNumber,
          'supplier_id': supplierId,
          'warehouse_id': warehouseId,
          'invoice_date': DateTime.now().toIso8601String(),
          'subtotal': subtotalSum,
          'tax': taxTotal,
          'total': total,
          'paid': paid,
          'payment_method': paymentMethod,
          'status': status,
          'notes': notes,
          'items': items
              .map(
                (e) => {
                  'product_id': e.productId.value,
                  'quantity': e.quantity.value,
                  'unit_cost': e.unitCost.value,
                  'tax_rate': e.taxRate.present ? e.taxRate.value : 0.0,
                  'batch_number': e.batchNumber.present ? e.batchNumber.value : null,
                  'expiry_date': e.expiryDate.value?.toIso8601String(),
                },
              )
              .toList(),
        },
      );

      // وختمُ الأمر **آخرُ ما يقع داخلَ المعاملة**: فلو أخفق
      // شيءٌ قبلَه رجع الختمُ مع الفاتورة، ولا يبقى أمرٌ مستهلَكٌ بلا
      // فاتورة — وهي حالةٌ لا يُخرج منها شيءٌ من الواجهة.
      if (sourceOrderId != null) {
        await _markPurchaseOrderConverted(sourceOrderId, invoiceId);
      }
      await resignPurchaseInvoice(invoiceId);
      return invoiceId;
    });
  }
}
