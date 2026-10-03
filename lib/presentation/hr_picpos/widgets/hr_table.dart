// J4 (الجزء ٢) — جدولُ بياناتٍ على توقيع PicPos (كتلةٌ بحدّ ١٧، صفُّ عناوين
// بلون الحقل، فواصلُ شعريّة، عرضٌ أدنى وتمريرٌ أفقيّ). خلافاً لـ
// `PicPosDataTable` لا يمرّر الخلايا في `tr`: الخلايا بياناتٌ (أسماءٌ
// وأوقات) والعناوينُ تُترجَم عند المنادي.
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../picpos_shell/picpos_empty_state.dart';
import '../../picpos_shell/picpos_surface.dart';

class HrTableColumn {
  const HrTableColumn(this.label, {this.flex = 2});
  final String label;
  final int flex;
}

class HrTableRow {
  const HrTableRow({required this.cells, this.onTap, this.key});
  final List<Widget> cells;
  final VoidCallback? onTap;
  final Key? key;
}

class HrTable extends StatelessWidget {
  const HrTable({
    super.key,
    required this.columns,
    required this.rows,
    this.minWidth = 900,
    this.emptyTitle,
    this.emptyHint,
    this.emptyIcon = PhosphorIconsBold.tray,
    this.footer,
  });
  final List<HrTableColumn> columns;
  final List<HrTableRow> rows;
  final double minWidth;
  final String? emptyTitle;
  final String? emptyHint;
  final IconData emptyIcon;

  /// صفُّ مجاميعَ اختياريّ بنفس أعمدة الجدول.
  final List<Widget>? footer;

  @override
  Widget build(BuildContext context) {
    final head = TextStyle(
        fontSize: 11.5, fontWeight: FontWeight.w800, color: context.picposMuted);
    Widget line(List<Widget> cells) => Row(children: [
          for (var i = 0; i < columns.length; i++)
            Expanded(
              flex: columns[i].flex,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: i < cells.length ? cells[i] : const SizedBox(),
              ),
            ),
        ]);
    return LayoutBuilder(builder: (context, c) {
      final width = c.maxWidth < minWidth ? minWidth : c.maxWidth;
      final table = Container(
        width: width,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: context.picposCard,
          border: Border.all(color: context.picposHairline),
          borderRadius: BorderRadius.circular(17),
        ),
        child: Column(children: [
          Container(
            color: context.picposField,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: line([
              for (final col in columns)
                Text(col.label,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: head),
            ]),
          ),
          Expanded(
            child: rows.isEmpty
                // قابلٌ للتمرير: جدولٌ قصيرٌ في تبويبٍ لا يفيض بحالته الفارغة.
                ? ListView(children: [
                    PicPosEmptyState(
                      icon: emptyIcon,
                      title: emptyTitle ?? '',
                      hint: emptyHint,
                    ),
                  ])
                : ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: context.picposHairline),
                    itemBuilder: (context, i) {
                      final r = rows[i];
                      return InkWell(
                        key: r.key,
                        onTap: r.onTap,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 9),
                          child: line(r.cells),
                        ),
                      );
                    },
                  ),
          ),
          if (footer != null)
            Container(
              color: context.picposField,
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: line(footer!),
            ),
        ]),
      );
      if (width <= c.maxWidth) return table;
      return SingleChildScrollView(
          scrollDirection: Axis.horizontal, child: table);
    });
  }
}

/// نصُّ خليّةٍ قويٌّ (13/700) مع سطرٍ خافتٍ اختياريّ.
class HrCellText extends StatelessWidget {
  const HrCellText(this.text, {super.key, this.sub, this.color, this.number = false});
  final String text;
  final String? sub;
  final Color? color;
  final bool number;

  @override
  Widget build(BuildContext context) {
    final strong = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: color ?? context.picposText,
      fontFeatures: number ? const [FontFeature.tabularFigures()] : null,
    );
    if (sub == null || sub!.isEmpty) {
      return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: strong);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: strong),
        Text(sub!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: context.picposMuted)),
      ],
    );
  }
}

/// شريطُ أدواتٍ تحت الرأس: بطاقةٌ بحدٍّ سفليٍّ و`Wrap` يلتفّ.
class HrToolbar extends StatelessWidget {
  const HrToolbar({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.fromSTEB(20, 10, 20, 12),
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border(bottom: BorderSide(color: context.picposHairline)),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: children,
      ),
    );
  }
}

/// تبويباتُ شاشةٍ على هويّة PicPos (‏`TabBar` في بطاقة).
class HrTabBar extends StatelessWidget implements PreferredSizeWidget {
  const HrTabBar({super.key, required this.controller, required this.tabs});
  final TabController controller;

  /// (مفتاح، أيقونة، تسمية).
  final List<(String, IconData, String)> tabs;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border(bottom: BorderSide(color: context.picposHairline)),
      ),
      child: TabBar(
        controller: controller,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelColor: Theme.of(context).colorScheme.primary,
        unselectedLabelColor: context.picposMuted,
        tabs: [
          for (final (key, icon, label) in tabs)
            Tab(
              key: Key(key),
              height: 44,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 17),
                const SizedBox(width: 7),
                Text(label),
              ]),
            ),
        ],
      ),
    );
  }
}

/// زرُّ تنقّلٍ بين الأيّام/الأشهر: سابقٌ ونصٌّ وتالٍ، وأسهمٌ تتبع الاتّجاه.
class HrStepper extends StatelessWidget {
  const HrStepper({
    super.key,
    required this.label,
    required this.onPrev,
    required this.onNext,
    this.onTapLabel,
    this.keyPrefix = 'hr_step',
  });
  final String label;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback? onTapLabel;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: context.picposField,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          key: Key('${keyPrefix}_prev'),
          iconSize: 16,
          onPressed: onPrev,
          icon: Icon(rtl
              ? PhosphorIconsBold.caretRight
              : PhosphorIconsBold.caretLeft),
        ),
        InkWell(
          key: Key('${keyPrefix}_label'),
          onTap: onTapLabel,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: context.picposText,
                  fontFeatures: const [FontFeature.tabularFigures()],
                )),
          ),
        ),
        IconButton(
          key: Key('${keyPrefix}_next'),
          iconSize: 16,
          onPressed: onNext,
          icon: Icon(rtl
              ? PhosphorIconsBold.caretLeft
              : PhosphorIconsBold.caretRight),
        ),
      ]),
    );
  }
}
