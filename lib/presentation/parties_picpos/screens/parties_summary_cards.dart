// بطاقاتُ عدّاداتِ «العملاء والموردين» — البطاقةُ نفسُها مشتركةٌ في
// `picpos_shell/picpos_kpi_row.dart` (سبعُ كتلِ تصميمٍ تحملها بترميزٍ متطابق)،
// وهذا الملفُّ يختار **ما يُعدّ** لا كيف يُرسم.
//
// ⚠️ **وكلُّ عدّادٍ هنا مشتقٌّ من عمودٍ حقيقيّ** — راجع [PicPosPartyKpis].
// لا «متوسّطَ شراءٍ» ولا «نموَّ عملاءَ» لأن لا مصدرَ لهما في `parties`.
part of 'parties_picpos_screen.dart';

/// لونُ النصِّ الخافت — يُعاد تصديرُه باسمٍ محلّيٍّ كي لا تتغيّر مواضعُ
/// الاستعمال في ملفّات هذه الشاشة.
Color _partiesMuted(BuildContext context) => picposMuted(context);

/// صفُّ البطاقات الأربع.
///
/// يُبنى من [PicPosPartyKpis] المحسوبةِ على القائمة **الكاملة** لا المرشَّحة —
/// راجع تعليقَ الصنف: عدّادٌ يتغيّر مع كلّ ضغطةِ بحثٍ لا يُعلِم بشيء.
class PartiesSummaryCards extends StatelessWidget {
  const PartiesSummaryCards({super.key, required this.kpis});

  final PicPosPartyKpis kpis;

  @override
  Widget build(BuildContext context) {
    return PicPosKpiRow(
      kpis: [
        PicPosKpi(
          label: tr('إجمالي الأطراف'),
          value: '${kpis.total}',
          icon: PhosphorIconsBold.usersThree,
          tint: AppColors.primary,
        ),
        PicPosKpi(
          label: tr('عملاء'),
          value: '${kpis.customers}',
          icon: PhosphorIconsBold.user,
          tint: AppColors.info,
        ),
        PicPosKpi(
          label: tr('موردين'),
          value: '${kpis.suppliers}',
          icon: PhosphorIconsBold.truck,
          tint: AppColors.warning,
        ),
        // ⚠️ الرابعةُ **متجاوزو حدّ الائتمان** لا «إجمالي الأرصدة»: الأخيرُ
        // رقمٌ يجمع مديناً ودائناً في خانةٍ واحدةٍ فيقرأ خطأً، وهذا عدٌّ
        // صريحٌ قابلٌ للتصرّف.
        PicPosKpi(
          label: tr('تجاوزوا حد الائتمان'),
          value: '${kpis.overLimitCount}',
          icon: PhosphorIconsBold.warning,
          tint: kpis.overLimitCount > 0 ? AppColors.error : AppColors.success,
        ),
      ],
    );
  }
}
