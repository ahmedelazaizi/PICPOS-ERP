import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens.dart';
import 'basics.dart';

/// KPI card: 3 px start-side tone stripe (follows RTL/LTR), icon badge,
/// label, figure and an optional footnote.
class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.tone = PicPosTone.brand,
    this.footnote,
    this.onTap,
  });
  final String label;
  final String value;
  final IconData? icon;
  final PicPosTone tone;
  final String? footnote;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final c = tone.color(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(children: [
          PositionedDirectional(start: 0, top: 0, bottom: 0, width: 3, child: ColoredBox(color: c)),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  if (icon != null) ...[
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: c.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(icon, size: 18, color: c),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(label,
                        style: tt.labelMedium?.copyWith(color: context.picposMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                ]),
                const SizedBox(height: 10),
                AmountText(value, style: tt.headlineMedium),
                if (footnote != null)
                  Text(footnote!,
                      style: tt.bodySmall?.copyWith(color: context.picposMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// Section card ("block"): 3.5×15 brand bar, title 14.5/800, muted
/// subtitle, end-aligned actions, then the content.
class PicPosBlock extends StatelessWidget {
  const PicPosBlock({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const [],
    this.padding = const EdgeInsets.all(PicPosSpacing.lg),
  });
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Container(
                width: 3.5,
                height: 15,
                decoration: BoxDecoration(color: context.picposBrandInk, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(title,
                      style: tt.titleSmall?.copyWith(fontSize: 14.5, fontWeight: FontWeight.w800),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (subtitle != null)
                    Text(subtitle!,
                        style: tt.labelSmall?.copyWith(fontSize: 11.5, fontWeight: FontWeight.w600, color: context.picposMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                ]),
              ),
              if (actions.isNotEmpty) Wrap(spacing: 7, children: actions),
            ]),
            const SizedBox(height: PicPosSpacing.md),
            child,
          ],
        ),
      ),
    );
  }
}

/// A column of [PicPosDataList].
class PicPosColumn<T> {
  const PicPosColumn({required this.label, required this.value, this.numeric = false, this.flex = 1});
  final String label;
  final String Function(T row) value;

  /// Right/left aligned per direction, tabular digits, LTR figures.
  final bool numeric;
  final int flex;
}

/// Mobile data list: card rows below 600 dp (first column as the title, the
/// rest as label/value pairs), a hairline table at 600 dp and wider.
class PicPosDataList<T> extends StatelessWidget {
  const PicPosDataList({super.key, required this.columns, required this.rows, this.onTap})
      : assert(columns.length > 0);
  final List<PicPosColumn<T>> columns;
  final List<T> rows;
  final void Function(T row)? onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      return c.maxWidth < PicPosBreakpoints.medium ? _cards(context) : _table(context);
    });
  }

  Widget _cell(BuildContext context, PicPosColumn<T> col, String text, TextStyle? style) => col.numeric
      ? AmountText(text, style: style, textAlign: TextAlign.end)
      : Text(text, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);

  Widget _cards(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      for (final r in rows)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(PicPosRadii.card),
              onTap: onTap == null ? null : () => onTap!(r),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _cell(context, columns.first, columns.first.value(r), tt.titleSmall),
                  for (final col in columns.skip(1))
                    Row(children: [
                      Expanded(
                        child: Text(col.label,
                            style: tt.bodySmall?.copyWith(color: context.picposMuted),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 8),
                      Flexible(child: _cell(context, col, col.value(r), tt.bodyMedium)),
                    ]),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }

  Widget _table(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    Widget row(List<Widget> cells, {Color? fill, VoidCallback? tap}) => InkWell(
          onTap: tap,
          child: Container(
            color: fill,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Row(children: cells),
          ),
        );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        row([
          for (final col in columns)
            Expanded(
              flex: col.flex,
              child: Text(col.label,
                  textAlign: col.numeric ? TextAlign.end : TextAlign.start,
                  style: tt.labelMedium?.copyWith(color: context.picposMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
        ], fill: context.picposField),
        for (final r in rows) ...[
          Divider(height: 1, color: context.picposHairline),
          row([
            for (final col in columns) Expanded(flex: col.flex, child: _cell(context, col, col.value(r), tt.bodyMedium)),
          ], tap: onTap == null ? null : () => onTap!(r)),
        ],
      ]),
    );
  }
}
