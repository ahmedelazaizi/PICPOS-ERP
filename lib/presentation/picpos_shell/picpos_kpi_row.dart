// صفُّ عدّاداتِ PicPos — أيقونةٌ ملوّنةٌ في مربّعٍ مصبوغٍ بشفافيّة، ثمّ تسميةٌ
// خافتةٌ فوق رقمٍ عريض، أربعةً في صفّ.
//
// ═══ لماذا مشتركٌ في `picpos_shell` ═══
//
// **سبعُ** كتلٍ في ملفّ التصميم تحمل هذه البطاقةَ بترميزٍ متطابقٍ حرفيّاً
// (‏`partyKpis` · `retKpis` · `prodKpis` · `invKpis` · `anKpis` · `userKpis` ·
// `kpis`) — قِيس بـ`diff` على الترميز لا بالنظر. وقد كُتبت مرّتين بالفعل قبل
// هذا الملفّ (في `parties_summary_cards.dart` و`picpos_returns_panel.dart`)،
// وكانت الثالثةُ ستقع مع أوّل شاشةٍ تالية.
//
// ⚠️ **ولمَ لا `PicPosStatTile` المشتركةُ القائمة؟** بنيتُها **رأسيّةٌ** (صفُّ
// أيقونةٍ وتسميةٍ، ثمّ القيمةُ تحته) وتحمل شارةَ اتّجاهٍ ونسبةَ تغيّر عن فترةٍ
// سابقة. وبطاقةُ هذا التصميم **أفقيّةٌ بلا اتّجاه**. فلَيُّ القائمةِ إلى هذا
// الشكل كان سيكسرها على مستهلكيها في التقارير — وهم أكثر.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// لونُ النصِّ الخافت — `--muted` في الوضعَين.
Color picposMuted(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF94A3B8)
        : AppColors.textMuted;

/// عدّادٌ واحد — بياناتٌ خالصةٌ لا ودجت، فيُبنى الصفُّ من قائمةٍ منها.
class PicPosKpi {
  const PicPosKpi({
    required this.label,
    required this.value,
    required this.icon,
    required this.tint,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color tint;
}

/// بطاقةُ عدّادٍ واحدة.
class PicPosKpiCard extends StatelessWidget {
  const PicPosKpiCard({super.key, required this.kpi});

  final PicPosKpi kpi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              // ‏`1F` سُدسيّاً = 31/255 ≈ 12٪ — نفسُ شفافيّةِ التصميم.
              color: kpi.tint.withValues(alpha: 31 / 255),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(kpi.icon, size: 17, color: kpi.tint),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  kpi.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: picposMuted(context),
                  ),
                ),
                Text(
                  kpi.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 19,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                    color: theme.textTheme.bodyLarge?.color,
                    fontFeatures: const [ui.FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// صفُّ العدّادات — أربعةٌ في العرض الكامل، اثنان دونه.
class PicPosKpiRow extends StatelessWidget {
  const PicPosKpiRow({super.key, required this.kpis});

  final List<PicPosKpi> kpis;

  @override
  Widget build(BuildContext context) {
    if (kpis.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 720 ? 2 : 4;
        // ارتفاعٌ صريحٌ لا نسبةٌ محسوبةٌ من العرض: النسبةُ كانت تعطي ٦٠ بكسلاً
        // بينما المحتوى يحتاج ~٦٥، ففاض بـ‏٤٫١ ثمّ ٤٫٥ حسب العرض (‏قِيس
        // 2026-08-22). و`mainAxisExtent` لا يتبع العرضَ أصلاً.
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 68,
          ),
          itemCount: kpis.length,
          itemBuilder: (context, i) => PicPosKpiCard(kpi: kpis[i]),
        );
      },
    );
  }
}
