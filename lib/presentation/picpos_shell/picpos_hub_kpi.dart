// بطاقةُ مؤشّرٍ بحدٍّ جانبيٍّ ملوَّنٍ وفرقٍ عن الفترة السابقة.
//
// المصدر: كتلةُ `kind:'kpis'` في «PicPos Branches.dc.html» — وهي **غيرُ**
// بطاقة `PicPosKpiCard` القائمة:
//
//   • القائمةُ **أفقيّةٌ** (أيقونةٌ يمينَ الرقم) وبلا فرقٍ ولا سهم.
//   • وهذه **رأسيّةٌ** بحدٍّ جانبيٍّ ٣ بكسل بلون المؤشّر: صفُّ أيقونةٍ
//     وتسميةٍ، ثمّ رقمٌ ٢٥، ثمّ سطرُ فرقٍ بسهمٍ ونصِّ مقارنة.
//
// ولا تُلوى إحداهما إلى الأخرى: القائمةُ يستهلكها ثلاثَ عشرةَ شاشةَ تقريرٍ
// وشاشاتُ الأطراف والمرتجعات، فتغييرُ شكلِها يكسرها عندهم جميعاً.
//
// ⚠️ **والفرقُ اختياريٌّ بالبناء.** التصميمُ يعامل `delta` الفارغةَ أو
// «—» على أنّها **لا فرق** فيُخفي السهمَ والنصَّ معاً ويُبقي سطرَ المقارنة.
// فلو رُسم سهمٌ لصفرٍ لقرأه المشغّلُ اتّجاهاً، وهو لا اتّجاه.
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'picpos_surface.dart';

/// مؤشّرٌ واحدٌ في صفّ مؤشّرات المركز — بياناتٌ خالصةٌ لا ودجت.
class PicPosHubKpi {
  const PicPosHubKpi({
    required this.icon,
    required this.label,
    required this.value,
    required this.tint,
    this.delta,
    this.up = true,
    this.vs = '',
  });

  final IconData icon;
  final String label;
  final String value;
  final Color tint;

  /// الفرقُ عن الفترة السابقة. `null` أو فارغٌ أو «—» ⇒ لا سهمَ ولا نصَّ فرق.
  final String? delta;
  final bool up;

  /// نصُّ المقارنة الخافتُ بجانب الفرق — «بالتكلفة» أو «من ٧ مسجلة».
  final String vs;

  bool get hasDelta {
    final d = delta;
    return d != null && d.isNotEmpty && d != '—';
  }
}

/// بطاقةُ مؤشّرٍ واحدة.
class PicPosHubKpiCard extends StatelessWidget {
  const PicPosHubKpiCard({super.key, required this.kpi});

  final PicPosHubKpi kpi;

  @override
  Widget build(BuildContext context) {
    final deltaFg = kpi.up ? AppColors.success : AppColors.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border(
          top: BorderSide(color: context.picposHairline),
          bottom: BorderSide(color: context.picposHairline),
          left: BorderSide(color: context.picposHairline),
          right: BorderSide(color: context.picposHairline),
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      foregroundDecoration: BoxDecoration(
        // الحدُّ الجانبيُّ الملوَّن — `border-inline-start:3px` في التصميم.
        // و`BorderDirectional` تحترم RTL فيقع على الجهة نفسِها.
        border: BorderDirectional(
          start: BorderSide(color: kpi.tint, width: 3),
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(kpi.icon, size: 15, color: kpi.tint),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  kpi.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: context.picposMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            kpi.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w800,
              height: 1.1,
              color: context.picposText,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (kpi.hasDelta || kpi.vs.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                if (kpi.hasDelta) ...[
                  Icon(
                    kpi.up
                        ? Icons.trending_up_rounded
                        : Icons.trending_down_rounded,
                    size: 13,
                    color: deltaFg,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    kpi.delta!,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: deltaFg,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                if (kpi.vs.isNotEmpty)
                  Expanded(
                    child: Text(
                      kpi.vs,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: context.picposMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// صفُّ المؤشّرات — شبكةٌ متساويةُ الأعمدة تلتفّ عند الضيق.
///
/// ⚠️ **تلتفّ ولا تُسحَق**: التصميمُ يفترض عرضَ ١٩٢٠ وخمسةَ مؤشّراتٍ في صفّ،
/// وعلى لوحِ كاشيرٍ ضيّقٍ كان الصفُّ الثابتُ يهرس الأرقامَ إلى «…». فيُحسَب
/// عرضُ العنصر من المتاح ويُنزَل صفّاً تحت [minTileWidth].
class PicPosHubKpiRow extends StatelessWidget {
  const PicPosHubKpiRow({
    super.key,
    required this.items,
    this.minTileWidth = 190,
    this.gap = 13,
  });

  final List<PicPosHubKpi> items;
  final double minTileWidth;
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, c) {
        final maxW = c.maxWidth.isFinite ? c.maxWidth : minTileWidth;
        var perRow = ((maxW + gap) / (minTileWidth + gap)).floor();
        if (perRow < 1) perRow = 1;
        if (perRow > items.length) perRow = items.length;
        final tileW = (maxW - gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final k in items)
              SizedBox(width: tileW, child: PicPosHubKpiCard(kpi: k)),
          ],
        );
      },
    );
  }
}
