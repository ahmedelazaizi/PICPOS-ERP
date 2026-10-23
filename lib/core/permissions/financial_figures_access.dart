import '../navigation/screen_id.dart';

/// Permission codes that authorize monetary and balance figures per screen.
///
/// Each list contains the screen's view permission and any dedicated
/// figure/column permissions. Keep this registry exhaustive with
/// [screenActionCodes]; action-only grants must not appear here.
const screenFigurePermissionCodes = <ScreenId, List<String>>{
  ScreenId.offers: ['offers_view'],
  ScreenId.tables: ['tables_view'],
  ScreenId.bookings: ['bookings_view'],
  ScreenId.products: ['products_price_view', 'products_cost_view', 'products_stock_view'],
  ScreenId.categories: ['categories_view'],
  ScreenId.customers: ['customers_view'],
  ScreenId.parties: ['customers_view'],
  ScreenId.suppliers: ['customers_view', 'suppliers_view'],
  ScreenId.salesInvoices: ['sales_view', 'sales_amounts_view'],
  ScreenId.salesReturns: ['sales_return_view', 'sales_amounts_view'],
  ScreenId.purchases: ['purchases_view'],
  ScreenId.purchaseReturns: ['purchases_return_view', 'purchases_view'],
  ScreenId.inventory: ['inventory_view', 'products_cost_view', 'products_stock_view'],
  ScreenId.kitchen: ['kitchen_view'],
  ScreenId.loyalty: ['loyalty_view'],
  ScreenId.distribution: ['distribution_view'],
  ScreenId.manufacturing: ['manufacturing_view'],
  ScreenId.fixedAssets: ['assets_view'],
  ScreenId.eInvoice: ['einvoice_view'],
};

/// Whether [permissions] may see monetary figures on [screen].
///
/// System administrators bypass the registry; all other users need either the
/// screen's primary permission or an explicitly registered figure permission.
bool canSeeScreenFigures(
  Iterable<String> permissions,
  ScreenId screen, {
  bool bypass = false,
}) {
  if (bypass) return true;
  final held = permissions is Set<String> ? permissions : permissions.toSet();
  return screenFigurePermissionCodes[screen]?.any(held.contains) ?? false;
}

/// A stable placeholder used by non-widget figure formatters and exports.
const maskedFinancialFigure = '—';
