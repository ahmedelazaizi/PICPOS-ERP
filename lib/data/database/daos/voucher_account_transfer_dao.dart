part of '../database.dart';

/// المرحلة هـ / E2 — طرفا السند من **دليل الحسابات** (قرارُ المالك).
///
/// • المستفيدُ: أيُّ حسابٍ تفصيليٍّ نشط. فإن كان حسابَ طرفٍ (عميلٍ/مورّد)
///   رُدَّ إلى الطرف نفسِه ليبقى رصيدُه وكشفُه كما هما اليوم.
/// • الخزينة: أيُّ حسابٍ تفصيليٍّ نشط. فإن كان حسابَ خزنةٍ رُدَّ إلى الخزنة
///   ومضى السندُ في مساره المعتاد؛ وإلّا فهو **تحويلٌ محاسبيّ** — قيدٌ بلا
///   حركةِ خزنة ([createAccountTransferVoucher]).
extension VoucherAccountTransferDao on AppDatabase {
  /// Active, postable (`detail`) accounts ordered by code — the picker list.
  Future<List<Account>> getActiveDetailAccounts() {
    return (select(accounts)
          ..where((a) =>
              a.accountNature.equals('detail') &
              a.isActive.equals(true) &
              a.deletedAt.isNull())
          ..orderBy([(a) => OrderingTerm.asc(a.code)]))
        .get();
  }

  /// Picker rows: every active detail account with the party whose
  /// sub-account it is and the safe that posts to it. [safeIds] limits the
  /// safe side to the user's branch scope (`null` = all).
  Future<List<({int id, String code, String name, int? partyId, int? safeId})>>
      voucherAccountOptions({Set<int>? safeIds}) async {
    final accountRows = await getActiveDetailAccounts();
    final partyRows = await select(parties).get();
    final safeRows = (await (select(safes)..where((s) => s.deletedAt.isNull()))
            .get())
        .where((s) => safeIds == null || safeIds.contains(s.id))
        .toList();
    final partyByAccount = <int, int>{
      for (final p in partyRows)
        if (p.accountId != null) p.accountId!: p.id,
    };
    final safeByAccount = <int, int>{};
    for (final s in safeRows) {
      if (s.linkedAccountId != null) safeByAccount[s.linkedAccountId!] ??= s.id;
    }
    final byCode = {for (final a in accountRows) a.code: a.id};
    for (final s in safeRows) {
      if (s.linkedAccountId != null) continue;
      final id = byCode[kSafeTypeAccountCode[s.safeType]];
      if (id != null) safeByAccount[id] ??= s.id;
    }
    return [
      for (final a in accountRows)
        (
          id: a.id,
          code: a.code,
          name: a.name,
          partyId: partyByAccount[a.id],
          safeId: safeByAccount[a.id],
        ),
    ];
  }

  /// The party whose own sub-account is [accountId] — `null` otherwise.
  Future<int?> partyIdForAccount(int accountId) async {
    final row = await (select(parties)
          ..where((p) => p.accountId.equals(accountId) & p.deletedAt.isNull())
          ..limit(1))
        .getSingleOrNull();
    return row?.id;
  }

  /// The safe that posts to [accountId] — its explicit `linked_account_id`
  /// first, else a safe whose type maps to that account code. `null` means
  /// the account is not a cash/bank safe account.
  Future<int?> safeIdForAccount(int accountId) async {
    final all = await (select(safes)..where((s) => s.deletedAt.isNull())).get();
    for (final s in all) {
      if (s.linkedAccountId == accountId) return s.id;
    }
    final account = await accountingDao.getAccountById(accountId);
    if (account == null) return null;
    for (final s in all) {
      if (s.linkedAccountId == null &&
          kSafeTypeAccountCode[s.safeType] == account.code) {
        return s.id;
      }
    }
    return null;
  }

  /// سندٌ تحويليّ: قيدٌ بين حساب الخزينة المختار والمستفيد، **بلا حركةِ
  /// خزنة**. يُكتَب صفٌّ مستنديٌّ في `safe_transactions` بنوع
  /// `transfer_receipt`/`transfer_payment` ورصيدِ الخزنة كما هو — نفسُ نمط
  /// صفِّ سند الشيك — ليظهر في السجلّ وكشف الطرف ويُرقَّم بنفس العدّاد.
  Future<int> createAccountTransferVoucher({
    required bool isReceipt,
    required double amount,
    required int treasuryAccountId,
    required String category,
    double discount = 0,
    int? beneficiaryAccountId,
    int? partyId,
    String? description,
    int? userId,
    int? costCenterId,
    int? documentSafeId,
    String? globalId,
    int? operatingBranchId,
    int? currencyId,
    double? paymentRate,
    double? foreignAmount,
  }) {
    return transaction(() async {
      await accountingDao.validateFinancialPeriod(DateTime.now(),
          operation: isReceipt ? 'سند قبض' : 'سند صرف');
      if (amount <= 0) throw StateError('amount must be > 0');

      final treasury =
          await accountingDao.getLeafAccountById(treasuryAccountId);
      if (treasury == null) {
        throw StateError('treasury account $treasuryAccountId not postable');
      }
      Account? other;
      if (beneficiaryAccountId != null) {
        other = await accountingDao.getLeafAccountById(beneficiaryAccountId);
      }
      if (other == null && partyId != null) {
        other = await _resolveVoucherPartyAccount(
            partyId: partyId, isReceipt: isReceipt);
      }
      if (other == null) {
        throw StateError('beneficiary account required for a transfer voucher');
      }

      Safe? docSafe;
      if (documentSafeId != null) {
        docSafe = await (select(safes)
              ..where((s) => s.id.equals(documentSafeId)))
            .getSingleOrNull();
      }
      docSafe ??= await getDefaultSafe();
      docSafe ??= await (select(safes)..limit(1)).getSingleOrNull();
      if (docSafe == null) throw StateError('no safe to file the voucher under');

      final gid = globalId ?? UuidV7.generate();
      final voucherNumber = await generateInvoiceNumber(isReceipt ? 'RV' : 'PV');
      final txnId = await into(safeTransactions).insert(
        SafeTransactionsCompanion.insert(
          voucherNumber: voucherNumber,
          safeId: docSafe.id,
          transactionType: isReceipt
              ? kAccountTransferReceiptTxnType
              : kAccountTransferPaymentTxnType,
          category: category,
          amount: amount,
          discount: Value(discount),
          // رصيدُ الخزنة كما هو — لا حركةَ عليها.
          balanceAfter: docSafe.balance,
          partyId: Value(partyId),
          description: Value(description),
          userId: Value(userId),
          costCenterId: Value(costCenterId),
          globalId: Value(gid),
          currencyId: Value(currencyId),
          exchangeRate: Value(paymentRate),
          foreignAmount: Value(foreignAmount),
        ),
      );
      await customUpdate(
        'UPDATE safe_transactions SET treasury_account_id = ? WHERE id = ?',
        variables: [Variable<int>(treasury.id), Variable<int>(txnId)],
        updates: {safeTransactions},
      );

      // رصيدُ الطرف — عينُ ما يفعله السندُ النقديّ.
      if (partyId != null) {
        await adjustPartyBalance(partyId, -(amount + discount));
      }

      final discountCode = isReceipt ? '5205' : '4202';
      final discountAccount = discount > 0
          ? await accountingDao.getAccountByCode(discountCode)
          : null;
      if (discount > 0 && discountAccount == null) {
        throw StateError('discount account $discountCode missing');
      }
      final text = description ?? (isReceipt ? 'سند قبض' : 'سند صرف');
      final total = amount + discount;
      final lines = <JournalLine>[
        if (isReceipt) ...[
          JournalLine(
              accountId: treasury.id, debit: amount, credit: 0, description: text),
          if (discountAccount != null)
            JournalLine(
                accountId: discountAccount.id,
                debit: discount,
                credit: 0,
                description: text),
          JournalLine(
              accountId: other.id, debit: 0, credit: total, description: text),
        ] else ...[
          JournalLine(
              accountId: other.id, debit: total, credit: 0, description: text),
          JournalLine(
              accountId: treasury.id, debit: 0, credit: amount, description: text),
          if (discountAccount != null)
            JournalLine(
                accountId: discountAccount.id,
                debit: 0,
                credit: discount,
                description: text),
        ],
      ];
      await accountingDao.createJournalEntry(
        description: text,
        date: DateTime.now(),
        lines: lines,
        referenceType: isReceipt ? 'receipt_voucher' : 'payment_voucher',
        referenceId: txnId,
        costCenterId: costCenterId,
        branchId: operatingBranchId ?? docSafe.branchId,
        globalId: '${isReceipt ? 'je-rcpt' : 'je-pmt'}-$gid',
      );
      return txnId;
    });
  }
}
