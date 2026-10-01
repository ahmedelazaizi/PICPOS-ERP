// =======================================================================
// SALES MUTATIONS DAO
// Extracted from sales_dao.dart — PIR Phase 3 God File Splitting
// Create/Update/Delete operations for sales invoices
// =======================================================================

part of '../database.dart';

/// Extension for Sales Invoice mutation operations (create, update, delete)
extension SalesMutationsDao on AppDatabase {

  /// Create a complete sales invoice with items
  Future<int> createSalesInvoice({
    String? invoiceNumber,
    int? customerId,
    required int warehouseId,
    required int userId,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    required double paid,

    /// فرقُ تقريب الإجماليّ — `total - roundedTotal`، بإشارته.
    ///
    /// افتراضُه صفرٌ عمداً فكلُّ منادٍ قائمٍ يبقى على سلوكه حرفاً بحرف.
    double roundingAdjustment = 0,
    required String paymentMethod,
    bool isBooking = false,
    String? deliveryStatus,
    double deliveryFee = 0,
    int? deliveryCompanyId,
    int? deliveryCompanyPartyId, // #Phase2: المرج المالي لشركة التوصيل
    int? courierId,
    String? notes,
    required List<SalesInvoiceItemsCompanion> items,
    double? cashAmount,
    double? bankAmount,
    int? cashSafeId, // New
    int? bankSafeId,
    int? clickSafeId, // New
    double? clickAmount,
    String saleType = 'default',
    DateTime? invoiceDate,
    int? costCenterId, // مركز التكلفة من الفرع العميل
    int? branchId, // L3: direct branchId from client (or resolved from warehouse)
    String? platformOrderNumber, // #Phase4: External platform order ID
    // UUID-First (Phase 1): server-side callers can pass the client's
    // globalId through so client and server rows share identity.
    String? globalId,
    String? adhocCustomerName,
    String? adhocCustomerPhone,
    String? adhocCustomerNote,
    int? currencyId,
    double? exchangeRate,

    /// يؤجّل قيدَ «Phase 8» لأن المنادي سيصدره بنفسه **بعد** أن يعرف تكلفةَ
    /// الخامات.
    ///
    /// ⚠️ ترتيبٌ لا يظهر إلا من المسار الكامل: `autoPostCashSale` يقرأ
    /// `sale_bom_consumptions` ليعرف تكلفةَ الصنف المركّب (تكلفتُه ليست على
    /// سطر الفاتورة — الصنفُ المركّب يحمل صفراً عادةً). لكن على مسار
    /// `SalesTransactionOrchestrator` لا تُكتب تلك الصفوف إلا في الخطوة ٤٫٥،
    /// أي **بعد** أن يكون هذا الـDAO قد أصدر القيدَ وعاد.
    ///
    /// فالقيدُ يخرج «مدين نقدية / دائن مبيعات» بلا تكلفةٍ إطلاقاً — متوازنٌ
    /// فلا يشتكي مدقّق، والخاماتُ خرجت من المخزن فعلاً. مقيس: تكلفةُ مبيعاتٍ
    /// صفرٌ بدل ٦٠ على بيعةِ ١٠٠ ⇒ هامشٌ ١٠٠٪ وربحٌ وهميّ بحجم التكلفة.
    /// ثم يأتي قيدُ المنسّق (ومعه التفصيل) فيصطدم بحارس الازدواج ويُهمَل.
    ///
    /// المنادون الآخرون (‏معالجُ الـAPI، الإيرادُ المؤجَّل، مسارا الإصلاح،
    /// التوصيل) لا يمرّرونها فيبقى سلوكُهم كما هو بالضبط.
    bool deferAutoPost = false,

    /// Allows the orchestrator's resolved branch/terminal shortage policy to
    /// authorize a tracked sale deduction before BOM depletion runs.
    bool allowNegativeStock = false,
  }) async {
    final invoiceId = await transaction(() async {
      // Use client-provided date or current server time
      final effectiveInvoiceDate = invoiceDate ?? DateTime.now();

      // 0. Soft/Hard Period Closing Gating
      await accountingDao.validateFinancialPeriod(effectiveInvoiceDate, operation: 'فاتورة مبيعات');


      // Generate invoice number if not provided.
      // Cluster 027 / Issue 5 — POS quick-returns must advance the SRET
      // counter, not the POS one. Without the saleType branch, returns
      // ate POS sequence numbers (gaps in printed receipts and zero
      // numbering on the returns side).
      final invNumber = invoiceNumber ??
          await generateInvoiceNumber(
            saleType == 'return' ? 'RET-' : 'Receipt',
          );
      debugPrint('[SALE] invoiceNumber param: $invoiceNumber → generated: $invNumber');

      final orderNum = await getNextDailyOrderNumber();

      // Calculate remaining (not stored, just for status determination)
      //
      // ⚠️ **وفرقُ التقريب يُطرَح — فهو ليس ديناً.** المقبوضُ مقرَّبٌ بينما
      // `total` حقيقيّ، فبلا هذا الطرح تُقرأ كلُّ فاتورةٍ قُرِّبت هبوطاً
      // `pending` إلى الأبد، ويُفتَح لها فرعُ الحدّ الائتمانيِّ أدناه، ويُضاف
      // فتاتُ التقريب إلى رصيد العميل في `_recordSalesReceipt`.
      final remaining = total - paid - roundingAdjustment;


      // #Phase4 + 062 (D1-004): Enforce credit limit, with override path
      // for users holding overrideCreditLimit. Override is logged.
      // SR-1: a return never raises exposure — don't apply the credit-limit check to returns.
      if (saleType != 'return' && customerId != null && remaining > 0.01) {
        final customer = await (select(
          parties,
        )..where((p) => p.id.equals(customerId))).getSingleOrNull();
        if (customer != null && customer.creditLimit > 0) {
          // Balance > 0 means they owe us.
          final projectedBalance = customer.balance + remaining;
          if (projectedBalance > customer.creditLimit) {
            final hasOverride = await permissionEnforcer.hasCriticalOp(
              userId, PermissionCodes.overrideCreditLimit);
            if (!hasOverride) {
              throw Exception(
                'تجاوز العميل الحد الائتماني المسموح به (${customer.creditLimit})',
              );
            }
            unawaited(DiagnosticLogger.log('CREDIT-OVERRIDE',
                'sales user=$userId customer=${customer.id} '
                'projected=$projectedBalance limit=${customer.creditLimit}'));
          }
        }
      }

      // PIR P1-04: Expiry date check — block sale of all-expired-batch products
      for (final item in items) {
        final product = await (select(products)
              ..where((p) => p.id.equals(item.productId.value)))
            .getSingleOrNull();
        if (product != null && product.trackExpiry) {
          final now = DateTime.now();
          // Get all active batches for the product
          final activeBatches = await (select(productBatches)
                ..where(
                  (b) =>
                      b.productId.equals(item.productId.value) &
                      b.status.equals('active') &
                      b.quantity.isBiggerThan(const Variable(0)),
                ))
              .get();

          if (activeBatches.isNotEmpty) {
            // Check if ALL batches are expired
            final hasValidBatch = activeBatches.any(
              (b) => b.expiryDate.isAfter(now),
            );
            if (!hasValidBatch) {
              throw Exception(
                'لا يمكن بيع المنتج "${product.name}" — '
                'جميع الدفعات منتهية الصلاحية. '
                'يرجى استلام دفعة جديدة أو مراجعة المخزون.',
              );
            }
          }
        }
      }

      // Use small tolerance (0.01) to handle floating-point rounding
      // differences between cart total (rounded) and recalculated total (raw).
      // Without this, cash-paid invoices can show as 'pending' due to
      // sub-cent discrepancies (e.g., total=10.004 vs paid=10.00).
      final status = isBooking
          ? 'booked'
          : (remaining <= 0.01 ? 'completed' : 'pending');

      // Insert invoice


      // Pre-validate FK references to give clear error messages
      final warehouse = await (select(warehouses)..where((w) => w.id.equals(warehouseId))).getSingleOrNull();
      if (warehouse == null) {
        throw Exception('المخزن غير موجود (warehouseId=$warehouseId). يرجى التأكد من إعدادات المخزن.');
      }
      final branchId = warehouse.branchId;

      final user = await (select(users)..where((u) => u.id.equals(userId))).getSingleOrNull();
      if (user == null) {
        throw Exception('المستخدم غير موجود (userId=$userId). يرجى تسجيل الدخول مرة أخرى.');
      }

      // Safe-resolve nullable FKs — auto-null if reference missing
      int? safeDeliveryCompanyId = deliveryCompanyId;
      int? safeCourierId = courierId;
      int? safeDeliveryPartyId = deliveryCompanyPartyId;

      if (safeDeliveryCompanyId != null) {
        final dc = await (select(deliveryCompanies)..where((d) => d.id.equals(safeDeliveryCompanyId!))).getSingleOrNull();
        if (dc == null) {
          debugPrint('[FK_FIX] deliveryCompanyId=$safeDeliveryCompanyId not found — setting to null');
          safeDeliveryCompanyId = null;
        }
      }
      if (safeCourierId != null) {
        final courier = await (select(couriers)..where((c) => c.id.equals(safeCourierId!))).getSingleOrNull();
        if (courier == null) {
          debugPrint('[FK_FIX] courierId=$safeCourierId not found — setting to null');
          safeCourierId = null;
        }
      }
      if (safeDeliveryPartyId != null) {
        final party = await (select(parties)..where((p) => p.id.equals(safeDeliveryPartyId!))).getSingleOrNull();
        if (party == null) {
          debugPrint('[FK_FIX] deliveryCompanyPartyId=$safeDeliveryPartyId not found — setting to null');
          safeDeliveryPartyId = null;
        }
      }


      // L3: resolve branchId from warehouse if caller didn't supply one
      int? resolvedBranchId = branchId;
      if (resolvedBranchId == null) {
        try {
          final wh = await (select(warehouses)..where((w) => w.id.equals(warehouseId))).getSingleOrNull();
          resolvedBranchId = wh?.branchId;
        } catch (_) {/* non-fatal */}
      }

      // v164 — الاستحقاقُ لقطةٌ تُكتَب مرّةً من مهلةِ الطرف وقتَ الإصدار.
      // و`null` تعني «بلا مهلة» فتُقرأ كتاريخ الإصدار.
      final dueAt = await resolveInvoiceDueDate(
        partyId: customerId,
        invoiceDate: effectiveInvoiceDate,
      );

      final invoiceId = await into(salesInvoices).insert(
        SalesInvoicesCompanion.insert(
          invoiceNumber: invNumber,
          customerId: Value(customerId),
          dueDate: Value(dueAt),
          warehouseId: warehouseId,
          branchId: Value(resolvedBranchId),
          userId: userId,
          invoiceDate: effectiveInvoiceDate,
          subtotal: Value(subtotal),
          discount: Value(discount),
          tax: Value(tax),
          total: Value(total),
          paid: Value(paid),
           currencyId: Value(currencyId),
           exchangeRate: Value(exchangeRate),
          // v175 — لا تخصيصاتِ دفعاتٍ لفاتورةٍ تُولَد الآن، فالقاعدةُ هي
          // المسدَّدُ كلُّه. راجع `paidUnallocated` في تعريف الجدول.
          paidUnallocated: Value(paid),
          roundingAdjustment: Value(roundingAdjustment),
          cashPaid: Value(cashAmount ?? 0),
          bankPaid: Value(bankAmount ?? 0),
          clickPaid: Value(clickAmount ?? 0),
          paymentMethod: Value(paymentMethod),
          status: Value(status),
          deliveryStatus: Value(deliveryStatus),
          deliveryFee: Value(deliveryFee),
          deliveryCompanyId: Value(safeDeliveryCompanyId),
          deliveryCompanyPartyId: Value(safeDeliveryPartyId), // #Phase2
          courierId: Value(safeCourierId),
          orderNumber: Value(orderNum), // #Phase2
          platformOrderNumber: Value(platformOrderNumber), // #Phase4
          notes: Value(notes),
          adhocCustomerName: Value(adhocCustomerName),
          adhocCustomerPhone: Value(adhocCustomerPhone),
          adhocCustomerNote: Value(adhocCustomerNote),
          saleType: Value(saleType),
          costCenterId: Value(costCenterId), // مركز التكلفة من الفرع
          // UUID-First (Phase 1): use the caller-supplied globalId (when the
          // server receives a client invoice, this is the client's UUID),
          // otherwise mint a fresh one so every invoice has a stable id.
          globalId: Value(
            (globalId != null && globalId.isNotEmpty)
                ? globalId
                : UuidV7.generate(),
          ),
        ),
      );
      // Insert items and update stock
      for (final item in items) {
        // PIR Phase 0: Auto-populate costPrice from product's current WAC
        // GAP-P2-FIX-10: Auto-populate taxRate and taxAmount from product card
        final productId = item.productId.value;
        final product = await getProductById(productId);
        // B3: the product-card fallback honours «معفى» via the shared rule
        // (no company default on this path — as before).
        final effectiveTaxRate = item.taxRate.present
            ? item.taxRate.value
            : effectiveItemTaxRate(
                rate: product?.taxRate ?? 0.0,
                exempt: product != null &&
                    (await getTaxExemptProductIds([productId])).isNotEmpty,
                companyDefault: 0,
              );
        final lineTotal = (item.unitPrice.present ? item.unitPrice.value : 0.0) *
            (item.quantity.present ? item.quantity.value : 1.0);
        final effectiveTaxAmount = item.taxAmount.present
            ? item.taxAmount.value
            : lineTotal * (effectiveTaxRate / 100.0);
        // UUID-First Phase 1 Slice 3: auto-mint per-line globalId so each
        // invoice item has stable cross-install identity.
        final hasLineGid = item.globalId.present &&
            (item.globalId.value?.isNotEmpty ?? false);
        final effectiveCostPrice = item.costPrice.present
            ? item.costPrice.value
            : (product?.costPrice ?? 0);
        // Zero-cost safeguard (IAS 2). Sales returns use the item snapshot to
        // reverse COGS — if we let a tracked item land with cost=0 now, the
        // return would reverse zero cost and leave the JE out of balance.
        // Non-tracked items (services) legitimately have cost=0.
        // Honors the user-configurable `zero_cost_policy` setting:
        //   block → throw (strict IAS 2)
        //   warn  → allow save, log warning (default)
        //   allow → allow save silently
        if (saleType != 'return' &&
            product != null &&
            product.trackInventory &&
            effectiveCostPrice <= 0) {
          final policy = (await getSettingValue('zero_cost_policy')) ?? 'warn';
          if (policy == 'block') {
            throw Exception(
              'تعذّر حفظ الفاتورة: الصنف "${product.name}" متعقّب للمخزون '
              'وتكلفته غير محددة. يرجى تحديث تكلفة الصنف أولاً.',
            );
          }
          if (policy == 'warn') {
            await DiagnosticLogger.logZeroCostSale(
              invoiceId: invoiceId,
              invoiceNumber: invNumber,
              productId: product.id,
              quantity: (item.quantity.present ? item.quantity.value : 1.0) *
                  (item.quantityInBase.present ? item.quantityInBase.value : 1.0),
            );
          }
        }
        final itemWithCost = item.copyWith(
          invoiceId: Value(invoiceId),
          costPrice: Value(effectiveCostPrice),
          taxRate: Value(effectiveTaxRate),
          taxAmount: Value(effectiveTaxAmount),
          globalId: hasLineGid ? item.globalId : Value(UuidV7.generate()),
        );
        await into(salesInvoiceItems).insert(itemWithCost);


        // Update product stock (UOM: multiply by quantityInBase for base-unit accuracy)
        final quantity = item.quantity.value;
        final qtyInBase = item.quantityInBase.present ? item.quantityInBase.value : 1.0;
        final stockQty = quantity * qtyInBase;
        if (product != null && product.trackInventory) {
          if (saleType == 'return') {
            // Quick POS return. Same rule as the returns dialog: blend the
            // returned units in at the cost the JE recognises, before
            // adjustStock (which is what changes current_stock).
            final returnCost =
                item.costPrice.present ? item.costPrice.value : 0.0;
            await updateProductWAC(
              productId: productId,
              newQuantity: stockQty,
              newUnitCost: returnCost,
            );
            await adjustStock(
              productId: productId,
              warehouseId: warehouseId,
              quantity: stockQty,
              type: 'return',
              referenceType: 'sales_invoice',
              referenceId: invoiceId,
              unitCost: returnCost,
              notes: 'صنف مرتجع فاتورة #$invNumber',
            );
          } else {
            await adjustStock(
              productId: productId,
              warehouseId: warehouseId,
              quantity: -stockQty,
              type: 'sale',
              referenceType: 'sales_invoice',
              referenceId: invoiceId,
              notes: 'مبيعات فاتورة #$invNumber',
              allowNegativeSale: allowNegativeStock,
            );
          }
        }
      }


      // Update customer balance if on credit
      // SR-1: a sale increases what the customer owes; a return credits
      // (reduces) it. This mirrors the GL (autoPostSalesReturn credits AR
      // by arRefund — see accounting_autopost_dao.dart) and the standalone
      // returns path (returns_repository_impl.dart adjustPartyBalance(-...)).
      // Without the sign flip, a credit-sale return INCREASED the customer's
      // debt instead of reducing it, diverging parties.balance from the GL.
      if (customerId != null && remaining > 0) {
        await adjustPartyBalance(
            customerId, saleType == 'return' ? -remaining : remaining);
      }
      // Historical credit-sale returns posted before this fix may have left
      // parties.balance too HIGH by ~2x the AR refund (the GL was
      // already correct — see autoPostSalesReturn). No safe existing utility
      // WRITES a corrected balance; `party_dao.dart`'s getPartyBalanceMismatches()
      // (Day-17 / Spec 133 "audit read-only, repair deferred") only DETECTS the
      // drift (parties.balance vs SUM(posted journal_entry_lines) on the
      // party's sub-account) without repairing it. Do not hand-roll an
      // untested mass balance-rewrite here — run getPartyBalanceMismatches()
      // first to find affected parties, confirm each one against its ledger,
      // then apply targeted adjustPartyBalance(partyId, -delta) corrections
      // (ideally behind a new one-shot settings flag, e.g.
      // 'sr1_ar_return_backfill_v1_applied', following the
      // mirror_cache_integrity_v1_applied self-heal pattern) as a follow-up.


      // #Phase2: Record delivery company debt if selected
      // Usually, for companies like Talabat/Careem, the total amount (net + fee) is debt on them
      // SR-1 audit note: no current caller threads `deliveryCompanyPartyId`
      // into createSalesInvoice() (grepped repo-wide — always null today),
      // so this branch is presently dead code and NOT fixed here (under-reach
      // per SR-1 scope). If it is ever wired up for return flows, apply the
      // same saleType=='return' sign flip used above for customerId, or this
      // will inflate the delivery party's debt on a return exactly like SR-1.
      if (safeDeliveryPartyId != null) {
        await adjustPartyBalance(safeDeliveryPartyId, total - paid);
      }


      if (paid != 0) {
        final amountToRecord = saleType == 'return' ? -paid.abs() : paid.abs();
        if ((paymentMethod == 'multiple' || paymentMethod == 'mixed') &&
            cashAmount != null &&
            bankAmount != null) {
          if (cashAmount != 0) {
            final cashRec = saleType == 'return'
                ? -cashAmount.abs()
                : cashAmount.abs();
            await _recordSalesReceipt(
              invoiceId, cashRec, 'cash',
              userId: userId, specificSafeId: cashSafeId, warehouseId: warehouseId, customerId: customerId,
               paymentRate: exchangeRate,
               foreignAmount: currencyId != null && exchangeRate != null && exchangeRate > 0 ? cashRec.abs() / exchangeRate : null,
            );
          }
          if (bankAmount != 0) {
            final bankRec = saleType == 'return'
                ? -bankAmount.abs()
                : bankAmount.abs();
            await _recordSalesReceipt(
              invoiceId, bankRec, 'bank',
              userId: userId, specificSafeId: bankSafeId, warehouseId: warehouseId, customerId: customerId,
               paymentRate: exchangeRate,
               foreignAmount: currencyId != null && exchangeRate != null && exchangeRate > 0 ? bankRec.abs() / exchangeRate : null
            );
          }
          if (clickAmount != null && clickAmount != 0) {
            final clickRec = saleType == 'return'
                ? -clickAmount.abs()
                : clickAmount.abs();
            await _recordSalesReceipt(
              invoiceId, clickRec, 'click',
              userId: userId, specificSafeId: clickSafeId, warehouseId: warehouseId, customerId: customerId,
               paymentRate: exchangeRate,
               foreignAmount: currencyId != null && exchangeRate != null && exchangeRate > 0 ? clickRec.abs() / exchangeRate : null
            );
          }
        } else {
          // Single payment method
          final isBankMethod = paymentMethod == 'transfer' ||
              paymentMethod == 'card' ||
              paymentMethod == 'bank';
          await _recordSalesReceipt(
            invoiceId, amountToRecord, paymentMethod,
             paymentRate: exchangeRate,
             foreignAmount: currencyId != null && exchangeRate != null && exchangeRate > 0 ? amountToRecord.abs() / exchangeRate : null,
            userId: userId,
            specificSafeId: isBankMethod
              ? bankSafeId
              : (paymentMethod == 'click' ? clickSafeId : (paymentMethod == 'cash' ? cashSafeId : null)),
            warehouseId: warehouseId,
            customerId: customerId,
          );
        }
      }

      // Phase 7: (Removed redundant outbox queuing since submitSale handles offline Syncing)
      await resignSalesInvoice(invoiceId);

      return invoiceId;
    });

    // Phase 8: Autopost journal entry OUTSIDE the transaction.
    // autoPostCashSale/autoPostCreditSale each wrap themselves in transaction()
    // internally — nesting them inside would cause SQLite deadlock (SqliteException 517).
    // The dedup guard (hasAutoPostEntry) inside each method is idempotent.
    if (deferAutoPost) return invoiceId; // اقرا [deferAutoPost] فوق
    try {
      final sale = await getSalesInvoiceById(invoiceId);
      if (sale != null) {
        if (saleType == 'return') {
          // Cluster 023 / Issue 1 — POS quick-return previously skipped JE
          // posting entirely. The regular returns dialog calls
          // autoPostSalesReturn explicitly, but the POS "مرتجع سريع" flow
          // routes through this DAO and never invoked it, so the safe
          // transaction was created without a matching journal entry. Cash
          // safe's GL balance silently drifted from the actual balance.
          final cashRefund = (paymentMethod == 'cash')
              ? paid
              : ((paymentMethod == 'multiple' || paymentMethod == 'mixed')
                  ? (cashAmount ?? 0)
                  : 0.0);
          final bankRefund = (isBankPaymentMethod(paymentMethod))
              ? paid
              : ((paymentMethod == 'multiple' || paymentMethod == 'mixed')
                  ? (bankAmount ?? 0)
                  : 0.0);
          final arRefund = (total - paid).clamp(0.0, double.infinity);
          final cogsAmount = items.fold<double>(
              0.0,
              (s, i) =>
                  s +
                  (i.costPrice.present ? i.costPrice.value : 0.0) *
                      (i.quantity.present ? i.quantity.value : 0.0) *
                      (i.quantityInBase.present ? i.quantityInBase.value : 1.0));
          await autoPostSalesReturn(
            originalInvoice: sale,
            returnAmount: total,
            cogsAmount: cogsAmount,
            cashRefund: cashRefund,
            bankRefund: bankRefund,
            arRefund: arRefund,
            vatAmount: tax,
            costCenterId: costCenterId,
          );
        } else {
          final isFullCredit = sale.paymentMethod == 'credit' ||
              (sale.total - sale.paid > 0.01 && sale.paid == 0);
          if (isFullCredit) {
            await autoPostCreditSale(sale);
          } else {
            // autoPostCashSale handles cash, bank, click, and mixed payments
            await autoPostCashSale(sale);
          }
        }
      }
    } catch (e) {
      // Log to failed_autoposts for startup repair.
      debugPrint('[AUTOPOST] Sale #$invoiceId JE failed (logged to failed_autoposts): $e');
      try {
        await into(failedAutoposts).insert(
          FailedAutopostsCompanion.insert(
            invoiceId: invoiceId,
            referenceType: saleType == 'return' ? 'sales_return' : 'sale',
            errorMessage: e.toString(),
          ),
        );
      } catch (logErr) {
        debugPrint('[AUTOPOST-LOG] Failed to record failure for sale #$invoiceId: $logErr');
      }
      // ISS-003: Immediate background retry — reduces the gap between the committed
      // safe balance update (Phase 6) and the JE creation from "until next startup"
      // to "milliseconds". The hasAutoPostEntry dedup guard makes retries idempotent.
      // Cluster 023 / Issue 1 — retry path branches on saleType too, otherwise a
      // failed quick-return retry would silently call autoPostCashSale (wrong direction).
      unawaited(Future.delayed(const Duration(milliseconds: 150), () async {
        try {
          final saleForRetry = await getSalesInvoiceById(invoiceId);
          if (saleForRetry == null) return;
          if (saleType == 'return') {
            final cashRefundRetry = (paymentMethod == 'cash')
                ? paid
                : ((paymentMethod == 'multiple' || paymentMethod == 'mixed')
                    ? (cashAmount ?? 0)
                    : 0.0);
            final bankRefundRetry = (isBankPaymentMethod(paymentMethod))
                ? paid
                : ((paymentMethod == 'multiple' || paymentMethod == 'mixed')
                    ? (bankAmount ?? 0)
                    : 0.0);
            final arRefundRetry = (total - paid).clamp(0.0, double.infinity);
            final cogsRetry = items.fold<double>(
                0.0,
                (s, i) =>
                    s +
                    (i.costPrice.present ? i.costPrice.value : 0.0) *
                        (i.quantity.present ? i.quantity.value : 0.0) *
                        (i.quantityInBase.present ? i.quantityInBase.value : 1.0));
            await autoPostSalesReturn(
              originalInvoice: saleForRetry,
              returnAmount: total,
              cogsAmount: cogsRetry,
              cashRefund: cashRefundRetry,
              bankRefund: bankRefundRetry,
              arRefund: arRefundRetry,
              vatAmount: tax,
              costCenterId: costCenterId,
            );
            await (delete(failedAutoposts)
                  ..where((f) =>
                      f.invoiceId.equals(invoiceId) &
                      f.referenceType.equals('sales_return')))
                .go();
          } else {
            final isFullCreditRetry = saleForRetry.paymentMethod == 'credit' ||
                (saleForRetry.total - saleForRetry.paid > 0.01 && saleForRetry.paid == 0);
            if (isFullCreditRetry) {
              await autoPostCreditSale(saleForRetry);
            } else {
              await autoPostCashSale(saleForRetry);
            }
            await (delete(failedAutoposts)
                  ..where((f) =>
                      f.invoiceId.equals(invoiceId) &
                      f.referenceType.equals('sale')))
                .go();
          }
          debugPrint('[AUTOPOST] Sale #$invoiceId JE retry succeeded — removed from failed_autoposts');
        } catch (_) {
          // Retry also failed — startup repair via repairFailedDeliveryAutoposts() will handle it
        }
      }));
    }

    // Phase 8.5: Submit for approval if a workflow applies (non-fatal)
    if (saleType != 'return') {
      try {
        await submitForApproval(
          entityType: 'sales_invoice',
          entityId: invoiceId,
          amount: total,
          requestedBy: userId,
          notes: 'فاتورة مبيعات تلقائية',
        );
      } catch (e) {
        debugPrint('[APPROVAL] submitForApproval failed for invoice #$invoiceId: $e');
      }
    }

    // Phase 9: Auto-award loyalty points (non-fatal, runs after autopost)
    if (customerId != null && saleType != 'return' && total > 0.01) {
      try {
        final program = await (select(loyaltyPrograms)
              ..where((p) => p.isActive.equals(true))
              ..limit(1))
            .getSingleOrNull();
        if (program != null) {
          // BUG-M08: round (not floor) so fractional point earns are not
          // systematically dropped. Owner-confirmed policy 2026-06-25; revert
          // this single line to .floor() if the business wants truncation.
          final pointsEarned = (total * program.pointsPerCurrency).round();
          if (pointsEarned > 0) {
            await transaction(() async {
              // Record the loyalty transaction
              await into(loyaltyTransactions).insert(
                LoyaltyTransactionsCompanion.insert(
                  customerId: customerId,
                  programId: program.id,
                  type: 'earn',
                  points: pointsEarned,
                  saleId: Value(invoiceId),
                  notes: Value('نقاط مكتسبة — فاتورة #$invoiceId'),
                ),
              );
              // Update or create customer balance record
              final existing = await (select(customerLoyaltyPoints)
                    ..where(
                      (c) =>
                          c.customerId.equals(customerId) &
                          c.programId.equals(program.id),
                    ))
                  .getSingleOrNull();
              if (existing != null) {
                await (update(customerLoyaltyPoints)
                      ..where((c) => c.id.equals(existing.id)))
                    .write(CustomerLoyaltyPointsCompanion(
                  totalEarned: Value(existing.totalEarned + pointsEarned),
                  currentBalance: Value(existing.currentBalance + pointsEarned),
                ));
              } else {
                await into(customerLoyaltyPoints).insert(
                  CustomerLoyaltyPointsCompanion.insert(
                    customerId: customerId,
                    programId: program.id,
                    totalEarned: Value(pointsEarned),
                    currentBalance: Value(pointsEarned),
                  ),
                );
              }
            });
          }
        }
      } catch (e) {
        debugPrint('[LOYALTY] Auto-allocate points failed for invoice #$invoiceId: $e');
      }
    }

    return invoiceId;
  }

  /// Simplified alias for createSalesInvoice for compatibility
  Future<int> legacyCreateSalesInvoice({
    required SalesInvoicesCompanion invoice,
    required List<SalesInvoiceItemsCompanion> items,
  }) async {
    return transaction(() async {
      // UUID-First (Phase 1): fill in a global_id if the caller didn't.
      final legacyHasGid = invoice.globalId.present &&
          (invoice.globalId.value?.isNotEmpty ?? false);
      final invoiceToInsert = legacyHasGid
          ? invoice
          : invoice.copyWith(globalId: Value(UuidV7.generate()));
      final id = await into(salesInvoices).insert(invoiceToInsert);
      for (final item in items) {
        await into(
          salesInvoiceItems,
        ).insert(item.copyWith(invoiceId: Value(id)));

        // Update stock (UOM: apply quantityInBase conversion)
        final product = await getProductById(item.productId.value);
        if (product != null && product.trackInventory) {
          final legacyQtyInBase = item.quantityInBase.present ? item.quantityInBase.value : 1.0;
          await adjustStock(
            productId: product.id,
            warehouseId: invoice.warehouseId.value,
            quantity: -(item.quantity.value * legacyQtyInBase),
            type: 'legacy_sale',
            referenceType: 'sales_invoice',
            referenceId: id,
            notes: 'مبيعات (Legacy) فاتورة #${invoice.invoiceNumber.value}',
          );
        }
      }
      return id;
    });
  }

  /// Insert sales invoice WITHOUT stock deduction.
  /// Used by client dual-write: server already handles stock, client just caches for local visibility.
  Future<int> insertSalesInvoiceWithoutStock({
    required SalesInvoicesCompanion invoice,
    required List<SalesInvoiceItemsCompanion> items,
  }) async {
    return transaction(() async {
      final id = await into(salesInvoices).insertOnConflictUpdate(invoice);
      for (final item in items) {
        await into(
          salesInvoiceItems,
        ).insertOnConflictUpdate(item.copyWith(invoiceId: Value(id)));
      }
      await resignSalesInvoice(id);
      return id;
    });
  }

  /// Record sales receipt in treasury
  Future<void> _recordSalesReceipt(
    int invoiceId,
    double amount,
    String paymentMethod, {
    int? userId,
    int? specificSafeId, // Override: use this safe instead of default
    int? warehouseId,    // Branch-aware safe resolution: prefer branch safe over system default
    int? customerId,     // P1-6: link safe transaction to party for traceability
    double? paymentRate,
    double? foreignAmount,
  }) async {
    final isNegative = amount < 0;
    final absAmount = amount.abs();

    // Map payment method to safe type.
    // 'bank' covers all non-cash electronic payments (card, visa, transfer, etc.)
    const bankMethods = {'bank', 'card', 'transfer', 'visa', 'mastercard', 'amex', 'mada', 'stcpay'};
    final safeType = paymentMethod == 'click'
        ? 'click'
        : bankMethods.contains(paymentMethod)
        ? 'bank'
        : 'cash';

    // سُلَّمُ الاختيار (P1/P2/P3) مشتركٌ الآن مع مسار المرتجع — انظر
    // `resolveSafeForOperation` في treasury_dao. لا `preferredBranchId` هنا:
    // البيعةُ تشتقّ فرعَها من مخزنها كما كانت دائماً، فسلوكُها محفوظٌ حرفيّاً.
    final targetSafe = await resolveSafeForOperation(
      safeType: safeType,
      warehouseId: warehouseId,
      specificSafeId: specificSafeId,
      operationLabel: 'invoice #$invoiceId/$paymentMethod',
      noSafeMessage:
          'لا توجد خزنة ${safeType == 'cash' ? 'نقدية' : safeType} صالحة '
          'لتسجيل المتحصَّل. اضبط الخزائن من الإعدادات ← الخزينة قبل البيع '
          '(الفاتورة لم تُحفظ).',
    );

    final newBalance = targetSafe.balance + amount; // negative if return
    // allow-bare-generateInvoiceNumber: _recordSalesReceipt is a private
    // helper called only from createSalesInvoice (lines 349, 358, 367, 377),
    // which wraps in transaction() at line 50.
    final voucherNumber = await generateInvoiceNumber(isNegative ? 'PV' : 'RV');

    // Deterministic UUID — prevents duplicate safe transactions when the
    // same sale is submitted via multiple paths (POS + server sync).
    // Format: safe_txn:sales_invoice:<invoiceId>:<safeId>:<safeType>
    final invoice = await (select(salesInvoices)
          ..where((i) => i.id.equals(invoiceId)))
        .getSingle();
    final invoiceIdentity = invoice.globalId ?? 'id:$invoiceId';
    final txnGlobalId = const Uuid().v5(
      Uuid.NAMESPACE_URL,
      'safe_txn:sales_invoice:$invoiceIdentity:${targetSafe.id}:$safeType',
    );

    await (into(safeTransactions).insertOnConflictUpdate(
      SafeTransactionsCompanion.insert(
        voucherNumber: voucherNumber,
        safeId: targetSafe.id,
        transactionType: isNegative ? 'payment' : 'receipt',
        category: isNegative ? 'return' : 'sales',
        amount: absAmount,
        balanceAfter: newBalance,
        referenceType: const Value('sales_invoice'),
        referenceId: Value(invoiceId),
        userId: Value(userId),
        partyId: Value(customerId),
        globalId: Value(txnGlobalId),
         currencyId: Value(invoice.currencyId),
         exchangeRate: Value(paymentRate),
         foreignAmount: Value(foreignAmount),
      ),
    ));

    if (paymentRate != null && foreignAmount != null) {
       final bookingRate = invoice.exchangeRate;
       if (invoice.currencyId != null && bookingRate != null && bookingRate > 0) {
         await _postRealizedFxDifference(
           invoiceType: 'sales',
           invoiceId: invoiceId,
           transactionId: txnGlobalId,
           foreignAmount: foreignAmount,
           bookingRate: bookingRate,
           settlementRate: paymentRate,
           partyId: customerId,
           entryDate: DateTime.now(),
         );
       }
     }

     // H15 · `adjustSafeBalance` لا `updateSafeBalance`: الثاني كتابةٌ مطلقة
    // بعد قراءة (`safe.balance + amount`) — وهو سباقُ «التحديث الضائع» تحت
    // عزل PostgreSQL الافتراضيّ Read-Committed: بيعتان متزامنتان بـ١٠٠ على
    // نفس الخزنة تنزلان +١٠٠ لا +٢٠٠. الأول يُجري الحسابَ في SQL نفسِه.
    // `newBalance` يبقى لـ`balanceAfter` — وهو لقطةٌ بطبيعتها.
    // (‏الوثيقةُ على `updateSafeBalance` تنصّ على هذا صراحةً: Spec 069/D5-003.)
    await adjustSafeBalance(targetSafe.id, amount);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SALES REPORTS — See sales_analytics_dao.dart
  // ═══════════════════════════════════════════════════════════════════════

  Future<int> _reverseActiveSaleEntriesForEdit(
    int invoiceId,
    String descriptionPrefix,
  ) async {
    final entries = await (select(journalEntries)
          ..where((e) =>
              (e.referenceType.equals('sales_invoice') |
                  e.referenceType.equals('sale') |
                  e.referenceType.equals('cash_sale') |
                  e.referenceType.equals('credit_sale')) &
              e.referenceId.equals(invoiceId) &
              e.isPosted.equals(true) &
              e.isDeleted.equals(false)))
        .get();
    var reversalCount = 0;
    for (final entry in entries) {
      final reversal = await (select(journalEntries)
            ..where((e) => e.referenceType.equals('reversal') &
                e.referenceId.equals(entry.id) &
                e.isPosted.equals(true) &
                e.isDeleted.equals(false))
            ..limit(1))
          .getSingleOrNull();
      if (reversal != null) {
        reversalCount++;
        continue;
      }
      await reverseJournalEntryById(
        entryId: entry.id,
        descriptionPrefix: descriptionPrefix,
      );
      reversalCount++;
    }
    return reversalCount;
  }

  /// Update an existing sales invoice with new data
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
    // 062 (D1-004): caller's userId for the modifyLockedInvoice gate.
    // Null = no override = same throw as today.
    int? userId,
  }) async {
    return transaction(() async {
      // Get old invoice data first
      final oldInvoice = await (select(
        salesInvoices,
      )..where((i) => i.id.equals(invoiceId))).getSingleOrNull();
      if (oldInvoice == null) return;

      // ISS-04 + 062 (D1-004): Prevent editing locked/posted invoices
      // unless the caller holds the modifyLockedInvoice permission.
      if (oldInvoice.isLocked) {
        await permissionEnforcer.requireCriticalOp(
          userId: userId,
          code: PermissionCodes.modifyLockedInvoice,
          arabicReason: 'لا يمكن تعديل فاتورة مُرحّلة محاسبيًا. '
              'استخدم المرتجعات بدلاً من التعديل، '
              'أو يلزم صلاحية "تعديل فاتورة مقفلة".',
        );
      }

      // 0. Soft/Hard Period Closing Gating
      await accountingDao.validateFinancialPeriod(oldInvoice.invoiceDate, operation: 'تعديل فاتورة مبيعات');

      final oldItems = await (select(
        salesInvoiceItems,
      )..where((i) => i.invoiceId.equals(invoiceId))).get();
      final amountsChanged = oldInvoice.isLocked &&
          (oldInvoice.subtotal != subtotal ||
              oldInvoice.discount != discount ||
              oldInvoice.tax != tax ||
              oldInvoice.total != total);
      var repostRevision = 0;
      if (amountsChanged) {
        repostRevision = await _reverseActiveSaleEntriesForEdit(
          invoiceId,
          'عكس تعديل مبالغ فاتورة مبيعات',
        );
      }

      final oldPaid = oldInvoice.paid;

      // Restore old stock quantities (UOM: apply quantityInBase conversion)
      for (final oldItem in oldItems) {
        final product = await getProductById(oldItem.productId);
        if (product != null && product.trackInventory) {
          final oldQtyInBase = oldItem.quantityInBase > 0 ? oldItem.quantityInBase : 1.0;
          final restoreQty = oldItem.quantity * oldQtyInBase;
          // Editing an invoice restores the OLD lines and then re-issues the
          // new ones. Nets to zero when the quantity is unchanged, but a
          // reduced quantity leaves goods on hand — and those goods must
          // carry the cost the original invoice froze, not today's WAC.
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

      // Delete old invoice items
      await (delete(
        salesInvoiceItems,
      )..where((i) => i.invoiceId.equals(invoiceId))).go();

      // Update invoice header
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
      // v175 — `paid` يُكتَب عبر الثابت وحدَه: تحريرُ فاتورةٍ لا يمسّ
      // تخصيصاتِها، فالقاعدةُ تُعاد حسابُها من الفرق.
      await _writeSalesInvoicePaid(invoiceId, paid);
      await resignSalesInvoice(invoiceId);

      // Insert new items and update stock
      for (final item in items) {
        await into(
          salesInvoiceItems,
        ).insert(item.copyWith(invoiceId: Value(invoiceId)));

        // Deduct new stock (UOM: apply quantityInBase conversion)
        final prodId = item.productId.value;
        final quantity = item.quantity.value;
        final editQtyInBase = item.quantityInBase.present ? item.quantityInBase.value : 1.0;
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

      // Adjust treasury if payment changed
      // Enhanced: Properly splits diffs for multi-payment (cash+bank) invoices
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

  // ignore: unused_local_variable
        final newCash = diff.newDistribution.cash;
  // ignore: unused_local_variable
        final newBank = diff.newDistribution.bank;
  // ignore: unused_local_variable
        final newClick = diff.newDistribution.click;

        // Apply cash safe diff
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
            await adjustSafeBalance(cashSafe.id, cashDiff); // H15
          }
        }

        // Apply bank safe diff
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
            await adjustSafeBalance(bankSafe.id, bankDiff); // H15
          }
        }

        // Apply click safe diff
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
            await adjustSafeBalance(clickSafe.id, clickDiff); // H15
          }
        }
      }

      // Update customer balance if applicable
      if (oldInvoice.customerId != null) {
        final oldRemaining = oldInvoice.total - oldPaid;
        final newRemaining = total - paid;
        final balanceDiff = newRemaining - oldRemaining;
        if (balanceDiff != 0) {
          await adjustPartyBalance(oldInvoice.customerId!, balanceDiff);
         }
       }

       if (amountsChanged) {
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

  /// Update sales invoice payment method and notes with treasury adjustments
  /// When payment method changes, moves amounts between cash and bank safes
  Future<void> updateSalesInvoicePayment(
    int invoiceId,
    String newPaymentMethod,
    String? notes, {
    double? newCashAmount,
    double? newBankAmount,
  }) async {
    return transaction(() async {
      // Get the current invoice
      final invoice = await (select(
        salesInvoices,
      )..where((i) => i.id.equals(invoiceId))).getSingleOrNull();
      if (invoice == null) return;

      // 0. Soft/Hard Period Closing Gating
      await accountingDao.validateFinancialPeriod(invoice.invoiceDate, operation: 'تعديل دفعة فاتورة مبيعات');

      // ISS-04 REVISED: Allow payment method changes on locked/posted invoices.
      // The existing journal entry is reversed and a new one is created so the
      // GL stays consistent. Editing line items or amounts still requires a return.
      final needsJournalReversal =
          invoice.isLocked && invoice.paymentMethod != newPaymentMethod;
      var repostRevision = 0;
      if (needsJournalReversal) {
        repostRevision = await _reverseActiveSaleEntriesForEdit(
          invoiceId,
          'عكس تعديل وسيلة دفع فاتورة مبيعات',
        );
      }

      final oldPaymentMethod = invoice.paymentMethod;
      final paidAmount = invoice.paid;
      // Skip if no payment method change or no paid amount
      if (oldPaymentMethod == newPaymentMethod) {
        // Just update the payment method and notes
        await (update(
          salesInvoices,
        )..where((i) => i.id.equals(invoiceId))).write(
          SalesInvoicesCompanion(
            paymentMethod: Value(newPaymentMethod),
            notes: Value(notes),
          ),
        );
        await resignSalesInvoice(invoiceId);
        return;
      }

      final diff = SalesPaymentCalculator.computeMethodChangeDiff(
        oldPaymentMethod: oldPaymentMethod,
        totalPaid: paidAmount,
        oldCashPaid: invoice.cashPaid,
        oldBankPaid: invoice.bankPaid,
        oldClickPaid: invoice.clickPaid,
        newPaymentMethod: newPaymentMethod,
        explicitlyProvidedNewCash: newCashAmount,
        explicitlyProvidedNewBank: newBankAmount,
      );

      final newCash = diff.newDistribution.cash;
      final newBank = diff.newDistribution.bank;
      final newClick = diff.newDistribution.click;

      // Adjust cash safe if needed
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
              category: 'payment_adjustment',
              amount: cashDiff.abs(),
              balanceAfter: newBalance,
              referenceType: const Value('sales_invoice'),
              referenceId: Value(invoiceId),
              description: Value(
                'تعديل وسيلة الدفع من $oldPaymentMethod إلى $newPaymentMethod',
              ),
            ),
          );

          await adjustSafeBalance(cashSafe.id, cashDiff); // H15
        }
      }

      // Adjust bank safe if needed
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
              category: 'payment_adjustment',
              amount: bankDiff.abs(),
              balanceAfter: newBalance,
              referenceType: const Value('sales_invoice'),
              referenceId: Value(invoiceId),
              description: Value(
                'تعديل وسيلة الدفع من $oldPaymentMethod إلى $newPaymentMethod',
              ),
            ),
          );

          await adjustSafeBalance(bankSafe.id, bankDiff); // H15
        }
      }

      // Adjust click safe if needed
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
              category: 'payment_adjustment',
              amount: clickDiff.abs(),
              balanceAfter: newBalance,
              referenceType: const Value('sales_invoice'),
              referenceId: Value(invoiceId),
              description: Value(
                'تعديل وسيلة الدفع من $oldPaymentMethod إلى $newPaymentMethod',
              ),
            ),
          );

          await adjustSafeBalance(clickSafe.id, clickDiff); // H15
        }
      }

      // Update invoice
      await (update(salesInvoices)..where((i) => i.id.equals(invoiceId))).write(
        SalesInvoicesCompanion(
          paymentMethod: Value(newPaymentMethod),
          cashPaid: Value(newCash),
          bankPaid: Value(newBank),
          clickPaid: Value(newClick),
          notes: Value(notes),
        ),
      );
      await resignSalesInvoice(invoiceId);

      // Re-post journal entry with new payment method for locked invoices
      if (needsJournalReversal) {
        final updated = await getSalesInvoiceById(invoiceId);
        if (updated != null) {
          if (newPaymentMethod == 'credit') {
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
          debugPrint('[SalesMutations] Re-posted journal entry for payment=$newPaymentMethod');
        }
      }
      await resignSalesInvoice(invoiceId);
    });
  }

  /// Get sales invoice items with their product data (for details dialog)
  /// [product] is nullable: a line whose product row is gone must still be
  /// returned, otherwise the dialog shows a total its lines don't explain.
  Future<List<({SalesInvoiceItem item, Product? product})>>
  getSalesInvoiceItemsWithProduct(int invoiceId) async {
    final items = await getSalesInvoiceItems(invoiceId);
    final result = <({SalesInvoiceItem item, Product? product})>[];
    for (final item in items) {
      result.add((item: item, product: await getProductById(item.productId)));
    }
    return result;
  }

  /// Update delivery status for a sales invoice.
  /// When status changes to 'delivered', triggers reversal of deferred revenue
  /// entry and creation of the proper sales revenue journal entry (GAP-22).
  Future<void> updateSalesDeliveryStatus(int invoiceId, String newStatus) async {
    final oldInvoice = await getSalesInvoiceById(invoiceId);
    if (oldInvoice == null) return;

    // Spec 151 F-05 — post the deferred→revenue JE BEFORE flipping the status,
    // and FAIL LOUD (no swallow). Previously the status was written FIRST and a
    // JE failure was caught by a bare catch{debugPrint} → the invoice showed
    // 'delivered' while its revenue stayed deferred (the exact A-03/A-04
    // swallow-and-commit class the campaign eliminated).
    //
    // We deliberately do NOT wrap the two writes in a single db.transaction():
    // nesting a transaction() around autoPostDeliveryConfirmed /
    // createJournalEntry has caused a confirmed "database is locked" deadlock
    // (SqliteException 517) twice in this codebase — see createSalesInvoice's
    // Phase-8 comment, the autoPostDeliveryConfirmed class doc, and the ACC-1
    // fail-loud test which pins the no-nested-transaction design. Ordering the
    // JE first achieves the SAME invariant — the status can never advance to
    // 'delivered' while revenue is still deferred — because a JE failure throws
    // here and the status write below is never reached.
    // autoPostDeliveryConfirmed is idempotent (dedup guard) so an operator
    // retry converges, and repairFailedDeliveryAutoposts still heals any legacy
    // 'delivered'-without-revenue rows at boot.
    if (newStatus == 'delivered' && oldInvoice.deliveryStatus != 'delivered') {
      await autoPostDeliveryConfirmed(invoiceId);
    }

    await (update(salesInvoices)..where((i) => i.id.equals(invoiceId))).write(
      SalesInvoicesCompanion(deliveryStatus: Value(newStatus)),
    );
  }

  /// Sum all payment_allocations for a given sales invoice.
  /// Used by [PaymentAllocationSyncStrategy] to recalculate the invoice's
  /// `paid` column whenever a new allocation arrives via delta-pull.
  Future<double> getPaymentAllocationsTotal(int invoiceId) async {
    final rows = await customSelect(
      'SELECT COALESCE(SUM(allocated_amount), 0.0) AS total '
      'FROM payment_allocations '
      "WHERE invoice_id = ? AND invoice_type = 'sales'",
      variables: [Variable<int>(invoiceId)],
      readsFrom: {paymentAllocations},
    ).getSingleOrNull();
    final raw = rows?.data['total'];
    if (raw == null) return 0.0;
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw) ?? 0.0;
    return 0.0;
  }

  /// Update sales invoice paid amount and status
  Future<void> updateSalesInvoicePaidAmount(
    int invoiceId,
    double newPaid,
  ) async {
    // Fetch the invoice to get its total for status calculation
    final invoice = await (select(salesInvoices)
          ..where((i) => i.id.equals(invoiceId)))
        .getSingleOrNull();

    String newStatus = 'pending';
    if (invoice != null) {
      if (newPaid >= invoice.total) {
        newStatus = 'paid';
      } else if (newPaid > 0) {
        newStatus = 'partial';
      }
    }

    await _writeSalesInvoicePaid(invoiceId, newPaid, status: newStatus);
    await resignSalesInvoice(invoiceId);
  }

  /// يكتب `paid` **ويُبقي الثابتَ** — الموضعُ الوحيدُ الذي يكتب العمودَين معاً.
  ///
  ///     paid = paid_unallocated + Σ payment_allocations
  ///
  /// ═══ 🔴 لماذا موضعٌ واحد ═══
  ///
  /// `PaymentAllocationSyncStrategy` تُعيد حسابَ `paid` من القاعدة والمجموع.
  /// فكلُّ كاتبٍ يرفع `paid` **بلا تخصيصٍ** يجب أن يرفع القاعدةَ بقدره،
  /// وإلّا محا أوّلُ إعادةِ حسابٍ ما كتبه: فاتورةٌ دُفع منها ٣٠٠ نقداً عند
  /// البيع وخُصِّص لها ٧٠٠ لاحقاً تعود إلى ٧٠٠ — وتختفي الثلاثُمئة من دفتر
  /// المبيعات ومن رصيد العميل معاً.
  ///
  /// وأربعةُ كُتّابٍ يكتبون `paid` مطلقاً (الإنشاءُ · التحريرُ · التحصيلُ ·
  /// هذا الضابط)، فجمعُ القاعدة في دالّةٍ واحدةٍ يجعل الثابتَ **بناءً** لا
  /// اتّفاقاً بين أربعة مواضع.
  ///
  /// ⚠️ **والقاعدةُ لا تنزل تحت الصفر**: ضبطٌ يخفض `paid` دون مجموعِ
  /// التخصيصات يعني أنّ تخصيصاتٍ لم تعد صحيحةً — وقصُّها عند الصفر يجعل
  /// إعادةَ الحساب تُرجع `paid` إلى المجموع، أي أنّ **التخصيصاتِ تفوز**.
  /// وهو عينُ ما تفعله الاستراتيجيّةُ اليوم (`serverWins`)، ولا يُفقَد به
  /// شيءٌ لم يكن يُفقَد قبل العمود.
  Future<void> _writeSalesInvoicePaid(
    int invoiceId,
    double newPaid, {
    String? status,
  }) async {
    final allocated = await getPaymentAllocationsTotal(invoiceId);
    final base = newPaid - allocated;
    await (update(salesInvoices)..where((i) => i.id.equals(invoiceId))).write(
      SalesInvoicesCompanion(
        paid: Value(newPaid),
        paidUnallocated: Value(base < 0 ? 0 : base),
        status: status == null ? const Value.absent() : Value(status),
      ),
    );
  }

  /// Spec 151 C-05 — apply a customer collection to a sales invoice. The exact
  /// symmetric TWIN of `PurchaseDao.addPurchasePayment` (C-03), for the money
  /// path a credit-sale collection was missing entirely (the old
  /// [updateSalesInvoicePaidAmount] wrote ONLY paid+status — no receipt,
  /// treasury, GL or party-balance move, and was ungated).
  ///
  /// ⚠️ [amount] is the DELTA collected THIS event, NOT an absolute new-paid.
  /// The sales `recordPayment(amount)` API carries an ABSOLUTE newPaid (unlike
  /// purchases, whose recordPayment carries a delta); the repository computes
  /// `delta = newPaid - invoice.paid` and feeds the DELTA here.
  ///
  /// The MONEY is posted by REUSING the existing receipt path
  /// ([createReceiptVoucher]): Dr Safe / Cr Customer-AR + safe balance +
  /// parties.balance + a balanced JE. This DAO owns ONLY the
  /// sales_invoices.paid/status advance — createReceiptVoucher deliberately
  /// never touches sales_invoices, so (CRUX 2 — no AR double-count) the credit
  /// sale's Dr-Customer at sale time is reversed here by exactly one Cr-Customer
  /// (via the receipt's party-AR leg, because partyId is set the JE credits the
  /// customer's AR sub-account, NOT revenue), and this invoice's paid is
  /// advanced exactly once, separately.
  ///
  /// R3 atomicity: the whole thing is in a transaction() — if the receipt/JE
  /// cannot post (no safe configured / period closed), createReceiptVoucher
  /// throws and the paid advance above rolls back too (fail-loud, mirroring
  /// addPurchasePayment's B7 guard).
  Future<void> addSalesPayment({
    required int invoiceId,
    required double amount,
    int? safeId,
    int? userId,
    String? globalId,
    double? paymentRate,
    double? foreignAmount,
  }) async {
    return transaction(() async {
      // Spec 151 C-05 idempotency (mirrors addPurchasePayment): a collection is
      // ADDITIVE, so an offline-outbox replay or a mirror re-submit carrying the
      // SAME globalId must NOT double-apply (over-crediting the safe, double-
      // reducing AR, over-advancing paid). The receipt's safe_transaction stamps
      // this globalId (threaded into createReceiptVoucher below), so if one
      // already exists this event was applied → return without touching
      // paid/safe/JE. Dedup lives here (not only in the HTTP handler) so BOTH the
      // local path and the server handler are idempotent. Inside the transaction
      // so it can't race a concurrent apply.
      if (globalId != null && globalId.isNotEmpty) {
        final existing = await (select(safeTransactions)
              ..where((t) => t.globalId.equals(globalId))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) return;
      }

      final invoice = await getSalesInvoiceById(invoiceId);
      if (invoice == null) throw Exception('Invoice not found');

      // Spec 151 C-05 — a collection MUST credit the customer's AR. With a null
      // customerId, createReceiptVoucher falls back to the 'sales' category
      // account (revenue) and would double-book revenue already recognised at
      // sale time. Upstream invariants (credit sales require a customer) make
      // this unreachable today, but fail loud rather than trust them — the
      // server handler could otherwise resolve a customerless invoice.
      if (invoice.customerId == null) {
        throw StateError(
          'تعذّر تسجيل تحصيل الفاتورة #${invoice.invoiceNumber}: '
          'لا يوجد عميل مرتبط بالفاتورة لقيد التحصيل على حسابه.',
        );
      }

      // 0. Soft/Hard Period Closing Gating (mirrors addPurchasePayment).
      await accountingDao.validateFinancialPeriod(invoice.invoiceDate,
          operation: 'تحصيل دفعة مبيعات');

      final settledAtBooking = invoice.currencyId != null &&
              invoice.exchangeRate != null &&
              invoice.exchangeRate! > 0 &&
              foreignAmount != null
          ? foreignAmount * invoice.exchangeRate!
          : amount;
      final newPaid = invoice.paid + settledAtBooking;
      final newRemaining = invoice.total - newPaid;
      final newStatus = newRemaining <= 0 ? 'paid' : 'partial';

      // v175 — تحصيلٌ **بلا تخصيص**، فالقاعدةُ تزيد بنفس المبلغ:
      // `base' = newPaid − Σ = (paid + amount) − Σ = base + amount`.
      await _writeSalesInvoicePaid(invoiceId, newPaid, status: newStatus);
      await resignSalesInvoice(invoiceId);
      // Post the MONEY via the receipt path: Dr Safe / Cr Customer-AR + safe
      // balance + parties.balance + balanced JE. Thread the SAME globalId so the
      // receipt's safe_transaction carries it for the dedup guard above. Both
      // skip flags false → full money post (never skip; we WANT the cash + JE).
      final receiptTxnId = await createReceiptVoucher(
        amount: amount,
        category: 'sales',
        partyId: invoice.customerId,
        safeId: safeId,
        userId: userId,
        costCenterId: invoice.costCenterId,
        globalId: globalId,
        operatingBranchId: invoice.branchId,
        currencyId: invoice.currencyId,
        paymentRate: paymentRate,
        foreignAmount: foreignAmount,
      );

      // B7 (S-FAILLOUD) parity: a collection must move cash AND post a balanced
      // JE. createReceiptVoucher throws (no target safe / unresolved account /
      // closed period) → the paid advance above rolls back with it. The <=0
      // guard is a defensive belt: the full money post returns the inserted
      // safe_transaction id (>0), so a 0 could only come from a future skip path
      // — reject it loudly rather than leave paid advanced with no treasury/GL.
      if (paymentRate != null && foreignAmount != null &&
          invoice.currencyId != null &&
          invoice.exchangeRate != null &&
          invoice.exchangeRate! > 0) {
        await _postRealizedFxDifference(
          invoiceType: 'sales',
          invoiceId: invoice.id,
          transactionId: globalId ?? 'sales-payment:$invoiceId:$receiptTxnId',
          foreignAmount: foreignAmount,
          bookingRate: invoice.exchangeRate!,
          settlementRate: paymentRate,
          partyId: invoice.customerId,
          entryDate: DateTime.now(),
        );
        final bookingAmount = foreignAmount * invoice.exchangeRate!;
        await adjustPartyBalance(invoice.customerId!, -(bookingAmount - amount));
      }

      if (receiptTxnId <= 0) {
        throw StateError(
          'تعذّر تسجيل تحصيل الفاتورة #${invoice.invoiceNumber}: '
          'لم يُنشأ سند القبض (لا يوجد صندوق/بنك محدد لاستلام الدفعة). '
          'راجع إعدادات الصناديق قبل تسجيل التحصيل.',
        );
      }
      await resignSalesInvoice(invoiceId);
    });
  }

}
