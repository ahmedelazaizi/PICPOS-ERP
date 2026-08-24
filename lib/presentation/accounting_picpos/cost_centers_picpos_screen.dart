import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../data/providers/providers.dart';
import '../../domain/repositories/accounting_repository.dart';
import '../picpos_shell/picpos_content_card.dart';
import '../picpos_shell/picpos_dialog.dart';
import '../picpos_shell/picpos_empty_state.dart';
import '../picpos_shell/picpos_screen_scaffold.dart';
import '../picpos_shell/picpos_section_header.dart';
import '../picpos_shell/picpos_toolbar.dart';
import '../screens/widgets/dialogs/cost_center_edit_dialog.dart';
import '../picpos_shell/picpos_surface.dart';

/// مراكزُ التكلفة بهويّة PicPos — تبويبُ `cc` في حاويةِ الحسابات.
///
/// التصميمُ لوحتان: شجرةٌ يمينَ التفاصيل، والتفاصيلُ فيها ترويسةُ المركز
/// وبطاقاتُه ثمّ الكياناتُ المرتبطةُ ثمّ حركاتُ المركز.
///
/// ⚠️ **«الموازنة» في التصميم لا عمودَ لها في القاعدة.** جدولُ `CostCenters`
/// فيه `code` و`name` و`parentId` و`isActive` فقط — **لا `budget`**. فشريطُ
/// «المنصرف مقابل الموازنة» ونسبُه وتوزيعُ «المصروف على البنود» كلُّها بلا
/// سند، ولم تُختلَق. ومكانَها ما يُقاس فعلاً: الرصيدُ من
/// `getCostCenterBalance` وحركاتُه من `getCostCenterLedger`.
///
/// ⚠️ **ولا يستورد `data/database` مباشرةً** خلافاً لأصله: الأصلُ سابقٌ
/// لحارس `presentation_db_import_guard` فمُتسامَحٌ معه، والملفُّ الجديدُ
/// يرفضه الحارس. والأنواعُ تصل عبر `providers.dart` (استيرادٌ غيرُ مباشرٍ
/// ليس مخالفة).
class CostCentersPicPosScreen extends ConsumerStatefulWidget {
  const CostCentersPicPosScreen({super.key});

  @override
  ConsumerState<CostCentersPicPosScreen> createState() =>
      _CostCentersPicPosScreenState();
}

class _CostCentersPicPosScreenState
    extends ConsumerState<CostCentersPicPosScreen> {
  int? _selectedId;
  bool _showInactive = false;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(accountingRepositoryProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: StreamBuilder<List<CostCenter>>(
        stream: repo.watchCostCenters(),
        builder: (context, snapshot) {
          final all = snapshot.data ?? const <CostCenter>[];

          // ⚠️ العدّاداتُ من القائمة **غيرِ المرشَّحة**.
          final total = all.length;
          final active = all.where((c) => c.isActive).length;

          var visible = _showInactive
              ? all
              : all.where((c) => c.isActive).toList();
          if (_query.isNotEmpty) {
            final q = _query.toLowerCase();
            visible = visible
                .where((c) =>
                    c.name.toLowerCase().contains(q) ||
                    c.code.toLowerCase().contains(q))
                .toList();
          }

          return PicPosScreenScaffold(
            title: 'مراكز التكلفة',
            subtitle: 'توزيع المصروفات والإيرادات على المراكز',
            icon: PhosphorIconsBold.crosshair,
            headerSearch: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'بحث باسم أو رمز المركز...',
                prefixIcon:
                    const Icon(PhosphorIconsBold.magnifyingGlass, size: 16),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(PhosphorIconsBold.x, size: 14),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
              ),
            ),
            // ⚠️ الترويسةُ `Row` بلا تقييدٍ في `PicPosPageHeader`، فأفعالٌ
            //    ثقيلةٌ تفيض عند ١٢٨٠ وتمرّ عند ١٩٢٠ (‏قِيس: فيضانُ ١٧٣px).
            //    فالزرُّ وحدَه هنا، والعدّادُ والمفتاحُ في الشريط الذي يلتفّ.
            headerActions: [
              FilledButton.icon(
                onPressed: () => _openEditor(),
                icon: const Icon(PhosphorIconsBold.plus, size: 16),
                label: const Text('مركز تكلفة'),
              ),
            ],
            toolbar: PicPosToolbar(
              children: [
                Text('$active من $total نشط',
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(color: AppColors.textMuted)),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('عرض غير النشطة',
                        style: Theme.of(context).textTheme.labelMedium),
                    Switch(
                      value: _showInactive,
                      onChanged: (v) => setState(() => _showInactive = v),
                    ),
                  ],
                ),
              ],
            ),
            body: snapshot.hasData
                ? _buildSplit(repo, visible, total)
                : const Center(child: CircularProgressIndicator()),
          );
        },
      ),
    );
  }

  Widget _buildSplit(
    IAccountingRepository repo,
    List<CostCenter> visible,
    int total,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 3, child: _buildTree(visible, total)),
        const SizedBox(width: 12),
        Expanded(flex: 4, child: _buildDetail(repo, visible)),
      ],
    );
  }

  Widget _buildTree(List<CostCenter> visible, int total) {
    final roots = visible.where((c) => c.parentId == null).toList();

    return PicPosContentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PicPosSectionHeader(
            title: 'الهيكل الشجري',
            icon: PhosphorIconsBold.treeStructure,
            subtitle: '${visible.length} معروض من $total',
          ),
          Expanded(
            child: visible.isEmpty
                ? PicPosEmptyState(
                    icon: PhosphorIconsBold.crosshair,
                    title: total == 0
                        ? 'لا مراكزَ تكلفة'
                        : 'لا مركزَ يطابق البحث',
                    hint: total == 0
                        ? 'أضف مركزاً لتوزيع المصروفات والإيرادات عليه.'
                        : null,
                  )
                : ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      for (final root in roots)
                        ..._treeNodes(root, visible, 0),
                      // مراكزُ ظهرت بالبحث وأصلُها مخفيٌّ — لا تُبتلَع.
                      for (final orphan in visible.where((c) =>
                          c.parentId != null &&
                          !visible.any((p) => p.id == c.parentId)))
                        ..._treeNodes(orphan, visible, 0),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  List<Widget> _treeNodes(
    CostCenter node,
    List<CostCenter> all,
    int depth,
  ) {
    final children = all.where((c) => c.parentId == node.id).toList();
    return [
      _TreeTile(
        center: node,
        depth: depth,
        selected: node.id == _selectedId,
        childCount: children.length,
        onTap: () => setState(() => _selectedId = node.id),
      ),
      for (final child in children) ..._treeNodes(child, all, depth + 1),
    ];
  }

  Widget _buildDetail(IAccountingRepository repo, List<CostCenter> visible) {
    if (_selectedId == null) {
      return const PicPosContentCard(
        child: PicPosEmptyState(
          icon: PhosphorIconsBold.cursorClick,
          title: 'اختر مركز تكلفة لعرض التفاصيل',
        ),
      );
    }

    final center = visible.where((c) => c.id == _selectedId).firstOrNull;
    if (center == null) {
      return const PicPosContentCard(
        child: PicPosEmptyState(
          icon: PhosphorIconsBold.cursorClick,
          title: 'المركزُ المحدَّدُ خارجَ الترشيح الحاليّ',
          hint: 'ارفع البحثَ أو فعّل «عرض غير النشطة».',
        ),
      );
    }

    final childCount = visible.where((c) => c.parentId == center.id).length;

    return PicPosContentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PicPosSectionHeader(
            title: '${center.code} — ${center.name}',
            icon: PhosphorIconsBold.crosshair,
            subtitle: center.parentId == null ? 'مركز رئيسي' : 'مركز فرعي',
            actions: [
              IconButton(
                tooltip: 'تعديل',
                icon: const Icon(PhosphorIconsBold.pencilSimple, size: 16),
                onPressed: () => _openEditor(existing: center),
              ),
              IconButton(
                tooltip: 'إضافة مركز فرعي',
                icon: const Icon(PhosphorIconsBold.plus, size: 16),
                onPressed: () => _openEditor(parentId: center.id),
              ),
              if (center.isActive)
                IconButton(
                  tooltip: 'تعطيل',
                  icon: const Icon(PhosphorIconsBold.prohibit, size: 16),
                  color: AppColors.error,
                  onPressed: () => _confirmDeactivate(repo, center),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _buildInfoRow(repo, center, childCount),
          const SizedBox(height: 12),
          _LinkedEntities(centerId: center.id),
          const SizedBox(height: 12),
          Expanded(child: _buildLedger(repo, center)),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    IAccountingRepository repo,
    CostCenter center,
    int childCount,
  ) {
    return Row(
      children: [
        Expanded(
          child: _InfoCard(
            label: 'الحالة',
            value: center.isActive ? 'نشط' : 'معطل',
            tint: center.isActive ? AppColors.success : AppColors.textMuted,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _InfoCard(
            label: 'النوع',
            value: center.parentId == null ? 'فرع رئيسي' : 'مركز فرعي',
            tint: AppColors.info,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _InfoCard(
            label: 'مراكز فرعية',
            value: '$childCount',
            tint: AppColors.warning,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FutureBuilder<Map<String, double>>(
            future: repo.getCostCenterBalance(center.id),
            builder: (context, snap) {
              final debit = snap.data?['debit'] ?? 0.0;
              final credit = snap.data?['credit'] ?? 0.0;
              // ⚠️ الصافي (مدين − دائن) لا مجموعُ الطرفين — الجمعُ يعدّ
              //    الحركةَ مرّتين. والتسميةُ «الرصيد» لأنّه رصيدٌ ختاميٌّ
              //    يساوي آخرَ صفٍّ في دفتر المركز، لا دورةَ حركةٍ إجماليّة.
              return _InfoCard(
                label: 'الرصيد',
                value: snap.hasData
                    ? '${(debit - credit).toStringAsFixed(0)} '
                        '${AppConstants.currencySymbol}'
                    : '—',
                tint: AppColors.primary,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLedger(IAccountingRepository repo, CostCenter center) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: repo.getCostCenterLedger(
        center.id,
        DateTime(DateTime.now().year, 1, 1),
        DateTime.now(),
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snapshot.data!;
        final moves = rows.where((r) => r['is_opening'] != true).length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PicPosSectionHeader(
              title: 'حركات المركز',
              icon: PhosphorIconsBold.notebook,
              subtitle: '$moves حركة · من أول العام',
            ),
            Expanded(
              child: rows.isEmpty
                  ? const PicPosEmptyState(
                      icon: PhosphorIconsBold.notebook,
                      title: 'لا حركاتِ على هذا المركز',
                    )
                  : ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: rows.length,
                      itemBuilder: (ctx, i) =>
                          _MovementRow(row: rows[i], striped: i.isEven),
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openEditor({CostCenter? existing, int? parentId}) async {
    await showDialog(
      context: context,
      builder: (_) => CostCenterEditDialog(
        existing: existing,
        initialParentId: parentId,
      ),
    );
  }

  Future<void> _confirmDeactivate(
    IAccountingRepository repo,
    CostCenter center,
  ) async {
    final confirmed = await showPicPosConfirm(
      context,
      icon: PhosphorIconsBold.prohibit,
      title: 'تعطيل مركز التكلفة',
      subtitle: '${center.code} — ${center.name}',
      message: 'سيختفي المركزُ من قوائم الاختيار ولا تُحذف حركاتُه السابقة. '
          'يمكن إظهارُه مجدَّداً بمفتاح «عرض غير النشطة».',
      confirmLabel: 'تعطيل',
      danger: true,
    );
    if (!confirmed) return;
    await repo.deactivateCostCenter(center.id);
  }
}

class _TreeTile extends StatelessWidget {
  const _TreeTile({
    required this.center,
    required this.depth,
    required this.selected,
    required this.childCount,
    required this.onTap,
  });

  final CostCenter center;
  final int depth;
  final bool selected;
  final int childCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final tint = center.isActive ? AppColors.primary : AppColors.textMuted;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsetsDirectional.only(
          start: 10.0 + depth * 16,
          end: 10,
          top: 8,
          bottom: 8,
        ),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.08)
              : Colors.transparent,
          // ‏`BorderDirectional` لا `Border`: الحدُّ المميِّزُ للمحدَّد يجب
          // أن يتبع اتجاهَ RTL فيقع يميناً.
          border: BorderDirectional(
            bottom: BorderSide(color: context.picposHairline),
            start: BorderSide(
              color: selected ? AppColors.primary : Colors.transparent,
              width: 2.5,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              childCount > 0
                  ? PhosphorIconsBold.folderOpen
                  : PhosphorIconsBold.crosshair,
              size: 15,
              color: tint,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    center.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelLarge?.copyWith(
                      fontWeight:
                          selected ? FontWeight.w800 : FontWeight.w700,
                      color: center.isActive
                          ? context.picposText
                          : AppColors.textMuted,
                    ),
                  ),
                  Text(center.code,
                      style: text.labelSmall
                          ?.copyWith(color: AppColors.textMuted)),
                ],
              ),
            ),
            if (!center.isActive)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.textMuted.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text('معطل',
                    style: text.labelSmall
                        ?.copyWith(color: AppColors.textMuted)),
              ),
          ],
        ),
      ),
    );
  }
}

/// الفروعُ والمخازنُ المرتبطةُ بالمركز — وتحذيرٌ صريحٌ حين لا ارتباط،
/// لأنّ مركزاً بلا كيانٍ لا يستقبل حركةً تلقائيّة.
class _LinkedEntities extends ConsumerWidget {
  const _LinkedEntities({required this.centerId});

  final int centerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(branchRepositoryProvider);
    return FutureBuilder<List<List<dynamic>>>(
      future: Future.wait([repo.getBranches(), repo.getWarehouses()]),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final branches = (snap.data![0] as List<Branche>)
            .where((b) => b.costCenterId == centerId)
            .toList();
        final warehouses = (snap.data![1] as List<Warehouse>)
            .where((w) => w.costCenterId == centerId)
            .toList();

        if (branches.isEmpty && warehouses.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.06),
              border:
                  Border.all(color: AppColors.warning.withValues(alpha: 0.25)),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              children: [
                const Icon(PhosphorIconsBold.info,
                    size: 15, color: AppColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'لا توجد فروع أو مخازن مرتبطة بهذا المركز',
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(color: AppColors.warning),
                  ),
                ),
              ],
            ),
          );
        }

        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final b in branches)
              _EntityChip(
                  icon: PhosphorIconsBold.buildings, label: b.name),
            for (final w in warehouses)
              _EntityChip(icon: PhosphorIconsBold.package, label: w.name),
          ],
        );
      },
    );
  }
}

class _EntityChip extends StatelessWidget {
  const _EntityChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: context.picposField,
        border: Border.all(color: context.picposHairline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.label,
    required this.value,
    required this.tint,
  });

  final String label;
  final String value;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.06),
        border: Border.all(color: tint.withValues(alpha: 0.20)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: text.labelSmall?.copyWith(color: AppColors.textMuted)),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.titleSmall
                ?.copyWith(color: tint, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _MovementRow extends StatelessWidget {
  const _MovementRow({required this.row, required this.striped});

  final Map<String, dynamic> row;
  final bool striped;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final isOpening = row['is_opening'] == true;
    final date = row['entry_date'];
    final dateStr = date is DateTime
        ? DateFormat('yyyy/MM/dd').format(date)
        : date?.toString() ?? '';
    final debit = (row['debit'] as num?)?.toDouble() ?? 0;
    final credit = (row['credit'] as num?)?.toDouble() ?? 0;
    final balance = (row['balance'] as num?)?.toDouble() ?? 0;
    final desc = row['line_desc']?.toString() ??
        row['entry_desc']?.toString() ??
        '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: isOpening
            ? AppColors.primary.withValues(alpha: 0.06)
            : (striped ? context.picposField : Colors.transparent),
        border: Border(bottom: BorderSide(color: context.picposHairline)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 82,
            child: Text(dateStr,
                style: text.labelSmall?.copyWith(color: AppColors.textMuted)),
          ),
          SizedBox(
            width: 78,
            child: Text(
              row['entry_number']?.toString() ?? '',
              style: text.labelSmall?.copyWith(
                  color: AppColors.primary, fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(
            child: Text(
              desc,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.labelMedium?.copyWith(
                fontWeight: isOpening ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          SizedBox(
            width: 88,
            child: Text(
              row['account_name']?.toString() ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.labelSmall?.copyWith(color: AppColors.textMuted),
            ),
          ),
          SizedBox(
            width: 78,
            child: Text(
              debit > 0
                  ? debit.toStringAsFixed(AppConstants.decimalPlaces)
                  : '-',
              textAlign: TextAlign.end,
              style: text.labelSmall?.copyWith(
                color: debit > 0 ? AppColors.success : AppColors.textMuted,
                fontWeight: debit > 0 ? FontWeight.w800 : FontWeight.normal,
              ),
            ),
          ),
          SizedBox(
            width: 78,
            child: Text(
              credit > 0
                  ? credit.toStringAsFixed(AppConstants.decimalPlaces)
                  : '-',
              textAlign: TextAlign.end,
              style: text.labelSmall?.copyWith(
                color: credit > 0 ? AppColors.error : AppColors.textMuted,
                fontWeight: credit > 0 ? FontWeight.w800 : FontWeight.normal,
              ),
            ),
          ),
          SizedBox(
            width: 88,
            child: Text(
              balance.toStringAsFixed(AppConstants.decimalPlaces),
              textAlign: TextAlign.end,
              style: text.labelSmall?.copyWith(
                  color: AppColors.primary, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}
