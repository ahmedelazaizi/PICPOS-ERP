// لوحةُ حالاتٍ بأعمدة — كتلةُ `kind:'board'` في ملفّات التصميم.
//
// أعمدةٌ بعددِ الحالات، لكلٍّ رأسٌ بخطٍّ علويٍّ ملوَّنٍ وعدّاد، وتحته بطاقاتٌ
// مضغوطة. تستعملها «الزيارات» في وحدة المناطق و«الاعتمادات» في التحليلات.
//
// ⚠️ **العدّادُ في الرأس عددُ ما في الحالة كلِّها لا ما يُعرَض.** التصميمُ
// يعرض ثلاثَ بطاقاتٍ ثمّ سطرَ «+٢٨ زيارة» — فالعدّادُ يقول الحقيقةَ وسطرُ
// «المزيد» يقول كم بقي. ولو ساوى العدّادُ المعروضَ لقرأ المشغّلُ أنّ
// الزياراتِ ثلاثٌ وهي واحدةٌ وثلاثون.
import 'package:flutter/material.dart';

import 'picpos_surface.dart';

/// بطاقةٌ في عمودٍ — سطرُ عنوانٍ وقيمة، ثمّ سطرٌ خافت، ثمّ سطرُ وسمٍ بأيقونة.
class PicPosBoardCard {
  const PicPosBoardCard({
    required this.title,
    this.subtitle = '',
    this.value = '',
    this.meta = '',
    this.metaIcon,
    this.metaTint,
    this.onTap,
  });

  final String title;
  final String subtitle;

  /// `—` أو الفراغُ يُرسَم خافتاً: لا قيمةَ بعد، لا صفرٌ محقَّق.
  final String value;

  final String meta;
  final IconData? metaIcon;
  final Color? metaTint;
  final VoidCallback? onTap;
}

/// عمودُ حالةٍ واحد.
class PicPosBoardColumn {
  const PicPosBoardColumn({
    required this.label,
    required this.icon,
    required this.tint,
    required this.total,
    required this.cards,
  });

  final String label;
  final IconData icon;
  final Color tint;

  /// العددُ الكلّيُّ في هذه الحالة — قد يفوق طولَ [cards].
  final int total;

  /// ما يُعرَض منها.
  final List<PicPosBoardCard> cards;
}

class PicPosStatusBoard extends StatelessWidget {
  const PicPosStatusBoard({
    super.key,
    required this.columns,
    this.minColumnWidth = 250,
    this.gap = 13,
    this.emptyLabel = 'لا شيءَ هنا',
  });

  final List<PicPosBoardColumn> columns;
  final double minColumnWidth;
  final double gap;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    if (columns.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, c) {
        final maxW = c.maxWidth.isFinite ? c.maxWidth : minColumnWidth;
        var perRow = ((maxW + gap) / (minColumnWidth + gap)).floor();
        if (perRow < 1) perRow = 1;
        if (perRow > columns.length) perRow = columns.length;
        final w = (maxW - gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          // الأعمدةُ تختلف طولاً باختلاف عددِ بطاقاتها — وشدُّها لأطولها
          // يترك فراغاً أبيضَ تحت القصيرة.
          crossAxisAlignment: WrapCrossAlignment.start,
          children: [
            for (final col in columns)
              SizedBox(width: w, child: _column(context, col)),
          ],
        );
      },
    );
  }

  Widget _column(BuildContext context, PicPosBoardColumn col) {
    return Container(
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border.all(color: context.picposHairline),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: col.tint, width: 3),
                bottom: BorderSide(color: context.picposHairline),
              ),
            ),
            child: Row(
              children: [
                Icon(col.icon, size: 16, color: col.tint),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    col.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: context.picposText,
                    ),
                  ),
                ),
                Text(
                  '${col.total}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: col.tint,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (col.cards.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Center(
                      child: Text(
                        emptyLabel,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: context.picposMuted,
                        ),
                      ),
                    ),
                  ),
                for (var i = 0; i < col.cards.length; i++) ...[
                  if (i > 0) const SizedBox(height: 9),
                  _card(context, col.cards[i]),
                ],
                // ⚠️ سطرُ «المزيد» يُشتقّ من الفرق لا يُكتَب — فلا يقول
                //    «+٢٨» بينما الباقي اثنان.
                if (col.total > col.cards.length) ...[
                  const SizedBox(height: 9),
                  Center(
                    child: Text(
                      '+${col.total - col.cards.length}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: context.picposBrandInk,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, PicPosBoardCard c) {
    final hasValue = c.value.isNotEmpty && c.value != '—';
    final body = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: context.picposField,
        border: Border.all(color: context.picposHairline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  c.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: context.picposText,
                  ),
                ),
              ),
              if (c.value.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  c.value,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color:
                        hasValue ? context.picposText : context.picposMuted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
          if (c.subtitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                c.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: context.picposMuted,
                ),
              ),
            ),
          if (c.meta.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  if (c.metaIcon != null) ...[
                    Icon(
                      c.metaIcon,
                      size: 12,
                      color: c.metaTint ?? context.picposMuted,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      c.meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: c.metaTint ?? context.picposMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    if (c.onTap == null) return body;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: c.onTap,
        borderRadius: BorderRadius.circular(12),
        child: body,
      ),
    );
  }
}
