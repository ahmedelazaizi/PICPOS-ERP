// بطاقاتُ عدّاداتِ «العملاء والموردين» — أربعُ بطاقاتٍ أفقيّةٍ في التصميم:
// أيقونةٌ ملوّنةٌ في مربّعٍ مصبوغٍ بشفافيّةٍ، ثمّ تسميةٌ خافتةٌ فوق رقمٍ عريض.
//
// ⚠️ **ولمَ لم تُستعمل `PicPosStatTile` المشتركة؟** بنيتُها رأسيّةٌ (صفُّ
// أيقونةٍ وتسميةٍ ثمّ القيمةُ تحته) وتحمل شارةَ اتّجاهٍ ونسبةَ تغيّر. وبطاقةُ
// التصميم هنا **أفقيّةٌ بلا اتّجاه**: لا فترةَ سابقةً تُقارَن بها أعدادُ
// الأطراف. فلَيُّ المشتركةِ إلى هذا الشكل كان سيُفسدها على مستهلكيها.
//
// ⚠️ **وكلُّ عدّادٍ هنا مشتقٌّ من عمودٍ حقيقيّ** — راجع [PicPosPartyKpis].
// لا «متوسّطَ شراءٍ» ولا «نموَّ عملاءَ» لأن لا مصدرَ لهما في `parties`.
part of 'parties_picpos_screen.dart';

/// لونُ النصِّ الخافت — `--muted` في الوضعَين.
Color _partiesMuted(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF94A3B8)
        : AppColors.textMuted;

/// بطاقةُ عدّادٍ واحدة.
class _PartyKpiCard extends StatelessWidget {
  const _PartyKpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.tint,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color tint;

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
              color: tint.withValues(alpha: 31 / 255),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: tint),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _partiesMuted(context),
                  ),
                ),
                Text(
                  value,
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

/// صفُّ البطاقات الأربع.
///
/// يُبنى من [PicPosPartyKpis] المحسوبةِ على القائمة **الكاملة** لا المرشَّحة —
/// راجع تعليقَ الصنف: عدّادٌ يتغيّر مع كلّ ضغطةِ بحثٍ لا يُعلِم بشيء.
class PartiesSummaryCards extends StatelessWidget {
  const PartiesSummaryCards({super.key, required this.kpis});

  final PicPosPartyKpis kpis;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      _PartyKpiCard(
        label: 'إجمالي الأطراف',
        value: '${kpis.total}',
        icon: PhosphorIconsBold.usersThree,
        tint: AppColors.primary,
      ),
      _PartyKpiCard(
        label: 'عملاء',
        value: '${kpis.customers}',
        icon: PhosphorIconsBold.user,
        tint: AppColors.info,
      ),
      _PartyKpiCard(
        label: 'موردين',
        value: '${kpis.suppliers}',
        icon: PhosphorIconsBold.truck,
        tint: AppColors.warning,
      ),
      // ⚠️ الرابعةُ **متجاوزو حدّ الائتمان** لا «إجمالي الأرصدة»: الأخيرُ
      // رقمٌ يجمع مديناً ودائناً في خانةٍ واحدةٍ فيقرأ خطأً، وهذا عدٌّ
      // صريحٌ قابلٌ للتصرّف.
      _PartyKpiCard(
        label: 'تجاوزوا حد الائتمان',
        value: '${kpis.overLimitCount}',
        icon: PhosphorIconsBold.warning,
        tint: kpis.overLimitCount > 0 ? AppColors.error : AppColors.success,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // ‏٤ أعمدةٍ تحتاج عرضاً معقولاً؛ دونه ينهار الصفُّ إلى عمودَين بدل
        // أن يفيض. (‏فيضانُ التخطيط لا يُسقط اختباراً إلّا إن فُحص صراحةً —
        // وهو مفحوصٌ في `parties_picpos_screen_test.dart`.)
        final columns = constraints.maxWidth < 720 ? 2 : 4;
        // ارتفاعٌ صريحٌ لا نسبةٌ محسوبة: النسبةُ كانت تُشتقّ من العرض فتعطي
        // ‏٦٠ بكسلاً بينما المحتوى يحتاج ~٦٥ — ففاض بـ‏٤٫١ ثمّ ‏٤٫٥ بكسل حسب
        // العرض. و`mainAxisExtent` يثبّت الارتفاعَ فلا يتبع العرضَ أصلاً.
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 68,
          ),
          itemCount: cards.length,
          itemBuilder: (context, i) => cards[i],
        );
      },
    );
  }
}
