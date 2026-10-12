// =======================================================================
// SALES ACTIONS DAO
// Extracted from sales_mutations_dao.dart — PIR Phase 3 Batch 1
// Specialized actions: Voiding, hard deletes, and validation helpers
// =======================================================================

part of '../database.dart';

/// A read-only finding for a voided invoice that still has a live return.
class VoidedAfterReturnReportRow {
  const VoidedAfterReturnReportRow({
    required this.invoiceId,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.total,
    required this.partyName,
    required this.originalQuantity,
    required this.returnedQuantity,
    required this.returnedValue,
    required this.imbalanceIndicators,
  });

  final int invoiceId;
  final String invoiceNumber;
  final DateTime invoiceDate;
  final double total;
  final String? partyName;
  final double originalQuantity;
  final double returnedQuantity;
  final double? returnedValue;
  final List<String> imbalanceIndicators;
}

/// Extension for specialized Sales Invoice actions (void, delete, etc.)
extension SalesActionsDao on AppDatabase {
  /// Finds historical voids whose return evidence is still active.
  Future<List<VoidedAfterReturnReportRow>> voidedAfterReturnReport() async {
    final voided =
        await (select(salesInvoices)..where(
              (invoice) =>
                  invoice.status.equals('voided') &
                  invoice.saleType.isNotIn(const ['return']),
            ))
            .get();
    final report = <VoidedAfterReturnReportRow>[];
    for (final invoice in voided) {
      final linked = await _linkedReturnTotals(invoice);
      final movements = await _returnMovementTotals(invoice.id);
      if (!linked.hasEvidence && !movements.hasEvidence) continue;

      final originalQuantity = (await getSalesInvoiceItems(
        invoice.id,
      )).fold<double>(0, (sum, item) => sum + item.quantity);
      final returnedQuantity = linked.quantity > 0
          ? linked.quantity
          : movements.quantity;
      final returnedValue = linked.value > 0 ? linked.value : movements.value;
      final indicators = <String>[
        'الإلغاء أعاد كامل كمية البيع فوق المرتجع السابق',
      ];
      if (returnedQuantity > originalQuantity + 0.005) {
        indicators.add('كمية المرتجع أكبر من كمية البيع الأصلية');
      }
      if (returnedValue > invoice.total + 0.005) {
        indicators.add('قيمة المرتجع أكبر من إجمالي الفاتورة');
      }
      report.add(
        VoidedAfterReturnReportRow(
          invoiceId: invoice.id,
          invoiceNumber: invoice.invoiceNumber,
          invoiceDate: invoice.invoiceDate,
          total: invoice.total,
          partyName: invoice.customerId == null
              ? null
              : (await getPartyById(invoice.customerId!))?.name,
          originalQuantity: originalQuantity,
          returnedQuantity: returnedQuantity,
          returnedValue: returnedValue > 0 ? returnedValue : null,
          imbalanceIndicators: indicators,
        ),
      );
    }
    return report;
  }

  Future<({double quantity, double value, bool hasEvidence})>
  _linkedReturnTotals(SalesInvoiceData invoice) async {
    const sql = '''
      SELECT COALESCE(SUM(r.total), 0) AS return_value,
             COALESCE((SELECT SUM(i.quantity) FROM sales_invoice_items i
               WHERE i.invoice_id IN (
                 SELECT r2.id FROM sales_invoices r2
                 WHERE r2.sale_type = 'return' AND r2.is_deleted = 0
                   AND (r2.notes = ? OR r2.notes LIKE ?
                     OR (? != '' AND r2.notes LIKE ?)))), 0) AS return_quantity
      FROM sales_invoices r
      WHERE r.sale_type = 'return' AND r.is_deleted = 0
        AND (r.notes = ? OR r.notes LIKE ?
          OR (? != '' AND r.notes LIKE ?))''';
    final note = localReturnLinkNote(invoice.id);
    final gid = invoice.globalId ?? '';
    final rows = await customSelect(
      sql,
      variables: [
        Variable.withString(note),
        Variable.withString('$note|%'),
        Variable.withString(gid),
        Variable.withString('%|gid:$gid%'),
        Variable.withString(note),
        Variable.withString('$note|%'),
        Variable.withString(gid),
        Variable.withString('%|gid:$gid%'),
      ],
      readsFrom: {salesInvoices, salesInvoiceItems},
    ).getSingle();
    final value = (rows.data['return_value'] as num).toDouble();
    final quantity = (rows.data['return_quantity'] as num).toDouble();
    return (
      quantity: quantity,
      value: value,
      hasEvidence: value > 0 || quantity > 0,
    );
  }

  Future<({double quantity, double value, bool hasEvidence})>
  _returnMovementTotals(int invoiceId) async {
    final movement = await customSelect(
      '''
      SELECT COALESCE(SUM(m.quantity), 0) AS return_quantity
      FROM stock_movements m
      WHERE m.movement_type = 'return'
        AND m.reference_type = 'sales_return'
        AND m.reference_id = ? AND m.deleted_at IS NULL
        AND NOT EXISTS (SELECT 1 FROM stock_movements c
          WHERE c.movement_type = 'return_cancel'
            AND c.reference_type = 'return_cancel'
            AND c.reference_id = m.reference_id
            AND c.deleted_at IS NULL)''',
      variables: [Variable.withInt(invoiceId)],
      readsFrom: {stockMovements},
    ).getSingle();
    final safe = await customSelect(
      '''
      SELECT COALESCE(SUM(t.amount), 0) AS return_value
      FROM safe_transactions t
      WHERE t.reference_type = 'sales_return' AND t.reference_id = ?
        AND t.category = 'sales_return' AND t.transaction_type = 'payment'
        AND t.deleted_at IS NULL
        AND NOT EXISTS (SELECT 1 FROM safe_transactions c
          WHERE c.reference_type = 'return_cancel'
            AND c.reference_id = t.reference_id
            AND c.category = 'return_cancel' AND c.deleted_at IS NULL)''',
      variables: [Variable.withInt(invoiceId)],
      readsFrom: {safeTransactions},
    ).getSingle();
    final quantity = (movement.data['return_quantity'] as num).toDouble();
    final value = (safe.data['return_value'] as num).toDouble();
    return (
      quantity: quantity,
      value: value,
      hasEvidence: quantity > 0 || value > 0,
    );
  }

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
      // عيب (2): لا إلغاء لمستند مرتجع ولا لفاتورة لها مرتجع حيّ — يرمي
      // SalesVoidBlockedException قبل أي كتابة. فاتورة بلا مرتجع: بلا تغيير.
      await assertSalesInvoiceVoidable(inv);

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

      // ── خاماتُ قائمة المكوّنات تعود كما تعود البضاعةُ التامّة ─────────────
      //
      // 🔴 الحلقةُ أعلاه تُعيد الصنفَ **المباع**. أمّا الصنفُ المركَّب
      // (‏وجبةٌ لها قائمةُ مكوّنات) فلا مخزونَ له غالباً — الذي خرج فعلاً هو
      // **خاماتُه**، يستنزفها `applyAutoDepleteForSale` عند البيع. والإبطالُ
      // كان لا يعيدها.
      //
      // والقيدُ المحاسبيُّ أدناه يعكس قيدَ البيع **سطراً بسطر**، وفيه رجلُ
      // تكلفةِ تلك الخامات. فالنتيجةُ اتّجاهٌ واحدٌ لا يتصفّى: حسابُ المخزون
      // في الأستاذ يعلو بقيمة الخامات، وكمّيّاتُها في المستودع تبقى ناقصةً
      // إلى الأبد ⇒ **التقييمُ ينخفض عن الأستاذ مع كلِّ إبطال**.
      //
      // ⚠️ **ولا قيدَ ثانياً هنا عمداً.** `reverseSaleConsumption` تُعيد
      // الكمّيّاتِ بـ`adjustStock(type: 'sale_auto_deplete_return')`، وهذا
      // النوعُ **خارجَ** `adjustmentAccountedTypes` في `inventory_dao`، فلا
      // ترحّل من نفسها. ولو رحّلت لكان الإبطالُ يُقيّد الخاماتِ مرّتين:
      // مرّةً بعكس قيد البيع ومرّةً بقيد التعديل — أي أن نقلب النقصَ إلى
      // ازدواج. (‏نفسُ المصيدةِ الموثَّقةِ في مسار المرتجع التالف.)
      //
      // والكسرُ ١٫٠ لكلِّ سطر: الإبطالُ إرجاعٌ كلّيٌّ بحكم تعريفه، بخلاف
      // المرتجع الجزئيّ الذي يمرّر نسبةَ كلِّ صنف.
      //
      // و`salesReturnId` هنا **مُعرِّفُ الفاتورة نفسِها** لا مستندَ مرتجع:
      // الإبطالُ لا يُنشئ مستنداً، والحقلُ وسمُ «عُكِس بماذا» الذي يجعل
      // إعادةَ الإبطال لا تُعيد الخاماتِ مرّتين.
      if (items.isNotEmpty) {
        await reverseSaleConsumption(
          saleInvoiceId: invoiceId,
          salesReturnId: invoiceId,
          itemReturnFractions: {for (final it in items) it.id: 1.0},
        );
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

  /// يرمي [SalesVoidBlockedException] إن لم يجز إلغاء [inv] (قراءة فقط).
  ///
  /// (أ) `saleType == 'return'`: حلقة المخزون في [voidSalesInvoice] تضيف الكمية
  /// دائماً، فإلغاء مستند مرتجع يضاعف المخزون.
  /// (ب) للأصل مرتجعٌ حيّ إن تحقق أيٌّ من:
  ///  • حالته `partial_return`/`returned` (الأثر الموحّد للشكلين، ويعيدها
  ///    `cancelSalesReturn` إلى `completed`)؛
  ///  • وجود صف `sale_type='return'` غير محذوف مربوط به بنص `notes`
  ///    (`localReturnLinkNote`): بالمعرّف العالمي أولاً ثم بالرقم لما قبل
  ///    صيغة gid — لأن تعديل الفاتورة قد يعيد الحالة `completed` فلا تكفي وحدها.
  /// ولا يُنظر في `safe_transactions` بنوع `sales_return`: `cancelSalesReturn`
  /// لا يحذفها (يضيف `return_cancel`)، فكانت ستمنع الإلغاء إلى الأبد.
  Future<void> assertSalesInvoiceVoidable(SalesInvoiceData inv) async {
    if (inv.saleType == 'return') {
      throw const SalesVoidBlockedException(kSalesVoidReturnDocMessage);
    }
    var hasReturn = inv.status == 'partial_return' || inv.status == 'returned';
    if (!hasReturn) {
      final gid = inv.globalId;
      final rows = await customSelect(
        "SELECT notes FROM sales_invoices WHERE sale_type = 'return' "
        'AND is_deleted = 0 AND notes LIKE ? '
        'AND (notes = ? OR notes LIKE ? OR notes LIKE ?)',
        variables: [
          Variable.withString('Return for invoice #%'),
          Variable.withString(localReturnLinkNote(inv.id)),
          Variable.withString('${localReturnLinkNote(inv.id)}|%'),
          Variable.withString('%|gid:${gid ?? ''}%'),
        ],
        readsFrom: {salesInvoices},
      ).get();
      for (final r in rows) {
        final note = r.data['notes'] as String?;
        final noteGid = returnOriginalGidFromNote(note);
        // الـgid حاسمٌ متى وُجد على الطرفين؛ والرقم احتياطٌ للصفوف الأقدم.
        final byGid = noteGid != null && gid != null && gid.isNotEmpty;
        if (byGid ? noteGid == gid : returnOriginalIdFromNote(note) == inv.id) {
          hasReturn = true;
          break;
        }
      }
    }
    if (hasReturn) {
      throw const SalesVoidBlockedException(kSalesVoidHasReturnMessage);
    }
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
