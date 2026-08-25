// ignore_for_file: avoid_dynamic_calls
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ural_erp/core/utils/number_utils.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:google_fonts/google_fonts.dart';
import '../../../core/logging/diagnostic_logger.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/shimmer_loading.dart';
import 'report_export_guard.dart';
import 'report_scaffold.dart';

import '../../../data/providers/providers.dart';
import '../../widgets/report_components.dart';
import '../../widgets/searchable_dropdown.dart';
import '../../../services/invoice_generator.dart';
import '../../../core/constants/app_constants.dart';
import '../../widgets/branch_warehouse_filter.dart';

class InventoryReportScreen extends ConsumerStatefulWidget {
  const InventoryReportScreen({super.key});

  @override
  ConsumerState<InventoryReportScreen> createState() =>
      _InventoryReportScreenState();
}

class _InventoryReportScreenState extends ConsumerState<InventoryReportScreen> {
  bool _isLoading = false;
  InventoryAnalytics? _analytics;
  List<Product> _products = [];
  List<Product> _filteredProducts = [];
  List<Category> _categories = [];
  int? _selectedCategoryId;
  int? _selectedRegionId;
  int? _selectedWarehouseId; // null = all warehouses
  int? _selectedBranchId;
  Map<int, double> _warehouseStockMap = {}; // productId -> quantity (per-warehouse)
  Map<int, String> _unitMap = {}; // productId -> base unit name
  final _searchController = TextEditingController();
  final _currencyFormat = NumberFormat.currency(symbol: '', decimalDigits: AppConstants.decimalPlaces);

  // Spec 151 Track-3: the logged-in user's branch authorization scope — an
  // AUTH CAP distinct from the user-chosen warehouse/branch/region filter.
  // null = full access (admin/financial-manager/mirror/userId=1). Resolved in
  // BOTH build() and _loadData().
  Set<int>? _allowedBranchIds;
  // True when the displayed stock is scoped to a warehouse set (either a user
  // selection OR the auth cap narrowed it) — then the per-warehouse stock map
  // drives the rows/analytics instead of the global products.currentStock.
  bool _stockScoped = false;
  // True when the EFFECTIVE (auth-capped) warehouse set is empty — a restricted
  // user whose branches have no warehouses, or who picked a foreign warehouse
  // that the intersection dropped. Fail-closed: show zero rows, not the whole
  // (global) product catalog.
  bool _scopeEmpty = false;

  // Spec 151 Track-3: the stock to display/value for a product under the
  // current scope. When a warehouse set is in effect (user selection OR auth
  // cap) the per-warehouse stock map is authoritative — a product absent from
  // it has 0 stock in-scope; otherwise (full access, no selection) the global
  // aggregate. Single source so rows, ABC, dead-stock, export and print agree.
  double _scopedStock(Product p) =>
      _stockScoped ? (_warehouseStockMap[p.id] ?? 0.0) : p.currentStock;

  // Feature 058: one-time guard for the no-branch-assigned inline notice.
  bool _noBranchNoticeShown = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      // Feature 058: seed _selectedBranchId from the device's active branch
      // BEFORE the first data fetch (FR-001 + FR-002).
      if (_selectedBranchId == null) {
        final activeBranchId = await ref.read(activeBranchIdProvider.future);
        if (!mounted) return;
        if (activeBranchId != null) {
          setState(() => _selectedBranchId = activeBranchId);
        } else if (!_noBranchNoticeShown) {
          _noBranchNoticeShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('لم يتم تعيين فرع لهذا المستخدم — يتم عرض كل الفروع'),
              duration: Duration(seconds: 6),
            ));
          });
        }
      }
      _loadData();
      try {
        final user = ref.read(authProvider).user;
        ref.read(activityLoggerProvider).logReportView(user?.id ?? 0, user?.displayName ?? 'مجهول', 'تقرير المخزون');
      } catch (_) {}
    });
    _searchController.addListener(_filterProducts);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterProducts() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredProducts = _products.where((p) {
        final matchesSearch =
            query.isEmpty ||
            p.name.toLowerCase().contains(query) ||
            p.code.toLowerCase().contains(query);
        final matchesCategory =
            _selectedCategoryId == null || p.categoryId == _selectedCategoryId;
        // When stock is scoped (a warehouse/branch/region selection OR the
        // Spec 151 Track-3 auth cap), show only products present in that scope.
        // Full access with no user selection (_stockScoped == false) shows all.
        // A genuinely empty effective set (_scopeEmpty) fails closed → no rows,
        // never the whole global catalog.
        final matchesWarehouse = !_stockScoped ||
            (!_scopeEmpty &&
                (_warehouseStockMap.isEmpty ||
                    _warehouseStockMap.containsKey(p.id)));
        return matchesSearch && matchesCategory && matchesWarehouse;
      }).toList();
    });
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Spec 151 Track-3: resolve the auth-level branch scope BEFORE the query
      // runs, on every call (closes the initState-microtask race).
      final scope = await ref.read(branchScopeProvider.future);
      if (!mounted) return;
      _allowedBranchIds = scope.hasFullAccess ? null : scope.allowedBranchIds;

      final reportRepo = ref.read(reportingRepositoryProvider);
      final productRepo = ref.read(productRepositoryProvider);

      // Build warehouseIds from filter state (USER-CHOSEN)
      List<int>? warehouseIds;
      if (_selectedWarehouseId != null) {
        warehouseIds = [_selectedWarehouseId!];
      } else if (_selectedBranchId != null) {
        final ids = await BranchWarehouseFilterBar.getBranchWarehouseIds(ref, _selectedBranchId!);
        warehouseIds = ids.toList();
      } else if (_selectedRegionId != null) {
        final regionRepo = ref.read(regionRepositoryProvider);
        warehouseIds = await regionRepo.getWarehouseIdsForRegion(_selectedRegionId!);
        // Spec 079b (B2): empty warehouse list under an active region means
        // region→branch→warehouse link is broken somewhere. Without this
        // diagnostic the operator sees an empty inventory table and can't
        // tell whether it's "no stock" or "filter resolved to nothing".
        if (warehouseIds.isEmpty) {
          unawaited(DiagnosticLogger.log(
            'FILTER-WARN',
            'Region $_selectedRegionId selected on inventory report but '
            'no warehouses linked. Check region→branch→warehouse mapping.',
          ));
        }
      }

      // Spec 151 Track-3: cap warehouseIds to the warehouses of the branches
      // this user may read. Inventory is per-warehouse, so the branch cap is a
      // warehouse cap (warehouses.branch_id). When the user hasn't narrowed the
      // scope, the cap REPLACES the null ("all warehouses") set; when they have,
      // it INTERSECTS so the user can never widen beyond their branches (an
      // empty intersection → analytics returns zero via isIn([]), the map stays
      // empty, and the row list shows nothing). Full access (_allowedBranchIds
      // == null) leaves warehouseIds untouched.
      if (_allowedBranchIds != null) {
        final allowedWarehouseIds = <int>{};
        for (final bId in _allowedBranchIds!) {
          allowedWarehouseIds
              .addAll(await BranchWarehouseFilterBar.getBranchWarehouseIds(ref, bId));
        }
        if (warehouseIds == null) {
          warehouseIds = allowedWarehouseIds.toList();
        } else {
          warehouseIds =
              warehouseIds.where((w) => allowedWarehouseIds.contains(w)).toList();
        }
      }

      // Scoped whenever an effective warehouse set exists — a user selection OR
      // the auth cap. Drives the per-row stock column off the stock map below.
      _stockScoped = warehouseIds != null;
      // Fail-closed marker: a non-null but EMPTY effective set (empty auth
      // intersection / no warehouses in the allowed branches) must show nothing.
      _scopeEmpty = _stockScoped && (warehouseIds?.isEmpty ?? false);

      final analytics = await reportRepo.getInventoryReportAnalytics(
        warehouseIds: warehouseIds,
      );
      final products = await productRepo.getAllProducts();
      final categories = await productRepo.getCategories();

      // Per-warehouse stock map built from the EFFECTIVE (auth-capped)
      // warehouse set — never from the raw _selectedWarehouseId — so a
      // restricted user can never see a foreign warehouse's stock even if the
      // user-chosen warehouse lies outside their branches.
      Map<int, double> warehouseStockMap = {};
      if (warehouseIds != null && warehouseIds.isNotEmpty) {
        final branchRepo = ref.read(branchRepositoryProvider);
        for (final wId in warehouseIds) {
          final map = await branchRepo.getWarehouseStockMap(wId);
          for (final entry in map.entries) {
            warehouseStockMap[entry.key] =
                (warehouseStockMap[entry.key] ?? 0.0) + entry.value;
          }
        }
      }

      // Load base unit names for all products (reuse productRepo from above)
      final unitMap = await productRepo.getBaseUnitNameMap();

      setState(() {
        _analytics = analytics;
        _products = products;
        _filteredProducts = products;
        _categories = categories;
        _warehouseStockMap = warehouseStockMap;
        _unitMap = unitMap;
      });
      _filterProducts();
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Spec 151 Track-3: resolve the auth-level branch scope BEFORE the report
    // renders. The report MUST NOT render (even a flash) while the scope is
    // unknown — a restricted user briefly seeing an unscoped report is itself
    // the leak this fix closes.
    final scopeAsync = ref.watch(branchScopeProvider);
    if (scopeAsync.isLoading) {
      return const Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    if (scopeAsync.hasError) {
      return Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Scaffold(
          body: Center(child: Text('تعذر تحديد صلاحيات الفرع: ${scopeAsync.error}')),
        ),
      );
    }
    final scope = scopeAsync.requireValue;
    _allowedBranchIds = scope.hasFullAccess ? null : scope.allowedBranchIds;

    return reportScaffold(
      context: context,
      title: 'تقرير قيمة المخزون الحالية',
      subtitle: 'أرصدةُ المخازن وقيمتُها بالتكلفة',
      icon: PhosphorIconsBold.package,
      actions: [
            IconButton(
              onPressed: _loadData,
              icon: const Icon(PhosphorIconsBold.arrowsClockwise),
              tooltip: 'تحديث البيانات',
            ),
            buildReportExportAction(onExport: _exportToExcel),
            IconButton(
              onPressed: _printReport,
              icon: const Icon(PhosphorIconsBold.printer),
              tooltip: 'طباعة/PDF',
            ),
          ],
        body: _isLoading
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: ShimmerLoading.list(itemCount: 6),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_analytics != null)
                      Row(
                        children: [
                          Expanded(
                            child: ReportKpiCard(
                              title: 'قيمة المخزون (سعر التكلفة)',
                              value:
                                  '${_currencyFormat.format(_analytics!.totalCostValue)} ${AppConstants.currencySymbolEn}',
                              icon: PhosphorIconsBold.calculator,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: ReportKpiCard(
                              title: 'قيمة المخزون (سعر البيع)',
                              value:
                                  '${_currencyFormat.format(_analytics!.totalSaleValue)} ${AppConstants.currencySymbolEn}',
                              icon: PhosphorIconsBold.money,
                              color: AppColors.success,
                              subtitle:
                                  'الربح المتوقع: ${_currencyFormat.format(_analytics!.potentialProfit)}',
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: ReportKpiCard(
                              title: 'تنبيهات نقص الكمية',
                              value: _analytics!.lowStockCount.toString(),
                              icon: PhosphorIconsBold.warningCircle,
                              color: AppColors.error,
                              subtitle:
                                  'إجمالي الأصناف: ${NumberUtils.formatQuantity(_analytics!.itemsCount)}',
                            ),
                          ),
                        ],
                      ),

                    const SizedBox(height: 16),

                    // ABC Analysis Row
                    if (_products.isNotEmpty)
                      _buildAbcAnalysis(),

                    // Expiry Alerts
                    if (_products.any((p) => p.trackExpiry))
                      _buildExpiryAlerts(),

                    const SizedBox(height: 24),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'جرد الأصناف والقيم',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(
                              context,
                            ).textTheme.titleLarge?.color,
                          ),
                        ),
                        // Region + Branch + Warehouse Filter
                        BranchWarehouseFilterBar(
                          selectedRegionId: _selectedRegionId,
                          onRegionChanged: (v) {
                            setState(() {
                              _selectedRegionId = v;
                              _selectedBranchId = null;
                              _selectedWarehouseId = null;
                            });
                            _loadData();
                          },
                          selectedBranchId: _selectedBranchId,
                          selectedWarehouseId: _selectedWarehouseId,
                          onBranchChanged: (v) {
                            setState(() {
                              _selectedBranchId = v;
                              _selectedWarehouseId = null;
                            });
                            _loadData();
                          },
                          onWarehouseChanged: (v) {
                            setState(() => _selectedWarehouseId = v);
                            _loadData();
                          },
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 180,
                          child: SearchableDropdown<Category>(
                            items: _categories,
                            value: _categories
                                .where((c) => c.id == _selectedCategoryId)
                                .firstOrNull,
                            hint: 'كل التصنيفات',
                            searchHint: 'ابحث عن تصنيف...',
                            labelBuilder: (c) => c.name,
                            onChanged: (c) {
                              setState(() => _selectedCategoryId = c?.id);
                              _filterProducts();
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 250,
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: 'ابحث عن صنف أو كود...',
                              prefixIcon: const Icon(
                                PhosphorIconsBold.magnifyingGlass,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: Theme.of(context).dividerColor),
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('كود الصنف')),
                            DataColumn(label: Text('اسم الصنف')),
                            DataColumn(label: Text('التصنيف')),
                            DataColumn(label: Text('الوحدة')),
                            DataColumn(label: Text('الكمية الحالية')),
                            DataColumn(label: Text('سعر التكلفة')),
                            DataColumn(label: Text('إجمالي التكلفة')),
                            DataColumn(label: Text('سعر البيع')),
                            DataColumn(label: Text('إجمالي البيع')),
                          ],
                          rows: _filteredProducts.map((p) {
                            // Spec 151 Track-3: use the scoped stock map when a
                            // warehouse set is in effect (user selection OR auth
                            // cap); otherwise the global product stock.
                            final stock = _stockScoped
                                ? (_warehouseStockMap[p.id] ?? 0.0)
                                : p.currentStock;
                            final totalCost = p.costPrice * stock;
                            final totalSale = p.salePrice * stock;
                            final isLow = stock <= p.minStock;
                            final category = _categories
                                .where((c) => c.id == p.categoryId)
                                .firstOrNull;
                            final categoryName = category?.name ?? 'غير مصنف';

                            return DataRow(
                              cells: [
                                DataCell(Text(p.code)),
                                DataCell(Text(p.name)),
                                DataCell(
                                  Text(
                                    categoryName,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    _unitMap[p.id] ?? 'قطعة',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    stock.toString(),
                                    style: TextStyle(
                                      color: isLow ? AppColors.error : null,
                                      fontWeight: isLow
                                          ? FontWeight.bold
                                          : null,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(_currencyFormat.format(p.costPrice)),
                                ),
                                DataCell(
                                  Text(_currencyFormat.format(totalCost)),
                                ),
                                DataCell(
                                  Text(_currencyFormat.format(p.salePrice)),
                                ),
                                DataCell(
                                  Text(_currencyFormat.format(totalSale)),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
    );
  }

  // ── ABC Inventory Classification ─────────────────────────
  Widget _buildAbcAnalysis() {
    // Spec 151 Track-3: value products by the SCOPED stock (not global
    // currentStock) so a branch-restricted user's ABC valuation + dead-stock
    // count reflect only their branches — the KPI cards + table above are
    // already scoped; this closes the leak directly beneath them.
    // Sort products by total value (cost * stock) descending
    final sorted = List<Product>.from(_products)
      ..sort((a, b) => (b.costPrice * _scopedStock(b))
          .compareTo(a.costPrice * _scopedStock(a)));

    final totalValue = sorted.fold<double>(
        0, (s, p) => s + (p.costPrice * _scopedStock(p)));

    // Classify: A = top 80%, B = next 15%, C = rest
    double cumulative = 0;
    int aCount = 0, bCount = 0, cCount = 0;
    double aValue = 0, bValue = 0, cValue = 0;
    for (final p in sorted) {
      final val = p.costPrice * _scopedStock(p);
      cumulative += val;
      final pct = totalValue > 0 ? cumulative / totalValue : 1;
      if (pct <= 0.80) {
        aCount++;
        aValue += val;
      } else if (pct <= 0.95) {
        bCount++;
        bValue += val;
      } else {
        cCount++;
        cValue += val;
      }
    }

    final deadStock = _products.where((p) => _scopedStock(p) == 0).length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          _abcCard('A', aCount, aValue, totalValue, const Color(0xFF059669)),
          const SizedBox(width: 12),
          _abcCard('B', bCount, bValue, totalValue, const Color(0xFFF59E0B)),
          const SizedBox(width: 12),
          _abcCard('C', cCount, cValue, totalValue, const Color(0xFFDC2626)),
          const SizedBox(width: 12),
          Expanded(
            child: ReportKpiCard(
              title: 'مخزون راكد (كمية = 0)',
              value: deadStock.toString(),
              icon: PhosphorIconsBold.archive,
              color: const Color(0xFF6B7280),
              subtitle: 'أصناف بدون حركة',
            ),
          ),
        ],
      ),
    );
  }

  Widget _abcCard(
      String grade, int count, double value, double total, Color color) {
    final pct = total > 0 ? (value / total * 100) : 0.0;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  alignment: Alignment.center,
                  child: Text(grade,
                      style: GoogleFonts.cairo(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14)),
                ),
                const SizedBox(width: 8),
                Text('$count صنف',
                    style: GoogleFonts.cairo(
                        fontWeight: FontWeight.w700, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 6),
            Text('${_currencyFormat.format(value)} ${AppConstants.currencySymbolEn}',
                style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textMuted)),
            Text('${pct.toStringAsFixed(1)}% من إجمالي القيمة',
                style: GoogleFonts.cairo(fontSize: 10, color: color)),
          ],
        ),
      ),
    );
  }

  // ── Expiry Alerts ───────────────────────────────────────
  Widget _buildExpiryAlerts() {
    // Find products with batches expiring soon (within 30 days)
    // Since we have product.trackExpiry and product.alertDaysBefore as columns,
    // we show an informational message about expiry-tracked items
    final expiryTracked = _products.where((p) => p.trackExpiry).toList();
    if (expiryTracked.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        elevation: 0,
        color: const Color(0xFFFFF7ED),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFFED7AA)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(PhosphorIconsBold.clock,
                  color: Color(0xFFF59E0B), size: 22),
              const SizedBox(width: 10),
              Text(
                '${expiryTracked.length} صنف يتم تتبع صلاحيته — راجع دفعات المنتج لمواعيد الانتهاء',
                style: GoogleFonts.cairo(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF92400E)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportToExcel() async {
    final service = ref.read(excelServiceProvider);

    final path = await service.exportReport(
      branchId: _selectedBranchId,
      scopedBranchIds:
          (await ref.read(branchScopeProvider.future)).allowedBranchIds,
      title: 'تقرير المخزون',
      headers: [
        'كود الصنف',
        'اسم الصنف',
        'الوحدة',
        'الكمية',
        'سعر التكلفة',
        'إجمالي التكلفة',
        'سعر البيع',
        'إجمالي البيع',
      ],
      rows: _filteredProducts
          .map<List<dynamic>>(
            (Product? p) {
              // Spec 151 Track-3: match the on-screen scoped-stock logic so the
              // export never leaks a foreign branch's stock for a restricted user.
              final stock = (_stockScoped && p != null)
                  ? (_warehouseStockMap[p.id] ?? 0.0)
                  : (p?.currentStock ?? 0.0);
              return [
                p?.code ?? '-',
                p?.name ?? '-',
                _unitMap[p?.id ?? 0] ?? 'قطعة',
                stock,
                p?.costPrice ?? 0.0,
                (p?.costPrice ?? 0.0) * stock,
                p?.salePrice ?? 0.0,
                (p?.salePrice ?? 0.0) * stock,
              ];
            },
          )
          .toList(),
    );

    if (path != null && mounted) {
      AppToast.show(
        context,
        'تم تصدير التقرير بنجاح: $path',
        type: ToastType.success,
      );
    }
  }

  Future<void> _printReport() async {
    if (_filteredProducts.isEmpty) {
      AppToast.show(context, 'لا توجد بيانات للطباعة', type: ToastType.error);
      return;
    }

    try {
      // Spec 151 Track-3: print the SAME scoped stock as the on-screen table +
      // Excel export. The PDF generator renders p.currentStock, so a restricted
      // user would otherwise print every branch's stock/valuation — project a
      // scoped copy. Full access (_stockScoped == false) prints global stock.
      final products = _stockScoped
          ? _filteredProducts
              .map((p) => p.copyWith(currentStock: _scopedStock(p)))
              .toList()
          : _filteredProducts;
      // GAP-15: اسم الشركة من إعدادات العميل مش قيمة مكتوبة بالإيد. كان
      // مثبَّت على `MONEXIA Market` — اسم علامة تالتة على رأس تقرير العميل.
      final receiptSettings =
          await ref.read(settingsRepositoryProvider).getReceiptSettings();

      await InvoiceGenerator.printInventoryReport(
        products: products,
        companyName: receiptSettings['companyName'] as String? ?? 'الشركة',
      );
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'خطأ في الطباعة: $e', type: ToastType.error);
      }
    }
  }
}