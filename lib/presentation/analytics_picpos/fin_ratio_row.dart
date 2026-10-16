// صفُّ نسبةٍ ماليّة: الاسمُ، والقيمةُ بوحدتها، وقيمةُ الفترة السابقة، وشارةُ
// الحالة، وتفصيلٌ قابلٌ للفتح بالمعادلة والتفسير. ودجتُ عرضٍ خالص.
//
// ⚠️ القيمةُ المجهولة «—» (لا صفر). والحالةُ والتفسيرُ والمعادلةُ كلُّها من
//    المحرّك كما هي — هذا الملفُّ لا يضيف عتبةً ولا قاعدة.
import 'package:flutter/material.dart';

import '../../core/design_system/spacing.dart';
import '../../core/design_system/typography.dart';
import '../../core/i18n/tr.dart';
import '../../domain/analytics/ratio_engine.dart';
import '../picpos_shell/picpos_surface.dart';
import 'fin_format.dart';

/// شارةُ حالةٍ: أيقونةٌ + نصٌّ + لون (اللونُ وحدَه لا يكفي القارئَ).
class FinStatusBadge extends StatelessWidget {
  const FinStatusBadge({super.key, required this.status});

  final RatioStatus status;

  @override
  Widget build(BuildContext context) {
    final color = finStatusColor(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(finStatusIcon(status), size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            finStatusLabel(status),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class FinancialRatioRow extends StatefulWidget {
  const FinancialRatioRow({
    super.key,
    required this.ratio,
    this.prior,
    this.initiallyExpanded = false,
  });

  final Ratio ratio;

  /// نفسُ النسبة في الفترة السابقة (`null` ⇒ «—»).
  final Ratio? prior;
  final bool initiallyExpanded;

  @override
  State<FinancialRatioRow> createState() => _FinancialRatioRowState();
}

class _FinancialRatioRowState extends State<FinancialRatioRow> {
  late bool _open = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final r = widget.ratio;
    final valueText = finRatioValue(r.value, r.unit);
    final priorText = finRatioValue(widget.prior?.value, r.unit);
    final valueStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.bold,
      color: r.value == null ? context.picposMuted : context.picposText,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final priorStyle = TextStyle(
      fontSize: 12,
      color: context.picposMuted,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final label = Text(
      r.labelText,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: context.picposText,
      ),
    );
    final value = Text(valueText, key: ValueKey('ratio-${r.key}-value'), style: valueStyle);
    final prior = Text(priorText, key: ValueKey('ratio-${r.key}-prior'), style: priorStyle);
    final badge = FinStatusBadge(status: r.status);

    return Semantics(
      container: true,
      label: '${r.labelText}: $valueText, ${finStatusLabel(r.status)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: ValueKey('ratio-${r.key}-toggle'),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.md,
                vertical: Spacing.sm,
              ),
              child: LayoutBuilder(
                builder: (context, c) {
                  final chevron = Icon(
                    _open ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: context.picposMuted,
                  );
                  if (c.maxWidth >= 560) {
                    return Row(
                      children: [
                        Expanded(flex: 4, child: label),
                        Expanded(flex: 2, child: value),
                        Expanded(flex: 2, child: prior),
                        SizedBox(
                          width: 110,
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: badge,
                          ),
                        ),
                        chevron,
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [Expanded(child: label), badge, chevron]),
                      const SizedBox(height: Spacing.xs),
                      Wrap(
                        spacing: Spacing.lg,
                        children: [
                          Text.rich(TextSpan(children: [
                            TextSpan(
                              text: '${tr('القيمة')}: ',
                              style: priorStyle,
                            ),
                            TextSpan(text: valueText, style: valueStyle),
                          ])),
                          Text(
                            '${tr('الفترة السابقة')}: $priorText',
                            style: priorStyle,
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          if (_open)
            Container(
              key: ValueKey('ratio-${r.key}-detail'),
              margin: const EdgeInsets.fromLTRB(
                Spacing.md,
                0,
                Spacing.md,
                Spacing.sm,
              ),
              padding: const EdgeInsets.all(Spacing.md),
              decoration: BoxDecoration(
                color: context.picposField,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.picposHairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('المعادلة'),
                    style: TextStyle(fontSize: 11, color: context.picposMuted),
                  ),
                  const SizedBox(height: 2),
                  // المعادلةُ نصٌّ إنجليزيٌّ من المحرّك — تُعرض يساراً دائماً.
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: SelectableText(
                        r.formula,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: AppTypography.mono,
                          color: context.picposText,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: Spacing.sm),
                  Text(
                    tr('التفسير'),
                    style: TextStyle(fontSize: 11, color: context.picposMuted),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    r.interpretationText,
                    key: ValueKey('ratio-${r.key}-interpretation'),
                    style: TextStyle(fontSize: 12.5, color: context.picposText),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
