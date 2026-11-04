part of '../database.dart';

typedef _FixedAssetCashPaymentRequest = ({
  int? entryId,
  int? contraAccountId,
  Account account,
  Safe? safe,
  int assetId,
  double amount,
  int? costCenterId,
});

extension FixedAssetCashRoutingDao on AppDatabase {
  Future<({Account? account, Safe? safe})> _resolveFixedAssetFunding(
    int? contraAccountId,
    int? branchId,
  ) async {
    if (contraAccountId != null) {
      return (account: await accountingDao.getAccountById(contraAccountId), safe: null);
    }
    final safe = await _findLinkedCashSafe(branchId);
    final linkedAccount = safe?.linkedAccountId == null
        ? null
        : await accountingDao.getAccountById(safe!.linkedAccountId!);
    return (
      account: linkedAccount ?? await _assetGetAccountByCode('1111'),
      safe: safe,
    );
  }

  Future<Safe?> _findLinkedCashSafe(int? branchId) async {
    if (branchId != null) {
      final branchSafe = await _findActiveCashSafeInBranch(branchId);
      if (branchSafe != null) return branchSafe;
    }
    return _findDefaultActiveCashSafe();
  }

  Future<Safe?> _findActiveCashSafeInBranch(int branchId) =>
      (select(safes)
            ..where((safe) =>
                safe.safeType.equals('cash') &
                safe.isActive.equals(true) &
                safe.branchId.equals(branchId) &
                safe.linkedAccountId.isNotNull())
            ..orderBy([
              (safe) => OrderingTerm(
                  expression: safe.isDefault, mode: OrderingMode.desc),
            ])
            ..limit(1))
          .getSingleOrNull();

  Future<Safe?> _findDefaultActiveCashSafe() =>
      (select(safes)
            ..where((safe) =>
                safe.safeType.equals('cash') &
                safe.isActive.equals(true) &
                safe.linkedAccountId.isNotNull())
            ..orderBy([
              (safe) => OrderingTerm(
                  expression: safe.isDefault, mode: OrderingMode.desc),
            ])
            ..limit(1))
          .getSingleOrNull();

  Future<void> _recordFixedAssetCashPayment(
    _FixedAssetCashPaymentRequest request,
  ) async {
    if (!_isFixedAssetCashPayment(request, request.safe)) return;
    final safe = request.safe!;
    final newBalance = safe.balance - request.amount;
    await _insertFixedAssetSafeTransaction(request, safe, newBalance);
    await adjustSafeBalance(safe.id, -request.amount);
  }

  bool _isFixedAssetCashPayment(
    _FixedAssetCashPaymentRequest request,
    Safe? safe,
  ) =>
      request.entryId != null &&
      request.contraAccountId == null &&
      safe != null &&
      safe.linkedAccountId == request.account.id;

  Future<void> _insertFixedAssetSafeTransaction(
    _FixedAssetCashPaymentRequest request,
    Safe safe,
    double balanceAfter,
  ) async {
    await into(safeTransactions).insert(
      SafeTransactionsCompanion.insert(
        // allow-bare-generateInvoiceNumber: the only caller (_recordFixedAssetCashPayment in fixed_assets_dao_ext.dart) runs inside the asset-purchase transaction(...)
        voucherNumber: await generateInvoiceNumber('PV'),
        safeId: safe.id,
        transactionType: 'payment',
        category: 'asset_purchase',
        amount: request.amount,
        balanceAfter: balanceAfter,
        referenceType: const Value('fixed_asset'),
        referenceId: Value(request.assetId),
        costCenterId: Value(request.costCenterId),
      ),
    );
  }
}
