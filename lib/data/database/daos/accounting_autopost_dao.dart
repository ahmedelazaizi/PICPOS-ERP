// =======================================================================
// ACCOUNTING AUTO-POSTING DAO
// Extracted from accounting_dao.dart - Sprint 12 God File Splitting
// =======================================================================

part of '../database.dart';

/// Extension for Accounting Auto-Posting operations
/// تاريخ ترحيل قيد المرتجع.
///
/// ── العطل اللي الدالة دي موجودة عشانه ───────────────────────────────────────
/// القيد كان بيتسجّل بـ`originalInvoice.invoiceDate` — تاريخ **الفاتورة
/// الأصلية**. أثرين:
///
/// ١. إعادة تشكيل فترة منتهية: مرتجع أغسطس بيقلّل إيراد مارس ويعكس تكلفة
///    مارس، فقائمة دخل مارس اللي اتطبعت واتقدّمت للضرايب بتتغيّر بأثر رجعي،
///    وأغسطس بيظهر مبيعات بلا مرتجعات.
///
/// ٢. قفل كامل للمرتجعات: `createJournalEntry` بينادي
///    `validateFinancialPeriod(date)`، فأول ما الشهر القديم يتقفل أي مرتجع
///    لفواتيره **بيترفض تماماً** — والمستدعي عكس المخزون والخزنة جوه نفس
///    الترانزاكشن، فالعملية كلها بترجع والكاشير مش قادر يعمل مرتجع مشروع.
///
/// المرتجع **حدث لاحق** له فترته الخاصة مش تعديل على المستند الأصلي.
///
/// `null` بيقع على تاريخ الفاتورة عشان المسارات اللي لسه ما بتمرّرش تاريخ
/// تفضل شغّالة بسلوكها القديم — الانتقال تدريجي مش كسر.
@visibleForTesting
DateTime resolveReturnPostingDate({
  required DateTime? returnDate,
  required DateTime originalInvoiceDate,
}) =>
    returnDate ?? originalInvoiceDate;

extension AccountingAutopostDao on AppDatabase {

  /// Spec 136 — shared derivation of the balanced primary + discount legs for
  /// the three auto-post paths (cash sale, credit sale, purchase). Extracted
  /// verbatim from the formerly-triplicated block; **no value change** — the
  /// arithmetic and the AUTOPOST-WARN emission are identical to the inline code.
  ///
  /// Returns the rounded `primaryLeg` (Sales credit on the sales side /
  /// Inventory debit on the purchase side) and `discountLeg` (sales-discount
  /// debit / purchase-discount credit), both derived from the invoice's OWN
  /// arithmetic so the JE balances by construction whether the upstream
  /// `subtotal` was gross or already net of discount (AQ-POS-1 repro: a poison
  /// invoice with subtotal==total + non-zero discount imbalanced by exactly the
  /// discount and dead-lettered, flooding the server with retries).
  ///
  /// VAT/delivery amounts are only subtracted from the net when their account
  /// is mapped (so they will actually be posted on their own leg); when
  /// unmapped, the amount stays folded into the primary leg to keep the JE
  /// balanced, and [unmappedVatWarning] is logged. Purchase callers pass
  /// `deliveryFee: 0` / `deliveryAccount: null` (no separately-booked delivery).
  ({double primaryLeg, double discountLeg}) _deriveBalancedLegs({
    required double total,
    required double subtotal,
    required double tax,
    required double discount,
    required double deliveryFee,
    required Account? vatAccount,
    required Account? deliveryAccount,
    required Account? discountAccount,
    required String unmappedVatWarning,
  }) {
    final vatLeg = (tax > 0 && vatAccount != null) ? tax : 0.0;
    final deliveryLeg =
        (deliveryFee > 0 && deliveryAccount != null) ? deliveryFee : 0.0;
    if (tax > 0 && vatAccount == null) {
      unawaited(DiagnosticLogger.log('AUTOPOST-WARN', unmappedVatWarning));
    }
    final net = total - vatLeg - deliveryLeg;
    final rawDiscount =
        (discount > 0 && discountAccount != null) ? (subtotal - net) : 0.0;
    final discountLeg = rawDiscount > 0
        ? double.parse(rawDiscount.toStringAsFixed(AppConstants.decimalPlaces))
        : 0.0;
    final primaryLeg = double.parse(
        (net + discountLeg).toStringAsFixed(AppConstants.decimalPlaces));
    return (primaryLeg: primaryLeg, discountLeg: discountLeg);
  }

  /// Helper to resolve branch-specific safe account vs global mapped account
  Future<Account?> _resolveBranchSafeAccount(int? branchId, String type, String fallbackPurpose) async {
    if (branchId != null) {
      // P2: branch-level safe
      final branchSafe = await (select(safes)
            ..where((s) =>
                s.branchId.equals(branchId) &
                s.safeType.equals(type) &
                s.isActive.equals(true))
            ..orderBy([(s) => OrderingTerm(expression: s.isDefault, mode: OrderingMode.desc)])
            ..limit(1))
          .getSingleOrNull();

      if (branchSafe?.linkedAccountId != null) {
        return accountingDao.getAccountById(branchSafe!.linkedAccountId!);
      }

      // P2b: region-level safe — branch exists but has no matching safe
      final branchRow = await (select(branches)..where((b) => b.id.equals(branchId))..limit(1)).getSingleOrNull();
      if (branchRow?.regionId != null) {
        Safe? targetSafe = await (select(safes)
              ..where((s) =>
                  s.regionId.equals(branchRow!.regionId!) &
                  s.safeType.equals(type) &
                  s.isActive.equals(true))
              ..limit(1))
            .getSingleOrNull();
        if (targetSafe != null) {
          debugPrint('[SafeRoute] P2b: region safe #${targetSafe.id} for region #${branchRow!.regionId}');
          if (targetSafe.linkedAccountId != null) {
            return accountingDao.getAccountById(targetSafe.linkedAccountId!);
          }
        }
      }
    }

    // P3: system default
    final fallbackCode = await accountingDao.getMappedAccountCode(fallbackPurpose, AccountingDao.accountPurposes[fallbackPurpose]!);
    return accountingDao.getAccountByCode(fallbackCode);
  }

  /// Spec 136 ISS-13: resolve the GL account for a sale's payment leg from the
  /// ACTUAL safe the receipt landed in, not the branch's *default* safe.
  ///
  /// Field incident: a branch (Aqaba) cash sale autoposted its cash debit to
  /// the ADMIN cash account (111-00001) instead of the branch cash safe
  /// (111-00003). Root cause: [_resolveBranchSafeAccount] picks the branch's
  /// first *default* active safe of the type and returns its `linkedAccountId`;
  /// when that default safe has a NULL link it gives up and falls through to the
  /// global mapped account — even though the safe the cash physically went into
  /// (recorded in `safe_transactions` by `_recordSalesReceipt`) IS linked.
  /// Shift-close was already branch-correct because it resolves the account from
  /// the actual safe (like `autoPostReceipt`); only the sale autopost wasn't.
  ///
  /// Resolution order:
  ///   1. The safe of [safeType] referenced by this sale's receipt row(s) in
  ///      `safe_transactions` → its `linkedAccountId`. This works on every
  ///      posting path (POS, server sync, failed-autopost repair) and is immune
  ///      to client/server id-drift because the receipt row was written
  ///      server-side with the server's own safe id.
  ///   2. Fallback to the previous branch-default resolution
  ///      ([_resolveBranchSafeAccount]) when the sale has no recorded safe of
  ///      that type (e.g. a repaired sale whose receipt row never landed) or
  ///      that safe has no linked account.
  Future<Account?> _resolveSaleLegAccount(
    int saleId,
    int? branchId,
    String safeType,
  ) async {
    final row = await (select(safeTransactions).join([
      innerJoin(safes, safes.id.equalsExp(safeTransactions.safeId)),
    ])
          ..where(safeTransactions.referenceType.equals('sales_invoice') &
              safeTransactions.referenceId.equals(saleId) &
              safeTransactions.transactionType.equals('receipt') &
              safes.safeType.equals(safeType))
          ..limit(1))
        .getSingleOrNull();
    if (row != null) {
      final safe = row.readTable(safes);
      if (safe.linkedAccountId != null) {
        final acct = await accountingDao.getAccountById(safe.linkedAccountId!);
        if (acct != null) return acct;
      }
    }
    // Fallback: previous branch-default behaviour.
    return _resolveBranchSafeAccount(branchId, safeType, safeType);
  }

  /// Resolve the effective AR/AP account for a given party.
  ///
  /// Every party row (created via [PartyDao.createParty]) is paired with a
  /// dedicated sub-account under the control parent (1121-XXXXX for AR /
  /// 2111-XXXXX for AP, both seeded by seedChartOfAccounts) and linked via
  /// `parties.accountId`. Routing journal lines through that sub-account
  /// is what makes per-party balances visible in the Chart of Accounts
  /// tree and the General Ledger drill-down — the `LIKE '1121%'` rollup
  /// in `getAccountLedger` then aggregates
  /// all customer sub-accounts under their parent, and each customer shows
  /// its own balance in the COA.
  ///
  /// Prior behaviour posted every AR/AP line straight at the parent control
  /// account, so party sub-accounts always read 0 in the ledger even though
  /// `parties.balance` was correctly maintained.
  ///
  /// Falls back to [fallbackControl] when the party has no linked account
  /// (e.g. legacy data or system parties without a sub-account).
  Future<Account?> _resolvePartySubAccount(int? partyId, Account? fallbackControl) async {
    if (partyId == null) return fallbackControl;
    final party = await (select(parties)..where((p) => p.id.equals(partyId))..limit(1))
        .getSingleOrNull();
    if (party?.accountId == null) return fallbackControl;
    final sub = await accountingDao.getAccountById(party!.accountId!);
    return sub ?? fallbackControl;
  }

  /// P5 (Issue #6): Resolve a `parties` row that represents the given delivery
  /// company so the receivable is posted to a real ledger account instead of
  /// going into a generic cash bucket. Resolution order:
  ///   1. Sale's `deliveryCompanyPartyId` (explicit FK, if populated).
  ///   2. parties.name == delivery_companies.name AND is_delivery_company=true.
  /// Returns null when no matching party exists — caller falls back to the
  /// previous cash-debit behaviour so the JE still posts.
  Future<int?> _resolveDeliveryCompanyPartyId({
    int? explicitPartyId,
    int? deliveryCompanyId,
  }) async {
    if (explicitPartyId != null) {
      final exists = await (select(parties)
            ..where((p) => p.id.equals(explicitPartyId))
            ..limit(1))
          .getSingleOrNull();
      if (exists != null) return exists.id;
    }
    if (deliveryCompanyId == null) return null;
    final company = await (select(deliveryCompanies)
          ..where((d) => d.id.equals(deliveryCompanyId))
          ..limit(1))
        .getSingleOrNull();
    if (company == null) return null;
    final party = await (select(parties)
          ..where((p) =>
              p.name.equals(company.name) & p.isDeliveryCompany.equals(true))
          ..limit(1))
        .getSingleOrNull();
    return party?.id;
  }
}
