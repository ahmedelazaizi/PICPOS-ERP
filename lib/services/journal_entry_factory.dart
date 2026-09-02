// ignore_for_file: avoid_dynamic_calls
// ═══════════════════════════════════════════════════════════════════════════
// JOURNAL ENTRY FACTORY
// ═══════════════════════════════════════════════════════════════════════════
//
// ISS-08: Extracted from AccountingService.
// Responsible for generating all automatic journal entries.
//
// PIR FIXES:
//   ISS-01: Balance validation before JE creation
//   ISS-02: Account-not-found guard (throw instead of skip)
//   ISS-04: Purchase JE payment method routing
//   ISS-05: costPrice == 0 warning
//   ISS-10: Period lock enforcement
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import '../data/database/database.dart'; // Drift data classes (SalesInvoiceItem, etc.)
import '../domain/repositories/accounting_repository.dart';
import '../domain/repositories/parties_repository.dart';
import '../domain/repositories/i_products_repository.dart';
import '../domain/repositories/inventory_repository.dart';
import '../domain/repositories/treasury_repository.dart';
import '../domain/repositories/audit_repository_interface.dart';
import '../data/database/sync_interceptor.dart';
import '../core/logging/diagnostic_logger.dart';
// Spec 139 — single balance-tolerance source of truth. `show` avoids importing
// FinancialUtils' own UnbalancedJournalException (this file declares its own).
import '../core/utils/financial_utils.dart' show FinancialUtils;

/// Exception thrown when a required GL account mapping is missing.
class MissingAccountException implements Exception {
  final String purpose;
  MissingAccountException(this.purpose);
  @override
  String toString() => 'MissingAccountException: حساب "$purpose" غير موجود في ربط الحسابات. '
      'يرجى إعداد ربط الحسابات من الإعدادات > ربط الحسابات.';
}

/// Exception thrown when a JE has unbalanced debits/credits.
class UnbalancedJournalException implements Exception {
  final double totalDebit;
  final double totalCredit;
  final String context;
  UnbalancedJournalException(this.totalDebit, this.totalCredit, this.context);
  @override
  String toString() => 'UnbalancedJournalException: القيد غير متوازن '
      '($context) — مدين: $totalDebit، دائن: $totalCredit '
      '(فرق: ${(totalDebit - totalCredit).abs()})';
}

/// Exception thrown when trying to post to a locked accounting period.
class PeriodLockedException implements Exception {
  final DateTime date;
  PeriodLockedException(this.date);
  @override
  String toString() => 'PeriodLockedException: الفترة المحاسبية مغلقة للتاريخ $date';
}

/// PIR-014: Policy for handling items with zero cost price.
/// - [block]: Throw [ZeroCostException] — prevents JE creation.
/// - [warn]: Log warning and continue (original ISS-05 behavior).
/// - [allow]: Silently continue without any notification.
enum ZeroCostPolicy { block, warn, allow }

/// Exception thrown when a zero-cost item is encountered and policy is [ZeroCostPolicy.block].
class ZeroCostException implements Exception {
  final int productId;
  final String invoiceNumber;
  ZeroCostException(this.productId, this.invoiceNumber);
  @override
  String toString() => 'ZeroCostException: صنف $productId بتكلفة صفر في فاتورة #$invoiceNumber — '
      'سياسة النظام تمنع إنشاء قيد بتكلفة صفرية. '
      'يرجى تحديث تكلفة الصنف أو تغيير السياسة من الإعدادات.';
}

/// Factory for generating automatic accounting journal entries.
///
/// Handles sales, purchase, return, closing, landed-cost, and cycle-count
/// JE generation. See [AccountingValidator] for business rule validation.
class JournalEntryFactory {
  final IAccountingRepository _accountingRepo;
  final IPartiesRepository _partiesRepo;
  final ITreasuryRepository _treasuryRepo;
  final IProductRepository _productRepo;
  final InventoryRepository _inventoryRepo;
  final IAuditRepository _auditRepo;

  JournalEntryFactory(
    this._accountingRepo,
    this._partiesRepo,
    this._treasuryRepo,
    this._productRepo,
    this._inventoryRepo,
    this._auditRepo,
  );

  /// PIR-014: Current zero-cost policy. Defaults to [ZeroCostPolicy.warn].
  /// Can be overridden at runtime via [setZeroCostPolicy].
  ZeroCostPolicy _zeroCostPolicy = ZeroCostPolicy.warn;

  /// Set the zero-cost policy at runtime (loaded from settings).
  void setZeroCostPolicy(ZeroCostPolicy policy) {
    _zeroCostPolicy = policy;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PIR GUARDS — ISS-01, ISS-02, ISS-10
  // ═══════════════════════════════════════════════════════════════════════

  /// ISS-02: Require a mapped account — throws [MissingAccountException]
  /// if no account is mapped for [purpose].
  ///
  /// Cluster 023 / Issue 3 — uses the leaf-safe resolver. If the user's seed
  /// or admin-edited mapping points at a `view` (parent) account, walks down
  /// to the first leaf descendant rather than letting the JE validator reject
  /// the post with a cryptic "code 22" error. Misconfigured mappings surface
  /// as `ACCT-WARN` diagnostic lines instead of blocking the sale.
  Future<Account> _requireAccount(String purpose) async {
    final account = await _accountingRepo.getLeafAccountByPurpose(purpose);
    if (account == null) {
      throw MissingAccountException(purpose);
    }
    return account;
  }

  /// Resolve the AR/AP account for a party — prefers the party's dedicated
  /// sub-account (1121-XXXXX / 2111-XXXXX, seeded codes), falls back to
  /// the mapped control account when the party is null or has no linked
  /// sub-account.
  ///
  /// Why: before this helper every AR/AP journal line went straight to the
  /// control parent (1121/2111), which meant per-party balances never
  /// surfaced in the Chart of Accounts tree or the General Ledger drill-
  /// down even though `parties.balance` was correctly maintained. Posting
  /// to the sub-account keeps double-entry integrity AND lets
  /// `getAccountLedger`'s `LIKE 'parent%'` rollup aggregate children
  /// correctly under the parent row.
  Future<Account> _partyAccount({
    required int? partyId,
    required String fallbackPurpose,
  }) async {
    final fallback = await _requireAccount(fallbackPurpose);
    if (partyId == null) return fallback;
    final party = await _partiesRepo.getPartyById(partyId);
    if (party?.accountId == null) return fallback;
    // Cluster 023 / Issue 3 — leaf-safe lookup so a party whose `accountId`
    // happens to point at a parent (legacy data drift) does not cause the
    // JE validator to reject the post.
    final sub = await _accountingRepo.getLeafAccountById(party!.accountId!);
    return sub ?? fallback;
  }

  /// ISS-02 (soft): Get account by purpose, log warning if not found.
  /// Used for optional lines (delivery_revenue, overage accounts).
  Future<Account?> _optionalAccount(String purpose) async {
    // Cluster 023 / Issue 3 — leaf-safe lookup also for optional purposes.
    final account = await _accountingRepo.getLeafAccountByPurpose(purpose);
    if (account == null) {
      debugPrint('[JE-WARNING] حساب اختياري "$purpose" غير مربوط — سيتم تخطي السطر');
    }
    return account;
  }

  /// ISS-01: Validate that total debits == total credits within tolerance,
  /// then create the journal entry. Throws [UnbalancedJournalException] on mismatch.
  Future<void> _validateAndCreateEntry({
    required List<JournalLine> lines,
    required String description,
    required DateTime date,
    required String referenceType,
    int? referenceId,
    int? costCenterId,
    int? branchId,
    String context = '',
  }) async {
    if (lines.isEmpty) return;

    // ISS-01: Balance check.
    // Spec 139 (M1) — compare in INTEGER MINOR UNITS against the single
    // balance-tolerance source of truth, IDENTICALLY to the DAO writer
    // (accounting_dao_writes.dart), so the two gates agree at the exact cap
    // boundary (a float `> 0.01` compare rejects `0.01000…` that the integer
    // `<= 10` accepts). This pre-check only rejects real imbalances; the DAO
    // books any legitimate sub-cap residual to the rounding-difference account.
    final debitMinor =
        lines.fold<int>(0, (sum, l) => sum + FinancialUtils.toMinorUnits(l.debit));
    final creditMinor =
        lines.fold<int>(0, (sum, l) => sum + FinancialUtils.toMinorUnits(l.credit));

    if ((debitMinor - creditMinor).abs() >
        FinancialUtils.balanceToleranceMinorUnits) {
      throw UnbalancedJournalException(FinancialUtils.fromMinorUnits(debitMinor),
          FinancialUtils.fromMinorUnits(creditMinor), context);
    }

    // ISS-10: Period lock check
    await _checkPeriodLock(date);

    // createJournalEntry already handles client→server sync internally
    // (accounting_dao_writes.dart calls submitJournalEntry when isClientMode).
    // No second call needed here — that was causing double submission.
    await _accountingRepo.createJournalEntry(
      description: description,
      date: date,
      lines: lines,
      referenceType: referenceType,
      referenceId: referenceId,
      isAutoPosted: true,
      costCenterId: costCenterId,
      branchId: branchId,
    );
  }

  /// ISS-10: Check if the accounting period for [date] is locked.
  /// Throws [PeriodLockedException] if the period is closed.
  Future<void> _checkPeriodLock(DateTime date) async {
    try {
      final fiscalYear = await _accountingRepo.getFiscalYearByDate(date);
      if (fiscalYear != null && fiscalYear.isClosed) {
        throw PeriodLockedException(date);
      }
    } catch (e) {
      if (e is PeriodLockedException) rethrow;
      // If no fiscal year setup, allow posting (fresh install)
      debugPrint('[JE-INFO] لا توجد سنة مالية — السماح بالقيد');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SALES INVOICE JE
  // ═══════════════════════════════════════════════════════════════════════

  /// Generate automatic accounting entry for a sales invoice
  Future<void> generateSalesAccountingEntry({
    required int invoiceId,
    required String invNumber,
    required double tax,
    required double paid,
    required double remaining,

    /// فرقُ تقريب الإجماليّ (`total - roundedTotal`) — صفرٌ بلا تقريب.
    ///
    /// ⚠️ **هذا المصنعُ هو مسارُ القيد الفعليُّ لشاشة الكاشير**، لا
    /// `autoPostCashSale`: الأوركستريتر يمرّر `deferAutoPost: true` لكلِّ بيعةٍ
    /// standalone فيصدر القيدَ بنفسه من هنا. فسطرُ ٤٣١٩ في الـDAO وحدَه كان
    /// يخدم الخادمَ ولا يبلغ الكاشيرَ أبداً:
    ///   • المقرَّبُ **صعوداً** ⇒ المدينُ يفوق الدائنَ بالفرق ⇒
    ///     `UnbalancedJournalException` ⇒ **البيعةُ تُرفَض كاملةً** والنقدُ
    ///     في الدرج بلا فاتورة.
    ///   • والمقرَّبُ **هبوطاً** ⇒ `remaining > 0` فيُفتَح `Dr 1121` وهميٌّ
    ///     على حساب المراقبة بدل ٤٣١٩.
    /// (‏بلاغُ اختبارات الوظائف 2026-08-30 · R1/R2)
    double roundingAdjustment = 0,
    required String paymentMethod,
    required double deliveryFee,
    required List<SalesInvoiceItem> items,
    int? customerId, // NEW: route AR line to customer sub-account
    int? costCenterId,
    int? branchId,
    String? branchName, // NEW: used to identify branch in JE description
    String? regionName, // Phase 9: region label in JE description
    DateTime? invoiceDate,
    // Feature 009 / T017 — when non-null, the inventory-credit leg is
    // split per raw-material inventory account (aggregated by accountId);
    // when null OR empty, the legacy single-account path runs unchanged
    // (Constitution I — byte-identical JE shape for sales with no
    // auto-deplete BOM in scope).
    List<CogsLine>? cogsBreakdown,
    // Feature 009 follow-up — sales_invoice_items.id whose cost was already
    // accounted for by [cogsBreakdown] because `applyAutoDepleteForSale`
    // consumed raw materials for them. Their own `costPrice` must NOT be added
    // on top, or a tracked finished item with a book cost would be charged
    // twice (once as the finished good, once as its raw materials).
    Set<int>? autoDepletedItemIds,
  }) async {
    final List<JournalLine> journalLines = [];
    double cogsTotal = 0;

    for (final item in items) {
      // Cost comes from the consumed raw materials, not from this line.
      if (autoDepletedItemIds != null &&
          autoDepletedItemIds.contains(item.id)) {
        continue;
      }
      // ISS-05 + PIR-014: Zero cost policy enforcement
      if (item.costPrice <= 0) {
        switch (_zeroCostPolicy) {
          case ZeroCostPolicy.block:
            throw ZeroCostException(item.productId, invNumber);
          case ZeroCostPolicy.warn:
            debugPrint('[JE-WARNING] صنف ${item.productId} بتكلفة صفر في فاتورة #$invNumber — '
                'COGS لن يُسجل لهذا الصنف');
            break;
          case ZeroCostPolicy.allow:
            break; // Silent
        }
      }
      // SAL-1: costPrice is per BASE unit (WAC); quantity is in SALE units.
      // quantityInBase converts to physical base-unit qty for correct COGS.
      cogsTotal += (item.costPrice * item.quantity * item.quantityInBase);
    }

    // Cost of the raw materials `applyAutoDepleteForSale` actually took out of
    // stock. This is a SEPARATE source of cost from the invoice lines, not a
    // subdivision of them: a finished BOM item normally carries costPrice = 0
    // (no production order ever stamped a WAC on it), so `cogsTotal` alone is
    // blind to it. Both must be recognised.
    final bool hasBreakdown =
        cogsBreakdown != null && cogsBreakdown.isNotEmpty;
    final double breakdownTotal = hasBreakdown
        ? cogsBreakdown.fold<double>(0.0, (s, l) => s + l.totalCost)
        : 0.0;
    final double totalCogsDebit = cogsTotal + breakdownTotal;

    // 1. Debit side (Assets/Expenses)
    if (paid > 0) {
      // FIX: Find the exact safe accounts used by the initial safe transactions to debit correct safes!
      final cashSafeAccs = await _treasuryRepo.getSafeAccountsForReference('sales_invoice', invoiceId);
      
      if (cashSafeAccs.isNotEmpty) {
        // Distribute debit across actual safes used
        for (final entry in cashSafeAccs) {
          final accId = entry['accountId'] as int;
          final amount = entry['amount'] as double;
          final name = entry['safeName'] as String;
          journalLines.add(JournalLine(
            accountId: accId,
            debit: amount,
            description: 'تحصيل نقدية/بنك ($name) لفاتورة مبيعات #$invNumber',
            costCenterId: costCenterId,
          ));
        }
      } else {
        // Fallback if no safe transaction found
        final cashAcc = await _requireAccount(
          paymentMethod == 'cash' ? 'cash' : 'bank',
        );
        journalLines.add(JournalLine(
          accountId: cashAcc.id,
          debit: paid,
          description: 'تحصيل فاتورة مبيعات #$invNumber',
          costCenterId: costCenterId,
        ));
      }
    }
    if (remaining > 0) {
      final arAcc = await _partyAccount(
        partyId: customerId,
        fallbackPurpose: 'receivables',
      );
      journalLines.add(JournalLine(
        accountId: arAcc.id,
        debit: remaining,
        description: 'مبيعات آجلة فاتورة #$invNumber',
        costCenterId: costCenterId,
      ));
    }

    // COGS Debit — gated on the COMBINED cost. Gating on `cogsTotal` alone
    // dropped the whole COGS block for a BOM sale whose finished item has
    // costPrice = 0, leaving a Dr Cash / Cr Sales entry that balances (so no
    // validator fires) while the raw materials had really left stock.
    if (totalCogsDebit > 0.001) {
      final cogsAcc = await _requireAccount('cogs');
      journalLines.add(JournalLine(
        accountId: cogsAcc.id,
        debit: totalCogsDebit,
        description: 'تكلفة بوابة المبيعات فاتورة #$invNumber',
        costCenterId: costCenterId,
      ));
    }

    // 2. Credit side (Revenue & Liabilities/Assets reduction)
    //
    // Spec 136 (field 2026-06-08): derive the sales (net revenue) credit from
    // the invoice TOTAL (paid + remaining) minus the legs booked separately
    // (VAT + delivery, and only when their accounts are mapped). This makes the
    // JE balance BY CONSTRUCTION even when the caller's subtotal/discount/tax/
    // total don't reconcile — the field "خطأ في قيد اليومية: المدين لا يساوي
    // الدائن" where the diff was exactly the tax. For a consistent invoice this
    // equals the old `subtotal - discount`. A missing output_vat/delivery
    // account folds that amount into Sales instead of failing the sale.
    //
    // Spec 136 (item 2): this builder books NET revenue — the trade discount
    // is already embedded in `total` (paid + remaining), so there is NO
    // separate sales-discount contra leg. This DELIBERATELY differs from
    // accounting_autopost_dao, which books GROSS Sales + a sales-discount
    // debit; both net to the same revenue (IFRS recognises revenue net of
    // trade discount). Because the net is derived from the total, the former
    // `subtotal` / `discount` parameters were dead and have been removed.
    final salesAcc = await _requireAccount('sales');
    final vatAcc = tax > 0 ? await _optionalAccount('output_vat') : null;
    final deliveryAcc =
        deliveryFee > 0 ? await _optionalAccount('delivery_revenue') : null;
    final vatLeg = (tax > 0 && vatAcc != null) ? tax : 0.0;
    final deliveryLeg =
        (deliveryFee > 0 && deliveryAcc != null) ? deliveryFee : 0.0;
    // Spec 136 (review 2026-06-14): when output_vat / delivery_revenue is
    // unmapped on a taxable/delivery invoice the amount folds into Sales to keep
    // the JE balanced — which OVERSTATES revenue. The autopost path already
    // warns; this local builder folded SILENTLY. Surface it so the operator maps
    // the account (does NOT block posting — availability is intentional).
    if (tax > 0 && vatAcc == null) {
      await DiagnosticLogger.log('AUTOPOST-WARN',
          'فاتورة #$invNumber: حساب ضريبة المخرجات (output_vat) غير مربوط — '
          'الضريبة $tax أُدمجت في إيراد المبيعات لإبقاء القيد متوازناً. '
          'اربط output_vat في الربط المحاسبي حتى تُرحَّل لحسابها وتظهر في الدفتر.');
    }
    if (deliveryFee > 0 && deliveryAcc == null) {
      await DiagnosticLogger.log('AUTOPOST-WARN',
          'فاتورة #$invNumber: حساب إيراد التوصيل (delivery_revenue) غير مربوط — '
          'مبلغ التوصيل $deliveryFee أُدمج في إيراد المبيعات. اربطه في الربط المحاسبي.');
    }
    // ── سطرُ فرق التقريب — يُضاف قبل احتساب الإيراد ────────────────────────
    //
    // موجبٌ = قُرِّب هبوطاً (‏قُبض أقلّ) ⇒ مدين. سالبٌ = صعوداً ⇒ دائن.
    // ونفسُ اتّجاه سطرِ `autoPostCashSale` حرفاً بحرف فلا يفترق المسارَان.
    if (roundingAdjustment != 0) {
      final roundingAcc = await _optionalAccount('rounding_difference');
      if (roundingAcc != null) {
        journalLines.add(JournalLine(
          accountId: roundingAcc.id,
          debit: roundingAdjustment > 0 ? roundingAdjustment : 0,
          credit: roundingAdjustment < 0 ? -roundingAdjustment : 0,
          description: 'فروق تقريب',
          costCenterId: costCenterId,
        ));
      } else {
        await DiagnosticLogger.log(
            'AUTOPOST-WARN',
            'فاتورة #$invNumber: حساب فروق التقريب (rounding_difference) غير '
            'مربوط — فرقُ $roundingAdjustment بلا سطر. اربطه في الربط المحاسبي.');
      }
    }

    // ⚠️ **و`roundingAdjustment` يدخل الإيراد.** الإيرادُ هو الإجماليُّ
    // **الحقيقيُّ** لا المقبوض: `paid + remaining + adj == total` بالبناء،
    // فبدونه يُحسَب الإيرادُ على المقبوضِ المقرَّب ويختلّ القيد.
    final netSalesCredit =
        (paid + remaining + roundingAdjustment) - vatLeg - deliveryLeg;
    if (netSalesCredit.abs() > 0.001) {
      journalLines.add(JournalLine(
        accountId: salesAcc.id,
        credit: netSalesCredit,
        description: 'إيراد مبيعات فاتورة #$invNumber',
        costCenterId: costCenterId,
      ));
    }
    if (vatLeg > 0) {
      journalLines.add(JournalLine(
        accountId: vatAcc!.id,
        credit: vatLeg,
        description: 'ضريبة مخرجات فاتورة #$invNumber',
        costCenterId: costCenterId,
      ));
    }
    // Inventory Credit (Stock reduction)
    //
    // Feature 009 / T017 — when `cogsBreakdown` is supplied (auto-deplete
    // path), split the inventory credit per raw-material account aggregated
    // by accountId, AND emit a residual legacy leg for any items whose
    // costPrice contributed to `cogsTotal` but were NOT covered by the
    // breakdown (mixed-mode invoices: some items have an active auto-deplete
    // BOM, others use the legacy single-account path). Today every
    // CogsLine.inventoryAccountId resolves to the same singleton '1136'
    // account, so an all-auto-deplete invoice produces ONE aggregated leg
    // — mathematically identical to the legacy single leg. Constitution I
    // (Behavior Preservation) is preserved when `cogsBreakdown` is null
    // OR empty.
    // The two cost sources credit inventory INDEPENDENTLY. The old code
    // treated the breakdown as a subdivision of `cogsTotal` and credited the
    // difference (`cogsTotal - breakdownTotal`), which had two failure modes:
    //   • an all-BOM invoice (cogsTotal == 0) skipped BOTH legs entirely, and
    //   • a mixed invoice produced a NEGATIVE `credit` — written verbatim into
    //     journal_entry_lines, where every report reading the credit column
    //     silently under-counts. The books still balanced, so nothing caught it.
    // Splitting the legs makes each amount a real, non-negative outflow.

    // Legacy singleton inventory account — the ordinary (non-BOM) lines.
    if (cogsTotal > 0.001) {
      final invAcc = await _requireAccount('inventory');
      journalLines.add(JournalLine(
        accountId: invAcc.id,
        credit: cogsTotal,
        description: 'خروج مخزون فاتورة #$invNumber',
        costCenterId: costCenterId,
      ));
    }

    // Per-account aggregated breakdown (one leg per distinct accountId) —
    // the raw materials consumed by auto-deplete. Deliberately OUTSIDE the
    // `cogsTotal` gate: that gate is exactly what hid this leg.
    if (breakdownTotal > 0.001) {
      final aggregated = <int, double>{};
      for (final line in cogsBreakdown!) {
        aggregated.update(
          line.inventoryAccountId,
          (existing) => existing + line.totalCost,
          ifAbsent: () => line.totalCost,
        );
      }
      for (final entry in aggregated.entries) {
        journalLines.add(JournalLine(
          accountId: entry.key,
          credit: entry.value,
          description: 'خروج مخزون فاتورة #$invNumber',
          costCenterId: costCenterId,
        ));
      }
    }

    // H-09 + Spec 136: delivery fee → delivery_revenue when mapped. When NOT
    // mapped, deliveryLeg is 0 and the fee was already folded into the Sales
    // credit above (derived from total), so we must NOT credit it again here —
    // the old fallback-to-sales would double-credit against the derived net.
    if (deliveryLeg > 0) {
      journalLines.add(JournalLine(
        accountId: deliveryAcc!.id,
        credit: deliveryLeg,
        description: 'إيراد توصيل فاتورة #$invNumber',
        costCenterId: costCenterId,
      ));
    }

    // ISS-01: Validate balance and create entry
    // BRANCH-LABEL FIX: append branch name to description so financial reports
    // clearly identify which branch originated each auto-posted JE.
    final branchLabel = (branchName != null && branchName.isNotEmpty)
        ? ' | $branchName'
        : '';
    final regionLabel = (regionName != null && regionName.isNotEmpty)
        ? ' | $regionName'
        : '';
    await _validateAndCreateEntry(
      lines: journalLines,
      description: 'قيد مبيعات تلقائي لفاتورة #$invNumber$regionLabel$branchLabel',
      date: invoiceDate ?? DateTime.now(),
      referenceType: 'sales_invoice',
      referenceId: invoiceId,
      costCenterId: costCenterId,
      branchId: branchId,
      context: 'فاتورة مبيعات #$invNumber',
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PURCHASE INVOICE JE
  // ═══════════════════════════════════════════════════════════════════════

  /// Generate automatic accounting entry for a purchase invoice.
  /// ISS-04: Now accepts [paymentMethod] to route to correct account.
  Future<void> generatePurchaseAccountingEntry({
    required int invoiceId,
    required double subtotal,
    required double tax,
    required double total,
    required double paid,
    required double remaining,
    required String? notes,
    String paymentMethod = 'cash', // ISS-04: default cash for backward compat
    int? supplierId, // NEW: route AP line to supplier sub-account
    int? costCenterId,
    int? branchId,
    DateTime? invoiceDate,
  }) async {
    final List<JournalLine> journalLines = [];
    final desc = notes ?? 'فاتورة مشتريات #$invoiceId';

    if (subtotal > 0) {
      final inventoryAcc = await _requireAccount('inventory');
      journalLines.add(JournalLine(
        accountId: inventoryAcc.id,
        debit: subtotal,
        description: 'مخزون وارد - $desc',
        costCenterId: costCenterId,
      ));
    }

    if (tax > 0) {
      final inputVatAcc = await _requireAccount('input_vat');
      journalLines.add(JournalLine(
        accountId: inputVatAcc.id,
        debit: tax,
        description: 'ضريبة مدخلات - $desc',
        costCenterId: costCenterId,
      ));
    }

    // ISS-04: Route payment to correct account based on paymentMethod
    if (paid > 0) {
      final paymentPurpose = paymentMethod == 'bank' ? 'bank' : 'cash';
      final paymentAcc = await _requireAccount(paymentPurpose);
      journalLines.add(JournalLine(
        accountId: paymentAcc.id,
        credit: paid,
        description: 'سداد ($paymentMethod) - $desc',
        costCenterId: costCenterId,
      ));
    }

    if (remaining > 0) {
      final payablesAcc = await _partyAccount(
        partyId: supplierId,
        fallbackPurpose: 'payables',
      );
      journalLines.add(JournalLine(
        accountId: payablesAcc.id,
        credit: remaining,
        description: 'مشتريات آجلة - $desc',
        costCenterId: costCenterId,
      ));
    }

    // ISS-01: Validate balance and create entry
    await _validateAndCreateEntry(
      lines: journalLines,
      description: 'قيد مشتريات تلقائي - $desc',
      date: invoiceDate ?? DateTime.now(),
      referenceType: 'purchase_invoice',
      referenceId: invoiceId,
      costCenterId: costCenterId,
      branchId: branchId,
      context: 'فاتورة مشتريات #$invoiceId',
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SALES RETURN JE
  // ═══════════════════════════════════════════════════════════════════════

  /// Generate automatic accounting entry for a sales return
  Future<void> generateReturnAccountingEntry({
    required int invoiceId,
    required String invNumber,
    required double totalReturn,
    required double totalTaxReturn,
    required double totalCogsReturn,
    required double cashRefund,
    required double bankRefund,
    required double arRefund,
    int? customerId, // NEW: route AR reversal to customer sub-account
    int? costCenterId,
    int? branchId,
  }) async {
    final List<JournalLine> lines = [];

    // 1. Debit side (Reversing Revenue & Tax)
    final salesReturnAcc = await _requireAccount('sales_return');
    lines.add(JournalLine(
      accountId: salesReturnAcc.id,
      debit: totalReturn - totalTaxReturn,
      description: 'مرتجع مبيعات فاتورة #$invNumber',
      costCenterId: costCenterId,
    ));

    if (totalTaxReturn > 0) {
      final taxAcc = await _requireAccount('output_vat');
      lines.add(JournalLine(
        accountId: taxAcc.id,
        debit: totalTaxReturn,
        description: 'مرتجع ضريبة فاتورة #$invNumber',
        costCenterId: costCenterId,
      ));
    }

    // COGS reversal (Debit Inventory)
    if (totalCogsReturn > 0) {
      final invAcc = await _requireAccount('inventory');
      lines.add(JournalLine(
        accountId: invAcc.id,
        debit: totalCogsReturn,
        description: 'إعادة للمخزون - مرتجع فاتورة #$invNumber',
        costCenterId: costCenterId,
      ));
    }

    // 2. Credit side (Reversing Payment & COGS)
    if (arRefund > 0) {
      final arAcc = await _partyAccount(
        partyId: customerId,
        fallbackPurpose: 'receivables',
      );
      lines.add(JournalLine(
        accountId: arAcc.id,
        credit: arRefund,
        description: 'تخفيض حساب عميل - مرتجع فاتورة #$invNumber',
        costCenterId: costCenterId,
      ));
    }
    if (cashRefund > 0) {
      final cashAcc = await _requireAccount('cash');
      lines.add(JournalLine(
        accountId: cashAcc.id,
        credit: cashRefund,
        description: 'صرف نقدي - مرتجع فاتورة #$invNumber',
        costCenterId: costCenterId,
      ));
    }
    if (bankRefund > 0) {
      final bankAcc = await _requireAccount('bank');
      lines.add(JournalLine(
        accountId: bankAcc.id,
        credit: bankRefund,
        description: 'صرف بنكي - مرتجع فاتورة #$invNumber',
        costCenterId: costCenterId,
      ));
    }

    // COGS reversal (Credit COGS)
    if (totalCogsReturn > 0) {
      final cogsAcc = await _requireAccount('cogs');
      lines.add(JournalLine(
        accountId: cogsAcc.id,
        credit: totalCogsReturn,
        description: 'تخفيض تكلفة المبيعات - مرتجع فاتورة #$invNumber',
        costCenterId: costCenterId,
      ));
    }

    // ISS-01: Validate balance and create entry
    await _validateAndCreateEntry(
      lines: lines,
      description: 'قيد مبيعات مرتجعة تلقائي لفاتورة #$invNumber',
      date: DateTime.now(),
      referenceType: 'sales_return',
      referenceId: invoiceId,
      costCenterId: costCenterId,
      branchId: branchId,
      context: 'مرتجع فاتورة #$invNumber',
    );
  }

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
            'sales_return', invoice.id),
        ...await _inventoryRepo.getStockMovementsByReference(
            'sales_invoice', invoice.id),
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
            referenceId: invoice.id,
            unitCost: movement.unitCost,
            notes: 'إلغاء مرتجع فاتورة ${invoice.invoiceNumber}',
          );
        }
      }

      // 2. Reverse refund safe transactions
      final returnSafeTransactions = await _treasuryRepo.getTransactionsByReference(
        'sales_return',
        invoice.id,
      );

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
              voucherNumber: 'CAN-RET${DateTime.now().year}${invoice.id.toString().padLeft(6, '0')}',
              safeId: safe.id,
              transactionType: 'receipt',
              category: 'return_cancel',
              amount: origTxn.amount,
              balanceAfter: newBalance,
              referenceType: 'return_cancel',
              referenceId: invoice.id,
              description: 'إلغاء مرتجع فاتورة ${invoice.invoiceNumber}',
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
            invoice.id,
          );

          for (final entry in entries) {
            final lines = await _accountingRepo.getJournalEntryLinesWithAccounts(entry.id);
            for (final line in lines) {
              if (line['account_id'] == arAcc.id && (line['credit'] ?? 0) > 0) {
                await _partiesRepo.adjustPartyBalance(invoice.customerId!, line['credit']);
              }
            }
          }
        }
      }

      // 4. Reverse Journal Entries
      await reverseReturnAccountingEntry(
        invoiceId: invoice.id,
        invNumber: invoice.invoiceNumber,
      );

      // 5. Reset invoice status
      await _accountingRepo.updateEntityStatus('sales_invoices', invoice.id, 'completed');

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

  // ═══════════════════════════════════════════════════════════════════════
  // SHIFT CLOSING JE (N6)
  // ═══════════════════════════════════════════════════════════════════════

  /// Generate detailed closing accounting entry
  Future<void> generateClosingAccountingEntry({
    required double cashAmount,
    required double bankAmount,
    required double clickAmount,
    required double totalExpenses,
    required double totalSales,
    required String employeeName,
    int? branchId, 
    int? costCenterId,
  }) async {
    final List<JournalLine> lines = [];
    final desc = 'قيد إغلاق وردية — $employeeName';

    if (cashAmount > 0) {
      final cashAcc = await _requireAccount('cash');
      lines.add(JournalLine(
        accountId: cashAcc.id,
        debit: cashAmount,
        description: 'تحصيل نقدي - $desc',
        costCenterId: costCenterId,
      ));
    }

    final bankTotal = bankAmount + clickAmount;
    if (bankTotal > 0) {
      final bankAcc = await _requireAccount('bank');
      lines.add(JournalLine(
        accountId: bankAcc.id,
        debit: bankTotal,
        description: 'تحصيل بنك/بطاقة/كليك - $desc',
        costCenterId: costCenterId,
      ));
    }

    if (totalExpenses > 0) {
      // Prefer the dedicated 'op_expenses' purpose; fall back to the
      // generic 'misc_expense' mapping (default code '6214'). Both
      // resolve through the seeded chart — no raw code lookup.
      final expenseAcc = await _optionalAccount('op_expenses')
          ?? await _optionalAccount('misc_expense');
      final fallback = expenseAcc;
      if (fallback != null) {
        lines.add(JournalLine(
          accountId: fallback.id,
          debit: totalExpenses,
          description: 'مصروفات الوردية - $desc',
          costCenterId: costCenterId,
        ));
      } else {
        debugPrint('[JE-WARNING] حساب المصروفات غير موجود — سيتم تخطي سطر المصروفات');
      }
    }

    final totalCredit = cashAmount + bankTotal + totalExpenses;
    if (totalCredit > 0) {
      final salesAcc = await _requireAccount('sales');
      lines.add(JournalLine(
        accountId: salesAcc.id,
        credit: totalCredit,
        description: 'إيرادات المبيعات - $desc',
        costCenterId: costCenterId,
      ));
    }

    // ISS-01: Validate balance and create entry
    await _validateAndCreateEntry(
      lines: lines,
      description: desc,
      date: DateTime.now(),
      referenceType: 'shift_closing',
      branchId: branchId,
      costCenterId: costCenterId,
      context: 'إغلاق وردية $employeeName',
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // CYCLE COUNT ADJUSTMENT JE (Phase C4)
  // ═══════════════════════════════════════════════════════════════════════

  // Spec 147 (S-COUNT): generateCycleCountEntry removed. The cycle-count
  // settlement JE now posts atomically inside AppDatabase.finalizeCycleCountTask
  // (one transaction with the stock corrections), so it no longer lives here.
}