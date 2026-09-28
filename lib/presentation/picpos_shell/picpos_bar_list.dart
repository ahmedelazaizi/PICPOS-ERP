// قائمةُ الأشرطة الأفقيّة — كتلةُ `kind:'bars'` في ملفّات التصميم.
//
// ═══ لماذا لبنةٌ سابعةٌ ولم تكفِ الستُّ ═══
//
// `PicPosReportChart` أعمدةٌ **رأسيّةٌ** تقف على خطٍّ واحد، وكتلةُ `bars`
// صفوفٌ **أفقيّةٌ** لكلٍّ منها تسميةٌ وسطرٌ خافتٌ وشريطٌ ونصٌّ داخلَه وقيمةٌ
// على اليسار. الشكلان مختلفان في التصميم نفسِه (‏كتلتان بترميزين منفصلين)،
// ولَيُّ الرسمِ الرأسيِّ إلى هذا الشكل كان سيكسره على مستهلكيه في التقارير
// السبعة — وهم أكثر.
//
// وتُستعمَل في كشفَي الحساب أربعَ مرّات: توزيعُ أعمار الدين، وجدولُ
// الالتزامات القادمة، وسلوكُ السداد، والخصمُ النقديّ.
//
// ⚠️ **النسبةُ تُحسَب لا تُكتَب** — كما في `PicPosReportChart` بالضبط.
// التصميمُ يكتب `pct:'62%'` بجانب `value:'12,040'` لأنّه صورةٌ ثابتة، وهنا
// القيمُ حقيقيّةٌ فتُقسَم على أكبرِها. ونسبةٌ مكتوبةٌ بجانب قيمةٍ محسوبةٍ
// تنحرف عنها بأوّل يومِ بيع.
//
// ⚠️ **ولا قسمةَ على صفر**: كلُّ القيم أصفاراً حالةٌ واقعيّة (طرفٌ بلا ذمّةٍ
// قائمة)، فتُرسم الأشرطةُ فارغةً ويبقى الصفُّ مقروءاً بدل `NaN`.
//
// ⚠️ **والنصُّ داخلَ الشريط يخرج منه إن ضاق.** التصميمُ عرضُه ١٩٢٠ فالفيضُ
// لا يقع عنده. وهنا الشريطُ قد يكون ٤٪ من عرضٍ ضيّق، فيُقاس اتّساعُه قبل
// الرسم: يسعُ النصَّ ⇒ داخلَه بالأبيض، وإلّا ⇒ بعدَه بلون النصّ العاديّ.
// النصُّ المقصوصُ إلى حرفٍ واحدٍ بيانةٌ ضائعةٌ لا تنسيقٌ مشدود.
import 'package:flutter/material.dart';

import 'picpos_surface.dart';

/// صفٌّ واحدٌ في القائمة — بياناتٌ خالصة.
///
/// [value] هو الرقمُ الحقيقيُّ الذي تُقاس عليه نسبةُ الشريط، و[display] نصُّه
/// كما يُقرأ على اليسار. فصلُهما مقصود: القياسُ على النصّ يجعل «١٢٫٥ ألف»
/// أطولَ من «٩٩٠٠».
class PicPosBarItem {
  const PicPosBarItem({
    required this.label,
    required this.value,
    required this.display,
    this.sub = '',
    this.caption = '',
    this.icon,
    this.tint,
  });

  final String label;

  /// السطرُ الخافتُ تحت التسمية.
  final String sub;

  /// الرقمُ المقيسُ عليه — تُقسَم عليه نسبةُ الشريط.
  final double value;

  /// نصُّ القيمة على اليسار.
  final String display;

  /// نصٌّ داخلَ الشريط — «٢٧٪ من الرصيد». يخرج خارجَه إن ضاق.
  final String caption;

  final IconData? icon;

  /// `null` ⇒ لونُ العلامة.
  final Color? tint;
}

/// بطاقةٌ برأسٍ وقائمةِ أشرطةٍ أفقيّة.
class PicPosBarList extends StatelessWidget {
  const PicPosBarList({
    super.key,
    required this.title,
    required this.items,
    this.subtitle = '',
    this.emptyHint = 'لا بيانات في هذه الفترة',
  });

  final String title;
  final String subtitle;
  final List<PicPosBarItem> items;
  final String emptyHint;

  @override
  Widget build(BuildContext context) {
    final hairline = context.picposHairline;
    return Container(
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border.all(color: hairline),
        borderRadius: BorderRadius.circular(17),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context, hairline),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 26),
              child: Center(
                child: Text(
                  emptyHint,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: context.picposMuted,
                  ),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(18, 14, 18, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const SizedBox(height: 11),
                    _row(context, items[i]),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// أكبرُ قيمةٍ موجبةٍ — مقامُ النسبة. صفرٌ ⇒ كلُّ الأشرطة فارغة.
  double get _peak {
    var peak = 0.0;
    for (final it in items) {
      final v = it.value.abs();
      if (v > peak) peak = v;
    }
    return peak;
  }

  Widget _header(BuildContext context, Color hairline) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: hairline)),
      ),
      child: Row(
        children: [
          Container(
            width: 3.5,
            height: 15,
            decoration: BoxDecoration(
              color: context.picposBrandInk,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                color: context.picposText,
              ),
            ),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: context.picposMuted,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(BuildContext context, PicPosBarItem item) {
    final tint = item.tint ?? context.picposBrandInk;
    return LayoutBuilder(
      builder: (context, c) {
        final total = c.maxWidth.isFinite ? c.maxWidth : 520.0;
        // التصميمُ يثبّت ١٧٠ و١١٠ على عرضِ ١٩٢٠. وعلى شاشةٍ ضيّقةٍ يبتلعان
        // مسارَ الشريط كلَّه، فيصير القياسُ البصريُّ بلا معنى.
        final leftW = _clamp(total * 0.34, 96, 170);
        final valueW = _clamp(total * 0.2, 62, 110);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(width: leftW, child: _label(context, item, tint)),
            const SizedBox(width: 14),
            Expanded(child: _bar(context, item, tint)),
            const SizedBox(width: 14),
            SizedBox(
              width: valueW,
              child: Text(
                item.display,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: context.picposText,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _label(BuildContext context, PicPosBarItem item, Color tint) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (item.icon != null) ...[
          Icon(item.icon, size: 15, color: tint),
          const SizedBox(width: 9),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: context.picposText,
                ),
              ),
              if (item.sub.isNotEmpty)
                Text(
                  item.sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: context.picposMuted,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bar(BuildContext context, PicPosBarItem item, Color tint) {
    final peak = _peak;
    final fraction = peak <= 0 ? 0.0 : _clamp(item.value.abs() / peak, 0, 1);
    return LayoutBuilder(
      builder: (context, c) {
        final track = c.maxWidth.isFinite ? c.maxWidth : 0.0;
        final fill = track * fraction;
        // تقديرُ اتّساع النصّ قبل الرسم — ١١px بوزنٍ ثقيلٍ ≈ ٦٫٥px للحرف،
        // زائدَ حشوَي ٩. والتقديرُ يميل إلى التشدّد عمداً: نصٌّ يخرج قليلاً
        // أهونُ من نصٍّ يُقصّ داخلَ الشريط.
        final needed = item.caption.isEmpty
            ? 0.0
            : item.caption.length * 6.5 + 18;
        final inside = item.caption.isNotEmpty && fill >= needed;
        return SizedBox(
          height: 24,
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.picposField,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Container(
                  width: fill,
                  height: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  alignment: AlignmentDirectional.centerStart,
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: inside
                      ? Text(
                          item.caption,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          softWrap: false,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            // أبيضُ فوق أرضيّةٍ مصبوغة — مقدّمةٌ لا خلفيّة،
                            // فلا يتبع سمةَ النهار/الليل.
                            color: Colors.white,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
              if (item.caption.isNotEmpty && !inside)
                Positioned.directional(
                  textDirection: Directionality.of(context),
                  start: fill + 8,
                  top: 0,
                  bottom: 0,
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      item.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: context.picposText,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  static double _clamp(double v, double lo, double hi) =>
      v < lo ? lo : (v > hi ? hi : v);
}
