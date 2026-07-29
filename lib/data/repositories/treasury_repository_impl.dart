import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'base_repository.dart';
import '../../services/accounting_service.dart';
import '../database/sync_interceptor.dart';
import '../../services/client_write_interceptor.dart';
import '../providers/providers.dart';
import 'package:flutter/foundation.dart';
import '../../core/utils/uuid_v7.dart';
import '../../services/cheque_receipt_jes.dart';

/// Repository for treasury operations
class TreasuryRepositoryImpl extends BaseRepository<Safe> implements ITreasuryRepository {
  final Ref _ref;
  TreasuryRepositoryImpl(super.db, this._ref);

  AccountingService get _accountingService => _ref.read(accountingServiceProvider);

  @override
  Stream<List<SafeData>> watchSafes() {
    return db.watchAllSafes().map((list) => list.map(_safeRowToData).toList());
  }

  @override
  Stream<List<SafeData>> watchSafesForBranches(Set<int>? branchIds) {
    return db
        .watchSafesForBranches(branchIds)
        .map((list) => list.map(_safeRowToData).toList());
  }

  SafeData _safeRowToData(Safe s) => SafeData(
        id: s.id,
        name: s.name,
        safeType: s.safeType,
        balance: s.balance,
        isDefault: s.isDefault,
        isActive: s.isActive,
        bankName: s.bankName,
        accountNumber: s.accountNumber,
        costCenterId: s.costCenterId,
        branchId: s.branchId,
        linkedAccountId: s.linkedAccountId,
      );

  @override
  Future<SafeData?> getSafeById(int id) async {
    final s = await (db.select(db.safes)..where((s) => s.id.equals(id))).getSingleOrNull();
    if (s == null) return null;
    return SafeData(
      id: s.id,
      name: s.name,
      safeType: s.safeType,
      balance: s.balance,
      isDefault: s.isDefault,
      isActive: s.isActive,
      bankName: s.bankName,
      accountNumber: s.accountNumber,
      costCenterId: s.costCenterId,
      branchId: s.branchId,
      linkedAccountId: s.linkedAccountId,
    );
  }

  @override
  Future<SafeData?> getDefaultSafeByType(String type) async {
    // P5 (Issue #5): `.limit(1)` defensive guard. If a sync bug ever produces
    // duplicate default-cash rows, the previous code threw "Bad state: Too
    // many elements" from `.getSingleOrNull()` and crashed the expense
    // dialog. The root cause is fixed in safe_sync_strategy, but this guard
    // keeps the POS working even if stale duplicates linger from before the
    // fix landed.
    final s = await (db.select(db.safes)
      ..where((s) => s.safeType.equals(type))
      ..where((s) => s.isDefault.equals(true))
      ..orderBy([(s) => OrderingTerm.asc(s.id)])
      ..limit(1))
      .getSingleOrNull();
    if (s == null) return null;
    return SafeData(
      id: s.id,
      name: s.name,
      safeType: s.safeType,
      balance: s.balance,
      isDefault: s.isDefault,
      isActive: s.isActive,
      bankName: s.bankName,
      accountNumber: s.accountNumber,
      costCenterId: s.costCenterId,
      branchId: s.branchId,
      linkedAccountId: s.linkedAccountId,
    );
  }

  @override
  Future<void> updateSafeBalance(int safeId, double newBalance) {
    return (db.update(db.safes)..where((s) => s.id.equals(safeId))).write(
      SafesCompanion(balance: Value(newBalance)),
    );
  }

  @override
  Future<double> getTotalCashBalance() => db.getTotalCashBalance();

  @override
  Future<int> createReceiptVoucher({
    required double amount,
    required String category,
    double discount = 0,
    String? description,
    int? partyId,
    int? safeId,
    int? userId,
    int? costCenterId,
    int? linkedAccountId, // GAP-03: Custom GL account from COA
    // Check metadata
    String? paperNumber,
    String? paperType,
    DateTime? paperIssueDate,
    DateTime? paperDueDate,
    String? paperBankName,
    // Issue 12: caller-supplied UUID so the local row and the server's
    // copy share identity. Pull-sync dedupes by globalId — without this
    // the same logical voucher ended up as two rows on the originating
    // device after a sync round-trip.
    String? globalId,
    // Spec 135 BUG-C — operator's working branch for JE attribution
    int? operatingBranchId,
  }) async {
    await _accountingService.ensureOpenFiscalPeriod(DateTime.now());

    return db.transaction(() async {
      // Spec 133 — mirror createPaymentVoucher (lines below). For cheque
      // receipts, the commercial-papers autopost owns the customer-credit
      // JE and the parties.balance adjustment. The DAO's cash-leg JE and
      // safe-transaction row are skipped to prevent the double-credit bug
      // that was observable on build 3.1.0+202. The discount portion
      // (settlement discount + delivery-company commission, both folded
      // into `discount` by the dialog) is posted separately by the
      // discount-only JE helper below — without that, a cheque receipt
      // with a discount would silently drop the discount-side accounting.
      final isCheckPayment = paperType == 'cheque' || paperType == 'check';

      int targetSafeId = safeId ?? 1;
      if (!isCheckPayment && safeId == null) {
        final defaultSafe = await (db.select(db.safes)..where((s) => s.isDefault.equals(true))).getSingleOrNull();
        if (defaultSafe != null) targetSafeId = defaultSafe.id;
      }

      final transactionId = await db.createReceiptVoucher(
        amount: amount,
        category: category,
        discount: discount,
        description: description,
        partyId: partyId,
        safeId: isCheckPayment ? null : targetSafeId,
        userId: userId,
        costCenterId: costCenterId,
        linkedAccountId: linkedAccountId,
        globalId: globalId,
        skipJournalEntry: isCheckPayment,
        skipSafeTransaction: isCheckPayment,
        operatingBranchId: operatingBranchId, // Spec 135 BUG-C
      );

      // Spec 133 (FR-010) — when a cheque receipt also carries a
      // settlement discount or delivery-company commission, post the
      // discount portion as its own JE (Dr: Discount Allowed / Cr:
      // Customer Sub-Account). The cash-leg JE that normally carries
      // the discount line is skipped above for cheques, so without
      // this the discount would silently disappear from the customer's
      // balance. The commercial-papers `pending` autopost (separate
      // write, separate transaction) credits the customer for the
      // cheque net amount. Net effect on the customer after both
      // writes: -(amount + discount), same as a cash receipt produces.
      //
      // Note on commission: the dialog folds delivery-company commission
      // into `discount` before calling the repo (see
      // receipt_voucher_dialog.dart::_saveVoucher line ~967), so this
      // single `discount > 0` gate covers both cases.
      if (isCheckPayment && discount > 0 && partyId != null) {
        await ChequeReceiptJEs.postDiscountAllowedJournalEntry(
          db: db,
          partyId: partyId,
          discountAmount: discount,
          costCenterId: costCenterId,
        );
      }

      // Spec 029 corrective patch — Bug A: do NOT auto-create a
      // commercial paper here. Receipt and payment voucher dialogs do
      // their own per-cheque create loop (one CommercialPaper per
      // physical check number, with the correctly-split amount). When
      // BOTH paths ran, every cheque ended up duplicated:
      //   - this repo created 1 paper using `paperNumber=allCheckNumbers`
      //     (e.g. "1, 2, 3" as a single string) — malformed.
      //   - the dialog auto-forward then created N more papers (one
      //     per real check number) — correct shape.
      // Net: N+1 rows per N cheques, plus one row whose paperNumber is
      // a comma-separated list. Removing the embedded create makes
      // the dialog auto-forward the canonical path. The legacy
      // `paperNumber`/`paperType`/`paperBankName`/`paperIssueDate`/
      // `paperDueDate` parameters are kept on the API for source
      // compatibility but no longer trigger paper creation here; the
      // dialog continues to use them only for the voucher description.
      // Symmetric with `createPaymentVoucher` (line 219-222) which
      // already documented this contract.

      return transactionId;
    });
  }

  @override
  Future<int> createPaymentVoucher({
    required double amount,
    required String category,
    double discount = 0,
    String? description,
    int? partyId,
    int? safeId,
    int? userId,
    int? costCenterId,
    String? globalId,
    // Check metadata
    String? paperNumber,
    String? paperType,
    DateTime? paperIssueDate,
    DateTime? paperDueDate,
    String? paperBankName,
    // Spec 135 BUG-C — operator's working branch for JE attribution
    int? operatingBranchId,
  }) async {
    await _accountingService.ensureOpenFiscalPeriod(DateTime.now());

    return db.transaction(() async {
      final isCheckPayment = paperType == 'cheque' || paperType == 'check';

      // For non-check payments, resolve the target safe
      int? resolvedSafeId;
      if (!isCheckPayment) {
        resolvedSafeId = safeId;
        if (resolvedSafeId == null) {
          final defaultSafe = await (db.select(db.safes)..where((s) => s.isDefault.equals(true))).getSingleOrNull();
          if (defaultSafe != null) resolvedSafeId = defaultSafe.id;
        }
      }

      final transactionId = await db.createPaymentVoucher(
        amount: amount,
        category: category,
        discount: discount,
        description: description,
        partyId: partyId,
        safeId: resolvedSafeId,
        userId: userId,
        costCenterId: costCenterId,
        globalId: globalId,
        // For check payments the commercial papers system (called from the UI
        // per-check loop) creates the correct Dr: Payables / Cr: Notes Payable
        // entry. Skip the cash JE here to avoid a duplicate.
        skipJournalEntry: isCheckPayment,
        // For check payments, no physical cash leaves the safe — skip entirely.
        skipSafeTransaction: isCheckPayment,
        operatingBranchId: operatingBranchId, // Spec 135 BUG-C
      );

      // Commercial paper creation is intentionally NOT done here.
      // The calling UI creates one CommercialPaper per check number (with the
      // correct split amounts).  Creating another one here would duplicate both
      // the papers and their auto-posted journal entries.

      return transactionId;
    });
  }

  @override
  Future<void> closeSafe(
    int safeId, {
    double? cashAmount,
    double? bankAmount,
    String? notes,
  }) async {
    final s = await (db.select(db.safes)..where((s) => s.id.equals(safeId))).getSingleOrNull();
    if (s == null) throw Exception('Safe not found');
    final amountToClose = s.balance;
    if (amountToClose <= 0) return;

    // Spec 135 — mint ONE close-event gid here (this repo is the caller of
    // both the local DAO and the server submit) and thread the SAME value
    // into both, so the client-posted and server-posted closing JE converge
    // on one deterministic globalId (dedup on next pull) instead of each side
    // minting a random divergent id → a duplicate closing JE on the client.
    // R9: caller mints, threads identically into local insert + server submit.
    final closeEventGid = UuidV7.generate();

    // Use DAO to handle the complete local transaction and JE logic
    await db.closeSafe(
      safeId,
      cashAmount: cashAmount,
      bankAmount: bankAmount,
      notes: notes,
      closeEventGid: closeEventGid,
    );

    // H-10 FIX: Route through dedicated closeSafe endpoint (not generic safeTransaction)
    try {
      await ClientWriteInterceptor.closeSafe(
        safeId,
        cashAmount: cashAmount,
        bankAmount: bankAmount,
        notes: notes,
        closeEventGid: closeEventGid,
      );
    } catch (e) {
      debugPrint('[TreasuryRepo] Failed to sync closing to server: $e');
    }
  }

  @override
  Stream<List<TransactionData>> watchRecentTransactions({int limit = 50}) {
    return db.watchRecentTransactions().map((list) => list.map((t) => TransactionData(
      id: t.id,
      voucherNumber: t.voucherNumber,
      safeId: t.safeId,
      safeName: '', // Need to join with safes or get from context
      transactionType: t.transactionType,
      category: t.category,
      amount: t.amount,
      discount: t.discount,
      balanceAfter: t.balanceAfter,
      partyId: t.partyId,
      partyName: null,
      description: t.description,
      createdAt: t.createdAt,
    )).toList());
  }

  /// Issue 14 — branch-scoped recent transactions. `branchIds == null`
  /// means full access (admin). The mapping body mirrors
  /// [watchRecentTransactions] so consumers don't need to special-case
  /// the scoped path.
  @override
  Stream<List<TransactionData>> watchRecentTransactionsForBranches(
    Set<int>? branchIds,
  ) {
    return db
        .watchRecentTransactionsForBranches(branchIds)
        .map((list) => list
            .map((t) => TransactionData(
                  id: t.id,
                  voucherNumber: t.voucherNumber,
                  safeId: t.safeId,
                  safeName: '',
                  transactionType: t.transactionType,
                  category: t.category,
                  amount: t.amount,
                  discount: t.discount,
                  balanceAfter: t.balanceAfter,
                  partyId: t.partyId,
                  partyName: null,
                  description: t.description,
                  createdAt: t.createdAt,
                ))
            .toList());
  }

  @override
  Future<List<TransactionData>> getTransactionsByDateRange(DateTime from, DateTime to, {int? userId}) async {
    final list = await db.getTransactionsByDateRange(from, to, userId: userId);
    return list.map((t) => TransactionData(
      id: t.id,
      voucherNumber: t.voucherNumber,
      safeId: t.safeId,
      safeName: '',
      transactionType: t.transactionType,
      category: t.category ?? '',
      amount: t.amount,
      discount: t.discount,
      balanceAfter: t.balanceAfter,
      partyId: t.partyId,
      partyName: null,
      description: t.description,
      userId: t.userId,
      userName: t.userName,
      createdAt: t.createdAt,
    )).toList();
  }

  @override
  Future<Map<String, double>> getTransactionsByCategory({
    required String type,
    DateTime? from,
    DateTime? to,
  }) async {
    final stats = await db.getTreasurySummary(fromDate: from, toDate: to);
    return {
      'total': type == 'receipt' ? stats.totalReceipts : stats.totalPayments,
    };
  }

  @override
  Future<TreasurySummaryData> getTreasurySummary({DateTime? fromDate, DateTime? toDate}) async {
    final s = await db.getTreasurySummary(fromDate: fromDate, toDate: toDate);
    final currentBalance = await db.getTotalCashBalance();
    return TreasurySummaryData(
      totalReceipts: s.totalReceipts,
      totalPayments: s.totalPayments,
      netBalance: s.netBalance,
      currentBalance: currentBalance,
    );
  }

  @override
  Stream<List<Safe>> watchAll() => db.watchAllSafes();

  @override
  Future<Safe?> getById(int id) {
    return (db.select(db.safes)..where((s) => s.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<int> createSafeTransaction({
    required String voucherNumber,
    required int safeId,
    required String transactionType,
    required String category,
    required double amount,
    required double balanceAfter,
    String? referenceType,
    int? referenceId,
    String? description,
    int? userId,
  }) async {
    // Spec 007 / FR-011 / T019.A: mint the safe-transaction globalId here so
    // the local insert and the post-commit submitSafeTransaction call share
    // the same UUID. Without this, the server minted its own globalId, and
    // the next DeltaPull inserted the server row as a *second* local
    // safe_transactions row — silently doubling the safe balance impact on
    // mirror devices. Same defect class as the manual JE bug fixed in T013.
    final txnGlobalId = UuidV7.generate();
    final companion = SafeTransactionsCompanion.insert(
      voucherNumber: voucherNumber,
      safeId: safeId,
      transactionType: transactionType,
      category: category,
      amount: amount,
      balanceAfter: balanceAfter,
      referenceType: Value(referenceType),
      referenceId: Value(referenceId),
      description: Value(description),
      userId: Value(userId),
      globalId: Value(txnGlobalId),
    );

    // Call DAO so the safe balance is updated locally
    final id = await db.createSafeTransaction(companion);

    // Sync to backend (fire-and-forget or queued)
    try {
      await SyncInterceptor.instance?.submitSafeTransaction(
        safeId: safeId,
        transactionType: transactionType,
        amount: amount,
        category: category,
        description: description,
        userId: userId,
        referenceType: referenceType,
        referenceId: referenceId,
        globalId: txnGlobalId,
      );
    } catch (e) {
      debugPrint('[TreasuryRepo] Failed to sync safe transaction: $e');
    }

    return id;
  }

  @override
  Future<SafeData?> getSafeByIdRaw(int id) async {
    final s = await (db.select(db.safes)..where((s) => s.id.equals(id))).getSingleOrNull();
    if (s == null) return null;
    return SafeData(
      id: s.id,
      name: s.name,
      safeType: s.safeType,
      balance: s.balance,
      isDefault: s.isDefault,
      isActive: s.isActive,
      bankName: s.bankName,
      accountNumber: s.accountNumber,
      costCenterId: s.costCenterId,
      branchId: s.branchId,
      linkedAccountId: s.linkedAccountId,
    );
  }

  @override
  Future<List<TransactionData>> getTransactionsByReference(String referenceType, int referenceId) async {
    final list = await (db.select(db.safeTransactions)
          ..where((t) => t.referenceType.equals(referenceType) & t.referenceId.equals(referenceId)))
        .get();

    return list.map((t) => TransactionData(
      id: t.id,
      voucherNumber: t.voucherNumber,
      safeId: t.safeId,
      safeName: '', // Could be fetched if needed
      transactionType: t.transactionType,
      category: t.category,
      amount: t.amount,
      discount: t.discount,
      balanceAfter: t.balanceAfter,
      partyId: t.partyId,
      partyName: null,
      description: t.description,
      userId: t.userId,
      createdAt: t.createdAt ?? DateTime.now(),
    )).toList();
  }

  @override
  Future<TransactionData?> getTransactionById(int id) async {
    final t = await (db.select(db.safeTransactions)
          ..where((row) => row.id.equals(id))
          ..limit(1))
        .getSingleOrNull();
    if (t == null) return null;
    return TransactionData(
      id: t.id,
      voucherNumber: t.voucherNumber,
      safeId: t.safeId,
      safeName: '',
      transactionType: t.transactionType,
      category: t.category,
      amount: t.amount,
      discount: t.discount,
      balanceAfter: t.balanceAfter,
      partyId: t.partyId,
      partyName: null,
      description: t.description,
      userId: t.userId,
      createdAt: t.createdAt ?? DateTime.now(),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getSafeAccountsForReference(String referenceType, int referenceId) async {
    // Custom query to join SafeTransactions with Safes to get the linked account ID
    final query = db.select(db.safeTransactions).join([
      innerJoin(db.safes, db.safes.id.equalsExp(db.safeTransactions.safeId)),
    ])..where(db.safeTransactions.referenceType.equals(referenceType) &
              db.safeTransactions.referenceId.equals(referenceId) &
              db.safeTransactions.transactionType.equals('receipt'));

    final rows = await query.get();
    final results = <Map<String, dynamic>>[];

    for (final row in rows) {
      final t = row.readTable(db.safeTransactions);
      final s = row.readTable(db.safes);

      int? accountId = s.linkedAccountId;
      // If safe has no linked account, fallback to global mapping
      if (accountId == null) {
        final assetType = s.safeType == 'bank' ? 'bank' : 'cash';
        final defaultCode = s.safeType == 'bank'
            ? AccountingDao.accountPurposes['bank']!
            : AccountingDao.accountPurposes['cash']!;
        final assetCode = await db.getMappedAccountCode(assetType, defaultCode);
        final account = await db.getAccountByCode(assetCode);
        if (account != null) {
          accountId = account.id;
        }
      }

      // Spec 029 corrective patch (2026-05-10) — leaf-safe resolution.
      // Beta server log on 2026-05-10 surfaced a sale-fail loop where
      // every POS sale aborted with HTTP 500: "لا يمكن الترحيل على حساب
      // رئيسي (111 - النقدية وما في حكمها) — يجب اختيار حساب تفصيلي".
      // Root cause: the operator's safe was wired to the cash HEADER
      // account (111), not a leaf. The cash leg of the sale's JE got
      // accountId=111, the JE-creation guard at accounting_dao_writes
      // .dart:194 (`accountNature == 'view'`) correctly refused the
      // post — but the resulting Exception bubbled into the API
      // response as 500, the client retried 10× until "permanent
      // failure" was recorded. Cluster 023 / Issue 3's leaf-safe
      // resolver was already wired into `getAccountByPurpose` and
      // `_partyAccount`, but the safe→linkedAccountId path bypassed
      // it entirely. Fixing here so EVERY origin of a JE accountId
      // funnels through `getLeafAccountById` before reaching the DAO
      // guard.
      if (accountId != null) {
        final leaf = await db.getLeafAccountById(accountId);
        if (leaf != null) {
          accountId = leaf.id;
        }
        // If `getLeafAccountById` returns null (header with no leaf
        // descendants) we keep the original id — the DAO guard will
        // still throw with a clear message and the operator will see
        // it during sale; better that than silently posting nothing.
      }

      if (accountId != null) {
        results.add({
          'accountId': accountId,
          'amount': t.amount,
          'safeName': s.name,
        });
      }
    }
    return results;
  }

  @override
  Future<ShiftData?> getCurrentOpenShift(int userId) async {
    final s = await db.getCurrentOpenShift(userId);
    if (s == null) return null;
    return _toShiftData(s);
  }

  @override
  Future<List<ShiftData>> getOpenShiftsForBranch({int? branchId}) async {
    final rows = await db.getOpenShiftsForBranch(branchId: branchId);
    return rows.map(_toShiftData).toList();
  }

  ShiftData _toShiftData(Shift s) => ShiftData(
        id: s.id,
        userId: s.userId,
        startTime: s.startTime,
        endTime: s.endTime,
        openingBalance: s.openingBalance,
        expectedCash: s.expectedCash,
        actualCash: s.actualCash,
        variance: s.variance,
        status: s.status,
        notes: s.notes,
        globalId: s.globalId,
      );

  @override
  Future<void> openShift(int userId, double openingBalance, {int? branchId}) =>
      db.openShift(userId, openingBalance, branchId: branchId);

  @override
  Future<void> closeShiftWithAudit(int shiftId, double actualCash, {String? notes, String closingMethod = 'normal', String? closingSnapshot, void Function(double)? onVarianceJeFailed}) =>
      db.closeShiftWithAudit(shiftId, actualCash, notes: notes, closingMethod: closingMethod, closingSnapshot: closingSnapshot, onVarianceJeFailed: onVarianceJeFailed);

  @override
  Future<void> deleteExpenseTransaction(int transactionId) =>
      db.deleteExpenseTransaction(transactionId);

  @override
  Future<int> createSafe({required String name, required String safeType, String? bankName, String? accountNumber, int? costCenterId, int? branchId, int? linkedAccountId}) async {
    // Feature 006 (MM.C) — when the device is in mirror mode (or client
    // mode), route safe creation through the server so the linked CoA
    // sub-account is minted atomically on HQ instead of only locally.
    // The next DeltaPull mirrors the new safe + account back to this
    // device. Standalone / server modes still write straight to the DAO.
    if (SyncInterceptor.isClientMode) {
      final id = await ClientWriteInterceptor.createSafe(
        name: name,
        safeType: safeType,
        bankName: bankName,
        accountNumber: accountNumber,
        costCenterId: costCenterId,
        branchId: branchId,
      );
      return id ?? 0;
    }
    // Feature 004 (US1): delegate to the atomic DAO method that also creates
    // and links a Chart-of-Accounts sub-account in the same transaction.
    // [linkedAccountId] is accepted for backward compatibility with older
    // callers but is now ignored — the DAO mints a fresh sub-account every
    // time so the linkage is guaranteed (Constitution IV — Atomic Persistence).
    return db.createSafeWithLinkedAccount(
      name: name,
      safeType: safeType,
      bankName: bankName,
      accountNumber: accountNumber,
      costCenterId: costCenterId,
      branchId: branchId,
    );
  }

  @override
  Future<void> updateSafeDetails({required int safeId, required String name, String? bankName, String? accountNumber, int? costCenterId, int? branchId, int? linkedAccountId}) async {
    if (SyncInterceptor.isClientMode) {
      await ClientWriteInterceptor.updateSafe(safeId, {
        'name': name,
        'bankName': bankName,
        'accountNumber': accountNumber,
        'costCenterId': costCenterId,
        'branchId': branchId,
      });
      return;
    }
    // Feature 004 (US1, FR-006): rename propagates to the linked CoA sub-account
    // atomically. Wrap in a transaction so the safe's new name and the account's
    // new name are committed together — no half-renamed state visible to readers.
    // The "manually-overridden account name" guard mentioned in FR-006 is
    // deferred to a follow-up spec; this implementation always propagates.
    await db.transaction(() async {
      // Read current state to detect a real name change.
      final current = await db.customSelect(
        'SELECT name, linked_account_id FROM safes WHERE id = ?',
        variables: [Variable.withInt(safeId)],
      ).getSingleOrNull();

      await db.customStatement(
        'UPDATE safes SET name = ?, bank_name = ?, account_number = ?, cost_center_id = ?, branch_id = ?, linked_account_id = ? WHERE id = ?',
        [name, bankName, accountNumber, costCenterId, branchId, linkedAccountId, safeId],
      );

      if (current != null) {
        final oldName = current.read<String?>('name');
        final linkedAcc = current.read<int?>('linked_account_id');
        if (linkedAcc != null && oldName != name) {
          await db.customStatement(
            'UPDATE accounts SET name = ? WHERE id = ?',
            [name, linkedAcc],
          );
        }
      }
    });
  }

  @override
  Future<void> setDefaultSafe(int safeId) async {
    // Mirror mode (Feature 006 / MM.C): server is authoritative — call
    // the interceptor first and let MirrorOfflineException propagate.
    // Skipping the local write avoids leaving stale "default" state in
    // SQLite when the server rejected (or never received) the change;
    // the next DeltaPull mirrors the authoritative value back.
    if (SyncInterceptor.isClientMode) {
      await ClientWriteInterceptor.submitSetDefaultSafe(safeId: safeId);
      return;
    }
    // Standalone / server modes: optimistic local update + (legacy)
    // best-effort backend sync — kept for the rare case where a
    // standalone instance has somehow accumulated an interceptor.
    await db.setDefaultSafe(safeId);
  }

  @override
  Future<void> toggleSafeActive(int safeId, bool isActive) async {
    // Mirror mode: the active flag is a structural CRUD edit, route it
    // through the dedicated updateSafe endpoint so HQ has the change
    // immediately and the next DeltaPull syncs the local cache.
    if (SyncInterceptor.isClientMode) {
      await ClientWriteInterceptor.updateSafe(safeId, {'isActive': isActive});
      return;
    }
    await db.toggleSafeActive(safeId, isActive);
  }

  @override
  Future<void> deleteSafeById(int safeId) async {
    if (SyncInterceptor.isClientMode) {
      await ClientWriteInterceptor.deleteSafe(safeId);
      return;
    }
    await db.deleteSafeById(safeId);
  }

  @override
  Future<List<TransactionData>> getTransactionsSince(DateTime since) async {
    final list = await (db.select(db.safeTransactions)
          ..where((t) => t.createdAt.isBiggerOrEqualValue(since)))
        .get();

    return list.map((t) => TransactionData(
      id: t.id,
      voucherNumber: t.voucherNumber,
      safeId: t.safeId,
      safeName: '',
      transactionType: t.transactionType,
      category: t.category,
      amount: t.amount,
      discount: t.discount,
      balanceAfter: t.balanceAfter,
      partyId: t.partyId,
      description: t.description,
      userId: t.userId,
      createdAt: t.createdAt ?? DateTime.now(),
    )).toList();
  }

  @override
  Future<List<TransactionData>> getSafeTransactionsForDate(int safeId, DateTime since) async {
    final list = await (db.select(db.safeTransactions)
          ..where((t) => t.safeId.equals(safeId))
          ..where((t) => t.createdAt.isBiggerOrEqualValue(since)))
        .get();

    return list.map((t) => TransactionData(
      id: t.id,
      voucherNumber: t.voucherNumber,
      safeId: t.safeId,
      safeName: '',
      transactionType: t.transactionType,
      category: t.category,
      amount: t.amount,
      discount: t.discount,
      balanceAfter: t.balanceAfter,
      partyId: t.partyId,
      description: t.description,
      userId: t.userId,
      createdAt: t.createdAt ?? DateTime.now(),
    )).toList();
  }

  @override
  Future<TransactionData?> getLastClosingTransaction() async {
    final t = await (db.select(db.safeTransactions)
          ..where((t) => t.referenceType.equals('daily_closing'))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(1))
        .getSingleOrNull();

    if (t == null) return null;

    return TransactionData(
      id: t.id,
      voucherNumber: t.voucherNumber,
      safeId: t.safeId,
      safeName: '',
      transactionType: t.transactionType,
      category: t.category,
      amount: t.amount,
      discount: t.discount,
      balanceAfter: t.balanceAfter,
      partyId: t.partyId,
      description: t.description,
      userId: t.userId,
      createdAt: t.createdAt ?? DateTime.now(),
    );
  }

  @override
  Future<List<SafeData>> getSafesList() {
    return db.watchAllSafes().first.then((list) => list.map((s) => SafeData(
      id: s.id,
      name: s.name,
      safeType: s.safeType,
      balance: s.balance,
      isDefault: s.isDefault,
      isActive: s.isActive,
      bankName: s.bankName,
      accountNumber: s.accountNumber,
      costCenterId: s.costCenterId,
      branchId: s.branchId,
      linkedAccountId: s.linkedAccountId,
    )).toList());
  }

  @override
  Future<double> getCalculatedSafeBalance(int safeId) async {
    // Receipts (deposits) add to balance, Payments (withdrawals) subtract
    final result = await db.customSelect(
      'SELECT '
      'COALESCE(SUM(CASE WHEN transaction_type IN (?, ?, ?) THEN amount ELSE 0 END), 0) as total_in, '
      'COALESCE(SUM(CASE WHEN transaction_type IN (?, ?, ?) THEN amount ELSE 0 END), 0) as total_out '
      'FROM safe_transactions WHERE safe_id = ?',
      variables: [
        const Variable('receipt'),
        const Variable('sale'),
        const Variable('transfer_in'),
        const Variable('payment'),
        const Variable('expense'),
        const Variable('transfer_out'),
        Variable(safeId),
      ],
      readsFrom: {db.safeTransactions},
    ).getSingle();

    final totalIn = (result.data['total_in'] as num?)?.toDouble() ?? 0.0;
    final totalOut = (result.data['total_out'] as num?)?.toDouble() ?? 0.0;
    return totalIn - totalOut;
  }
}
