part of 'database.dart';

/// v182 — `products.tax_exempt`: the product form's «معفى من الضريبة» flag.
///
/// Raw SQL outside Drift's table model (no codegen run). Tax CALCULATION does
/// not read this column: `products.tax_rate` stays the single value every
/// sale path, report and e-invoice reads, written exactly as the old tax
/// dropdown wrote it. The flag only lets the product dialogs tell an exempt
/// item (rate 0, flag 1) from a company-default item (rate 0, flag 0) when
/// reopening it. See `lib/core/tax/product_tax_choice.dart`.
///
/// Not part of the product sync payload: on another device an exempt item
/// reopens as "company default" — the same stored tax_rate, so the same tax.
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

  Future<void> setProductTaxExempt(int productId, bool exempt) async {
    await customStatement(
      'UPDATE products SET tax_exempt = ? WHERE id = ?',
      [exempt ? 1 : 0, productId],
    );
  }
}
