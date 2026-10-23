import 'package:picpos_erp/core/i18n/tr.dart';
// مكتبةُ النماذج — تصميمُ `PicPos Template Library.dc.html`.
//
// ── ما تحلّه ──────────────────────────────────────────────────────────────
// تسعةَ عشرَ ملفَّ قالبٍ في `assets/invoice_templates/`، ولا يصل منها القاعدةَ
// إلّا ما تعرضه قائمتا «النماذج الجاهزة» في `invoice_template_dao` — ثمانيةٌ
// وأربعة. فأحدَ عشرَ ملفاً، **وفيها كلُّ الجديدة**، بلا مسارِ استيرادٍ
// إطلاقاً: مكتوبةٌ في المستودع ولا يراها المالك.
//
// ⚠️ **ولا استيرادَ لـ`data/database` هنا**: حارسُ
// `presentation_db_import_guard` يمنعه على أيّ ملفِّ عرضٍ جديد. فالصفوفُ تصل
// نموذجاً خالصاً ([TemplateCard]) والوصلُ وقع في طبقة البيانات.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/providers/template_library_providers.dart';
import '../../../domain/models/picpos_template_card.dart';
import '../../picpos_shell/picpos_content_card.dart';
import '../../picpos_shell/picpos_empty_state.dart';
import '../../picpos_shell/picpos_filter_strip.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_section_header.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../widgets/template_detail_panel.dart';
import '../widgets/new_template_sheet.dart';
import '../widgets/template_gallery_card.dart';

/// عرضُ لوحة التفاصيل. تحتَه تُطوى اللوحةُ وتبقى الشبكةُ وحدَها — بطاقةٌ
/// بعرض ٢٤٠ لا تقلّ، ولوحةٌ بعرض ٣٤٠ لا تقلّ، فأقلُّ عرضٍ يسعهما ٦٦٠.
const double _detailPanelWidth = 340;
const double _twoPaneMinWidth = 900;

class TemplateLibraryPicposScreen extends ConsumerStatefulWidget {
  const TemplateLibraryPicposScreen({super.key});

  @override
  ConsumerState<TemplateLibraryPicposScreen> createState() =>
      _TemplateLibraryPicposScreenState();
}

class _TemplateLibraryPicposScreenState
    extends ConsumerState<TemplateLibraryPicposScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cardsAsync = ref.watch(templateCardsProvider);
    final all = cardsAsync.value ?? const <TemplateCard>[];
    final visible = ref.watch(visibleTemplateCardsProvider);
    final selected = ref.watch(selectedTemplateCardProvider);
    final counts = templateFilterCounts(all);
    final active = ref.watch(templateFilterProvider);

    return PicPosScreenScaffold(
      title: tr('مكتبة النماذج'),
      subtitle: _subtitleFor(all),
      icon: PhosphorIconsBold.books,
      headerActions: [
        FilledButton.icon(
          onPressed: () => showNewTemplateSheet(context, ref),
          icon: const Icon(PhosphorIconsBold.filePlus, size: 17),
          label:  Text(tr('قالب جديد')),
        ),
      ],
      headerSearch: TextField(
        controller: _searchCtrl,
        onChanged: (v) => ref.read(templateQueryProvider.notifier).set(v),
        decoration: InputDecoration(
          isDense: true,
          hintText: tr('ابحث باسم القالب...'),
          prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 16),
          suffixIcon: _searchCtrl.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(PhosphorIconsBold.x, size: 14),
                  onPressed: () {
                    _searchCtrl.clear();
                    ref.read(templateQueryProvider.notifier).set('');
                  },
                ),
        ),
      ),
      subHeader: PicPosFilterStrip(
        children: [
          for (final f in TemplateFilter.values)
            PicPosFilterPill(
              icon: _filterIcon(f),
              label: '${f.label} (${counts[f] ?? 0})',
              tone: f == active ? context.picposBrandInk : null,
              onTap: () => ref.read(templateFilterProvider.notifier).set(f),
            ),
        ],
      ),
      body: cardsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => PicPosEmptyState(
          icon: PhosphorIconsBold.warning,
          title: tr('تعذّرت قراءةُ المكتبة'),
          hint: '$e',
        ),
        data: (_) => LayoutBuilder(
          builder: (context, box) {
            final twoPane = box.maxWidth >= _twoPaneMinWidth;
            final gallery = _Gallery(
              cards: visible,
              selectedId: selected?.id,
              onSelect: (id) =>
                  ref.read(selectedTemplateIdProvider.notifier).set(id),
            );

            if (!twoPane) return gallery;

            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: gallery),
                const SizedBox(width: 12),
                SizedBox(
                  width: _detailPanelWidth,
                  child: TemplateDetailPanel(card: selected),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _subtitleFor(List<TemplateCard> all) {
    if (all.isEmpty) return tr('لا قوالبَ بعد');
    final bound = all.where((c) => c.isBound).length;
    return tr('{p0} قالباً · {bound} مربوطٌ بمستند', {'p0': all.length, 'bound': bound});
  }

  IconData _filterIcon(TemplateFilter f) {
    switch (f) {
      case TemplateFilter.all:
        return PhosphorIconsBold.squaresFour;
      case TemplateFilter.a4:
        return PhosphorIconsBold.fileText;
      case TemplateFilter.thermal:
        return PhosphorIconsBold.receipt;
      case TemplateFilter.statement:
        return PhosphorIconsBold.scroll;
      case TemplateFilter.report:
        return PhosphorIconsBold.chartBar;
    }
  }
}

class _Gallery extends StatelessWidget {
  const _Gallery({
    required this.cards,
    required this.selectedId,
    required this.onSelect,
  });

  final List<TemplateCard> cards;
  final int? selectedId;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) {
      return  PicPosEmptyState(
        icon: PhosphorIconsBold.files,
        title: tr('لا قالبَ يطابق البحث'),
        hint: tr('جرّب مرشِّحاً آخرَ أو امسح نصَّ البحث'),
      );
    }

    return PicPosContentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PicPosSectionHeader(
            title: tr('النماذج'),
            subtitle: tr('{p0} معروضاً', {'p0': cards.length}),
            icon: PhosphorIconsBold.gridFour,
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                // بطاقةٌ لا تضيق عن ٢٤٠: تحتَها تصير المصغَّرةُ لطخةً لا
                // تُقرأ منها بنيةُ الورقة — وهي كلُّ فائدتها.
                final columns = (box.maxWidth / 250).floor().clamp(1, 6);
                return GridView.builder(
                  padding: const EdgeInsets.only(top: 8),
                  gridDelegate:
                      SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.72,
                  ),
                  itemCount: cards.length,
                  itemBuilder: (context, i) => TemplateGalleryCard(
                    card: cards[i],
                    selected: cards[i].id == selectedId,
                    onTap: () => onSelect(cards[i].id),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// لونُ الشارة حسب حالة القالب — مرجعٌ واحدٌ تقرؤه البطاقةُ واللوحة.
Color templateStatusTone(TemplateCard c) {
  if (c.isBound) return AppColors.success;
  if (c.isDefault) return AppColors.info;
  return AppColors.textMuted;
}

String templateStatusLabel(TemplateCard c) {
  if (c.isBound) return tr('مربوط');
  if (c.isDefault) return tr('افتراضي');
  return tr('مسوّدة');
}
