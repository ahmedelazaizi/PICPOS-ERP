// رسمُ الأعمدة — اللبنةُ السادسةُ في `picpos_shell`.
//
// المصدر: كتلةُ `view.chart` في «PicPos Reports.dc.html» (سطور ٣١٢–٣٤٢):
// بطاقةٌ برأسٍ فيه شريطُ لونٍ جانبيٌّ وعنوانٌ ووصفٌ ومفتاحُ ألوان، وجسمٌ
// أعمدتُه تقف على خطٍّ واحدٍ بارتفاعٍ نسبيّ.
//
// ⚠️ **الارتفاعُ نسبةٌ تُحسَب لا تُكتَب.** التصميمُ يكتب `pct` لكلّ عمودٍ
// يدويّاً لأنّه صورةٌ ثابتة. وهنا القيمُ حقيقيّةٌ فتُقسَم على أكبرِها —
// ونسبةٌ مكتوبةٌ بجانب قيمةٍ محسوبةٍ تنحرف عنها بأوّل يومِ بيع.
//
// ⚠️ **ولا قسمةَ على صفر.** كلُّ القيم أصفاراً (يومٌ بلا بيع، فترةٌ فارغة)
// حالةٌ واقعيّةٌ لا استثنائيّة: تُرسم الأعمدةُ عند الحدّ الأدنى ويبقى
// المحورُ مقروءاً بدل `NaN` تُسقط الإطار.
//
// ⚠️ **والارتفاعُ محدودٌ بالبناء** (`SizedBox` لا `Expanded`): الرسمُ يقع
// داخلَ `Column` في جسم الشاشة، و`Column` يمنح أبناءه ارتفاعاً غيرَ محدود
// فأيُّ `FractionallySizedBox` داخله ينهار (درسُ `bodyFill`).
import 'package:flutter/material.dart';

import 'picpos_surface.dart';

/// عمودٌ واحدٌ في الرسم — بياناتٌ خالصة.
///
/// [value] هو الرقمُ الحقيقيُّ الذي يُقاس عليه الارتفاع، و[display] نصُّه
/// كما يُقرأ فوقَ العمود (مُنسَّقاً بالعملة أو بالنسبة). فصلُهما مقصود:
/// القياسُ على النصّ يجعل «١٢٫٥ ألف» أطولَ من «٩٩٠٠».
class PicPosChartBar {
  const PicPosChartBar({
    required this.label,
    required this.value,
    required this.display,
    this.secondValue,
  });

  final String label;
  final double value;
  final String display;

  /// قيمةُ سلسلةٍ ثانيةٍ اختياريّةٍ تقف بجانب الأولى في نفس العمود.
  final double? secondValue;
}

/// مفتاحُ ألوانِ الرسم — سلسلةٌ واحدةٌ أو اثنتان.
class PicPosChartSeries {
  const PicPosChartSeries({required this.label, required this.color});

  final String label;
  final Color color;
}

/// رسمُ أعمدةٍ ببطاقةٍ ورأسٍ ومفتاح.
class PicPosReportChart extends StatelessWidget {
  const PicPosReportChart({
    super.key,
    required this.title,
    required this.bars,
    required this.series,
    this.subtitle = '',
    this.height = 212,
    this.emptyHint = 'لا بيانات في هذه الفترة',
  });

  final String title;
  final String subtitle;
  final List<PicPosChartBar> bars;

  /// سلسلةٌ أو سلسلتان. الأولى تلوّن العمودَ الأساسيَّ والثانيةُ المرافق.
  final List<PicPosChartSeries> series;

  /// ارتفاعُ منطقة الأعمدة وحدَها — دون الرأس.
  final double height;

  final String emptyHint;

  @override
  Widget build(BuildContext context) {
    final hairline = context.picposHairline;
    return Container(
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border.all(color: hairline),
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _header(context, hairline),
          SizedBox(
            height: height,
            child: bars.isEmpty
                ? Center(
                    child: Text(
                      emptyHint,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: context.picposMuted,
                      ),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                    child: _bars(context),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, Color hairline) {
    final primary =
        series.isNotEmpty ? series.first.color : context.picposBrandInk;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: hairline)),
      ),
      child: Row(
        children: [
          Container(
            width: 3.5,
            height: 16,
            decoration: BoxDecoration(
              color: primary,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: context.picposText,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: context.picposMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // المفتاحُ يلتفّ عند الضيق بدل أن يدفع العنوانَ خارجَ البطاقة.
          if (series.isNotEmpty) ...[
            const SizedBox(width: 12),
            Flexible(
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 14,
                runSpacing: 4,
                children: [
                  for (final s in series)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: s.color,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          s.label,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: context.picposText,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bars(BuildContext context) {
    // القياسُ على أكبرِ قيمةٍ في **السلسلتين معاً** — لو قِيست كلُّ سلسلةٍ
    // على أكبرِها وحدَها لبدا عمودٌ صغيرٌ مساوياً لعمودٍ كبير.
    var peak = 0.0;
    for (final b in bars) {
      final v = b.value.abs();
      if (v > peak) peak = v;
      final s = b.secondValue?.abs();
      if (s != null && s > peak) peak = s;
    }
    final hasPeak = peak > 0;
    final firstColor =
        series.isNotEmpty ? series.first.color : context.picposBrandInk;
    final secondColor = series.length > 1 ? series[1].color : firstColor;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < bars.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: _Bar(
              bar: bars[i],
              // بلا ذروةٍ تبقى الأعمدةُ عند الحدّ الأدنى ولا تُقسَم على صفر.
              fraction: hasPeak ? (bars[i].value.abs() / peak) : 0,
              secondFraction: hasPeak && bars[i].secondValue != null
                  ? (bars[i].secondValue!.abs() / peak)
                  : null,
              firstColor: firstColor,
              secondColor: secondColor,
            ),
          ),
        ],
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.bar,
    required this.fraction,
    required this.secondFraction,
    required this.firstColor,
    required this.secondColor,
  });

  final PicPosChartBar bar;
  final double fraction;
  final double? secondFraction;
  final Color firstColor;
  final Color secondColor;

  /// أدنى ارتفاعٍ مرئيّ — عمودٌ بصفرٍ يبقى خطّاً رفيعاً يُقرأ، لا فراغاً
  /// يوهم بأنّ الفترةَ لا عمودَ لها أصلاً.
  static const double _minFraction = 0.02;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          bar.display,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: context.picposText,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: _ChartColumn(
                  fraction: fraction.clamp(_minFraction, 1.0),
                  color: firstColor,
                ),
              ),
              if (secondFraction != null) ...[
                const SizedBox(width: 3),
                Flexible(
                  child: _ChartColumn(
                    fraction: secondFraction!.clamp(_minFraction, 1.0),
                    color: secondColor,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          bar.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: context.picposMuted,
          ),
        ),
      ],
    );
  }
}

class _ChartColumn extends StatelessWidget {
  const _ChartColumn({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 26),
      child: FractionallySizedBox(
        heightFactor: fraction,
        alignment: Alignment.bottomCenter,
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(6),
              topRight: Radius.circular(6),
              bottomLeft: Radius.circular(2),
              bottomRight: Radius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}
