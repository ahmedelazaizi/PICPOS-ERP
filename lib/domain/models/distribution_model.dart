import '../../core/i18n/tr.dart';

// نموذجُ التوزيع — المرحلة و (بندا المالك ١٢ و١٨).
//
// القاعدةُ الملزمة: **منطقةُ توزيعٍ ← مسارٌ بمندوبٍ واحد ← عملاءُ مرتَّبون**.
// العميلُ على مسارٍ واحدٍ في كلّ لحظة، ومندوبُه **مشتقٌّ** من مندوب مساره
// ولا يُخزَّن على الطرف. والمستنداتُ تختم المندوبَ والمسارَ لحظةَ إنشائها،
// فإعادةُ التوزيع لا تعيد كتابةَ التاريخ.
//
// يعيش النموذجُ هنا لا في الـDAO: شاشاتُ العرض ممنوعةٌ من استيراد
// `data/database` (‏`presentation_db_import_guard`).

/// A rejected distribution operation. [key] is the Arabic catalog key.
class DistributionException implements Exception {
  DistributionException(this.key, [this.params = const {}]);
  final String key;
  final Map<String, Object?> params;

  String get message => tr(key, params);

  @override
  String toString() => message;
}

/// One row of `distribution_areas` — separate from the branch-grouping
/// `regions` table.
class DistributionArea {
  const DistributionArea({
    required this.id,
    required this.name,
    this.code,
    this.boundary,
    this.branchId,
    this.isActive = true,
  });
  final int id;
  final String name;
  final String? code;

  /// Free-text boundary description (streets, landmarks).
  final String? boundary;
  final int? branchId;
  final bool isActive;
}

/// A `sales_routes` row with its v185 raw columns resolved.
class DistributionRoute {
  const DistributionRoute({
    required this.id,
    required this.name,
    this.description,
    this.areaId,
    this.areaName,
    this.repEmployeeId,
    this.repName,
    this.visitDays = const [],
    this.legacyArea,
    this.isActive = true,
    this.customerCount = 0,
  });
  final int id;
  final String name;
  final String? description;
  final int? areaId;
  final String? areaName;

  /// The ONE responsible rep (`sales_routes.sales_rep_id`).
  final int? repEmployeeId;
  final String? repName;

  /// ISO weekdays (1 = Monday … 7 = Sunday).
  final List<int> visitDays;

  /// The pre-v185 free-text `area` — display only.
  final String? legacyArea;
  final bool isActive;
  final int customerCount;
}

/// A customer's current place on a route (`route_customers`, open row).
class RouteCustomer {
  const RouteCustomer({
    required this.rowId,
    required this.routeId,
    required this.customerId,
    required this.customerName,
    required this.sequence,
    required this.effectiveFrom,
    this.effectiveTo,
    this.phone,
    this.balance = 0,
  });
  final int rowId;
  final int routeId;
  final int customerId;
  final String customerName;
  final int sequence;
  final DateTime effectiveFrom;
  final DateTime? effectiveTo;
  final String? phone;
  final double balance;
}

/// Route / area / rep derived for one customer from its current route.
class CustomerRouteInfo {
  const CustomerRouteInfo({
    required this.customerId,
    required this.routeId,
    required this.routeName,
    this.areaId,
    this.areaName,
    this.repEmployeeId,
    this.repName,
  });
  final int customerId;
  final int routeId;
  final String routeName;
  final int? areaId;
  final String? areaName;
  final int? repEmployeeId;
  final String? repName;
}

/// The rep + route a document is stamped with at creation time.
class RepStamp {
  const RepStamp({this.repEmployeeId, this.routeId});
  final int? repEmployeeId;
  final int? routeId;
  bool get isEmpty => repEmployeeId == null && routeId == null;
}

/// A rep's working resources (`rep_resources`).
class RepResources {
  const RepResources({
    required this.employeeId,
    this.vanWarehouseId,
    this.custodySafeId,
  });
  final int employeeId;
  final int? vanWarehouseId;
  final int? custodySafeId;
}

/// One `route_rep_history` row.
class RouteRepHistoryEntry {
  const RouteRepHistoryEntry({
    required this.routeId,
    required this.repEmployeeId,
    required this.effectiveFrom,
    this.effectiveTo,
  });
  final int routeId;
  final int repEmployeeId;
  final DateTime effectiveFrom;
  final DateTime? effectiveTo;
}

/// Report 1 — one rep's period summary, from the STAMPED rep.
class RepSalesSummaryRow {
  const RepSalesSummaryRow({
    required this.repEmployeeId,
    required this.repName,
    this.invoiceCount = 0,
    this.netSales = 0,
    this.returns = 0,
    this.collections = 0,
    this.fieldCollections = 0,
    this.handedOver = 0,
  });
  final int repEmployeeId;
  final String repName;
  final int invoiceCount;

  /// Σ sales invoices total (returns excluded).
  final double netSales;

  /// Σ sales returns (return invoices + standalone `SRET` rows).
  final double returns;

  /// Σ receipt vouchers from the rep's customers.
  final double collections;

  /// Σ `sales_rep_collections` (field collections).
  final double fieldCollections;

  /// Σ cash handed over from the custody safe to the treasury.
  final double handedOver;
}

/// Report 2 — one stamped document line.
class RepTransactionRow {
  const RepTransactionRow({
    required this.date,
    required this.kind,
    required this.number,
    required this.amount,
    this.repEmployeeId,
    this.customerName,
    this.routeName,
    this.paid = 0,
  });
  final DateTime date;

  /// `invoice` | `return` | `receipt` | `collection` | `handover`.
  final String kind;
  final String number;
  final double amount;
  final int? repEmployeeId;
  final String? customerName;
  final String? routeName;
  final double paid;
  double get remaining => kind == 'invoice' ? amount - paid : 0;
}

/// Report 3 — one customer on a route.
class RouteCoverageRow {
  const RouteCoverageRow({
    required this.routeId,
    required this.routeName,
    required this.customerId,
    required this.customerName,
    required this.sequence,
    this.repName,
    this.areaName,
    this.lastInvoiceDate,
    this.lastVisitDate,
    this.balance = 0,
  });
  final int routeId;
  final String routeName;
  final int customerId;
  final String customerName;
  final int sequence;
  final String? repName;
  final String? areaName;
  final DateTime? lastInvoiceDate;
  final DateTime? lastVisitDate;
  final double balance;
}

/// Report 4 — one product line in a rep's van warehouse.
class VanStockRow {
  const VanStockRow({
    required this.repEmployeeId,
    required this.repName,
    required this.warehouseId,
    required this.warehouseName,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.averageCost,
  });
  final int repEmployeeId;
  final String repName;
  final int warehouseId;
  final String warehouseName;
  final int productId;
  final String productName;
  final double quantity;
  final double averageCost;
  double get value => quantity * averageCost;
}

/// Parses the `visit_days` CSV ("1,3,5") into sorted ISO weekdays.
List<int> parseVisitDays(String? csv) {
  if (csv == null || csv.trim().isEmpty) return const [];
  final days = <int>{};
  for (final part in csv.split(',')) {
    final d = int.tryParse(part.trim());
    if (d != null && d >= 1 && d <= 7) days.add(d);
  }
  return days.toList()..sort();
}

/// The `visit_days` CSV for [days] (`null` when empty).
String? encodeVisitDays(Iterable<int> days) {
  final list = days.where((d) => d >= 1 && d <= 7).toSet().toList()..sort();
  return list.isEmpty ? null : list.join(',');
}
