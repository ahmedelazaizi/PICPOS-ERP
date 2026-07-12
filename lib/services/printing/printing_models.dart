class InvoiceItem {
  final String name;
  final double quantity;
  final double price;
  final double total;
  final String? barcode;
  final String? note;
  /// Issue 2 (Feature 019): when true, this row represents a category-section
  /// header in a held-order print (the [name] field carries the category
  /// label, e.g. "مأكولات"). The thermal template renders these as
  /// centered, bold dividers and skips qty/price/total columns. Real items
  /// (the default false) render normally.
  final bool isCategoryHeader;

  InvoiceItem({
    required this.name,
    required this.quantity,
    required this.price,
    required this.total,
    this.barcode,
    this.note,
    this.isCategoryHeader = false,
  });
}

class StatementItem {
  final DateTime date;
  final String description;
  final double debit;
  final double credit;
  final double balance;

  StatementItem({
    required this.date,
    required this.description,
    required this.debit,
    required this.credit,
    required this.balance,
  });
}
