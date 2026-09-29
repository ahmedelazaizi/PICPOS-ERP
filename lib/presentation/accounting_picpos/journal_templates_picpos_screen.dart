import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../../core/permissions/permission_codes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_toast.dart';
import '../../data/providers/providers.dart';
import '../../domain/repositories/accounting_repository.dart';
import '../picpos_shell/picpos_dialog.dart';
import '../picpos_shell/picpos_empty_state.dart';
import '../picpos_shell/picpos_screen_scaffold.dart';
import '../screens/create_journal_template_dialog.dart';
import '../widgets/permission_guard.dart';
import '../picpos_shell/picpos_surface.dart';

/// قوالبُ القيود بهويّة PicPos — تبويبُ `tpl` في حاويةِ الحسابات.
///
/// التصميمُ شبكةُ بطاقاتٍ بأربعةِ أعمدة، كلُّ بطاقةٍ: أيقونةٌ · اسمٌ · سطرُ
/// وصفٍ · سطورُ القالب بشارةَ مدين/دائن · وأزرارٌ أسفلَها.
///
/// ⚠️ **وما يعرضه التصميمُ ولا تحمله القاعدةُ لم يُختلَق.** جدولُ
/// `JournalEntryTemplates` فيه `name` و`description` و`isActive` و`createdAt`
/// فقط — **لا `code` ولا عدّادَ استخدام**. فبدلهما يُعرض ما يُقاس فعلاً:
/// عددُ السطور وحالةُ التفعيل. وزرُّ «استخدام القالب» في التصميم لا فعلَ
/// خلفَه في الكود (القوالبُ تُستدعى من شاشة القيود عبر منتقيها)، فمكانَه
/// الفعلان القائمان: تعديلٌ وحذف.
class JournalTemplatesPicPosScreen extends ConsumerStatefulWidget {
  const JournalTemplatesPicPosScreen({super.key});

  @override
  ConsumerState<JournalTemplatesPicPosScreen> createState() =>
      _JournalTemplatesPicPosScreenState();
}

class _JournalTemplatesPicPosScreenState
    extends ConsumerState<JournalTemplatesPicPosScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(accountingRepositoryProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: StreamBuilder<List<JournalEntryTemplateData>>(
        stream: repo.watchAllTemplates(),
        builder: (context, snapshot) {
          final all = snapshot.data ?? const <JournalEntryTemplateData>[];

          final filtered = _searchQuery.isEmpty
              ? all
              : all
                  .where((t) =>
                      t.name.contains(_searchQuery) ||
                      (t.description ?? '').contains(_searchQuery))
                  .toList();

          // ⚠️ العدّاداتُ من القائمة **غيرِ المرشَّحة**: الترشيحُ يُخفي ولا
          //    يحذف، فعدّادٌ يتبع البحثَ يقول للمستخدم إنّ قوالبَه نقصت.
          final total = all.length;
          final active = all.where((t) => t.isActive).length;

          return PicPosScreenScaffold(
            title: tr('قوالب القيود'),
            subtitle: tr('قيود متكررة جاهزة للاستخدام'),
            icon: PhosphorIconsBold.stack,
            headerSearch: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                isDense: true,
                hintText: tr('بحث في القوالب...'),
                prefixIcon:
                    const Icon(PhosphorIconsBold.magnifyingGlass, size: 16),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(PhosphorIconsBold.x, size: 14),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
              ),
            ),
            headerActions: [
              _CountChip(
                label: tr('الإجمالي'),
                value: '$total',
                tint: AppColors.primary,
              ),
              const SizedBox(width: 8),
              _CountChip(
                label: tr('النشطة'),
                value: '$active',
                tint: AppColors.success,
              ),
              const SizedBox(width: 12),
              PermissionGuard(
                permission: PermissionCodes.accountingManage,
                fallback: const SizedBox.shrink(),
                child: FilledButton.icon(
                  onPressed: () => _showTemplateDialog(repo),
                  icon: const Icon(PhosphorIconsBold.plus, size: 16),
                  label:  Text(tr('قالب جديد')),
                ),
              ),
            ],
            body: _buildBody(snapshot, filtered, repo, total),
          );
        },
      ),
    );
  }

  Widget _buildBody(
    AsyncSnapshot<List<JournalEntryTemplateData>> snapshot,
    List<JournalEntryTemplateData> filtered,
    IAccountingRepository repo,
    int total,
  ) {
    if (snapshot.hasError) {
      return PicPosEmptyState(
        icon: PhosphorIconsBold.warning,
        title: tr('تعذّرت قراءةُ القوالب'),
        hint: '${snapshot.error}',
      );
    }
    if (!snapshot.hasData) {
      return const Center(child: CircularProgressIndicator());
    }

    if (total == 0) {
      return  PicPosEmptyState(
        icon: PhosphorIconsBold.stack,
        title: tr('لا توجد قوالب قيود'),
        hint: 'استخدم القوالب لتسريع إنشاء القيود المتكررة '
            'كرواتب الموظفين أو الإيجارات.',
      );
    }
    if (filtered.isEmpty) {
      return PicPosEmptyState(
        icon: PhosphorIconsBold.magnifyingGlass,
        title: tr('لا قالبَ يطابق البحث'),
        hint: tr('البحثُ عن «{_searchQuery}» لم يطابق أيّاً من {total} قالباً.', {'_searchQuery': _searchQuery, 'total': total}),
        action: TextButton.icon(
          onPressed: () {
            _searchController.clear();
            setState(() => _searchQuery = '');
          },
          icon: const Icon(PhosphorIconsBold.x, size: 14),
          label:  Text(tr('امسح البحث')),
        ),
      );
    }

    // شبكةُ التصميم أربعةُ أعمدة، وتضيق بالعرض بدل أن تفيض.
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = switch (constraints.maxWidth) {
          >= 1500 => 4,
          >= 1100 => 3,
          >= 720 => 2,
          _ => 1,
        };
        return GridView.builder(
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 300,
          ),
          itemCount: filtered.length,
          itemBuilder: (context, i) => _TemplateCard(
            template: filtered[i],
            repo: repo,
            onEdit: (lines) =>
                _showTemplateDialog(repo, template: filtered[i], lines: lines),
            onDelete: () => _deleteTemplate(repo, filtered[i]),
          ),
        );
      },
    );
  }

  Future<void> _deleteTemplate(
    IAccountingRepository repo,
    JournalEntryTemplateData template,
  ) async {
    final confirmed = await showPicPosConfirm(
      context,
      icon: PhosphorIconsBold.trash,
      title: tr('تأكيد الحذف'),
      subtitle: template.name,
      message: 'هل أنت متأكد من حذف القالب «${template.name}»؟ '
          'لا يؤثّر الحذفُ على القيود المُنشأة منه سابقاً.',
      confirmLabel: tr('حذف'),
      danger: true,
    );
    if (!confirmed) return;

    await repo.deleteJournalTemplate(template.id);
    if (mounted) {
      AppToast.show(context, tr('تم حذف القالب بنجاح'), type: ToastType.warning);
    }
  }

  void _showTemplateDialog(
    IAccountingRepository repo, {
    JournalEntryTemplateData? template,
    List<Map<String, dynamic>>? lines,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => CreateJournalTemplateDialog(
        templateToEdit: template,
        initialLines: lines,
      ),
    );
  }
}

/// بطاقةُ قالبٍ واحدة — على تخطيط التصميم.
class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.repo,
    required this.onEdit,
    required this.onDelete,
  });

  final JournalEntryTemplateData template;
  final IAccountingRepository repo;
  final ValueChanged<List<Map<String, dynamic>>> onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final tint = template.isActive ? AppColors.primary : AppColors.textMuted;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border.all(color: context.picposHairline),
        borderRadius: BorderRadius.circular(14),
      ),
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: repo.getTemplateLinesWithAccounts(template.id),
        builder: (context, snap) {
          final lines = snap.data ?? const <Map<String, dynamic>>[];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: tint.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(PhosphorIconsBold.stack, size: 18, color: tint),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          template.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: template.isActive
                                ? context.picposText
                                : AppColors.textMuted,
                          ),
                        ),
                        Text(
                          // بديلُ `code · uses` اللذَين لا وجودَ لهما.
                          snap.hasData
                              ? tr('{p0} سطر', {'p0': lines.length})
                              : tr('— سطر'),
                          style: text.labelSmall
                              ?.copyWith(color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  if (!template.isActive)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.textMuted.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(tr('غير نشط'),
                          style: text.labelSmall
                              ?.copyWith(color: AppColors.textMuted)),
                    ),
                ],
              ),
              const SizedBox(height: 11),
              SizedBox(
                height: 34,
                child: Text(
                  template.description?.isNotEmpty == true
                      ? template.description!
                      : tr('بلا وصف'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: snap.hasData
                    ? _LinesPreview(lines: lines)
                    : const Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed:
                          snap.hasData ? () => onEdit(lines) : null,
                      icon: const Icon(PhosphorIconsBold.pencilSimple, size: 13),
                      label:  Text(tr('تعديل القالب')),
                    ),
                  ),
                  const SizedBox(width: 7),
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(PhosphorIconsBold.trash, size: 14),
                    color: AppColors.error,
                    tooltip: tr('حذف القالب'),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.error.withValues(alpha: 0.08),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// سطورُ القالب بشارةِ مدين/دائن — أوّلُ ثلاثةٍ ثمّ «و س غيرها».
class _LinesPreview extends StatelessWidget {
  const _LinesPreview({required this.lines});

  final List<Map<String, dynamic>> lines;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(tr('بلا سطور'),
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: AppColors.textMuted)),
      );
    }

    const maxShown = 3;
    final shown = lines.take(maxShown).toList();
    final rest = lines.length - shown.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final line in shown) ...[
          _LineChip(line: line),
          const SizedBox(height: 5),
        ],
        if (rest > 0)
          Text(tr('و{rest} سطراً غيرها', {'rest': rest}),
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: AppColors.textMuted)),
      ],
    );
  }
}

class _LineChip extends StatelessWidget {
  const _LineChip({required this.line});

  final Map<String, dynamic> line;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final debit = (line['debit'] as num?)?.toDouble() ?? 0;
    final isDebit = debit > 0;
    final amount = isDebit
        ? debit
        : ((line['credit'] as num?)?.toDouble() ?? 0);
    final sideColor = isDebit ? AppColors.success : AppColors.error;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: context.picposField,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            padding: const EdgeInsets.symmetric(vertical: 2),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: sideColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              isDebit ? tr('مدين') : tr('دائن'),
              style: text.labelSmall?.copyWith(
                color: sideColor,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            line['account_code']?.toString() ?? '',
            style: text.labelSmall?.copyWith(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              line['account_name']?.toString() ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.labelSmall
                  ?.copyWith(color: context.picposText),
            ),
          ),
          Text(
            amount.toStringAsFixed(AppConstants.decimalPlaces),
            style: text.labelSmall?.copyWith(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// عدّادٌ صغيرٌ في الترويسة — مقيسٌ من الصفوف لا من المرشَّح.
class _CountChip extends StatelessWidget {
  const _CountChip({
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.08),
        border: Border.all(color: tint.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: text.labelSmall?.copyWith(color: AppColors.textMuted)),
          const SizedBox(width: 6),
          Text(value,
              style: text.labelMedium
                  ?.copyWith(color: tint, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
