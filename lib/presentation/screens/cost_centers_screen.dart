import 'package:ural_erp/core/constants/app_constants.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../data/providers/repository_providers.dart';
import '../../data/database/database.dart';
import '../../domain/repositories/accounting_repository.dart';
import 'widgets/dialogs/cost_center_edit_dialog.dart';
import '../widgets/dialogs/app_confirm_dialog.dart';

/// Cost Centers Management Screen — Hierarchical tree with CRUD + ledger view
class CostCentersScreen extends ConsumerStatefulWidget {
  const CostCentersScreen({super.key});

  @override
  ConsumerState<CostCentersScreen> createState() => _CostCentersScreenState();
}

class _CostCentersScreenState extends ConsumerState<CostCentersScreen> {
  int? _selectedCenterId;
  bool _showInactive = false;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(accountingRepositoryProvider);

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: StreamBuilder<List<CostCenter>>(
                stream: repo.watchCostCenters(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  var centers = snapshot.data!;

                  // Filter inactive
                  if (!_showInactive) {
                    centers = centers.where((c) => c.isActive).toList();
                  }

                  // Filter by search
                  final query = _searchCtrl.text.trim().toLowerCase();
                  if (query.isNotEmpty) {
                    centers = centers.where((c) =>
                        c.name.toLowerCase().contains(query) ||
                        c.code.toLowerCase().contains(query)).toList();
                  }

                  return Row(
                    children: [
                      // Left panel: Tree view
                      Expanded(
                        flex: 3,
                        child: _buildTreePanel(context, repo, centers),
                      ),
                      // Right panel: Detail/Ledger view
                      Expanded(
                        flex: 4,
                        child: _buildDetailPanel(context, repo, centers),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryDark, AppColors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(PhosphorIconsBold.treeStructure, color: Colors.white, size: 24),
          const SizedBox(width: 12),
          Text(
            'مراكز التكلفة والفروع',
            style: GoogleFonts.cairo(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 24),
          // Search
          SizedBox(
            width: 250,
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              style: GoogleFonts.cairo(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'بحث بالاسم أو الرمز...',
                hintStyle: GoogleFonts.cairo(color: Colors.white60, fontSize: 13),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.15),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, color: Colors.white70, size: 16),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
          const Spacer(),
          // Toggle inactive
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('عرض غير النشطة', style: GoogleFonts.cairo(color: Colors.white70, fontSize: 12)),
              Switch(
                value: _showInactive,
                onChanged: (v) => setState(() => _showInactive = v),
                activeThumbColor: Colors.white,
              ),
            ],
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: () => _showAddDialog(context),
            icon: const Icon(PhosphorIconsBold.plus, size: 16),
            label: Text('إضافة مركز تكلفة', style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTreePanel(BuildContext context, IAccountingRepository repo, List<CostCenter> centers) {
    // Build tree: roots first (parentId == null), then children
    final roots = centers.where((c) => c.parentId == null).toList();

    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(PhosphorIconsBold.treeStructure, size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Text('الهيكل الشجري', style: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 14)),
                const Spacer(),
                Text(
                  '${centers.length} مركز',
                  style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: roots.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(PhosphorIconsBold.treeStructure, size: 48, color: AppColors.textMuted),
                        const SizedBox(height: 8),
                        Text(
                          'لا توجد مراكز تكلفة',
                          style: GoogleFonts.cairo(color: AppColors.textMuted, fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'أضف فرع أو مركز تكلفة للبدء',
                          style: GoogleFonts.cairo(color: AppColors.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    children: roots.map((root) => _buildTreeNode(context, repo, root, centers, 0)).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTreeNode(BuildContext context, IAccountingRepository repo, CostCenter node, List<CostCenter> all, int depth) {
    final children = all.where((c) => c.parentId == node.id).toList();
    final isSelected = _selectedCenterId == node.id;
    final hasChildren = children.isNotEmpty;
    final isRoot = node.parentId == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _selectedCenterId = node.id),
          child: Container(
            padding: EdgeInsets.only(
              right: 12 + (depth * 20.0),
              left: 8,
              top: 8,
              bottom: 8,
            ),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primary.withValues(alpha: 0.08) : null,
              border: isSelected
                  ? const Border(right: BorderSide(color: AppColors.primary, width: 3))
                  : null,
            ),
            child: Row(
              children: [
                // Branch/Leaf icon
                Icon(
                  isRoot
                      ? PhosphorIconsBold.buildings
                      : (hasChildren ? PhosphorIconsBold.folder : PhosphorIconsBold.tag),
                  size: 16,
                  color: isSelected
                      ? AppColors.primary
                      : (!node.isActive ? AppColors.textMuted : (isRoot ? AppColors.warning : AppColors.textSecondary)),
                ),
                const SizedBox(width: 8),
                // Code badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    node.code,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Name
                Expanded(
                  child: Text(
                    node.name,
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: !node.isActive
                          ? AppColors.textMuted
                          : (isSelected ? AppColors.primary : AppColors.textPrimary),
                      decoration: !node.isActive ? TextDecoration.lineThrough : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!node.isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text('معطل', style: GoogleFonts.cairo(fontSize: 8, color: AppColors.error)),
                  ),
                if (hasChildren)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      color: AppColors.textMuted.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      '${children.length}',
                      style: GoogleFonts.jetBrainsMono(fontSize: 8, color: AppColors.textMuted),
                    ),
                  ),
              ],
            ),
          ),
        ),
        // Render children recursively
        ...children.map((child) => _buildTreeNode(context, repo, child, all, depth + 1)),
      ],
    );
  }

  Widget _buildDetailPanel(BuildContext context, IAccountingRepository repo, List<CostCenter> centers) {
    if (_selectedCenterId == null) {
      return Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(PhosphorIconsBold.cursorClick, size: 48, color: AppColors.textMuted.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              Text(
                'اختر مركز تكلفة لعرض التفاصيل',
                style: GoogleFonts.cairo(color: AppColors.textMuted, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    final center = centers.where((c) => c.id == _selectedCenterId).firstOrNull;
    if (center == null) {
      return const Center(child: Text('مركز التكلفة غير موجود'));
    }

    final children = centers.where((c) => c.parentId == center.id).toList();
    final parent = center.parentId != null
        ? centers.where((c) => c.id == center.parentId).firstOrNull
        : null;

    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 12, left: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with actions
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  center.parentId == null ? PhosphorIconsBold.buildings : PhosphorIconsBold.tag,
                  color: AppColors.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        center.name,
                        style: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                      Row(
                        children: [
                          Text(
                            'الرمز: ${center.code}',
                            style: GoogleFonts.jetBrainsMono(fontSize: 11, color: AppColors.textMuted),
                          ),
                          if (parent != null) ...[
                            const SizedBox(width: 12),
                            Text(
                              'تابع لـ: ${parent.name}',
                              style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textMuted),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // Edit button
                IconButton(
                  onPressed: () => _showEditDialog(context, center),
                  icon: const Icon(PhosphorIconsBold.pencilSimple, size: 16),
                  tooltip: 'تعديل',
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                    foregroundColor: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 4),
                // Add child button
                IconButton(
                  onPressed: () => _showAddDialog(context, parentId: center.id),
                  icon: const Icon(PhosphorIconsBold.plus, size: 16),
                  tooltip: 'إضافة مركز فرعي',
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.success.withValues(alpha: 0.08),
                    foregroundColor: AppColors.success,
                  ),
                ),
                const SizedBox(width: 4),
                // Deactivate button
                if (center.isActive)
                  IconButton(
                    onPressed: () => _confirmDeactivate(context, repo, center),
                    icon: const Icon(PhosphorIconsBold.prohibit, size: 16),
                    tooltip: 'تعطيل',
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.error.withValues(alpha: 0.08),
                      foregroundColor: AppColors.error,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Info cards row
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _buildInfoCard(
                  'الحالة',
                  center.isActive ? 'نشط ✓' : 'معطل ✗',
                  center.isActive ? AppColors.success : AppColors.error,
                ),
                const SizedBox(width: 8),
                _buildInfoCard(
                  'النوع',
                  center.parentId == null ? 'فرع رئيسي' : 'مركز فرعي',
                  AppColors.primary,
                ),
                const SizedBox(width: 8),
                _buildInfoCard(
                  'مراكز فرعية',
                  '${children.length}',
                  AppColors.warning,
                ),
                const SizedBox(width: 8),
                // Balance card
                FutureBuilder<Map<String, double>>(
                  future: repo.getCostCenterBalance(center.id),
                  builder: (context, snap) {
                    final debit = snap.data?['debit'] ?? 0.0;
                    final credit = snap.data?['credit'] ?? 0.0;
                    // Spec 150 (a): net (debit − credit), not the sum of both
                    // legs — summing double-counts. Labelled «الرصيد» because
                    // the value is a closing balance (it equals the ledger's
                    // last running-balance row), not gross turnover.
                    return _buildInfoCard(
                      'الرصيد',
                      '${(debit - credit).toStringAsFixed(0)} ${AppConstants.currencySymbol}',
                      AppColors.primary,
                    );
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // ─── Linked Branches & Warehouses ───
          FutureBuilder<List<List<dynamic>>>(
            future: Future.wait([
              ref.read(branchRepositoryProvider).getBranches(),
              ref.read(branchRepositoryProvider).getWarehouses(),
            ]),
            builder: (context, snap) {
              if (!snap.hasData) return const SizedBox.shrink();
              final allBranches = snap.data![0] as List<Branche>;
              final allWarehouses = snap.data![1] as List<Warehouse>;
              final linkedBranches = allBranches.where((b) => b.costCenterId == center.id).toList();
              final linkedWarehhouses = allWarehouses.where((w) => w.costCenterId == center.id).toList();

              if (linkedBranches.isEmpty && linkedWarehhouses.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(PhosphorIconsBold.info, size: 16, color: Colors.orange),
                        const SizedBox(width: 8),
                        Text(
                          'لا توجد فروع أو مخازن مرتبطة بهذا المركز',
                          style: GoogleFonts.cairo(fontSize: 12, color: Colors.orange.shade700),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('الكيانات المرتبطة',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        ...linkedBranches.map((b) => Chip(
                              avatar: const Icon(PhosphorIconsBold.buildings, size: 14, color: AppColors.primary),
                              label: Text(b.name, style: GoogleFonts.cairo(fontSize: 11)),
                              backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                              side: BorderSide(color: AppColors.primary.withValues(alpha: 0.2)),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            )),
                        ...linkedWarehhouses.map((w) => Chip(
                              avatar: const Icon(PhosphorIconsBold.warehouse, size: 14, color: Colors.green),
                              label: Text(w.name, style: GoogleFonts.cairo(fontSize: 11)),
                              backgroundColor: Colors.green.withValues(alpha: 0.08),
                              side: BorderSide(color: Colors.green.withValues(alpha: 0.2)),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            )),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
          const Divider(height: 1),

          // Ledger section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('دفتر الأستاذ', style: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 14)),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: repo.getCostCenterLedger(
                center.id,
                DateTime(DateTime.now().year, 1, 1),
                DateTime.now(),
              ),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final entries = snapshot.data!;
                if (entries.isEmpty) {
                  return Center(
                    child: Text(
                      'لا توجد حركات لهذا المركز',
                      style: GoogleFonts.cairo(color: AppColors.textMuted, fontSize: 13),
                    ),
                  );
                }

                final dateFormat = DateFormat('yyyy/MM/dd');

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: entries.length,
                  itemBuilder: (ctx, i) {
                    final e = entries[i];
                    // Spec 150 (c): getCostCenterLedger now prepends an
                    // opening-balance row — mark it visually like the
                    // general-ledger screen does for its own opening row.
                    final isOpening = e['is_opening'] == true;
                    final date = e['entry_date'] is DateTime
                        ? dateFormat.format(e['entry_date'] as DateTime)
                        : e['entry_date']?.toString() ?? '';
                    final debit = (e['debit'] as num?)?.toDouble() ?? 0;
                    final credit = (e['credit'] as num?)?.toDouble() ?? 0;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isOpening
                            ? AppColors.primary.withValues(alpha: 0.06)
                            : (i.isEven ? AppColors.surface : Colors.white),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 80,
                            child: Text(date, style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppColors.textMuted)),
                          ),
                          SizedBox(
                            width: 80,
                            child: Text(
                              e['entry_number']?.toString() ?? '',
                              style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppColors.primary),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              e['line_desc']?.toString() ?? e['entry_desc']?.toString() ?? '',
                              style: GoogleFonts.cairo(fontSize: 11, fontWeight: isOpening ? FontWeight.w700 : FontWeight.normal),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(
                            width: 70,
                            child: Text(
                              e['account_name']?.toString() ?? '',
                              style: GoogleFonts.cairo(fontSize: 10, color: AppColors.textMuted),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(
                            width: 80,
                            child: Text(
                              debit > 0 ? debit.toStringAsFixed(AppConstants.decimalPlaces) : '-',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10,
                                color: debit > 0 ? AppColors.error : AppColors.textMuted,
                                fontWeight: debit > 0 ? FontWeight.w600 : FontWeight.normal,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          SizedBox(
                            width: 80,
                            child: Text(
                              credit > 0 ? credit.toStringAsFixed(AppConstants.decimalPlaces) : '-',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10,
                                color: credit > 0 ? AppColors.success : AppColors.textMuted,
                                fontWeight: credit > 0 ? FontWeight.w600 : FontWeight.normal,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          // Spec 150 (c): running balance (opening + Σ debit−credit)
                          // so the ledger reconciles with the «إجمالي الحركات» card.
                          SizedBox(
                            width: 84,
                            child: Text(
                              ((e['balance'] as num?)?.toDouble() ?? 0)
                                  .toStringAsFixed(AppConstants.decimalPlaces),
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                              textAlign: TextAlign.center,
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
        ],
      ),
    );
  }

  Widget _buildInfoCard(String title, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(title, style: GoogleFonts.cairo(fontSize: 10, color: AppColors.textMuted)),
            const SizedBox(height: 2),
            Text(
              value,
              style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w700, color: color),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DIALOGS
  // ═══════════════════════════════════════════════════════════════════════════

  void _showAddDialog(BuildContext context, {int? parentId}) async {
    await showDialog(
      context: context,
      builder: (ctx) => CostCenterEditDialog(initialParentId: parentId),
    );
  }

  void _showEditDialog(BuildContext context, CostCenter center) async {
    await showDialog(
      context: context,
      builder: (ctx) => CostCenterEditDialog(existing: center),
    );
  }

  void _confirmDeactivate(BuildContext context, IAccountingRepository repo, CostCenter center) async {
    final confirmed = await AppConfirmDialog.show(
      context,
      title: 'تأكيد التعطيل',
      message: 'هل أنت متأكد من تعطيل مركز التكلفة "${center.name}"؟',
      confirmLabel: 'تعطيل',
      isDangerous: true,
    );

    if (confirmed == true && mounted) {
      await repo.updateCostCenter(
        center.id,
        code: center.code,
        name: center.name,
        parentId: center.parentId,
        isActive: false,
      );
    }
  }
}
