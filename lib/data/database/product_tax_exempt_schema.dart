part of 'database.dart';

/// v182 — `products.tax_exempt`: the product form's «معفى من الضريبة» flag.
///
/// Raw SQL outside Drift's table model (no codegen run). Tells an exempt item
/// (rate 0, flag 1) from a company-default item (rate 0, flag 0). See
/// `lib/core/tax/product_tax_choice.dart`.
///
/// B3 (owner decision): the flag now drives money — an exempt item is taxed
/// at 0 % on every sale/return/table/POS/purchase path through
/// `effectiveItemTaxRate` (`lib/core/tax/effective_item_tax_rate.dart`), and
/// e-invoices classify its lines as exempt. It therefore travels with the
/// product: `/api/products` snapshots (`taxExempt`), the client create/update
/// push, and the generic `SELECT *` delta pull.
extension ProductTaxExemptSchema on AppDatabase {
  Future<void> ensureProductTaxExemptSchema() async {
    if (_isPostgres) {
      await customStatement(
        'ALTER TABLE products ADD COLUMN IF NOT EXISTS tax_exempt INTEGER '
        'NOT NULL DEFAULT 0',
      );
      return;
    }
    final columns =
        await customSelect('PRAGMA table_info(products)').get();
    if (columns.any((c) => c.data['name'] == 'tax_exempt')) return;
    try {
      await customStatement(
        'ALTER TABLE products ADD COLUMN tax_exempt INTEGER NOT NULL DEFAULT 0',
      );
    } catch (error) {
      if (!isIdempotentMigrationError(error.toString())) rethrow;
    }
  }

  Future<bool> getProductTaxExempt(int productId) async {
    final row = await customSelect(
      'SELECT tax_exempt FROM products WHERE id = ?',
      variables: [Variable<int>(productId)],
    ).getSingleOrNull();
    final value = row?.data['tax_exempt'];
    return value == true || (value is num && value != 0);
  }

  /// B3 — ids among [productIds] whose `tax_exempt` flag is set. One query
  /// for a whole cart/invoice; an empty input never touches the database.
  Future<Set<int>> getTaxExemptProductIds(Iterable<int> productIds) async {
    final ids = productIds.toSet().toList();
    if (ids.isEmpty) return <int>{};
    final placeholders = List.filled(ids.length, '?').join(', ');
    final rows = await customSelect(
      'SELECT id FROM products WHERE tax_exempt <> 0 AND id IN ($placeholders)',
      variables: [for (final id in ids) Variable<int>(id)],
      readsFrom: {products},
    ).get();
    return {for (final r in rows) (r.data['id'] as num).toInt()};
  }

  Future<void> setProductTaxExempt(int productId, bool exempt) async {
    // `customUpdate` with `updates:` so watched product streams (POS grid,
    // product lists) re-emit and pick up the new flag. A no-op write is
    // skipped so sync re-applies don't bump the row's update triggers.
    final value = exempt ? 1 : 0;
    await customUpdate(
      'UPDATE products SET tax_exempt = ? WHERE id = ? AND tax_exempt <> ?',
      variables: [
        Variable<int>(value),
        Variable<int>(productId),
        Variable<int>(value),
      ],
      updates: {products},
    );
  }
}
