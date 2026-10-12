part of '../journal_entry_factory.dart';
// ignore_for_file: avoid_dynamic_calls

extension JournalEntryFactorySalesReturnCancel on JournalEntryFactory {
  // ═══════════════════════════════════════════════════════════════════════
  // REVERSAL JE
  // ═══════════════════════════════════════════════════════════════════════

  /// Reverse accounting entries when a return is cancelled
  Future<void> reverseReturnAccountingEntry({
    required int invoiceId,
    required String invNumber,
  }) async {
    await _accountingRepo.reverseReturnAccountingEntry(
      invoiceId: invoiceId,
      invNumber: invNumber,
    );
  }

  /// Generically reverse any accounting transaction
  Future<void> reverseTransaction({
    required String referenceType,
    required int referenceId,
    required String descriptionPrefix,
    required String newReferenceType,
  }) async {
    await _accountingRepo.reverseTransaction(
      referenceType: referenceType,
      referenceId: referenceId,
      descriptionPrefix: descriptionPrefix,
      newReferenceType: newReferenceType,
    );
  }

  /// F-02 fix (MJE-1 / MJE-2): reverse a single journal entry by its own
  /// primary key — see [reverseTransaction] above for the bug this avoids.
  /// Returns the new reversal JE id, or 0 if nothing was reversed.
  Future<int> reverseJournalEntryById({
    required int entryId,
    String? descriptionPrefix,
  }) {
    return _accountingRepo.reverseJournalEntryById(
      entryId: entryId,
      descriptionPrefix: descriptionPrefix,
    );
  }

  /// Cancel a return - reverse all operations (Stock, Safe, Accounting, AR)
  Future<void> cancelSalesReturn({
    required SalesInvoiceData invoice,
    required int userId,
    required String userName,
  }) async {
    await _accountingRepo.runInTransaction(() async {
      final linkedReturns =
          await _accountingRepo.getLinkedSalesReturnDocuments(invoice);
      final SalesInvoiceData event;
      if (linkedReturns.isNotEmpty) {
        event = linkedReturns.reduce(
          (latest, candidate) =>
              candidate.id > latest.id ? candidate : latest,
        );
      } else if (invoice.status == 'partial_return' ||
          invoice.status == 'returned') {
        event = invoice;
      } else {
        throw StateError('لا يوجد مرتجع حي لإلغائه.');
      }
      final eventId = event.id;

      // 1. Reverse Stock
      //
      // ⚠️ مسارا المرتجع يكتبان مرجعَين مختلفَين لنفس الحركة:
      //   * `ReturnsRepositoryImpl.processSalesReturn` (شاشةُ مرتجع
      //     المبيعات ووضعُ المرتجع في نقطة البيع — المسارُ الرئيسيّ) يكتب
      //     `'sales_return'`. (كان التعليقُ يسمّي `ProcessSalesReturnUseCase`
      //     وهي كانت كوداً ميّتاً بلا مُنادٍ — حُذفت 2026-09-02؛ والمرجعُ
      //     المكتوبُ واحدٌ في المسارَين فالإصلاحُ أدناه صحيحٌ على الحيّ.)
      //   * المرتجعُ السريع من البيع السريع (`sales_mutations_dao`) يكتب
      //     `'sales_invoice'`.
      // وكان هذا يستعلم بـ`'sales_invoice'` وحدَه، بينما الخطوتان ٢ و٣ تحته
      // تستعلمان بـ`'sales_return'`. فعلى المسار الرئيسيِّ لم تدر الحلقةُ
      // إطلاقاً: القيدُ ينعكس والنقديةُ ترجع ورصيدُ العميل يُعدَّل،
      // **والبضاعةُ تفضل في المخزون**. مقيس: انحرافُ ٥ وحداتٍ لكلّ إلغاء.
      final returnMovements = <StockMovementData>[
        ...await _inventoryRepo.getStockMovementsByReference(
          'sales_return',
          eventId,
        ),
        ...await _inventoryRepo.getStockMovementsByReference(
          'sales_invoice',
          eventId,
        ),
      ];

      for (final movement in returnMovements) {
        if (movement.movementType == 'return') {
          // عكسٌ حقيقيٌّ عبر `adjustStock` لا تعديلٌ يدويّ: التعديلُ اليدويُّ
          // كان يمسّ `products.current_stock` وحدَه ويحذف صفَّ الحركة، فلا
          // يلمس `inventory_balances` إطلاقاً — ينفصل رصيدُ المخزن عن رصيد
          // الصنف، ويُمحى الدليلُ على أن المرتجع حصل أصلاً.
          await _inventoryRepo.adjustStock(
            productId: movement.productId,
            warehouseId: movement.warehouseId,
            quantity: -movement.quantity,
            type: 'return_cancel',
            referenceType: 'return_cancel',
            referenceId: eventId,
            unitCost: movement.unitCost,
            notes: 'إلغاء مرتجع فاتورة ${event.invoiceNumber}',
          );
        }
      }

      // 2. Reverse refund safe transactions
      final returnSafeTransactions = await _treasuryRepo
          .getTransactionsByReference('sales_return', eventId);

      for (final origTxn in returnSafeTransactions) {
        if (origTxn.category == 'sales_return') {
          final safe = await _treasuryRepo.getSafeByIdRaw(origTxn.safeId);
          if (safe != null) {
            // ⚠️ لا كتابةَ رصيدٍ هنا. `createSafeTransaction('receipt')`
            // يزيد الرصيدَ بنفسه (‏`treasury_dao.dart:1464-1469`)، فكتابةُ
            // `newBalance` قبله تُضيف المبلغَ مرّتين ⇒ نقديةٌ تُخلق من العدم.
            //
            // وكان العطبُ **مستوراً**: مسارُ المرتجع كان يخصم مرّتين أيضاً،
            // فالغلطان يتعادلان ما دام الإلغاءُ يتبع المرتجع. أُصلح المرتجعُ
            // في `returns_repository_impl.dart` فظهر هذا وحدَه.
            //
            // و`newBalance` يبقى لقطةً لـ`balanceAfter`.
            final newBalance = safe.balance + origTxn.amount;
            await _treasuryRepo.createSafeTransaction(
              voucherNumber:
                  'CAN-RET${DateTime.now().year}${eventId.toString().padLeft(6, '0')}',
              safeId: safe.id,
              transactionType: 'receipt',
              category: 'return_cancel',
              amount: origTxn.amount,
              balanceAfter: newBalance,
              referenceType: 'return_cancel',
              referenceId: eventId,
              description: 'إلغاء مرتجع فاتورة ${event.invoiceNumber}',
              userId: userId,
            );
          }
        }
      }

      // 3. Reverse AR Balance — resolve via purpose to honour the
      // user's mapping (defaults to '1121' ذمم عملاء محليون). The
      // earlier hardcoded '1201' code was never seeded.
      if (invoice.customerId != null) {
        final arAcc = await _accountingRepo.getAccountByPurpose('receivables');
        if (arAcc != null) {
          final entries = await _accountingRepo.getJournalEntriesByReference(
            'sales_return',
            eventId,
          );

          for (final entry in entries) {
            final lines = await _accountingRepo
                .getJournalEntryLinesWithAccounts(entry.id);
            for (final line in lines) {
              final accountCode = line['account_code'] as String?;
              if (accountCode != null &&
                  accountCode.startsWith(arAcc.code) &&
                  (line['credit'] ?? 0) > 0) {
                await _partiesRepo.adjustPartyBalance(
                  invoice.customerId!,
                  (line['credit'] as num).toDouble(),
                );
              }
            }
          }
        }
      }

      // 4. Reverse Journal Entries
      await reverseReturnAccountingEntry(
        invoiceId: eventId,
        invNumber: event.invoiceNumber,
      );

      if (linkedReturns.isNotEmpty) {
        await _accountingRepo.voidSalesReturnDocument(eventId, userId);
      }
      final remainingReturns =
          await _accountingRepo.getLinkedSalesReturnDocuments(invoice);
      // A linked return leaves the original partially returned while others live.
      await _accountingRepo.updateEntityStatus(
        'sales_invoices',
        invoice.id,
        remainingReturns.isEmpty ? 'completed' : 'partial_return',
      );

      // 6. Log Activity
      await _auditRepo.logActivity(
        userId: userId,
        userName: userName,
        action: 'cancel_return',
        entityType: 'invoice',
        entityId: invoice.id,
        description: 'إلغاء مرتجع فاتورة ${invoice.invoiceNumber}',
      );
    });
  }


}
