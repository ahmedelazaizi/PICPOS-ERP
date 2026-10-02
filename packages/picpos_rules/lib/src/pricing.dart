/// Price resolution and sales-return math (desktop rules, see each function).
/// Fixture: `docs/mobile/fixtures/pricing_parity.json`.
library;

import 'tax.dart';

/// One active-candidate price-list row for a product.
class PriceListEntry {
  PriceListEntry({
    required this.listGlobalId,
    required this.isDefault,
    required this.isActive,
    required this.price,
    required this.minQuantity,
    this.startDate,
    this.endDate,
    this.listOrder = 0,
  });
  final String listGlobalId;
  final bool isDefault;
  final bool isActive;
  final double price;
  final double minQuantity;

  /// `YYYY-MM-DD` (inclusive) or null.
  final String? startDate;
  final String? endDate;

  /// Tie-break between lists (cloud: price_lists.id).
  final int listOrder;
}

class ResolvedPrice {
  const ResolvedPrice(this.price, this.source, [this.listGlobalId]);
  final double price;

  /// `price_level` | `price_list` | `sale_price`.
  final String source;
  final String? listGlobalId;
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Unit price for a customer/product/quantity:
/// 1. customer price level `wholesale` and product wholesale price > 0 →
///    wholesale price (desktop POS `CartController.resolveProductPrice`);
/// 2. active price lists (is_active, start ≤ today ≤ end), default list first
///    then [PriceListEntry.listOrder]; in the first list that has a row with
///    `min_quantity ≤ quantity`, the row with the highest `min_quantity` wins
///    (desktop `MultiCurrencyPricelistDao.resolveProductPrice`);
/// 3. the product sale price.
ResolvedPrice resolveUnitPrice({
  required double salePrice,
  double? wholesalePrice,
  String? priceLevel,
  required double quantity,
  required DateTime today,
  List<PriceListEntry> entries = const [],
}) {
  if (priceLevel == 'wholesale' && (wholesalePrice ?? 0) > 0) {
    return ResolvedPrice(wholesalePrice!, 'price_level');
  }
  final day = _ymd(today);
  final valid = entries
      .where((e) =>
          e.isActive &&
          (e.startDate == null || e.startDate!.compareTo(day) <= 0) &&
          (e.endDate == null || e.endDate!.compareTo(day) >= 0))
      .toList();
  final lists = <String, List<PriceListEntry>>{};
  for (final e in valid) {
    lists.putIfAbsent(e.listGlobalId, () => []).add(e);
  }
  final ordered = lists.entries.toList()
    ..sort((a, b) {
      final ad = a.value.first.isDefault, bd = b.value.first.isDefault;
      if (ad != bd) return ad ? -1 : 1;
      return a.value.first.listOrder.compareTo(b.value.first.listOrder);
    });
  for (final l in ordered) {
    final fits = l.value.where((e) => e.minQuantity <= quantity + 1e-9).toList()
      ..sort((a, b) => b.minQuantity.compareTo(a.minQuantity));
    if (fits.isNotEmpty) return ResolvedPrice(fits.first.price, 'price_list', l.key);
  }
  return ResolvedPrice(salePrice, 'sale_price');
}

/// What was sold of one product on an invoice and what was already returned.
class SoldProduct {
  SoldProduct({
    required this.soldQty,
    required this.soldTotal,
    required this.soldTax,
    this.returnedQty = 0,
    this.returnedTotal = 0,
    this.returnedTax = 0,
  });
  final double soldQty, soldTotal, soldTax;
  final double returnedQty, returnedTotal, returnedTax;
  double get returnableQty => soldQty - returnedQty;
}

class ReturnLineAmounts {
  ReturnLineAmounts(this.total, this.tax, this.net);
  final double total, tax, net;
}

/// Desktop parity (`calculateReturnRefundTotal`, returns_repository_impl):
/// a returned line is valued from the original invoice line — total and tax
/// pro-rata by quantity (cloud invoices have no header discount or delivery
/// fee, so the desktop factor is 1). Returning the whole remaining quantity
/// takes exactly what is left, so partial returns never drift by rounding.
/// Returns null when [qty] exceeds the returnable quantity.
ReturnLineAmounts? returnLineAmounts(SoldProduct p, double qty, {int decimals = 2}) {
  double r(double v) => roundDp(v, decimals);
  if (qty <= 0 || qty > p.returnableQty + 1e-9) return null;
  double total, tax;
  if ((qty - p.returnableQty).abs() <= 1e-9) {
    total = r(p.soldTotal - p.returnedTotal);
    tax = r(p.soldTax - p.returnedTax);
  } else {
    total = r(p.soldTotal * qty / p.soldQty);
    tax = r(p.soldTax * qty / p.soldQty);
  }
  return ReturnLineAmounts(total, tax, r(total - tax));
}

/// Desktop `SalesReturnRefundSplit`: the return first offsets what is still
/// unpaid on the original invoice (customer balance ↓, credit note), the rest
/// is refunded in cash (original method; mobile invoices are cash/credit) from
/// the rep's custody safe.
({double arOffset, double cashRefund}) returnSettlement({
  required double invoiceTotal,
  required double invoicePaid,
  required double previousArOffset,
  required double returnTotal,
  int decimals = 2,
}) {
  double r(double v) => roundDp(v, decimals);
  var open = r(invoiceTotal - invoicePaid - previousArOffset);
  if (open < 0) open = 0;
  final ar = returnTotal < open ? returnTotal : open;
  return (arOffset: r(ar), cashRefund: r(returnTotal - ar));
}
