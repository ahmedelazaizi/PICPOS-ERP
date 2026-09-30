import 'package:ural_erp/core/i18n/tr.dart';
// شاشةُ حسم القوالب — تصميمُ `PicPos Template Resolution.dc.html`.
//
// ── ما تحلّه ──────────────────────────────────────────────────────────────
// «الفاتورةُ خرجت بهذا الشكل — لماذا؟» سؤالٌ جوابُه اليومَ موزَّعٌ على ثلاثة
// مواضعَ لا يجمعها عرض: جدولُ `template_bindings` وعَلَمُ `isDefault` وسلسلةُ
// `_resolveTemplate`. فيربط المالكُ قالباً ولا يعرف أيَصلُ الورقةَ أم لا.
//
// والسطرُ هنا يقول الجوابَ كاملاً: أيُّ قالبٍ فاز، وبأيِّ مستوىً من الستّة،
// وأيُّ المستوياتِ جُرِّب قبله وأخفق.
//
// ⚠️ **ولا استيرادَ لـ`data/database`**: حارسُ `presentation_db_import_guard`
// يمنعه على أيّ ملفِّ عرضٍ جديد — الصفوفُ تصل [PrintResolutionRow] خالصةً.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/providers/print_resolution_providers.dart';
import '../../../domain/models/print_resolution_row.dart';
import '../../picpos_shell/picpos_content_card.dart';
import '../../picpos_shell/picpos_empty_state.dart';
import '../../picpos_shell/picpos_filter_strip.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_section_header.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../widgets/resolution_chain_panel.dart';

/// عرضُ لوحة السلسلة — ‏٤٣٠ في التصميم. وتحتَ [_twoPaneMinWidth] تُطوى
/// وتبقى الجدولُ وحدَه: جدولُ ستّةِ أعمدةٍ لا يقلّ عن ٥٦٠ مقروءاً.
const double _chainPanelWidth = 430;
const double _twoPaneMinWidth = 1040;

class TemplateResolutionPicposScreen extends ConsumerWidget {
  const TemplateResolutionPicposScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rowsAsync = ref.watch(printResolutionRowsProvider);
    final rows = rowsAsync.value ?? const <PrintResolutionRow>[];
    final selected = ref.watch(selectedResolutionRowProvider);
    final branches = ref.watch(resolutionBranchOptionsProvider);
    final branchId = ref.watch(resolutionBranchProvider);
    final locale = ref.watch(resolutionLocaleProvider);

    final healthy = rows.where((r) => !r.health.needsAttention).length;
    final broken = rows.where((r) => r.health.needsAttention).length;

    return PicPosScreenScaffold(
      title: tr('حسم القوالب والطابعات'),
      subtitle: tr('أي مستند ← أي قالب ← أي طابعة · المفتاح: نوع المستند + الفرع + الطابعة + اللغة'),
      icon: PhosphorIconsBold.gitFork,
      headerActions: [
        _HeaderStat(label: tr('مسارات الطباعة'), value: '${rows.length}'),
        _HeaderStat(
            label: tr('حسم سليم'), value: '$healthy', tone: AppColors.success),
        _HeaderStat(
            label: tr('يحتاج معالجة'), value: '$broken', tone: AppColors.error),
      ],
      subHeader: PicPosFilterStrip(
        children: [
          for (final b in branches)
            PicPosFilterPill(
              icon: PhosphorIconsBold.storefront,
              label: b.id == null ? tr('كل الفروع') : trData(b.label),
              tone: b.id == branchId ? context.picposBrandInk : null,
              onTap: () =>
                  ref.read(resolutionBranchProvider.notifier).set(b.id),
            ),
          for (final l in  [
            (code: 'ar', label: tr('عربي')),
            (code: 'en', label: 'English'),
          ])
            PicPosFilterPill(
              icon: PhosphorIconsBold.translate,
              label: l.label,
              tone: l.code == locale ? context.picposBrandInk : null,
              onTap: () =>
                  ref.read(resolutionLocaleProvider.notifier).set(l.code),
            ),
        ],
      ),
      body: rowsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => PicPosEmptyState(
          icon: PhosphorIconsBold.warning,
          title: tr('تعذّر قراءةُ مسارات الطباعة'),
          hint: '$e',
        ),
        data: (_) => LayoutBuilder(
          builder: (context, box) {
            final table = _ResolutionTable(
              rows: rows,
              selectedType: selected?.documentType,
              onSelect: (t) =>
                  ref.read(selectedDocumentTypeProvider.notifier).set(t),
            );

            if (box.maxWidth < _twoPaneMinWidth) return table;

            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: table),
                const SizedBox(width: 12),
                SizedBox(
                  width: _chainPanelWidth,
                  child: ResolutionChainPanel(row: selected),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// عدّادُ الترويسة — تسميةٌ خافتةٌ فوق رقمٍ عريض، كالتصميم.
class _HeaderStat extends StatelessWidget {
  const _HeaderStat({required this.label, required this.value, this.tone});

  final String label;
  final String value;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: context.picposMuted)),
          Text(value,
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: tone ?? context.picposText)),
        ],
      ),
    );
  }
}

class _ResolutionTable extends StatelessWidget {
  const _ResolutionTable({
    required this.rows,
    required this.selectedType,
    required this.onSelect,
  });

  final List<PrintResolutionRow> rows;
  final String? selectedType;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return  PicPosEmptyState(
        icon: PhosphorIconsBold.gitFork,
        title: tr('لا مسارَ طباعةٍ مسجَّل'),
        hint: tr('أنواعُ المستندات تُعلَن في `TemplateResolver.documentTypes`'),
      );
    }

    return PicPosContentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PicPosSectionHeader(
            title: tr('مسارات الطباعة'),
            subtitle: tr('{p0} نوعَ مستند', {'p0': rows.length}),
            icon: PhosphorIconsBold.funnel,
          ),
          const _TableHead(),
          Expanded(
            child: ListView.builder(
              itemCount: rows.length,
              itemBuilder: (context, i) => _ResolutionRowTile(
                row: rows[i],
                selected: rows[i].documentType == selectedType,
                onTap: () => onSelect(rows[i].documentType),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// نِسَبُ الأعمدة — نفسُ `grid-template-columns` في التصميم.
const _columnFlex = <int>[19, 14, 19, 15, 9, 12];

class _TableHead extends StatelessWidget {
  const _TableHead();

  @override
  Widget build(BuildContext context) {
    final titles = [
      tr('نوع المستند'),
      tr('الفئة والورق'),
      tr('القالب المحسوم'),
      tr('الطابعة'),
      tr('النُّسخ'),
      tr('الحالة'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: context.picposField,
        border: Border(bottom: BorderSide(color: context.picposHairline)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < titles.length; i++)
            Expanded(
              flex: _columnFlex[i],
              child: Text(
                titles[i],
                textAlign: i == 4 ? TextAlign.center : TextAlign.start,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: context.picposMuted),
              ),
            ),
        ],
      ),
    );
  }
}

class _ResolutionRowTile extends StatelessWidget {
  const _ResolutionRowTile({
    required this.row,
    required this.selected,
    required this.onTap,
  });

  final PrintResolutionRow row;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = resolutionTone(context, row.health);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? context.picposBrandInk.withValues(alpha: 0.08)
              : Colors.transparent,
          // `BorderDirectional` لا `Border`: الشريطُ الجانبيُّ يعلّم المحدَّد
          // وهو `border-inline-start` في التصميم — يتبع اتّجاهَ اللغة لا
          // الجهةَ الثابتة، و`Border.left` كان سيقع يساراً في العربيّة.
          border: BorderDirectional(
            bottom: BorderSide(color: context.picposHairline),
            start: BorderSide(
              color: selected ? context.picposBrandInk : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              flex: _columnFlex[0],
              child: _TwoLine(
                top: tr(row.documentLabel),
                bottom: row.documentType,
                bottomMono: true,
              ),
            ),
            Expanded(
              flex: _columnFlex[1],
              child: _TwoLine(
                top: row.category,
                bottom: row.paperLabel,
                topMono: true,
              ),
            ),
            Expanded(
              flex: _columnFlex[2],
              child: Row(
                children: [
                  Icon(_healthIcon(row.health), size: 13, color: tone),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _TwoLine(
                      top: trData(row.templateName),
                      bottom: tr(row.health.note),
                      topTone: row.hasTemplate ? null : context.picposMuted,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: _columnFlex[3],
              child: _TwoLine(
                top: row.printerName ?? tr('غير محدَّدة'),
                bottom: row.printerName == null
                    ? tr(row.printerNote)
                    : row.printerNote,
                topTone: row.printerName == null ? context.picposMuted : null,
              ),
            ),
            Expanded(
              flex: _columnFlex[4],
              child: Text(
                '${row.copies}',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: context.picposText),
              ),
            ),
            Expanded(
              flex: _columnFlex[5],
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    tr(row.health.label),
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: tone),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TwoLine extends StatelessWidget {
  const _TwoLine({
    required this.top,
    required this.bottom,
    this.topMono = false,
    this.bottomMono = false,
    this.topTone,
  });

  final String top;
  final String bottom;
  final bool topMono;
  final bool bottomMono;
  final Color? topTone;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          top,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            fontFamily: topMono ? 'monospace' : null,
            color: topTone ?? context.picposText,
          ),
        ),
        Text(
          bottom,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            fontFamily: bottomMono ? 'monospace' : null,
            color: context.picposMuted,
          ),
        ),
      ],
    );
  }
}

/// لونُ الحال — مرجعٌ واحدٌ يقرؤه الصفُّ واللوحة.
///
/// ⚠️ و«بانتظار التوصيل» **كهرمانيّةٌ لا حمراء**: نقصُ امتدادٍ مخطَّطٌ له،
/// لا إعدادٌ معطوب. وتلوينُها حمراءَ يجعل المالكَ يطارد عطباً لا وجود له.
Color resolutionTone(BuildContext context, ResolutionHealth health) =>
    switch (health) {
      ResolutionHealth.builtIn => context.picposMuted,
      ResolutionHealth.paperMismatch => AppColors.error,
      ResolutionHealth.collision => AppColors.error,
      ResolutionHealth.unwired => AppColors.warning,
      ResolutionHealth.branchScoped => context.picposBrandInk,
      ResolutionHealth.categoryOnly => AppColors.info,
      ResolutionHealth.bound => AppColors.success,
    };

IconData _healthIcon(ResolutionHealth health) => switch (health) {
      ResolutionHealth.builtIn => PhosphorIconsBold.prohibit,
      ResolutionHealth.paperMismatch => PhosphorIconsBold.warning,
      ResolutionHealth.collision => PhosphorIconsBold.warningOctagon,
      ResolutionHealth.unwired => PhosphorIconsBold.hourglass,
      ResolutionHealth.branchScoped => PhosphorIconsBold.storefront,
      ResolutionHealth.categoryOnly => PhosphorIconsBold.stack,
      ResolutionHealth.bound => PhosphorIconsBold.checkCircle,
    };
