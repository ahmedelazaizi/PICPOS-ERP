import 'package:flutter/material.dart';

import '../../../core/design_system/spacing.dart';
import '../../../domain/models/table_status.dart';
import '../../picpos_shell/picpos_stat_tile.dart';
import '../../screens/tables/widgets/table_status_info.dart';

/// عدُّ الطاولات لكلِّ حالة — **بمدخلٍ لكلِّ حالةٍ ولو كان صفراً**.
///
/// إخفاءُ الصفر يجعل العمودَ يقفز طولاً كلّما تبدّلت الطاولات، ويخفي معلومةً
/// حقيقيّة: «لا طاولةَ خارجَ الخدمة» خبرٌ لا فراغ.
Map<String, int> countByStatus(List<String> statuses) {
  final counts = {for (final s in TableStatus.all) s: 0};
  for (final s in statuses) {
    if (counts.containsKey(s)) counts[s] = counts[s]! + 1;
  }
  return counts;
}

class TablesStatusRail extends StatelessWidget {
  const TablesStatusRail({
    super.key,
    required this.counts,
    required this.selected,
    required this.onSelect,
  });

  final Map<String, int> counts;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final status in TableStatus.all)
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.sm),
            child: InkWell(
              onTap: () => onSelect(selected == status ? null : status),
              child: PicPosStatTile(
                label: tableStatusLabel(status),
                value: '${counts[status] ?? 0}',
                accent: tableStatusColor(status),
              ),
            ),
          ),
      ],
    );
  }
}
