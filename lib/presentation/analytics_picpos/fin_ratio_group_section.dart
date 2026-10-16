// قسمُ مجموعةٍ من النسب (السيولة، الربحية…): ترويسةٌ وصفوفٌ قابلةٌ للفتح.
import 'package:flutter/material.dart';

import '../../core/design_system/spacing.dart';
import '../../core/i18n/tr.dart';
import '../../domain/analytics/ratio_engine.dart';
import '../picpos_shell/picpos_surface.dart';
import 'fin_format.dart';
import 'fin_ratio_row.dart';

class FinancialRatioGroupSection extends StatelessWidget {
  const FinancialRatioGroupSection({
    super.key,
    required this.group,
    required this.ratios,
    required this.priorByKey,
  });

  final RatioGroup group;

  /// نسبُ هذه المجموعة وحدَها بترتيب المحرّك.
  final List<Ratio> ratios;

  /// نسبُ الفترة السابقة بمفتاح النسبة.
  final Map<String, Ratio> priorByKey;

  @override
  Widget build(BuildContext context) {
    final headStyle = TextStyle(fontSize: 11, color: context.picposMuted);
    return Container(
      key: ValueKey('ratio-group-${group.name}'),
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border.all(color: context.picposHairline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Row(
              children: [
                Icon(finGroupIcon(group), size: 17, color: context.picposBrandInk),
                const SizedBox(width: Spacing.sm),
                Text(
                  finGroupLabel(group),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: context.picposText,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: context.picposHairline),
          LayoutBuilder(
            builder: (context, c) => c.maxWidth < 560
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Spacing.md,
                      Spacing.sm,
                      Spacing.md + 18,
                      Spacing.xs,
                    ),
                    child: Row(children: [
                      Expanded(flex: 4, child: Text(tr('النسبة'), style: headStyle)),
                      Expanded(flex: 2, child: Text(tr('القيمة'), style: headStyle)),
                      Expanded(
                        flex: 2,
                        child: Text(tr('الفترة السابقة'), style: headStyle),
                      ),
                      SizedBox(
                        width: 110,
                        child: Text(tr('الحالة'), style: headStyle),
                      ),
                    ]),
                  ),
          ),
          for (var i = 0; i < ratios.length; i++) ...[
            if (i > 0) Divider(height: 1, color: context.picposHairline),
            FinancialRatioRow(
              ratio: ratios[i],
              prior: priorByKey[ratios[i].key],
            ),
          ],
          const SizedBox(height: Spacing.xs),
        ],
      ),
    );
  }
}
