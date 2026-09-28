// شريطُ إجماليّات المشتريات — **نحيفٌ نهائيّاً**.
//
// قرارُ المالك 2026-09-18 على تصميم «الاستعلام عن المشتريات»: «البطاقاتُ
// الخمسُ تُستبدَل بالشريط النحيف نهائيّاً».
//
// ═══ ما ذهب وما بقي ═══
//
// **ذهب الشكلُ**: بطاقةٌ رئيسيّةٌ داكنةٌ بارتفاع ١٥٠px تحمل المعادلةَ وشريطَ
// نسبةٍ، وأربعُ بطاقاتٍ ثانويّةٌ بشاراتِ اتّجاهٍ (‏`purchases_summary_cards.dart`،
// ٦٢١ سطراً). وكانت تأكل ١٦٠–٢٤٠px من أعلى شاشةٍ **جدولُها هو المقصود**.
//
// **وبقيت الأرقامُ الستّةُ كلُّها.** القرارُ يمسّ الشكلَ لا المحتوى، فإسقاطُ
// «المسدَّد» و«المتبقي» و«عدد الفواتير» — وهي ليست في صورة التصميم — كان
// سيسحب من الشاشة معلوماتٍ لم يطلب أحدٌ سحبَها. والشريطُ يلتفّ، فستّةُ بنودٍ
// تنزل سطرَين على شاشةٍ ضيّقة بدل أن تفيض.
//
// ⚠️ **وشاراتُ الاتّجاه (±٪) سقطت مع البطاقات**، وهي خسارةٌ حقيقيّةٌ لا
// تجميل: `previousPeriod` ما زال مقيساً في الحالة ولا قارئَ له الآن. أُبقي
// الحسابُ في المتحكّم لأنّ إسقاطَه تغييرُ منطقٍ لا شكل، ويُستأنَف متى طلب
// المالكُ إظهارَ الاتّجاه في الشكل الجديد.
part of 'purchases_picpos_screen.dart';

/// لونُ النصِّ الخافت — `--muted` في الوضعين.
///
/// ⚠️ **يعيش هنا لأنّ ثلاثةَ ملفّاتٍ تقرؤه** (‏هذا وشريطُ الترشيح والجدول)،
/// وكان في `purchases_summary_cards.dart` المحذوف.
Color _purMuted(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF94A3B8)
        : AppColors.textMuted;

/// شريطُ الإجماليّات — سطرٌ واحدٌ يلتفّ، بدل صفِّ بطاقات.
class PurchasesTotalsBar extends ConsumerWidget {
  const PurchasesTotalsBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalAmount = ref.watch(
        purchaseInvoicesControllerProvider.select((s) => s.totalAmount));
    final totalPaid = ref
        .watch(purchaseInvoicesControllerProvider.select((s) => s.totalPaid));
    final totalRemaining = ref.watch(
        purchaseInvoicesControllerProvider.select((s) => s.totalRemaining));
    final totalReturns = ref.watch(
        purchaseInvoicesControllerProvider.select((s) => s.totalReturns));
    final invoiceCount = ref.watch(
        purchaseInvoicesControllerProvider.select((s) => s.invoiceCount));

    String money(double v) =>
        '${v.toStringAsFixed(AppConstants.decimalPlaces)} '
        '${AppConstants.currencySymbolEn}';

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 16, 6),
      child: PicPosTotalsBar(
        items: [
          PicPosTotal(
            label: 'إجمالي المشتريات',
            value: money(totalAmount),
          ),
          PicPosTotal(
            label: 'إجمالي المرتجعات',
            value: money(totalReturns),
            tone: AppColors.error,
          ),
          // ⚠️ **الصافي مطروحٌ لا مجموع**: `total - returns` هي عينُ معادلة
          // البطاقة الرئيسيّة المحذوفة، ونقلُها كما هي شرطُ ألّا يتغيّر رقمٌ
          // مع تغيّر الشكل.
          PicPosTotal(
            label: 'الصافي',
            value: money(totalAmount - totalReturns),
            emphasis: true,
          ),
          PicPosTotal(
            label: 'المسدَّد',
            value: money(totalPaid),
            tone: AppColors.success,
          ),
          PicPosTotal(
            label: 'المتبقي',
            value: money(totalRemaining),
            tone: AppColors.warning,
          ),
          PicPosTotal(label: 'عدد الفواتير', value: '$invoiceCount'),
        ],
      ),
    );
  }
}
