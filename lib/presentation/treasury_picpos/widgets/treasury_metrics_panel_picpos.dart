// لوحُ مقاييس الخزينة بهويّة PicPos — **فوركٌ بقرار المالك 2026-08-22**
// («انسخه إلى PicPos ولا تشارك تعديلاتِ PicPos على UralCash»).
//
// المصدر: `treasury/widgets/treasury_metrics_panel.dart`، ويبقى بلا مساسٍ
// لشاشة UralCash.
//
// **الجديدُ من التصميم:** شريطُ تقسيمِ الرصيد (`trSplit`) — نقديٌّ وبنكيٌّ
// وكليك بنسبهم. والأصلُ يعرض المجموعَ وحدَه.
//
// ⚠️ **وسندا القبض والصرف لم يعودا هنا** — انتقلا بحرّاسهما إلى
// `treasury_actions_grid_picpos.dart` (شبكةُ ٢×٢ يسارَ هذه البطاقة كما في
// التصميم)، وهي **داخلَ مجلد التوأم** فلا تنكسر حافةُ
// `picpos_permission_parity_test`. والحارسان هناك يُمرَّر لهما `onGranted`
// صراحةً — راجع تعليقَ ذلك الملفّ: تخمينُ الحارس لا يعرف بطاقةً مخصَّصة.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart';
import '../../../domain/models/picpos_treasury_view.dart';
import '../../../core/theme/app_colors.dart';
import 'treasury_picpos_tokens.dart';

import 'package:picpos_erp/l10n/app_localizations.dart';
import '../../../data/providers/providers.dart';
import '../../../core/constants/app_constants.dart';

class TreasuryMetricsPanelPicpos extends ConsumerWidget {
  const TreasuryMetricsPanelPicpos({super.key, this.split});

  /// تقسيمُ الرصيد — يُرسم **داخل** البطاقة الداكنة كما في التصميم.
  ///
  /// `null` يعني «لم يصل بعد» (الصناديقُ تُحمَّل بثّاً)، فتُرسم البطاقةُ بلا
  /// شرائحَ بدل أن تُرسم شرائحُ أصفارٍ تُقرأ خبراً.
  final PicPosTreasurySplit? split;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalBalance = ref.watch(totalCashBalanceProvider);
    final localizations = AppLocalizations.of(context)!;

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          // القرصُ الزخرفيّ في التصميم — يُقصّ بحدّ البطاقة (`overflow:hidden`).
          PositionedDirectional(
            start: -30,
            top: -50,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: TreasuryPicposTokens.bankTint.withValues(alpha: .18),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    PhosphorIconsBold.wallet,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                // ⚠️ `Expanded` لا `Flexible`: هو ما يبتلع الفراغَ فيدفع
                // الشرائحَ إلى آخر الصفّ — ويُغني عن `Spacer` الذي كان
                // **ينازعها العرضَ** فيُجبرها على الالتفاف سطرَين.
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        localizations.totalTreasuryBalance,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .72),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      totalBalance.when(
                        data: (balance) => TreasuryHeroAmountPicpos(amount: balance),
                        loading: () => const TreasuryHeroAmountPicpos(amount: null),
                        error: (e, s) => const TreasuryHeroAmountPicpos(amount: 0),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // الشرائحُ **داخل** البطاقة الداكنة — لا تحتها على الفاتح.
                // راجع تعليقَ [PicPosTreasurySplitChips]: وضعُها خارجاً هو ما
                // أنتج «أبيضَ على فاتح» في لقطة المالك. والتصميمُ يضعها في
                // آخر الصفّ (`margin-inline-start:auto`) لا تحت الرقم.
                //
                // ونسبةٌ ثابتةٌ من الصفّ (٤ مقابل ٥) لا عرضٌ طبيعيّ: بها تبقى
                // الشرائحُ **متناسبةً مع مساحة البطاقة** على أيّ عرضِ نافذة،
                // وتقسم ما تأخذه بالتساوي فلا تلتفّ ولا تفيض.
                if (split != null)
                  Expanded(
                    flex: 4,
                    child: PicPosTreasurySplitChips(split: split!),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// الرقمُ الكبير في البطاقة الداكنة، وكودُ العملة صغيراً بجانبه.
///
/// ═══ ⚠️ لماذا صفٌّ لا سلسلةٌ واحدة ═══
///
/// كان يُكتب `'$number $currency'` في `Text` واحدة. وفي فقرةٍ عربيّةٍ (RTL)
/// تُشكّل الأرقامُ والحروفُ اللاتينيّةُ **مقطعاً واحداً يساريّاً**، فيُرسم
/// الرقمُ ثمّ الكودُ يمينَه — أي الكودُ **بعد** الرقم بصريّاً. والتصميمُ يضعه
/// **قبلَه** (`{{trTotal}}<span>EGP</span>` في حاوٍ RTL: الرقمُ يميناً والكودُ
/// يسارَه).
///
/// فالصفُّ يحسم الترتيبَ بالتخطيط لا بخوارزمية bidi: أوّلُ عنصرٍ في `Row`
/// تحت RTL يقع أقصى اليمين.
///
/// و[AppConstants.currencySymbolEn] **كودُ عملةِ المنشأة** لا `EGP` محفورة —
/// التصميمُ مصريُّ العيّنة، والتنصيبةُ قد تكون أردنيّة.
@visibleForTesting
class TreasuryHeroAmountPicpos extends StatelessWidget {
  const TreasuryHeroAmountPicpos({super.key, required this.amount});

  /// `null` أثناء التحميل — فتُعرض نقاطٌ بدل صفرٍ يُقرأ خبراً.
  final double? amount;

  @override
  Widget build(BuildContext context) {
    final a = amount;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(
          child: Text(
            a == null ? '...' : NumberFormat('#,##0.00', 'ar').format(a),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              height: 1.15,
              letterSpacing: -.5,
              fontWeight: FontWeight.w800,
              fontFeatures: [ui.FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          AppConstants.currencySymbolEn,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .6),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// شرائحُ تقسيم الرصيد — `trSplit` في التصميم.
///
/// ═══ ⚠️ عطبٌ شُحن ثمّ صُحّح — والدرسُ أهمُّ من الإصلاح ═══
///
/// كُتبت أوّلاً شريطاً أفقيّاً بنصوصٍ **بيضاء** (`Colors.white70`) لأنها
/// صُمِّمت لتقع داخل البطاقة الداكنة، ثمّ وُضعت **خارجَها** على خلفيّة
/// الصفحة الفاتحة. النتيجةُ في لقطة المالك: نصٌّ غيرُ مقروءٍ ومقصوص.
///
/// وهو **حرفيّاً** عطبُ `headingRowColor` الذي حُرس في هذه الجلسة نفسِها:
/// لونُ النصِّ ولونُ الأرضيّة عقدٌ **مقترن**، وفصلُ أحدهما عن الآخر يُخفي
/// المحتوى بلا خطأٍ ولا تحذير.
///
/// فالعلاجُ ليس تفتيحَ النصِّ يدويّاً: الشرائحُ صارت **جزءاً من البطاقة
/// الداكنة** كما يرسمها التصميمُ أصلاً، فالعقدُ مستأنَفٌ في مكانٍ واحد.
/// و[onDark] يُمرَّر صراحةً فلا يُستنتَج — من يضعها على سطحٍ فاتحٍ يقول ذلك.
@visibleForTesting
class PicPosTreasurySplitChips extends StatelessWidget {
  const PicPosTreasurySplitChips({
    super.key,
    required this.split,
    this.onDark = true,
  });

  final PicPosTreasurySplit split;

  /// هل تقع الشرائحُ على سطحٍ داكن؟ **يُمرَّر ولا يُستنتَج** — راجع تعليقَ
  /// الصنف: استنتاجُه ضمناً هو ما أنتج «أبيضَ على فاتح».
  final bool onDark;

  /// ألوانُ الأنواع — تُقرأ من [TreasuryPicposTokens] فتطابق **بالبناء** لونَ
  /// بطاقة الصندوق تحتها.
  ///
  /// ⚠️ كانت مكتوبةً هنا حرفيّاً، وكليك فيها `#A78BFA` بينما البطاقةُ
  /// والتصميمُ `#8B5CF6` — لونان لنفس النوع على نفس الشاشة.

  @override
  Widget build(BuildContext context) {
    final labelColor = onDark ? Colors.white70 : AppColors.textMuted;
    final valueColor =
        onDark ? Colors.white : Theme.of(context).textTheme.bodyLarge?.color;
    final chipBg = onDark
        ? Colors.white.withValues(alpha: .10)
        : Theme.of(context).scaffoldBackgroundColor;

    // ═══ 🔴 صفٌّ واحدٌ لا التفاف — بلاغُ المالك 2026-08-23 ═══
    //
    // كانت `Wrap`، فحين ضاق العرضُ نزلت «كليك» سطراً ثانياً: ثلاثُ شرائحَ
    // في سطرَين داخل بطاقةٍ عاليةٍ فبدت صغيرةً ضائعةً — وهو ما أرسله المالك
    // مقارَناً بالمطلوب (ثلاثتُها في سطرٍ واحد).
    //
    // والعلاجُ **ليس تصغيرَها**: `Row` بأبناءٍ مرنين (`Flexible`) يبقيها في
    // سطرٍ واحدٍ دائماً، وتتقلّص بالتساوي عند الضيق بدل أن تلتفّ. والنصُّ
    // داخلَها يقصُّ نفسَه (`ellipsis`) فلا فيضان — وهو ما يحفظه اختبارُ
    // العرضِ الضيّق في `picpos_treasury_metrics_test`.
    return Row(
      children: [
        for (final s in split.slices)
          // `Expanded` لا `Flexible` بحدٍّ أدنى: الحدُّ الأدنى هو ما جعل
          // الثلاثةَ تفيض عند عرضٍ ضيّق (٣×١١٦ > المتاح) — مقيسٌ في اختبار
          // العرض الضيّق. والتقسيمُ بالتساوي يبقيها سطراً واحداً على أيّ
          // عرضٍ ويجعلها **متناسبةً** مع مساحة البطاقة لا ضائعةً فيها.
          Expanded(
            child: Container(
            margin: const EdgeInsetsDirectional.only(start: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: chipBg,
              borderRadius: BorderRadius.circular(11),
              border: onDark
                  ? Border.all(color: Colors.white.withValues(alpha: .14))
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(

                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: TreasuryPicposTokens.tintFor(s.kind),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    // ⚠️ `Flexible` على الاسم: الشريحةُ صارت تقتسم عرضَ
                    // البطاقة، فعلى نافذةٍ ضيّقةٍ يضيق سطرُ الاسم والنسبة.
                    // والقصُّ أهونُ من الشريط الأصفر والأسود.
                    Flexible(
                      child: Text(
                        s.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: labelColor,
                        ),
                      ),
                    ),
                    // النسبةُ تُعرض فقط حين يكون لها معنى — مجموعٌ غيرُ موجبٍ
                    // يجعل «0%» تُقرأ كأن الرصيدَ صفر. راجع [hasBar].
                    if (split.hasBar) ...[
                      const SizedBox(width: 10),
                      Text(
                        s.percentLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: labelColor,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  // ⚠️ **نفسُ تنسيق بقيّة الشاشة، لا `valueLabel`.**
                  //
                  // `PicPosTreasurySlice.valueLabel` يستعمل
                  // `AppConstants.decimalPlaces` وهو **ثابتُ ترجمةٍ = ٣**
                  // (دقّةُ الدينار)، بينما المجموعَ وبطاقاتِ الصناديق وصفوفَ
                  // الحركات كلُّها `NumberFormat('#,##0.00')`. فظهر على
                  // الشاشة الواحدة رقمان بدقّتَين: «0.00» فوق و«0.000» تحته
                  // — وهو ما رآه المالك.
                  //
                  // 🔴 **والجذرُ أعمقُ من العرض ولا يُصلَح هنا:**
                  // `setCurrency` يبدّل الرمزَ والكودَ و**لا يمسّ**
                  // `decimalPlaces`، فتنصيبةٌ بالجنيه تحسب بثلاث خانات.
                  // و`FinancialUtils._precision` مبنيٌّ عليه — أي أنّ تبديلَه
                  // يغيّر تدويرَ المحرّك المحاسبيّ كلِّه وحدَّ اتّزان القيود.
                  // فهو قرارٌ يُعرَض لا تعديلٌ يُدسّ في إصلاح بطاقة.
                  NumberFormat('#,##0.00', 'ar').format(s.value),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    color: valueColor,
                    fontFeatures: const [ui.FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            ),
          ),
      ],
    );
  }
}
