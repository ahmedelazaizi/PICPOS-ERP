import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/diagnostics/perf_trace.dart';
import '../../../core/logging/diagnostic_logger.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
// 063 (D1-005): dual-approval gate for stock write-offs.
import '../../../services/dual_approval_service.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/entities/product_entity.dart';
import '../products/widgets/barcode_print_dialog.dart';
import 'inventory_notifier.dart';
import 'widgets/stock_balances_table.dart';
import 'widgets/stock_movements_table.dart';
import 'widgets/inventory_summary_row.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _adjQtyController = TextEditingController();
  final TextEditingController _adjNotesController = TextEditingController();
  final TextEditingController _movementSearchController =
      TextEditingController();
  String? _selectedMovementType; // null = all types

  // Spec 029 / US4 — perf instrumentation. Compiled out in release
  // unless `kPerfDebug` is flipped to true. See perf-audit.md.
  final _perfFirstPaint = PerfFirstPaint('inventory');
  // ignore: unused_field
  TimingsCallback? _perfFrameCallback;

  // Spec 032 v3 diagnostic — build counter for the screen itself, separate
  // from the table's build counter. If this fires 10+/sec during scroll,
  // a parent provider is over-emitting and we need to narrow the
  // .watch granularity.
  final _screenBuilds = PerfRebuildCounter('inventory_screen', everyN: 10);

  // ── Spec 136 ISS-9b — offset-based infinite scroll for the balances tab ────
  // Held in screen state (not a Riverpod family-notifier — the project is on
  // Riverpod 3 without a family-notifier precedent). Each page is fetched +
  // appended once so the whole catalog browses smoothly. Changing any filter
  // changes [_pagedKey] → a fresh page-0 reload.
  List<ProductEntity> _pagedItems = const [];
  bool _pageLoading = false;
  bool _pageHasMore = true;
  String? _pagedKey;

  String _argsKey(InventoryListArgs a) =>
      '${a.search}|${a.categoryId}|${a.lowStockOnly}|${a.warehouseId}';

  Future<List<int>?> _resolveRestrictIds(int? warehouseId) async {
    if (warehouseId == null) return null;
    try {
      final m = await ref.read(warehouseStockMapProvider(warehouseId).future);
      return m.keys.toList();
    } catch (_) {
      return const <int>[]; // warehouse map unavailable → show nothing, not all
    }
  }

  Future<void> _loadInventoryPage(InventoryListArgs args,
      {required bool reset}) async {
    if (_pageLoading) return;
    if (!reset && !_pageHasMore) return;
    setState(() => _pageLoading = true);
    try {
      final repo = ref.read(productRepositoryProvider);
      final restrict = await _resolveRestrictIds(args.warehouseId);
      final offset = reset ? 0 : _pagedItems.length;
      final page = await repo.getInventoryProductsPage(
        limit: kInventoryPageSize,
        offset: offset,
        search: args.search.isEmpty ? null : args.search,
        categoryId: args.categoryId,
        lowStockOnly: args.lowStockOnly,
        restrictToIds: restrict,
      );
      if (!mounted) return;
      setState(() {
        _pagedItems = reset ? page : [..._pagedItems, ...page];
        _pageHasMore = page.length == kInventoryPageSize;
        _pageLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _pageLoading = false);
      debugPrint('[Inventory] page load failed: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    if (kPerfDebug) {
      _perfFrameCallback = (timings) =>
          perfReportFrameOverBudget('inventory', timings);
      SchedulerBinding.instance.addTimingsCallback(_perfFrameCallback!);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _perfFirstPaint.emit();
      if (kPerfDebug) {
        DiagnosticLogger.startSession('inventory screen entered');
      }
    });
  }

  @override
  void dispose() {
    if (kPerfDebug && _perfFrameCallback != null) {
      SchedulerBinding.instance.removeTimingsCallback(_perfFrameCallback!);
    }
    _tabController.dispose();
    _searchController.dispose();
    _adjQtyController.dispose();
    _adjNotesController.dispose();
    _movementSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _screenBuilds.tick();
    final state = ref.watch(inventoryNotifierProvider);
    // Spec 136 ISS-9/9b — the balances tab + summary use the paginated/aggregate
    // providers (inventoryPagedProvider / inventorySummaryProvider) instead of
    // the unbounded allProductsProvider, so entering inventory no longer loads
    // + maps the whole catalog (the 762ms stall). The movements tab keeps its
    // own watch and only fires when that tab is built.
    final categoriesAsync = ref.watch(visibleCategoriesProvider);
    final unitMapAsync = ref.watch(baseUnitNamesProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('إدارة المخزون'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'أرصدة المستودع', icon: Icon(PhosphorIconsBold.package)),
            Tab(
              text: 'حركة الأصناف',
              icon: Icon(PhosphorIconsBold.arrowsLeftRight),
            ),
          ],
        ),
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsetsDirectional.fromSTEB(24, 24, 24, 16),
            child: InventorySummaryRow(),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Expanded(child: _buildSearchField(context, ref)),
                const SizedBox(width: 12),
                _buildWarehouseFilter(context, ref),
                const SizedBox(width: 12),
                _buildCategoryFilter(context, ref),
                const SizedBox(width: 12),
                _buildLowStockToggle(ref, state),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildBalancesTab(categoriesAsync, unitMapAsync),
                  _buildMovementsTab(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context, WidgetRef ref) {
    return TextField(
      controller: _searchController,
      onChanged: (v) =>
          ref.read(inventoryNotifierProvider.notifier).setSearchQuery(v),
      decoration: InputDecoration(
        hintText: 'بحث عن صنف أو كود...',
        prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 18),
        filled: true,
        fillColor: Theme.of(context).cardColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      ),
    );
  }

  Widget _buildWarehouseFilter(BuildContext context, WidgetRef ref) {
    final warehousesAsync = ref.watch(allWarehousesProvider);
    return warehousesAsync.when(
      data: (warehouses) {
        if (warehouses.length <= 1) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int?>(
              value: ref.watch(inventoryNotifierProvider).selectedWarehouseId,
              hint: const Text('كل المستودعات'),
              items: [
                const DropdownMenuItem(value: null, child: Text('كل المستودعات')),
                ...warehouses.map(
                  (w) => DropdownMenuItem(value: w.id, child: Text(w.name)),
                ),
              ],
              onChanged: (v) =>
                  ref.read(inventoryNotifierProvider.notifier).setWarehouse(v),
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  Widget _buildCategoryFilter(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(visibleCategoriesProvider);
    return categoriesAsync.when(
      data: (cats) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int?>(
            value: ref.watch(inventoryNotifierProvider).selectedCategoryId,
            hint: const Text('كل التصنيفات'),
            items: [
              const DropdownMenuItem(value: null, child: Text('كل التصنيفات')),
              ...cats.map(
                (c) => DropdownMenuItem(value: c.id, child: Text(c.name)),
              ),
            ],
            onChanged: (v) =>
                ref.read(inventoryNotifierProvider.notifier).setCategory(v),
          ),
        ),
      ),
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  Widget _buildLowStockToggle(WidgetRef ref, InventoryState state) {
    return FilterChip(
      label: const Text('نواقص المخزون'),
      selected: state.showLowStockOnly,
      onSelected: (v) =>
          ref.read(inventoryNotifierProvider.notifier).toggleLowStock(v),
      selectedColor: AppColors.warning.withValues(alpha: 0.2),
      checkmarkColor: AppColors.warning,
      labelStyle: TextStyle(
        color: state.showLowStockOnly ? AppColors.warning : AppColors.textMuted,
        fontWeight: state.showLowStockOnly
            ? FontWeight.bold
            : FontWeight.normal,
      ),
    );
  }

  Widget _buildBalancesTab(
    AsyncValue<List<Category>> categoriesAsync,
    AsyncValue<Map<int, String>> unitMapAsync,
  ) {
    final state = ref.watch(inventoryNotifierProvider);
    final selectedWarehouseId = state.selectedWarehouseId;

    // Spec 136 ISS-9 + ISS-9b — DB-filtered + OFFSET-paginated product list.
    // Each page is fetched + mapped once and appended on scroll, so the whole
    // catalog browses smoothly without ever materialising it all at once.
    // Changing any filter spins a fresh controller (family key) → resets paging.
    final InventoryListArgs listArgs = (
      search: state.searchQuery,
      categoryId: state.selectedCategoryId,
      lowStockOnly: state.showLowStockOnly,
      warehouseId: selectedWarehouseId,
    );
    // Reset + load page 0 whenever the filter signature changes (or first
    // build). Setting _pagedKey synchronously dedupes re-scheduling across
    // rebuilds; the actual fetch runs post-frame to avoid setState-in-build.
    final key = _argsKey(listArgs);
    if (key != _pagedKey) {
      _pagedKey = key;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadInventoryPage(listArgs, reset: true);
      });
    }
    final AsyncValue<List<ProductEntity>> productsAsync =
        (_pagedItems.isEmpty && _pageLoading)
            ? const AsyncValue.loading()
            : AsyncValue.data(_pagedItems);

    // Load per-warehouse stock map when a warehouse is selected
    final warehouseStockMapAsync = selectedWarehouseId != null
        ? ref.watch(warehouseStockMapProvider(selectedWarehouseId))
        : null;

    final warehouseStockMap = warehouseStockMapAsync?.when(
          data: (m) => m,
          loading: () => <int, double>{},
          error: (_, _) => <int, double>{},
        ) ??
        <int, double>{};

    // Spec 032 v3 — ALWAYS render the Card(StockBalancesTable) even when
    // categories / units haven't loaded yet. The previous code returned
    // ShimmerLoading.list() during async transitions, which destroyed
    // the table's Element (and therefore its State + ScrollController);
    // a scroll gesture in flight would silently drop. The user reported
    // "vertical scroll doesn't respond" and the diagnostic trace
    // confirmed `stock_balances_table rebuild #1` reset multiple times
    // mid-session. Now we feed empty maps to the table while async
    // sources are loading; category/unit labels read as blank during
    // the brief warm-up but the table widget identity stays stable.
    final categoryMap = ref.watch(categoryNameMapProvider);
    final unitMap = unitMapAsync.maybeWhen(
      data: (m) => m,
      orElse: () => const <int, String>{},
    );
    // Surface category-load errors in a banner; don't kill the table.
    final categoriesError = categoriesAsync.maybeWhen(
      error: (e, _) => 'خطأ في تحميل التصنيفات: $e',
      orElse: () => null,
    );

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          if (categoriesError != null)
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppColors.error.withValues(alpha: 0.08),
              child: Text(
                categoriesError,
                style: const TextStyle(color: AppColors.error, fontSize: 12),
              ),
            ),
          Expanded(
            child: StockBalancesTable(
              productsAsync: productsAsync,
              expiryMap: const {},
              categoryMap: categoryMap,
              unitMap: unitMap,
              onAdjustStock: _showAdjustmentDialog,
              onPrint: (p) => BarcodePrintDialog.show(context, p),
              warehouseStockMap: warehouseStockMap,
              filterByWarehouse: selectedWarehouseId != null,
              // Spec 136 ISS-9b — append the next page when the operator
              // scrolls near the end (no-op while loading / once the end is
              // reached).
              onLoadMore: () => _loadInventoryPage(listArgs, reset: false),
              isLoadingMore: _pageLoading && _pagedItems.isNotEmpty,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMovementsTab() {
    final state = ref.watch(inventoryNotifierProvider);
    final productsAsync = ref.watch(allProductsProvider);
    final movementsAsync = ref.watch(
      state.selectedMovementProductId != null
          ? productMovementsProvider(state.selectedMovementProductId!)
          : stockMovementsProvider,
    );

    // Build maps from the products list
    final productNameMap = <int, String>{};
    final productCategoryMap = <int, int?>{};
    productsAsync.whenData((products) {
      for (var p in products) {
        productNameMap[p.id] = p.name;
        productCategoryMap[p.id] = p.categoryId;
      }
    });

    return Column(
      children: [
        _buildMovementFilters(productsAsync),
        const SizedBox(height: 12),
        Expanded(
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: StockMovementsTable(
              productNameMap: productNameMap,
              movementsAsync: movementsAsync.when(
                data: (list) {
                  var mapped = list.toList();

                  // Filter by warehouse if selected
                  if (state.selectedWarehouseId != null) {
                    mapped = mapped.where((m) => m.warehouseId == state.selectedWarehouseId).toList();
                  }

                  // Filter by movement type if selected
                  if (_selectedMovementType != null) {
                    mapped = mapped.where((m) => m.movementType == _selectedMovementType).toList();
                  }

                  // Filter by global search query (match product name)
                  if (state.searchQuery.isNotEmpty) {
                    final query = state.searchQuery.toLowerCase();
                    mapped = mapped.where((m) {
                      final name = productNameMap[m.productId]?.toLowerCase() ?? '';
                      return name.contains(query);
                    }).toList();
                  }

                  // Filter by selected category (match product's category)
                  if (state.selectedCategoryId != null) {
                    mapped = mapped.where((m) {
                      return productCategoryMap[m.productId] == state.selectedCategoryId;
                    }).toList();
                  }

                  return AsyncValue.data(mapped);
                },
                loading: () => const AsyncValue.loading(),
                error: (e, s) => AsyncValue.error(e, s),
              ),
              onNavigateToInvoice: _navigateToInvoice,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMovementFilters(AsyncValue<List<ProductEntity>> productsAsync) {
    final state = ref.watch(inventoryNotifierProvider);
    final selectedProductId = state.selectedMovementProductId;

    return Row(
      children: [
        // Product filter dropdown
        Expanded(
          flex: 3,
          child: productsAsync.when(
            data: (products) {
  // ignore: unused_local_variable
              final searchText = _movementSearchController.text.toLowerCase();
              // Find selected product name
  // ignore: unused_local_variable
              final selectedName = selectedProductId != null
                  ? products.where((p) => p.id == selectedProductId).firstOrNull?.name
                  : null;

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selectedProductId != null ? AppColors.primary : AppColors.border,
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int?>(
                    value: selectedProductId,
                    isExpanded: true,
                    hint: const Text('كل الأصناف'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('كل الأصناف')),
                      ...products.map(
                        (p) => DropdownMenuItem(
                          value: p.id,
                          child: Text(
                            p.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      ref.read(inventoryNotifierProvider.notifier).setMovementProduct(v);
                    },
                  ),
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
        ),
        const SizedBox(width: 12),

        // Movement type filter chips
        Expanded(
          flex: 5,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _movementTypeChip(null, 'الكل', PhosphorIconsBold.listBullets),
                const SizedBox(width: 6),
                _movementTypeChip('sale', 'مبيعات', PhosphorIconsBold.receipt),
                const SizedBox(width: 6),
                _movementTypeChip('purchase', 'مشتريات', PhosphorIconsBold.shoppingCart),
                const SizedBox(width: 6),
                _movementTypeChip('return', 'مرتجع', PhosphorIconsBold.arrowUDownLeft),
                const SizedBox(width: 6),
                _movementTypeChip('adjustment', 'تسوية', PhosphorIconsBold.faders),
                const SizedBox(width: 6),
                _movementTypeChip('waste', 'هدر/تالف', PhosphorIconsBold.trash),
                const SizedBox(width: 6),
                _movementTypeChip('damage', 'تلف', PhosphorIconsBold.warning),
                const SizedBox(width: 6),
                _movementTypeChip('transfer', 'تحويل', PhosphorIconsBold.arrowsLeftRight),
                const SizedBox(width: 6),
                _movementTypeChip('opening_stock', 'رصيد افتتاحي', PhosphorIconsBold.package),
              ],
            ),
          ),
        ),

        const SizedBox(width: 12),
        // Clear all filters button
        if (selectedProductId != null || _selectedMovementType != null)
          IconButton(
            onPressed: () {
              ref.read(inventoryNotifierProvider.notifier).setMovementProduct(null);
              setState(() => _selectedMovementType = null);
            },
            icon: const Icon(PhosphorIconsBold.x, size: 18),
            tooltip: 'إزالة الفلاتر',
            style: IconButton.styleFrom(
              backgroundColor: AppColors.error.withValues(alpha: 0.1),
              foregroundColor: AppColors.error,
            ),
          ),
      ],
    );
  }

  Widget _movementTypeChip(String? type, String label, IconData icon) {
    final isSelected = _selectedMovementType == type;
    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: isSelected ? Colors.white : AppColors.textMuted),
          const SizedBox(width: 4),
          Text(label),
        ],
      ),
      selected: isSelected,
      onSelected: (_) {
        setState(() => _selectedMovementType = type);
      },
      selectedColor: AppColors.primary,
      checkmarkColor: Colors.white,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : AppColors.textMuted,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
    );
  }

  void _showAdjustmentDialog(ProductEntity product) {
    _adjQtyController.clear();
    _adjNotesController.clear();
    String adjustmentType = 'add';
    // R2: re-entrancy guard declared OUTSIDE StatefulBuilder so it survives
    // rebuilds. Without it a rapid double-tap on "حفظ التسوية" mints two
    // distinct adjustmentEventGids (Spec 135 BUG-A) → two stock movements +
    // two JEs for one logical adjustment.
    bool saving = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text('تسوية مخزون: ${product.name}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: adjustmentType,
                  items: const [
                    DropdownMenuItem(
                      value: 'add',
                      child: Text('إضافة للمخزون'),
                    ),
                    DropdownMenuItem(
                      value: 'remove',
                      child: Text('سحب من المخزون'),
                    ),
                    DropdownMenuItem(
                      value: 'waste',
                      child: Text('هدر / تالف'),
                    ),
                    DropdownMenuItem(
                      value: 'damage',
                      child: Text('تلف (ضرر)'),
                    ),
                    DropdownMenuItem(
                      value: 'opening',
                      child: Text('تعديل الرصيد الإفتتاحي'),
                    ),
                  ],
                  onChanged: (v) => setDialogState(() => adjustmentType = v!),
                  decoration: const InputDecoration(labelText: 'نوع التسوية'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _adjQtyController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'الكمية',
                    suffixText: 'وحدة',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _adjNotesController,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات (اختياري)',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: saving
                    ? null
                    : () async {
                  final qty = double.tryParse(_adjQtyController.text) ?? 0;
                  if (qty <= 0) return;

                  setDialogState(() => saving = true);
                  try {
                    // 063 (D1-005): dual-approval gate for write-off-class
                    // adjustments (waste / damage / sizable remove). The
                    // settings flag dual_approval_stockWriteOff_enabled is
                    // OFF by default — no dialog, no UX change.
                    final isWriteOff = adjustmentType == 'waste' ||
                        adjustmentType == 'damage' ||
                        adjustmentType == 'remove';
                    if (isWriteOff) {
                      final approved =
                          await DualApprovalService.requireApprovalForOp(
                        context,
                        ref,
                        operation: DualApprovalOperation.stockWriteOff,
                        details: '${product.name} — $adjustmentType × $qty',
                      );
                      if (!approved) {
                        if (context.mounted) {
                          AppToast.show(
                            context,
                            'الموافقة الثنائية مرفوضة — لم يتم تنفيذ التسوية',
                            type: ToastType.warning,
                          );
                        }
                        return;
                      }
                    }
                    await ref
                        .read(inventoryNotifierProvider.notifier)
                        .adjustStock(
                          productId: product.id,
                          quantity: qty,
                          adjustmentType: adjustmentType,
                          notes: _adjNotesController.text,
                          currentStock: product.currentStock,
                        );
                    // #3: force the balances list (local paged State) to reload
                    // page-0 so the edited row shows its new stock immediately,
                    // instead of only after leaving and re-entering the screen.
                    if (mounted) setState(() => _pagedKey = null);
                    if (context.mounted) Navigator.pop(context);
                  } finally {
                    // Reset only if the dialog is still on screen (reject /
                    // error path). On the success path we've already popped,
                    // so the StatefulBuilder is gone — skip to avoid
                    // setState-after-dispose.
                    if (context.mounted) {
                      setDialogState(() => saving = false);
                    }
                  }
                },
                child: const Text('حفظ التسوية'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  void _printInventoryReport(List<ProductEntity> products) async {
    // Standard implementation using InvoiceGenerator
  }

  void _navigateToInvoice(String type, int id) {
    // Standard implementation
  }
}
