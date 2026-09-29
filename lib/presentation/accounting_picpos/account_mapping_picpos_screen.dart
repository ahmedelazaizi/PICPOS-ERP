import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/arabic_utils.dart';
import '../../core/widgets/app_toast.dart';
import '../../data/providers/providers.dart';
import '../picpos_shell/picpos_content_card.dart';
import '../picpos_shell/picpos_dialog.dart';
import '../picpos_shell/picpos_empty_state.dart';
import '../picpos_shell/picpos_screen_scaffold.dart';
import 'account_mapping_purposes.dart';
import '../picpos_shell/picpos_surface.dart';

/// ربطُ الحسابات بالعمليات بهويّة PicPos — تبويبُ `map` في حاويةِ الحسابات.
///
/// ⚠️ **جدولُ التصميم يصف نموذجاً لا تملكه القاعدة.** أعمدةُ «الطرف المدين ·
/// الطرف الدائن · حساب الضريبة» تفترض لكلّ عمليةٍ ثلاثةَ حسابات، بينما
/// `AccountMappings` هو `purpose → accountId` واحدٌ (‏مع تجاوزٍ اختياريٍّ
/// بمركز تكلفة). فبناءُ الأعمدة الثلاثة يقتضي اختراعَ نموذجٍ ودلالاتٍ لا
/// وجودَ لهما — وهو تصميمٌ جديدٌ لا إعادةُ تنسيق.
///
/// فالمأخوذُ من التصميم ما ينطبق فعلاً: شرائحُ المجموعات بعدّاداتها ·
/// لافتةُ التحذير للعمليات غير المربوطة · صفوفٌ بشارةِ حالة · ومنتقي حسابٍ
/// لكلّ صفّ. وتعريفاتُ الأغراض في [accountMappingPurposeGroups].
///
/// ⚠️ **ووضعُ العميل للقراءة فقط** — الربطُ يُضبَط مركزيّاً على الخادم،
/// وإسقاطُ الحارس يسمح لجهازٍ فرعيٍّ بتبديل الترحيل المحاسبيّ للشبكة كلِّها.
class AccountMappingPicPosScreen extends ConsumerStatefulWidget {
  const AccountMappingPicPosScreen({super.key});

  @override
  ConsumerState<AccountMappingPicPosScreen> createState() =>
      _AccountMappingPicPosScreenState();
}

class _AccountMappingPicPosScreenState
    extends ConsumerState<AccountMappingPicPosScreen> {
  List<Account> _accounts = const [];
  List<CostCenter> _costCenters = const [];
  List<AccountMapping> _mappings = const [];
  bool _loading = true;
  int _groupIndex = 0;
  String _query = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final repo = ref.read(accountingRepositoryProvider);
      final accounts = await repo.getAllAccounts();
      final centers = await repo.getActiveCostCenters();
      final mappings = await repo.getAllAccountMappings();
      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _costCenters = centers;
        _mappings = mappings;
        _loading = false;
      });
    } catch (e, s) {
      debugPrint('[ACCOUNT_MAPPING] Error loading data: $e\n$s');
      if (mounted) setState(() => _loading = false);
    }
  }

  List<AccountMapping> _forPurpose(String purpose) =>
      _mappings.where((m) => m.purpose == purpose).toList();

  @override
  Widget build(BuildContext context) {
    final readOnly = ref.watch(isClientModeProvider);
    final groups = accountMappingPurposeGroups;

    // ⚠️ العدّاداتُ من التعريفات كلِّها لا من المرشَّح.
    final allItems = [for (final g in groups) ...g.items];
    final unmapped =
        allItems.where((i) => _forPurpose(i.purpose).isEmpty).length;

    final group = groups[_groupIndex];
    final items = _query.isEmpty
        ? group.items
        : group.items
            .where((i) =>
                i.label.contains(_query) ||
                i.purpose.contains(_query) ||
                i.defaultCode.contains(_query))
            .toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: PicPosScreenScaffold(
        title: tr('ربط الحسابات بالعمليات'),
        subtitle: tr('كل عملية في النظام وأثرها المحاسبي'),
        icon: PhosphorIconsBold.plugsConnected,
        headerSearch: TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            isDense: true,
            hintText: tr('بحث في العمليات...'),
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
        // ⚠️ العدّادُ خرج من الترويسة إلى شريطِ المجموعات: `PicPosPageHeader`
        //    صفٌّ بلا تقييد، وحملُه الكاملُ فاض ١٤٣px عند ١٢٨٠ ومرّ عند ١٩٢٠.
        headerActions: [
          if (!readOnly)
            OutlinedButton.icon(
              onPressed: _resetToDefaults,
              icon: const Icon(PhosphorIconsBold.arrowCounterClockwise,
                  size: 15),
              label:  Text(tr('استعادة الافتراضي')),
            ),
        ],
        subHeader: _GroupStrip(
          groups: groups,
          selected: _groupIndex,
          summary: tr('{p0} من {p1} مربوط', {'p0': allItems.length - unmapped, 'p1': allItems.length}),
          countFor: (g) =>
              g.items.where((i) => _forPurpose(i.purpose).isNotEmpty).length,
          onSelect: (i) => setState(() => _groupIndex = i),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (readOnly) ...[
                    const _Banner(
                      icon: PhosphorIconsBold.lockKey,
                      text: 'وضع القراءة فقط — الربط المحاسبي يُضبط مركزيّاً '
                          'على الخادم.',
                      tint: AppColors.warning,
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (unmapped > 0) ...[
                    _Banner(
                      icon: PhosphorIconsBold.warning,
                      text: '$unmapped عملية تحتاج ضبط الربط قبل الترحيل '
                          'التلقائي',
                      tint: AppColors.error,
                    ),
                    const SizedBox(height: 8),
                  ],
                  Expanded(
                    child: items.isEmpty
                        ? PicPosEmptyState(
                            icon: PhosphorIconsBold.magnifyingGlass,
                            title: tr('لا عمليةَ تطابق البحث'),
                            hint: tr('في مجموعة «{p0}».', {'p0': group.title}),
                          )
                        : ListView.separated(
                            padding: EdgeInsets.zero,
                            itemCount: items.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, i) => _PurposeRow(
                              item: items[i],
                              tint: group.color,
                              accounts: _accounts,
                              costCenters: _costCenters,
                              mappings: _forPurpose(items[i].purpose),
                              readOnly: readOnly,
                              onAdd: () => _editMapping(items[i]),
                              onEdit: (m) => _editMapping(items[i], existing: m),
                              onDelete: (m) => _deleteMapping(items[i], m),
                            ),
                          ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _resetToDefaults() async {
    final confirmed = await showPicPosConfirm(
      context,
      icon: PhosphorIconsBold.arrowCounterClockwise,
      title: tr('استعادة الربط الافتراضي'),
      message: 'سيُحذف الربطُ المحاسبيُّ الحاليُّ كلُّه ويُستعاد الافتراضيُّ '
          'من دليل الحسابات. القيودُ المرحَّلةُ سابقاً لا تتأثّر.',
      confirmLabel: tr('استعادة'),
      danger: true,
    );
    if (!confirmed) return;
    try {
      await ref.read(accountingRepositoryProvider).resetToDefaultMappings();
      await _load();
      if (mounted) {
        AppToast.show(context, tr('تم استعادة الربط المحاسبي الافتراضي بنجاح'));
      }
    } catch (e) {
      if (mounted) AppToast.show(context, tr('خطأ: {e}', {'e': e}), type: ToastType.error);
    }
  }

  Future<void> _deleteMapping(
    AccountMappingPurpose item,
    AccountMapping mapping,
  ) async {
    final confirmed = await showPicPosConfirm(
      context,
      icon: PhosphorIconsBold.trash,
      title: tr('حذف الربط'),
      subtitle: item.label,
      message: tr('بعد الحذف لن تجد هذه العمليةُ حساباً تُرحَّل إليه تلقائيّاً.'),
      confirmLabel: tr('حذف'),
      danger: true,
    );
    if (!confirmed) return;
    try {
      // ‏`…ById` لا `deleteAccountMapping(purpose)`: الثانيةُ تحذف ربطَ
      // الغرض كلَّه، وهنا نحذف صفّاً بعينه (قد يكون تجاوزَ مركزِ تكلفة).
      await ref
          .read(accountingRepositoryProvider)
          .deleteAccountMappingById(mapping.id);
      await _load();
    } catch (e) {
      if (mounted) AppToast.show(context, tr('خطأ: {e}', {'e': e}), type: ToastType.error);
    }
  }

  Future<void> _editMapping(
    AccountMappingPurpose item, {
    AccountMapping? existing,
  }) async {
    final result = await showDialog<(int accountId, int? costCenterId)>(
      context: context,
      builder: (ctx) => _MappingEditorDialog(
        item: item,
        accounts: _accounts,
        costCenters: _costCenters,
        initialAccountId: existing?.accountId,
        initialCostCenterId: existing?.costCenterId,
      ),
    );
    if (result == null) return;

    try {
      final repo = ref.read(accountingRepositoryProvider);
      await repo.setAccountMapping(
        item.purpose,
        result.$1,
        costCenterId: result.$2,
      );
      await _load();
      if (mounted) AppToast.show(context, tr('تم حفظ الربط'));
    } catch (e) {
      if (mounted) AppToast.show(context, tr('خطأ: {e}', {'e': e}), type: ToastType.error);
    }
  }
}

/// شرائحُ المجموعات الستّ بعدّاداتها — «مجموعةُ التصميم» بأرقامٍ مقيسة.
class _GroupStrip extends StatelessWidget {
  const _GroupStrip({
    required this.groups,
    required this.selected,
    required this.summary,
    required this.countFor,
    required this.onSelect,
  });

  final List<AccountMappingPurposeGroup> groups;
  final int selected;

  /// «س من ص مربوط» — مقيسٌ من التعريفات كلِّها لا من المجموعة المعروضة.
  final String summary;
  final int Function(AccountMappingPurposeGroup) countFor;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border(bottom: BorderSide(color: context.picposHairline)),
      ),
      child: Row(
        children: [
          Text(summary,
              style: text.labelSmall?.copyWith(color: AppColors.textMuted)),
          const SizedBox(width: 10),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < groups.length; i++) ...[
              Builder(builder: (context) {
                final g = groups[i];
                final on = i == selected;
                final mapped = countFor(g);
                return InkWell(
                  onTap: () => onSelect(i),
                  borderRadius: BorderRadius.circular(9),
                  child: Container(
                    height: 34,
                    padding: const EdgeInsets.symmetric(horizontal: 11),
                    decoration: BoxDecoration(
                      color: on
                          ? g.color.withValues(alpha: 0.10)
                          : Colors.transparent,
                      border:
                          Border.all(color: on ? g.color : context.picposHairline),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(g.icon,
                            size: 14,
                            color: on ? g.color : AppColors.textMuted),
                        const SizedBox(width: 6),
                        Text(g.title,
                            style: text.labelMedium?.copyWith(
                              color:
                                  on ? g.color : AppColors.textSecondary,
                              fontWeight:
                                  on ? FontWeight.w800 : FontWeight.w600,
                            )),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: (on ? g.color : AppColors.textMuted)
                                .withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text('$mapped/${g.items.length}',
                              style: text.labelSmall?.copyWith(
                                color: on ? g.color : AppColors.textMuted,
                                fontWeight: FontWeight.w800,
                              )),
                        ),
                      ],
                    ),
                  ),
                );
                  }),
                  const SizedBox(width: 6),
                ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, required this.tint});

  final IconData icon;
  final String text;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.06),
        border: Border.all(color: tint.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: tint),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: tint, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

/// صفُّ غرضٍ واحد: اسمُه ووصفُه وحالتُه وحساباتُه المربوطة.
class _PurposeRow extends StatelessWidget {
  const _PurposeRow({
    required this.item,
    required this.tint,
    required this.accounts,
    required this.costCenters,
    required this.mappings,
    required this.readOnly,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final AccountMappingPurpose item;
  final Color tint;
  final List<Account> accounts;
  final List<CostCenter> costCenters;
  final List<AccountMapping> mappings;
  final bool readOnly;
  final VoidCallback onAdd;
  final ValueChanged<AccountMapping> onEdit;
  final ValueChanged<AccountMapping> onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final mapped = mappings.isNotEmpty;

    return PicPosContentCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(PhosphorIconsBold.plugsConnected,
                    size: 16, color: tint),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.label,
                        style: text.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    Text(
                      tr('{p0} · الافتراضي {p1}', {'p0': item.purpose, 'p1': item.defaultCode}),
                      style: text.labelSmall
                          ?.copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              _StatusBadge(mapped: mapped),
              if (!readOnly) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: onAdd,
                  icon: Icon(
                      mapped
                          ? PhosphorIconsBold.pencilSimple
                          : PhosphorIconsBold.plus,
                      size: 14),
                  label: Text(mapped ? tr('تعديل') : tr('ربط')),
                ),
              ],
            ],
          ),
          if (mappings.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final m in mappings)
              _MappingChip(
                mapping: m,
                account: accounts.where((a) => a.id == m.accountId).firstOrNull,
                costCenter: m.costCenterId == null
                    ? null
                    : costCenters
                        .where((c) => c.id == m.costCenterId)
                        .firstOrNull,
                readOnly: readOnly,
                onEdit: () => onEdit(m),
                onDelete: () => onDelete(m),
              ),
          ],
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.mapped});

  final bool mapped;

  @override
  Widget build(BuildContext context) {
    final tint = mapped ? AppColors.success : AppColors.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(mapped ? PhosphorIconsBold.check : PhosphorIconsBold.warning,
              size: 12, color: tint),
          const SizedBox(width: 5),
          Text(mapped ? tr('مربوط') : tr('غير مربوط'),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tint, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _MappingChip extends StatelessWidget {
  const _MappingChip({
    required this.mapping,
    required this.account,
    required this.costCenter,
    required this.readOnly,
    required this.onEdit,
    required this.onDelete,
  });

  final AccountMapping mapping;
  final Account? account;
  final CostCenter? costCenter;
  final bool readOnly;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: context.picposField,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(PhosphorIconsBold.arrowElbowDownRight,
              size: 13, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              account == null
                  ? tr('حساب #{p0} (غير موجود)', {'p0': mapping.accountId})
                  : '${account!.code} — ${account!.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color:
                    account == null ? AppColors.error : context.picposText,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              costCenter == null ? tr('افتراضي') : tr('مركز: {p0}', {'p0': costCenter!.name}),
              style: text.labelSmall?.copyWith(color: AppColors.primary),
            ),
          ),
          if (!readOnly) ...[
            const SizedBox(width: 6),
            IconButton(
              tooltip: tr('تعديل'),
              iconSize: 14,
              visualDensity: VisualDensity.compact,
              icon: const Icon(PhosphorIconsBold.pencilSimple),
              onPressed: onEdit,
            ),
            IconButton(
              tooltip: tr('حذف'),
              iconSize: 14,
              visualDensity: VisualDensity.compact,
              color: AppColors.error,
              icon: const Icon(PhosphorIconsBold.trash),
              onPressed: onDelete,
            ),
          ],
        ],
      ),
    );
  }
}

/// حوارُ اختيار الحساب (ومركزِ التكلفة اختياريّاً) لغرضٍ واحد.
class _MappingEditorDialog extends StatefulWidget {
  const _MappingEditorDialog({
    required this.item,
    required this.accounts,
    required this.costCenters,
    this.initialAccountId,
    this.initialCostCenterId,
  });

  final AccountMappingPurpose item;
  final List<Account> accounts;
  final List<CostCenter> costCenters;
  final int? initialAccountId;
  final int? initialCostCenterId;

  @override
  State<_MappingEditorDialog> createState() => _MappingEditorDialogState();
}

class _MappingEditorDialogState extends State<_MappingEditorDialog> {
  late int? _accountId = widget.initialAccountId;
  late int? _costCenterId = widget.initialCostCenterId;
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final matches = widget.accounts.where((a) {
      if (_filter.isEmpty) return true;
      final q = ArabicUtils.normalize(_filter.toLowerCase());
      return ArabicUtils.normalize(a.name.toLowerCase()).contains(q) ||
          a.code.contains(q);
    }).toList();

    return PicPosDialog(
      icon: PhosphorIconsBold.plugsConnected,
      title: tr('ربط «{p0}»', {'p0': widget.item.label}),
      subtitle: tr('الحساب الافتراضي في الدليل: {p0}', {'p0': widget.item.defaultCode}),
      width: 620,
      onCancel: () => Navigator.pop(context),
      primaryAction: PicPosDialogAction(
        label: tr('حفظ الربط'),
        icon: PhosphorIconsBold.check,
        onPressed: _accountId == null
            ? null
            : () => Navigator.pop(context, (_accountId!, _costCenterId)),
      ),
      body: [
        Text(widget.item.description,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.textMuted)),
        const SizedBox(height: 12),
        DropdownButtonFormField<int?>(
          initialValue: _costCenterId,
          isExpanded: true,
          decoration:  InputDecoration(
            isDense: true,
            labelText: tr('مركز التكلفة (اختياري)'),
            helperText: tr('اتركه فارغاً ليكون الربطُ افتراضيّاً لكلّ المراكز'),
          ),
          items: [
             DropdownMenuItem(value: null, child: Text(tr('افتراضي — كل المراكز'))),
            for (final c in widget.costCenters)
              DropdownMenuItem(value: c.id, child: Text('${c.code} — ${c.name}')),
          ],
          onChanged: (v) => setState(() => _costCenterId = v),
        ),
        const SizedBox(height: 12),
        TextField(
          onChanged: (v) => setState(() => _filter = v),
          decoration:  InputDecoration(
            isDense: true,
            hintText: tr('بحث بالاسم أو الرمز...'),
            prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 16),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 320,
          child: matches.isEmpty
              ?  PicPosEmptyState(
                  icon: PhosphorIconsBold.magnifyingGlass,
                  title: tr('لا حسابَ يطابق البحث'),
                )
              : ListView.builder(
                  itemCount: matches.length,
                  itemBuilder: (context, i) {
                    final a = matches[i];
                    return RadioListTile<int>(
                      dense: true,
                      value: a.id,
                      groupValue: _accountId,
                      onChanged: (v) => setState(() => _accountId = v),
                      title: Text('${a.code} — ${a.name}',
                          style: const TextStyle(fontSize: 13)),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
