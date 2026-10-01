part of 'database.dart';

/// v183 — `sales_invoices.revenue_account_id`: the sales invoice's chosen
/// revenue account («حساب المبيعات»).
///
/// Raw SQL outside Drift's table model (no codegen run), following the
/// `products.tax_exempt` pattern (`product_tax_exempt_schema.dart`).
///
/// Semantics (owner decision, Phase C2):
/// • `NULL` ⇒ existing behaviour — the sales JE credits the account mapped
///   for purpose `'sales'`, and its return debits the `'sales_return'`
///   mapping. Every invoice created before v183 is `NULL`, so old books are
///   untouched.
/// • set ⇒ the sales JE credits THIS account, and a return of the invoice
///   debits the SAME account (see [resolveSalesRevenueAccountOverride]).
///
/// Travels with the invoice: the generic `SELECT *` delta pull, the
/// `/api/sales` snapshot (`revenueAccountId`), and the client sale push
/// (`SyncSaleRequest.revenueAccountId`).
extension SalesInvoiceRevenueAccountSchema on AppDatabase {
  Future<void> ensureSalesInvoiceRevenueAccountSchema() async {
    if (_isPostgres) {
      await customStatement(
        'ALTER TABLE sales_invoices ADD COLUMN IF NOT EXISTS '
        'revenue_account_id INTEGER',
      );
      return;
    }
    final columns =
        await customSelect('PRAGMA table_info(sales_invoices)').get();
    if (columns.any((c) => c.data['name'] == 'revenue_account_id')) return;
    try {
      await customStatement(
        'ALTER TABLE sales_invoices ADD COLUMN revenue_account_id INTEGER',
      );
    } catch (error) {
      if (!isIdempotentMigrationError(error.toString())) rethrow;
    }
  }

  /// The raw stored value — `null` when unset (or the invoice is missing).
  Future<int?> getSalesInvoiceRevenueAccountId(int invoiceId) async {
    final row = await customSelect(
      'SELECT revenue_account_id FROM sales_invoices WHERE id = ?',
      variables: [Variable<int>(invoiceId)],
    ).getSingleOrNull();
    final value = row?.data['revenue_account_id'];
    return value is num ? value.toInt() : null;
  }

  /// Stores (or clears, with `null`) the invoice's revenue account. A no-op
  /// write is skipped so sync re-applies don't bump update triggers.
  Future<void> setSalesInvoiceRevenueAccountId(
    int invoiceId,
    int? accountId,
  ) async {
    // Compared in Dart, not SQL: `IS NOT ?` is SQLite-only (PG needs
    // `IS DISTINCT FROM`), and this runs on both engines.
    if (await getSalesInvoiceRevenueAccountId(invoiceId) == accountId) return;
    await customUpdate(
      'UPDATE sales_invoices SET revenue_account_id = ? WHERE id = ?',
      variables: [Variable<int>(accountId), Variable<int>(invoiceId)],
      updates: {salesInvoices},
    );
  }

  /// Every account the «حساب المبيعات» field may offer: active, postable
  /// (`detail`) revenue accounts, ordered by code.
  Future<List<Account>> getActiveRevenueDetailAccounts() {
    return (select(accounts)
          ..where((a) =>
              a.accountType.equals('revenue') &
              a.accountNature.equals('detail') &
              a.isActive.equals(true) &
              a.deletedAt.isNull())
          ..orderBy([(a) => OrderingTerm.asc(a.code)]))
        .get();
  }

  /// The revenue account a sales JE (or its return) must use INSTEAD of the
  /// mapped default — `null` ⇒ keep the mapped default.
  ///
  /// [invoiceId] is the sale row. When that row is itself a return
  /// (`sale_type = 'return'`, the POS quick-return shape) and carries no
  /// account of its own, the original invoice — linked through the note
  /// written by `localReturnLinkNote` — is consulted, so a return always
  /// mirrors the account its original sale credited.
  ///
  /// A stored id that no longer resolves to an active revenue account falls
  /// back to `null` (mapped default) rather than posting to a dead account.
  Future<Account?> resolveSalesRevenueAccountOverride(int invoiceId) async {
    final row = await customSelect(
      'SELECT revenue_account_id, sale_type, notes FROM sales_invoices '
      'WHERE id = ?',
      variables: [Variable<int>(invoiceId)],
    ).getSingleOrNull();
    if (row == null) return null;
    var raw = row.data['revenue_account_id'];
    if (raw is! num && row.data['sale_type'] == 'return') {
      final notes = row.data['notes'] as String?;
      // Global id first (see `return_original_link.dart`): a numeric id only
      // means something on the store that wrote it.
      final gid = returnOriginalGidFromNote(notes);
      if (gid != null) {
        final orig = await customSelect(
          'SELECT revenue_account_id FROM sales_invoices WHERE global_id = ?',
          variables: [Variable<String>(gid)],
        ).getSingleOrNull();
        raw = orig?.data['revenue_account_id'];
      }
      final originalId = returnOriginalIdFromNote(notes);
      if (raw is! num &&
          gid == null &&
          originalId != null &&
          originalId != invoiceId) {
        raw = await getSalesInvoiceRevenueAccountId(originalId);
      }
    }
    if (raw is! num) return null;
    final accountId = raw.toInt();
    final acc = await (select(accounts)
          ..where((a) => a.id.equals(accountId)))
        .getSingleOrNull();
    if (acc == null ||
        !acc.isActive ||
        acc.deletedAt != null ||
        acc.accountType != 'revenue' ||
        acc.accountNature == 'view') {
      return null;
    }
    return acc;
  }
}
