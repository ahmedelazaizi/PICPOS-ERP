// لوحةُ مخاطر مبسّطة — مشتقّةٌ من **حالات النسب وحدَها** (جيد/تحذير/خطر)
// كما صنّفها المحرّك بعتباته. لا قاعدةَ جديدة ولا رقمَ مُختلَق:
//   • عدّادٌ لكلّ مجموعةٍ لما هو «خطر» ولما هو «تحذير».
//   • قائمةٌ مرتّبة: الخطرُ أوّلاً ثمّ التحذير، وداخل كلّ درجةٍ بترتيب المحرّك.
//   • ما حالتُه «غير محدد» يُعدّ ولا يُصنَّف (لا يُحسب سليماً ولا خطراً).
import 'package:flutter/material.dart';

import '../../core/design_system/spacing.dart';
import '../../core/i18n/tr.dart';
import '../../domain/analytics/ratio_engine.dart';
import '../picpos_shell/picpos_surface.dart';
import 'fin_format.dart';
import 'fin_ratio_row.dart';

/// عدّادُ حالات مجموعةٍ واحدة.
class FinGroupRiskCount {
  const FinGroupRiskCount(this.group, this.bad, this.warning);
  final RatioGroup group;
  final int bad;
  final int warning;
}

/// ملخّصُ المخاطر المشتقّ من [ratios].
class FinRiskSummary {
  const FinRiskSummary({
    required this.perGroup,
    required this.worst,
    required this.unknownCount,
    required this.totalCount,
  });

  /// مجموعةٌ لكلّ [RatioGroup] لها نسبٌ، بترتيب المحرّك.
  final List<FinGroupRiskCount> perGroup;

  /// الخطرُ ثمّ التحذير — مرتّبة ثابتاً.
  final List<Ratio> worst;
  final int unknownCount;
  final int totalCount;

  int get badCount => worst.where((r) => r.status == RatioStatus.bad).length;
  int get warningCount => worst.length - badCount;
}

FinRiskSummary buildFinRiskSummary(List<Ratio> ratios) {
  final groups = <RatioGroup>[];
  for (final r in ratios) {
    if (!groups.contains(r.group)) groups.add(r.group);
  }
  final perGroup = [
    for (final g in groups)
      FinGroupRiskCount(
        g,
        ratios.where((r) => r.group == g && r.status == RatioStatus.bad).length,
        ratios
            .where((r) => r.group == g && r.status == RatioStatus.warning)
            .length,
      ),
  ];
  final bad = ratios.where((r) => r.status == RatioStatus.bad);
  final warn = ratios.where((r) => r.status == RatioStatus.warning);
  return FinRiskSummary(
    perGroup: perGroup,
    worst: [...bad, ...warn],
    unknownCount: ratios.where((r) => r.status == RatioStatus.unknown).length,
    totalCount: ratios.length,
  );
}

class FinancialRiskPanel extends StatelessWidget {
  const FinancialRiskPanel({super.key, required this.ratios});

  final List<Ratio> ratios;

  @override
  Widget build(BuildContext context) {
    final s = buildFinRiskSummary(ratios);
    final muted = TextStyle(fontSize: 11.5, color: context.picposMuted);
    final allUnknown = s.totalCount == 0 || s.unknownCount == s.totalCount;

    return Container(
      key: const ValueKey('risk-panel'),
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border.all(color: context.picposHairline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(Icons.shield_outlined, size: 17, color: context.picposBrandInk),
            const SizedBox(width: Spacing.sm),
            Text(
              tr('ملخص المخاطر'),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: context.picposText,
              ),
            ),
          ]),
          const SizedBox(height: 2),
          Text(
            tr('مشتق من حالات النسب فقط وفق حدود المحرك'),
            style: muted,
          ),
          const SizedBox(height: Spacing.md),
          if (allUnknown)
            Text(
              tr('لا توجد بيانات كافية لتقييم النسب'),
              key: const ValueKey('risk-no-data'),
              style: muted,
            )
          else ...[
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              children: [
                for (final g in s.perGroup) _GroupChip(count: g),
              ],
            ),
            const SizedBox(height: Spacing.md),
            if (s.worst.isEmpty)
              Text(
                tr('لا توجد نسب في حالة تحذير أو خطر'),
                key: const ValueKey('risk-none'),
                style: TextStyle(
                  fontSize: 12.5,
                  color: finStatusColor(context, RatioStatus.good),
                ),
              )
            else ...[
              Text(
                tr('أسوأ النسب'),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: context.picposText,
                ),
              ),
              const SizedBox(height: Spacing.xs),
              for (var i = 0; i < s.worst.length; i++)
                _WorstItem(rank: i + 1, ratio: s.worst[i]),
            ],
            if (s.unknownCount > 0) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                tr('{p0} نسب غير محتسبة', {'p0': s.unknownCount}),
                key: const ValueKey('risk-unknown'),
                style: muted,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _GroupChip extends StatelessWidget {
  const _GroupChip({required this.count});
  final FinGroupRiskCount count;

  @override
  Widget build(BuildContext context) {
    final g = count.group;
    return Container(
      key: ValueKey('risk-group-${g.name}'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: context.picposField,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.picposHairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            finGroupLabel(g),
            style: TextStyle(fontSize: 12, color: context.picposText),
          ),
          const SizedBox(width: Spacing.sm),
          _Count(
            n: count.bad,
            status: RatioStatus.bad,
            keyName: 'risk-group-${g.name}-bad',
          ),
          const SizedBox(width: Spacing.xs),
          _Count(
            n: count.warning,
            status: RatioStatus.warning,
            keyName: 'risk-group-${g.name}-warning',
          ),
        ],
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.n, required this.status, required this.keyName});
  final int n;
  final RatioStatus status;
  final String keyName;

  @override
  Widget build(BuildContext context) {
    // الصفرُ يُكتب خافتاً ولا يُلوَّن — لا إنذارَ بلا حالة.
    final color = n == 0
        ? context.picposMuted
        : finStatusColor(context, status);
    return Text(
      '$n ${finStatusLabel(status)}',
      key: ValueKey(keyName),
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: n == 0 ? FontWeight.normal : FontWeight.bold,
        color: color,
      ),
    );
  }
}

class _WorstItem extends StatelessWidget {
  const _WorstItem({required this.rank, required this.ratio});
  final int rank;
  final Ratio ratio;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: ValueKey('risk-item-$rank-${ratio.key}'),
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '$rank',
              style: TextStyle(fontSize: 12, color: context.picposMuted),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${ratio.labelText} · ${finRatioValue(ratio.value, ratio.unit)}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: context.picposText,
                  ),
                ),
                Text(
                  ratio.interpretationText,
                  style: TextStyle(fontSize: 11.5, color: context.picposMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: Spacing.sm),
          FinStatusBadge(status: ratio.status),
        ],
      ),
    );
  }
}
