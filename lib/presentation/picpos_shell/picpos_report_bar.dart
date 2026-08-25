// شريطُ مرشِّحات التقارير على هويّة PicPos.
//
// المصدر: `PicPos Reports.dc.html` — شريطُ شاشة التقرير (‏`isReport`):
//
//     ┌──────────────────────────────────────────────────────────────┐
//     │ [اليوم|أمس|الشهر|السنة]   📅 المدى   ▾ فرع   ▾ مخزن  …        │
//     └──────────────────────────────────────────────────────────────┘
//
// ⚠️ **لماذا ملفٌّ واحدٌ يستحقّ العناء**: ثلاثَ عشرةَ شاشةَ تقريرٍ من ثماني
// عشرةَ تتشارك `ReportFilterBar` واحدة. فتنسيقُها هنا مرّةً يُلبس الثلاثَ عشرةَ
// الهويّةَ دفعةً — وتنسيقُ كلٍّ على حدةٍ كان سيعني ثلاثَ عشرةَ نسخةً تنحرف.
//
// ⚠️ **والقياساتُ من التصميم لا مخترَعة**: الشريطُ حشوُه ‎26×12‎ بأرضيّةِ
// البطاقة وحدٍّ سفليٍّ شعريّ؛ وحاويةُ الفترات أرضيّتُها `--field` باستدارة ١١
// وحشوٍ ٤ وفاصلٍ ٥؛ والفترةُ ارتفاعُها ٣٢ باستدارة ٨ وحشوٍ أفقيٍّ ١٣ وخطٍّ ١٢
// (‏وزنُه ٨٠٠ للمنتقاة و٧٠٠ لغيرها)؛ وزرُّ المدى ارتفاعُه ٤٠ باستدارة ١١.
//
// ⚠️ **ولا يحسب مدىً ولا يقرّر أيُّ فترةٍ منتقاة**: يقرأ ذلك من
// `DateRangeFilter.presets()` و`isPresetSelected` — لأنّ التقريرَ كلَّه يُحسَب
// من هذه الحدود، فاختلافُ «الشهر» بين الشريطَين أرقامٌ خاطئةٌ لا اختلافُ شكل.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../widgets/report_components.dart' show DateRangeFilter;
import 'picpos_surface.dart';

class PicPosReportFilterBar extends StatelessWidget {
  const PicPosReportFilterBar({
    super.key,
    required this.selectedRange,
    required this.onRangeChanged,
    required this.trailing,
    this.padding,
  });

  final DateTimeRange selectedRange;
  final void Function(DateTime start, DateTime end) onRangeChanged;

  /// المرشِّحاتُ المتغيّرةُ التي تعطيها الشاشة — قوائمُ منسدلةٌ في الغالب.
  ///
  /// ⚠️ **تُعرَض كما هي ولا تُحوَّل إلى رقائقَ كالتصميم**: التصميمُ يرسم
  /// المرشِّحاتِ النشطةَ رقائقَ لأنّه يعرف كلَّ مرشِّحٍ بياناً (أيقونةً وعنواناً
  /// وقابليّةَ مسح). وهنا هي **ودجتاتٌ عامّةٌ** تبنيها كلُّ شاشةٍ بنفسها، ولا
  /// سبيلَ لقراءة عنوانها. وتحويلُها يقتضي أن تُعلن كلُّ شاشةٍ مرشِّحاتِها
  /// بياناً — وهي ثلاثَ عشرةَ شاشةً، فبندٌ مفتوحٌ لا تفصيلُ تنسيق.
  final List<Widget> trailing;

  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final ps = DateRangeFilter.presets();
    return Container(
      width: double.infinity,
      padding: padding ??
          const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border(bottom: BorderSide(color: context.picposHairline)),
      ),
      // ⚠️ `Wrap` لا `Row`: هذا الشريطُ وُجد أصلاً لأنّ صفّاً واحداً بسبعة
      //    مرشِّحاتٍ كان يفيض حتى على ١٩٢٠ (‏Spec 076). والتصميمُ صفٌّ لأنّه
      //    يرسم ثلاثةَ مرشِّحاتٍ لا سبعة.
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _presetGroup(context, ps),
          _rangePill(context),
          ...trailing,
        ],
      ),
    );
  }

  Widget _presetGroup(
    BuildContext context,
    List<({String label, DateTimeRange range})> ps,
  ) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.picposField,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: context.picposHairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < ps.length; i++) ...[
            if (i > 0) const SizedBox(width: 5),
            _preset(context, ps[i]),
          ],
        ],
      ),
    );
  }

  Widget _preset(
    BuildContext context,
    ({String label, DateTimeRange range}) p,
  ) {
    final on = DateRangeFilter.isPresetSelected(selectedRange, p.range);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onRangeChanged(p.range.start, p.range.end),
        child: Container(
          height: 32,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            // المنتقاةُ ترتفع بأرضيّةِ البطاقة فوق أرضيّةِ الحاوية.
            color: on ? context.picposCard : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            p.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: on ? FontWeight.w800 : FontWeight.w700,
              color: on ? context.picposBrandInk : context.picposMuted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _rangePill(BuildContext context) {
    final fmt = DateFormat('yyyy/MM/dd');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: () => DateRangeFilter.pickCustomRange(
          context,
          selectedRange,
          onRangeChanged,
        ),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: context.picposField,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: context.picposHairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                PhosphorIconsBold.calendarBlank,
                size: 15,
                color: context.picposBrandInk,
              ),
              const SizedBox(width: 8),
              Text(
                // فاصلُ التصميم سهمٌ لا شرطة — أوضحُ في سياقٍ من اليمين لليسار.
                '${fmt.format(selectedRange.start)} ← '
                '${fmt.format(selectedRange.end)}',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: context.picposText,
                  // أرقامٌ ثابتةُ العرض كي لا يرقص الزرُّ مع تبدّل التاريخ.
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
