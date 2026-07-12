import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers.dart';

// ═══════════════════════════════════════════════════════════════════════════
// BOM PROVIDERS — قوائم المكونات
// ═══════════════════════════════════════════════════════════════════════════

/// Watch all active BOMs
final allBomsProvider = StreamProvider.autoDispose<List<BillOfMaterialData>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchBOMs();
});

/// Get BOM components for a specific BOM
final bomComponentsProvider = FutureProvider.autoDispose
    .family<List<BomComponentData>, int>((ref, bomId) {
  final db = ref.read(databaseProvider);
  return db.getBOMComponents(bomId);
});

// ═══════════════════════════════════════════════════════════════════════════
// MANUFACTURING ORDER PROVIDERS — أوامر الإنتاج
// ═══════════════════════════════════════════════════════════════════════════

/// Watch all manufacturing orders (optionally filtered by status)
final allManufacturingOrdersProvider = StreamProvider.autoDispose
    .family<List<ManufacturingOrderData>, String?>((ref, status) {
  final db = ref.watch(databaseProvider);
  return db.watchManufacturingOrders(status: status);
});

/// Watch all manufacturing orders (no filter)
final manufacturingOrdersProvider =
    StreamProvider.autoDispose<List<ManufacturingOrderData>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchManufacturingOrders();
});

/// Selected status filter for UI
class ManufacturingStatusFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? value) => state = value;
}

final manufacturingStatusFilterProvider =
    NotifierProvider<ManufacturingStatusFilterNotifier, String?>(
        ManufacturingStatusFilterNotifier.new);

/// Warehouse list for dropdown.
///
/// Spec 150 (BUG 5) — queries `warehouses` directly instead of through
/// branches_dao.dart, so it needs its own copy of the same defensive
/// same-name collapse (see `_dedupBranchesByName` there for the rationale).
final warehouseListProvider = FutureProvider.autoDispose<List<Warehouse>>((ref) async {
  final db = ref.read(databaseProvider);
  final rows = await (db.select(db.warehouses)
        ..where((w) => w.isActive.equals(true))
        ..orderBy([(w) => OrderingTerm.asc(w.name)]))
      .get();
  return _dedupWarehousesByName(rows);
});

List<Warehouse> _dedupWarehousesByName(List<Warehouse> rows) {
  final byName = <String, Warehouse>{};
  for (final row in rows) {
    final key = row.name.trim();
    final current = byName[key];
    if (current == null || _preferWarehouse(row, current)) {
      byName[key] = row;
    }
  }
  return byName.values.toList();
}

bool _preferWarehouse(Warehouse candidate, Warehouse current) {
  if (candidate.isSystemDefault != current.isSystemDefault) {
    return candidate.isSystemDefault;
  }
  if ((candidate.globalId != null) != (current.globalId != null)) {
    return candidate.globalId != null;
  }
  return candidate.id < current.id;
}

/// Spec 032 v3 — cached `warehouseId → name` lookup for table rendering
/// (analogous to `categoryNameMapProvider`). Tables `.watch` this and
/// receive a stable Map reference until warehouses change, instead of
/// rebuilding the Map literal on every parent rebuild.
final warehouseNameMapProvider = Provider.autoDispose<Map<int, String>>((ref) {
  final whs = ref.watch(warehouseListProvider);
  return whs.maybeWhen(
    data: (list) => {for (final w in list) w.id: w.name},
    orElse: () => const <int, String>{},
  );
});

/// Branch list for dropdown filters.
///
/// Spec 079 / B2 (2026-05-16): filter out soft-deleted (`deletedAt`)
/// and inactive (`isActive=false`) branches. Without this filter,
/// renamed/deleted branches like "الفرع الرئيسي" continued appearing
/// in every report's filter dropdown even after admins replaced them.
/// Mirrors `warehouseListProvider` above which already filters
/// `isActive=true`.
final branchListProvider = FutureProvider.autoDispose<List<Branche>>((ref) async {
  final db = ref.read(databaseProvider);
  final rows = await (db.select(db.branches)
        ..where((b) => b.isActive.equals(true) & b.deletedAt.isNull())
        ..orderBy([(b) => OrderingTerm.asc(b.name)]))
      .get();
  return _dedupBranchesByName(rows);
});

List<Branche> _dedupBranchesByName(List<Branche> rows) {
  final byName = <String, Branche>{};
  for (final row in rows) {
    final key = row.name.trim();
    final current = byName[key];
    if (current == null || _preferBranch(row, current)) {
      byName[key] = row;
    }
  }
  return byName.values.toList();
}

bool _preferBranch(Branche candidate, Branche current) {
  if (candidate.isSystemDefault != current.isSystemDefault) {
    return candidate.isSystemDefault;
  }
  if ((candidate.globalId != null) != (current.globalId != null)) {
    return candidate.globalId != null;
  }
  return candidate.id < current.id;
}

/// Weighted average cost per product from purchase invoices
/// Formula: SUM(quantity * unitCost) / SUM(quantity) for each product
final weightedAverageCostProvider =
    FutureProvider.autoDispose<Map<int, double>>((ref) async {
  final db = ref.read(databaseProvider);
  final results = await db.customSelect(
    '''
    SELECT product_id, 
           SUM(quantity * unit_cost) / SUM(quantity) as avg_cost
    FROM purchase_invoice_items
    GROUP BY product_id
    HAVING SUM(quantity) > 0
    ''',
    readsFrom: {db.purchaseInvoiceItems},
  ).get();

  final map = <int, double>{};
  for (final row in results) {
    final productId = row.data['product_id'] as int;
    final avgCost = (row.data['avg_cost'] as num?)?.toDouble() ?? 0.0;
    map[productId] = avgCost;
  }
  return map;
});

// ═══════════════════════════════════════════════════════════════════════════
// OPERATIONAL EXPENSES PROVIDERS — المصروفات التشغيلية
// ═══════════════════════════════════════════════════════════════════════════

/// Watch all expense categories
final expenseCategoriesProvider =
    StreamProvider.autoDispose<List<OpExpenseCategoryData>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchExpenseCategories();
});

/// Get active expense categories
final activeExpenseCategoriesProvider =
    FutureProvider.autoDispose<List<OpExpenseCategoryData>>((ref) {
  final db = ref.read(databaseProvider);
  return db.getActiveExpenseCategories();
});

/// Manufacturing order cost breakdown (by type)
final mfgOrderCostBreakdownProvider =
    FutureProvider.autoDispose.family<Map<String, double>, int>((ref, orderId) {
  final db = ref.read(databaseProvider);
  return db.getMfgOrderCostBreakdown(orderId);
});

/// Watch manufacturing order costs
final mfgOrderCostsProvider =
    StreamProvider.autoDispose.family<List<MfgOrderCostData>, int>((ref, orderId) {
  final db = ref.watch(databaseProvider);
  return db.watchMfgOrderCosts(orderId);
});

