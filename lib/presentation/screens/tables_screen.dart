import 'package:ural_erp/core/i18n/tr.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/widgets/app_toast.dart';
import '../../core/constants/app_constants.dart';
import '../../core/logging/diagnostic_logger.dart';
import '../../core/theme/app_colors.dart';
import '../../core/permissions/permission_codes.dart';
import '../../data/providers/providers.dart';
import '../../domain/entities/product_entity.dart';
import '../../domain/models/table_actions.dart';
import '../../domain/models/table_status.dart';
import '../../domain/repositories/restaurant_repository.dart';
import '../../services/invoice_generator.dart';
import '../pos/screens/pos_table_service_screen.dart';
import '../widgets/permission_guard.dart';
import 'tables/tables.dart';
import 'tables/merge_table_dialog.dart';
import 'tables/split_table_dialog.dart';
import 'tables/table_log_sheet.dart';
import 'tables/transfer_dialog.dart';
import '../../data/services/receipt_qr_resolver.dart';
import '../../domain/models/receipt_qr_decision.dart';

// ── Part files (dialogs and mixed logic) ─────────────────────────────────
part 'tables/table_order_dialogs.dart';
part 'tables/table_sections_crud.dart';
part 'tables/table_operations.dart';

class TablesScreen extends ConsumerStatefulWidget {
  const TablesScreen({super.key});

  @override
  ConsumerState<TablesScreen> createState() => _TablesScreenState();
}

class _TablesScreenState extends ConsumerState<TablesScreen>
    with
        SingleTickerProviderStateMixin,
        _TableOrderDialogsMixin,
        _TableSectionsMixin,
        _TableOperationsMixin {
  TabController? _tabController;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final restaurantRepo = ref.watch(restaurantRepositoryProvider);
    final uiState = ref.watch(tablesUIProvider);
  // ignore: unused_local_variable
    final uiNotifier = ref.read(tablesUIProvider.notifier);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF080E1E),
        body: Column(
          children: [
            TablesTopBar(
              onAddTable: () => _showAddTableDialog(context, restaurantRepo),
              onManageSections: () => _showSectionsManager(context, restaurantRepo),
            ),
            const TablesFilterBar(),
            Expanded(
              child: Row(
                children: [
                  // Left Panel: Floor Plan / Grid
                  Expanded(
                    flex: 3,
                    child: _buildMainContent(restaurantRepo, uiState),
                  ),

                  // Right Panel: Order Details
                  Container(
                    width: 380,
                    margin: const EdgeInsetsDirectional.only(end: 12, bottom: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF111827),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                    ),
                    child: _buildRightPanel(restaurantRepo, uiState),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent(IRestaurantRepository repo, TablesUIState state) {
    return StreamBuilder<List<TableSection>>(
      stream: repo.watchAllSections(),
      builder: (context, snap) {
        final sections = snap.data ?? [];
        if (sections.isEmpty) return _buildEmptySectionsState(repo);

        if (_tabController == null || _tabController!.length != sections.length) {
          _tabController?.dispose();
          _tabController = TabController(length: sections.length, vsync: this);
        }

        return Column(
          children: [
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabs: sections.map((s) => Tab(text: s.name)).toList(),
              labelStyle: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: sections.map((s) => _buildTablesGrid(repo, s, state)).toList(),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTablesGrid(IRestaurantRepository repo, TableSection section, TablesUIState state) {
    return StreamBuilder<List<RestaurantTable>>(
      stream: repo.watchTablesInSection(section.id),
      builder: (context, snap) {
        var tables = snap.data ?? [];
        if (state.statusFilter != 'all') {
          tables = tables.where((t) => t.status == state.statusFilter).toList();
        }

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: state.tableCardSize,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 1,
          ),
          itemCount: tables.length,
          itemBuilder: (context, index) {
            final table = tables[index];
            return TableCard(
              table: table,
              restaurantRepo: repo,
              onInteraction: (t) => _handleTableTapNew(t, repo),
            );
          },
        );
      },
    );
  }

  Widget _buildRightPanel(IRestaurantRepository repo, TablesUIState state) {
    if (state.selectedTableId == null) return _buildNoTableSelected();
    
    return FutureBuilder<RestaurantTable?>(
      future: repo.getAllTables().then((tables) => 
        tables.where((t) => t.id == state.selectedTableId).firstOrNull),
      builder: (context, snap) {
        final table = snap.data;
        if (table == null) return _buildNoTableSelected();
        return TableOrderPanel(
          table: table,
          onOpenOrder: () => _showTableOptions(context, repo, table),
          onShowOrder: () => _showTableOrderDialog(context, repo, table),
          onTransfer: () => _handleTransferOrder(context, repo, table),
          onSplit: () => _handleSplitTable(context, repo, table),
        );
      },
    );
  }

  Widget _buildNoTableSelected() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(PhosphorIconsBold.cursor, size: 44, color: Colors.white.withValues(alpha: 0.1)),
          const SizedBox(height: 20),
          Text(tr('اختر طاولة'), style: GoogleFonts.cairo(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white.withValues(alpha: 0.2))),
        ],
      ),
    );
  }

  Widget _buildEmptySectionsState(IRestaurantRepository repo) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(PhosphorIconsBold.mapPin, size: 48, color: Colors.white.withValues(alpha: 0.15)),
          const SizedBox(height: 16),
          Text(
            tr('لا توجد أقسام'),
            style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white.withValues(alpha: 0.3)),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () => _showSectionsManager(context, repo),
            icon: const Icon(PhosphorIconsBold.plus),
            label: Text(tr('إضافة قسم'), style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );
  }

  void _showSectionsManager(BuildContext context, IRestaurantRepository repo) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(tr('إدارة الأقسام'), style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: 400,
            height: 400,
            child: StreamBuilder<List<TableSection>>(
              stream: repo.watchAllSections(),
              builder: (context, snap) {
                final sections = snap.data ?? [];
                if (sections.isEmpty) {
                  return  Center(child: Text(tr('لا توجد أقسام')));
                }
                return ListView.separated(
                  itemCount: sections.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final section = sections[i];
                    return ListTile(
                      title: Text(section.name, style: GoogleFonts.cairo()),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          PermissionGuard(
                            permission: PermissionCodes.tablesManage,
                            allowManagerOverride: true,
                            actionName: tr('تعديل قسم طاولات'),
                            onGranted: () =>
                                _showEditSectionDialog(context, repo, section),
                            child: IconButton(
                              icon: const Icon(PhosphorIconsBold.pencil, size: 18, color: AppColors.primary),
                              onPressed: () => _showEditSectionDialog(context, repo, section),
                            ),
                          ),
                          PermissionGuard(
                            permission: PermissionCodes.tablesManage,
                            allowManagerOverride: true,
                            actionName: tr('حذف قسم طاولات'),
                            onGranted: () =>
                                _confirmDeleteSection(context, repo, section),
                            child: IconButton(
                              icon: const Icon(PhosphorIconsBold.trash, size: 18, color: AppColors.error),
                              onPressed: () => _confirmDeleteSection(context, repo, section),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            PermissionGuard(
              permission: PermissionCodes.tablesManage,
              allowManagerOverride: true,
              actionName: tr('إضافة قسم طاولات'),
              onGranted: () => _showAddSectionDialog(ctx, repo),
              child: TextButton(
                onPressed: () => _showAddSectionDialog(ctx, repo),
                child:  Text(tr('إضافة قسم')),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:  Text(tr('إغلاق')),
            ),
          ],
        ),
      ),
    );
  }

  void _handleTableTapNew(RestaurantTable table, IRestaurantRepository repo) {
    ref.read(tablesUIProvider.notifier).selectTable(table.id);
    if (table.status == 'available') {
      _confirmOpenTable(repo, table);
    }
  }

  // Preserve interfaces for legacy parts if needed, though mostly cleaned up
  @override
  Future<TableOrder?> _getOpenOrder(IRestaurantRepository repo, int tableId) async {
    return repo.getActiveOrderForTable(tableId);
  }
}
