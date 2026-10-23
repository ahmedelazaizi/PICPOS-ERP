// Party transaction history and statement entries.
part of '../database.dart';

extension PartyTransactionsDao on AppDatabase {
  /// Get party transaction history (sales/purchases + payments)
  Future<List<PartyStatementEntry>> getPartyStatement(
    int partyId, {
    DateTime? fromDate,
    DateTime? toDate,
    int? branchId,
  }) async {
    final party = await getPartyById(partyId);
    if (party == null) return [];

    // Normalize dates to include full day range (matching getSalesByDateRange behavior)
    final from = fromDate ?? DateTime(2020);
    final to = toDate != null
        ? DateTime(
            toDate.year,
            toDate.month,
            toDate.day,
          ).add(const Duration(days: 1))
        : DateTime.now().add(const Duration(days: 1));

    final entries = <PartyStatementEntry>[];

    if (party.isCustomer) {
      // Get sales invoices for customers
      final salesQuery = select(salesInvoices)
        ..where(
          (i) =>
              i.customerId.equals(partyId) &
              i.isDeleted.equals(false) &
              i.status.isNotIn(const ['voided', 'cancelled']) &
              i.invoiceDate.isBetween(Variable(from), Variable(to)),
        );
      if (branchId != null) {
        salesQuery.where((i) => i.warehouseId.isInQuery(
          selectOnly(warehouses)
            ..addColumns([warehouses.id])
            ..where(warehouses.branchId.equals(branchId) | warehouses.branchId.isNull())
        ));
      }
      salesQuery.orderBy([(i) => OrderingTerm.asc(i.invoiceDate)]);
      final sales = await salesQuery.get();

      for (final sale in sales) {
        // Spec 113 — sales returns (saleType='return') live in the SAME
        // table as regular sales. Pre-113 the loop labelled them all as
        // "فاتورة مبيعات" and put the amount in the DEBIT column, which
        // (a) lied about the document type and (b) increased the
        // customer's apparent debt instead of decreasing it. Now we
        // branch on `saleType` to flip the label and the column.
        final isReturn = sale.saleType == 'return';
        entries.add(
          PartyStatementEntry(
            date: sale.invoiceDate,
            description: isReturn ? 'مرتجع مبيعات' : 'فاتورة مبيعات',
            invoiceNumber: sale.invoiceNumber,
            entryType: isReturn ? 'sales_return' : 'invoice',
            debit: isReturn ? 0.0 : sale.total,
            credit: isReturn ? sale.total : 0.0,
            balance: 0.0, // Calculated on display
            referenceId: sale.id,
            referenceType: isReturn ? 'sales_return' : 'sales_invoice',
          ),
        );
      }
    }

    if (party.isSupplier) {
      // Get purchase invoices for suppliers
      final purchasesQuery = select(purchaseInvoices)
        ..where(
          (i) =>
              i.supplierId.equals(partyId) &
              i.isDeleted.equals(false) &
              i.status.isNotIn(const ['voided', 'cancelled']) &
              i.invoiceDate.isBetween(Variable(from), Variable(to)),
        );
      if (branchId != null) {
        purchasesQuery.where((i) => i.warehouseId.isInQuery(
          selectOnly(warehouses)
            ..addColumns([warehouses.id])
            ..where(warehouses.branchId.equals(branchId) | warehouses.branchId.isNull())
        ));
      }
      purchasesQuery.orderBy([(i) => OrderingTerm.asc(i.invoiceDate)]);
      final purchases = await purchasesQuery.get();

      for (final purchase in purchases) {
        String desc = 'فاتورة مشتريات';
        if (purchase.supplierInvoiceNumber != null && purchase.supplierInvoiceNumber!.isNotEmpty) {
          desc += ' - وثيقة المورد: ${purchase.supplierInvoiceNumber!}';
        }
        if (purchase.notes != null && purchase.notes!.isNotEmpty) {
          desc += ' - ملاحظات: ${purchase.notes!}';
        }
        entries.add(
          PartyStatementEntry(
            date: purchase.invoiceDate,
            description: desc,
            invoiceNumber: purchase.invoiceNumber,
            entryType: 'purchase',
            debit: 0.0,
            credit: purchase.total,
            balance: 0.0, // Calculated on display
            referenceId: purchase.id,
            referenceType: 'purchase_invoice',
          ),
        );
      }
    }

    // Get Safe Transactions (Payments/Receipts)
    final stQuery = select(safeTransactions).join([
      innerJoin(safes, safes.id.equalsExp(safeTransactions.safeId))
    ])..where(safeTransactions.partyId.equals(partyId) &
              safeTransactions.deletedAt.isNull() &
              safeTransactions.createdAt.isBetween(Variable(from), Variable(to)) &
              // 🔴 سندُ الشيك مستندٌ لا حركة — راجع [getPartyTransactions].
              safeTransactions.transactionType
                  .equals(kChequeVoucherTxnType)
                  .not());

    if (branchId != null) {
      stQuery.where(safes.branchId.equals(branchId) | safes.branchId.isNull());
    }

    final transactionRows = await stQuery.get();
    final transactions = transactionRows.map((row) => row.readTable(safeTransactions)).toList();

    for (final t in transactions) {
      // Spec 113 — safe-transaction rows generated by the return flow
      // (sales_mutations_dao._recordSalesReceipt creates a PV/PMT for the
      // "paid" leg of a return) duplicate the return invoice row already
      // emitted by the salesInvoices loop above. Skip them to keep the
      // statement showing exactly one entry per economic event.
      //
      // Also skip the 'memo' AR-adjustment rows for the same reason:
      // pre-113 they were the only visible signal that the return
      // happened (because the invoice row was mis-labelled); now the
      // invoice row carries the information directly.
      // Spec 136 ISS-14 — purchase returns have NO row in purchaseInvoices
      // (unlike sales returns, which live in salesInvoices as saleType='return'
      // and are emitted by the loop above). They exist ONLY as a
      // 'purchase_return_balance' memo in safe_transactions. The Spec 113 skip
      // below assumed every return has an invoice-table row carrying it — true
      // for sales, false for purchases — so the memo was dropped and the
      // supplier statement never showed the return. Emit it here as a DEBIT
      // (reduces the AP credit balance), matching the opening-balance calc that
      // subtracts these same memos. The cash-refund leg ('purchase_return',
      // type 'receipt') stays skipped: it offsets cash already paid, not AP, so
      // surfacing it would double-reduce the supplier balance.
      if (party.isSupplier && t.category == 'purchase_return_balance') {
        entries.add(
          PartyStatementEntry(
            date: t.createdAt,
            description: t.description ?? 'مرتجع مشتريات',
            invoiceNumber: t.voucherNumber,
            entryType: t.transactionType, // 'memo'
            debit: t.amount,
            credit: 0.0,
            balance: 0.0,
            referenceId: t.id,
            referenceType: 'safe_transaction',
          ),
        );
        continue;
      }

      // Spec 136 ISS-26 — the customer-side mirror of the ISS-14 fix above.
      // A sales return created from the returns dialog
      // (returns_repository_impl) exists ONLY as a 'sales_return_balance' memo
      // in safe_transactions — it writes NO sales_invoices row (verified: only
      // the POS quick-return path writes saleType='return', which the sales
      // loop above already shows). The Spec 113 skip below dropped this memo,
      // so dialog-path sales returns never appeared in the customer statement
      // even though the memo carries the AR reduction (and the opening-balance
      // calc already subtracts it). Emit it as a CREDIT (reduces the
      // customer's AR debit balance). No double-count: the two return paths
      // are disjoint (memo XOR invoice row). referenceType is
      // 'sales_return_balance' so party_statement_dialogs renders the proper
      // label + print template.
      if (party.isCustomer && t.category == 'sales_return_balance') {
        entries.add(
          PartyStatementEntry(
            date: t.createdAt,
            description: t.description ?? 'مرتجع مبيعات',
            invoiceNumber: t.voucherNumber,
            entryType: t.transactionType, // 'memo'
            debit: 0.0,
            credit: t.amount,
            balance: 0.0,
            referenceId: t.id,
            referenceType: 'sales_return_balance',
          ),
        );
        continue;
      }

      if (t.category == 'return' ||
          t.category == 'sales_return' ||
          t.category == 'sales_return_balance' ||
          t.category == 'purchase_return' ||
          t.category == 'purchase_return_balance') {
        continue;
      }

      double debit = 0;
      double credit = 0;
      // E2 — سندُ التحويل المحاسبيّ يُقرأ في الكشف كنظيره النقديّ.
      final txType = switch (t.transactionType) {
        'transfer_receipt' => 'receipt',
        'transfer_payment' => 'payment',
        final other => other,
      };

      if (party.isCustomer) {
        if (txType == 'receipt') {
          credit = t.amount;
        } else if (txType == 'payment') {
          credit = t.amount;
        }
      } else if (party.isSupplier) {
        if (txType == 'payment') {
          debit = t.amount;
        } else if (txType == 'receipt') {
          debit = t.amount;
        }
      }

      entries.add(
        PartyStatementEntry(
          date: t.createdAt,
          description: t.description ?? (txType == 'receipt' ? 'سند قبض' : t.transactionType == 'memo' ? 'تسوية رصيد' : 'سند صرف'),
          invoiceNumber: t.voucherNumber,
          entryType: txType,
          debit: debit,
          credit: credit,
          balance: 0.0,
          referenceId: t.id,
          referenceType: 'safe_transaction',
        ),
      );

      // Settlement discount (خصم معجّل دفع) — createPaymentVoucher /
      // createReceiptVoucher reduce parties.balance by (amount + discount) but
      // only `amount` is the cash that moved. Pre-fix the statement rendered
      // debit/credit = amount only and dropped the discount entirely, so the
      // كشف حساب kept a phantom residual equal to the discount that never
      // matched the party-card balance. Emit the discount as its own line so
      // the running balance reconciles with parties.balance. Direction mirrors
      // the voucher: supplier payment → خصم مكتسب (debit, cuts our AP);
      // customer receipt → خصم مسموح به (credit, cuts their AR).
      if (t.discount > 0) {
        double discountDebit = 0;
        double discountCredit = 0;
        if (party.isSupplier && txType == 'payment') {
          discountDebit = t.discount;
        } else if (party.isCustomer && txType == 'receipt') {
          discountCredit = t.discount;
        }
        if (discountDebit > 0 || discountCredit > 0) {
          entries.add(
            PartyStatementEntry(
              date: t.createdAt,
              description: party.isSupplier ? 'خصم مكتسب (تسوية)' : 'خصم مسموح به (تسوية)',
              invoiceNumber: t.voucherNumber,
              entryType: 'discount',
              debit: discountDebit,
              credit: discountCredit,
              balance: 0.0,
              referenceId: t.id,
              referenceType: 'safe_transaction',
            ),
          );
        }
      }
    }

    double chequeOpeningBalance = 0;

    void addCommercialPaperStatementEntry({
      required CommercialPaperData paper,
      required DateTime date,
      required String status,
    }) {
      double debit = 0;
      double credit = 0;
      String? description;

      if (party.isCustomer && paper.direction == 'received') {
        if (status == 'pending') {
          credit = paper.amount;
          description = 'استلام شيك رقم ${paper.paperNumber}';
        } else if (status == 'bounced') {
          debit = paper.amount;
          description = 'ارتجاع شيك رقم ${paper.paperNumber}';
        }
      }

      if (party.isSupplier && paper.direction == 'issued') {
        if (status == 'pending') {
          debit = paper.amount;
          description = 'إصدار شيك رقم ${paper.paperNumber}';
        } else if (status == 'bounced') {
          credit = paper.amount;
          description = 'ارتجاع شيك صادر رقم ${paper.paperNumber}';
        }
      }

      if (description == null) return;

      if (date.isBefore(from)) {
        chequeOpeningBalance += party.isCustomer
            ? debit - credit
            : credit - debit;
        return;
      }

      if (!date.isBefore(to)) return;

      entries.add(
        PartyStatementEntry(
          date: date,
          description: description,
          invoiceNumber: paper.paperNumber,
          entryType: 'commercial_paper',
          debit: debit,
          credit: credit,
          balance: 0.0,
          referenceId: paper.id,
          referenceType: 'commercial_paper',
        ),
      );
    }

    // Spec 101: commercial-paper rows are not safe transactions. Add only
    // party-balance transitions so supplier/customer statements match the
    // cheque side-effects applied in commercial_papers_dao.
    final paperRows = await (select(commercialPapers)
          ..where((p) => p.partyId.equals(partyId))
          ..where((p) => p.createdAt.isSmallerThanValue(to)))
        .get();
    for (final paper in paperRows) {
      addCommercialPaperStatementEntry(
        paper: paper,
        date: paper.createdAt,
        status: 'pending',
      );

      final histories = await (select(paperStatusHistory)
            ..where((h) => h.paperId.equals(paper.id))
            ..where((h) => h.changedAt.isSmallerThanValue(to))
            ..orderBy([(h) => OrderingTerm.asc(h.changedAt)]))
          .get();
      for (final history in histories) {
        addCommercialPaperStatementEntry(
          paper: paper,
          date: history.changedAt,
          status: history.toStatus,
        );
      }
    }

    // Sort by date
    entries.sort((a, b) => a.date.compareTo(b.date));

    // Calculate running balance
    // For customers: Balance = Opening + Sum(Debit) - Sum(Credit) 
    // For suppliers: Balance = Opening + Sum(Credit) - Sum(Debit) (Assuming normal Credit balance)
    
    // As a simplification, we could calculate the Opening Balance from before 'from'
    // But assuming the frontend expects the exact window's running offset or total:
    // Actually, in many cases, we just want the running balance of the *visible* rows or a cumulative one.
    // Let's get the opening balance before the 'from' date.
    
    double openingBalance = 0;

    // ⚠️ **شرطُ الفرع مكتوبٌ مرّةً واحدةً لكلّ جدول — وبـ`IS NULL`.**
    //
    // 🔴 كان مكرّراً ستَّ مرّاتٍ بيدها، وكان يفترق عن صفوف الفترة أعلاه في
    // كلمةٍ واحدة: النافذةُ تقول
    // `warehouses.branchId.equals(b) | warehouses.branchId.isNull()` وSQL
    // الافتتاحيّ كانت تقول `branch_id = ?` وحدَها. فمخزنٌ أو خزنةٌ **بلا فرع**
    // — وهي الحالةُ الافتراضيّةُ في تجهيزةٍ لم تُقسَّم فروعاً — تدخل الحركةَ
    // وتخرج من رصيد البداية، فيبدأ الكشفُ من رقمٍ أصغرَ ممّا يقابل حركتَه
    // ويظلّ الختاميُّ ناقصاً إلى آخر سطر. ولا فحصَ اتّزانٍ يمسكه: الكشفُ
    // متّسقٌ مع نفسه، والخطأُ في نقطة البدء.
    //
    // و`branch_id IS NULL` تعني «غيرُ مخصَّصٍ لفرع» لا «فرعٌ آخر» — فالمشتركُ
    // يخصّ الجميعَ ويُقرأ من كلّ فرع.
    final branchOfWarehouse = branchId == null
        ? ''
        : 'AND (warehouse_id IN (SELECT id FROM warehouses '
            'WHERE branch_id = ? OR branch_id IS NULL))';
    final branchOfJoinedSafe =
        branchId == null ? '' : 'AND (s.branch_id = ? OR s.branch_id IS NULL)';
    final branchOfMemoSafe = branchId == null
        ? ''
        : 'AND (t.safe_id IN (SELECT id FROM safes '
            'WHERE branch_id = ? OR branch_id IS NULL))';

    // ═══ الافتتاحيُّ **مرآةُ النافذة** ═══════════════════════════════════
    //
    // 🔴 كان `if (isCustomer) … else …`، وصفوفُ الفترة أعلاه **شرطان
    // مستقلّان** (`if (isCustomer)` ثمّ `if (isSupplier)`). فطرفٌ بالصفتين —
    // مورّدٌ نشتري منه ونبيع له، وهي حالةٌ شائعة — تظهر فواتيرُ شرائه داخلَ
    // الفترة ولا تدخل رصيدَ بدايتها، فيبدأ كشفُه من رقمٍ يُغفل مشترياته
    // السابقةَ كلَّها.
    //
    // والاتّجاهُ يقرّره `isCustomer` وحدَه في حلقة الرصيد الجاري
    // (`runningBalance += debit − credit`)، فالشقُّ المورّديُّ لطرفٍ بالصفتين
    // يُحسَب **باتّجاه العميل**: الشراءُ دائنٌ ⇒ سالب، وتسويةُ مردود الشراء
    // مدينةٌ ⇒ موجبة. وطرفٌ مورّدٌ خالصٌ يبقى على معادلته كما هي حرفاً بحرف.
    double customerSide = 0;
    double supplierSide = 0;

    if (party.isCustomer) {
      // 🔴 **والمبيعاتُ موقَّعةٌ بنوعها.** مرتجعُ نقطةِ البيع صفٌّ في
      // `sales_invoices` بـ`sale_type = 'return'` (‏Spec 113)، وصفُّ الفترة
      // يضعه **دائناً**؛ و`SUM(total)` بلا شرطٍ كانت تضعه مديناً — فينحرف
      // الافتتاحيُّ بضعف قيمة المرتجع.
      final pastSales = await customSelect(
        "SELECT COALESCE(SUM(CASE WHEN sale_type = 'return' THEN -total ELSE total END), 0) as amt FROM sales_invoices WHERE customer_id = ? AND is_deleted = ${sqlBool(false)} AND status NOT IN ('voided', 'cancelled') AND invoice_date < ? $branchOfWarehouse",
        variables: [Variable(partyId), dateVar(from), if (branchId != null) Variable(branchId)],
      ).getSingle();
      // Include the settlement discount: a receipt voucher reduces the
      // customer's AR by (amount + discount), so the opening balance must too
      // — matching the discount statement line emitted in the window above.
      final pastReceipts = await customSelect(
        "SELECT COALESCE(SUM(t.amount + COALESCE(t.discount, 0)), 0) as amt FROM safe_transactions t JOIN safes s ON t.safe_id = s.id WHERE t.party_id = ? AND t.deleted_at IS NULL AND t.transaction_type IN ('receipt', 'transfer_receipt') AND t.created_at < ? $branchOfJoinedSafe",
        variables: [Variable(partyId), dateVar(from), if (branchId != null) Variable(branchId)],
      ).getSingle();
      final pastPayments = await customSelect(
        "SELECT COALESCE(SUM(t.amount), 0) as amt FROM safe_transactions t JOIN safes s ON t.safe_id = s.id WHERE t.party_id = ? AND t.deleted_at IS NULL AND t.transaction_type IN ('payment', 'transfer_payment') AND t.created_at < ? $branchOfJoinedSafe",
        variables: [Variable(partyId), dateVar(from), if (branchId != null) Variable(branchId)],
      ).getSingle();

      final pastSalesReturnMemos = await customSelect(
        "SELECT COALESCE(SUM(t.amount), 0) as amt FROM safe_transactions t WHERE t.party_id = ? AND t.deleted_at IS NULL AND t.transaction_type = 'memo' AND t.category = 'sales_return_balance' AND t.created_at < ? $branchOfMemoSafe",
        variables: [Variable(partyId), dateVar(from), if (branchId != null) Variable(branchId)],
      ).getSingle();
      // Customer balance = sales − receipts − cash refunds − balance adjustments from returns
  // ignore: dead_code
      customerSide = (pastSales.read<double>('amt') ?? 0)
                   - (pastReceipts.read<double>('amt') ?? 0)
                   - (pastPayments.read<double>('amt') ?? 0)
                   - (pastSalesReturnMemos.read<double>('amt') ?? 0);
    }

    if (party.isSupplier) {
      final pastPurchases = await customSelect(
        'SELECT COALESCE(SUM(total), 0) as amt FROM purchase_invoices WHERE supplier_id = ? AND is_deleted = ${sqlBool(false)} AND status NOT IN (\'voided\', \'cancelled\') AND invoice_date < ? $branchOfWarehouse',
        variables: [Variable(partyId), dateVar(from), if (branchId != null) Variable(branchId)],
      ).getSingle();
      final pastPurchaseReturnMemos = await customSelect(
        "SELECT COALESCE(SUM(t.amount), 0) as amt FROM safe_transactions t WHERE t.party_id = ? AND t.deleted_at IS NULL AND t.transaction_type = 'memo' AND t.category = 'purchase_return_balance' AND t.created_at < ? $branchOfMemoSafe",
        variables: [Variable(partyId), dateVar(from), if (branchId != null) Variable(branchId)],
      ).getSingle();

      if (party.isCustomer) {
        // ⚠️ **وحركةُ الخزنة لا تُحسَب هنا ثانيةً**: صفُّ الفترة يفرّع
        //    `if (isCustomer) … else if (isSupplier)` فيقرأ سندَ القبض
        //    والصرف **مرّةً واحدةً** باتّجاه العميل. وجمعُ الشقَّين هنا كان
        //    سيطرح السندَ مرّتين.
  // ignore: dead_code
        supplierSide = -(pastPurchases.read<double>('amt') ?? 0)
                     + (pastPurchaseReturnMemos.read<double>('amt') ?? 0);
      } else {
        // Include the settlement discount: a payment voucher reduces our AP to
        // the supplier by (amount + discount), so the opening balance must too
        // — matching the discount statement line emitted in the window above.
        final pastPayments = await customSelect(
          "SELECT COALESCE(SUM(t.amount + COALESCE(t.discount, 0)), 0) as amt FROM safe_transactions t JOIN safes s ON t.safe_id = s.id WHERE t.party_id = ? AND t.deleted_at IS NULL AND t.transaction_type IN ('payment', 'transfer_payment') AND t.created_at < ? $branchOfJoinedSafe",
          variables: [Variable(partyId), dateVar(from), if (branchId != null) Variable(branchId)],
        ).getSingle();
        final pastReceipts = await customSelect(
          "SELECT COALESCE(SUM(t.amount), 0) as amt FROM safe_transactions t JOIN safes s ON t.safe_id = s.id WHERE t.party_id = ? AND t.deleted_at IS NULL AND t.transaction_type IN ('receipt', 'transfer_receipt') AND t.created_at < ? $branchOfJoinedSafe",
          variables: [Variable(partyId), dateVar(from), if (branchId != null) Variable(branchId)],
        ).getSingle();
        // Supplier balance = purchases − payments − cash receipts from supplier − balance adjustments from returns
  // ignore: dead_code
        supplierSide = (pastPurchases.read<double>('amt') ?? 0)
                     - (pastPayments.read<double>('amt') ?? 0)
                     - (pastReceipts.read<double>('amt') ?? 0)
                     - (pastPurchaseReturnMemos.read<double>('amt') ?? 0);
      }
    }

    openingBalance = customerSide + supplierSide + chequeOpeningBalance;

    if (openingBalance != 0) {
      entries.insert(0, PartyStatementEntry(
        date: from,
        description: 'رصيد افتتاحي (سابق للفترة)',
        entryType: 'opening',
        debit: party.isCustomer && openingBalance > 0 ? openingBalance : (party.isSupplier && openingBalance < 0 ? openingBalance.abs() : 0),
        credit: party.isSupplier && openingBalance > 0 ? openingBalance : (party.isCustomer && openingBalance < 0 ? openingBalance.abs() : 0),
        balance: openingBalance, // Will be replaced by running balance loop
      ));
    }

    double runningBalance = openingBalance;
    final List<PartyStatementEntry> populatedEntries = [];
    
    for (int i = 0; i < entries.length; i++) {
      final e = entries[i];
      if (e.entryType == 'opening') {
         populatedEntries.add(e);
         continue; // balance already set to openingBalance above, runningBalance initialized
      }
      
      if (party.isCustomer) {
        runningBalance += e.debit - e.credit;
      } else {
        runningBalance += e.credit - e.debit; // supplier balance is Credit normal
      }
      
      populatedEntries.add(PartyStatementEntry(
        date: e.date,
        description: e.description,
        invoiceNumber: e.invoiceNumber,
        entryType: e.entryType,
        debit: e.debit,
        credit: e.credit,
        balance: runningBalance,
        referenceId: e.referenceId,
        referenceType: e.referenceType,
      ));
    }

    // Spec 136 field diagnostic — pin why receipts / sales-returns may not
    // surface in the customer statement on the mirror. Shows whether the rows
    // EXIST locally (creation/sync issue) vs are filtered out (display issue).
    try {
      final stByTypeCat = <String, int>{};
      for (final t in transactions) {
        final k = '${t.transactionType}/${t.category}';
        stByTypeCat[k] = (stByTypeCat[k] ?? 0) + 1;
      }
      final entryTypes = <String, int>{};
      for (final e in populatedEntries) {
        entryTypes[e.entryType] = (entryTypes[e.entryType] ?? 0) + 1;
      }
      unawaited(DiagnosticLogger.log(
          'PARTY-STATEMENT',
          'partyId=$partyId isCustomer=${party.isCustomer} '
          'safeTxnRows=${transactions.length} byTypeCat=$stByTypeCat '
          'commercialPapers=${paperRows.length} '
          'entries=${populatedEntries.length} entryTypes=$entryTypes'));
    } catch (e) {
      // Spec 136 item 6 — don't let the diagnostic hook fail silently. Stays
      // non-fatal (statement rendering must not break on a logging glitch),
      // but a swallowed error is now visible in the run log.
      debugPrint('[PartyDao] PARTY-STATEMENT diagnostic failed (non-fatal): $e');
    }

    return populatedEntries;
  }

  /// Get party transactions for statement
  Future<List<SafeTransactionData>> getPartyTransactions(int partyId) async {
    return (select(safeTransactions)
          ..where((t) =>
              t.partyId.equals(partyId) &
              // 🔴 سندُ الشيك مستندٌ لا حركة: ماله يتحرّك حين تُحصَّل الورقةُ
              //    ويكتبه محرّكُ الأوراق التجاريّة. وعدُّه هنا يُظهر دفعةً
              //    ثانيةً بجوار قيد الترحيل الآليّ — عينُ ازدواج مواصفة ١٣٣.
              t.transactionType.equals(kChequeVoucherTxnType).not())
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }
}
