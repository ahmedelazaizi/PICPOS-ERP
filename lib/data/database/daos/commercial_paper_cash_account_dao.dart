part of '../database.dart';

extension CommercialPaperCashAccountDao on AppDatabase {
  Future<({Account? cash, Account? bank})> _cpResolvePaperCashAccounts(
    CommercialPaperData paper,
    String oldStatus,
    String newStatus,
    Account? counterOverride,
  ) async {
    final defaultCash = await _cpResolveAccount('cash');
    final defaultBank = await _cpResolveAccount('bank');
    final cash = counterOverride ?? defaultCash;
    final bank = counterOverride ?? defaultBank;
    if (counterOverride != null ||
        (newStatus != 'cashed' && newStatus != 'collected')) {
      return (cash: cash, bank: bank);
    }
    return _cpResolvePaperCollectionAccounts(paper, oldStatus, defaultCash, defaultBank);
  }

  Future<({Account? cash, Account? bank})> _cpResolvePaperCollectionAccounts(
    CommercialPaperData paper,
    String oldStatus,
    Account? defaultCash,
    Account? defaultBank,
  ) {
    final viaBank = paper.direction != 'received' ||
        oldStatus == 'deposited' ||
        oldStatus == 'deposited_for_collection';
    return viaBank
        ? _cpResolveBankCollectionAccounts(paper, defaultCash, defaultBank)
        : _cpResolveCashCollectionAccounts(paper, defaultCash, defaultBank);
  }

  Future<({Account? cash, Account? bank})> _cpResolveCashCollectionAccounts(
    CommercialPaperData paper,
    Account? defaultCash,
    Account? defaultBank,
  ) async {
    final safe = await _cpResolveSafeForPaper(paper, bank: false);
    final linked = safe?.linkedAccountId == null
        ? null
        : await accountingDao.getAccountById(safe!.linkedAccountId!);
    return (cash: linked ?? defaultCash, bank: defaultBank);
  }

  Future<({Account? cash, Account? bank})> _cpResolveBankCollectionAccounts(
    CommercialPaperData paper,
    Account? defaultCash,
    Account? defaultBank,
  ) async {
    final safe = await _cpResolveSafeForPaper(paper, bank: true);
    final linked = safe?.linkedAccountId == null
        ? null
        : await accountingDao.getAccountById(safe!.linkedAccountId!);
    return (cash: defaultCash, bank: linked ?? defaultBank);
  }
}
