part of 'database.dart';

/// v188 — `purchase_invoices.purchase_account_id`: the purchase invoice's
/// chosen «حساب المشتريات» (mirror of the sales side, v183).
///
/// Raw SQL outside Drift's table model (no codegen run), following
/// `sales_invoice_revenue_account_schema.dart`.
///
/// Semantics (owner decision, J1b):
/// • `NULL` ⇒ existing behaviour — the purchase JE debits the account mapped
///   for purpose `'inventory'` (raw-material lines keep their own mapping),
///   and a purchase return credits the same mapped account. Every invoice
///   created before v188 is `NULL`, so old books are untouched.
/// • set ⇒ the purchase JE debits THIS account for the whole goods cost, and
///   a return of the invoice credits the SAME account
///   (see [resolvePurchaseAccountOverride]). Stock/WAC movements are unchanged.
///
/// Travels with the invoice: the generic `SELECT *` delta pull, the
/// `/api/purchases` snapshot (`purchaseAccountId`), and the client purchase
/// push (`purchaseAccountId`).
extension PurchaseInvoicePurchaseAccountSchema on AppDatabase {
  Future<void> ensurePurchaseInvoicePurchaseAccountSchema() async {
    if (_isPostgres) {
      await customStatement(
        'ALTER TABLE purchase_invoices ADD COLUMN IF NOT EXISTS '
        'purchase_account_id INTEGER',
      );
      return;
    }
    final columns =
        await customSelect('PRAGMA table_info(purchase_invoices)').get();
    if (columns.any((c) => c.data['name'] == 'purchase_account_id')) return;
    try {
      await customStatement(
        'ALTER TABLE purchase_invoices ADD COLUMN purchase_account_id INTEGER',
      );
    } catch (error) {
      if (!isIdempotentMigrationError(error.toString())) rethrow;
    }
  }

  /// The raw stored value — `null` when unset (or the invoice is missing).
  Future<int?> getPurchaseInvoicePurchaseAccountId(int invoiceId) async {
    final row = await customSelect(
      'SELECT purchase_account_id FROM purchase_invoices WHERE id = ?',
      variables: [Variable<int>(invoiceId)],
    ).getSingleOrNull();
    final value = row?.data['purchase_account_id'];
    return value is num ? value.toInt() : null;
  }

  /// Stores (or clears, with `null`) the invoice's purchase account. A no-op
  /// write is skipped so sync re-applies don't bump update triggers.
  Future<void> setPurchaseInvoicePurchaseAccountId(
    int invoiceId,
    int? accountId,
  ) async {
    if (await getPurchaseInvoicePurchaseAccountId(invoiceId) == accountId) {
      return;
    }
    await customUpdate(
      'UPDATE purchase_invoices SET purchase_account_id = ? WHERE id = ?',
      variables: [Variable<int>(accountId), Variable<int>(invoiceId)],
      updates: {purchaseInvoices},
    );
  }

  /// Whether [a] may carry a purchase debit: active, postable (`detail`),
  /// not deleted, and an expense / asset account (purchases, COGS, inventory,
  /// fixed assets…). Revenue, liability and equity are clearly wrong.
  static bool isPurchaseDebitAccount(Account a) =>
      a.isActive &&
      a.deletedAt == null &&
      a.accountNature == 'detail' &&
      (a.accountType == 'expense' || a.accountType == 'asset');

  /// Every account the «حساب المشتريات» field may offer, ordered by code.
  Future<List<Account>> getActivePurchaseDebitAccounts() {
    return (select(accounts)
          ..where((a) =>
              a.accountType.isIn(const ['expense', 'asset']) &
              a.accountNature.equals('detail') &
              a.isActive.equals(true) &
              a.deletedAt.isNull())
          ..orderBy([(a) => OrderingTerm.asc(a.code)]))
        .get();
  }

  /// The account a purchase JE (or its return) must use INSTEAD of the mapped
  /// default — `null` ⇒ keep the mapped default.
  ///
  /// A stored id that no longer resolves to a suitable account falls back to
  /// `null` (mapped default) rather than posting to a dead account.
  Future<Account?> resolvePurchaseAccountOverride(int invoiceId) async {
    final raw = await getPurchaseInvoicePurchaseAccountId(invoiceId);
    if (raw == null) return null;
    final acc = await (select(accounts)..where((a) => a.id.equals(raw)))
        .getSingleOrNull();
    if (acc == null || !isPurchaseDebitAccount(acc)) return null;
    return acc;
  }
}
