// ignore_for_file: avoid_dynamic_calls
import 'package:flutter/material.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../data/providers/providers.dart';
import '../../../../../core/constants/app_constants.dart';
import '../../services/client_write_interceptor.dart';
import '../widgets/dialogs/app_confirm_dialog.dart';
import 'widgets/dialogs/branch_edit_dialog.dart';
import 'widgets/dialogs/warehouse_edit_dialog.dart';
import 'widgets/dialogs/quick_cost_center_dialog.dart';

part 'branch_management_dialogs.dart';

/// Branch Management Screen - إدارة الفروع والمخازن
class BranchManagementScreen extends ConsumerStatefulWidget {
  const BranchManagementScreen({super.key});

  @override
  ConsumerState<BranchManagementScreen> createState() =>
      _BranchManagementScreenState();
}

class _BranchManagementScreenState extends ConsumerState<BranchManagementScreen>
    with SingleTickerProviderStateMixin, _BranchManagementDialogsMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  // ── Mixin interface for _BranchManagementDialogsMixin ──
  @override
  WidgetRef get screenRef => ref;
  @override
  TabController get tabController => _tabController;
  @override
  void refreshAuxData() => _refreshAuxData();

  // ─── Cached data loaded once, updated via stream subscriptions ───
  List<dynamic> _branches = [];
  List<dynamic> _warehouses = [];
  List<dynamic> _costCenters = [];
  List<int> _userBranchAccessIds = [];
  List<int> _userWarehouseAccessIds = [];
  Map<int, String> _costCenterMap = {};
  Map<int, String> _branchNameMap = {};
  Map<int, int> _branchWarehouseCount = {};
  bool _isLoading = true;

  // Stream subscriptions — kept alive to react to DB changes
  dynamic _branchesSub;
  dynamic _warehousesSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Defer data loading to avoid provider access during initState
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _branchesSub?.cancel();
    _warehousesSub?.cancel();
    super.dispose();
  }

  /// Load all data using stream subscriptions so the list updates reactively
  /// but WITHOUT creating new StreamBuilder widgets inside build().
  Future<void> _loadData() async {
    try {
      final branchRepo = ref.read(branchRepositoryProvider);
      final accountingRepo = ref.read(accountingRepositoryProvider);
      final authState = ref.read(authProvider);
      final userId = authState.user?.id;

      // Load user access IDs once (these don't change during screen lifetime)
      if (userId != null) {
        _userBranchAccessIds = await branchRepo.getUserAccessibleBranchIds(userId);
        _userWarehouseAccessIds = await branchRepo.getUserAccessibleWarehouseIds(userId);
      }

      // Load cost centers once
      _costCenters = await accountingRepo.getCostCenters();
      _costCenterMap = {for (final cc in _costCenters) cc.id: cc.name};

      bool branchesLoaded = false;
      bool warehousesLoaded = false;

      void checkLoading() {
        if (branchesLoaded && warehousesLoaded && _isLoading && mounted) {
          setState(() => _isLoading = false);
        }
      }

      // Subscribe to branches stream
      _branchesSub = branchRepo.watchAllBranches().listen((branches) {
        if (!mounted) return;
        setState(() {
          _branches = branches;
          _branchNameMap = {for (final b in branches) b.id: b.name};
        });
        branchesLoaded = true;
        checkLoading();
      }, onError: (e) {
        debugPrint('[BranchManagement] Branches stream error: $e');
        branchesLoaded = true;
        checkLoading();
      });

      // Subscribe to warehouses stream
      _warehousesSub = branchRepo.watchAllWarehouses().listen((warehouses) {
        if (!mounted) return;
        setState(() {
          _warehouses = warehouses;
          _branchWarehouseCount = <int, int>{};
          for (final w in warehouses) {
            if (w.branchId != null) {
              _branchWarehouseCount[w.branchId!] =
                  (_branchWarehouseCount[w.branchId!] ?? 0) + 1;
            }
          }
        });
        warehousesLoaded = true;
        checkLoading();
      }, onError: (e) {
        debugPrint('[BranchManagement] Warehouses stream error: $e');
        warehousesLoaded = true;
        checkLoading();
      });

      // Safety timeout — never stay stuck loading forever
      Future.delayed(const Duration(seconds: 3), () {
        if (_isLoading && mounted) {
          debugPrint('[BranchManagement] Loading timeout — forcing UI');
          setState(() => _isLoading = false);
        }
      });
    } catch (e) {
      debugPrint('[BranchManagement] Error loading data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Refresh auxiliary data (cost centers, access IDs) after add/edit operations
  Future<void> _refreshAuxData() async {
    final accountingRepo = ref.read(accountingRepositoryProvider);
    _costCenters = await accountingRepo.getCostCenters();
    _costCenterMap = {for (final cc in _costCenters) cc.id: cc.name};
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title: const Text('إدارة الفروع والمخازن'),
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: const [
              Tab(icon: Icon(PhosphorIconsBold.buildings), text: 'الفروع'),
              Tab(icon: Icon(PhosphorIconsBold.warehouse), text: 'المخازن'),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'بحث عن فرع أو مخزن...',
                        prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 18),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () { _searchController.clear(); setState(() => _searchQuery = ''); })
                            : null,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [_buildBranchesTab(), _buildWarehousesTab()],
                    ),
                  ),
                ],
              ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            if (_tabController.index == 0) {
              showAddBranchDialog();
            } else {
              showAddWarehouseDialog();
            }
          },
          backgroundColor: AppColors.primary,
          icon: const Icon(PhosphorIconsBold.plus, color: Colors.white),
          label: Text(
            _tabController.index == 0 ? 'فرع جديد' : 'مخزن جديد',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _buildBranchesTab() {
    var filteredBranches = _userBranchAccessIds.isEmpty
        ? _branches
        : _branches.where((b) => _userBranchAccessIds.contains(b.id)).toList();
    if (_searchQuery.isNotEmpty) {
      filteredBranches = filteredBranches.where((b) =>
        (b.name as String).toLowerCase().contains(_searchQuery) ||
        ((b.address as String?) ?? '').toLowerCase().contains(_searchQuery) ||
        ((b.phone as String?) ?? '').contains(_searchQuery)
      ).toList();
    }

    if (filteredBranches.isEmpty) {
      return _buildEmptyState('لا توجد فروع', 'أضف فرعاً جديداً للبدء');
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filteredBranches.length,
      itemBuilder: (ctx, index) {
        final branch = filteredBranches[index];
        final ccName = branch.costCenterId != null ? _costCenterMap[branch.costCenterId!] : null;
        final whCount = _branchWarehouseCount[branch.id] ?? 0;
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.primary.withValues(alpha: 0.1),
              child: const Icon(PhosphorIconsBold.buildings, color: AppColors.primary),
            ),
            title: Text(branch.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (branch.address != null && branch.address!.isNotEmpty)
                  Text('📍 ${branch.address}'),
                if (branch.phone != null && branch.phone!.isNotEmpty)
                  Text('📞 ${branch.phone}'),
                if (ccName != null)
                  Text('🎯 مركز التكلفة: $ccName',
                      style: TextStyle(color: AppColors.primary.withValues(alpha: 0.8), fontSize: 12)),
                if (whCount > 0)
                  Text('🏭 المخازن: $whCount',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              ],
            ),
            isThreeLine: true,
            trailing: const Icon(Icons.more_vert),
            onTap: () => showBranchActionsDialog(branch),
          ),
        );
      },
    );
  }

  Widget _buildWarehousesTab() {
    var filteredWarehouses = _userWarehouseAccessIds.isEmpty
        ? _warehouses
        : _warehouses.where((w) => _userWarehouseAccessIds.contains(w.id)).toList();
    if (_searchQuery.isNotEmpty) {
      filteredWarehouses = filteredWarehouses.where((w) =>
        (w.name as String).toLowerCase().contains(_searchQuery)
      ).toList();
    }

    if (filteredWarehouses.isEmpty) {
      return _buildEmptyState('لا توجد مخازن', 'أضف مخزناً جديداً للبدء');
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filteredWarehouses.length,
      itemBuilder: (ctx, index) {
        final warehouse = filteredWarehouses[index];
        final branchName = (warehouse as Warehouse).branchId != null ? _branchNameMap[warehouse.branchId!] : null;
        final ccName = warehouse.costCenterId != null ? _costCenterMap[warehouse.costCenterId!] : null;
        // Map type to Arabic label
        String typeLabel;
        Color typeColor;
        switch (warehouse.type) {
          case 'raw_materials':
            typeLabel = 'خامات';
            typeColor = Colors.orange;
            break;
          case 'finished_goods':
            typeLabel = 'منتج تام';
            typeColor = Colors.blue;
            break;
          case 'retail':
            typeLabel = 'بيع';
            typeColor = Colors.purple;
            break;
          default:
            typeLabel = 'عام';
            typeColor = Colors.grey;
        }
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: warehouse.isDefault
                  ? Colors.green.withValues(alpha: 0.1)
                  : Colors.grey.withValues(alpha: 0.1),
              child: Icon(
                PhosphorIconsBold.warehouse,
                color: warehouse.isDefault ? Colors.green : Colors.grey,
              ),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(warehouse.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                if (warehouse.isDefault) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('افتراضي', style: TextStyle(color: Colors.green, fontSize: 10)),
                  ),
                ],
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(typeLabel,
                      style: TextStyle(color: typeColor, fontSize: 10, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (branchName != null)
                  Text('🏢 الفرع: $branchName', style: const TextStyle(fontSize: 12))
                else
                  const Text('🏢 بدون فرع', style: TextStyle(fontSize: 12, color: Colors.grey)),
                if (ccName != null)
                  Text('🎯 مركز التكلفة: $ccName',
                      style: TextStyle(color: AppColors.primary.withValues(alpha: 0.8), fontSize: 12)),
              ],
            ),
            isThreeLine: warehouse.branchId != null && warehouse.costCenterId != null,
            trailing: const Icon(Icons.more_vert),
            onTap: () => showWarehouseActionsDialog(warehouse),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            PhosphorIconsBold.buildings,
            size: 64,
            color: Colors.grey.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(subtitle, style: TextStyle(color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  // NOTE: All dialog methods, action handlers, edit forms, stats, and
  // quick cost center creation have been extracted to
  // branch_management_dialogs.dart via _BranchManagementDialogsMixin
}