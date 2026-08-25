// شريطُ مرشِّحاتٍ عامٌّ على هويّة PicPos — الغلافُ وحدَه.
//
// المصدر: `PicPos Reports.dc.html` — شريطُ شاشة التقرير: أرضيّةُ البطاقة،
// حدٌّ سفليٌّ شعريّ، حشوٌ ‎26×12‎، وفاصلٌ ١٠ بين عناصره.
//
// ⚠️ **لماذا غلافٌ مستقلٌّ عن [PicPosReportFilterBar]**: ذاك مبنيٌّ حول مدىً
// زمنيٍّ وفتراتٍ جاهزة، وكثيرٌ من التقارير مرشِّحُها **تاريخٌ واحد** أو قائمةُ
// اختيار. فالغلافُ هنا واحدٌ للاثنين، فلا يفترق شريطُ تقريرٍ عن آخر بحدٍّ أو
// حشوٍ لأنّ نوعَ مرشِّحه اختلف.
import 'package:flutter/material.dart';

import 'picpos_surface.dart';

/// شريطٌ يحمل مرشِّحاتِ التقرير تحت الترويسة.
class PicPosFilterStrip extends StatelessWidget {
  const PicPosFilterStrip({
    super.key,
    required this.children,
    this.padding,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding ??
          const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border(bottom: BorderSide(color: context.picposHairline)),
      ),
      // ⚠️ `Wrap` لا `Row`: شاشةٌ بسبعة مرشِّحاتٍ تفيض حتى على ١٩٢٠ — وهو
      //    العطبُ الذي بُني له `ReportFilterBar` أصلاً (‏Spec 076).
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      ),
    );
  }
}

/// مرشِّحٌ واحدٌ في الشريط — أيقونةٌ وعنوانٌ، ويُنقَر ليُفتَح منتقيه.
///
/// القياساتُ من التصميم: ارتفاعٌ ٤٠، استدارةٌ ١١، أرضيّةُ الحقل وحدُّ الشعرة،
/// وأيقونةٌ ١٥ بحبر العلامة، ونصٌّ ١٢.٥ وزنُه ٧٠٠.
class PicPosFilterPill extends StatelessWidget {
  const PicPosFilterPill({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.tone,
    this.tabular = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  /// لونُ المرشِّح حين يكون **مفعَّلاً** — التصميمُ يميّز المرشِّحَ الذي يضيّق
  /// النتيجةَ بحدِّ العلامة وأرضيّةِ الغسل. `null` ⇒ الحيادُ.
  final Color? tone;

  /// أرقامٌ ثابتةُ العرض — للتواريخ كي لا يرقص عرضُ الزرّ مع تبدّلها.
  final bool tabular;

  @override
  Widget build(BuildContext context) {
    final on = tone != null;
    final fg = on ? tone! : context.picposText;
    final pill = Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: on ? tone!.withValues(alpha: 0.08) : context.picposField,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: on ? tone! : context.picposHairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: on ? tone! : context.picposBrandInk),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: fg,
              fontFeatures:
                  tabular ? const [FontFeature.tabularFigures()] : null,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return pill;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: pill,
      ),
    );
  }
}
