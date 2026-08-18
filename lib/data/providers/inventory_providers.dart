import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb, listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers.dart';
import '../../core/diagnostics/perf_trace.dart';
import '../../core/logging/diagnostic_logger.dart';
import '../../domain/repositories/inventory_repository.dart';
import '../database/sync_interceptor.dart';
import '../../services/network_service.dart';
import '../../domain/entities/product_entity.dart';

// inventoryRepositoryProvider moved to repository_providers.dart

// ═══════════════════════════════════════════════════════════════════════════
// GLOBAL ACTIVE WAREHOUSE
// ═══════════════════════════════════════════════════════════════════════════

/// User-overridable active warehouse. Null = use default warehouse.
class ActiveWarehouseNotifier extends Notifier<int?> {
  @override
  int? build() => null;
  void set(int? id) => state = id;
}

final activeWarehouseOverrideProvider =
    NotifierProvider<ActiveWarehouseNotifier, int?>(ActiveWarehouseNotifier.new);

/// Resolved active warehouse ID. Resolution order:
///   1. Manual override (`activeWarehouseOverrideProvider`)
///   2. Per-branch setting `pos_default_warehouse_branch_$activeBranchId`
///      (Feature 006 #4 — lets HQ admins assign a default warehouse to each
///      branch's POS without touching every device.)
///   3. Global device setting `pos_default_warehouse_id`
///   4. Active branch warehouse (`isDefault`, else first warehouse in branch)
///   5. Repository default warehouse
final activeWarehouseIdProvider = FutureProvider<int>((ref) async {
  final override = ref.watch(activeWarehouseOverrideProvider);
  if (override != null) return override;

  final settingsRepo = ref.read(settingsRepositoryProvider);

  final branchId = await ref.watch(activeBranchIdProvider.future);
  if (branchId != null) {
    final perBranch = await settingsRepo.getSetting(
      'pos_default_warehouse_branch_$branchId',
    );
    if (perBranch != null && perBranch.isNotEmpty) {
      final id = int.tryParse(perBranch);
      if (id != null) return id;
    }
  }

  final posSetting = await settingsRepo.getSetting('pos_default_warehouse_id');
  if (posSetting != null) {
    final id = int.tryParse(posSetting);
    if (id != null) return id;
  }

  if (branchId != null) {
    final branchRepo = ref.read(branchRepositoryProvider);
    final warehouses = await branchRepo.getWarehousesByBranch(branchId);
    if (warehouses.isNotEmpty) {
      return warehouses.where((w) => w.isDefault).map((w) => w.id).firstOrNull ??
          warehouses.first.id;
    }
  }

  final repo = ref.read(inventoryRepositoryProvider);
  final defaultWh = await repo.getDefaultWarehouse();
  return defaultWh?.id ?? 1;
});

// ═══════════════════════════════════════════════════════════════════════════
// PRODUCT & INVENTORY PROVIDERS
// ═══════════════════════════════════════════════════════════════════════════

// Spec 032 v3 diagnostic — wrap allProductsProvider's emissions with a
// counter so we can see how often Drift re-fires the products stream
// during scroll. If this is high (10+/sec), background sync activity
// is mutating the products table and forcing every consumer to rebuild.
int _allProductsEmits = 0;
final allProductsProvider = StreamProvider<List<ProductEntity>>((
  ref,
) {
  final repo = ref.watch(productRepositoryProvider);
  return repo.watchAllProducts().map((list) {
    if (kPerfDebug) {
      _allProductsEmits++;
      if (_allProductsEmits <= 5 || _allProductsEmits % 10 == 0) {
        unawaited(DiagnosticLogger.log(
          'PERF',
          'allProductsProvider emit #$_allProductsEmits (${list.length} items)',
        ));
      }
    }
    return list;
  });
});

final searchProductsProvider = StreamProvider.autoDispose
    .family<List<ProductEntity>, String>((ref, query) {
      final repo = ref.watch(productRepositoryProvider);
      return repo.searchProducts(query);
    });

// ── Spec 136 ISS-9 / ISS-9b — inventory stock-balances data ──────────────────
// The inventory screen used to watch the UNBOUNDED allProductsProvider, which
// loaded + mapped every active product (762ms UI stall on a 57978-row catalog).
// Now: a cheap SQL aggregate for the summary cards (inventorySummaryProvider)
// and OFFSET-paginated, DB-filtered pages for the list (inventoryPagedProvider).

/// Filter arguments for the inventory list. All fields are value-equatable
/// primitives so the family key is stable (a `List<int>` key would compare by
/// identity and refetch on every rebuild — hence warehouse is passed as an id
/// and resolved to its product set inside the controller).
typedef InventoryListArgs = ({
  String search,
  int? categoryId,
  bool lowStockOnly,
  int? warehouseId,
});

/// Cheap SQL aggregate for the inventory summary cards (active count,
/// low-stock count, total stock value) — independent of the page size so the
/// totals stay accurate over the whole catalog.
final inventorySummaryProvider = StreamProvider.autoDispose<
    ({int activeCount, int lowStockCount, double totalValue})>((ref) {
  final repo = ref.watch(productRepositoryProvider);
  return repo.watchInventorySummary();
});

// Spec 136 ISS-9b — page size for the inventory infinite-scroll (offset-based
// pagination is driven from the inventory screen's own ConsumerState, which
// fetches + appends one page at a time so the whole catalog browses smoothly
// without ever materialising it all at once).
const int kInventoryPageSize = 300;

// ── Spec 136 ISS-12 — bounded POS product grid ──────────────────────────────
// The POS grid watched the unbounded allProductsProvider, loading + mapping the
// whole catalog (57978 rows: ~8s POS entry, and re-mapped on every sale → the
// post-sale readback blocked ~7s). It only ever shows one category or the
// search results, so this scopes the query to those, DB-side + LIMIT.

typedef PosGridArgs = ({String search, int? selectedCategoryId});

List<int> _descendantCategoryIds(List<Category> cats, int rootId) {
  final ids = <int>{rootId};
  void addChildren(int parentId) {
    for (final c in cats.where((c) => c.parentId == parentId)) {
      if (ids.add(c.id)) addChildren(c.id);
    }
  }
  addChildren(rootId);
  return ids.toList();
}

/// Spec 150 BUG-3 — «عام» is the seeded catch-all category. When it (or a
/// stray duplicate of it) is the selected filter, the grid must also surface
/// uncategorized (NULL-category) products and anything still filed under a
/// duplicate «عام» row, otherwise the field sees an empty "General" tab. The
/// canonical row carries [isSystemDefault]; duplicates from getOrCreateCategory
/// don't, so we also match on the trimmed name.
bool isGeneralCategory(Category c) =>
    c.isSystemDefault || c.name.trim() == 'عام';

final posGridProductsProvider = StreamProvider.autoDispose
    .family<List<ProductEntity>, PosGridArgs>((ref, args) {
  final repo = ref.watch(productRepositoryProvider);
  if (args.search.trim().isNotEmpty) {
    // Search overrides category — find the typed item anywhere (bounded).
    return repo.watchPosProducts(search: args.search);
  }
  if (args.selectedCategoryId != null) {
    final cats =
        ref.watch(allCategoriesProvider).asData?.value ?? const <Category>[];
    final ids = _descendantCategoryIds(cats, args.selectedCategoryId!);
    final selectedIsGeneral = cats
        .any((c) => c.id == args.selectedCategoryId! && isGeneralCategory(c));
    if (selectedIsGeneral) {
      // Fold in every «عام» variant + uncategorized products.
      final generalIds = cats.where(isGeneralCategory).map((c) => c.id);
      return repo.watchPosProducts(
        categoryIds: {...ids, ...generalIds}.toList(),
        includeUncategorized: true,
      );
    }
    return repo.watchPosProducts(categoryIds: ids);
  }
  // "All" view — bounded by the query LIMIT.
  return repo.watchPosProducts();
});

final allCategoriesProvider = StreamProvider<List<Category>>((ref) {
  if (kIsWeb) {
    final supabase = ref.watch(supabaseDatabaseProvider);
    return supabase?.watchCategories() ?? Stream.value([]);
  }
  final repo = ref.watch(productRepositoryProvider);
  return repo.watchAllCategories();
});

// Spec 032 v3 diagnostic — emission counter for visibleCategoriesProvider.
int _visibleCategoriesEmits = 0;

/// 4.8: Categories filtered by active branch (for POS & Order intake)
final visibleCategoriesProvider = StreamProvider<List<Category>>((ref) {
  final branchIdAsync = ref.watch(activeBranchIdProvider);

  Stream<List<Category>> baseStream;
  return branchIdAsync.when(
    data: (branchId) {
      if (branchId == null) {
        final repo = ref.watch(productRepositoryProvider);
        baseStream = repo.watchAllCategories();
      } else {
        final repo = ref.watch(productRepositoryProvider);
        baseStream = repo.watchCategoriesForBranch(branchId);
      }
      // Spec 136 ISS-23 — the Drift categories stream re-emits on EVERY
      // dependency-table update (every delta-pull / markTablesUpdated), even
      // when the category list is byte-identical. On a mirror (which pulls on
      // every branch's broadcast) that fired hundreds of times (#370 in the
      // field log), and each emit cascaded into categoryNameMapProvider, the
      // POS grid filter and the category chips — the reported mirror lag.
      // `Category` is a Drift DataClass with value equality, so suppress
      // identical re-emits with a content-based distinct BEFORE anything
      // downstream sees them. The counter now reflects DISTINCT (propagated)
      // emits, so the log directly shows the storm is gone.
      return baseStream.distinct(listEquals).map((list) {
        if (kPerfDebug) {
          _visibleCategoriesEmits++;
          if (_visibleCategoriesEmits <= 5 ||
              _visibleCategoriesEmits % 10 == 0) {
            unawaited(DiagnosticLogger.log(
              'PERF',
              'visibleCategoriesProvider emit '
                  '#$_visibleCategoriesEmits (${list.length} cats)',
            ));
          }
        }
        return list;
      });
    },
    loading: () => const Stream.empty(),
    error: (e, st) => Stream.error(e, st),
  );
});

/// Provider for low stock alerts - products at or below minimum stock
final lowStockProductsProvider =
    StreamProvider.autoDispose<List<ProductEntity>>((ref) {
      final repo = ref.watch(productRepositoryProvider);
      return repo.watchLowStockProducts();
    });

// ═══════════════════════════════════════════════════════════════════════════
// DERIVED MAPS (Spec 032 v3) — cached lookups for table rendering
// ═══════════════════════════════════════════════════════════════════════════
//
// Tables (products, stock-balances) need `id → name` lookups for category
// and warehouse columns. Building those maps inline on every table rebuild
// (which can fire 5–10 times per second during scroll-driven loadNextPage
// cycles — confirmed by the diagnostic trace) was costing ~30–80 ms per
// frame because each rebuild allocated a fresh Map literal of all
// categories / warehouses. These derived providers do the work ONCE per
// data change and Riverpod caches the result; tables `ref.watch` and
// receive the same Map reference until the underlying source updates.

/// `categoryId → categoryName`. Empty when categories are loading or the
/// stream errored.
final categoryNameMapProvider = Provider<Map<int, String>>((ref) {
  final cats = ref.watch(visibleCategoriesProvider);
  return cats.maybeWhen(
    data: (list) => {for (final c in list) c.id: c.name},
    orElse: () => const <int, String>{},
  );
});

/// IDs of categories whose `isLocked` flag is set. Tables use this to
/// render the locked-category status badge on individual products.
final lockedCategoryIdsProvider = Provider<Set<int>>((ref) {
  final cats = ref.watch(visibleCategoriesProvider);
  return cats.maybeWhen(
    data: (list) => list.where((c) => c.isLocked).map((c) => c.id).toSet(),
    orElse: () => const <int>{},
  );
});

/// Provider for held/suspended orders in POS
final heldOrdersProvider = StreamProvider.autoDispose<List<HeldOrder>>((ref) {
  final repo = ref.watch(inventoryRepositoryProvider);
  return repo.watchHeldOrders();
});

final stockAuditItemsProvider =
    FutureProvider.family<List<StockAuditItem>, int>((ref, auditId) {
      final repo = ref.watch(inventoryRepositoryProvider);
      return repo.getAuditItems(auditId);
    });

final allPrintersProvider = StreamProvider.autoDispose<List<Printer>>((ref) {
  final repo = ref.watch(printersRepositoryProvider);
  return repo.watchPrinters();
});

/// Stream of all active warehouses — filtered by N3 user access control.
/// Admin/system users see all warehouses (empty access = full access).
final allWarehousesProvider = StreamProvider<List<WarehouseData>>((
  ref,
) {
  final repo = ref.watch(inventoryRepositoryProvider);
  final authState = ref.watch(authProvider);
  final userId = authState.user?.id;

  return repo.watchWarehouses().asyncMap((warehouses) async {
    if (userId == null) return warehouses;
    final db = ref.read(databaseProvider);
    final scope = await db.getWarehouseScopeForUser(userId);

    // null = مميّز ⇒ بلا حصر.
    if (scope == null) return warehouses;

    if (scope.isEmpty) {
      // غير مميّز ومحدش خصّصله مخازن. `getUserAccessibleWarehouseIds` كانت
      // بتدّي `[]` هنا و`[]` للمميّز كمان، فالاتنين كانوا بياخدوا كل المخازن —
      // أقلّ مستخدم صلاحيةً وأعلاه بنفس النتيجة.
      //
      // قرار المالك (2026-08-04): نفشل مقفولاً على **أجهزة العميل والمرآة
      // فقط**. دول الأجهزة اللي بتسرّب فعلاً. الجهاز المستقل بيفضل بسلوكه
      // القديم عن قصد — محل بجهاز واحد وكاشير محدش خصّصله مخازن ماينفعش
      // يقف عشان حصر مالوش لازمة أصلاً على جهاز واحد.
      // هويّةُ الجهاز لا توجيهُ الكتابة: `SyncInterceptor.isClientMode` كانت
      // تنفتح على مرآةٍ لم يكتمل تصافحُها وقبل تهيئةِ المعترِض، فيُسلَّم
      // للمستخدمِ سيّئِ التزويد كلُّ المخازن — عكسُ ما يقوله هذا التعليقُ
      // نفسُه. انظر `NetworkService.isBranchScopedDevice`.
      if (NetworkService.instance.isBranchScopedDevice) {
        debugPrint('[WarehouseScope] ⚠ user=$userId غير مميّز وبلا تخصيص مخازن '
            'على جهاز عميل/مرآة ⇒ صفر مخازن (فشل مقفول)');
        return const <WarehouseData>[];
      }
      return warehouses;
    }

    return warehouses.where((w) => scope.contains(w.id)).toList();
    // Spec 136 ISS-23 — suppress byte-identical re-emits (Drift fires on every
    // dependency-table update; on a mirror that's the rebuild/refresh storm).
    // WarehouseData is a Drift DataClass with value equality.
  }).distinct(listEquals);
});

/// Whether this device runs in client OR mirror mode (the broadened R9
/// predicate). Presentation reads this instead of importing SyncInterceptor
/// directly (Constitution §IV / R7: no presentation → data/database imports).
final isClientModeProvider = Provider<bool>((ref) => SyncInterceptor.isClientMode);

final openAuditProvider = StreamProvider.autoDispose<StockAudit?>((ref) {
  final repo = ref.watch(inventoryRepositoryProvider);
  return repo.watchOpenAudit().map((list) => list.firstOrNull);
});

final stockMovementsProvider =
    StreamProvider.autoDispose<List<StockMovementData>>((ref) {
      final repo = ref.watch(inventoryRepositoryProvider);
      return repo.watchAllStockMovements();
    });

final productMovementsProvider = StreamProvider.autoDispose
    .family<List<StockMovementData>, int>((ref, productId) {
      final repo = ref.watch(inventoryRepositoryProvider);
      return repo.watchProductMovements(productId);
    });

/// Map of productId → base unit name (e.g. "قطعة", "كرتونة")
/// Used by stock balances and inventory reports to display UOM info.
final baseUnitNamesProvider = FutureProvider.autoDispose<Map<int, String>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.getBaseUnitNameMap();
});

/// Per-warehouse stock map: productId → quantity in that warehouse.
/// Used by inventory management screen to show warehouse-specific balances.
final warehouseStockMapProvider =
    FutureProvider.autoDispose.family<Map<int, double>, int>((ref, warehouseId) {
  final db = ref.watch(databaseProvider);
  return db.getWarehouseStockMap(warehouseId);
});

/// Stream of all active regions
final allRegionsProvider = StreamProvider<List<RegionData>>((ref) {
  return ref.watch(regionRepositoryProvider).watchRegions();
});

/// Branches belonging to a specific region
final regionBranchesProvider =
    StreamProvider.autoDispose.family<List<Branche>, int>((ref, regionId) {
  return ref.watch(regionRepositoryProvider).watchBranchesByRegion(regionId);
});
