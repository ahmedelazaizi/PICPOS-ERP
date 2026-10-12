// Purchase insert-without-side-effects path, supplier invoice number guard, treasury payment recording.
part of '../database.dart';

extension PurchaseInsertSupportDao on AppDatabase {
  /// Insert purchase invoice WITHOUT stock/accounting/treasury side effects.
  /// Used by client dual-write: server handles stock/WAC/GL, client just caches for local visibility.
  Future<int> insertPurchaseInvoiceWithoutStock({
    required int supplierId,
    required int warehouseId,
    required List<PurchaseInvoiceItemsCompanion> items,
    required double paid,
    String paymentMethod = 'cash',
    String? notes,
    String? supplierInvoiceNumber,
    DateTime? invoiceDate,
    int? costCenterId,
    // UUID-First (Phase 1): pass-through from the server's submission
    String? globalId,
     double? paymentRate,
     double? foreignAmount,
    // ح-1: mirror the server's net total in the local cache row, otherwise the
    // mirror's invoice list shows a gross total the server never stored.
    double discount = 0,
    // المرحلة ٨ — نفسُ لقطةِ العملة التي يخزّنها الخادم. بدونها يعرض
    // العميلُ فاتورةَ استيرادٍ **بلا عملتها** حتى أوّل سحبٍ يصحّحها، ويقرأ
    // المستخدمُ رقماً محلّيّاً بلا ما يقول إنّه كان بالدولار.
    int? currencyId,
    double? exchangeRate,
    ImportDocumentFields? importDetails,
    // J1b (v188) — the mirrored invoice's «حساب المشتريات» (raw column).
    int? purchaseAccountId,
  }) async {
    final badRate = validateExchangeRate(
      currencyId: currencyId,
      localPerForeign: exchangeRate,
    );
    if (badRate != null) throw ArgumentError(badRate);
    // الطولُ يفحصه `_writeImportPurchaseDetails` — راجع `createPurchaseInvoice`.
    return transaction(() async {
  // ignore: unused_local_variable
      final effectiveInvoiceDate = invoiceDate ?? DateTime.now();
      double taxTotal = 0;
      double total = 0;
      double subtotalSum = 0;

      for (final item in items) {
        final qty = item.quantity.present ? item.quantity.value : 1.0;
        final cost = item.unitCost.present ? item.unitCost.value : 0.0;
  // ignore: dead_code
        final rate = item.taxRate.present ? (item.taxRate.value ?? 0.0) : 0.0;
        final subtotal = qty * cost;
        // Honour the per-line `taxAmount` passed from the form so exempt
        // lines (toggle off) stay at 0 even when the product carries a
        // non-zero default rate. See createPurchaseInvoice for the same
        // fix; this path is used by the client-mode local cache.
        final tax = item.taxAmount.present
  // ignore: dead_code
            ? (item.taxAmount.value ?? 0.0)
            : subtotal * (rate / 100);
        subtotalSum += subtotal;
        total += subtotal + tax;
        taxTotal += tax;
      }

      // ح-1 (trade discount): same net rule as createPurchaseInvoice so the
      // mirror's cached header matches what the server actually stored. This
      // path writes no stock/WAC (that is the server's job), so only the
      // header amounts need netting here.
      final requestedDiscount =
          discount > 0 ? FinancialUtils.round(discount) : 0.0;
      // نفسُ قاعدةِ الإنشاء — وإلّا قالت ترويسةُ المرآة رقماً غيرَ الذي
      // خزّنه الخادمُ لنفس الفاتورة.
      var explicitLineDiscountSum = 0.0;
      for (final it in items) {
        final d = it.discount.present ? it.discount.value : 0.0;
        if (d > 0) explicitLineDiscountSum += d;
      }
      explicitLineDiscountSum = FinancialUtils.round(explicitLineDiscountSum);
      final effectiveDiscount = requestedDiscount > explicitLineDiscountSum
          ? requestedDiscount
          : explicitLineDiscountSum;
      total = FinancialUtils.round(total - effectiveDiscount);
      subtotalSum = FinancialUtils.round(subtotalSum - effectiveDiscount);

      final remaining = total - paid;
      final status = remaining <= 0.01 ? 'paid' : (paid > 0 ? 'partial' : 'pending');
      final invoiceNumber = await generateInvoiceNumber('PUR');

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
          invoiceDate: invoiceDate ?? DateTime.now(),
          dueDate: Value(dueAt),
          subtotal: Value(subtotalSum),
          discount: Value(effectiveDiscount),
          tax: Value(taxTotal),
          total: Value(total),
          paid: Value(paid),
          status: Value(status),
          paymentMethod: Value(paymentMethod),
          notes: Value(notes),
          supplierInvoiceNumber: Value(supplierInvoiceNumber),
          costCenterId: Value(costCenterId),
          currencyId: Value(currencyId),
          exchangeRate: Value(exchangeRate),
          globalId: Value(
            (globalId != null && globalId.isNotEmpty)
                ? globalId
                : UuidV7.generate(),
          ),
        ),
      );

      // نفسُ حكمِ مسار الإنشاء: الوسمُ في المعاملة لا بعدَها.
      if (importDetails != null) {
        await _writeImportPurchaseDetails(invoiceId, importDetails);
      }
      if (purchaseAccountId != null) {
        await setPurchaseInvoicePurchaseAccountId(invoiceId, purchaseAccountId);
      }

      for (final item in items) {
        final hasLineGid = item.globalId.present &&
            (item.globalId.value?.isNotEmpty ?? false);
        await into(purchaseInvoiceItems).insert(
          item.copyWith(
            invoiceId: Value(invoiceId),
            // UUID-First Phase 1 Slice 3: stable per-line identity.
            globalId: hasLineGid ? item.globalId : Value(UuidV7.generate()),
          ),
        );
      }
      await resignPurchaseInvoice(invoiceId);
      return invoiceId;
    });
  }

  /// Record purchase payment in treasury.
  ///
  /// البند 5 (متطلبات العميل 2026-07-25) — يرفض تكرار رقم فاتورة المورد
  /// **لنفس المورد**.
  ///
  /// Scope is per-supplier, NOT global: a supplier's invoice number is only
  /// unique within that supplier's own book, so two different suppliers may
  /// legitimately both issue `1001`. A global UNIQUE would reject real data.
  ///
  /// Blank/absent numbers are exempt — those invoices get an auto-generated
  /// `PUR-n`, which carries no business meaning to collide on.
  ///
  /// Soft-deleted (voided) invoices do not reserve their number.
  ///
  /// [excludeInvoiceId] must be passed on the edit path so re-saving an invoice
  /// under its own number isn't reported as a collision with itself.
  ///
  /// NOTE: this is an APPLICATION-level guard on purpose. A partial UNIQUE
  /// index is the stronger fix but must not be added until the customer's live
  /// database is confirmed free of pre-existing duplicates — otherwise the
  /// migration fails on their data.
  Future<void> _assertSupplierInvoiceNumberFree(
    int supplierId,
    String? number, {
    int? excludeInvoiceId,
  }) async {
    if (number == null || number.trim().isEmpty) return;
    final trimmed = number.trim();

    final query = select(purchaseInvoices)
      ..where((p) =>
          p.supplierId.equals(supplierId) &
          p.supplierInvoiceNumber.equals(trimmed) &
          p.isDeleted.equals(false))
      ..limit(2);

    final hits = await query.get();
    final clash = hits.where((h) => h.id != excludeInvoiceId).toList();
    if (clash.isEmpty) return;

    final supplier = await (select(parties)
          ..where((p) => p.id.equals(supplierId))
          ..limit(1))
        .getSingleOrNull();
    throw StateError(
      'رقم فاتورة المورد "$trimmed" مستخدم بالفعل '
      '${supplier != null ? 'للمورد «${supplier.name}» ' : ''}'
      '(فاتورة #${clash.first.invoiceNumber}). '
      'راجع الرقم أو افتح الفاتورة القائمة لتعديلها.',
    );
  }

  /// P2 (batch B7): returns the inserted safe-transaction row (or null when
  /// no target safe was resolved) so callers — [addPurchasePayment] — can
  /// feed it straight into [AccountingAutopostDao.autoPostPayment] without a
  /// second lookup, keeping the payment + its GL posting in one atomic pass.
  Future<SafeTransactionData?> _recordPurchasePayment(
    int invoiceId,
    double amount,
    String paymentMethod,
    int? costCenterId, {
    int? safeId,
    int? supplierId,
    int? userId,
    String? globalId,
     double? paymentRate,
     double? foreignAmount,
  }) async {
    final safeType = (paymentMethod == 'transfer' || paymentMethod == 'card')
        ? 'bank'
        : 'cash';

    Safe? targetSafe;

    // If a specific safe was requested by the user, use it directly
    if (safeId != null) {
      targetSafe = await (select(safes)..where((s) => s.id.equals(safeId))).getSingleOrNull();
    }

    if (targetSafe == null && costCenterId != null) {
      // Find default safe for this specific cost center. `.limit(1)` is
      // required to keep `getSingleOrNull` safe when a cost center has
      // more than one safe of the same type (e.g. main cash + secondary
      // cash till) — without it the whole purchase save crashes with
      // "Bad state: Too many elements".
      targetSafe = await (select(safes)
            ..where((s) =>
                s.safeType.equals(safeType) &
                s.costCenterId.equals(costCenterId) &
                s.isActive.equals(true))
            ..limit(1))
          .getSingleOrNull();
    }

    // Fallback to global default safe if none found
    targetSafe ??= await getDefaultSafeByType(safeType);

    if (targetSafe != null) {
      final newBalance = targetSafe.balance - amount;
      // allow-bare-generateInvoiceNumber: _recordPurchasePayment is a private
      // helper called only from createPurchaseInvoice, voidPurchaseInvoice
      // and addPurchasePayment — all already inside a transaction().
      final voucherNumber = await generateInvoiceNumber('PV');

      final txnId = await into(safeTransactions).insert(
        SafeTransactionsCompanion.insert(
          voucherNumber: voucherNumber,
          safeId: targetSafe.id,
          transactionType: 'payment',
          category: 'purchase',
          amount: amount,
          balanceAfter: newBalance,
          referenceType: const Value('purchase_invoice'),
          referenceId: Value(invoiceId),
          partyId: Value(supplierId),
          // Spec 151 C-03: stamp the caller's userId + deterministic globalId so
          // the payment voucher is attributable and dedup-keyed end-to-end
          // (offline replay / mirror re-submit match on this globalId).
          userId: Value(userId),
          globalId: Value(globalId),
           currencyId: Value((await (select(purchaseInvoices)..where((i) => i.id.equals(invoiceId))).getSingle()).currencyId),
           exchangeRate: Value(paymentRate),
           foreignAmount: Value(foreignAmount),
        ),
      );

      // H15 — خصمُ سدادٍ ذرّيّ: سدادان متزامنان على نفس الخزنة كانا
      // يقرآن نفسَ الرصيد فيضيع أحدُهما. `newBalance` لقطةُ `balanceAfter`.
      await adjustSafeBalance(targetSafe.id, -amount);

       if (paymentRate != null && foreignAmount != null) {
         final invoice = await (select(purchaseInvoices)..where((i) => i.id.equals(invoiceId))).getSingleOrNull();
         final bookingRate = invoice?.exchangeRate;
         if (invoice?.currencyId != null && bookingRate != null && bookingRate > 0) {
           await _postRealizedFxDifference(
             invoiceType: 'purchase',
             invoiceId: invoiceId,
             transactionId: globalId ?? 'purchase-payment:$invoiceId:$txnId',
             foreignAmount: foreignAmount,
             bookingRate: bookingRate,
             settlementRate: paymentRate,
             partyId: supplierId,
             entryDate: DateTime.now(),
           );
         }
       }

      return (select(safeTransactions)..where((t) => t.id.equals(txnId)))
          .getSingle();
    }
    return null;
  }
}
